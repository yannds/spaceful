import SwiftUI

struct TreemapTile: Identifiable {
    let id: UUID
    let node: FileNode
    let rect: CGRect
    let depth: Int
}

/// Squarified treemap layout. Lays a node's children into a rectangle, then recurses
/// into directory tiles up to `maxDepth` so nested files are visible and clickable.
enum Treemap {
    static func layout(nodes: [FileNode], in rect: CGRect, depth: Int = 0, maxDepth: Int = 3) -> [TreemapTile] {
        guard rect.width > 1, rect.height > 1 else { return [] }
        let valued = nodes.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        guard !valued.isEmpty else { return [] }

        let total = valued.reduce(0.0) { $0 + Double($1.size) }
        let scale = (Double(rect.width) * Double(rect.height)) / total
        let areas = valued.map { Double($0.size) * scale }

        var tiles: [TreemapTile] = []
        squarify(nodes: valued, areas: areas, rect: rect) { node, r in
            tiles.append(TreemapTile(id: node.id, node: node, rect: r, depth: depth))
            if depth < maxDepth, node.isDirectory, !node.isBundle,
               !node.children.isEmpty, r.width > 30, r.height > 30 {
                let header: CGFloat = 15
                let body = CGRect(x: r.minX + 1, y: r.minY + header,
                                  width: r.width - 2, height: r.height - header - 1)
                tiles += layout(nodes: node.children, in: body, depth: depth + 1, maxDepth: maxDepth)
            }
        }
        return tiles
    }

    private static func squarify(nodes: [FileNode], areas: [Double], rect startRect: CGRect,
                                 place: (FileNode, CGRect) -> Void) {
        var rect = startRect
        var idx = 0
        while idx < nodes.count {
            let shorter = Double(min(rect.width, rect.height))
            guard shorter > 0 else { return }

            var rowCount = 0
            var rowArea = 0.0
            var best = Double.greatestFiniteMagnitude
            while idx + rowCount < nodes.count {
                let a = areas[idx + rowCount]
                let w = worst(rowArea: rowArea + a,
                              maxA: rowCount == 0 ? a : max(maxInRow(areas, idx, rowCount), a),
                              minA: rowCount == 0 ? a : min(minInRow(areas, idx, rowCount), a),
                              length: shorter)
                if w <= best { best = w; rowArea += a; rowCount += 1 } else { break }
            }
            if rowCount == 0 { rowArea = areas[idx]; rowCount = 1 }

            let thickness = rowArea / shorter
            if rect.width >= rect.height {
                var y = rect.minY
                for k in 0..<rowCount {
                    let a = areas[idx + k]
                    let h = a / thickness
                    place(nodes[idx + k], CGRect(x: rect.minX, y: y, width: thickness, height: h))
                    y += h
                }
                rect = CGRect(x: rect.minX + thickness, y: rect.minY,
                              width: rect.width - thickness, height: rect.height)
            } else {
                var x = rect.minX
                for k in 0..<rowCount {
                    let a = areas[idx + k]
                    let w = a / thickness
                    place(nodes[idx + k], CGRect(x: x, y: rect.minY, width: w, height: thickness))
                    x += w
                }
                rect = CGRect(x: rect.minX, y: rect.minY + thickness,
                              width: rect.width, height: rect.height - thickness)
            }
            idx += rowCount
        }
    }

    private static func maxInRow(_ areas: [Double], _ start: Int, _ count: Int) -> Double {
        var m = -Double.greatestFiniteMagnitude
        for i in start..<(start + count) { m = max(m, areas[i]) }
        return m
    }
    private static func minInRow(_ areas: [Double], _ start: Int, _ count: Int) -> Double {
        var m = Double.greatestFiniteMagnitude
        for i in start..<(start + count) { m = min(m, areas[i]) }
        return m
    }
    private static func worst(rowArea: Double, maxA: Double, minA: Double, length: Double) -> Double {
        let s2 = rowArea * rowArea
        let l2 = length * length
        guard s2 > 0, minA > 0 else { return .greatestFiniteMagnitude }
        return max((l2 * maxA) / s2, s2 / (l2 * minA))
    }
}

struct TreemapView: View {
    @EnvironmentObject var model: AppModel
    let node: FileNode

    @State private var tiles: [TreemapTile] = []
    @State private var size: CGSize = .zero
    @State private var hovered: UUID?
    @State private var hoverPoint: CGPoint?

    private struct LayoutKey: Equatable { let id: UUID; let w: CGFloat; let h: CGFloat; let revision: Int }

