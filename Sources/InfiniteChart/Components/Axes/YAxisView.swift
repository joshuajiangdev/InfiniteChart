//
//  YAxisView.swift
//  
//
//  Created by Joshua Jiang on 8/21/24.
//

import Foundation
import Combine

final class YAxisView: ChartPlatformView, Transformable, Pannable, Pinchable {
    
    // MARK: - Transformable
    
    typealias TransformerType = AffineTransformer
    var transformerProvider: (any TransformerProviding)?
    var transformableAxes: [TransformableAxis] = [.vertical]
    var transformerStream: AnyPublisher<AffineTransformer, Never>?
    
    var config = AxisConfig()
    
    private var entries: [Double] = []
    
    private var labels: [AxisLabel] = []
    
    var disposeBag = Set<AnyCancellable>()
    private var currentTransformer: TransformerType?
    
    // MARK: - Pannable
    
    var lastDragPoint: CGPoint?
    
    private var oldBounds: CGRect = .zero
    
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
        let min = transformer.valueForTouchPoint(CGPoint(x: 0, y: bounds.height)).y
        let max = transformer.valueForTouchPoint(CGPoint(x: 0, y: 0)).y
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
        context.move(to: CGPoint(x: 0.5, y: 0))
        context.addLine(to: CGPoint(x: 0.5, y: bounds.height))
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
        let labelWidth = bounds.width
        
        for (index, label) in labels.enumerated() {
            let value = entries[index]
            let yPosition = transformer.pixelForValue(DoublePrecisionPoint(x: 0, y: value)).y
            
            label.frame = CGRect(
                x: 0,
                y: yPosition - label.intrinsicContentSize.height / 2,
                width: labelWidth,
                height: label.intrinsicContentSize.height
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
