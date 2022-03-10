// -----------------------------------------------------------------------------
// Coordinates image data between the program and file systems.
// -----------------------------------------------------------------------------

import CLibTIFF
import Geometry

public enum TIFFError : Error {
    /// Stores the reference to the tag.
    case SetField(Int32)

    /// Stores the reference to the tag.
    case GetField(Int32)

    case Open
    case Flush
    case WriteScanline
    case ReadScanline
    case InternalInconsistancy
    case InvalidReference
    case IncorrectChannelSize(UInt32)
}

public class TIFFImage<Channel> : ImageProtocol {
    /// Stores a reference to the image handle (The contents is of type 
    /// `TIFF*` in C)
    fileprivate var tiffref: OpaquePointer?
    /// Stores the full path of the file.
    public private(set) var path: String?
    /// Accesses the attributes of the TIFF file. 
    public var attributes: TIFFAttributes
    /// The size of the image (in pixels). If you want to resize the image, then
    /// you should create a new one.
    public var size: Size {
        get {
            return Size(width: Int(attributes.width), height: Int(attributes.height))
        }
    }

    /// Stores the contents of the image. It must be in the form:
    ///
    ///     When y=0, x1, x2, x3, x4, x5, ..., xN
    ///     When y=1, x1, x2, x3, x4, x5, ..., xN
    ///     When y=., ..., ...,           ..., xN
    ///     When y=K, x1, x2, x3, x4, x5, ..., xN
    ///
    public private(set) var buffer: UnsafeMutablePointer<Channel> 

    public var hasAlpha: Bool {
        // TODO: This is lazy and probably incorrect.
        return attributes.samplesPerPixel == 4
    }
    public var channelCount: Int {
        return Int(attributes.samplesPerPixel)
    }

    public private(set) var mode: String?

    public init(readingAt path: String) throws {
        self.mode = "r"
        self.path = path
        guard let ptr = TIFFOpen(path, self.mode) else {
            throw TIFFError.Open
        }
        self.tiffref = ptr
        self.attributes = try TIFFAttributes(tiffref: ptr)
        let k = MemoryLayout<Channel>.size
        guard UInt32(8 * k) == attributes.bitsPerSample else {
            throw TIFFError.IncorrectChannelSize(attributes.bitsPerSample)
        }
        let size = Int(attributes.width) * Int(attributes.height)
        let byteCount = size * Int(attributes.bitsPerSample)
        self.buffer = UnsafeMutablePointer<Channel>.allocate(capacity: byteCount)
        try read()
    }

    public init(writingAt path: String, size: Size, hasAlpha: Bool) throws {
        self.mode = "w"
        self.path = path
        guard let ptr = TIFFOpen(path, mode) else {
            throw TIFFError.Open
        }
        self.tiffref = ptr
        let extraSamples: [UInt16]
        if hasAlpha {
            extraSamples = [UInt16(EXTRASAMPLE_ASSOCALPHA)]
        } else {
            extraSamples = []
        } 
        let bps = UInt32(MemoryLayout<Channel>.stride * 8)
        self.attributes = try TIFFAttributes(writingAt: ptr,
                                         size: size,
                                         bitsPerSample: bps,
                                         samplesPerPixel: 3 + (hasAlpha ? 1 : 0),
                                         rowsPerStrip: 1,
                                         photometric: UInt32(PHOTOMETRIC_RGB),
                                         planarconfig: UInt32(PLANARCONFIG_CONTIG),
                                         orientation: UInt32(ORIENTATION_TOPLEFT),
                                         extraSamples: extraSamples)
        let pixelCount = size.width * size.height
        let byteCount = pixelCount * Int(attributes.bitsPerSample)
        
        self.buffer = UnsafeMutablePointer<Channel>.allocate(capacity: byteCount)
    }