    private var hoveredTile: TreemapTile? { tiles.first { $0.id == hovered } }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, _ in draw(ctx) }
                .background(Color(nsColor: .windowBackgroundColor))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): hovered = deepestTile(at: point)?.id; hoverPoint = point
                    case .ended: hovered = nil; hoverPoint = nil
                    }
                }
                .gesture(SpatialTapGesture(count: 2).onEnded { handleTap($0.location, drill: true) })
                .simultaneousGesture(SpatialTapGesture(count: 1).onEnded { handleTap($0.location, drill: false) })
                .overlay(alignment: .topLeading) { tooltip(in: geo.size) }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Treemap de \(node.name)")
                .accessibilityChildren { accessibilityTiles }
                .onChange(of: geo.size) { newValue in size = newValue }
                .task(id: LayoutKey(id: node.id, w: geo.size.width, h: geo.size.height,
                                    revision: model.scanner.revision)) {
                    size = geo.size
                    tiles = Treemap.layout(nodes: node.children,
                                           in: CGRect(origin: .zero, size: geo.size))
                }
        }
    }

    /// Floating name + size card following the cursor.
    @ViewBuilder
    private func tooltip(in canvasSize: CGSize) -> some View {
        if let tile = hoveredTile, let p = hoverPoint {
            VizTooltip(title: tile.node.name,
                       subtitle: "\(tile.node.category.label) · \(Format.bytes(tile.node.size))")
                .position(x: min(max(p.x + 8, 8), canvasSize.width - 8),
                          y: max(p.y - 22, 8))
                .allowsHitTesting(false)
        }
    }

    /// Invisible, correctly-positioned rectangles giving VoiceOver one element per tile.
    private var accessibilityTiles: some View {
        ForEach(tiles.filter { $0.depth == 0 }) { tile in
            Rectangle().fill(.clear)
                .frame(width: tile.rect.width, height: tile.rect.height)
                .position(x: tile.rect.midX, y: tile.rect.midY)
                .accessibilityLabel(tile.node.accessibilityDescription)
        }
    }

    private func draw(_ ctx: GraphicsContext) {
        for tile in tiles {
            let path = Path(roundedRect: tile.rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2)
            let isLeaf = !tile.node.isDirectory || tile.node.isBundle
            var fill = tile.node.color(depth: tile.depth)
            if tile.id == hovered { fill = fill.opacity(0.7) }
            ctx.fill(path, with: .color(fill))
            ctx.stroke(path, with: .color(Color.black.opacity(tile.depth == 0 ? 0.35 : 0.15)),
                       lineWidth: tile.depth == 0 ? 1 : 0.5)

            if tile.id == model.selection?.id {
                ctx.stroke(Path(roundedRect: tile.rect.insetBy(dx: 1, dy: 1), cornerRadius: 2),
                           with: .color(.white), lineWidth: 2)
            }

            if tile.rect.width > 46, tile.rect.height > 14 {
                // Contrast-aware text: dark on light tiles, light on dark ones.
                let dark = tile.node.prefersDarkText(depth: tile.depth)
                let textColor = (dark ? Color.black : Color.white)
                let label = Text(tile.node.name)
                    .font(.system(size: 10, weight: isLeaf ? .regular : .semibold))
                    .foregroundColor(textColor.opacity(0.85))
                ctx.draw(label, at: CGPoint(x: tile.rect.minX + 4, y: tile.rect.minY + 8),
                         anchor: .leading)
                if tile.rect.width > 70, tile.rect.height > 30 {
                    let sz = Text(Format.bytes(tile.node.size))
                        .font(.system(size: 9)).foregroundColor(textColor.opacity(0.65))
                    ctx.draw(sz, at: CGPoint(x: tile.rect.minX + 4, y: tile.rect.minY + 20),
                             anchor: .leading)
                }
            }
        }
    }

    private func deepestTile(at point: CGPoint) -> TreemapTile? {
        tiles.filter { $0.rect.contains(point) }.max { $0.depth < $1.depth }
    }

    private func handleTap(_ point: CGPoint, drill: Bool) {
        guard let tile = deepestTile(at: point) else {
            if drill { model.goUp() }   // double-click on empty space goes up a level
            return
        }
        model.selection = tile.node
        if drill { model.drill(into: tile.node) }
    }
}

/// Shared floating label used by both visualizations on hover.
struct VizTooltip: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.bold()).lineLimit(1)
            Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
        .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
        .frame(maxWidth: 260, alignment: .leading)
        .fixedSize()
    }
}
