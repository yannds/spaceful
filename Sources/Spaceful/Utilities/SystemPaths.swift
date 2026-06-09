import Foundation

/// Guards against destroying the operating system or the user's account.
///
/// Two levels of protection:
/// - **Critical**: OS-owned subtrees (`/System`, `/usr`, …). Never deletable, never
///   surfaced as cleanup suggestions — touching them can brick the Mac.
/// - **Essential**: top-level containers the user owns but should never delete *wholesale*
///   (`/Users`, the home folder, `~/Library`, `~/Documents`, …). Their *contents* remain
///   navigable and individually deletable; only the container itself is locked.
///
/// The deletion UI consults `isProtected` before ever offering a Trash action, and the
/// `Analyzer` skips protected paths entirely, so a stray `/Users` never gets a delete button.
enum SystemPaths {

    /// OS-owned prefixes whose entire subtree is off-limits.
    private static let criticalPrefixes: [String] = [
        "/System", "/usr", "/bin", "/sbin", "/Library/Apple",
        "/dev", "/cores", "/Network", "/.vol",
        "/private/var/db", "/private/var/folders/zz", "/private/var/vm"
    ]

    /// Exact paths that may be browsed but must never be deleted as a whole.
    private static let essentialExact: Set<String> = {
        var paths: Set<String> = [
            "/", "/System", "/Library", "/Users", "/private", "/opt",
            "/Applications", "/Volumes", "/Network", "/home", "/cores",
            "/bin", "/sbin", "/usr", "/etc", "/var", "/tmp",
            "/private/var", "/private/etc", "/private/tmp"
        ]
        let home = NSHomeDirectory()
        paths.insert(home)
        for sub in ["Library", "Documents", "Desktop", "Downloads", "Movies",
                    "Music", "Pictures", "Public", "Applications",
                    "Library/Mobile Documents", "Library/CloudStorage"] {
            paths.insert(home + "/" + sub)
        }
        return paths
    }()

    /// A standardized absolute path, with the common `/var`,`/tmp`,`/etc` symlinks resolved.
    private static func normalized(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// OS-owned subtree — must never be deleted *or even suggested*.
    static func isCritical(_ url: URL) -> Bool {
        let path = normalized(url)
        return criticalPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// True when this exact item must not be offered for deletion (critical OR an
    /// essential container). Items *inside* an essential container are not protected.
    static func isProtected(_ url: URL) -> Bool {
        if isCritical(url) { return true }
        let path = normalized(url)
        if essentialExact.contains(path) { return true }
        // Also lock anything sitting directly under the volume root (e.g. "/Foo"):
        // a one-component absolute path is always a top-level system container.
        let comps = path.split(separator: "/")
        if comps.count <= 1 { return true }
        return false
    }

    /// User-facing explanation for why the Trash action is unavailable.
    static func reason(for url: URL) -> String {
        isCritical(url)
            ? "Élément système macOS — protégé contre la suppression."
            : "Dossier essentiel — suppression du dossier lui-même désactivée. Son contenu reste supprimable individuellement."
    }
}
