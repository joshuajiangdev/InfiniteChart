# InfiniteChart

A UIKit charting library distributed with Swift Package Manager. `Package.swift`
defines the library and its tests; no `.xcodeproj` or checked-in workspace is
required.

## Requirements

- Swift 5.10 or later and an Xcode installation with the Apple platform SDKs.
- iOS 13 or later, or Mac Catalyst 13 or later.

The library uses UIKit, Combine, and Accelerate. Native macOS, watchOS, and tvOS
are not supported.

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

## Build and test

Run these commands from the repository root. Xcode's command-line tools read the
Swift package directly and provide its `InfiniteChart` scheme.

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

Build for Mac Catalyst:

```sh
xcodebuild -scheme InfiniteChart \
    -destination 'generic/platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath .build/catalyst \
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

Plain `swift build` and `swift test` select the host macOS platform, which cannot
import UIKit. Use an iOS Simulator or Mac Catalyst destination as shown above.
You can also open `Package.swift` directly in Xcode. Generated `.swiftpm`, build,
and IDE files are ignored by Git.
