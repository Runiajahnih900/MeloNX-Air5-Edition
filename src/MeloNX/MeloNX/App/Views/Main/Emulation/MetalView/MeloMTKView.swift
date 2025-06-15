//
//  MeloMTKView.swift
//  MeloNX
//
//  Created by Stossy11 on 03/03/2025.
//

import MetalKit
import UIKit

class MeloMTKView: MTKView {
    private var activeTouches: [UITouch] = []
    private var ignoredTouches: Set<UITouch> = []
    private var touchIndexMap: [UITouch: Int] = [:]

    private let baseWidth: CGFloat = 1280
    private let baseHeight: CGFloat = 720
    private var aspectRatio: AspectRatio = .fixed16x9

    func setAspectRatio(_ ratio: AspectRatio) {
        self.aspectRatio = ratio
    }

    private func scaleToTargetResolution(_ location: CGPoint) -> CGPoint? {
        let viewWidth = self.frame.width
        let viewHeight = self.frame.height
        
        var scaleX: CGFloat
        var scaleY: CGFloat
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0
        
        var targetAspect: CGFloat
        
        switch aspectRatio {
        case .fixed4x3:
            targetAspect = 4.0 / 3.0
        case .fixed16x9:
            targetAspect = 16.0 / 9.0
        case .fixed16x10:
            targetAspect = 16.0 / 10.0
        case .fixed21x9:
            targetAspect = 21.0 / 9.0
        case .fixed32x9:
            targetAspect = 32.0 / 9.0
        case .stretched:
            scaleX = baseWidth / viewWidth
            scaleY = baseHeight / viewHeight
            
            let adjustedX = location.x
            let adjustedY = location.y
            
            let scaledX = max(0, min(adjustedX * scaleX, baseWidth))
            let scaledY = max(0, min(adjustedY * scaleY, baseHeight))
            
            return CGPoint(x: scaledX, y: scaledY)
        }
        
        let viewAspect = viewWidth / viewHeight
        
        if viewAspect > targetAspect {
            let scaledWidth = viewHeight * targetAspect
            offsetX = (viewWidth - scaledWidth) / 2
            scaleX = baseWidth / scaledWidth
            scaleY = baseHeight / viewHeight
        } else {
            let scaledHeight = viewWidth / targetAspect
            offsetY = (viewHeight - scaledHeight) / 2
            scaleX = baseWidth / viewWidth
            scaleY = baseHeight / scaledHeight
        }
        
        if location.x < offsetX || location.x > (viewWidth - offsetX) ||
           location.y < offsetY || location.y > (viewHeight - offsetY) {
            return nil
        }
        
        let adjustedX = location.x - offsetX
        let adjustedY = location.y - offsetY
        
        let scaledX = max(0, min(adjustedX * scaleX, baseWidth))
        let scaledY = max(0, min(adjustedY * scaleY, baseHeight))

        return CGPoint(x: scaledX, y: scaledY)
    }

    private func getNextAvailableIndex() -> Int {
        for i in 0..<Int.max {
            if !touchIndexMap.values.contains(i) {
                return i
            }
        }
        return 0
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        let disabled = UserDefaults.standard.bool(forKey: "disableTouch")
        guard !disabled else { return }
        
        setAspectRatio(Ryujinx.shared.config?.aspectRatio ?? .fixed16x9)

        for touch in touches {
            let location = touch.location(in: self)
            guard let scaledLocation = scaleToTargetResolution(location) else {
                ignoredTouches.insert(touch)
                continue
            }

            let index = getNextAvailableIndex()
            touchIndexMap[touch] = index
            activeTouches.append(touch)
            
            touch_began(Float(scaledLocation.x), Float(scaledLocation.y), Int32(index))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)

        let disabled = UserDefaults.standard.bool(forKey: "disableTouch")
        guard !disabled else {
            for touch in touches {
                ignoredTouches.remove(touch)
                if let index = activeTouches.firstIndex(of: touch) {
                    activeTouches.remove(at: index)
                }
                touchIndexMap.removeValue(forKey: touch)
            }
            return
        }

        for touch in touches {
            if ignoredTouches.remove(touch) != nil {
                continue
            }

            if let touchIndex = touchIndexMap[touch] {
                touch_ended(Int32(touchIndex))
                
                if let arrayIndex = activeTouches.firstIndex(of: touch) {
                    activeTouches.remove(at: arrayIndex)
                }
                touchIndexMap.removeValue(forKey: touch)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)

        let disabled = UserDefaults.standard.bool(forKey: "disableTouch")
        guard !disabled else { return }
        
        setAspectRatio(Ryujinx.shared.config?.aspectRatio ?? .fixed16x9)

        for touch in touches {
            if ignoredTouches.contains(touch) {
                continue
            }

            guard let touchIndex = touchIndexMap[touch] else {
                continue
            }

            let location = touch.location(in: self)
            guard let scaledLocation = scaleToTargetResolution(location) else {
                touch_ended(Int32(touchIndex))
                
                if let arrayIndex = activeTouches.firstIndex(of: touch) {
                    activeTouches.remove(at: arrayIndex)
                }
                touchIndexMap.removeValue(forKey: touch)
                ignoredTouches.insert(touch)
                continue
            }

            touch_moved(Float(scaledLocation.x), Float(scaledLocation.y), Int32(touchIndex))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        touchesEnded(touches, with: event)
    }
    

    func resetTouchTracking() {
        activeTouches.removeAll()
        ignoredTouches.removeAll()
        touchIndexMap.removeAll()
    }
}

