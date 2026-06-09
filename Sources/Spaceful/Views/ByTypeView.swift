import SwiftUI

/// "Types" tab: a flat, sortable breakdown of disk usage by file category.
struct ByTypeView: View {
    @EnvironmentObject var model: AppModel

    enum Sort: String, CaseIterable, Identifiable {
        case size = "Taille", count = "Nombre", name = "Nom"
        var id: String { rawValue }
    }
    @State private var sort: Sort = .size

    private var rows: [CategoryTotal] {
        let r = model.indexer.categoryTotals
        switch sort {
        case .size:  return r.sorted { $0.size > $1.size }
        case .count: return r.sorted { $0.count > $1.count }
        case .name:  return r.sorted { $0.category.label < $1.category.label }
        }
    }
    private var maxSize: Int64 { model.indexer.categoryTotals.map(\.size).max() ?? 1 }

    var body: some View {
        VStack(spacing: 0) {
            IndexHeader(title: "Répartition par type",
                        subtitle: "\(Format.bytes(model.indexer.grandTotal)) au total",
                        trailing: AnyView(sortPicker))
            Divider()
            content
        }
        .onAppear { model.ensureIndexed() }
    }

    private var sortPicker: some View {
        Picker("Trier", selection: $sort) {
            ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.menu).fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        if model.indexer.isIndexing {
            Spacer(); ProgressView("Indexation… \(model.indexer.scanned) éléments"); Spacer()
        } else if model.indexer.categoryTotals.isEmpty {
            Spacer(); IndexEmptyView(); Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        CategoryRow(total: row, fraction: Double(row.size) / Double(max(maxSize, 1)))
                            .contentShape(Rectangle())
                            .onTapGesture { model.indexer.focusCategory = row.category; model.tab = .biggest }
                        Divider()
                    }
                }
            }
        }
    }
}

private struct CategoryRow: View {
    let total: CategoryTotal
    let fraction: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: total.category.symbol)
                .foregroundStyle(total.category.color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(total.category.label).fontWeight(.medium)
                    Spacer()
                    Text(Format.bytes(total.size)).font(.callout.monospacedDigit())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12))
                        RoundedRectangle(cornerRadius: 3).fill(total.category.color)
                            .frame(width: max(3, geo.size.width * fraction))
                    }
                }
                .frame(height: 6)
                Text("\(total.count) fichier\(total.count > 1 ? "s" : "")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(total.category.label), \(Format.bytes(total.size)), \(total.count) fichiers")
    }
}

/// Shared header for the index-backed tabs (Types / Volumineux).
struct IndexHeader: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let subtitle: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(model.indexer.isIndexing ? "Indexation en cours…" : subtitle)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if let trailing { trailing }
            if model.indexer.isIndexing {
                Button("Arrêter") { model.indexer.cancel() }
            } else {
                Button { model.buildIndex() } label: {
                    Label(model.indexer.hasData ? "Réanalyser" : "Analyser", systemImage: "arrow.clockwise")
                }
                .disabled(model.root == nil)
            }
        }
        .padding(14)
    }
}

struct IndexEmptyView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal").font(.largeTitle).foregroundStyle(.tint)
            Text("Indexation").font(.headline)
            Text("Parcourt l'emplacement courant pour répartir l'espace par type et lister les plus gros fichiers.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
        }
    }
}
