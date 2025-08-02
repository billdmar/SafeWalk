//
//  ContentView.swift
//  Party Watcher
//
//  Created by Bill Mar on 7/23/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        SafetyWatcherView()
            .background(Color("UTBackground").ignoresSafeArea())
    }
}

#Preview {
    ContentView()
}
