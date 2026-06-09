import Foundation

/// Capacity snapshot of the volume a scanned path lives on. The headline number a
/// disk-space tool must always show: how much room is actually left.
struct DiskSpace: Equatable {
    let total: Int64
    let free: Int64

    var used: Int64 { max(0, total - free) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func forVolume(containing url: URL) -> DiskSpace? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        guard let v = try? url.resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity, total > 0 else { return nil }
        // `forImportantUsage` reflects space reclaimable for the user (incl. purgeable);
        // fall back to the raw available bytes if it's unavailable.
        let free = v.volumeAvailableCapacityForImportantUsage
            ?? Int64(v.volumeAvailableCapacity ?? 0)
        return DiskSpace(total: Int64(total), free: free)
    }

    /// The volume holding the user's home directory — the default headline.
    static var primary: DiskSpace? {
        forVolume(containing: FileManager.default.homeDirectoryForCurrentUser)
    }
}
