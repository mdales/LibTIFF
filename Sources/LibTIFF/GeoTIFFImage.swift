import Foundation

import CLibTIFF

// from http://docs.opengeospatial.org/is/19-008r4/19-008r4.html
public enum GeoTIFFTag: UInt32 {
	case GeoKeyDirectoryTag = 34735
	case GeoDoubleParamsTag = 34736
	case GeoAsciiParamsTag = 34737
	case ModelPixelScaleTag = 33550
	case ModelTiepointTag = 33922
	case ModelTransformationTag = 34264
}

public enum GeoTIFFImageError: Error {
	case TagNotFound
	case MemoryError
	case FailedToAddTags
	case DirectoryHeaderTooShort(Int)
	case DirectorySizeIncorrect(expected: Int, got: Int)
	case UnrecognisedGeoKey(UInt16)
}

public enum GeoTIFFDirectoryID: UInt16 {
	case GTModelTypeGeoKey = 1024
	case GTRasterTypeGeoKey = 1025

	case GeodeticCRSGeoKey = 2048
	case GeodeticCitationGeoKey = 2049
	case GeodeticDatumGeoKey = 2050
	case PrimeMeridianGeoKey = 2051
    case GeogLinearUnitsGeoKey = 2052
	case GeogLinearUnitSizeGeoKey = 2053
	case GeogAngularUnitsGeoKey = 2054
	case GeogAngularUnitSizeGeoKey = 2055
	case EllipsoidGeoKey = 2056
	case EllipsoidSemiMajorAxisGeoKey = 2057
	case EllipsoidSemiMinorAxisGeoKey = 2058
	case EllipsoidInvFlatteningGeoKey = 2059
	case AzimuthUnitsGeoKey = 2060
	case PrimeMeridianLongitudeGeoKey = 2061

	case ProjectionGeoKey = 3074
	case ProjMethodGeoKey = 3075
	case ProjLinearUnitsGeoKey = 3076
	case ProjLinearUnitSizeGeoKey = 3077

	case VerticalGeoKey = 4096

	case VerticalDatumGeoKey = 4098
	case VerticalUnitsGeoKey = 4099
}

public struct GeoTIFFDirectoryEntry {
	public let keyID: GeoTIFFDirectoryID
	public let tiffTag: UInt16?
	public let valueCount: UInt16
	public let valueOrIndex: UInt16

	public init(keyID: GeoTIFFDirectoryID, tiffTag: UInt16?, valueCount: UInt16, valueOrIndex: UInt16) {
		self.keyID = keyID
		self.tiffTag = tiffTag
		self.valueCount = valueCount
		self.valueOrIndex = valueOrIndex
	}
}

public struct GeoTIFFDirectory {
	public let majorVersion: UInt16
	public let minorVersion: UInt16
	public let revision: UInt16
	// In the TIFF there is a key count, but here that's
	// the length of the array

	public let entries: [GeoTIFFDirectoryEntry]

	public init(majorVersion: UInt16, minorVersion: UInt16, revision: UInt16, entries: [GeoTIFFDirectoryEntry]) {
		self.majorVersion = majorVersion
		self.minorVersion = minorVersion
		self.revision = revision
		self.entries = entries
	}
}

public class GeoTIFFImage<Channel>: LazyTIFFImage<Channel> {

	public override init(readingAt path: String) throws {
		try super.init(readingAt: path)
		guard let ref = tiffref else {
			throw TIFFError.InvalidReference
		}
		guard SetGeoTIFFFields(ref) == 0 else {
			throw GeoTIFFImageError.FailedToAddTags
		}
	}

	public override init(writingAt path: String, size: Size, samplesPerPixel: Int, hasAlpha: Bool, useBigTIFF: Bool=false) throws {
		try super.init(writingAt: path, size: size, samplesPerPixel: samplesPerPixel, hasAlpha: hasAlpha, useBigTIFF: useBigTIFF)
		guard let ref = tiffref else {
			throw TIFFError.InvalidReference
		}
		guard SetGeoTIFFFields(ref) == 0 else {
			throw GeoTIFFImageError.FailedToAddTags
		}
	}
}

extension GeoTIFFImage {

	public func getPixelScale() throws -> [Double] {
		return try getCustomTagArray(.ModelPixelScaleTag)
	}

	public func getTilePoint() throws -> [Double] {
		return try getCustomTagArray(.ModelTiepointTag)
	}

