import SwiftUI

/// Right-hand details panel for the currently selected node.
struct InspectorView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let node = model.selection ?? model.focus {
                content(for: node)
            } else {
                Spacer()
                Text("Sélectionnez un élément").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func content(for node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon(node)).font(.title)
                    .foregroundStyle(node.category.color)
                VStack(alignment: .leading) {
                    Text(node.name).font(.headline).lineLimit(2).truncationMode(.middle)
                    Text(node.category.label)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                infoRow("Taille", Format.bytes(node.size))
                if node.isDirectory { infoRow("Éléments", "\(node.fileCount)") }
                infoRow("Modifié", Format.relativeDate(node.modificationDate))
                if let parent = node.parent, parent.size > 0 {
                    infoRow("Part du parent", Format.percent(Double(node.size) / Double(parent.size)))
                }
            }

            Text(node.url.path)
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled).lineLimit(4).truncationMode(.middle)

            Divider()

            VStack(spacing: 8) {
                if node.isDirectory && !node.isBundle && !node.children.isEmpty {
                    actionButton("Explorer", "arrow.down.forward.square") { model.drill(into: node) }
                }
                actionButton("Afficher dans le Finder", "magnifyingglass") { FileActions.revealInFinder(node.url) }
                actionButton("Ouvrir", "arrow.up.forward.app") { FileActions.open(node.url) }

                if node.isProtected {
                    Label(SystemPaths.reason(for: node.url), systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                } else {
                    Button {
                        model.requestDeletion(node)
                    } label: {
                        Label("Mettre à la corbeille", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.red)
                }
            }
            Spacer()
        }
        .padding(16)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.callout)
    }

    private func actionButton(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func icon(_ node: FileNode) -> String {
        if node.isSymlink { return "arrow.up.right.square" }
        if node.isBundle { return "app.fill" }
        if node.isDirectory { return "folder.fill" }
        return "doc.fill"
    }
}
