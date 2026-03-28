// EmulatorView.swift
// MeloNX Air5 Edition
//
// Main emulator screen: game display + on-screen controller, optimized for iPad Air 5.

import SwiftUI
import MetalKit

struct EmulatorView: View {
    @EnvironmentObject var vm: EmulatorViewModel
    @State private var showHUD = true
    @State private var hudHideTimer: Timer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Game display
            MetalView()
                .ignoresSafeArea()
                .onTapGesture {
                    showHUD = true
                    resetHUDTimer()
                }

            // On-screen controller overlay
            if vm.isControllerVisible {
                OnScreenControllerView()
            }

            // HUD overlay (FPS, game title, controls)
            if showHUD {
                HUDOverlay()
                    .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            resetHUDTimer()
        }
    }

    private func resetHUDTimer() {
        hudHideTimer?.invalidate()
        hudHideTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
            Task { @MainActor in
                withAnimation { showHUD = false }
            }
        }
    }
}

// MARK: - Metal View (UIViewRepresentable)

struct MetalView: UIViewRepresentable {

    func makeCoordinator() -> MetalRenderer? {
        MetalRenderer()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.preferredFramesPerSecond = 60
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        // The coordinator (MetalRenderer) is retained by the UIViewRepresentable.
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}

// MARK: - HUD Overlay

struct HUDOverlay: View {
    @EnvironmentObject var vm: EmulatorViewModel

    var body: some View {
        VStack {
            HStack {
                // FPS indicator
                Label("\(vm.fps) FPS", systemImage: "speedometer")
                    .font(.caption.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(fpsColor)

                Spacer()

                // Game title
                Text(vm.loadedGameTitle)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.6), in: Capsule())

                Spacer()

                // Pause / menu
                Button {
                    vm.pauseResume()
                } label: {
                    Image(systemName: vm.emulatorState == .paused ? "play.fill" : "pause.fill")
                        .padding(10)
                        .background(.black.opacity(0.6), in: Circle())
                }

                Button {
                    vm.stopEmulation()
                } label: {
                    Image(systemName: "xmark")
                        .padding(10)
                        .background(.black.opacity(0.6), in: Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()
        }
        .foregroundStyle(.white)
    }

    private var fpsColor: Color {
        switch vm.fps {
        case 50...:  return .green
        case 30..<50: return .yellow
        default:      return .red
        }
    }
}

// MARK: - On-Screen Controller

struct OnScreenControllerView: View {
    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                // Left side: D-pad + left stick
                LeftControllerPanel()

                Spacer()

                // Center: Start + Select
                CenterControllerPanel()

                Spacer()

                // Right side: ABXY + right buttons
                RightControllerPanel()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Left Controller Panel

struct LeftControllerPanel: View {
    var body: some View {
        VStack(spacing: 16) {
            // Left stick (virtual joystick)
            VirtualJoystick(label: "L")

            // D-Pad
            DPadView()
        }
    }
}

// MARK: - Right Controller Panel

struct RightControllerPanel: View {
    var body: some View {
        VStack(spacing: 16) {
            // ABXY buttons
            ABXYButtonsView()

            // Right stick
            VirtualJoystick(label: "R")
        }
    }
}

// MARK: - Center Controller Panel

struct CenterControllerPanel: View {
    var body: some View {
        HStack(spacing: 20) {
            ControllerButton(label: "−", systemImage: nil)
            ControllerButton(label: nil, systemImage: "house.fill")
            ControllerButton(label: "+", systemImage: nil)
        }
    }
}

// MARK: - Virtual Joystick

struct VirtualJoystick: View {
    let label: String
    @State private var offset: CGSize = .zero

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.15))
                .frame(width: 80, height: 80)

            Circle()
                .fill(.white.opacity(0.4))
                .frame(width: 36, height: 36)
                .offset(offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let maxRadius: CGFloat = 20
                            let delta = value.translation
                            let dist  = sqrt(delta.width * delta.width + delta.height * delta.height)
                            if dist <= maxRadius {
                                offset = delta
                            } else {
                                let scale = maxRadius / dist
                                offset = CGSize(width: delta.width * scale, height: delta.height * scale)
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.spring(duration: 0.15)) {
                                offset = .zero
                            }
                        }
                )

            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.5))
                .offset(y: 30)
        }
    }
}

// MARK: - D-Pad

struct DPadView: View {
    var body: some View {
        ZStack {
            // Horizontal bar
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.2))
                .frame(width: 90, height: 30)
            // Vertical bar
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.2))
                .frame(width: 30, height: 90)

            // Arrow indicators
            VStack(spacing: 0) {
                Image(systemName: "chevron.up").font(.caption2).foregroundStyle(.white.opacity(0.7))
                Spacer().frame(height: 40)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 0) {
                Image(systemName: "chevron.left").font(.caption2).foregroundStyle(.white.opacity(0.7))
                Spacer().frame(width: 40)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - ABXY Buttons

struct ABXYButtonsView: View {
    var body: some View {
        VStack(spacing: 4) {
            ControllerButton(label: "X", systemImage: nil, color: .blue)
            HStack(spacing: 4) {
                ControllerButton(label: "Y", systemImage: nil, color: .yellow)
                Spacer().frame(width: 4)
                ControllerButton(label: "A", systemImage: nil, color: .red)
            }
            ControllerButton(label: "B", systemImage: nil, color: .green)
        }
    }
}

// MARK: - Generic Controller Button

struct ControllerButton: View {
    let label: String?
    let systemImage: String?
    var color: Color = .white

    var body: some View {
        Button { } label: {
            ZStack {
                Circle()
                    .fill(color.opacity(0.25))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .strokeBorder(color.opacity(0.5), lineWidth: 1.5)
                    )

                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color.opacity(0.9))
                } else if let label {
                    Text(label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(color.opacity(0.9))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
