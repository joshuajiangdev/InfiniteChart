# BTC examples

Native iOS and macOS examples inspired by [InfiniteChartExample](https://github.com/joshuajiangdev/InfiniteChartExample). Both display BTC/USD one-minute candlesticks, trading volume, and optional SMA 10 and EMA 10 overlays. Chart time labels use UTC.

`Examples/Package.swift` is a standalone Swift package with a local dependency on `..`. The root `Package.swift` remains the library's build definition; the examples introduce no Xcode project or workspace.

## Run on macOS

Requires macOS 12 or later and Swift 5.10 or later. From the repository root:

```sh
swift run --package-path Examples BTCMacExample
```

To render the macOS example to a PNG and exit:

```sh
swift run --package-path Examples BTCMacExample --snapshot /tmp/btc-example.png
```

## Run on iOS Simulator

Requires Xcode, its command-line tools, and an installed iOS 15 or later Simulator runtime. From the repository root:

```sh
./Examples/run-ios.sh
```

The launcher builds the Swift package, assembles an app bundle, and installs and launches it in Simulator. It prefers a booted iPhone, otherwise an iPhone on the newest available iOS runtime. To choose a simulator, pass its UDID:

```sh
xcrun simctl list devices available
./Examples/run-ios.sh SIMULATOR_UDID
```

To build without launching:

```sh
./Examples/run-ios.sh --build-only
```

The app bundle is written to `Examples/.build/ios/BTCiOSExample.app`. This launcher supports Simulator only; physical-device signing is not configured. If Xcode's Simulator GUI is unavailable, the app still runs in the selected simulator and the launcher reports the missing GUI.

## Data and interaction

The initial chart uses a bundled historical snapshot from Coinbase's public BTC/USD candles endpoint, so it works offline. It contains 240 candles from August 25, 2024; see the [snapshot source and format](Shared/Resources/README.md). Select **Refresh** to request recent one-minute candles from Coinbase without an API key or account. The status identifies bundled versus fetched data and shows the displayed time range; a failed refresh keeps the existing chart and displays an error. Refresh is manual, with no streaming or background polling.

Toggle **SMA 10** and **EMA 10** to show or hide the moving averages. Drag to pan, pinch to zoom, and drag an axis to adjust its range.

## Files and tests

- `Shared/`: the shared screen, chart data provider, and bundled BTC candles.
- `iOS/`: the UIKit application entry point and app metadata.
- `macOS/`: the AppKit application entry point.
- `Tests/BTCExampleSupportTests/`: example data and provider tests.
- `run-ios.sh`: the Simulator build and launch script.

Run the example tests from the repository root:

```sh
swift test --package-path Examples
```

The library's tests remain in the root package and run separately with `swift test`.
