import SwiftUI

/// Baika's look: a deep ink background, warm paper-cream text, one amber accent.
/// Large type, one big primary action per screen, icon buttons for controls.
enum Theme {
    static let ink = Color(hex: 0x14110F)
    static let surface = Color(hex: 0x1F1A17)
    static let surfaceHigh = Color(hex: 0x2B2420)
    static let line = Color(hex: 0x3A312B)
    static let amber = Color(hex: 0xF2A33A)
    static let amberDeep = Color(hex: 0xC97A12)
    static let cream = Color(hex: 0xF4EBDD)
    static let muted = Color(hex: 0xA99C8D)
    static let danger = Color(hex: 0xE5776B)

    static let gap: CGFloat = 16
    static let radius: CGFloat = 20
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    func inkBackground() -> some View {
        background(Theme.ink.ignoresSafeArea())
    }

    func card(padding: CGFloat = Theme.gap) -> some View {
        self.padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

/// The one big action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                Capsule().fill(isEnabled ? Theme.amber : Theme.amber.opacity(0.28)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// A round icon button: pause, skip, stop. Every use sets an accessibility label.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 52
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(filled ? Theme.ink : Theme.cream)
            .frame(width: size, height: size)
            .background(Circle().fill(filled ? Theme.amber : Theme.surfaceHigh))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static func icon(size: CGFloat = 52, filled: Bool = false) -> IconButtonStyle {
        IconButtonStyle(size: size, filled: filled)
    }
}

/// A selectable chip: a style, a length, a voice.
struct Chip: View {
    let title: String
    var subtitle: String?
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption).lineLimit(2).multilineTextAlignment(.leading)
            }
        }
        .foregroundStyle(selected ? Theme.ink : Theme.cream)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? Theme.amber : Theme.surfaceHigh))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? Color.clear : Theme.line))
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A section label above a group of choices.
struct SectionLabel: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(Theme.muted)
            .accessibilityAddTraits(.isHeader)
    }
}