	public func getProjection() throws -> String {
		let ascii: [UInt8] = try getCustomTagArray(.GeoAsciiParamsTag)
		return String(ascii.map { Character(UnicodeScalar($0)) })
	}

	public func getDirectory() throws -> GeoTIFFDirectory {
		let rawDirectory: [UInt16] = try getCustomTagArray(.GeoKeyDirectoryTag)
		guard rawDirectory.count >= 4 else {
			throw GeoTIFFImageError.DirectoryHeaderTooShort(rawDirectory.count)
		}
		guard rawDirectory.count == 4 + (Int(rawDirectory[3]) * 4) else {
			throw GeoTIFFImageError.DirectorySizeIncorrect(
				expected: 4 + (Int(rawDirectory[3]) * 4),
				got: rawDirectory.count
			)
		}

		var entries: [GeoTIFFDirectoryEntry] = []
		for idx in 0..<Int(rawDirectory[3]) {
			let offset = 4 + (idx * 4)
			guard let keyID = GeoTIFFDirectoryID(rawValue: rawDirectory[offset + 0]) else {
				throw GeoTIFFImageError.UnrecognisedGeoKey(rawDirectory[offset + 0])
			}

			entries.append(GeoTIFFDirectoryEntry(
				keyID: keyID,
				tiffTag: rawDirectory[offset + 1] == 0 ? nil : rawDirectory[offset + 1],
				valueCount: rawDirectory[offset + 2],
				valueOrIndex: rawDirectory[offset + 3]
			))
		}

		return GeoTIFFDirectory(
			majorVersion: rawDirectory[0],
			minorVersion: rawDirectory[1],
			revision: rawDirectory[2],
			entries: entries
		)
	}

	private func getCustomTagArray<T>(_ tag: GeoTIFFTag) throws -> [T] {
		guard let ref = tiffref else {
			throw TIFFError.InvalidReference
		}
		var data: UnsafeMutablePointer<T>?
		var count = UInt16(0)
		try withUnsafeMutablePointer(to: &data) {
			guard TIFFGetField_CustomDataArray(ref, tag.rawValue, &count, $0) == 1 else {
				throw GeoTIFFImageError.TagNotFound
			}
		}
		guard let data = data else {
			throw GeoTIFFImageError.MemoryError
		}
		let buffer = UnsafeBufferPointer<T>(start: data, count: Int(count))
		return Array(buffer)
	}

	public func setPixelScale(_ scale: [Double]) throws {
		try setCustomTagArray(tag: .ModelPixelScaleTag, data: scale)
	}

	public func setTiePoint(_ tiePoint: [Double]) throws {
		try setCustomTagArray(tag: .ModelTiepointTag, data: tiePoint)
	}

	public func setProjection(_ projection: String) throws {
		guard let ref = tiffref else {
			throw TIFFError.InvalidReference
		}
		let withSeperator = projection + "|"
		try withSeperator.withCString {
			let mutableCStringPtr = UnsafeMutablePointer(mutating: $0)
			guard TIFFSetField_CustomDataAscii(ref, GeoTIFFTag.GeoAsciiParamsTag.rawValue, mutableCStringPtr) == 1 else {
				throw GeoTIFFImageError.TagNotFound
			}
		}
	}

	public func setDirectory(_ directory: GeoTIFFDirectory) throws {
		var buffer: [UInt16] = []
		buffer.append(directory.majorVersion)
		buffer.append(directory.minorVersion)
		buffer.append(directory.revision)
		buffer.append(UInt16(directory.entries.count))

		for entry in directory.entries {
			buffer.append(entry.keyID.rawValue)
			if let tiffTag = entry.tiffTag {
				buffer.append(tiffTag)
			} else {
				buffer.append(0)
			}
			buffer.append(entry.valueCount)
			buffer.append(entry.valueOrIndex)
		}
		try setCustomTagArray(tag: .GeoKeyDirectoryTag, data: buffer)
	}

	private func setCustomTagArray<T>(tag: GeoTIFFTag, data: [T]) throws {
		guard let ref = tiffref else {
			throw TIFFError.InvalidReference
		}
		let count = UInt16(data.count)

		// data is immutable, but C world needs a mutable copy, so we
		// duplicate it here
		var duplicate = [T].init(data)
		try duplicate.withUnsafeMutableBytes {
			guard TIFFSetField_CustomDataArray(ref, tag.rawValue, count, $0.baseAddress!) == 1 else {
				throw GeoTIFFImageError.TagNotFound
			}
		}
	}
}