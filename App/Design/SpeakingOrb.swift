import SwiftUI

/// The clear, animated state of the storyteller: still when paused, breathing slowly while the
/// story is being written or the next part is loading, pulsing with rings while the voice
/// speaks. In Talk, `level` (0...1) makes it follow the microphone while it listens and the
/// storyteller's voice while it answers. Reduce Motion turns the animation off and keeps the
/// state readable by colour.
struct SpeakingOrb: View {
    enum Mode: Equatable {
        case still
        case breathing
        case speaking
        /// Talk: the microphone is open and the orb follows its level.
        case listening
        /// Talk: the microphone is muted.
        case muted
    }

    let mode: Mode
    var size: CGFloat = 168
    /// Loudness, 0...1. Only Talk passes it; the other screens leave it at 0.
    var level: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: dim || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .strokeBorder(Theme.amber.opacity(ringOpacity(ring)), lineWidth: 2)
                        .scaleEffect(ringScale(ring, t))
                }
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.amber, Theme.amberDeep], center: .center, startRadius: 4,
                            endRadius: size * 0.4)
                    )
                    .frame(width: size * 0.56, height: size * 0.56)
                    .scaleEffect(coreScale(t) + CGFloat(level) * 0.3)
                    .shadow(color: Theme.amber.opacity(dim ? 0.1 : 0.45), radius: mode == .speaking ? 24 : 12)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.2, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: size, height: size)
        }
        .animation(.easeInOut(duration: 0.3), value: mode)
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }

    private var dim: Bool { mode == .still || mode == .muted }

    private var symbol: String {
        switch mode {
        case .still: "pause.fill"
        case .muted: "mic.slash.fill"
        case .listening: "mic.fill"
        case .breathing, .speaking: "waveform"
        }
    }

    private func ringOpacity(_ ring: Int) -> Double {
        switch mode {
        case .still, .muted: 0.12
        case .breathing: 0.25 - Double(ring) * 0.06
        case .listening: 0.3 + level * 0.3 - Double(ring) * 0.08
        case .speaking: 0.5 - Double(ring) * 0.14
        }
    }

    private func ringScale(_ ring: Int, _ t: TimeInterval) -> CGFloat {
        let base = 0.62 + CGFloat(ring) * 0.19
        // Each ring swells with the level, the outer ones most.
        let swell = CGFloat(level) * 0.12 * CGFloat(ring + 1)
        guard !reduceMotion else { return base + 0.08 + swell }
        switch mode {
        case .still, .muted: return base
        case .breathing: return base + 0.04 * CGFloat(sin(t * 1.1 + Double(ring) * 0.8))
        case .listening: return base + 0.03 * CGFloat(sin(t * 1.4 + Double(ring) * 0.8)) + swell
        case .speaking: return base + 0.09 * CGFloat(sin(t * 3.4 + Double(ring) * 1.3)) + swell
        }
    }

    private func coreScale(_ t: TimeInterval) -> CGFloat {
        guard !reduceMotion else { return 1 }
        switch mode {
        case .still, .muted: return 1
        case .breathing: return 1 + 0.04 * CGFloat(sin(t * 1.1))
        case .listening: return 1 + 0.03 * CGFloat(sin(t * 1.4))
        case .speaking: return 1 + 0.07 * CGFloat(sin(t * 5.2))
        }
    }
}

#Preview("Orb") {
    VStack(spacing: 40) {
        SpeakingOrb(mode: .speaking)
        SpeakingOrb(mode: .breathing)
        SpeakingOrb(mode: .still)
        SpeakingOrb(mode: .listening, level: 0.6)
    }
    .padding()
    .inkBackground()
}
