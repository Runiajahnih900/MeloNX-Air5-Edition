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
        enableJIT()
        MusicSelectorView.stopMusic()
        nativeSettings.isVirtualController.value = controllerManager.hasVirtualController()
        MetalView.createView()
        
        guard let currentGame else { return }

        LogCapture.shared.startGameSessionLog(gameTitle: currentGame.titleName, titleId: currentGame.titleId)
        
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
            if normalizedTitleId == "010071b00f63a000" {
                if config.memoryManagerMode != "HostMapped" {
                    print("[MeloNX] Eastward stability profile: memory mode \(config.memoryManagerMode) -> HostMapped")
                    config.memoryManagerMode = "HostMapped"
                }

                if config.expandRam {
                    print("[MeloNX] Eastward stability profile: disabling Expand Guest RAM")
                    config.expandRam = false
                }

                if config.ignoreMissingServices {
                    print("[MeloNX] Eastward stability profile: disabling Ignore Missing Services")
                    config.ignoreMissingServices = false
                }

                if !config.additionalArgs.contains("--disable-guest-logs") {
                    config.additionalArgs.append("--disable-guest-logs")
                }

                if !config.additionalArgs.contains("--disable-stub-logs") {
                    config.additionalArgs.append("--disable-stub-logs")
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

        LogCapture.shared.logDiagnostic("Config summary: memoryMode=\(config.memoryManagerMode), expandRam=\(config.expandRam), hypervisor=\(config.hypervisor), debugLogs=\(config.debuglogs), traceLogs=\(config.tracelogs), ignoreMissingServices=\(config.ignoreMissingServices), controllerCount=\(config.inputids.count)")
        
        print(config.inputids)
        configureEnvironmentVariables()
        
        do {
            try ryujinx.start(with: config)
        } catch {
            print("Failed to start game '\(currentGame.titleId)': \(error)")
            LogCapture.shared.endGameSessionLog()
        }
    }
    
    private func configureEnvironmentVariables() {
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
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", "1", 1)
            return
        }
        
        let supportsArgumentBuffersTier2 = device.argumentBuffersSupport.rawValue >= MTLArgumentBuffersTier.tier2.rawValue
        setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", supportsArgumentBuffersTier2 ? "1" : "0", 1)
    }
}
