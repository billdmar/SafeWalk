//
//  Party_WatcherApp.swift
//  Party Watcher
//
//  Created by Bill Mar on 7/23/25.
//

import SwiftUI

@main
struct Party_WatcherApp: App {
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
