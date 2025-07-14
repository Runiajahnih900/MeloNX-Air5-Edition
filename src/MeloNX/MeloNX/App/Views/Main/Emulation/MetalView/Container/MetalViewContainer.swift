//
//  MetalViewContainer.swift
//  MeloNX
//
//  Created by Stossy11 on 06/07/2025.
//

import SwiftUI

struct MetalViewContainer: View {
    @ObservedObject var ryujinx = Ryujinx.shared
    @AppStorage("OldView") var oldView = true
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if shouldStretchToFillScreen {
                    stretchedView
                } else if oldView {
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    
                    oldStyleView(containerSize: geo.size)
                } else {
                    modernView(containerSize: geo.size)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: ryujinx.aspectRatio)
            .animation(.easeInOut(duration: 0.3), value: oldView)
        }
    }
    
    // MARK: - View Components
    
    private var stretchedView: some View {
        MetalView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(contentMode: .fill)
            .edgesIgnoringSafeArea(.all)
    }
    
    private func oldStyleView(containerSize: CGSize) -> some View {
        let size = targetSize(for: containerSize)
        let isPortrait = containerSize.width < containerSize.height
        
        return ZStack {
            MetalView()
                .frame(width: size.width, height: size.height)
                .aspectRatio(contentMode: .fit)
                .ignoresSafeArea(.container, edges: isPortrait ? .horizontal : .vertical)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func modernView(containerSize: CGSize) -> some View {
        let size = targetSize(for: containerSize)
        let isPortrait = containerSize.width < containerSize.height
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        let scale = calculateScale(isPortrait: isPortrait, isPhone: isPhone)
        
        return ZStack {
            borderedMetalView(size: size)
                .scaleEffect(scale)
                .ignoresSafeArea(.container, edges: isPortrait ? .horizontal : .vertical)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func borderedMetalView(size: CGSize) -> some View {
        let cornerRadius: CGFloat = 16
        let borderWidth: CGFloat = 2
        
        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundColor)
                .shadow(color: shadowColor, radius: 8, x: 0, y: 2)
            
            MetalView()
                .frame(width: size.width - borderWidth * 2, height: size.height - borderWidth * 2)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius - borderWidth, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .frame(width: size.width, height: size.height)
    }
    
    // MARK: - Computed Properties
    
    private var shouldStretchToFillScreen: Bool {
        ryujinx.aspectRatio == .stretched ||
        (ryujinx.aspectRatio == .fixed4x3 && isScreenAspectRatio(4, 3))
    }
    
    private var borderColor: Color {
        colorScheme == .light ? Color.gray : Color(UIColor.darkGray)
    }
    
    private var backgroundColor: Color {
        colorScheme == .light ? .white : Color(.systemGray6)
    }
    
    private var shadowColor: Color {
        colorScheme == .light ? .black.opacity(0.1) : .black.opacity(0.3)
    }
    
    // MARK: - Helper Methods
    
    private func calculateScale(isPortrait: Bool, isPhone: Bool) -> CGFloat {
        let baseScale: CGFloat = isPhone ? 0.95 : 1.0
        return isPortrait ? baseScale : baseScale * 0.92
    }
    
    private func targetSize(for containerSize: CGSize) -> CGSize {
        let targetAspect: CGFloat = {
            switch ryujinx.aspectRatio {
            case .fixed4x3: return 4.0 / 3.0
            case .fixed16x9: return 16.0 / 9.0
            case .fixed16x10: return 16.0 / 10.0
            case .fixed21x9: return 21.0 / 9.0
            case .fixed32x9: return 32.0 / 10.0
            case .stretched: return containerSize.width / containerSize.height
            }
        }()
        
        let safeArea = UIApplication.shared.windows.first?.safeAreaInsets ?? .zero
        let adjustedContainer = CGSize(
            width: containerSize.width - safeArea.left - safeArea.right,
            height: containerSize.height - safeArea.top - safeArea.bottom
        )
        
        if ryujinx.aspectRatio == .stretched {
            return adjustedContainer
        }
        
        let containerAspect = adjustedContainer.width / adjustedContainer.height
        
        if containerAspect > targetAspect {
            let height = adjustedContainer.height
            let width = height * targetAspect
            return CGSize(width: width, height: height)
        } else {
            let width = adjustedContainer.width
            let height = width / targetAspect
            return CGSize(width: width, height: height)
        }
    }
    
    private func isScreenAspectRatio(_ targetWidth: CGFloat, _ targetHeight: CGFloat, tolerance: CGFloat = 0.05) -> Bool {
        let screenSize = UIScreen.main.bounds.size
        let actualRatio = screenSize.width / screenSize.height
        let targetRatio = targetWidth / targetHeight
        return abs(actualRatio - targetRatio) < tolerance
    }
}
