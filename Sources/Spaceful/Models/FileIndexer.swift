import Foundation
import Combine

/// A single file surfaced by the flat indexer (Volumineux view).
struct IndexedFile: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let modDate: Date?
    let isDirectory: Bool
    let isBundle: Bool
    let category: FileCategory

    var isProtected: Bool { SystemPaths.isProtected(url) }
    var ext: String { (name as NSString).pathExtension.lowercased() }
}

/// Aggregated size + count for one file category (Types view).
struct CategoryTotal: Identifiable {
    let category: FileCategory
    var size: Int64
    var count: Int
    var id: String { category.rawValue }
}

/// Walks a subtree **once** (off the main thread) and produces two flat, sortable
/// datasets shared by the *Types* and *Volumineux* tabs:
/// - `categoryTotals`: bytes & file count per `FileCategory`
/// - `largest`: the N biggest individual files
///
/// Independent of navigation and cleanup; runs only when the user opens those tabs, so it
/// never adds permission prompts on its own. System (`/System`, `/usr`…) subtrees are skipped.
@MainActor
final class FileIndexer: ObservableObject {
    @Published private(set) var categoryTotals: [CategoryTotal] = []
    @Published private(set) var largest: [IndexedFile] = []
    @Published private(set) var isIndexing = false
    @Published private(set) var scanned = 0
    @Published private(set) var indexedRoot: String?

    /// When set from the Types tab, the Volumineux tab opens pre-filtered to this category.
    @Published var focusCategory: FileCategory?

    /// How many of the biggest files to retain.
    private let topN = 500
    private let queue = DispatchQueue(label: "spaceful.index", qos: .utility)
    private var cancelFlag = AtomicFlag()

    var grandTotal: Int64 { categoryTotals.reduce(0) { $0 + $1.size } }
    var hasData: Bool { !categoryTotals.isEmpty || !largest.isEmpty }

    func cancel() {
        cancelFlag.set()
        isIndexing = false
    }

    /// Drop indexed files at/under `path` after the user trashes them, keeping the
    /// per-category totals consistent for the entries we still track.
    func removeFiles(under path: String) {
        let removed = largest.filter { $0.url.path == path || $0.url.path.hasPrefix(path + "/") }
        guard !removed.isEmpty else { return }
        largest.removeAll { f in removed.contains { $0.id == f.id } }
        for r in removed {
            guard let i = categoryTotals.firstIndex(where: { $0.category == r.category }) else { continue }
            categoryTotals[i].size = max(0, categoryTotals[i].size - r.size)
            categoryTotals[i].count = max(0, categoryTotals[i].count - 1)
        }
    }

    /// (Re)build the index for `url`, replacing any previous result.
    func index(url: URL) {
        cancelFlag.set()
        let flag = AtomicFlag()
        cancelFlag = flag
        categoryTotals = []
        largest = []
        scanned = 0
        isIndexing = true
        indexedRoot = url.path
        let topN = self.topN

        queue.async { [weak self] in
            guard let self else { return }
            var acc = Accumulator(topN: topN)
            self.walk(url, flag: flag, into: &acc)
            if flag.isSet { return }
            let totals = acc.totals.values
                .map { CategoryTotal(category: $0.category, size: $0.size, count: $0.count) }
                .sorted { $0.size > $1.size }
            let biggest = acc.heap.sorted { $0.size > $1.size }
            DispatchQueue.main.async {
                guard !flag.isSet else { return }
                self.categoryTotals = totals
                self.largest = biggest
                self.isIndexing = false
            }
        }
    }

    // MARK: - Walk

    private struct Bucket { let category: FileCategory; var size: Int64; var count: Int }

    /// Plain value accumulator, touched only on the indexer's serial queue.
    private struct Accumulator {
        let topN: Int
        var totals: [FileCategory: Bucket] = [:]
        var heap: [IndexedFile] = []      // current top-N, not kept sorted until the end
        var minKept: Int64 = 0            // smallest size currently in `heap` (when full)
        var count = 0

        mutating func add(_ file: IndexedFile) {
            var b = totals[file.category] ?? Bucket(category: file.category, size: 0, count: 0)
            b.size += file.size; b.count += 1
            totals[file.category] = b

            if heap.count < topN {
                heap.append(file)
                if heap.count == topN { minKept = heap.map(\.size).min() ?? 0 }
            } else if file.size > minKept {
                // Replace the smallest retained file.
                if let idx = heap.firstIndex(where: { $0.size == minKept }) {
                    heap[idx] = file
                    minKept = heap.map(\.size).min() ?? 0
                }
            }
        }
    }

    nonisolated private func walk(_ url: URL, flag: AtomicFlag, into acc: inout Accumulator) {
        if flag.isSet { return }
        if SystemPaths.isCritical(url) { return }
        guard let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
            .contentModificationDateKey
        ]) else { return }
        if values.isSymbolicLink == true { return }

        let isDir = values.isDirectory ?? false
        let isBundle = values.isPackage ?? false

        acc.count += 1
        if acc.count % 4000 == 0 {
            let n = acc.count
            DispatchQueue.main.async { [weak self] in
                guard let self, !flag.isSet else { return }
                self.scanned = n
            }
        }

        if !isDir || isBundle {        // leaf: regular file or bundle
            let size = isBundle ? bundleBytes(url, flag: flag)
                                : Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            let file = IndexedFile(url: url, name: url.lastPathComponent, size: size,
                                   modDate: values.contentModificationDate,
                                   isDirectory: false, isBundle: isBundle,
                                   category: FileCategory.of(url: url, isDirectory: false, isBundle: isBundle))
            acc.add(file)
            return
        }

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [])) ?? []
        for child in entries {
            if flag.isSet { return }
            walk(child, flag: flag, into: &acc)
        }
    }

    nonisolated private func bundleBytes(_ url: URL, flag: AtomicFlag) -> Int64 {
        var total: Int64 = 0
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey], options: []) else { return 0 }
        for case let item as URL in e {
            if flag.isSet { return total }
            let v = try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        return total
    }
}
