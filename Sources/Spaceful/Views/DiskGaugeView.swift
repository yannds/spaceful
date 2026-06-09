import SwiftUI

/// Headline capacity gauge — "X libres sur Y". The single most important number for a
/// disk-space tool, kept visible at the top of the sidebar at all times.
struct DiskGaugeView: View {
    let space: DiskSpace

    private var freeFraction: Double { space.total > 0 ? Double(space.free) / Double(space.total) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.bytes(space.free)).font(.title3.bold().monospacedDigit())
                    + Text(" libres").font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Text("sur \(Format.bytes(space.total))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(LinearGradient(colors: barColors,
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * space.usedFraction))
                }
            }
            .frame(height: 8)

            Text("\(Format.bytes(space.used)) utilisés · \(Format.percent(space.usedFraction)) plein")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Espace disque")
        .accessibilityValue("\(Format.bytes(space.free)) libres sur \(Format.bytes(space.total)), \(Format.percent(space.usedFraction)) utilisés")
    }

    /// Green when there's headroom, amber past 80%, red past 92%.
    private var barColors: [Color] {
        switch space.usedFraction {
        case ..<0.8:  return [.green, .teal]
        case ..<0.92: return [.yellow, .orange]
        default:      return [.orange, .red]
        }
    }
}
