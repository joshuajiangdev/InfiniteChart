//
//  ChartBaseView.swift
//  
//
//  Created by Joshua Jiang on 8/21/24.
//

import Foundation
import Combine

class ChartBaseView: ChartPlatformView, Transformable, Pannable, Pinchable {
    
    // MARK: - Transformable
    var transformerStream: AnyPublisher<AccelerateTransformer, Never>?
    
    typealias TransformerType = AccelerateTransformer
    
    var transformerProvider: (any TransformerProviding)?
    
    var transformableAxes: [TransformableAxis] = [.horizontal, .vertical]
    
    // MARK: - Pannable
    
    var lastDragPoint: CGPoint?
    
    // MARK: - Private Properties
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureChartAppearance(background: .clear)
        setupGestureRecognizers()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupGestureRecognizers() {
        installChartGestures(
            panAction: #selector(handlePanGesture(_:)),
            pinchAction: #selector(handlePinchGesture(_:))
        )
    }
    
    @objc func handlePanGesture(_ gesture: ChartPanGestureRecognizer) {
        self.panGestureHandler(gesture)
    }

    @objc func handlePinchGesture(_ gesture: ChartPinchGestureRecognizer) {
        self.pinchGestureHandler(gesture)
    }
}
