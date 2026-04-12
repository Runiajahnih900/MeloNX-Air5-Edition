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
    private static let crashResilienceGameThresholdBytes: Int64 = 4_294_967_296 // 4 GiB
    private static let lowMemoryDeviceThresholdBytes: UInt64 = 6_442_450_944 // 6 GiB
    private static let standardMemoryDeviceThresholdBytes: UInt64 = 8_589_934_592 // 8 GiB
    private static let storyOfSeasonsTitleId = "0100ed400eec2000"
    private static let theGardenPathTitleId = "010030f01a882000"
    private static let oriAndTheBlindForestTitleId = "010046601125a000"
    private static let oriAndTheWillOfTheWispsTitleId = "01008dd013200000"
    
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
        applyGeneralCrashResilienceProfileIfNeeded(for: currentGame, config: &config)

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
        LogCapture.shared.logDiagnostic("MELONX_IOS_CRASH_RESILIENCE_V1_ACTIVE: generalized compatibility profile enabled")

        let enableEventWaitPromotion = nativeSettings.setting(forKey: "iosEventWaitPromotionFallback", default: false).value
        let enableNvWaitPromotion = nativeSettings.setting(forKey: "iosNvWaitPromotionFallback", default: false).value
        let activeTitleId = currentGame?.titleId.lowercased() ?? ""
        let isStoryOfSeasons = activeTitleId == Self.storyOfSeasonsTitleId
        let isTheGardenPath = activeTitleId == Self.theGardenPathTitleId
        let isOriAndTheBlindForest = activeTitleId == Self.oriAndTheBlindForestTitleId
        let isOriAndTheWillOfTheWisps = activeTitleId == Self.oriAndTheWillOfTheWispsTitleId
        let isOriFamily = isOriAndTheBlindForest || isOriAndTheWillOfTheWisps
        let genericCrashResilienceEnabled = shouldEnableGeneralCrashResilience(for: currentGame)
        let lowMemoryFallbackEnabled = ProcessInfo.processInfo.physicalMemory <= Self.lowMemoryDeviceThresholdBytes

        // Hybrid strategy:
        // - keep generalized profile for broad compatibility
        // - hard-enable known fragile titles on iOS save/load or early boot paths
        let crashResilienceEnabled = genericCrashResilienceEnabled || isStoryOfSeasons || isTheGardenPath || isOriFamily
        let enableNvWaitBlocking = !ProcessInfo.processInfo.isiOSAppOnMac && (crashResilienceEnabled || lowMemoryFallbackEnabled)

        // For Garden/ORI, avoid syncpoint timeout promotion because forced promotion can
        // desynchronize guest/host GPU progress and lead to early-load stalls/crashes.
        var enableNvWaitTimeoutPromotion = !ProcessInfo.processInfo.isiOSAppOnMac && (crashResilienceEnabled || lowMemoryFallbackEnabled)
        if isTheGardenPath || isOriFamily {
            enableNvWaitTimeoutPromotion = false
        }

        setenv("MELONX_IOS_EVENTWAIT_PROMOTION", enableEventWaitPromotion ? "1" : "0", 1)
        setenv("MELONX_IOS_NV_WAIT_PROMOTION", enableNvWaitPromotion ? "1" : "0", 1)
        setenv("MELONX_IOS_NV_WAIT_BLOCKING", enableNvWaitBlocking ? "1" : "0", 1)
        setenv("MELONX_IOS_NV_WAIT_TIMEOUT_PROMOTION", enableNvWaitTimeoutPromotion ? "1" : "0", 1)
        let crashResilienceEnvValue = crashResilienceEnabled ? "1" : "0"
        setenv("MELONX_IOS_CRASH_RESILIENCE", crashResilienceEnvValue, 1)
        // Backward-compat bridge for older cores still expecting legacy key.
        setenv("MELONX_IOS_SOS_CRASH_RESILIENCE", crashResilienceEnvValue, 1)

        // Ori WotW shows repeated low-address invalid accesses; tolerating those can lock the game in
        // endless recovery loops. Keep invalid-access resilience OFF for this title so it fails fast.
        let invalidAccessResilienceEnabled = !(activeTitleId == Self.oriAndTheWillOfTheWispsTitleId)
        setenv("MELONX_IOS_INVALID_ACCESS_RESILIENCE", invalidAccessResilienceEnabled ? "1" : "0", 1)

        LogCapture.shared.logDiagnostic("Env setup: titleId=\(activeTitleId), isSOS=\(isStoryOfSeasons), isGarden=\(isTheGardenPath), isOri=\(isOriFamily), iosEventWaitPromotionFallback=\(enableEventWaitPromotion), iosNvWaitPromotionFallback=\(enableNvWaitPromotion), iosNvWaitBlocking=\(enableNvWaitBlocking), iosNvWaitTimeoutPromotion=\(enableNvWaitTimeoutPromotion), crashResilience=\(crashResilienceEnabled), invalidAccessResilience=\(invalidAccessResilienceEnabled), lowMemoryFallback=\(lowMemoryFallbackEnabled)")

        var useDualMappedJIT: Bool
        if #available(iOS 19, *) {
            useDualMappedJIT = nativeSettings.setting(forKey: "DUAL_MAPPED_JIT", default: true).value
        } else {
            useDualMappedJIT = nativeSettings.setting(forKey: "DUAL_MAPPED_JIT", default: false).value
        }

        // Godot-based titles (The Garden Path / Ori family) are observed to freeze at early boot on some iOS builds
        // when dual-mapped JIT is enabled, even if initialization succeeds.
        if isTheGardenPath || isOriFamily {
            if useDualMappedJIT {
                LogCapture.shared.logDiagnostic("Env setup: forcing DualMappedJIT=0 for Garden/ORI early-load stability")
            }
            useDualMappedJIT = false
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

        // Garden/ORI are Godot-based and have shown early-load instability on iOS with
        // Metal argument buffers enabled through MoltenVK on some devices/OS versions.
        if isTheGardenPath || isOriFamily {
            useMetalArgumentBuffers = false
            LogCapture.shared.logDiagnostic("Env setup: forcing argument buffers=0 for Garden/ORI stability")
        }

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

    private func shouldEnableGeneralCrashResilience(for game: Game?) -> Bool {
        guard !ProcessInfo.processInfo.isiOSAppOnMac,
              let game else {
            return false
        }

        let gameSizeBytes = getGameFileSizeBytes(for: game) ?? 0
        let lowMemoryDevice = ProcessInfo.processInfo.physicalMemory <= Self.lowMemoryDeviceThresholdBytes

        // Generalized resilience trigger:
        // - Low-memory devices (historically most crash-prone)
        // - Medium/large titles where NV wait/fence stalls are more likely
        return lowMemoryDevice || gameSizeBytes >= Self.crashResilienceGameThresholdBytes
    }

    private func applyGeneralCrashResilienceProfileIfNeeded(for game: Game, config: inout Ryujinx.Arguments) {
        let activeTitleId = game.titleId.lowercased()
        let isStoryOfSeasons = activeTitleId == Self.storyOfSeasonsTitleId
        let isTheGardenPath = activeTitleId == Self.theGardenPathTitleId
        let isOriAndTheBlindForest = activeTitleId == Self.oriAndTheBlindForestTitleId
        let isOriAndTheWillOfTheWisps = activeTitleId == Self.oriAndTheWillOfTheWispsTitleId
        let isOriFamily = isOriAndTheBlindForest || isOriAndTheWillOfTheWisps

        guard shouldEnableGeneralCrashResilience(for: game) || isStoryOfSeasons || isTheGardenPath || isOriFamily else {
            return
        }

        var adjustments: [String] = []

        // Prefer safer memory mode for heavier titles on iOS.
        if config.memoryManagerMode == "HostMappedUnsafe" {
            config.memoryManagerMode = "HostMapped"
            adjustments.append("memoryMode=HostMapped")
        }

        // Keep backend threading conservative to reduce race-related stalls on mobile iOS GPUs.
        // For SOS this is treated as hard override.
        let normalizedArgs = config.additionalArgs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        if let backendIndex = normalizedArgs.firstIndex(of: "--backend-threading") {
            if backendIndex + 1 < config.additionalArgs.count,
               (config.additionalArgs[backendIndex + 1].lowercased() != "off" || isStoryOfSeasons) {
                config.additionalArgs[backendIndex + 1] = "Off"
                adjustments.append("backendThreading=Off")
            }
        } else {
            config.additionalArgs.append("--backend-threading")
            config.additionalArgs.append("Off")
            adjustments.append("backendThreading=Off")
        }

        if (isStoryOfSeasons || isTheGardenPath || isOriFamily), config.memoryManagerMode != "SoftwarePageTable" {
            config.memoryManagerMode = "SoftwarePageTable"
            if isStoryOfSeasons {
                adjustments.append("memoryMode=SoftwarePageTable(SOS)")
            } else if isTheGardenPath {
                adjustments.append("memoryMode=SoftwarePageTable(Garden)")
            } else if isOriAndTheWillOfTheWisps {
                adjustments.append("memoryMode=SoftwarePageTable(OriWotW)")
            } else {
                adjustments.append("memoryMode=SoftwarePageTable(ORI)")
            }
        }

        // Garden/ORI on iOS are sensitive to HLE service behavior during early boot.
        // Prefer stricter service emulation and avoid suppressing missing service faults.
        if isTheGardenPath || isOriFamily {
            if config.ignoreMissingServices {
                config.ignoreMissingServices = false
                adjustments.append("ignoreMissingServices=false(Garden/ORI)")
            }

            if !config.macroHLE {
                config.macroHLE = true
                adjustments.append("macroHLE=true(Garden/ORI)")
            }

            // Conservative startup path for fragile Godot/Unity boots on iOS:
            // avoid carrying translation/shader cache state across launches.
            if !config.disablePTC {
                config.disablePTC = true
                adjustments.append("disablePTC=true(Garden/ORI)")
            }

            if config.enableShaderCache {
                config.enableShaderCache = false
                adjustments.append("shaderCache=false(Garden/ORI)")
            }
        }

        if !adjustments.isEmpty {
            LogCapture.shared.logDiagnostic("General crash resilience profile applied for \(game.titleId): \(adjustments.joined(separator: ","))")
        }
    }
}
