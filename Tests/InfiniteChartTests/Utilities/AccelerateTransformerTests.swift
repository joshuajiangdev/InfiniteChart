//
//  TransformerTests.swift
//  InfiniteChart
//
//  Created by Joshua Jiang on 8/17/24.
//

import XCTest
@testable import InfiniteChart

class AccelerateTransformerTests: XCTestCase {
    var accelerateTransformerProvider: AccelerateTransformerProvider!

    override func setUp() {
        super.setUp()
        
        accelerateTransformerProvider = AccelerateTransformerProvider(
            size: CGSize(
                width: 100,
                height: 100
            ),
            dataRanges: DataRanges(
                chartXMin: 0,
                deltaX: 1000,
                chartYMin: 0,
                deltaY: 1000
            )
        )
    }
    
    func testNonZeroSetup() {
        accelerateTransformerProvider = AccelerateTransformerProvider(
            size: CGSize(
                width: 300,
                height: 800
            ),
            dataRanges: DataRanges(
                chartXMin: 10000,
                deltaX: 1000,
                chartYMin: 600,
                deltaY: 10
            )
        )
        
        print(accelerateTransformerProvider.transformer.pixelToValueMatrix)
        var pixel = CGPoint(x: 0, y: 0)
        var value = DoublePrecisionPoint(x: 0, y: 0)
        
        pixel = CGPoint(x: 0, y: 0)
        value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 10000)
        XCTAssertEqual(value.y, 610.0)
        
        pixel = CGPoint(x: 300, y: 800)
        value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 11000.0)
        XCTAssertEqual(value.y, 600.0)
        
    }
    
    func testBasic() {
        var pixel = CGPoint(x: 50, y: 50)
        var value = DoublePrecisionPoint(x: 0, y: 0)
        
        value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 500.0)
        XCTAssertEqual(value.y, 500.0)
        
        pixel = CGPoint(x: 0, y: 0)
        value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 0)
        XCTAssertEqual(value.y, 1000.0)
        
        pixel = CGPoint(x: 100, y: 100)
        value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 1000.0)
        XCTAssertEqual(value.y, 0.0)
    }

    func testZoomAtZero() {
        accelerateTransformerProvider.zoom(scaleX: 2, scaleY: 2)
        
        // Test pixel to value
        var pixel = CGPoint(x: 50, y: 50)
        var value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 250)
        XCTAssertEqual(value.y, 750)
        
        pixel = CGPoint(x: 0, y: 0)
        value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 0)
        XCTAssertEqual(value.y, 1000)
        
        pixel = CGPoint(x: 100, y: 100)
        value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 500)
        XCTAssertEqual(value.y, 500)
    }
    
    func testZoomAtCenter() {
        accelerateTransformerProvider.zoom(scaleX: 2, scaleY: 2, x: 50, y: 50)
        
        // Test pixel to value
        var pixel = CGPoint(x: 50, y: 50)
        var value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 500)
        XCTAssertEqual(value.y, 500)
        
        pixel = CGPoint(x: 0, y: 0)
        value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 250)
        XCTAssertEqual(value.y, 750)
        
        pixel = CGPoint(x: 100, y: 100)
        value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 750)
        XCTAssertEqual(value.y, 250)
    }
    

    func testTranslate() {
        accelerateTransformerProvider.translate(delta: CGPoint(x: -50, y: -50))
        
        // Test pixel to value
        var pixel = CGPoint(x: 50, y: 50)
        var value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 1000)
        XCTAssertEqual(value.y, 0)
        
        pixel = CGPoint(x: 0, y: 0)
        value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 500)
        XCTAssertEqual(value.y, 500)
        
        pixel = CGPoint(x: 100, y: 100)
        value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 1500)
        XCTAssertEqual(value.y, -500)
    }
    
    func testTranslateAndZoom() {
        accelerateTransformerProvider.translate(delta: CGPoint(x: -50, y: -50))
        print(accelerateTransformerProvider.transformer.valueForTouchPoint(CGPoint(x: 50, y: 50)))
        accelerateTransformerProvider.zoom(scaleX: 2, scaleY: 2, x: 50, y: 50)
        
        // Test pixel to value
        var pixel = CGPoint(x: 50, y: 50)
        var value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 1000)
        XCTAssertEqual(value.y, 0)
        
        pixel = CGPoint(x: 0, y: 0)
        value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 750)
        XCTAssertEqual(value.y, 250)
        
        pixel = CGPoint(x: 100, y: 100)
        value = accelerateTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 1250)
        XCTAssertEqual(value.y, -250)
    }
}
