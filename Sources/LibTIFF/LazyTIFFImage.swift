
import CLibTIFF

public struct Point {
	let x: Int
	let y: Int
}

public struct Area {
	let origin: Point
	let size: Size
}

enum LazyTIFFImageError: Error {
	case AreaOutOfBounds
	case PartialScanlineUpdatesNotPossible
}

public class LazyTIFFImage<Channel> {
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
	}

	public init(writingAt path: String, size: Size, samplesPerPixel: Int, hasAlpha: Bool) throws {
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
										 samplesPerPixel: UInt32(samplesPerPixel),
										 rowsPerStrip: 1,
										 photometric: UInt32(PHOTOMETRIC_RGB),
										 planarconfig: UInt32(PLANARCONFIG_CONTIG),
										 orientation: UInt32(ORIENTATION_TOPLEFT),
										 extraSamples: extraSamples)
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

	public func read(_ area: Area) throws -> UnsafePointer<Channel> {
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
		let buffer = UnsafeMutablePointer<Channel>.allocate(capacity: elementCount)

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
			let target = buffer.advanced(by: yoffset * area.size.width * Int(attributes.samplesPerPixel))
			let src = linebuffer.advanced(by: area.origin.x * Int(attributes.samplesPerPixel))
			target.assign(from:src, count: area.size.width * Int(attributes.samplesPerPixel))
		}

		return UnsafePointer<Channel>(buffer)
	}

	// TODO: Ideally this would be an UnsafePointer<Channel>, but it seems LibTIFF expects a mutable pointer
	// as part of the call to TIFFWriteScanline
	public func write(area: Area, buffer: UnsafeMutablePointer<Channel>) throws {
		guard let ref = tiffref else {
			throw TIFFError.InvalidReference
		}
		guard mode == "w" else {
			throw TIFFError.WrongMode
		}

		let size = self.size
		if (area.origin.x + area.size.width) > size.width {
			throw LazyTIFFImageError.AreaOutOfBounds
		}
		if (area.origin.y + area.size.height) > size.height {
			throw LazyTIFFImageError.AreaOutOfBounds
		}

		// Don't try to be clever here, just get something working
		// and we can optimise things later!
		let lineElementCount = size.width * Int(attributes.samplesPerPixel)
		guard TIFFScanlineSize(ref) == lineElementCount * MemoryLayout<Channel>.stride else {
			throw TIFFError.InternalInconsistancy
		}

		for line in 0..<area.size.height {
			// print(line)
			let yoffset = line + area.origin.y
			// print(yoffset)
			let src = buffer.advanced(by: ((line * area.size.width) + area.origin.x) * Int(attributes.samplesPerPixel))

			if area.origin.x == 0 && area.size.width == size.width {
				// full width, so no need to compose data
				guard TIFFWriteScanline(ref, src, UInt32(yoffset), 0) == 1  else {
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