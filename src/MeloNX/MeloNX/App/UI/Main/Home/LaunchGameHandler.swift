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
    private static let eastwardTitleId = "010071b00f63a000"
    
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
        guard let currentGame else { return }

        LogCapture.shared.startGameSessionLog(gameTitle: currentGame.titleName, titleId: currentGame.titleId)
        LogCapture.shared.logDiagnostic("Launch stage: startGame invoked for titleId=\(currentGame.titleId)")

        enableJIT()
        LogCapture.shared.logDiagnostic("Launch stage: JIT check finished. jitenabled=\(ryujinx.jitenabled), ignoreJIT=\(nativeSettings.ignoreJIT.value), hasTXM=\(ProcessInfo.processInfo.hasTXM)")

        MusicSelectorView.stopMusic()
        nativeSettings.isVirtualController.value = controllerManager.hasVirtualController()
        MetalView.createView()
        
        persettings.loadSettings()
        
        var config = persettings.config[currentGame.titleId] ?? self.config

        let allowUnsafeVerboseLogs = nativeSettings.setting(forKey: "allowUnsafeVerboseLogs", default: false).value
        if !ProcessInfo.processInfo.isiOSAppOnMac && !allowUnsafeVerboseLogs {
            if config.tracelogs || config.debuglogs {
                print("[MeloNX] Verbose logs (trace/debug) disabled on iOS for stability. Set 'allowUnsafeVerboseLogs' to true to override.")
            }

            config.tracelogs = false
            config.debuglogs = false
        }

        if !ProcessInfo.processInfo.isiOSAppOnMac {
            let normalizedTitleId = currentGame.titleId.lowercased()
            if normalizedTitleId == Self.eastwardTitleId {
                if config.memoryManagerMode != "HostMapped" {
                    print("[MeloNX] Eastward compatibility profile: memory mode \(config.memoryManagerMode) -> HostMapped")
                    config.memoryManagerMode = "HostMapped"
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

                config.additionalArgs.removeAll { $0 == "--disable-guest-logs" || $0 == "--disable-stub-logs" }
                LogCapture.shared.logDiagnostic("Eastward diagnostics profile: removed forced --disable-guest-logs/--disable-stub-logs from additional args")
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

        LogCapture.shared.logDiagnostic("Config summary: memoryMode=\(config.memoryManagerMode), disablePTC=\(config.disablePTC), expandRam=\(config.expandRam), hypervisor=\(config.hypervisor), debugLogs=\(config.debuglogs), traceLogs=\(config.tracelogs), macroHLE=\(config.macroHLE), docked=\(config.enableDockedMode), ignoreMissingServices=\(config.ignoreMissingServices), additionalArgs=\(config.additionalArgs.joined(separator: " ")), controllerCount=\(config.inputids.count)")
        
        print(config.inputids)
        LogCapture.shared.logDiagnostic("Launch stage: configuring environment variables")
        configureEnvironmentVariables(for: config)
        LogCapture.shared.logDiagnostic("Launch stage: invoking core start")
        
        do {
            try ryujinx.start(with: config)
        } catch {
            print("Failed to start game '\(currentGame.titleId)': \(error)")
            LogCapture.shared.logDiagnostic("Launch stage: failed before entering core loop. error=\(error)")
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

        let normalizedTitleId = currentGame?.titleId.lowercased() ?? "unknown"
        let isEastwardOnIOS = !ProcessInfo.processInfo.isiOSAppOnMac && normalizedTitleId == Self.eastwardTitleId
        let requestedDualMappedJIT = useDualMappedJIT

        if isEastwardOnIOS {
            if #available(iOS 19, *) {
                // Keep user choice on newer iOS versions.
            } else {
                useDualMappedJIT = false
            }

            if requestedDualMappedJIT && !useDualMappedJIT {
                LogCapture.shared.logDiagnostic("JIT env override: disabling dual-mapped JIT for Eastward on iOS < 19 to avoid startup stalls")
            }
        }

        LogCapture.shared.logDiagnostic("JIT env decision: titleId=\(normalizedTitleId), requestedDualMapped=\(requestedDualMappedJIT), effectiveDualMapped=\(useDualMappedJIT), hasTXM=\(ProcessInfo.processInfo.hasTXM)")
        
        if useDualMappedJIT {
            setenv("DUAL_MAPPED_JIT", "1", 1)
            Self.succeededJIT = RyujinxBridge.initialize_dualmapped()
            LogCapture.shared.logDiagnostic("JIT env apply: initialize_dualmapped result=\(Self.succeededJIT)")

            if !Self.succeededJIT {
                print("[MeloNX] Dual-mapped JIT init failed, falling back to standard JIT mapping.")
                setenv("DUAL_MAPPED_JIT", "0", 1)
                LogCapture.shared.logDiagnostic("JIT env apply: dual-mapped init failed, switched to standard mapping")
            }
        } else {
            setenv("DUAL_MAPPED_JIT", "0", 1)
            Self.succeededJIT = true
            LogCapture.shared.logDiagnostic("JIT env apply: using standard JIT mapping")
        }
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", "1", 1)
            LogCapture.shared.logDiagnostic("Metal env decision: no default MTL device, forcing MVK argument buffers=1")
            return
        }
        
        let supportsArgumentBuffersTier2 = device.argumentBuffersSupport.rawValue >= MTLArgumentBuffersTier.tier2.rawValue
        setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", supportsArgumentBuffersTier2 ? "1" : "0", 1)
        LogCapture.shared.logDiagnostic("Metal env decision: argumentBuffersTier2=\(supportsArgumentBuffersTier2)")
    }
}
