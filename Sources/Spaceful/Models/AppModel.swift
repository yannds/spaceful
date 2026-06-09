import Foundation
import SwiftUI
import Combine

enum VizMode: String, CaseIterable, Identifiable {
    case treemap = "Treemap"
    case sunburst = "Soleil"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .treemap: return "square.grid.2x2"
        case .sunburst: return "circle.circle"
        }
    }
}

/// Central observable state shared by every view. Owns the two engines and forwards
/// their updates so views need only observe `AppModel`.
///
/// Navigation (`ScanEngine`) and cleanup analysis (`Analyzer`) run **independently**:
/// opening a folder is instant and sizes fill in progressively, while a separate
/// background pass feeds the "Nettoyage" tab without ever blocking the UI.
@MainActor
final class AppModel: ObservableObject {
    let scanner = ScanEngine()
    let analyzer = Analyzer()
    let permissions = PermissionManager()

    @Published var focus: FileNode?
    @Published var selection: FileNode?
    @Published var vizMode: VizMode = .treemap
    @Published var tab: MainTab = .explore
    @Published var errorMessage: String?
    @Published var pendingDeletion: DeletionRequest?
    @Published var toast: ToastState?
    @Published private(set) var diskSpace: DiskSpace?

    /// Checked suggestions in the cleanup tab (by `Suggestion.id`), for batch trashing.
    @Published var cleanupSelection: Set<UUID> = []

    private var cancellables = Set<AnyCancellable>()
    private var toastDismissTask: Task<Void, Never>?

    init() {
        // Bridge nested engine updates up to this model so views observing AppModel
        // refresh as sizes/suggestions arrive.
        scanner.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        analyzer.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        permissions.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        diskSpace = DiskSpace.primary
    }

    var root: FileNode? { scanner.root }

    func refreshDiskSpace() {
        diskSpace = scanner.root.flatMap { DiskSpace.forVolume(containing: $0.url) } ?? DiskSpace.primary
    }

    /// Distinct categories present under the current focus, for the legend.
    var legendCategories: [FileCategory] {
        guard let focus else { return [] }
        return VizLegend.categories(in: focus)
    }

    // MARK: - Scanning & navigation

    func startScan(_ url: URL) {
        selection = nil
        scanner.openRoot(url: url)        // instant: lists + sizes top level in background
        focus = scanner.root
        refreshDiskSpace()
        // Cleanup analysis is no longer automatic: it walks the whole subtree (a second
        // pass that would double the permission prompts). The user triggers it explicitly
        // from the "Nettoyage" tab via `analyzeCleanup()`.
    }

    /// Scan a location *and* immediately run cleanup on it, switching to the Nettoyage
    /// tab — the truthful behaviour for the sidebar's "Nettoyage rapide" shortcuts.
    func scanAndClean(_ url: URL) {
        startScan(url)
        tab = .clean
        analyzeCleanup()
    }

    func keyboardMoveSelection(_ delta: Int) {
        guard let focus else { return }
        let items = focus.childrenBySize
        guard !items.isEmpty else { return }
        if let current = selection, let i = items.firstIndex(where: { $0 === current }) {
            let next = min(max(i + delta, 0), items.count - 1)
            selection = items[next]
        } else {
            selection = items.first
        }
    }

    func drillIntoSelection() {
        if let sel = selection { drill(into: sel) }
    }

    /// Run the cleanup analysis on the current root (explicit, user-initiated).
    func analyzeCleanup() {
        guard let url = scanner.root?.url else { return }
        analyzer.analyze(url: url)
    }

    func drill(into node: FileNode) {
        guard node.isDirectory, !node.isBundle else { return }
        scanner.open(node)                // lazily load + size this level
        focus = node
        selection = nil
    }

    func navigate(to node: FileNode) {
        scanner.open(node)
        focus = node
        selection = nil
    }

    func goUp() {
        if let parent = focus?.parent { navigate(to: parent) }
    }

    // MARK: - Deletion (always to Trash, after confirmation; never system paths)

    /// Request to trash a single node. Silently refused for protected system/essential
    /// paths — the UI never shows a Trash button for those, this is defense in depth.
    func requestDeletion(_ node: FileNode) {
        guard !node.isProtected else {
            errorMessage = SystemPaths.reason(for: node.url)
            return
        }
        pendingDeletion = DeletionRequest(nodes: [node])
    }

    /// Request to trash several nodes at once (cleanup batch). Protected paths are dropped.
    func requestBatchDeletion(_ nodes: [FileNode]) {
        let deletable = nodes.filter { !$0.isProtected }
        guard !deletable.isEmpty else { return }
        pendingDeletion = DeletionRequest(nodes: deletable)
    }

