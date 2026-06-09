import XCTest
@testable import Spaceful

final class SystemPathsTests: XCTestCase {
    private func url(_ p: String) -> URL { URL(fileURLWithPath: p) }

    func testCriticalSubtreesAreProtected() {
        XCTAssertTrue(SystemPaths.isCritical(url("/System")))
        XCTAssertTrue(SystemPaths.isCritical(url("/System/Library/CoreServices")))
        XCTAssertTrue(SystemPaths.isCritical(url("/usr/bin/swift")))
        XCTAssertTrue(SystemPaths.isCritical(url("/bin/zsh")))
        XCTAssertTrue(SystemPaths.isProtected(url("/System/anything")))
    }

    func testEssentialContainersAreProtectedButNotCritical() {
        XCTAssertTrue(SystemPaths.isProtected(url("/")))
        XCTAssertTrue(SystemPaths.isProtected(url("/Users")))
        XCTAssertTrue(SystemPaths.isProtected(url("/Applications")))
        XCTAssertFalse(SystemPaths.isCritical(url("/Users")))   // browsable, just not deletable
    }

    func testHomeAndStandardSubfoldersProtected() {
        let home = NSHomeDirectory()
        XCTAssertTrue(SystemPaths.isProtected(url(home)))
        XCTAssertTrue(SystemPaths.isProtected(url(home + "/Downloads")))
        XCTAssertTrue(SystemPaths.isProtected(url(home + "/Library")))
    }

    func testContentsInsideEssentialFolderAreDeletable() {
        let home = NSHomeDirectory()
        XCTAssertFalse(SystemPaths.isProtected(url(home + "/Downloads/big-file.zip")))
        XCTAssertFalse(SystemPaths.isProtected(url(home + "/Documents/report.pdf")))
    }

    func testTopLevelOneComponentIsProtected() {
        XCTAssertTrue(SystemPaths.isProtected(url("/SomeRandomTopLevel")))
    }
}
