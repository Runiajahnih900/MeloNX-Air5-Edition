// LibraryView.swift
// MeloNX Air5 Edition
//
// ROM library browser, designed for the iPad Air 5's 10.9" landscape display.

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var vm: EmulatorViewModel
    @State private var searchText = ""
    @State private var showingSettings = false

    private var filteredROMs: [ROMEntry] {
        if searchText.isEmpty { return vm.romLibrary }
        return vm.romLibrary.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if vm.romLibrary.isEmpty {
                    EmptyLibraryView()
                } else {
                    romGrid
                }
            }
            .navigationTitle("MeloNX Air5 Edition")
            .searchable(text: $searchText, prompt: "Search games…")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var romGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)],
                spacing: 16
            ) {
                ForEach(filteredROMs) { rom in
                    ROMCardView(rom: rom)
                        .onTapGesture {
                            vm.loadROM(entry: rom)
                        }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Empty Library

struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
            Text("Belum ada game")
                .font(.title2.bold())
            Text("Tambahkan file ROM (.nsp, .xci, .nro)\nke folder Documents aplikasi ini.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - ROM Card

struct ROMCardView: View {
    let rom: ROMEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [.indigo.opacity(0.7), .purple.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 130)
                .overlay {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.8))
                }

            Text(rom.title)
                .font(.footnote.bold())
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack {
                Text(rom.format)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.2), in: Capsule())
                    .foregroundStyle(.blue)

                Spacer()

                Text(rom.sizeDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
