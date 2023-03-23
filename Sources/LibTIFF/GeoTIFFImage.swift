import Foundation

import CLibTIFF

// from http://docs.opengeospatial.org/is/19-008r4/19-008r4.html
enum GeoTIFFTag: UInt32 {
	case GeoKeyDirectoryTag = 34735
	case GeoDoubleParamsTag = 34736
	case GeoAsciiParamsTag = 34737
	case ModelPixelScaleTag = 33550
	case ModelTiepointTag = 33922
	case ModelTransformationTag = 34264
}

enum GeoTIFFImageError: Error {
	case TagNotFound
	case MemoryError
}

public class GeoTIFFImage<Channel>: LazyTIFFImage<Channel> {

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

	func getCustomTagArray<T>(_ tag: GeoTIFFTag) throws -> [T] {
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
}