import SwiftUI

/// Compact colour legend for the type-coloured visualizations. Only the categories
/// actually present under the current focus are shown, so it stays relevant.
struct VizLegend: View {
    let categories: [FileCategory]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(categories) { cat in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(cat.color)
                            .frame(width: 11, height: 11)
                        Text(cat.label).font(.caption2).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(cat.label)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
        }
        .background(.bar)
    }

    /// Distinct categories among a node's immediate children, ordered by the enum.
    static func categories(in node: FileNode) -> [FileCategory] {
        let present = Set(node.children.filter { $0.size > 0 }.map { FileCategory.of(node: $0) })
        return FileCategory.allCases.filter { present.contains($0) }
    }
}
