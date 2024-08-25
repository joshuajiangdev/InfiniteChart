import UIKit

public struct AxisConfig {
    let labelCount: Int
    let centerAxisLabelsEnabled: Bool
    let labelFont: UIFont
    let labelColor: UIColor
    let axisColor: UIColor
    let requiredSpace: CGFloat // Width for Y-axis, Height for X-axis
    
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
