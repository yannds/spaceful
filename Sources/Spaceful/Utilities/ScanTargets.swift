import Foundation

/// A one-click place to analyze, shown in the sidebar.
struct ScanTarget: Identifiable, Hashable {
    enum Group: String, CaseIterable {
        case places = "Emplacements"
        case cleanup = "Nettoyage rapide"
    }

    let id = UUID()
    let title: String
    let symbol: String
    let url: URL
    var group: Group

    /// The essentials first: the user's home, all users, and the whole disk — then the
    /// usual cleanup spots (caches, logs, downloads, trash).
    static var all: [ScanTarget] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func h(_ path: String) -> URL { home.appendingPathComponent(path) }
        let userName = NSUserName()

        let candidates: [ScanTarget] = [
            ScanTarget(title: "Maison (\(userName))", symbol: "house", url: home, group: .places),
            ScanTarget(title: "Utilisateurs", symbol: "person.2", url: URL(fileURLWithPath: "/Users"), group: .places),
            ScanTarget(title: "Macintosh HD", symbol: "internaldrive", url: URL(fileURLWithPath: "/"), group: .places),

            ScanTarget(title: "Caches", symbol: "shippingbox", url: h("Library/Caches"), group: .cleanup),
            ScanTarget(title: "Journaux (Logs)", symbol: "doc.text", url: h("Library/Logs"), group: .cleanup),
            ScanTarget(title: "Téléchargements", symbol: "arrow.down.circle", url: h("Downloads"), group: .cleanup),
            ScanTarget(title: "Corbeille", symbol: "trash", url: h(".Trash"), group: .cleanup),
            ScanTarget(title: "DerivedData (Xcode)", symbol: "hammer",
                       url: h("Library/Developer/Xcode/DerivedData"), group: .cleanup)
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    static func targets(in group: Group) -> [ScanTarget] {
        all.filter { $0.group == group }
    }
}
