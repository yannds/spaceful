import Foundation
import Combine

/// Lazy, progressive directory engine driving the visualization.
///
/// Opening a directory is **instant**: its immediate children are listed synchronously
/// (one `contentsOfDirectory` call). Each child directory's aggregated size is then
/// computed **in parallel, in the background**, and the result is published as it
/// arrives — so the biggest items surface within moments instead of after a full scan.
/// We only ever walk the subtree of a directory the user actually opens; results are
/// cached so re-opening is instant. Navigating elsewhere cancels in-flight sizing.
@MainActor
final class ScanEngine: ObservableObject {
    @Published private(set) var root: FileNode?
    @Published private(set) var revision = 0          // bumped as sizes fill in
    @Published private(set) var pendingSizing = 0     // child directories still computing

    var isSizing: Bool { pendingSizing > 0 }

    private let sizer = DirectorySizer()
    private let sizingQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        q.qualityOfService = .userInitiated
        return q
    }()

    private let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .fileSizeKey, .contentModificationDateKey
    ]

    // MARK: - Public API

    /// Begin a new exploration rooted at `url`.
    func openRoot(url: URL) {
        sizingQueue.cancelAllOperations()
        guard let node = makeNode(url: url, parent: nil) else { return }
        node.childrenLoaded = false
        root = node
        open(node)
    }

    /// Load (if needed) and size the children of `node`, publishing progressively.
    func open(_ node: FileNode) {
        guard node.isDirectory, !node.isBundle else { return }
        sizingQueue.cancelAllOperations()
        loadChildrenIfNeeded(node)
        sizeChildren(of: node)
    }

    func cancel() {
        sizingQueue.cancelAllOperations()
        pendingSizing = 0
    }

    /// Drop cached sizes under `path` (e.g. after a deletion) so they recompute.
    func invalidateCache(under path: String) {
        sizer.invalidate(under: path)
    }

    /// Persist the size cache to disk (instant reopen across launches).
    func persist() { sizer.saveAsync() }

    /// Force-relist a directory from disk (e.g. after an Undo restores files), then resize.
    func reload(_ node: FileNode) {
        guard node.isDirectory, !node.isBundle else { return }
        sizer.invalidate(under: node.url.path)
        node.childrenLoaded = false
        open(node)
    }

    // MARK: - Lazy listing

    private func loadChildrenIfNeeded(_ node: FileNode) {
        guard !node.childrenLoaded else { return }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: node.url, includingPropertiesForKeys: Array(resourceKeys), options: [])) ?? []
        node.children = entries.compactMap { makeNode(url: $0, parent: node) }
        node.childrenLoaded = true
    }

    /// Create a node from a URL. Files get their size immediately; directories start at
    /// zero and are sized later (unless a cached size is available).
    private func makeNode(url: URL, parent: FileNode?) -> FileNode? {
        guard let values = try? url.resourceValues(forKeys: resourceKeys) else { return nil }
        let isDir = values.isDirectory ?? false
        let isSym = values.isSymbolicLink ?? false
        let isBundle = values.isPackage ?? false
        let leafSize = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent

        let node = FileNode(url: url, name: name,
                            isDirectory: isDir, isSymlink: isSym, isBundle: isBundle,
                            modificationDate: values.contentModificationDate,
                            ownSize: (isDir && !isBundle) ? 0 : leafSize,
                            size: (isDir && !isBundle) ? 0 : leafSize,
                            fileCount: (isDir && !isBundle) ? 0 : 1,
                            parent: parent, children: [])
        if isSym || !isDir || isBundle { node.childrenLoaded = true }   // leaves
        if let cached = sizer.cached(node.url.path), isDir, !isBundle {
            node.size = cached.bytes
            node.fileCount = cached.files
        }
        return node
    }

    // MARK: - Progressive sizing

    private func sizeChildren(of node: FileNode) {
        let sizer = self.sizer   // capture the (thread-safe) sizer, not the actor's property
        let dirs = node.children.filter { $0.isDirectory && !$0.isBundle && !sizer.isCached($0.url.path) }
        for d in dirs { d.isSizing = true }
        pendingSizing = dirs.count
        revision &+= 1
        guard !dirs.isEmpty else { aggregate(node); return }

        for child in dirs {
            let op = BlockOperation()
            op.addExecutionBlock { [weak op, weak self] in
                let info = sizer.size(of: child.url) { op?.isCancelled ?? true }
                if op?.isCancelled == true { return }
                Task { @MainActor in
                    guard let self else { return }
                    child.size = info.bytes
                    child.fileCount = info.files
                    child.isSizing = false
                    self.pendingSizing = max(0, self.pendingSizing - 1)
                    self.aggregate(node)
                    self.revision &+= 1
                    if self.pendingSizing == 0 { sizer.saveAsync() }   // persist once settled
                }
            }
            sizingQueue.addOperation(op)
        }
    }

    /// Roll the children's sizes up into `node` (and onto the breadcrumb root label).
    private func aggregate(_ node: FileNode) {
        node.size = node.children.reduce(0) { $0 + $1.size }
        node.fileCount = node.children.reduce(0) { $0 + $1.fileCount }
    }
}
