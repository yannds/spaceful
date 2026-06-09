import Foundation

/// Computes the allocated-on-disk size of a directory subtree, with a thread-safe cache
/// that is **persisted to disk** so reopening a location is instant across launches.
///
/// A cached entry stores the directory's modification date; on lookup we compare it to the
/// current `mtime` and drop the entry if it changed. (A directory's `mtime` only moves when
/// its *immediate* children change, so a deep edit can leave a stale total until the next
/// explicit rescan — the trade-off for instant reopen.)
///
/// Safe to call concurrently from background operations; the cache is lock-guarded.
final class DirectorySizer: @unchecked Sendable {
    struct SizeInfo: Codable { let bytes: Int64; let files: Int; let mtime: Date? }

    private let lock = NSLock()
    private var cache: [String: SizeInfo] = [:]
    private let ioQueue = DispatchQueue(label: "spaceful.sizecache.io", qos: .utility)

    private static let keys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey
    ]

    init() { load() }

    // MARK: - Lookup (with staleness check)

    func isCached(_ path: String) -> Bool { validEntry(path) != nil }
    func cached(_ path: String) -> SizeInfo? { validEntry(path) }

    /// Returns a cached entry only if the directory hasn't been modified since.
    private func validEntry(_ path: String) -> SizeInfo? {
        lock.lock()
        let entry = cache[path]
        lock.unlock()
        guard let entry else { return nil }
        if currentMtime(path) != entry.mtime {
            lock.lock(); cache.removeValue(forKey: path); lock.unlock()
            return nil
        }
        return entry
    }

    private func currentMtime(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
    }

    // MARK: - Sizing

    /// Returns the subtree size, computing and caching it on a miss. If `isCancelled`
    /// fires mid-walk, returns the partial total **without** caching it.
    func size(of url: URL, isCancelled: () -> Bool) -> SizeInfo {
        if let hit = cached(url.path) { return hit }

        var bytes: Int64 = 0
        var files = 0
        if let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(Self.keys), options: []) {
            for case let item as URL in enumerator {
                if isCancelled() { return SizeInfo(bytes: bytes, files: files, mtime: nil) }
                guard let values = try? item.resourceValues(forKeys: Self.keys) else { continue }
                if values.isRegularFile == true { files += 1 }
                bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }

        let info = SizeInfo(bytes: bytes, files: files, mtime: currentMtime(url.path))
        lock.lock(); cache[url.path] = info; lock.unlock()
        return info
    }

    func invalidate(under path: String) {
        lock.lock(); defer { lock.unlock() }
        for key in cache.keys where key == path || key.hasPrefix(path + "/") {
            cache.removeValue(forKey: key)
        }
    }

    // MARK: - Persistence

    private static var fileURL: URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return nil }
        let folder = dir.appendingPathComponent("Spaceful", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("sizecache.json")
    }

    /// Persist the cache off the main thread.
    func saveAsync() {
        lock.lock(); let snapshot = cache; lock.unlock()
        ioQueue.async {
            guard let url = Self.fileURL,
                  let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load() {
        guard let url = Self.fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: SizeInfo].self, from: data) else { return }
        lock.lock(); cache = decoded; lock.unlock()
    }
}
