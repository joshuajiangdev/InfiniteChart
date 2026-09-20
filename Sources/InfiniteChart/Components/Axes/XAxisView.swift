//
//  XAxis.swift
//  
//
//  Created by Joshua Jiang on 8/18/24.
//

import Foundation
import Combine

final class XAxisView: ChartPlatformView, Transformable, Pannable, Pinchable {
    // MARK: - Transformable
    
    typealias TransformerType = AffineTransformer
    var transformerProvider: (any TransformerProviding)?
    var transformableAxes: [TransformableAxis] = [.horizontal]
    var transformerStream: AnyPublisher<AffineTransformer, Never>?
    
    var config = AxisConfig()
    
    private var entries: [Double] = []
    
    private var labels: [AxisLabel] = []
    
    var disposeBag = Set<AnyCancellable>()
    private var currentTransformer: TransformerType?
    
    // MARK: - Pannable
    
    private var oldBounds: CGRect = .zero
    
    var lastDragPoint: CGPoint?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureChartAppearance(background: .white)
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
    
    func setup() {
        disposeBag.removeAll()
        transformerStream?
            .sink(receiveValue: { [weak self] transformer in
                self?.currentTransformer = transformer
                self?.setupAxis(transformer: transformer)
            })
            .store(in: &disposeBag)
        requestChartDisplay()
    }
    
    func setupAxis(transformer: any Transformer) {
        let min = transformer.valueForTouchPoint(CGPoint(x: 0, y: 0)).x
        let max = transformer.valueForTouchPoint(CGPoint(x: bounds.width, y: 0)).x
        computeAxisValues(min: min, max: max)
        updateLabels()
        requestChartLayout()
    }
    
    func computeAxisValues(min: Double, max: Double) {
        entries = AxisTicks.values(min: min, max: max, config: config)
    }
    
    private func updateLabels() {
        let valuesToUse = entries
        
        // Remove excess labels
        while labels.count > valuesToUse.count {
            let label = labels.removeLast()
            label.removeFromSuperview()
        }
        
        // Add more labels if needed
        while labels.count < valuesToUse.count {
            let label = AxisLabel(frame: .zero)
            label.font = config.labelFont
            label.textColor = config.labelColor
            label.rotationAngle = .pi / 2
            addSubview(label)
            labels.append(label)
        }
        
        // Update label texts
        for (index, label) in labels.enumerated() {
            label.font = config.labelFont
            label.textColor = config.labelColor
            label.text = config.labelFormatter?(valuesToUse[index]) ?? String(format: "%.2f", valuesToUse[index])
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = currentChartGraphicsContext() else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(config.axisColor.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: 0, y: 0.5))
        context.addLine(to: CGPoint(x: bounds.width, y: 0.5))
        context.strokePath()
    }
    
    override func layoutChartSubviews() {
        super.layoutChartSubviews()
        
        guard let transformer = currentTransformer else { return }
        
        // Detect if bounds have changed
        if self.bounds.size != oldBounds.size {
            // The bounds have changed, handle the change here
            oldBounds = self.bounds
            setupAxis(transformer: transformer)
        }
        
        for (index, label) in labels.enumerated() {
            let value = entries[index]
            let xPosition = transformer.pixelForValue(DoublePrecisionPoint(x: value, y: 0)).x
            
            label.frame = CGRect(
                x: xPosition - label.intrinsicContentSize.height / 2,
                y: 0,
                width: label.intrinsicContentSize.height,
                height: bounds.height
            )
        }
    }
    
    @objc func handlePanGesture(_ gesture: ChartPanGestureRecognizer) {
        self.panGestureHandler(gesture)
    }

    @objc func handlePinchGesture(_ gesture: ChartPinchGestureRecognizer) {
        self.pinchGestureHandler(gesture)
    }
}
