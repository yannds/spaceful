import Foundation

/// Computes the allocated-on-disk size of a directory subtree, with a thread-safe
/// session cache. Uses a single `FileManager` enumerator pass (no per-node object
/// allocation), which is markedly faster than building a full tree just to total sizes.
///
/// Safe to call concurrently from background operations; the cache is lock-guarded.
final class DirectorySizer: @unchecked Sendable {
    struct SizeInfo { let bytes: Int64; let files: Int }

    private let lock = NSLock()
    private var cache: [String: SizeInfo] = [:]

    private static let keys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey
    ]

    func isCached(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cache[path] != nil
    }

    func cached(_ path: String) -> SizeInfo? {
        lock.lock(); defer { lock.unlock() }
        return cache[path]
    }

    /// Returns the subtree size, computing and caching it on a miss. If `isCancelled`
    /// fires mid-walk, returns the partial total **without** caching it.
    func size(of url: URL, isCancelled: () -> Bool) -> SizeInfo {
        if let hit = cached(url.path) { return hit }

        var bytes: Int64 = 0
        var files = 0
        if let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(Self.keys), options: []) {
            for case let item as URL in enumerator {
                if isCancelled() { return SizeInfo(bytes: bytes, files: files) }
                guard let values = try? item.resourceValues(forKeys: Self.keys) else { continue }
                if values.isRegularFile == true { files += 1 }
                bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }

        let info = SizeInfo(bytes: bytes, files: files)
        lock.lock(); cache[url.path] = info; lock.unlock()
        return info
    }

    func invalidate(under path: String) {
        lock.lock(); defer { lock.unlock() }
        for key in cache.keys where key == path || key.hasPrefix(path + "/") {
            cache.removeValue(forKey: key)
        }
    }
}
