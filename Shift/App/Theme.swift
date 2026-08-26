import SwiftUI

enum ShiftTheme {
    static let bg = Color(red: 0.05, green: 0.07, blue: 0.11)
    static let card = Color.white.opacity(0.07)
    static let stroke = Color.white.opacity(0.08)
    static let accent = Color(red: 0.98, green: 0.62, blue: 0.22)
    static let delay = Color(red: 0.98, green: 0.62, blue: 0.22)
    static let advance = Color(red: 0.45, green: 0.72, blue: 1.0)
    static let flight = Color(red: 0.73, green: 0.55, blue: 1.0)
    static let hold = Color(red: 0.46, green: 0.84, blue: 0.62)

    static func color(for kind: ShiftKind) -> Color {
        switch kind {
        case .delay: return delay
        case .advance: return advance
        case .flight: return flight
        case .hold: return hold
        }
    }
}

struct ShiftCard<Content: View>: View {
    var tint: Color = ShiftTheme.accent
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShiftTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }
}

struct KindBadge: View {
    let kind: ShiftKind
    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(ShiftTheme.color(for: kind))
            .background(ShiftTheme.color(for: kind).opacity(0.16), in: Capsule())
    }

    private var label: String {
        switch kind {
        case .delay: return "DELAY"
        case .advance: return "ADVANCE"
        case .flight: return "FLIGHT"
        case .hold: return "HOLD"
        }
    }
}
