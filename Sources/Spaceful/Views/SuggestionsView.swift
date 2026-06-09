import SwiftUI

/// "Nettoyage" tab: reclaimable space grouped by category, with per-item *and* batch trash.
struct SuggestionsView: View {
    @EnvironmentObject var model: AppModel

    private var totalReclaimable: Int64 {
        model.analyzer.groups.reduce(0) { $0 + $1.totalSize }
    }

    private var allItems: [Suggestion] {
        model.analyzer.groups.flatMap { $0.items }
    }
    private var selectedItems: [Suggestion] {
        allItems.filter { model.cleanupSelection.contains($0.id) }
    }
    private var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !selectedItems.isEmpty { selectionBar; Divider() }
            if model.analyzer.isAnalyzing {
                Spacer()
                ProgressView("Analyse des fichiers à nettoyer…")
                Spacer()
            } else if model.analyzer.groups.isEmpty {
                Spacer()
                ContentUnavailableLikeView()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.analyzer.groups) { group in
                            GroupCard(group: group)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading) {
                Text("Espace récupérable").font(.headline)
                Text(model.analyzer.isAnalyzing ? "Analyse en cours…"
                     : "≈ \(Format.bytes(totalReclaimable)) à libérer")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if model.analyzer.isAnalyzing {
                Button("Arrêter") { model.analyzer.cancel() }
            } else {
                if !model.analyzer.groups.isEmpty {
                    Button(allSelected ? "Tout désélectionner" : "Tout sélectionner") {
                        toggleSelectAll()
                    }
                    .controlSize(.small)
                }
                Button {
                    model.analyzeCleanup()
                } label: {
                    Label(model.analyzer.groups.isEmpty ? "Analyser" : "Réanalyser", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.root == nil)
            }
        }
        .padding(14)
    }

    /// Sticky action bar shown when items are checked — one confirmation for the whole batch.
    private var selectionBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            Text("\(selectedItems.count) sélectionné(s) · \(Format.bytes(selectedSize))")
                .font(.callout)
            Spacer()
            Button("Désélectionner") { model.cleanupSelection.removeAll() }
                .controlSize(.small)
            Button {
                model.requestBatchDeletion(selectedItems.map { $0.node })
            } label: {
                Label("Mettre à la corbeille", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent).tint(.red)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.bar)
    }

    private var allSelected: Bool {
        !allItems.isEmpty && model.cleanupSelection.count == allItems.count
    }
    private func toggleSelectAll() {
        if allSelected { model.cleanupSelection.removeAll() }
        else { model.cleanupSelection = Set(allItems.map { $0.id }) }
    }
}

private struct GroupCard: View {
    @EnvironmentObject var model: AppModel
    let group: SuggestionGroup
    @State private var expanded = false

    private var selectedInGroup: Int {
        group.items.filter { model.cleanupSelection.contains($0.id) }.count
    }
    private var allInGroupSelected: Bool {
        !group.items.isEmpty && selectedInGroup == group.items.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                checkbox(on: allInGroupSelected, partial: selectedInGroup > 0 && !allInGroupSelected) {
                    toggleGroup()
                }
                Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: group.symbol).font(.title3).frame(width: 26)
                            .foregroundStyle(safetyColor)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(group.title).font(.headline)
                                safetyBadge
                            }
                            Text(group.blurb).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(Format.bytes(group.totalSize)).font(.callout.monospacedDigit().bold())
                            Text("\(group.items.count) éléments").font(.caption2).foregroundStyle(.secondary)
                        }
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            if expanded {
                Divider()
                ForEach(group.items) { item in
                    SuggestionRow(item: item)
                    Divider().padding(.leading, 12)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
    }

    private func toggleGroup() {
        let ids = group.items.map { $0.id }
        if allInGroupSelected { ids.forEach { model.cleanupSelection.remove($0) } }
        else { ids.forEach { model.cleanupSelection.insert($0) } }
    }

    private func checkbox(on: Bool, partial: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: on ? "checkmark.circle.fill" : partial ? "minus.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(on || partial ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(on ? "Tout désélectionner dans ce groupe" : "Tout sélectionner dans ce groupe")
    }

    private var safetyColor: Color {
        switch group.safety {
        case .safe: return .green
        case .review: return .blue
        case .caution: return .orange
        }
    }

    private var safetyBadge: some View {
        let text: String
        switch group.safety {
        case .safe: text = "Sans risque"
        case .review: text = "À vérifier"
        case .caution: text = "Prudence"
        }
        return Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(safetyColor.opacity(0.18)))
            .foregroundStyle(safetyColor)
    }
}

private struct SuggestionRow: View {
    @EnvironmentObject var model: AppModel
    let item: Suggestion

    private var isSelected: Bool { model.cleanupSelection.contains(item.id) }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if isSelected { model.cleanupSelection.remove(item.id) }
                else { model.cleanupSelection.insert(item.id) }
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.node.name).lineLimit(1).truncationMode(.middle)
                Text(item.subtitle).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(Format.bytes(item.size)).font(.callout.monospacedDigit())
            Button { FileActions.revealInFinder(item.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Afficher dans le Finder")
            Button { model.requestDeletion(item.node) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).foregroundStyle(.red).help("Mettre à la corbeille")
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.node.name), \(Format.bytes(item.size)), \(item.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Lightweight stand-in so we don't depend on ContentUnavailableView availability.
private struct ContentUnavailableLikeView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.tint)
            Text("Analyse du nettoyage").font(.headline)
            Text("Cliquez sur « Analyser » en haut à droite pour détecter caches, doublons et fichiers inutilisés dans l'emplacement courant.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
        }
    }
}
