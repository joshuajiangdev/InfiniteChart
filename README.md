# InfiniteChart

A native macOS and iOS charting library distributed with Swift Package Manager. `Package.swift`
defines the library and its tests; no `.xcodeproj` or checked-in workspace is
required.

## Requirements

- Swift 5.10 or later and an Xcode installation with the Apple platform SDKs.
- macOS 10.15 or later, or iOS 13 or later.

The library uses AppKit on macOS and UIKit on iOS, with shared
Core Graphics rendering and affine transforms, with Combine publishers. watchOS
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

Use `chart.viewportStream.value` to read the current viewport, or subscribe to
`chart.viewportStream` for updates:

```swift
let currentViewport = chart.viewportStream.value
let viewportObservation = chart.viewportStream
    .compactMap { $0 }
    .sink { viewport in
        print(viewport.visibleXRange)
        print(viewport.visibleYRange)
        print(viewport.plotSize)
    }
```

The chart maintains a `CurrentValueSubject<ChartViewport?, Never>`. Its value is
nil before layout or while the plot is empty; use `compactMap` to observe only
valid viewports. The value stays current even when no application is subscribed.
Keep the returned `AnyCancellable` alive while observing the chart.

Read and subscribe on the main actor. Subscriptions receive the current value
immediately, then each distinct transform or layout update. If a subscriber
changes the chart, defer that work with `Task { @MainActor in ... }` until the
transform update completes. Data-only redraws do not publish viewport changes.

`ChartViewport` reports visible X/Y ranges in the provider's data units and plot
size in points, excluding the axes.

## Examples

The standalone [Examples package](Examples/README.md) includes native macOS and
iOS BTC/USD charts with volume, SMA/EMA toggles, bundled historical candles, and
public market-data refresh. It depends on this library through `.package(path: "..")`.

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
