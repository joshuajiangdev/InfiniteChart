//
//  TransformerTests.swift
//  InfiniteChart
//
//  Created by Joshua Jiang on 8/17/24.
//

import XCTest
@testable import InfiniteChart

class TransformerTests: XCTestCase {
    var transformer: Transformer!
    var viewPortHandler: ViewPortHandler!

    override func setUp() {
        super.setUp()
        viewPortHandler = ViewPortHandler()
        viewPortHandler.setChartDimens(width: 100, height: 100)
        transformer = Transformer(viewPortHandler: viewPortHandler)
        transformer.prepareMatrixValuePx(
            chartXMin: 0,
            deltaX: 1000,
            chartYMin: 0,
            deltaY: 1000
        )
        transformer.prepareMatrixOffset(inverted: false)
    }
    
    func testBasic() {
        var pixel = CGPoint(x: 50, y: 50)
        var value = transformer.transformMatrixSet.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 500.0)
        XCTAssertEqual(value.y, 500.0)
        
        pixel = CGPoint(x: 0, y: 0)
        value = transformer.transformMatrixSet.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 0)
        XCTAssertEqual(value.y, 1000.0)
        
        pixel = CGPoint(x: 100, y: 100)
        value = transformer.transformMatrixSet.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 1000.0)
        XCTAssertEqual(value.y, 0.0)
    }

    func testZoom() {
        viewPortHandler.zoom(scaleX: 2, scaleY: 2)
        
        // Test pixel to value
        var pixel = CGPoint(x: 50, y: 50)
        var value = transformer.transformMatrixSet.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 250)
        XCTAssertEqual(value.y, 250)
        
        pixel = CGPoint(x: 0, y: 0)
        value = transformer.transformMatrixSet.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 0)
        XCTAssertEqual(value.y, 500)
        
        pixel = CGPoint(x: 100, y: 100)
        value = transformer.transformMatrixSet.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 500)
        XCTAssertEqual(value.y, 0)
    }
    
    func testTranslate() {
        viewPortHandler.translate(pt: CGPoint(x: 50, y: -50))
        
        // Test pixel to value
        var pixel = CGPoint(x: 50, y: 50)
        var value = transformer.transformMatrixSet.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 1000)
        XCTAssertEqual(value.y, 1000)
        
        pixel = CGPoint(x: 0, y: 0)
        value = transformer.transformMatrixSet.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 500)
        XCTAssertEqual(value.y, 1500)
        
        pixel = CGPoint(x: 100, y: 100)
        value = transformer.transformMatrixSet.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 1500)
        XCTAssertEqual(value.y, 500)
    }
    
    func testTranslateAndZoom() {
        viewPortHandler.translate(pt: CGPoint(x: 50, y: -50))
        viewPortHandler.zoom(scaleX: 2, scaleY: 2, x: 50, y: 50)
        
        // Test pixel to value
        var pixel = CGPoint(x: 50, y: 50)
        var value = transformer.transformMatrixSet.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 1000)
        XCTAssertEqual(value.y, 500)
        
        pixel = CGPoint(x: 0, y: 0)
        value = transformer.transformMatrixSet.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 750)
        XCTAssertEqual(value.y, 750)
        
        pixel = CGPoint(x: 100, y: 100)
        value = transformer.transformMatrixSet.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 1250)
        XCTAssertEqual(value.y, 250)
    }
}
