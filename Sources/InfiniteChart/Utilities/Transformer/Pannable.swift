//
//  Pannable.swift
//  
//
//  Created by Joshua Jiang on 8/21/24.
//

import UIKit

protocol Pannable: Transformable, UIView {
    func panGestureHandler(_ gesture: UIPanGestureRecognizer)
    var lastDragPoint: CGPoint? { get set }
}

extension Pannable {
    func panGestureHandler(_ gesture: UIPanGestureRecognizer) {
        guard let transformerProvider = transformerProvider else { return }
        
        switch gesture.state {
        case .began:
            lastDragPoint = gesture.location(in: self)
            
        case .changed:
            guard let lastDragPoint = lastDragPoint else { return }
            
            let currentPoint = gesture.location(in: self)
            let deltaX = transformableAxis != .vertical ? currentPoint.x - lastDragPoint.x : 0
            let deltaY = transformableAxis != .horizontal ? currentPoint.y - lastDragPoint.y : 0
            
            transformerProvider.translate(delta: CGPoint(x: deltaX, y: deltaY))
            
            self.lastDragPoint = currentPoint
            
        case .ended, .cancelled:
            lastDragPoint = nil
            
        default:
            break
        }
    }
}
