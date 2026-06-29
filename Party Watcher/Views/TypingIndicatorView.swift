import SwiftUI

/// An animated three-dot "typing…" indicator for the companion. The dots pulse
/// in sequence; under Reduce Motion they hold steady so the row is still legible
/// without animation. Announced to VoiceOver as a single status.
struct TypingIndicatorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Theme.burntOrange.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .scaleEffect(scale(for: index))
                        .animation(
                            reduceMotion ? nil :
                                .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            Text("Companion is typing…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .onAppear { animating = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Companion is typing")
    }

    private func scale(for index: Int) -> CGFloat {
        guard !reduceMotion, animating else { return 1 }
        return 1.4
    }
}