    public init(size: Size, hasAlpha: Bool = false) {
        self.mode = nil
        self.path = nil
        self.tiffref = nil
        let extraSamples: [UInt16]
        if hasAlpha {
            extraSamples = [UInt16(EXTRASAMPLE_ASSOCALPHA)]
        } else {
            extraSamples = []
        }
        let bps = UInt32(MemoryLayout<Channel>.stride * 8)
        self.attributes = try! TIFFAttributes(size: size,
                                     bitsPerSample: bps,
                                     samplesPerPixel: hasAlpha ? 4 : 3,
                                     rowsPerStrip: 1,
                                     photometric: UInt32(PHOTOMETRIC_RGB),
                                     planarconfig: UInt32(PLANARCONFIG_CONTIG),
                                     orientation: UInt32(ORIENTATION_TOPLEFT),
                                     extraSamples: extraSamples)
        let pixelCount = size.width * size.height
        let byteCount = pixelCount * Int(attributes.bitsPerSample)
        self.buffer = UnsafeMutablePointer<Channel>.allocate(capacity: byteCount)
    }


    public func open(at path: String, mode: String) throws {
        self.mode = mode
        self.path = path
        guard let ptr = TIFFOpen(path, mode) else {
            throw TIFFError.Open
        }
        self.tiffref = ptr
        self.attributes = try TIFFAttributes(writingAt: ptr, coping: self.attributes)
        guard UInt32(8 * MemoryLayout<Channel>.stride) == attributes.bitsPerSample else {
            throw TIFFError.IncorrectChannelSize(attributes.bitsPerSample)
        }
    }

    deinit {
        self.buffer.deallocate()
        self.close()
    }

    public func close() {
        if let ref = tiffref {
            TIFFFlush(ref)
            TIFFClose(ref)
            tiffref = nil
            attributes.tiffref = nil
        }
    }

    public func flush() throws {
        if let ref = tiffref {
            guard TIFFFlush(ref) == 1 else {
                throw TIFFError.Flush
            }
        } else {
            throw TIFFError.InvalidReference
        }
    }
}

extension TIFFImage {
    public func write() throws {
        try write(verticalRange: 0..<size.height)
        try flush()
    }

    public func write(verticalRange r: Range<Int>) throws {
        guard let ref = tiffref else {
            throw TIFFError.InvalidReference
        }

        let scount = Int(attributes.samplesPerPixel)
        let expectedBytesInAScanline = MemoryLayout<Channel>.stride * scount * size.width
        for y in r.lowerBound..<r.upperBound {
            guard expectedBytesInAScanline == TIFFScanlineSize(ref) else {
                throw TIFFError.InternalInconsistancy
            }
            let line = buffer.advanced(by: y * size.width * scount)
            guard TIFFWriteScanline(ref, line, UInt32(y), 0) == 1 else {
                throw TIFFError.WriteScanline
            }
        }
    }

    public func read() throws {
        try read(verticalRange: 0..<size.height)
    }

    public func read(verticalRange r: Range<Int>) throws {
        guard let ref = tiffref else {
            throw TIFFError.InvalidReference
        }
        let scount = Int(attributes.samplesPerPixel)
        let expectedBytesInAScanline = MemoryLayout<Channel>.stride * scount * size.width
        for y in r.lowerBound..<r.upperBound {
            guard expectedBytesInAScanline == TIFFScanlineSize(ref) else {
                throw TIFFError.InternalInconsistancy
            }
            let line = buffer.advanced(by: y * size.width * scount)
            guard TIFFReadScanline(ref, line, UInt32(y), 0) == 1 else {
                throw TIFFError.ReadScanline
            }
        }
    }
}

public struct TIFFAttributes {
    var tiffref: OpaquePointer?

    public private(set) var extraSamples: [UInt16]  = [] {
        didSet {
            _ = try? write(samples: extraSamples)
        }
    }
    public private(set) var bitsPerSample   : UInt32    = 0 {
        didSet {
            _ = try? write(bitsPerSample, for: TIFFTAG_BITSPERSAMPLE)
        }
    }
    public private(set) var samplesPerPixel : UInt32    = 0 {
        didSet {
            _ = try? write(samplesPerPixel, for: TIFFTAG_SAMPLESPERPIXEL)
        }
    }
    public private(set) var rowsPerStrip    : UInt32    = 0 {
        didSet {
            _ = try? write(rowsPerStrip, for: TIFFTAG_ROWSPERSTRIP)
        }
    }
    public private(set) var photometric     : UInt32    = 0 {
        didSet {
            _ = try? write(photometric, for: TIFFTAG_PHOTOMETRIC)
        }
    }
    public private(set) var planarconfig    : UInt32    = 0 {
        didSet {
            _ = try? write(planarconfig, for: TIFFTAG_PLANARCONFIG)
        }
    }
    public private(set) var orientation     : UInt32    = 0 {
        didSet {
            _ = try? write(orientation, for: TIFFTAG_ORIENTATION)
        }
    }
    public private(set) var width           : UInt32    = 0 {
        didSet {
            _ = try? write(width, for: TIFFTAG_IMAGEWIDTH)
        }
    }
    public private(set) var height          : UInt32    = 0 {
        didSet {
            _ = try? write(height, for: TIFFTAG_IMAGELENGTH)
        }
    }

