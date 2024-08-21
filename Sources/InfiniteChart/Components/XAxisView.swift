//
//  XAxis.swift
//  
//
//  Created by Joshua Jiang on 8/18/24.
//

import UIKit
import Combine

class XAxisView<TransformerType: Transformer>: UIView {
    
    // TODO: Move a data model
    private let labelCount = 12
    private let centerAxisLabelsEnabled = true
    private var entries: [Double] = []
    private var centeredEntries: [Double] = []
    
    private var labels: [UILabel] = []
    
    var transformerStream: AnyPublisher<TransformerType, Never>?
    var transformerProvider: AccelerateTransformerProvider?
    var disposeBag = Set<AnyCancellable>()
    private var currentTransformer: TransformerType?
    
    private var panGestureRecognizer: UIPanGestureRecognizer!
    private var pinchGestureRecognizer: UIPinchGestureRecognizer!
    
    private var lastDragPoint: CGPoint?
    private var isScaling = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .yellow
        setupGestureRecognizers()
        clipsToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    private func setupGestureRecognizers() {
        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGestureRecognizer.maximumNumberOfTouches = 1
        addGestureRecognizer(panGestureRecognizer)
        
        pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        addGestureRecognizer(pinchGestureRecognizer)
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard let transformerProvider = transformerProvider else { return }
        
        switch gesture.state {
        case .began:
            lastDragPoint = gesture.location(in: self)
            
        case .changed:
            guard let lastDragPoint = lastDragPoint else { return }
            
            let currentPoint = gesture.location(in: self)
            let deltaX = currentPoint.x - lastDragPoint.x
            
            // Update the viewport using pixel values
            transformerProvider.translate(delta: CGPoint(x: deltaX, y: 0))
            
            // Update last drag point
            self.lastDragPoint = currentPoint
            
        case .ended, .cancelled:
            lastDragPoint = nil
            
        default:
            break
        }
    }
    
    @objc private func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
        guard let transformerProvider = transformerProvider else { return }
        
        switch gesture.state {
        case .began:
            isScaling = true
            
        case .changed:
            if isScaling {
                let scaleX = gesture.scale
                transformerProvider.zoom(scaleX: scaleX, scaleY: 1.0, x: bounds.width/2, y: 0)
                gesture.scale = 1.0
            }
            
        case .ended, .cancelled:
            isScaling = false
            setNeedsDisplay()
            
        default:
            break
        }
    }
    
    func setup() {
        setupLabels()
        transformerStream?
            .sink(receiveValue: { [weak self] transformer in
                self?.currentTransformer = transformer
                self?.setupAxis(transformer: transformer)
            })
            .store(in: &disposeBag)
    }
    
    private func setupLabels() {
        for _ in 0..<labelCount {
            let label = UILabel()
            label.textAlignment = .center
            label.font = UIFont.systemFont(ofSize: 10)
            label.transform = CGAffineTransform(rotationAngle: CGFloat.pi / 2)
            addSubview(label)
            labels.append(label)
        }
    }
    
    func setupAxis(transformer: any Transformer) {
        let min = transformer.valueForTouchPoint(CGPoint(x: 0, y: 0)).x
        let max = transformer.valueForTouchPoint(CGPoint(x: bounds.width, y: 0)).x
        computeAxisValues(min: min, max: max)
        updateLabels()
        setNeedsLayout()
    }
    
    func computeAxisValues(min: Double, max: Double) {
        let range = abs(max - min)
        
        let rawInterval = range / Double(labelCount)
        var interval = rawInterval.roundedToNextSignificant()
        // TODO: Use granularity
        interval = Swift.max(interval, 0.1)
        
        let intervalMagnitude = pow(10.0, Double(Int(log10(interval)))).roundedToNextSignificant()
        let intervalSigDigit = Int(interval / intervalMagnitude)
        if intervalSigDigit > 5
        {
            // Use one order of magnitude higher, to avoid intervals like 0.9 or 90
            interval = floor(10.0 * Double(intervalMagnitude))
        }
        
        var n = centerAxisLabelsEnabled ? 1 : 0
        
        var first = interval == 0.0 ? 0.0 : ceil(min / interval) * interval

        if centerAxisLabelsEnabled
        {
            first -= interval
        }

        let last = interval == 0.0 ? 0.0 : (floor(max / interval) * interval).nextUp

        if interval != 0.0, last != first
        {
            stride(from: first, through: last, by: interval).forEach { _ in n += 1 }
        }

        // Ensure stops contains at least n elements.
        entries.removeAll(keepingCapacity: true)
        entries.reserveCapacity(labelCount)

        let start = first, end = first + Double(n) * interval

        // Fix for IEEE negative zero case (Where value == -0.0, and 0.0 == -0.0)
        let values = stride(from: start, to: end, by: interval).map { $0 == 0.0 ? 0.0 : $0 }
        entries.append(contentsOf: values)
        
        var decimals = 0
        // set decimals
        if interval < 1
        {
            decimals = Int(ceil(-log10(interval)))
        }
        else
        {
            decimals = 0
        }

        if centerAxisLabelsEnabled
        {
            let offset: Double = interval / 2.0
            centeredEntries = entries[..<n]
                .map { $0 + offset }
        }
    }
    
    private func updateLabels() {
        let valuesToUse = centerAxisLabelsEnabled ? centeredEntries : entries
        
        // Remove excess labels
        while labels.count > valuesToUse.count {
            let label = labels.removeLast()
            label.removeFromSuperview()
        }
        
        // Add more labels if needed
        while labels.count < valuesToUse.count {
            let label = UILabel()
            label.textAlignment = .center
            label.font = UIFont.systemFont(ofSize: 10)
            label.transform = CGAffineTransform(rotationAngle: CGFloat.pi / 2)
            addSubview(label)
            labels.append(label)
        }
        
        // Update label texts
        for (index, label) in labels.enumerated() {
            label.text = String(format: "%.2f", valuesToUse[index])
            label.sizeToFit()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        guard let transformer = currentTransformer else { return }
        
        let labelHeight: CGFloat = 50
        
        for (index, label) in labels.enumerated() {
            let value = centerAxisLabelsEnabled ? centeredEntries[index] : entries[index]
            let xPosition = transformer.pixelForValue(DoublePrecisionPoint(x: value, y: 0)).x
            
            label.frame = CGRect(x: xPosition - label.intrinsicContentSize.height / 2,
                                 y: 0,
                                 width: label.intrinsicContentSize.height,
                                 height: labelHeight)
        }
    }
}
