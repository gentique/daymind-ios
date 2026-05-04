//
//  DaymindApp.swift
//  Daymind
//
//  Created by Gentian Barileva on 4.5.26.
//

import SwiftUI
import RevenueCat

@main
struct DaymindApp: App {
    init() {
        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(withAPIKey: "test_sBQUvNsrTUdRjdZeozIQaaFeLbP")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
