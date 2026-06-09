import XCTest
@testable import Spaceful

final class FileCategoryTests: XCTestCase {
    private func cat(_ path: String, dir: Bool = false, bundle: Bool = false) -> FileCategory {
        FileCategory.of(url: URL(fileURLWithPath: path), isDirectory: dir, isBundle: bundle)
    }

    func testByExtension() {
        XCTAssertEqual(cat("/x/a.swift"), .code)
        XCTAssertEqual(cat("/x/photo.JPG"), .image)        // case-insensitive
        XCTAssertEqual(cat("/x/clip.mov"), .video)
        XCTAssertEqual(cat("/x/song.flac"), .audio)
        XCTAssertEqual(cat("/x/bundle.zip"), .archive)
        XCTAssertEqual(cat("/x/report.pdf"), .document)
        XCTAssertEqual(cat("/x/installer.dmg"), .diskImage)
        XCTAssertEqual(cat("/x/server.log"), .cache)
        XCTAssertEqual(cat("/x/unknown.xyz"), .other)
        XCTAssertEqual(cat("/x/noext"), .other)
    }

    func testDirectoriesAndBundles() {
        XCTAssertEqual(cat("/x/Photos", dir: true), .folder)
        XCTAssertEqual(cat("/x/Caches", dir: true), .cache)
        XCTAssertEqual(cat("/x/node_modules", dir: true), .cache)
        XCTAssertEqual(cat("/Applications/Foo.app", dir: true, bundle: true), .application)
    }

    func testCriticalPathIsSystem() {
        XCTAssertEqual(cat("/System/Library/x.dylib"), .system)
    }

    func testEveryCategoryHasLabelAndColor() {
        for c in FileCategory.allCases {
            XCTAssertFalse(c.label.isEmpty)
            XCTAssertFalse(c.symbol.isEmpty)
        }
    }
}
