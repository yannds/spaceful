import SwiftUI
import AppKit

/// Sidebar built from a plain ScrollView/VStack rather than a `List`. On macOS 26 a
/// `List(.sidebar)` inside this NavigationSplitView rendered empty; a VStack of rows is
/// simple and always shows.
struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    private let places = ScanTarget.targets(in: .places)
    private let cleanup = ScanTarget.targets(in: .cleanup)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if let space = model.diskSpace {
                    DiskGaugeView(space: space)
                        .padding(.bottom, 4)
                }

                header("Emplacements")
                ForEach(places) { Row(target: $0) }

                header("Nettoyage rapide")
                ForEach(cleanup) { Row(target: $0) }

                Divider().padding(.vertical, 8)

                Button(action: chooseFolder) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus").frame(width: 20)
                        Text("Choisir un dossier…")
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .safeAreaInset(edge: .bottom) { progressFooter }
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 12).padding(.bottom, 2)
    }

    @ViewBuilder
    private var progressFooter: some View {
        if model.scanner.isSizing || model.analyzer.isAnalyzing {
            VStack(alignment: .leading, spacing: 6) {
                if model.scanner.isSizing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Calcul des tailles…").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if model.analyzer.isAnalyzing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Analyse… \(model.analyzer.scannedItems) éléments")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button("Arrêter") { model.analyzer.cancel() }.controlSize(.mini)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Analyser"
        if panel.runModal() == .OK, let url = panel.url {
            model.startScan(url)
        }
    }
}

/// A single clickable sidebar entry with hover + selected highlighting.
private struct Row: View {
    @EnvironmentObject var model: AppModel
    let target: ScanTarget
    @State private var hovering = false

    private var isCurrent: Bool { model.root?.url.path == target.url.path }

    var body: some View {
        Button {
            // "Nettoyage rapide" shortcuts truly clean: scan + analyze + switch tab.
            if target.group == .cleanup { model.scanAndClean(target.url) }
            else { model.startScan(target.url) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: target.symbol)
                    .frame(width: 20)
                    .foregroundStyle(isCurrent ? Color.white : Color.accentColor)
                Text(target.title)
                    .foregroundStyle(isCurrent ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? Color.accentColor
                          : hovering ? Color.secondary.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(target.url.path)
    }
}
