import Foundation
import AppKit
import Combine

/// Tracks whether the app has macOS **Full Disk Access** — the single, one-time grant
/// that lets a disk tool read every protected location without per-folder TCC prompts.
///
/// There is no public API to query TCC status, so we probe it: the user's TCC database
/// is only openable *with* Full Disk Access. If we can open it, the grant is in place.
@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var hasFullDiskAccess = false

    init() { refresh() }

    func refresh() {
        hasFullDiskAccess = Self.probeFullDiskAccess()
    }

    /// Opens System Settings ▸ Privacy & Security ▸ Full Disk Access directly.
    func openFullDiskAccessSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func probeFullDiskAccess() -> Bool {
        let candidates = [
            "\(NSHomeDirectory())/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Application Support/com.apple.TCC/TCC.db"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            if let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) {
                try? handle.close()
                return true
            }
        }
        return false
    }
}
