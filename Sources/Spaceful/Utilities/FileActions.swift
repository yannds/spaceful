import Foundation
import AppKit

/// File-system side effects requested from the UI. Deletions go to the Trash so they
/// are recoverable; nothing is ever `rm`-ed permanently.
enum FileActions {
    enum ActionError: LocalizedError {
        case trashFailed(URL, Error)
        case protected(URL)
        case restoreFailed(URL)
        var errorDescription: String? {
            switch self {
            case let .trashFailed(url, error):
                return "Impossible de mettre « \(url.lastPathComponent) » à la corbeille : \(error.localizedDescription)"
            case let .protected(url):
                return SystemPaths.reason(for: url)
            case let .restoreFailed(url):
                return "Impossible de restaurer « \(url.lastPathComponent) »."
            }
        }
    }

    /// Move a file or directory to the Trash. Returns the resulting Trash URL.
    /// Refuses protected system/essential paths outright.
    @discardableResult
    static func moveToTrash(_ url: URL) throws -> URL? {
        guard !SystemPaths.isProtected(url) else { throw ActionError.protected(url) }
        var resultURL: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultURL)
            return resultURL as URL?
        } catch {
            throw ActionError.trashFailed(url, error)
        }
    }

    /// Put a previously trashed item back at its original location (Undo).
    static func restoreFromTrash(_ receipt: TrashReceipt) throws {
        guard let trashed = receipt.trashed else { throw ActionError.restoreFailed(receipt.original) }
        // Don't clobber anything that reappeared at the destination meanwhile.
        guard !FileManager.default.fileExists(atPath: receipt.original.path) else {
            throw ActionError.restoreFailed(receipt.original)
        }
        try FileManager.default.moveItem(at: trashed, to: receipt.original)
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