    func cancelDeletion() { pendingDeletion = nil }

    func confirmDeletion() {
        guard let request = pendingDeletion else { return }
        pendingDeletion = nil

        let previousGroups = analyzer.groups          // snapshot for undo
        var receipts: [TrashReceipt] = []
        var failures: [String] = []

        for node in request.nodes where !node.isProtected {
            do {
                let trashed = try FileActions.moveToTrash(node.url)
                receipts.append(TrashReceipt(original: node.url, trashed: trashed, size: node.size))
                if focus === node, let parent = node.parent { focus = parent }
                if selection === node { selection = nil }
                node.detachFromParent()
                scanner.invalidateCache(under: node.url.path)
                pruneSuggestions(matching: node)
            } catch {
                failures.append(error.localizedDescription)
            }
        }

        cleanupSelection.removeAll()
        refreshDiskSpace()
        objectWillChange.send()

        if let first = failures.first { errorMessage = first }
        if !receipts.isEmpty { presentUndoToast(receipts, previousGroups: previousGroups) }
    }

    private func pruneSuggestions(matching node: FileNode) {
        analyzer.removeItems { $0.node === node || $0.url.path.hasPrefix(node.url.path + "/") }
    }

    // MARK: - Undo

    private func presentUndoToast(_ receipts: [TrashReceipt], previousGroups: [SuggestionGroup]) {
        let freed = receipts.reduce(0) { $0 + $1.size }
        let count = receipts.count
        let noun = count == 1 ? "élément mis à la corbeille" : "éléments mis à la corbeille"
        let message = "\(count) \(noun) · \(Format.bytes(freed)) libérés"

        toast = ToastState(message: message) { [weak self] in
            self?.undo(receipts: receipts, restoringGroups: previousGroups)
        }
        scheduleToastDismiss()
    }

    private func scheduleToastDismiss() {
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.toast = nil }
        }
    }

    func dismissToast() {
        toastDismissTask?.cancel()
        toast = nil
    }

    /// Restore trashed files to their original location and rebuild the affected views.
    private func undo(receipts: [TrashReceipt], restoringGroups: [SuggestionGroup]) {
        var restoredAny = false
        for receipt in receipts {
            if (try? FileActions.restoreFromTrash(receipt)) != nil { restoredAny = true }
        }
        if restoredAny {
            analyzer.restore(groups: restoringGroups)
            if let focus { scanner.reload(focus) }      // re-list the current level from disk
            refreshDiskSpace()
        }
        dismissToast()
        objectWillChange.send()
    }
}

/// A pending Trash operation: one or many nodes, confirmed via a single alert.
struct DeletionRequest: Identifiable {
    let id = UUID()
    let nodes: [FileNode]
    var isBatch: Bool { nodes.count > 1 }
    var totalSize: Int64 { nodes.reduce(0) { $0 + $1.size } }
    var single: FileNode? { nodes.count == 1 ? nodes.first : nil }
}

/// What's needed to put one trashed item back where it was.
struct TrashReceipt {
    let original: URL
    let trashed: URL?
    let size: Int64
}

/// A transient confirmation banner with an Undo action.
struct ToastState: Identifiable {
    let id = UUID()
    let message: String
    let undo: () -> Void
}

/// Type-driven colour and protection, shared by every visualization.
extension FileNode {
    /// Meaningful category (Photos, Vidéos, Code…) used to colour the space it occupies.
    var category: FileCategory { FileCategory.of(node: self) }

    /// Hue used by the detail-list bar — derived from the category, not a random hash.
    var hue: Double { category.color.hueComponent }

    func color(depth: Int) -> Color {
        if isSymlink { return Color.gray.opacity(0.4) }
        return category.color(depth: depth)
    }

    /// Whether dark text is more legible on this node's tile at the given depth.
    func prefersDarkText(depth: Int) -> Bool {
        if isSymlink { return true }
        return category.prefersDarkText(depth: depth)
    }

    /// True when this exact item must not be offered for deletion (system/essential).
    var isProtected: Bool { SystemPaths.isProtected(url) }

    /// VoiceOver description: "Photos, dossier, 1,2 Go, 34 % du parent".
    var accessibilityDescription: String {
        var parts = [name, category.label, Format.bytes(size)]
        if let parent, parent.size > 0 {
            parts.append(Format.percent(Double(size) / Double(parent.size)) + " du parent")
        }
        return parts.joined(separator: ", ")
    }
}

private extension Color {
    /// HSB hue of a colour, for the legacy bar tint helper.
    var hueComponent: Double {
        #if canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? .gray
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Double(h)
        #else
        return 0.5
        #endif
    }
}
