//
//  LaunchGameHandler.swift
//  MeloNX
//
//  Created by Stossy11 on 10/11/2025.
//

import Combine
import Foundation
import SwiftUI

class LaunchGameHandler: ObservableObject {
    @Published var currentGame: Game? = nil
    @Published var profileSelected = false
    @Published var showApp: Bool = true
    @Published var isPortrait: Bool = true
    @AppStorage("gametorun") var gametorun: String = ""
    @AppStorage("gametorun-date") var gametorunDate: String = ""
    
    static var succeededJIT: Bool = true
    
    private static let jitEntitlement = "com.apple.developer.kernel.increased-memory-limit"
    private static let largeGameThresholdBytes: Int64 = 8_589_934_592 // 8 GiB
    private static let mediumGameThresholdBytes: Int64 = 4_294_967_296 // 4 GiB
    private static let lowMemoryDeviceThresholdBytes: UInt64 = 6_442_450_944 // 6 GiB
    private static let standardMemoryDeviceThresholdBytes: UInt64 = 8_589_934_592 // 8 GiB
    private static let storyOfSeasonsTitleId = "0100ed400eec2000"
    
    private let ryujinx = Ryujinx.shared
    private let nativeSettings = NativeSettingsManager.shared
    private let settingsManager = SettingsManager.shared
    private let persettings = PerGameSettingsManager.shared
    private let controllerManager = ControllerManager.shared
    
    private var config: Ryujinx.Arguments {
        settingsManager.config
    }
    
