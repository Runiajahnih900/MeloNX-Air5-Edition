//
//  EmulationView.swift
//  MeloNX
//
//  Created by Stossy11 on 09/02/2025.
//

import SwiftUI

// Emulation View
struct EmulationView: View {
    @AppStorage("performacehud") var performacehud: Bool = false
    @AppStorage("isVirtualController") var isVCA: Bool = true
    @AppStorage("showScreenShotButton") var ssb: Bool = false
    @AppStorage("showlogsgame") var showlogsgame: Bool = false
    
    @AppStorage("On-ScreenControllerOpacity") var controllerOpacity: Double = 1.0
    
    @AppStorage("OldView") var oldView = true
    @State var isPresentedThree: Bool = false
    @State var isAirplaying = Air.shared.connected
    @Binding var startgame: Game?
    
    @Environment(\.scenePhase) var scenePhase
    @State private var isInBackground = false
    @State var showSettings = false
    @State var pauseEmu = true
    @AppStorage("location-enabled") var locationenabled: Bool = false
    @FocusState private var isFocused: Bool
    @ObservedObject var ryujijnx = Ryujinx.shared
    
    var body: some View {
        ZStack {
            if oldView {
                Color.black
                    .ignoresSafeArea()
                    .edgesIgnoringSafeArea(.all)
                    .allowsHitTesting(false)
            }
            
            if isAirplaying {
                TouchView()
                    .ignoresSafeArea()
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        Air.play(AnyView(MetalView().ignoresSafeArea().edgesIgnoringSafeArea(.all)))
                    }
            } else {
                MetalViewContainer() // The Emulation View
            }
            
            // Above Emulation View
            
            if isVCA {
                ControllerView(isEditing: .constant(false), gameId: startgame?.titleId) // Virtual Controller
                    .opacity(controllerOpacity)
                    .allowsHitTesting(true)
            }
            
            
            VStack {
                HStack {
                    if !performacehud, showlogsgame, ProcessInfo.processInfo.isLowPowerModeEnabled {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 10, height: 10)
                            .padding()
                    }
                    

                    if ssb {
                        Menu {
                            Button {
                                pause_emulation(pauseEmu)
                                pauseEmu.toggle()
                            } label: {
                                Label {
                                    Text(pauseEmu ? "Pause" : "Play")
                                } icon: {
                                    Image(systemName: pauseEmu ? "pause.circle" : "play.circle")
                                }
                            }
                            
                            Button {
                                // ryujijnx.config?.aspectRatio
                                ryujijnx.aspectRatio = nextAspectRatio(current: ryujijnx.aspectRatio)
                            } label: {
                                Label {
                                    Text(ryujijnx.aspectRatio.displayName)
                                } icon: {
                                    Image(systemName: "rectangle.expand.vertical")
                                }
                            }
                            
                            Button(role: .destructive) {
                                startgame = nil
                                stop_emulation()
                                try? Ryujinx.shared.stop()
                            } label: {
                                Label {
                                    Text("Exit (Unstable)")
                                } icon: {
                                    Image(systemName: "x.circle")
                                }
                            }
                        } label: {
                            ExtButtonIconView(button: .guide, opacity: 0.4)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .padding()
                    }
                    
                    
                    Spacer()
                    
                    
                    if performacehud, getenv("MTL_HUD_ENABLED").flatMap({ String(cString: $0) }) != "1" {
                        PerformanceOverlayView()
                            .opacity(controllerOpacity)
                            .padding(.horizontal)
                    }
                    
                }
                
                Spacer()
            }
            
            if showlogsgame, get_current_fps() != 0 {
                VStack {
                    LogFileView(isfps: false)
                    
                    Spacer()
                }
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
            
            LocationManager.sharedInstance.startUpdatingLocation()
            Air.shared.connectionCallbacks.append { cool in
                DispatchQueue.main.async {
                    isAirplaying = cool
                    // print(cool)
                }
            }
            
            RegisterCallback("exit-emulation") { cool in
                DispatchQueue.main.async {
                    print(cool)
                    startgame = nil
                    stop_emulation()
                    try? ryujijnx.stop()
                }
            }
        }
        .onKeyPress()
        .focused($isFocused)
        .onChange(of: scenePhase) { newPhase in
            // Detect when the app enters the background
            if newPhase == .background {
                pause_emulation(true)
                isInBackground = true
            } else if newPhase == .active {
                pause_emulation(false)
                isInBackground = false
            } else if newPhase == .inactive {
                pause_emulation(true)
                isInBackground = true
            }
        }
        .sheet(isPresented: $showSettings) {
            // PerGameSettingsView(titleId: startgame?.titleId ?? "", manager: InGameSettingsManager.shared)
                // .onDisappear() {
                    // InGameSettingsManager.shared.saveSettings()
                // }
        }
    }
    
    func nextAspectRatio(current: AspectRatio) -> AspectRatio {
        let all = AspectRatio.allCases
        if let index = all.firstIndex(of: current) {
            let nextIndex = (index + 1) % all.count
            return all[nextIndex]
        } else {
            return .fixed16x9 // Default fallback
        }
    }

}

// This is just to stop the sound on macOS when doing a keypress
extension View {
    func onKeyPress() -> some View {
        if #available(iOS 17.0, *), ProcessInfo.processInfo.isiOSAppOnMac {
            return AnyView(self
                .focusable()
                .focusEffectDisabled()
                .onKeyPress { _ in
                    return .handled
                })
        } else {
            return AnyView(self)
        }
    }
}

