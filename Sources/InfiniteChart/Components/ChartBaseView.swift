//
//  ChartBaseView.swift
//  
//
//  Created by Joshua Jiang on 8/21/24.
//

import UIKit
import Combine

class ChartBaseView: UIView, Transformable, Pannable, Pinchable {
    
    // MARK: - Transformable
    var transformerStream: AnyPublisher<AccelerateTransformer, Never>?
    
    typealias TransformerType = AccelerateTransformer
    
    var transformerProvider: (any TransformerProviding)?
    
    var transformableAxes: [TransformableAxis] = [.horizontal, .vertical]
    
    // MARK: - Pannable
    
    var lastDragPoint: CGPoint?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .green
        setupGestureRecognizers()
        clipsToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupGestureRecognizers() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(panGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        addGestureRecognizer(pinchGesture)
    }
    
//    func setup() {
//        transformerStream?
//            .sink(receiveValue: { [weak self] transformer in
//                self?.currentTransformer = transformer
//                self?.setupAxis(transformer: transformer)
//            })
//            .store(in: &disposeBag)
//    }
//    
    @objc func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        self.panGestureHandler(gesture)
    }

    @objc func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
        self.pinchGestureHandler(gesture)
    }
}
