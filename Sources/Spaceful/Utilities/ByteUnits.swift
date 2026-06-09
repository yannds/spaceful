import Foundation

/// Readable byte-size literals so thresholds read as `200.MB` instead of
/// `200 * 1024 * 1024`. Defined on `Int` (the default literal type) and returning
/// `Int64` so `200.MB` slots straight into size fields. Uses binary multiples.
extension Int {
    var KB: Int64 { Int64(self) * 1024 }
    var MB: Int64 { Int64(self) * 1024 * 1024 }
    var GB: Int64 { Int64(self) * 1024 * 1024 * 1024 }
}

/// Readable time spans for age-based thresholds.
extension TimeInterval {
    static func days(_ count: Double) -> TimeInterval { count * 86_400 }
}
