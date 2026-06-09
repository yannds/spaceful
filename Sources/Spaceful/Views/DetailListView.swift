import SwiftUI

/// Sorted, bar-chart list of the focus node's children. Mirrors the visualization:
/// click selects, double-click drills, with per-row reveal / trash actions.
struct DetailListView: View {
    @EnvironmentObject var model: AppModel
    let node: FileNode

    private var rows: [FileNode] { node.childrenBySize }
    private var maxSize: Int64 { rows.first?.size ?? 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(rows.count) éléments")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Format.bytes(node.size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            if rows.isEmpty {
                Spacer()
                Text("Dossier vide").foregroundStyle(.secondary).font(.callout)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { child in
                            DetailRow(child: child, fraction: Double(child.size) / Double(max(maxSize, 1)))
                                .background(child.id == model.selection?.id ? Color.accentColor.opacity(0.15) : .clear)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { model.selection = child; model.drill(into: child) }
                                .onTapGesture { model.selection = child }
                                .contextMenu { rowMenu(child) }
                            Divider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ child: FileNode) -> some View {
        if child.isDirectory && !child.isBundle && !child.children.isEmpty {
            Button("Ouvrir ici") { model.drill(into: child) }
        }
        Button("Afficher dans le Finder") { FileActions.revealInFinder(child.url) }
        Button("Ouvrir") { FileActions.open(child.url) }
        Divider()
        if child.isProtected {
            Label("Protégé — suppression désactivée", systemImage: "lock.fill")
        } else {
            Button("Mettre à la corbeille…", role: .destructive) { model.requestDeletion(child) }
        }
    }
}

private struct DetailRow: View {
    @EnvironmentObject var model: AppModel
    let child: FileNode
    let fraction: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(child.isDirectory ? Color.accentColor : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(child.name).lineLimit(1).truncationMode(.middle)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.12))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(child.category.color)
                            .frame(width: max(2, geo.size.width * fraction))
                    }
                }
                .frame(height: 4)
            }
            VStack(alignment: .trailing, spacing: 2) {
                if child.isSizing {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("calcul…").font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text(Format.bytes(child.size)).font(.callout.monospacedDigit())
                }
                Text(Format.relativeDate(child.modificationDate))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .trailing)
            if child.isProtected {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.tertiary)
                    .help(SystemPaths.reason(for: child.url))
            } else {
                Button { model.requestDeletion(child) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Mettre à la corbeille")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(child.accessibilityDescription)
    }

    private var icon: String {
        if child.isSymlink { return "arrow.up.right.square" }
        if child.isBundle { return "app" }
        if child.isDirectory { return "folder.fill" }
        return "doc"
    }
}
