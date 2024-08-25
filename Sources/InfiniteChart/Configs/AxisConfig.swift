import UIKit

public struct AxisConfig {
    public let labelCount: Int
    public let centerAxisLabelsEnabled: Bool
    public let labelFont: UIFont
    public let labelColor: UIColor
    public let axisColor: UIColor
    public let requiredSpace: CGFloat // Width for Y-axis, Height for X-axis
    
    public init(
        labelCount: Int = 12,
        centerAxisLabelsEnabled: Bool = true,
        labelFont: UIFont = .systemFont(ofSize: 10),
        labelColor: UIColor = .black,
        axisColor: UIColor = .black,
        requiredSpace: CGFloat = 50
    ) {
        self.labelCount = labelCount
        self.centerAxisLabelsEnabled = centerAxisLabelsEnabled
        self.labelFont = labelFont
        self.labelColor = labelColor
        self.axisColor = axisColor
        self.requiredSpace = requiredSpace
    }
}
