//
//  DataProvider.swift
//
//
//  Created by Joshua Jiang on 8/24/24.
//

import UIKit

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

public protocol ChartDataProviderBase {
    
    var tranformerUpdatedDelegate: ChartDataProviderDelegate? { get }
    
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

public protocol LineChartDataProvider: ChartDataProviderBase {
    
    /**
     Get the y value for the target x value
     
     - Parameter for: The target value we want to get y value of
     
     - Returns: The corresponding y value or nil if no value
     */
    func getYValue(for xValue: Double) -> Double?
}

public struct CandleStickDataPoint {
    public let high: Double
    public let low: Double
    public let open: Double
    public let close: Double
    public let color: UIColor
    
    public init(high: Double, low: Double, open: Double, close: Double, color: UIColor) {
        self.high = high
        self.low = low
        self.open = open
        self.close = close
        self.color = color
    }
}

public protocol CandleStickDataProvider: ChartDataProviderBase {
    
    /**
     Get the y value for the target x value
     
     - Parameter for: The target value we want to get y value of
     
     - Returns: The corresponding y value or nil if no value
     */
    func getCandleStickDataPoint(for xValue: Double) -> CandleStickDataPoint?
}

public protocol VolumeDataProvider: ChartDataProviderBase {
    func getVolumeValueAndColor(for xValue: Double) -> (volume: Double, color: UIColor)?
}
