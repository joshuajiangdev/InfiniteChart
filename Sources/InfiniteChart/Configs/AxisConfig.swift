#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

public struct AxisConfig {
    public let labelCount: Int
    public let centerAxisLabelsEnabled: Bool
    public let labelFont: ChartFont
    public let labelColor: ChartColor
    public let axisColor: ChartColor
    public let requiredSpace: CGFloat // Width for Y-axis, Height for X-axis
    /// Formats axis values for display. The default uses two decimal places.
    public let labelFormatter: ((Double) -> String)?
    
    public init(
        labelCount: Int = 12,
        centerAxisLabelsEnabled: Bool = true,
        labelFont: ChartFont = .systemFont(ofSize: 10),
        labelColor: ChartColor = .black,
        axisColor: ChartColor = .black,
        requiredSpace: CGFloat = 50,
        labelFormatter: ((Double) -> String)? = nil
    ) {
        self.labelCount = labelCount
        self.centerAxisLabelsEnabled = centerAxisLabelsEnabled
        self.labelFont = labelFont
        self.labelColor = labelColor
        self.axisColor = axisColor
        self.requiredSpace = requiredSpace
        self.labelFormatter = labelFormatter
    }
}