    private var hasJITEntitlement: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac ? true : checkAppEntitlement(Self.jitEntitlement)
    }
    
    var isGameReady: Bool {
        currentGame != nil
            && (nativeSettings.ignoreJIT.value ? true : ryujinx.jitenabled)
            && (nativeSettings.showProfileonGame.value ? profileSelected : true)
    }
    
    var shouldLaunchGame: Bool {
        isGameReady && hasJITEntitlement
    }
    
    var shouldShowEntitlement: Bool {
        isGameReady && !hasJITEntitlement
    }
    
    var shouldShowPopover: Bool {
        currentGame != nil
            && ryujinx.jitenabled
            && !profileSelected
            && nativeSettings.showProfileonGame.value
            && hasJITEntitlement
    }
    
    var shouldCheckJIT: Bool {
        currentGame != nil
            && !ryujinx.jitenabled
            && !(nativeSettings.ignoreJIT.value as Bool)
            && hasJITEntitlement
    }
    
    
    
    func enableJIT() {
        ryujinx.checkForJIT()
        print("Has TXM? \(ProcessInfo.processInfo.hasTXM)")
        
        if !ryujinx.jitenabled {
            if nativeSettings.useTrollStore.value {
                gametorunDate = "\(Date().timeIntervalSince1970)"
                gametorun = currentGame?.titleId ?? ""
                askForJIT()
            } else if nativeSettings.stikJIT.value {
                gametorunDate = "\(Date().timeIntervalSince1970)"
                gametorun = currentGame?.titleId ?? ""
                enableJITStik()
            } else {
                // nothing
            }
        }
    }
    
    func startGame() {
        LogCapture.shared.logDiagnostic("Launch stage: startGame invoked")

        enableJIT()
        LogCapture.shared.logDiagnostic("Launch stage: enableJIT completed (jitEnabled=\(ryujinx.jitenabled), hasTXM=\(ProcessInfo.processInfo.hasTXM))")

        MusicSelectorView.stopMusic()
        nativeSettings.isVirtualController.value = controllerManager.hasVirtualController()
        MetalView.createView()
        
        guard let currentGame else {
            LogCapture.shared.logDiagnostic("Launch aborted: currentGame is nil")
            return
        }

        LogCapture.shared.logDiagnostic("Launch stage: preparing session for titleId=\(currentGame.titleId)")

        LogCapture.shared.startGameSessionLog(gameTitle: currentGame.titleName, titleId: currentGame.titleId)
        LogCapture.shared.logDiagnostic("Launch stage: session log started")
        LogCapture.shared.logDiagnostic("MELONX_IOS_LIFECYCLE_V10_ACTIVE: session instrumentation enabled")
        
        persettings.loadSettings()
        LogCapture.shared.logDiagnostic("Launch stage: per-game settings loaded")
        
        var config = persettings.config[currentGame.titleId] ?? self.config

        let crashForensicsMode = nativeSettings.setting(forKey: "crashForensicsMode", default: true).value
        let allowUnsafeVerboseLogs = nativeSettings.setting(forKey: "allowUnsafeVerboseLogs", default: false).value
        let allowStubLogs = nativeSettings.setting(forKey: "allowStubLogs", default: false).value
        LogCapture.shared.logDiagnostic("Forensics toggles: crashForensics=\(crashForensicsMode), allowStubLogs=\(allowStubLogs), allowUnsafeVerboseLogs=\(allowUnsafeVerboseLogs)")

        if !ProcessInfo.processInfo.isiOSAppOnMac && !allowUnsafeVerboseLogs {
            if config.tracelogs || config.debuglogs {
                print("[MeloNX] Verbose logs (trace/debug) disabled on iOS for stability. Set 'allowUnsafeVerboseLogs' to true to override.")
            }

            config.tracelogs = false
            config.debuglogs = false
        }

        applyLargeGameMemoryProfileIfNeeded(for: currentGame, config: &config, crashForensicsMode: crashForensicsMode)
        applyStoryOfSeasonsCompatibilityProfileIfNeeded(for: currentGame, config: &config)

        if config.hypervisor && !(ProcessInfo.processInfo.isiOSAppOnMac || checkAppEntitlement("com.apple.private.hypervisor")) {
            config.hypervisor = false
        }
        
        controllerManager.registerControllerTypeForMatchingControllers()
        config.gamepath = currentGame.fileURL.path
        config.inputids = Array(Set(controllerManager.selectedControllers))
        
        if config.inputids.isEmpty {
            config.inputids.append("0")
        }

        LogCapture.shared.logDiagnostic("Config summary: memoryMode=\(config.memoryManagerMode), disablePTC=\(config.disablePTC), expandRam=\(config.expandRam), hypervisor=\(config.hypervisor), debugLogs=\(config.debuglogs), traceLogs=\(config.tracelogs), macroHLE=\(config.macroHLE), docked=\(config.enableDockedMode), ignoreMissingServices=\(config.ignoreMissingServices), controllerCount=\(config.inputids.count)")
        LogCapture.shared.logDiagnostic("Config additionalArgs=\(config.additionalArgs.joined(separator: " "))")
        
        print(config.inputids)
        configureEnvironmentVariables(for: config)
        LogCapture.shared.logDiagnostic("Launch stage: environment configured, starting Ryujinx core")
        
        do {
            try ryujinx.start(with: config)
        } catch {
            print("Failed to start game '\(currentGame.titleId)': \(error)")
            LogCapture.shared.endGameSessionLog()
        }
    }
    
    private func configureEnvironmentVariables(for config: Ryujinx.Arguments) {
        LogCapture.shared.logDiagnostic("MELONX_IOS_SAVELOAD_V1_ACTIVE: Story of Seasons compatibility profile available")

        let enableEventWaitPromotion = nativeSettings.setting(forKey: "iosEventWaitPromotionFallback", default: false).value
        let enableNvWaitPromotion = nativeSettings.setting(forKey: "iosNvWaitPromotionFallback", default: false).value
        let activeTitleId = currentGame?.titleId.lowercased() ?? ""
        let enableNvWaitBlocking = !ProcessInfo.processInfo.isiOSAppOnMac && activeTitleId == Self.storyOfSeasonsTitleId
        let enableNvWaitTimeoutPromotion = !ProcessInfo.processInfo.isiOSAppOnMac && activeTitleId == Self.storyOfSeasonsTitleId

        setenv("MELONX_IOS_EVENTWAIT_PROMOTION", enableEventWaitPromotion ? "1" : "0", 1)
        setenv("MELONX_IOS_NV_WAIT_PROMOTION", enableNvWaitPromotion ? "1" : "0", 1)
        setenv("MELONX_IOS_NV_WAIT_BLOCKING", enableNvWaitBlocking ? "1" : "0", 1)
        setenv("MELONX_IOS_NV_WAIT_TIMEOUT_PROMOTION", enableNvWaitTimeoutPromotion ? "1" : "0", 1)

        LogCapture.shared.logDiagnostic("Env setup: iosEventWaitPromotionFallback=\(enableEventWaitPromotion), iosNvWaitPromotionFallback=\(enableNvWaitPromotion), iosNvWaitBlocking=\(enableNvWaitBlocking), iosNvWaitTimeoutPromotion=\(enableNvWaitTimeoutPromotion)")

        var useDualMappedJIT: Bool
        if #available(iOS 19, *) {
            useDualMappedJIT = nativeSettings.setting(forKey: "DUAL_MAPPED_JIT", default: true).value
        } else {
            useDualMappedJIT = nativeSettings.setting(forKey: "DUAL_MAPPED_JIT", default: false).value
        }

        if activeTitleId == Self.storyOfSeasonsTitleId && !ProcessInfo.processInfo.isiOSAppOnMac && !useDualMappedJIT {
            useDualMappedJIT = true
            LogCapture.shared.logDiagnostic("Env setup: forcing DualMappedJIT for Story of Seasons iOS load-save compatibility")
        }

        LogCapture.shared.logDiagnostic("Env setup: requested DualMappedJIT=\(useDualMappedJIT)")
        
        if useDualMappedJIT {
            setenv("DUAL_MAPPED_JIT", "1", 1)
            Self.succeededJIT = RyujinxBridge.initialize_dualmapped()

            if !Self.succeededJIT {
                print("[MeloNX] Dual-mapped JIT init failed, falling back to standard JIT mapping.")
                setenv("DUAL_MAPPED_JIT", "0", 1)
            }
        } else {
            setenv("DUAL_MAPPED_JIT", "0", 1)
            Self.succeededJIT = true
        }

        LogCapture.shared.logDiagnostic("Env setup: dualMappedJitInitSuccess=\(Self.succeededJIT)")
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", "1", 1)
            LogCapture.shared.logDiagnostic("Env setup: MTLCreateSystemDefaultDevice unavailable, forcing argument buffers=1")
            return
        }
        
        let supportsArgumentBuffersTier2 = device.argumentBuffersSupport.rawValue >= MTLArgumentBuffersTier.tier2.rawValue
        var useMetalArgumentBuffers = supportsArgumentBuffersTier2

        setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", useMetalArgumentBuffers ? "1" : "0", 1)
        LogCapture.shared.logDiagnostic("Env setup: device=\(device.name), argumentBuffersTier2=\(supportsArgumentBuffersTier2), usingArgumentBuffers=\(useMetalArgumentBuffers)")
    }

    private func applyLargeGameMemoryProfileIfNeeded(for game: Game, config: inout Ryujinx.Arguments, crashForensicsMode: Bool) {
        guard !ProcessInfo.processInfo.isiOSAppOnMac else {
            return
        }

        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let gameSizeBytes = getGameFileSizeBytes(for: game)
        let isLargeGame = (gameSizeBytes ?? 0) >= Self.largeGameThresholdBytes
        let isMediumGameOnLowMemoryDevice = (gameSizeBytes ?? 0) >= Self.mediumGameThresholdBytes && physicalMemory <= Self.lowMemoryDeviceThresholdBytes

        var triggers: [String] = []

        if isLargeGame {
            triggers.append("largeGame")
        }

        if isMediumGameOnLowMemoryDevice {
            triggers.append("mediumGameOnLowMemoryDevice")
        }

        if config.expandRam && physicalMemory <= Self.standardMemoryDeviceThresholdBytes {
            triggers.append("expandRamOn<=8GiBDevice")
        }

        if config.memoryManagerMode == "HostMappedUnsafe" && config.expandRam {
            triggers.append("hostMappedUnsafe+expandRam")
        }

        guard !triggers.isEmpty else {
            return
        }

        var appliedAdjustments: [String] = []

        if config.memoryManagerMode == "HostMappedUnsafe" {
            config.memoryManagerMode = "HostMapped"
            appliedAdjustments.append("memoryManagerMode=HostMapped")
        }

        if config.expandRam {
            config.expandRam = false
            appliedAdjustments.append("expandRam=false")
        }

        if config.enableDockedMode {
            config.enableDockedMode = false
            appliedAdjustments.append("enableDockedMode=false")
        }

        if (isLargeGame || isMediumGameOnLowMemoryDevice) && config.resscale > 0.75 {
            config.resscale = 0.75
            appliedAdjustments.append("resolutionScale=0.75")
        }

        if !appliedAdjustments.isEmpty {
            let sizeGiB = gameSizeBytes.map { String(format: "%.2f", Double($0) / 1_073_741_824.0) } ?? "unknown"
            print("[MeloNX] iOS memory safety profile enabled (size=\(sizeGiB) GiB, physicalMemory=\(physicalMemory) bytes, triggers=\(triggers.joined(separator: ","))): \(appliedAdjustments.joined(separator: ", "))")
            LogCapture.shared.logDiagnostic("iOS memory safety profile applied: sizeGiB=\(sizeGiB), crashForensics=\(crashForensicsMode), triggers=\(triggers.joined(separator: ",")), adjustments=\(appliedAdjustments.joined(separator: ","))")
        }
    }

    private func getGameFileSizeBytes(for game: Game) -> Int64? {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]

        guard let values = try? game.fileURL.resourceValues(forKeys: keys) else {
            return nil
        }

        if let totalAllocated = values.totalFileAllocatedSize {
            return Int64(totalAllocated)
        }

        if let allocated = values.fileAllocatedSize {
            return Int64(allocated)
        }

        if let fileSize = values.fileSize {
            return Int64(fileSize)
        }

        return nil
    }

    private func applyStoryOfSeasonsCompatibilityProfileIfNeeded(for game: Game, config: inout Ryujinx.Arguments) {
        guard !ProcessInfo.processInfo.isiOSAppOnMac,
              game.titleId.lowercased() == Self.storyOfSeasonsTitleId else {
            return
        }

        if config.memoryManagerMode != "SoftwarePageTable" {
            config.memoryManagerMode = "SoftwarePageTable"
            LogCapture.shared.logDiagnostic("Story of Seasons compatibility: forcing memory manager mode SoftwarePageTable")
        }

        let normalizedArgs = Set(config.additionalArgs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        if !normalizedArgs.contains("--backend-threading") {
            config.additionalArgs.append("--backend-threading")
            config.additionalArgs.append("Off")
            LogCapture.shared.logDiagnostic("Story of Seasons compatibility: forcing --backend-threading Off")
        }
    }
}
