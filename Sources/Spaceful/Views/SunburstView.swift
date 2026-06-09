import SwiftUI

struct SunburstArc: Identifiable {
    let id: UUID
    let node: FileNode
    let depth: Int          // ring index, 1 = first ring out from center
    let start: Double       // fraction [0,1) of full circle
    let end: Double
}

enum Sunburst {
    /// Build arcs for `focus`'s descendants. The focus itself is the center disc.
    static func arcs(focus: FileNode, maxDepth: Int = 5) -> [SunburstArc] {
        var result: [SunburstArc] = []
        func recurse(_ node: FileNode, depth: Int, start: Double, end: Double) {
            guard depth <= maxDepth else { return }
            let span = end - start
            guard span > 0.0008 else { return }      // skip slivers
            let children = node.children.filter { $0.size > 0 }.sorted { $0.size > $1.size }
            let total = children.reduce(0.0) { $0 + Double($1.size) }
            guard total > 0 else { return }
            var cursor = start
            for child in children {
                let frac = Double(child.size) / total * span
                let cEnd = cursor + frac
                result.append(SunburstArc(id: child.id, node: child, depth: depth,
                                          start: cursor, end: cEnd))
                if child.isDirectory, !child.isBundle, !child.children.isEmpty {
                    recurse(child, depth: depth + 1, start: cursor, end: cEnd)
                }
                cursor = cEnd
            }
        }
        recurse(focus, depth: 1, start: 0, end: 1)
        return result
    }
}

struct SunburstView: View {
    @EnvironmentObject var model: AppModel
    let node: FileNode

    @State private var arcs: [SunburstArc] = []
    @State private var hovered: UUID?
    @State private var hoverPoint: CGPoint?

    private struct ArcKey: Equatable { let id: UUID; let revision: Int }

    private let centerRadius: CGFloat = 46
    private let ringWidth: CGFloat = 34

    private var hoveredArc: SunburstArc? { arcs.first { $0.id == hovered } }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            Canvas { ctx, _ in draw(ctx, center: center) }
                .background(Color(nsColor: .windowBackgroundColor))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): hovered = arc(at: p, center: center)?.id; hoverPoint = p
                    case .ended: hovered = nil; hoverPoint = nil
                    }
                }
                // Consistent with the treemap: single click selects, double click navigates.
                .gesture(SpatialTapGesture(count: 2).onEnded { handleDrill($0.location, center: center) })
                .simultaneousGesture(SpatialTapGesture(count: 1).onEnded { handleSelect($0.location, center: center) })
                .overlay(alignment: .topLeading) { tooltip(in: geo.size) }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Diagramme soleil de \(node.name)")
                .accessibilityChildren { accessibilityArcs }
                .task(id: ArcKey(id: node.id, revision: model.scanner.revision)) {
                    arcs = Sunburst.arcs(focus: node)
                }
        }
    }

    @ViewBuilder
    private func tooltip(in canvasSize: CGSize) -> some View {
        if let a = hoveredArc, let p = hoverPoint {
            VizTooltip(title: a.node.name,
                       subtitle: "\(a.node.category.label) · \(Format.bytes(a.node.size))")
                .position(x: min(max(p.x + 8, 8), canvasSize.width - 8),
                          y: max(p.y - 22, 8))
                .allowsHitTesting(false)
        }
    }

    /// One accessibility element per first-ring slice (the focus's direct children).
    private var accessibilityArcs: some View {
        ForEach(arcs.filter { $0.depth == 1 }) { a in
            Rectangle().fill(.clear).frame(width: 1, height: 1)
                .accessibilityLabel(a.node.accessibilityDescription)
        }
    }

    private func draw(_ ctx: GraphicsContext, center: CGPoint) {
        // Center disc = current focus, click to go up.
        let disc = Path(ellipseIn: CGRect(x: center.x - centerRadius, y: center.y - centerRadius,
                                          width: centerRadius * 2, height: centerRadius * 2))
        ctx.fill(disc, with: .color(node.color(depth: 0)))
        ctx.stroke(disc, with: .color(.black.opacity(0.25)), lineWidth: 1)
        let centerText = node.prefersDarkText(depth: 0) ? Color.black : Color.white
        ctx.draw(Text(node.name).font(.system(size: 11, weight: .semibold)).foregroundColor(centerText.opacity(0.85)),
                 at: CGPoint(x: center.x, y: center.y - 6))
        ctx.draw(Text(Format.bytes(node.size)).font(.system(size: 10)).foregroundColor(centerText.opacity(0.65)),
                 at: CGPoint(x: center.x, y: center.y + 9))

        for arc in arcs {
            let inner = centerRadius + CGFloat(arc.depth - 1) * ringWidth
            let outer = inner + ringWidth
            let a0 = Angle.degrees(arc.start * 360 - 90)
            let a1 = Angle.degrees(arc.end * 360 - 90)
            var path = Path()
            path.addArc(center: center, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
            path.addArc(center: center, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
            path.closeSubpath()

            var fill = arc.node.color(depth: arc.depth)
            if arc.id == hovered { fill = fill.opacity(0.7) }
            ctx.fill(path, with: .color(fill))
            ctx.stroke(path, with: .color(.black.opacity(0.18)), lineWidth: 0.5)

            if arc.id == model.selection?.id {
                ctx.stroke(path, with: .color(.white), lineWidth: 2)
            }

            // Label arcs that are wide enough.
            if (arc.end - arc.start) > 0.035 {
                let mid = (arc.start + arc.end) / 2
                let r = (inner + outer) / 2
                let rad = (mid * 360 - 90) * .pi / 180
                let p = CGPoint(x: center.x + cos(rad) * r, y: center.y + sin(rad) * r)
                ctx.draw(Text(arc.node.name).font(.system(size: 8)).foregroundColor(.black.opacity(0.75)),
                         at: p)
            }
        }
    }

    private func arc(at point: CGPoint, center: CGPoint) -> SunburstArc? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radius = sqrt(dx * dx + dy * dy)
        guard radius > centerRadius else { return nil }
        let depth = Int((radius - centerRadius) / ringWidth) + 1
        var deg = atan2(dy, dx) * 180 / .pi + 90
        if deg < 0 { deg += 360 }
        let fraction = deg / 360
        return arcs.first { $0.depth == depth && fraction >= $0.start && fraction < $0.end }
    }

    private func handleSelect(_ point: CGPoint, center: CGPoint) {
        let dx = point.x - center.x, dy = point.y - center.y
        if sqrt(dx * dx + dy * dy) <= centerRadius { model.selection = node; return }
        if let hit = arc(at: point, center: center) { model.selection = hit.node }
    }

    private func handleDrill(_ point: CGPoint, center: CGPoint) {
        let dx = point.x - center.x, dy = point.y - center.y
        if sqrt(dx * dx + dy * dy) <= centerRadius {     // double-click center → go up
            model.goUp()
            return
        }
        guard let hit = arc(at: point, center: center) else { return }
        model.selection = hit.node
        if hit.node.isDirectory, !hit.node.isBundle, !hit.node.children.isEmpty {
            model.drill(into: hit.node)
        }
    }
}
