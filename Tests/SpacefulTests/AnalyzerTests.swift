import XCTest
@testable import Spaceful

@MainActor
final class AnalyzerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpacefulTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ name: String, bytes: Int, in dir: URL? = nil) throws {
        let target = (dir ?? root).appendingPathComponent(name)
        try Data(count: bytes).write(to: target)
    }

    /// Thresholds lowered so the fixture stays tiny and fast.
    private var testConfig: AnalyzerConfig {
        var c = AnalyzerConfig()
        c.duplicateMinSize = 4 * 1024
        c.largeFileThreshold = 1.GB        // suppress the "large files" group
        c.oldFileMinSize = 1.GB            // suppress the "old files" group
        c.minCacheSize = 1024
        c.minDevJunkSize = 1.GB
        return c
    }

    private func runAnalysis(_ analyzer: Analyzer) async {
        analyzer.analyze(url: root)
        for _ in 0..<100 where analyzer.isAnalyzing {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func testDetectsDuplicatesAcrossDifferentNames() async throws {
        // Identical content, different names → must be flagged as a duplicate.
        try write("original.bin", bytes: 100 * 1024)
        try write("totally-different-name.bin", bytes: 100 * 1024)
        // A unique file that must NOT be flagged.
        var unique = Data(count: 100 * 1024); unique[0] = 7
        try unique.write(to: root.appendingPathComponent("unique.bin"))

        let analyzer = Analyzer(config: testConfig)
        await runAnalysis(analyzer)

        XCTAssertFalse(analyzer.isAnalyzing)
        let dupes = analyzer.groups.first { $0.title.contains("Doublons") }
        XCTAssertNotNil(dupes, "un groupe de doublons doit exister")
        XCTAssertEqual(dupes?.items.count, 1, "une seule copie excédentaire flaggée (l'autre est conservée)")
    }

    func testDetectsCacheDirectories() async throws {
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try write("blob.bin", bytes: 50 * 1024, in: caches)

        let analyzer = Analyzer(config: testConfig)
        await runAnalysis(analyzer)

        XCTAssertTrue(analyzer.groups.contains { $0.title.contains("Caches") },
                      "un groupe « Caches » doit exister")
    }

    func testNoFalsePositivesOnUniqueFiles() async throws {
        for i in 0..<3 {
            var d = Data(count: 20 * 1024); d[0] = UInt8(i + 1)
            try d.write(to: root.appendingPathComponent("file\(i).bin"))
        }
        let analyzer = Analyzer(config: testConfig)
        await runAnalysis(analyzer)
        XCTAssertNil(analyzer.groups.first { $0.title.contains("Doublons") },
                     "aucun doublon ne doit être détecté sur des fichiers distincts")
    }
}
