# InfiniteChart

A native macOS and iOS charting library distributed with Swift Package Manager. `Package.swift`
defines the library and its tests; no `.xcodeproj` or checked-in workspace is
required.

## Requirements

- Swift 5.10 or later and an Xcode installation with the Apple platform SDKs.
- macOS 10.15 or later, or iOS 13 or later.

The library uses AppKit on macOS and UIKit on iOS, with shared
Core Graphics rendering, Combine publishers, and Accelerate transforms. watchOS
and tvOS are not supported.

## Add the library to a package

For a local checkout, add InfiniteChart to the consuming package's dependencies:

```swift
dependencies: [
    .package(path: "../InfiniteChart"),
],
```

Then add its library product to the consuming target's dependencies:

```swift
.product(name: "InfiniteChart", package: "InfiniteChart"),
```

Import the module with `import InfiniteChart`. The chart view is
`InfiniteChartBase`; provide chart data through `ChartDataProviderBase` and its
specialized protocols, and configure the axes with `AxisConfig`.

`InfiniteChartBase` is an `NSView` on macOS and a `UIView` on iOS.
Add it to your native view hierarchy and set its frame or layout constraints.
`ChartColor` and `ChartFont` resolve to `NSColor` and `NSFont` on macOS, or `UIColor`
and `UIFont` on iOS. Existing iOS providers can continue using UIKit types.

Drag to pan and pinch to zoom on either platform. macOS also supports mouse wheel
and trackpad scrolling to pan. Gestures on an axis affect only that axis.
Use `AxisConfig.labelFormatter` to display timestamps, prices, or other custom labels.

Applications can observe `chart.onViewportChange` to choose a data resolution:

```swift
chart.onViewportChange = { [weak provider] change in
    // Application code chooses, loads, or aggregates data for this viewport.
    provider?.updateViewport(change.viewport)
}
```

The callback reports the visible X/Y ranges, plot size, and change reason. The
application owns detail selection and updates its data provider; replacing the
displayed data and publishing a redraw preserves the viewport. `updateViewport`
above is an application method, demonstrated by the BTC example provider.
Use `chart.setVisibleXRange(...)` for programmatic time-range changes,
`chart.setVisibleYRange(...)` to fit prices without changing the horizontal range,
`chart.resetViewport()` to restore the initial ranges, and `chart.xSpanLimits`
to configure zoom limits in your data's X units.

For variable intervals or irregular samples, also adopt `IndexedChartDataProvider`.
Return the actual sorted, unique X values in the requested inclusive range from
`getXValues(in:)`, and provide `nominalXStep` in the same X units for bar sizing.
The renderer then uses those samples instead of the legacy one-minute step.
Viewport notifications arrive on the main queue, coalesce rapid changes, and are
not emitted for data-only redraws. Applications loading data asynchronously should
discard superseded responses and preserve the latest viewport when applying data.

## Examples

The standalone [Examples package](Examples/README.md) includes native macOS and
iOS BTC/USD charts with volume, SMA/EMA toggles, bundled historical candles, and
public market-data refresh. Both demonstrate application-owned transitions
between remotely fetched 1m, 5m, and 15m candles when zooming. Coarser resolutions
load longer history, and panning beyond cached data requests another window.
Zoom buttons, loading/retry states, and a live interval label make the transitions
visible. It depends on this library through `.package(name: "InfiniteChart", path: "..")`.

```sh
swift run --package-path Examples BTCMacExample
./Examples/run-ios.sh
```

## Build and test

Run these commands from the repository root. Build and test native macOS with
Swift Package Manager:

```sh
swift build
swift test
```

For iOS, Xcode's command-line tools read the Swift package
directly and provide its `InfiniteChart` scheme.

Inspect the package:

```sh
swift package describe
```

Build for iOS Simulator:

```sh
xcodebuild -scheme InfiniteChart \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath .build/ios \
    build CODE_SIGNING_ALLOWED=NO
```

Run the XCTest suite on an installed iOS Simulator. Find its UUID with
`xcrun simctl list devices available`, then substitute it for `SIMULATOR_UUID`:

```sh
xcodebuild -scheme InfiniteChart \
    -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
    -derivedDataPath .build/ios \
    test CODE_SIGNING_ALLOWED=NO
```

The tests cover coordinate transforms, native view layout and resizing, pan and
pinch gestures, axis labels, and chart rendering on both macOS and iOS. GitHub
Actions runs both test suites on pushes and pull requests.
You can also open `Package.swift` directly in Xcode. Generated `.swiftpm`, build,
and IDE files are ignored by Git.
