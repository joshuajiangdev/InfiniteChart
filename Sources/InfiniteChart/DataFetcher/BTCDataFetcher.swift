//
//  BTCDataFetcher.swift
//  
//
//  Created by Joshua Jiang on 8/22/24.
//

import Foundation

struct BTCDataPoint {
    let timestamp: Double
    let price: Double
}

final class BTCDataFetcher {

    private let polygonApiKey = "zLOFgQfuQNMppR0oWjU7NPGXMdWF6JRE"
    
    var dataPoints: [Double: Double] = [:]
    
    // Setup polygon.io URLSession
    private lazy var urlSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["Authorization": "Bearer \(polygonApiKey)"]
        return URLSession(configuration: configuration)
    }()

    init() {
        let currentTime = Date()
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: currentTime)!
        let fiveThousandMinutesAgo = Calendar.current.date(byAdding: .minute, value: -5000, to: oneDayAgo)!

        Task {
            try? await fetch(from: fiveThousandMinutesAgo.timeIntervalSince1970, to: oneDayAgo.timeIntervalSince1970)
        }
    }
    
    func fetch(from: Double, to: Double) async throws {
        let url = URL(string: "https://api.polygon.io/v2/aggs/ticker/X:BTCUSD/range/1/minute/\(Int(from*1000))/\(Int(to*1000))?apiKey=zLOFgQfuQNMppR0oWjU7NPGXMdWF6JRE")!
        let request = URLRequest(url: url)
        let (data, _) = try await urlSession.data(for: request)
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(PolygonResponse.self, from: data)
        
        dataPoints = Dictionary(uniqueKeysWithValues: response.results.map { (Double($0.t), $0.c) })
    }
    
    func getData(for timestamp: Double) -> Double? {
        if let price = dataPoints[timestamp] {
            return price
        }
        return nil
    }
    
    func getDataRanges() -> (minX: Double, deltaX: Double, minY: Double, deltaY: Double)? {
        guard !dataPoints.isEmpty else { return nil }
        
        let sortedDataPoints = dataPoints.sorted { $0.key < $1.key }
        
        guard let firstPoint = sortedDataPoints.first, let lastPoint = sortedDataPoints.last else { return nil }
        
        let minX = max(lastPoint.key - (1000 * 60 * 1000), firstPoint.key)
        let deltaX = lastPoint.key - minX
        
        let recentDataPoints = sortedDataPoints.filter { $0.key >= minX }
        let prices = recentDataPoints.map { $0.value }
        
        guard let minY = prices.min(), let maxY = prices.max() else { return nil }
        let deltaY = maxY - minY
        
        return (minX: minX, deltaX: deltaX, minY: minY, deltaY: deltaY)
    }

//    get closest x value with option to seek below or above
    func getClosestXValue(to timestamp: Double, seekBelow: Bool) -> Double? {
        let sortedDataPoints = dataPoints.sorted { $0.key < $1.key }
        let closest = sortedDataPoints.min(by: { abs($0.key - timestamp) < abs($1.key - timestamp) })
        return closest?.key
    }
}

struct PolygonResponse: Codable {
    let results: [Result]
}

struct Result: Codable {
    let t: Int  // timestamp
    let c: Double  // closing price
}
