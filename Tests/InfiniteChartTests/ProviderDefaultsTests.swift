import Combine
import XCTest
import InfiniteChart

final class ProviderDefaultsTests: XCTestCase {
    func testConsumerCanOmitUnusedDelegateAndOverlays() {
        let provider = MinimalProvider()
        XCTAssertNil(provider.tranformerUpdatedDelegate)
        XCTAssertTrue(provider.technicalIndicators.isEmpty)
    }
}

private struct MinimalProvider: ChartDataProviderBase {
    let redrawStream = Empty<Void, Never>().eraseToAnyPublisher()
    func getInitDataRanges() -> DataRanges? { nil }
    func getClosestXValue(to xValue: Double, seekBelow: Bool, offset: Int) -> Double? { nil }
}
