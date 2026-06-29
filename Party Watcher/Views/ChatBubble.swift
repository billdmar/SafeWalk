import SwiftUI

/// A single chat message bubble, styled and aligned by whether the user sent it.
struct ChatBubble: View {
    let message: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(isUser ? Theme.burntOrange.opacity(0.92) : Color(UIColor.secondarySystemBackground))
                .foregroundColor(isUser ? .white : .primary)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                // Cap at ~78% of the screen width so a short message hugs its
                // text while a long one wraps instead of clipping — relative to
                // the screen (and so it grows with Dynamic Type) rather than the
                // old fixed 300 pt that truncated at large accessibility sizes.
                .frame(maxWidth: UIScreen.main.bounds.width * 0.78, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.vertical, 1)
        .accessibilityLabel("\(isUser ? "You" : "Companion"): \(message)")
    }
}