    init(tiffref: OpaquePointer) throws {
        self.tiffref    = tiffref
        bitsPerSample   = try read(tag: TIFFTAG_BITSPERSAMPLE)
        samplesPerPixel = try read(tag: TIFFTAG_SAMPLESPERPIXEL)
        rowsPerStrip    = try read(tag: TIFFTAG_ROWSPERSTRIP)
        photometric     = try read(tag: TIFFTAG_PHOTOMETRIC)
        planarconfig    = try read(tag: TIFFTAG_PLANARCONFIG)
        do {
            orientation     = try read(tag: TIFFTAG_ORIENTATION)
        } catch {
            // missing orientation
        }
        width           = try read(tag: TIFFTAG_IMAGEWIDTH)
        height          = try read(tag: TIFFTAG_IMAGELENGTH)
        if let es = try? readSamples() {
            extraSamples = es
        } else {
            extraSamples = []
        }
    }

    init(writingAt tiffref: OpaquePointer? = nil, 
         size: Size, 
         bitsPerSample: UInt32, 
         samplesPerPixel: UInt32, 
         rowsPerStrip: UInt32, 
         photometric: UInt32, 
         planarconfig: UInt32,
         orientation: UInt32, 
         extraSamples: [UInt16]) throws {

        self.tiffref = tiffref
        self.bitsPerSample      = bitsPerSample
        self.samplesPerPixel    = samplesPerPixel
        self.rowsPerStrip       = rowsPerStrip
        self.photometric        = photometric
        self.planarconfig       = planarconfig
        self.orientation        = orientation
        self.width              = UInt32(size.width)
        self.height             = UInt32(size.height)
        self.extraSamples       = extraSamples

        if tiffref == nil {
            _ = try? write(bitsPerSample, for: TIFFTAG_BITSPERSAMPLE)
            _ = try? write(samplesPerPixel, for: TIFFTAG_SAMPLESPERPIXEL)
            _ = try? write(rowsPerStrip, for: TIFFTAG_ROWSPERSTRIP)
            _ = try? write(photometric, for: TIFFTAG_PHOTOMETRIC)
            _ = try? write(planarconfig, for: TIFFTAG_PLANARCONFIG)
            _ = try? write(orientation, for: TIFFTAG_ORIENTATION)
            _ = try? write(width, for: TIFFTAG_IMAGEWIDTH)
            _ = try? write(height, for: TIFFTAG_IMAGELENGTH)
            _ = try? write(samples: extraSamples)
        } else {
            try write(bitsPerSample, for: TIFFTAG_BITSPERSAMPLE)
            try write(samplesPerPixel, for: TIFFTAG_SAMPLESPERPIXEL)
            try write(rowsPerStrip, for: TIFFTAG_ROWSPERSTRIP)
            try write(photometric, for: TIFFTAG_PHOTOMETRIC)
            try write(planarconfig, for: TIFFTAG_PLANARCONFIG)
            try write(orientation, for: TIFFTAG_ORIENTATION)
            try write(width, for: TIFFTAG_IMAGEWIDTH)
            try write(height, for: TIFFTAG_IMAGELENGTH)
            try write(samples: extraSamples)
        }
    }

