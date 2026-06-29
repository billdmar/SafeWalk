import SwiftUI

/// The screenshot centerpiece: a large, animated safety status indicator.
struct StatusHeroView: View {
    let status: SafetyStatus
    /// Honor the system "Reduce Motion" setting — when on, the hero stops
    /// pulsing so the animation doesn't bother motion-sensitive users.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(status.color.opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: status.symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(status.color)
                    .symbolEffect(.pulse,
                                  options: (status == .safe || reduceMotion) ? .nonRepeating : .repeating,
                                  value: status)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(status.title)
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(status.color)
                Text(status.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(status.color.opacity(0.5), lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.35), value: status)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.title). \(status.subtitle)")
    }
}
