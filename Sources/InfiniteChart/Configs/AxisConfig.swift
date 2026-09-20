#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

public struct AxisConfig {
    /// The approximate number of labels. Nonpositive values hide labels.
    public let labelCount: Int
    public let centerAxisLabelsEnabled: Bool
    public let labelFont: ChartFont
    public let labelColor: ChartColor
    public let axisColor: ChartColor
    /// Width for Y-axis, height for X-axis. Invalid or negative space becomes zero.
    public let requiredSpace: CGFloat
    /// Formats axis values for display. The default uses two decimal places.
    public let labelFormatter: ((Double) -> String)?
    
    /// Creates the appearance, spacing, and formatting configuration for an axis.
    /// - Parameters:
    ///   - labelCount: Approximate label count; nonpositive values hide labels.
    ///   - centerAxisLabelsEnabled: Whether to offset tick values by half an interval.
    ///   - labelFont: Font used to display axis values.
    ///   - labelColor: Color of axis label text.
    ///   - axisColor: Color of the border along the plot edge.
    ///   - requiredSpace: Y-axis width or X-axis height in points; negative or nonfinite values become zero.
    ///   - labelFormatter: Optional value formatter; `nil` uses two decimal places.
    public init(
        labelCount: Int = 12,
        centerAxisLabelsEnabled: Bool = true,
        labelFont: ChartFont = .systemFont(ofSize: 10),
        labelColor: ChartColor = .black,
        axisColor: ChartColor = .black,
        requiredSpace: CGFloat = 50,
        labelFormatter: ((Double) -> String)? = nil
    ) {
        self.labelCount = max(0, labelCount)
        self.centerAxisLabelsEnabled = centerAxisLabelsEnabled
        self.labelFont = labelFont
        self.labelColor = labelColor
        self.axisColor = axisColor
        self.requiredSpace = requiredSpace.isFinite ? max(0, requiredSpace) : 0
        self.labelFormatter = labelFormatter
    }
}
