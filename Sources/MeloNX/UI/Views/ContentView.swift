// ContentView.swift
// MeloNX Air5 Edition
//
// Root view: shows the game library when idle, or the emulator screen when running.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: EmulatorViewModel

    var body: some View {
        Group {
            switch vm.emulatorState {
            case .idle, .stopped:
                LibraryView()
            case .running, .paused:
                EmulatorView()
            }
        }
        .preferredColorScheme(.dark)
    }
}
