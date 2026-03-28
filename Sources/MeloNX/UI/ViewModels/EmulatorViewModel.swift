// EmulatorViewModel.swift
// MeloNX Air5 Edition
//
// Central view model coordinating the emulator core, GPU, and audio.

import Foundation
import Combine
import SwiftUI

/// Represents the running state of the emulator.
enum EmulatorState {
    case idle
    case running
    case paused
    case stopped
}

/// Observable view model for the emulator.
/// Drives the SwiftUI UI and manages the lifecycle of the emulator core.
@MainActor
final class EmulatorViewModel: ObservableObject {

    // MARK: - Published state

    @Published var emulatorState: EmulatorState = .idle
    @Published var loadedGameTitle: String = ""
    @Published var fps: Int = 0
    @Published var performanceTier: iPadAir5Device.PerformanceTier = .performance
    @Published var isControllerVisible = true
    @Published var thermalState: String = iPadAir5Device.thermalStateDescription
    @Published var romLibrary: [ROMEntry] = []

    // MARK: - Core objects

    private let memoryBus = MemoryBus()
    private lazy var cpu = CPUCore(memoryBus: memoryBus)
    private let audio = EmulatorAudioEngine()
    private var fpsTimer: Timer?
    private var frameCount = 0
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        observeThermalState()
        loadROMLibrary()
    }

    // MARK: - ROM Loading

    func loadROM(entry: ROMEntry) {
        guard emulatorState == .idle || emulatorState == .stopped else { return }
        loadedGameTitle = entry.title
        emulatorState = .running
        audio.start()
        cpu.start()
        startFPSCounter()
    }

    func stopEmulation() {
        cpu.stop()
        audio.stop()
        fpsTimer?.invalidate()
        fpsTimer = nil
        emulatorState = .stopped
        fps = 0
    }

    func pauseResume() {
        switch emulatorState {
        case .running:
            cpu.stop()
            emulatorState = .paused
        case .paused:
            cpu.start()
            emulatorState = .running
        default:
            break
        }
    }

    // MARK: - Performance

    func setPerformanceTier(_ tier: iPadAir5Device.PerformanceTier) {
        performanceTier = tier
    }

    // MARK: - ROM Library

    private func loadROMLibrary() {
        // Scan the Documents directory for .nsp, .xci, and .nro files.
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            romLibrary = []
            return
        }
        let supportedExtensions: Set<String> = ["nsp", "xci", "nro"]
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: docs,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )
            romLibrary = files
                .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
                .map { url in
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    return ROMEntry(
                        title: url.deletingPathExtension().lastPathComponent,
                        url: url,
                        format: url.pathExtension.uppercased(),
                        sizeBytes: size
                    )
                }
                .sorted { $0.title < $1.title }
        } catch {
            romLibrary = []
        }
    }

    // MARK: - Private

    private func startFPSCounter() {
        frameCount = 0
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.fps = self.frameCount
                self.frameCount = 0
            }
        }
    }

    func incrementFrameCount() {
        frameCount += 1
    }

    private func observeThermalState() {
        NotificationCenter.default
            .publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.thermalState = iPadAir5Device.thermalStateDescription
                    let recommended = iPadAir5Device.recommendedPerformanceTier
                    if self.performanceTier.targetFPS > recommended.targetFPS {
                        self.performanceTier = recommended
                    }
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - ROMEntry

struct ROMEntry: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    let format: String
    let sizeBytes: Int

    var sizeDescription: String {
        let gb = Double(sizeBytes) / 1_073_741_824
        if gb >= 1.0 { return String(format: "%.1f GB", gb) }
        let mb = Double(sizeBytes) / 1_048_576
        return String(format: "%.1f MB", mb)
    }
}
