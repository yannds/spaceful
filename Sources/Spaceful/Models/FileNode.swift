import Foundation

/// A node in the scanned filesystem tree.
///
/// `size` is the aggregated, allocated-on-disk size of the node and all of its
/// descendants. For a regular file it equals `ownSize`; for a directory it is the
/// sum of its children. The tree is built off the main thread by `ScanEngine` and
/// is treated as immutable once published (except for `children`, which is pruned
/// when the user deletes items).
///
/// `@unchecked Sendable`: background workers only read the immutable `url`; all mutation
/// of `size`/`children`/`isSizing` happens back on the main actor, so passing a node to a
/// sizing operation is safe by construction.
final class FileNode: Identifiable, @unchecked Sendable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let isSymlink: Bool
    let isBundle: Bool          // .app / .bundle / package directory
    let modificationDate: Date?

    var ownSize: Int64          // size of the file itself (0 for directories)
    var size: Int64             // aggregated size of subtree
    var fileCount: Int          // number of regular files in subtree (1 for a file)

    /// Lazy-navigation state. Children are listed on demand when a directory is
    /// opened; directory sizes are then filled in progressively in the background.
    var childrenLoaded = false  // immediate children have been listed
    var isSizing = false        // aggregated size is still being computed

    weak var parent: FileNode?
    var children: [FileNode]

    init(url: URL,
         name: String,
         isDirectory: Bool,
         isSymlink: Bool,
         isBundle: Bool,
         modificationDate: Date?,
         ownSize: Int64,
         size: Int64,
         fileCount: Int,
         parent: FileNode?,
         children: [FileNode]) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isBundle = isBundle
        self.modificationDate = modificationDate
        self.ownSize = ownSize
        self.size = size
        self.fileCount = fileCount
        self.parent = parent
        self.children = children
    }

    /// Path from the root down to this node, used for the breadcrumb.
    var ancestry: [FileNode] {
        var chain: [FileNode] = []
        var current: FileNode? = self
        while let node = current {
            chain.append(node)
            current = node.parent
        }
        return chain.reversed()
    }

    /// Children sorted largest-first, ignoring empty entries.
    var childrenBySize: [FileNode] {
        children.sorted { $0.size > $1.size }
    }

    /// Remove this node from its parent and fix up aggregated sizes up the chain.
    /// Called after the underlying file has been moved to the Trash.
    func detachFromParent() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        var current: FileNode? = parent
        while let node = current {
            node.size -= size
            node.fileCount -= fileCount
            current = node.parent
        }
    }
}
