//
//  ContentView.swift
//  MartenIOSWrapper
//
//  Created by Hirchyts Daniil on 11/02/2026.
//

import MartenIOSApp
import SwiftUI

struct ContentView: View {
    @State private var bootstrap = MartenIOSStorageConfiguration().makeBootstrap(
        userDefaults: UserDefaults(suiteName: MartenIOSStorageConfiguration.defaultAppGroupIdentifier)
            ?? .standard
    )

    var body: some View {
        MartenIOSRootView(bootstrap: bootstrap)
    }
}

#Preview {
    ContentView()
}
