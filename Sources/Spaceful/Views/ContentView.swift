import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case explore = "Visualisation"
    case clean = "Nettoyage"
    var id: String { rawValue }
    var symbol: String { self == .explore ? "chart.pie" : "sparkles" }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Manual HSplitView instead of NavigationSplitView: on macOS 26 the latter's
        // sidebar column rendered empty. Three resizable panes — sidebar | content | inspector.
        HSplitView {
            SidebarView()
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 340, maxHeight: .infinity)

            VStack(spacing: 0) {
                PermissionBanner()
                mainArea
            }
            .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)

            InspectorView()
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 380, maxHeight: .infinity)
        }
        .frame(minWidth: 980, minHeight: 600)
        .overlay(alignment: .bottom) { toastOverlay }
        .navigationTitle("Spaceful — Visionneuse d'espace disque")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $model.tab) {
                    ForEach(MainTab.allCases) { t in
                        Label(t.rawValue, systemImage: t.symbol).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
            ToolbarItem(placement: .primaryAction) {
                if model.tab == .explore, model.focus != nil {
                    Picker("Vue", selection: $model.vizMode) {
                        ForEach(VizMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Basculer entre treemap et diagramme soleil")
                }
            }
        }
        .alert("Mettre à la corbeille ?", isPresented: deletionBinding, presenting: model.pendingDeletion) { _ in
            Button("Annuler", role: .cancel) { model.cancelDeletion() }
            Button("Mettre à la corbeille", role: .destructive) { model.confirmDeletion() }
        } message: { request in
            Text(deletionMessage(request))
        }
        .alert("Erreur", isPresented: errorBinding, presenting: model.errorMessage) { _ in
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { msg in Text(msg) }
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.permissions.refresh() }   // re-check after Settings toggle
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = model.toast {
            ToastView(toast: toast)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast?.id)
        }
    }

    @ViewBuilder
    private var mainArea: some View {
        if model.root == nil && !model.scanner.isSizing {
            EmptyStateView()
        } else if model.tab == .clean {
            SuggestionsView()
        } else {
            ExploreView()
        }
    }

    private func deletionMessage(_ request: DeletionRequest) -> String {
        if let node = request.single {
            return "« \(node.name) » (\(Format.bytes(node.size))) sera déplacé vers la corbeille. Récupérable depuis la corbeille ou via Annuler."
        }
        let count = request.nodes.count
        return "\(count) éléments (\(Format.bytes(request.totalSize))) seront déplacés vers la corbeille. Récupérables depuis la corbeille ou via Annuler."
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { model.pendingDeletion != nil },
                set: { if !$0 { model.cancelDeletion() } })
    }
    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }
}

/// Visualization + detail list for the current focus node.
private struct ExploreView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let focus = model.focus {
                Breadcrumb(focus: focus)
                Divider()

                VSplitView {
                    VStack(spacing: 0) {
                        Group {
                            switch model.vizMode {
                            case .treemap: TreemapView(node: focus)
                            case .sunburst: SunburstView(node: focus)
                            }
                        }
                        let cats = model.legendCategories
                        if !cats.isEmpty {
                            Divider()
                            VizLegend(categories: cats)
                        }
                    }
                    .frame(minHeight: 240)

                    DetailListView(node: focus)
                        .frame(minHeight: 160)
                }
            } else if model.scanner.isSizing {
                Spacer()
                ProgressView("Ouverture…")
                Spacer()
            }
        }
        .background(KeyboardShortcuts())
    }
}

/// Invisible buttons that give the explore view standard macOS keyboard navigation:
/// ↑/↓ move the selection, ⌘↓ drills in, ⌘↑ goes up, ⌘⌫ trashes the selection.
private struct KeyboardShortcuts: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            shortcut(.upArrow, modifiers: []) { model.keyboardMoveSelection(-1) }
            shortcut(.downArrow, modifiers: []) { model.keyboardMoveSelection(1) }
            shortcut(.downArrow, modifiers: .command) { model.drillIntoSelection() }
            shortcut(.upArrow, modifiers: .command) { model.goUp() }
            shortcut(.delete, modifiers: .command) {
                if let sel = model.selection { model.requestDeletion(sel) }
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func shortcut(_ key: KeyEquivalent, modifiers: EventModifiers, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Color.clear }
            .buttonStyle(.plain)
            .keyboardShortcut(key, modifiers: modifiers)
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 56)).foregroundStyle(.tint)
            Text("Visionneuse d'espace disque").font(.title2.bold())
            Text("Choisissez un emplacement à analyser dans la barre latérale.\nVisualisez ce qui prend de la place, puis nettoyez en toute sécurité.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("Astuce : pour analyser tout le disque, activez l'« Accès complet au disque » pour cette app dans Réglages Système ▸ Confidentialité et sécurité.")
                .font(.caption).multilineTextAlignment(.center).foregroundStyle(.tertiary)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
