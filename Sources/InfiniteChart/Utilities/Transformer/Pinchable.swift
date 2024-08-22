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
        
        switch gesture.state {
        case .changed:
            let scaleX = transformableAxis == .horizontal ? gesture.scale : 1.0
            let scaleY = transformableAxis == .vertical ? gesture.scale : 1.0
            let centerX = transformableAxis == .horizontal ? bounds.width / 2 : 0
            let centerY = transformableAxis == .vertical ? bounds.height / 2 : 0
            transformerProvider.zoom(scaleX: scaleX, scaleY: scaleY, x: centerX, y: centerY)
            gesture.scale = 1.0
        default:
            break
        }
    }
}
