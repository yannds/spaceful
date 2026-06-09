import Foundation

/// All tunables for `Analyzer` in one place — no magic numbers scattered through the
/// detection logic. Injectable so the thresholds can be tuned or unit-tested.
struct AnalyzerConfig {
    /// A file at or above this size is flagged as "large".
    var largeFileThreshold: Int64 = 200.MB
    /// Files untouched longer than this (outside Downloads) are flagged as "old".
    var oldFileAge: TimeInterval = .days(365)
    /// Shorter staleness window applied inside the Downloads folder.
    var downloadsOldAge: TimeInterval = .days(90)
    /// Ignore cache directories smaller than this.
    var minCacheSize: Int64 = 1.MB
    /// Ignore dev-artifact directories smaller than this.
    var minDevJunkSize: Int64 = 5.MB
    /// Only consider "old" files above this size (small old files aren't worth it).
    var oldFileMinSize: Int64 = 10.MB
    /// Only hash files at or above this size when hunting duplicates.
    var duplicateMinSize: Int64 = 1.MB
    /// Bytes read from each candidate to compute its dedup fingerprint.
    var fingerprintBytes: Int = 256 * 1024
    /// Cap on items surfaced per group, to keep the UI responsive.
    var maxItemsPerGroup = 50
    /// Cap specific to the duplicates group.
    var maxDuplicates = 100

    /// Directory names treated as disposable cache/log data.
    var cacheDirectoryNames: Set<String> = ["Caches", "Cache", "Logs", "GPUCache", "Code Cache", "tmp"]
    /// Directory names treated as regenerable development artifacts.
    var devArtifactNames: Set<String> = ["node_modules", "DerivedData", ".gradle", "Pods", "target", ".venv", "__pycache__"]

    static let `default` = AnalyzerConfig()
}
