// iPadAir5Device.swift
// MeloNX Air5 Edition
//
// iPad Air 5 (M1) device profile and optimizations.

import Foundation
import UIKit

/// Device profile for the iPad Air 5 (5th generation, 2022).
/// Chip: Apple M1 | Display: 10.9" 2360×1640 @ 264 ppi | RAM: 8 GB
enum iPadAir5Device {

    // MARK: - Hardware Specifications

    /// Display resolution in physical pixels.
    static let displayWidth  = 2360
    static let displayHeight = 1640

    /// Display scale factor (Retina 2×).
    static let displayScale: CGFloat = 2.0

    /// Logical (point) display size.
    static let logicalWidth:  CGFloat = 1180
    static let logicalHeight: CGFloat = 820

    /// Display pixel density.
    static let ppi: Float = 264.0

    /// Total RAM available (bytes).
    static let totalRAM: UInt64 = 8 * 1024 * 1024 * 1024  // 8 GB

    /// RAM allocated to the emulator guest (bytes).
    static let emulatorRAMBudget: UInt64 = 4 * 1024 * 1024 * 1024  // 4 GB

    /// M1 performance-core count.
    static let performanceCoreCount = 4

    /// M1 efficiency-core count.
    static let efficiencyCoreCount = 4

    /// M1 GPU core count.
    static let gpuCoreCount = 7

    // MARK: - Performance Tiers

    /// Performance preset selection based on user preference and thermal state.
    enum PerformanceTier: String, CaseIterable {
        case ultraPerformance = "Ultra Performance"
        case performance      = "Performance"
        case balanced         = "Balanced"
        case batteryLife      = "Battery Life"

        /// Maximum target frame rate for each tier.
        var targetFPS: Int {
            switch self {
            case .ultraPerformance: return 60
            case .performance:      return 60
            case .balanced:         return 45
            case .batteryLife:      return 30
            }
        }

        /// Render scale factor (1.0 = native 2360×1640).
        var renderScale: Float {
            switch self {
            case .ultraPerformance: return 1.0
            case .performance:      return 0.85
            case .balanced:         return 0.75
            case .batteryLife:      return 0.5
            }
        }

        /// Number of JIT worker threads.
        var jitThreadCount: Int {
            switch self {
            case .ultraPerformance: return 4
            case .performance:      return 3
            case .balanced:         return 2
            case .batteryLife:      return 2
            }
        }
    }

    // MARK: - Compatibility Check

    /// Returns `true` if the current device is an iPad Air 5.
    static var isCurrentDevice: Bool {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { rawPtr -> String in
            let ptr = rawPtr.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: ptr)
        }
        // iPad Air 5th gen identifiers: iPad13,16 (Wi-Fi) and iPad13,17 (Cellular)
        return machine == "iPad13,16" || machine == "iPad13,17"
    }

    /// Returns the current thermal state as a human-readable string.
    static var thermalStateDescription: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    /// Recommended performance tier based on current thermal state.
    static var recommendedPerformanceTier: PerformanceTier {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return .performance
        case .fair:     return .balanced
        case .serious:  return .batteryLife
        case .critical: return .batteryLife
        @unknown default: return .balanced
        }
    }
}
