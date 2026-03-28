// MeloNXApp.swift
// MeloNX Air5 Edition
//
// Application entry point for MeloNX Air5 Edition.

import SwiftUI

@main
struct MeloNXApp: App {

    @StateObject private var emulatorState = EmulatorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(emulatorState)
                .preferredColorScheme(.dark)
        }
    }
}
