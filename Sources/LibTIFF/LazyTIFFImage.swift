
import CLibTIFF

public struct Point {
	public let x: Int
	public let y: Int

	public init(x: Int, y: Int) {
		self.x = x
		self.y = y
	}
}

public struct Area {
	public let origin: Point
	public let size: Size

	public init (origin: Point, size: Size) {
		self.origin = origin
		self.size = size
	}
}

enum LazyTIFFImageError: Error {
	case AreaOutOfBounds
	case PartialScanlineUpdatesNotPossible
	case UnsupportedType
	case NoBaseAddress
}

public class LazyTIFFImage<Channel> {
	/// Stores a reference to the image handle (The contents is of type
	/// `TIFF*` in C)
	internal var tiffref: OpaquePointer?
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

	public var hasAlpha: Bool {
		// TODO: This is lazy and probably incorrect.
		return attributes.samplesPerPixel == 4
	}
	public var channelCount: Int {
		return Int(attributes.samplesPerPixel)
	}

	public private(set) var mode: String

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
	}

	public init(writingAt path: String, size: Size, samplesPerPixel: Int, hasAlpha: Bool, useBigTIFF: Bool=false) throws {
		self.mode = "w"
		self.path = path
		let tiffmode = self.mode + (useBigTIFF ? "8" : "")
		guard let ptr = TIFFOpen(path, tiffmode) else {
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

		// obvious bodge...
		let photometric = samplesPerPixel == 1 ? PHOTOMETRIC_MINISBLACK : PHOTOMETRIC_RGB

		self.attributes = try TIFFAttributes(writingAt: ptr,
										 size: size,
										 bitsPerSample: bps,
										 samplesPerPixel: UInt32(samplesPerPixel),
										 rowsPerStrip: 1,
										 photometric: UInt32(photometric),
										 planarconfig: UInt32(PLANARCONFIG_CONTIG),
										 orientation: UInt32(ORIENTATION_TOPLEFT),
										 extraSamples: extraSamples)
		switch Channel.self {
			case is Double.Type:
				try self.attributes.set(tag: TIFFTAG_SAMPLEFORMAT, with: UInt16(SAMPLEFORMAT_IEEEFP))
			case is UInt8.Type, is UInt16.Type, is UInt32.Type, is UInt64.Type:
				try self.attributes.set(tag: TIFFTAG_SAMPLEFORMAT, with: UInt16(SAMPLEFORMAT_UINT))
			case is Int8.Type, is Int16.Type, is Int32.Type, is Int64.Type:
				try self.attributes.set(tag: TIFFTAG_SAMPLEFORMAT, with: UInt16(SAMPLEFORMAT_INT))
			default:
				throw LazyTIFFImageError.UnsupportedType
		}
	}

	deinit {
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

	public func read(_ area: Area) throws -> UnsafeBufferPointer<Channel> {
		guard let ref = tiffref else {
			throw TIFFError.InvalidReference
		}
		guard mode == "r" else {
			throw TIFFError.WrongMode
		}

		let size = self.size
		if (area.origin.x + area.size.width) > size.width {
			throw LazyTIFFImageError.AreaOutOfBounds
		}
		if (area.origin.y + area.size.height) > size.height {
			throw LazyTIFFImageError.AreaOutOfBounds
		}

		let elementCount = area.size.width * area.size.height * Int(attributes.samplesPerPixel)
		let buffer = UnsafeMutableBufferPointer<Channel>.allocate(capacity: elementCount)
		let pointer = buffer.baseAddress!

		// Don't try to be clever here, just get something working
		// and we can optimise things later!
		let lineElementCount = size.width * Int(attributes.samplesPerPixel)
		let linebuffer = UnsafeMutablePointer<Channel>.allocate(capacity: lineElementCount)
		defer { linebuffer.deallocate() }
		for line in 0..<area.size.height {
			let yoffset = line + area.origin.y
			guard TIFFReadScanline(ref, linebuffer, UInt32(yoffset), 0) == 1 else {
				throw TIFFError.ReadScanline
			}
			let target = pointer.advanced(by: line * area.size.width * Int(attributes.samplesPerPixel))
			let src = linebuffer.advanced(by: area.origin.x * Int(attributes.samplesPerPixel))
			target.update(from:src, count: area.size.width * Int(attributes.samplesPerPixel))
		}
		return UnsafeBufferPointer<Channel>(buffer)
	}

	// TODO: Ideally this would be an UnsafePointer<Channel>, but it seems LibTIFF expects a mutable pointer
	// as part of the call to TIFFWriteScanline
	public func write(area: Area, buffer: UnsafeBufferPointer<Channel>) throws {
		guard let ref = tiffref else {
			throw TIFFError.InvalidReference
		}
		guard mode == "w" else {
			throw TIFFError.WrongMode
		}
		guard let pointer = buffer.baseAddress else {
			throw LazyTIFFImageError.NoBaseAddress
		}

		let size = self.size
		guard (area.origin.x + area.size.width) <= size.width else {
			throw LazyTIFFImageError.AreaOutOfBounds
		}
		guard (area.origin.y + area.size.height) <= size.height else {
			throw LazyTIFFImageError.AreaOutOfBounds
		}

		// Don't try to be clever here, just get something working
		// and we can optimise things later!
		let lineElementCount = size.width * Int(attributes.samplesPerPixel)
		guard TIFFScanlineSize(ref) == lineElementCount * MemoryLayout<Channel>.stride else {
			throw TIFFError.InternalInconsistancy
		}

		for line in 0..<area.size.height {
			let yoffset = line + area.origin.y
			let src = pointer.advanced(by: ((line * area.size.width) + area.origin.x) * Int(attributes.samplesPerPixel))

			if area.origin.x == 0 && area.size.width == size.width {
				// full width, so no need to compose data
				let raw = UnsafeMutableRawPointer(mutating: src)
				guard TIFFWriteScanline(ref, raw, UInt32(yoffset), 0) == 1  else {
					throw TIFFError.WriteScanline
				}
			} else {
				// partial line width, so attempt to compose a line from old and new data
				// TODO: For this case to work, you in theory need to read back the data from
				// the TIFF, but if you try to call TIFFReadScanline then it breaks TIFFWriteScanline
				// for whatever reason.
				throw LazyTIFFImageError.PartialScanlineUpdatesNotPossible
			}
		}
	}
}