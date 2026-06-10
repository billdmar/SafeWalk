//
//  Theme.swift
//  Party Watcher
//
//  SafeWalk's central design system: the UT-inspired color palette, the
//  safety status colors, shared gradients, typography, and a reusable card
//  surface. Centralizing these here removes the `burntOrange` computed
//  property that was previously duplicated across views and gives the whole
//  app one consistent, dark-mode-aware look.
//

import SwiftUI

/// SafeWalk's palette and shared visual tokens.
///
/// All colors are defined so they read well in both light and dark mode. The
/// brand color is UT Austin's burnt orange; the safety status colors (green /
/// amber / red) drive the status hero and quick-action accents.
enum Theme {
    // MARK: Brand

    /// UT Austin burnt orange — the app's primary brand color.
    static let burntOrange = Color(red: 191 / 255, green: 87 / 255, blue: 0 / 255)
    /// A slightly lighter orange used for gradients and hovers.
    static let burntOrangeLight = Color(red: 214 / 255, green: 116 / 255, blue: 31 / 255)

    // MARK: Safety status

    /// "Safe" — calm, everything is fine.
    static let safe = Color(red: 34 / 255, green: 160 / 255, blue: 94 / 255)
    /// "Checking in…" — a check-in is pending a reply.
    static let checking = Color(red: 226 / 255, green: 150 / 255, blue: 30 / 255)
    /// "Alert" — escalation has fired.
    static let alert = Color(red: 210 / 255, green: 51 / 255, blue: 51 / 255)

    // MARK: Surfaces

    /// The app's background — a soft vertical gradient that adapts to color scheme.
    static func background(_ scheme: ColorScheme) -> LinearGradient {
        let top = scheme == .dark ? Color(white: 0.07) : Color.white
        let bottom = scheme == .dark
            ? burntOrange.opacity(0.18)
            : burntOrange.opacity(0.08)
        return LinearGradient(
            gradient: Gradient(colors: [top, bottom]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Fill color for card surfaces, adapting to the color scheme.
    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.13) : Color.white
    }
}

/// A rounded, subtly shadowed card surface used for each dashboard section.
///
/// Apply with `.card()`. The fill adapts to light/dark mode and the shadow is
/// kept soft so several cards can stack without visual noise.
struct CardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.cardFill(scheme))
            )
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.4 : 0.06),
                    radius: 10, x: 0, y: 4)
    }
}

extension View {
    /// Wraps the view in SafeWalk's standard card surface.
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }
}
