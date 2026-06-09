import SwiftUI

/// "Volumineux" tab: a flat, searchable, sortable list of the largest individual files,
/// with per-row reveal / trash (protected paths excluded).
struct BiggestFilesView: View {
    @EnvironmentObject var model: AppModel

    enum Sort: String, CaseIterable, Identifiable {
        case size = "Taille", name = "Nom", date = "Date"
        var id: String { rawValue }
    }
    enum AgeFilter: String, CaseIterable, Identifiable {
        case any = "Tout âge", m1 = "> 1 mois", m6 = "> 6 mois", y1 = "> 1 an"
        var id: String { rawValue }
        var seconds: TimeInterval? {
            switch self {
            case .any: return nil
            case .m1:  return .days(30)
            case .m6:  return .days(182)
            case .y1:  return .days(365)
            }
        }
    }
    enum MinSize: String, CaseIterable, Identifiable {
        case any = "Toutes", mb50 = "≥ 50 Mo", mb100 = "≥ 100 Mo", mb500 = "≥ 500 Mo", gb1 = "≥ 1 Go"
        var id: String { rawValue }
        var bytes: Int64 {
            switch self {
            case .any: return 0
            case .mb50: return 50.MB
            case .mb100: return 100.MB
            case .mb500: return 500.MB
            case .gb1: return 1.GB
            }
        }
    }

    @State private var query = ""
    @State private var sort: Sort = .size
    @State private var age: AgeFilter = .any
    @State private var minSize: MinSize = .any
    @State private var category: FileCategory?

    private var filtered: [IndexedFile] {
        let now = Date()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var list = model.indexer.largest.filter { f in
            if f.size < minSize.bytes { return false }
            if let cat = category, f.category != cat { return false }
            if let maxAge = age.seconds {
                guard let d = f.modDate, now.timeIntervalSince(d) > maxAge else { return false }
            }
            if !q.isEmpty, !f.name.lowercased().contains(q), !f.ext.contains(q) { return false }
            return true
        }
        switch sort {
        case .size: list.sort { $0.size > $1.size }
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .date: list.sort { ($0.modDate ?? .distantPast) > ($1.modDate ?? .distantPast) }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            IndexHeader(title: "Les plus gros fichiers",
                        subtitle: "\(model.indexer.largest.count) fichiers indexés")
            Divider()
            if model.indexer.isIndexing {
                Spacer(); ProgressView("Indexation… \(model.indexer.scanned) éléments"); Spacer()
            } else if model.indexer.largest.isEmpty {
                Spacer(); IndexEmptyView(); Spacer()
            } else {
                filterBar
                Divider()
                resultsList
            }
        }
        .onAppear {
            model.ensureIndexed()
            if let c = model.indexer.focusCategory { category = c; model.indexer.focusCategory = nil }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher par nom ou extension…", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

            HStack(spacing: 8) {
                menu("Taille", MinSize.allCases, $minSize) { $0.rawValue }
                menu("Âge", AgeFilter.allCases, $age) { $0.rawValue }
                categoryMenu
                Spacer()
                menu("Trier", Sort.allCases, $sort) { "Tri : \($0.rawValue)" }
            }
            .font(.caption)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func menu<T: Hashable & Identifiable>(_ label: String, _ options: [T],
                                                  _ binding: Binding<T>,
                                                  _ title: @escaping (T) -> String) -> some View {
        Picker(label, selection: binding) {
            ForEach(options) { Text(title($0)).tag($0) }
        }
        .pickerStyle(.menu).fixedSize()
    }

    private var categoryMenu: some View {
        Menu {
            Button("Tous les types") { category = nil }
            Divider()
            ForEach(presentCategories, id: \.self) { c in
                Button { category = c } label: { Label(c.label, systemImage: c.symbol) }
            }
        } label: {
            Label(category?.label ?? "Type", systemImage: "line.3.horizontal.decrease.circle")
        }
        .fixedSize()
    }
    private var presentCategories: [FileCategory] {
        let present = Set(model.indexer.largest.map(\.category))
        return FileCategory.allCases.filter { present.contains($0) }
    }

    private var resultsList: some View {
        Group {
            let rows = filtered
            if rows.isEmpty {
                Spacer(); Text("Aucun fichier ne correspond aux filtres.")
                    .foregroundStyle(.secondary).font(.callout); Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        HStack {
                            Text("\(rows.count) résultats").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(Format.bytes(rows.reduce(0) { $0 + $1.size }))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        Divider()
                        ForEach(rows) { file in
                            FileRow(file: file)
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
        }
    }
}

private struct FileRow: View {
    @EnvironmentObject var model: AppModel
    let file: IndexedFile

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.category.symbol)
                .foregroundStyle(file.category.color).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).lineLimit(1).truncationMode(.middle)
                Text(file.url.deletingLastPathComponent().path)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.bytes(file.size)).font(.callout.monospacedDigit())
                Text(Format.relativeDate(file.modDate)).font(.caption2).foregroundStyle(.secondary)
            }
            Button { FileActions.revealInFinder(file.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Afficher dans le Finder")
            if file.isProtected {
                Image(systemName: "lock.fill").foregroundStyle(.tertiary)
                    .help(SystemPaths.reason(for: file.url))
            } else {
                Button { model.requestDeletion(node(for: file)) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(.red).help("Mettre à la corbeille")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { FileActions.revealInFinder(file.url) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(file.name), \(file.category.label), \(Format.bytes(file.size))")
    }

    /// Wrap an indexed file in a transient FileNode so it flows through the shared
    /// deletion pipeline (confirmation, trash, undo).
    private func node(for f: IndexedFile) -> FileNode {
        FileNode(url: f.url, name: f.name, isDirectory: f.isDirectory, isSymlink: false,
                 isBundle: f.isBundle, modificationDate: f.modDate,
                 ownSize: f.size, size: f.size, fileCount: 1, parent: nil, children: [])
    }
}
