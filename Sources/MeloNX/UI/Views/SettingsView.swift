// SettingsView.swift
// MeloNX Air5 Edition
//
// Settings screen for MeloNX Air5 Edition.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: EmulatorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                // MARK: Device info
                Section("Perangkat / Device") {
                    LabeledContent("Model") {
                        Text(iPadAir5Device.isCurrentDevice ? "iPad Air 5 ✓" : "Not iPad Air 5 ⚠️")
                            .foregroundStyle(iPadAir5Device.isCurrentDevice ? .green : .orange)
                    }
                    LabeledContent("Thermal State") {
                        Text(vm.thermalState)
                            .foregroundStyle(thermalColor)
                    }
                    LabeledContent("Display") {
                        Text("\(iPadAir5Device.displayWidth)×\(iPadAir5Device.displayHeight) @ \(Int(iPadAir5Device.ppi)) ppi")
                    }
                }

                // MARK: Performance
                Section("Performa / Performance") {
                    Picker("Performance Tier", selection: $vm.performanceTier) {
                        ForEach(iPadAir5Device.PerformanceTier.allCases, id: \.self) { tier in
                            VStack(alignment: .leading) {
                                Text(tier.rawValue)
                                Text("\(tier.targetFPS) FPS target · \(Int(tier.renderScale * 100))% render scale")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(tier)
                        }
                    }
                    .pickerStyle(.inline)
                    .onChange(of: vm.performanceTier) { _, newTier in
                        vm.setPerformanceTier(newTier)
                    }
                }

                // MARK: Controls
                Section("Kontrol / Controls") {
                    Toggle("On-Screen Controller", isOn: $vm.isControllerVisible)
                }

                // MARK: About
                Section("Tentang / About") {
                    LabeledContent("Versi", value: "1.0.0 (Air5 Edition)")
                    LabeledContent("Platform", value: "iPadOS 16+ · Apple M1")
                    LabeledContent("Renderer", value: "Metal 3")
                }
            }
            .navigationTitle("Pengaturan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Selesai") { dismiss() }
                }
            }
        }
    }

    private var thermalColor: Color {
        switch vm.thermalState {
        case "Nominal": return .green
        case "Fair":    return .yellow
        case "Serious": return .orange
        default:        return .red
        }
    }
}