    init(writingAt tiffref: OpaquePointer, coping attributes: TIFFAttributes) throws {
        self.tiffref = tiffref
        
        self.tiffref = tiffref
        self.bitsPerSample      = attributes.bitsPerSample
        self.samplesPerPixel    = attributes.samplesPerPixel
        self.rowsPerStrip       = attributes.rowsPerStrip
        self.photometric        = attributes.photometric
        self.planarconfig       = attributes.planarconfig
        self.orientation        = attributes.orientation
        self.width              = UInt32(attributes.width)
        self.height             = UInt32(attributes.height)
        self.extraSamples       = attributes.extraSamples

        _ = try? write(bitsPerSample, for: TIFFTAG_BITSPERSAMPLE)
        _ = try? write(samplesPerPixel, for: TIFFTAG_SAMPLESPERPIXEL)
        _ = try? write(rowsPerStrip, for: TIFFTAG_ROWSPERSTRIP)
        _ = try? write(photometric, for: TIFFTAG_PHOTOMETRIC)
        _ = try? write(planarconfig, for: TIFFTAG_PLANARCONFIG)
        _ = try? write(orientation, for: TIFFTAG_ORIENTATION)
        _ = try? write(width, for: TIFFTAG_IMAGEWIDTH)
        _ = try? write(height, for: TIFFTAG_IMAGELENGTH)
        _ = try? write(samples: extraSamples)
    }


    public func set(tag: Int32, with value: UInt16) throws {
        try write(value, for: tag)
    }
    public func get(tag: Int32) throws -> UInt16 {
        return try read(tag: tag)
    }

    public func set(tag: Int32, with value: UInt32) throws {
        try write(value, for: tag)
    }
    public func get(tag: Int32) throws -> UInt32 {
        return try read(tag: tag)
    }

    /// Warning: `value` must be of type UInt16, or UInt32.
    private func write(_ value: Any, for tag: Int32) throws {
        guard let ref = self.tiffref else {
            throw TIFFError.InvalidReference
        }
            
        let result: Int32
        switch value {
        case is UInt16:
            result = TIFFSetField_uint16(ref, 
                                         UInt32(bitPattern: tag), 
                                         value as! UInt16)
        case is UInt32:
            result = TIFFSetField_uint32(ref,
                                         UInt32(bitPattern: tag),
                                         value as! UInt32)
        default:
            fatalError("cannot write `value` whose type is not UInt32 or UInt16")
        }
        guard result == 1 else {
            throw TIFFError.SetField(tag)
        }
    }

    /// Warning: Only UInt16 and UInt32 types are support.
    private func read<T: Any>(tag: Int32) throws -> T {
        guard let ref = tiffref else {
            throw TIFFError.InvalidReference
        }

        let result: Int32
        switch T.self {
        case is UInt16.Type:
            var value = UInt16(0)
            result = TIFFGetField_uint16(ref,
                                         UInt32(bitPattern: tag),
                                         &value)
            guard result == 1 else {
                throw TIFFError.GetField(tag)
            }
            return value as! T
        case is UInt32.Type:
            var value = UInt32(0)
            result = TIFFGetField_uint32(ref,
                                         UInt32(bitPattern: tag),
                                         &value)
            guard result == 1 else {
                throw TIFFError.GetField(tag)
            }
            return value as! T
        default:
            fatalError("cannot read a tag whose value is \(T.self). It must be either UInt32 or UInt16.")
        }
    }

    func readSamples() throws -> [UInt16] {
        guard let ref = tiffref else {
            throw TIFFError.InvalidReference
        }
        var count: UInt16 = 4
        typealias Ptr = UnsafeMutablePointer<UInt16>
        var buff: Ptr? = Ptr.allocate(capacity: Int(count))
        let result = TIFFGetField_ExtraSample(ref,
                                              &count,
                                              &buff)
        guard result == 1 else {
            throw TIFFError.GetField(TIFFTAG_EXTRASAMPLES)
        }
        var samples = [UInt16](repeating: 0, count: Int(count))
        if let buff = buff {
            for index in 0..<Int(count) {
                samples[index] = buff[index]
            }
        } else {
            throw TIFFError.GetField(TIFFTAG_EXTRASAMPLES)
        }
        return samples 
    }

    mutating func write(samples: [UInt16]) throws {
        guard let ref = tiffref else {
            throw TIFFError.InvalidReference
        }
        var samples = samples
        let result = TIFFSetField_ExtraSample(ref,
                                              UInt16(samples.count),
                                              &samples)
        guard result == 1 else {
            throw TIFFError.SetField(TIFFTAG_EXTRASAMPLES)
        }
    }
}
