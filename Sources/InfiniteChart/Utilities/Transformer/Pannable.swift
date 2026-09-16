//
//  Pannable.swift
//  
//
//  Created by Joshua Jiang on 8/21/24.
//

import Foundation

@MainActor
protocol Pannable: Transformable, ChartPlatformView {
    func panGestureHandler(_ gesture: ChartPanGestureRecognizer)
    var lastDragPoint: CGPoint? { get set }
}

@MainActor
extension Pannable {
    func pan(by delta: CGPoint) {
        transformerProvider?.translate(delta: CGPoint(
            x: transformableAxes.contains(.horizontal) ? delta.x : 0,
            y: transformableAxes.contains(.vertical) ? delta.y : 0
        ))
    }

    func panGestureHandler(_ gesture: ChartPanGestureRecognizer) {
        
        switch gesture.state {
        case .began:
            lastDragPoint = gesture.location(in: self)
            
        case .changed:
            guard let lastDragPoint = lastDragPoint else { return }
            
            let currentPoint = gesture.location(in: self)
            
            pan(by: CGPoint(x: currentPoint.x - lastDragPoint.x, y: currentPoint.y - lastDragPoint.y))
            
            self.lastDragPoint = currentPoint
            
        case .ended, .cancelled, .failed:
            lastDragPoint = nil
            
        default:
            break
        }
    }
}
