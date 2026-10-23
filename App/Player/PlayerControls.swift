import SwiftUI

enum TimeFormat {
    /// "3:07" for 187 seconds.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// Progress, back 15 seconds, play or pause, forward 15 seconds.
struct PlayerControls: View {
    let player: NarrationPlayer

    var body: some View {
        VStack(spacing: 14) {
            let total = max(player.duration, 1)
            ProgressView(value: min(max(player.elapsed, 0), total), total: total)
                .tint(Theme.amber)
                .accessibilityLabel("Progress")
                .accessibilityValue(Text("\(TimeFormat.clock(player.elapsed)) of \(TimeFormat.clock(player.duration))"))
            HStack {
                Text(TimeFormat.clock(player.elapsed))
                Spacer()
                Text(TimeFormat.clock(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.muted)
            .accessibilityHidden(true)

            HStack(spacing: 32) {
                Button {
                    player.skip(by: -NarrationPlayer.skipSeconds)
                } label: {
                    Image(systemName: "gobackward.15")
                }
                .buttonStyle(.icon())
                .accessibilityLabel("Back 15 seconds")

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.state == .playing ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.icon(size: 80, filled: true))
                .accessibilityLabel(player.state == .playing ? Text("Pause") : Text("Play"))

                Button {
                    player.skip(by: NarrationPlayer.skipSeconds)
                } label: {
                    Image(systemName: "goforward.15")
                }
                .buttonStyle(.icon())
                .accessibilityLabel("Forward 15 seconds")
            }
        }
    }
}
