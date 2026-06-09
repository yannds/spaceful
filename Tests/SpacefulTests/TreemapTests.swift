import XCTest
@testable import Spaceful

final class TreemapTests: XCTestCase {
    private func file(_ name: String, _ size: Int64) -> FileNode {
        FileNode(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name,
                 isDirectory: false, isSymlink: false, isBundle: false,
                 modificationDate: nil, ownSize: size, size: size, fileCount: 1,
                 parent: nil, children: [])
    }

    func testTilesStayWithinBounds() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let nodes = [file("a", 500), file("b", 300), file("c", 150), file("d", 50)]
        let tiles = Treemap.layout(nodes: nodes, in: rect)
        XCTAssertEqual(tiles.count, 4)
        let eps: CGFloat = 0.5
        for t in tiles {
            XCTAssertGreaterThanOrEqual(t.rect.minX, rect.minX - eps)
            XCTAssertGreaterThanOrEqual(t.rect.minY, rect.minY - eps)
            XCTAssertLessThanOrEqual(t.rect.maxX, rect.maxX + eps)
            XCTAssertLessThanOrEqual(t.rect.maxY, rect.maxY + eps)
            XCTAssertFalse(t.rect.width.isNaN || t.rect.height.isNaN)
        }
    }

    func testTilesFillTheRectangle() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 200)
        let nodes = [file("a", 400), file("b", 300), file("c", 200), file("d", 100)]
        let area = nodes.reduce(0.0) { $0 + Double($1.size) }   // proportional check below
        let tiles = Treemap.layout(nodes: nodes, in: rect).filter { $0.depth == 0 }
        let tileArea = tiles.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        XCTAssertEqual(tileArea, 40000, accuracy: 40000 * 0.02)   // ~fills 200×200

        // Each tile's area should track its share of the total size.
        let total = Double(rect.width * rect.height)
        for t in tiles {
            let expected = Double(t.node.size) / area * total
            let actual = Double(t.rect.width * t.rect.height)
            XCTAssertEqual(actual, expected, accuracy: expected * 0.05)
        }
    }

    func testZeroSizedAndEmptyInputs() {
        XCTAssertTrue(Treemap.layout(nodes: [], in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
        XCTAssertTrue(Treemap.layout(nodes: [file("z", 0)], in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
        XCTAssertTrue(Treemap.layout(nodes: [file("a", 10)], in: .zero).isEmpty)
    }
}
