//
//  Party_WatcherApp.swift
//  Party Watcher
//
//  Created by Bill Mar on 7/23/25.
//

import SwiftUI

@main
struct Party_WatcherApp: App {
    init() {
        // Register the actionable escalation categories and the notification
        // delegate once, at launch — not lazily when an escalation fires, which
        // would race the notification's own delivery and could drop the action
        // buttons on the first alert.
        NotificationService.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // SafeWalk uses a fixed orange-and-white look, so lock the whole
                // app (including presented sheets) to light mode rather than
                // following the system's dark appearance.
                .preferredColorScheme(.light)
        }
    }
}
