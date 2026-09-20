# BTC examples

Native iOS and macOS examples inspired by [InfiniteChartExample](https://github.com/joshuajiangdev/InfiniteChartExample). Both display BTC/USD candlesticks, trading volume, and optional SMA 10 and EMA 10 overlays. The application fetches one-, five-, and fifteen-minute candles from Coinbase as the visible range changes. Chart time labels use UTC.

`Examples/Package.swift` is a standalone Swift package with a named local dependency on `..`, so it also builds in checkouts and worktrees with other directory names. The root `Package.swift` remains the library's build definition; the examples introduce no Xcode project or workspace.

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

The initial chart uses a bundled historical snapshot from Coinbase's public BTC/USD candles endpoint, so the first view works offline. It contains 240 candles from August 25, 2024; see the [snapshot source and format](Shared/Resources/README.md). Zooming or panning beyond cached coverage requests remote candles around the timestamps you are viewing, including historical dates. Select **Refresh** to explicitly jump to recent one-minute candles. No API key or account is required, and there is no streaming or background polling.

The status shows whether candles are bundled or fetched, their interval, and the loaded time range. A pending request keeps the current chart visible. A failed request keeps the previous data and offers **Retry**. After a history failure, Retry reloads the current viewport; after a failed Refresh, it requests recent one-minute candles again. It does not silently substitute locally aggregated candles.

Toggle **SMA 10** and **EMA 10** to show or hide the moving averages. Drag to pan, pinch to zoom, and drag an axis to adjust its range.

## Try automatic detail on either platform

1. Launch the iOS or macOS example. The label above the chart shows the current candle interval and visible time span. The default view starts with one-minute candles at typical device and window sizes; a very narrow plot may select coarser candles.
2. Select **Zoom out** (the minus magnifier) repeatedly. The application requests coarser **5-minute** and **15-minute candles** from Coinbase as more time fits into the chart. On macOS, resizing the window can also change the selected detail.
3. Select **Zoom in** (the plus magnifier) to return to finer candles. Pinching follows the same path. The price chart, volume, and indicators update together when the response arrives. Horizontal navigation preserves your vertical position and zoom; loading candles preserves both visible ranges.
4. Select **Reset** to restore the initial price and time ranges: approximately twenty-six minutes on iOS or ninety-two minutes on macOS, including padding. The interval is then chosen again for the current plot width.

Each remote window covers the visible time range plus a buffer, targeting at least 240 candles: approximately **4 hours at 1m, 20 hours at 5m, and 60 hours at 15m**. Unlike aggregating the four-hour snapshot locally, a coarser remote request loads a longer history. Pan beyond the cached window to load another window at the same resolution. Missing trading intervals stay empty. This example allows visible spans from fifteen minutes to twenty-four hours.

### Play or record the demo

Pass `--demo` to pan two hours into the loaded history, then play **1m → 5m → 15m → 1m** around that historical position, followed by Reset. It uses the same viewport API and remote requests as the controls. The sequence takes about twenty-five seconds plus network time and waits for pending data at each stop:

```sh
swift run --package-path Examples BTCMacExample --demo
./Examples/run-ios.sh --demo
```

To save the macOS example's content as a 30 fps H.264 video and exit:

```sh
swift run --package-path Examples BTCMacExample --demo --record-video /tmp/btc-macos.mp4 --record-duration 40
```

The macOS recorder captures only the example view. For iOS, build and install the example with the launcher, then use Simulator's **File → Record Screen** or `xcrun simctl io SIMULATOR_UDID recordVideo --codec=h264 /tmp/btc-ios.mp4`. Relaunch with `xcrun simctl launch --terminate-running-process SIMULATOR_UDID dev.infinitechart.BTCiOSExample --demo` to replay the sequence; stop a command-line recording with Control-C after the final reset.

### Application-owned selection

`BTCExampleScreen` subscribes to `chart.viewportStream`. `BTCChartControls` retains the subscription and cancels it when attaching a replacement chart. The current-value stream holds the latest viewport in `.value` and publishes transform and layout updates synchronously. The controls skip nil viewports and use a main-actor task to read `.value`, update the provider, and publish the visible span after the transform update completes. The chart reports its visible data ranges and plot size. The example provider uses that information to select a candle interval, with different thresholds for moving to finer versus coarser data so small movements near a boundary do not continually switch levels.

The provider requests Coinbase's native candle buckets using `granularity=60`, `300`, or `900`, together with explicit `start` and `end` timestamps. Requests exceeding Coinbase's 300-candle limit are split into smaller windows, then filtered and deduplicated. See the [Coinbase candle API](https://docs.cdp.coinbase.com/api-reference/exchange-api/rest-api/products/get-product-candles).

Viewport requests are debounced, and responses are cached by resolution and covered time range. Superseded requests are cancelled; a generation check also prevents late responses from replacing newer data. Candles, volume, SMA 10, and EMA 10 swap together after a successful response. Indicators are computed locally from the returned candles; OHLCV candles are not aggregated locally. A data swap preserves both horizontal and vertical navigation. **Refresh** intentionally starts a new viewport around the latest period and invalidates older cached windows.

The library has no BTC timeframe policy or data-fetching logic. The example application owns the intervals, density thresholds, remote requests, cache, and retry behavior.

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
