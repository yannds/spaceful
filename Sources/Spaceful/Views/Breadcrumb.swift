import SwiftUI

struct Breadcrumb: View {
    @EnvironmentObject var model: AppModel
    let focus: FileNode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    model.goUp()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(focus.parent == nil)
                .help("Remonter d'un niveau")

                ForEach(Array(focus.ancestry.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Button {
                        model.navigate(to: node)
                    } label: {
                        Text(node.name)
                            .fontWeight(node.id == focus.id ? .semibold : .regular)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(node.id == focus.id ? Color.primary : Color.accentColor)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .background(.bar)
    }
}
