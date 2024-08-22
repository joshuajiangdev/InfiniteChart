//
//  Pinchable.swift
//  
//
//  Created by Joshua Jiang on 8/21/24.
//

import UIKit

protocol Pinchable: Transformable, UIView {
    func pinchGestureHandler(_ gesture: UIPinchGestureRecognizer)
}

extension Pinchable {
    func pinchGestureHandler(_ gesture: UIPinchGestureRecognizer) {
        guard let transformerProvider = transformerProvider else { return }
        let location = gesture.location(in: self)
        
        switch gesture.state {
        case .changed:
            let scaleX = transformableAxes.contains(.horizontal) ? gesture.scale : 1.0
            let scaleY = transformableAxes.contains(.vertical) ? gesture.scale : 1.0
            
            let centerX = if transformableAxes.count == 1 {
                transformableAxes.contains(.horizontal) ? bounds.width / 2 : 0
            } else {
                location.x
            }
            
            let centerY = if transformableAxes.count == 1 {
                transformableAxes.contains(.vertical) ? bounds.height / 2 : 0
            } else {
                location.y
            }
            
            transformerProvider.zoom(scaleX: scaleX, scaleY: scaleY, x: centerX, y: centerY)
            gesture.scale = 1.0
        default:
            break
        }
    }
}
