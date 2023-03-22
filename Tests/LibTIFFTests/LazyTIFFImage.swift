import XCTest

@testable import LibTIFF

class LazyTIFFImageTests : XCTestCase {

	var basePath: String!
	var tempPath: String!

	func path(function: String = #function) -> String {
		let path = "\(basePath!)\(function).tiff"
		return path
	}

	override func setUp() {
		let template = "/tmp/tmpdir.XXXXXX"
		var bytes = template.utf8CString.map { $0 }
		if let cpath = mkdtemp(&bytes) {
			let path = String(cString: cpath)
			basePath = path + "/"
			tempPath = path
		}
	}

	override func tearDown() {
		if unlink(tempPath) != -1 {
			exit(EXIT_FAILURE)
		}
	}

	func testLazyReading() throws {
		let size = 100 * 100 * 3
		var written = [UInt8](repeating: 0, count: size)
		let image = try TIFFImage<UInt8>(writingAt: path(), size: Size(width: 100, height: 100), hasAlpha: false)

		// Turn on every red pixel.
		var c = 0
		while c < size {
			let v: UInt8 = c % 3 == 0 ? 255 : 0
			image.buffer[c] = v
			c += 1
		}

		for i in 0..<size {
			written[i] = image.buffer[i]
		}

		try! image.write()
		image.close()

		let reading = try! LazyTIFFImage<UInt8>(readingAt: path())
		XCTAssertEqual(reading.size, image.size)
		XCTAssertEqual(reading.attributes.samplesPerPixel, 3)
		XCTAssertEqual(reading.attributes.bitsPerSample, 8)

		let area = Area(
			origin: Point(x: 0, y: 0),
			size: image.size
		)
		let data = try reading.read(area)
		defer { data.deallocate() }
		for i in 0..<size {
			XCTAssert(written[i] == data[i], "contents of written file != contents of read file")
		}
	}

	func testLazyWritingAllData() throws {
		let size = 100 * 100 * 3
		var written = [UInt8](repeating: 0, count: size)
		let image = try LazyTIFFImage<UInt8>(writingAt: path(), size: Size(width: 100, height: 100), samplesPerPixel: 3, hasAlpha: false)

		// Turn on every red pixel.
		var c = 0
		while c < size {
			let v: UInt8 = c % 3 == 0 ? 255 : 0
			written[c] = v
			c += 1
		}

		let area = Area(
			origin: Point(x: 0, y: 0),
			size: image.size
		)
		written.withUnsafeMutableBufferPointer {
			try! image.write(area: area, buffer: $0.baseAddress!)
		}
		image.close()

		let reading = try TIFFImage<UInt8>(readingAt: path())
		for i in 0..<size {
			XCTAssert(written[i] == reading.buffer[i], "contents of written file != contents of read file")
		}
	}

	func testLazyWritingFullScanlines() throws {
		let size = 100 * 100 * 3
		let image = try LazyTIFFImage<UInt8>(writingAt: path(), size: Size(width: 100, height: 100), samplesPerPixel: 3, hasAlpha: false)

		// We need to write all pixels, otherwise libtiff will generate a tiff file that is considered corrupt by most tools
		for y in 0..<100 {
			var blankline = [UInt8](repeating: UInt8(y*2), count: 100 * 3)
			try blankline.withUnsafeMutableBufferPointer {
				let area = Area(
					origin: Point(x: 0, y: y),
					size: Size(width: 100, height: 1)
				)
				try image.write(area: area, buffer: $0.baseAddress!)
			}
		}
		image.close()

		var expected = [UInt8](repeating: 255, count: size)
		for y in 0..<100 {
			for x in 0..<100 {
				for sample in 0..<3 {
					expected[(((y * 100) + x) * 3) + sample] = UInt8(y * 2)
				}
			}
		}
		let reading = try TIFFImage<UInt8>(readingAt: path())
		for i in 0..<10 {
			XCTAssert(expected[i] == reading.buffer[i], "contents of written file != contents of read file")
		}
	}

	func testLazyWritingPartialScanlines() throws {
		let image = try! LazyTIFFImage<UInt8>(writingAt: path(), size: Size(width: 100, height: 100), samplesPerPixel: 3, hasAlpha: false)

		var blankline = [UInt8](repeating: UInt8(255), count: 100 * 3)
		try blankline.withUnsafeMutableBufferPointer {
			let area = Area(
				origin: Point(x: 10, y: 10),
				size: Size(width: 50, height: 1)
			)
			XCTAssertThrowsError(try image.write(area: area, buffer: $0.baseAddress!), "Expected error for partial update")
		}
	}
}