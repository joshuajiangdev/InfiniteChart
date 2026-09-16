#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Draws centered text in the same coordinate system on UIKit and AppKit.
final class AxisLabel: ChartPlatformView {
    var text: String = "" {
        didSet {
            invalidateIntrinsicContentSize()
            requestChartDisplay()
        }
    }
    var font: ChartFont = .systemFont(ofSize: 10) {
        didSet {
            invalidateIntrinsicContentSize()
            requestChartDisplay()
        }
    }
    var textColor: ChartColor = .black {
        didSet { requestChartDisplay() }
    }
    var rotationAngle: CGFloat = 0 {
        didSet { requestChartDisplay() }
    }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: textColor]
    }

    override var intrinsicContentSize: CGSize {
        (text as NSString).size(withAttributes: attributes)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureChartAppearance(background: .clear)
        #if canImport(UIKit)
        isUserInteractionEnabled = false
        #endif
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = currentChartGraphicsContext() else { return }
        let size = intrinsicContentSize
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: rotationAngle)
        (text as NSString).draw(
            in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height),
            withAttributes: attributes
        )
    }
}
