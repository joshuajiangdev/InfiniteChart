//
//  DataProvider.swift
//
//
//  Created by Joshua Jiang on 8/24/24.
//

public struct DataRanges {
    public let chartXMin: Double
    public let deltaX: Double
    public let chartYMin: Double
    public let deltaY: Double
    
    public init(chartXMin: Double, deltaX: Double, chartYMin: Double, deltaY: Double) {
        self.chartXMin = chartXMin
        self.deltaX = deltaX
        self.chartYMin = chartYMin
        self.deltaY = deltaY
    }
}

public protocol ChartDataProviderDelegate: AnyObject {
    func transformerDidUpdate(transformer: any Transformer)
}

public protocol ChartDataProvider {
    
    var tranformerUpdatedDelegate: ChartDataProviderDelegate? { get }
    
    /**
     Get the y value for the target x value
     
     - Parameter for: The target value we want to get y value of
     
     - Returns: The corresponding y value or nil if no value
     */
    func getYValue(for xValue: Double) -> Double?
    
    /**
     Get initial data range
     
     - Parameter for: The target value we want to get y value of
     
     - Returns: DataRanges
     */
    func getInitDataRanges() -> DataRanges?
    
    /**
     Get nearest x value
     
     - Parameter 
        to: The target value we want to find the nearest x value to
        seekBelow: boolean to indicate search to bottom or above
        offset: how many extra data point to skip

     - Returns: The nearest x value to what we passed in
     */
    func getClosestXValue(to xValue: Double, seekBelow: Bool, offset: Int) -> Double?
}
