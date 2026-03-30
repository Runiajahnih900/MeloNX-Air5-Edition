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
        
        persettings.loadSettings()
        LogCapture.shared.logDiagnostic("Launch stage: per-game settings loaded")
        
        var config = persettings.config[currentGame.titleId] ?? self.config

        let crashForensicsMode = nativeSettings.setting(forKey: "crashForensicsMode", default: true).value
        let eastwardSceneForensicsMode = nativeSettings.setting(forKey: "eastwardSceneForensicsMode", default: false).value
        let allowUnsafeVerboseLogs = nativeSettings.setting(forKey: "allowUnsafeVerboseLogs", default: false).value
        let allowStubLogs = nativeSettings.setting(forKey: "allowStubLogs", default: false).value
        LogCapture.shared.logDiagnostic("Forensics toggles: crashForensics=\(crashForensicsMode), eastwardSceneForensics=\(eastwardSceneForensicsMode), allowStubLogs=\(allowStubLogs), allowUnsafeVerboseLogs=\(allowUnsafeVerboseLogs)")

        if eastwardSceneForensicsMode {
            config.debuglogs = true
            config.tracelogs = false
            LogCapture.shared.logDiagnostic("Eastward scene forensics mode enabled: forcing debugLogs=true and traceLogs=false")
        }

        if !ProcessInfo.processInfo.isiOSAppOnMac && !allowUnsafeVerboseLogs && !eastwardSceneForensicsMode {
            if config.tracelogs || config.debuglogs {
                print("[MeloNX] Verbose logs (trace/debug) disabled on iOS for stability. Set 'allowUnsafeVerboseLogs' to true to override.")
            }

            config.tracelogs = false
            config.debuglogs = false
        }

        if !ProcessInfo.processInfo.isiOSAppOnMac {
            let normalizedTitleId = currentGame.titleId.lowercased()
            if normalizedTitleId == "010071b00f63a000" {
                let targetMemoryMode = "HostMapped"
                if config.memoryManagerMode != targetMemoryMode {
                    print("[MeloNX] Eastward compatibility profile: memory mode \(config.memoryManagerMode) -> \(targetMemoryMode)")
                    config.memoryManagerMode = targetMemoryMode
                }

                if config.expandRam {
                    print("[MeloNX] Eastward stability profile: disabling Expand Guest RAM")
                    config.expandRam = false
                }

                if !config.disablePTC {
                    print("[MeloNX] Eastward stability profile: disabling PTC")
                    config.disablePTC = true
                }

                if config.ignoreMissingServices {
                    print("[MeloNX] Eastward stability profile: disabling Ignore Missing Services")
                    config.ignoreMissingServices = false
                }

                if !config.macroHLE {
                    print("[MeloNX] Eastward compatibility profile: enabling Macro HLE")
                    config.macroHLE = true
                }

                if !config.enableDockedMode {
                    print("[MeloNX] Eastward compatibility profile: enabling Docked Mode")
                    config.enableDockedMode = true
                }

                if config.enableShaderCache {
                    print("[MeloNX] Eastward compatibility profile: disabling Shader Cache")
                    config.enableShaderCache = false
                    LogCapture.shared.logDiagnostic("Eastward compatibility: forcing config.enableShaderCache=false to reduce Vulkan cache-related stalls")
                }

                let hadManualDisableShaderCacheArg = config.additionalArgs.contains {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "--disable-shader-cache"
                }

                if hadManualDisableShaderCacheArg {
                    config.enableShaderCache = false
                    config.additionalArgs.removeAll {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "--disable-shader-cache"
                    }
                    LogCapture.shared.logDiagnostic("Eastward compatibility: normalized --disable-shader-cache into config.enableShaderCache=false")
                }

                if !config.additionalArgs.contains(where: {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "--force-dummy-audio"
                }) {
                    config.additionalArgs.append("--force-dummy-audio")
                    LogCapture.shared.logDiagnostic("Eastward compatibility: forcing dummy audio backend for iOS stability test (no sound output)")
                }

                if let backendThreadingIndex = config.additionalArgs.firstIndex(where: {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "--backend-threading"
                }) {
                    if backendThreadingIndex + 1 < config.additionalArgs.count {
                        config.additionalArgs.remove(at: backendThreadingIndex + 1)
                    }

                    config.additionalArgs.remove(at: backendThreadingIndex)
                }

                config.additionalArgs.append(contentsOf: ["--backend-threading", "Off"])
                LogCapture.shared.logDiagnostic("Eastward compatibility: forcing --backend-threading Off to avoid iOS render-thread stalls")

                if eastwardSceneForensicsMode {
                    config.additionalArgs.removeAll {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "--disable-guest-logs"
                    }

                    if allowStubLogs {
                        config.additionalArgs.removeAll {
                            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "--disable-stub-logs"
                        }
                        LogCapture.shared.logDiagnostic("Eastward forensics active: guest logs enabled, stub logs enabled by user override")
                    } else {
                        config.additionalArgs.removeAll {
                            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "--disable-stub-logs"
                        }
                        config.additionalArgs.append("--disable-stub-logs")
                        LogCapture.shared.logDiagnostic("Eastward forensics active: guest logs enabled, stub logs disabled to reduce scene-stall log flood")
                    }
                } else {
                    if !config.additionalArgs.contains(where: {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "--disable-guest-logs"
                    }) {
                        config.additionalArgs.append("--disable-guest-logs")
                    }

                    if !config.additionalArgs.contains(where: {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "--disable-stub-logs"
                    }) {
                        config.additionalArgs.append("--disable-stub-logs")
                    }

                    if crashForensicsMode {
                        LogCapture.shared.logDiagnostic("Eastward stability mode active: guest/stub logs disabled by default. Enable Eastward Scene Forensics to capture scene-level guest logs.")
                    }
                }
            }
        }

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
        var useDualMappedJIT: Bool
        if #available(iOS 19, *) {
            useDualMappedJIT = nativeSettings.setting(forKey: "DUAL_MAPPED_JIT", default: true).value
        } else {
            useDualMappedJIT = nativeSettings.setting(forKey: "DUAL_MAPPED_JIT", default: false).value
        }

                if !ProcessInfo.processInfo.isiOSAppOnMac,
                     currentGame?.titleId.lowercased() == "010071b00f63a000" {
            useDualMappedJIT = true
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
        setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", supportsArgumentBuffersTier2 ? "1" : "0", 1)
        LogCapture.shared.logDiagnostic("Env setup: device=\(device.name), argumentBuffersTier2=\(supportsArgumentBuffersTier2)")
    }
}
