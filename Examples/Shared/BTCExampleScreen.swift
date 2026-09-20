import SwiftUI
import Combine
import InfiniteChart

/// The same chart/data provider hosted by a native view on each platform.
@MainActor
public struct BTCExampleScreen: View {
    @StateObject private var provider: BTCDataProvider
    @StateObject private var chartControls = BTCChartControls()

    public init() {
        #if os(iOS)
        _provider = StateObject(wrappedValue: BTCDataProvider(visibleCandleCount: 24))
        #else
        _provider = StateObject(wrappedValue: BTCDataProvider(visibleCandleCount: 90))
        #endif
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("INFINITECHART EXAMPLE")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text("BTC / USD")
                        .font(.title.weight(.bold))
                    Text("Bitcoin · remote detail")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 12)
                Button {
                    Task { await provider.refresh() }
                } label: {
                    Label(provider.isLoading ? "Loading…" : "Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(provider.isLoading)
                .accessibilityLabel("Refresh BTC market data")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(provider.latestPriceText)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(provider.changeText)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(provider.isPriceUp ? .green : .red)
            }

            HStack(spacing: 20) {
                Toggle("SMA 10", isOn: $provider.showingSMA)
                    .tint(.blue)
                Toggle("EMA 10", isOn: $provider.showingEMA)
                    .tint(.purple)
            }
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)

            Divider()

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.detailText)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("chart-detail-level")
                    Text(chartControls.visibleSpanText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .accessibilityIdentifier("chart-visible-span")
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button(action: chartControls.zoomOut) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .accessibilityLabel("Zoom out")
                    .accessibilityIdentifier("chart-zoom-out")
                    Button(action: chartControls.zoomIn) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .accessibilityLabel("Zoom in")
                    .accessibilityIdentifier("chart-zoom-in")
                    Button("Reset", action: chartControls.reset)
                        .accessibilityLabel("Reset chart viewport")
                        .accessibilityIdentifier("chart-reset")
                }
                .buttonStyle(.bordered)
                .fixedSize(horizontal: true, vertical: false)
            }

            if provider.getInitDataRanges() != nil {
                BTCNativeChart(provider: provider, controls: chartControls)
                    .id(provider.revision)
                    .frame(minHeight: 180, maxHeight: .infinity)
                    .background(Color.white)
                    .accessibilityLabel("Bitcoin price candlesticks with trading volume")
            } else {
                Text("BTC data is unavailable. Refresh to load candles.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if provider.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Loading candle history")
                    }
                    Text(provider.statusText)
                        .font(.caption.weight(.medium))
                }
                Text(provider.sourceText + " · " + provider.rangeText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let message = provider.errorMessage {
                    HStack {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.red)
                            .accessibilityLabel("Candle loading error: " + message)
                        Button("Retry") {
                            Task { await provider.retryFailedLoad() }
                        }
                        .disabled(provider.isLoading)
                    }
                }
                Text("Zoom for remote 1m / 5m / 15m candles · Pan to load more history")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Drag to pan · Pinch or use + / − to zoom · Drag an axis to adjust it")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(Color.white)
        .preferredColorScheme(.light)
    }
}

@MainActor
final class BTCChartControls: ObservableObject {
    @Published private(set) var visibleSpanText = "Preparing chart…"
    private(set) weak var chart: InfiniteChartBase?
    private weak var provider: BTCDataProvider?
    private var dataObservation: AnyCancellable?
    private var viewportObservation: AnyCancellable?
    private var lastAutoFitXRange: ClosedRange<Double>?
    private var demoTask: Task<Void, Never>?

    func attach(_ chart: InfiniteChartBase, provider: BTCDataProvider) {
        demoTask?.cancel()
        dataObservation?.cancel()
        viewportObservation?.cancel()
        self.chart = chart
        self.provider = provider
        lastAutoFitXRange = nil
        dataObservation = provider.redrawStream
            .sink { [weak self, weak chart] _ in
                Task { @MainActor [weak self, weak chart] in
                    guard let self, let chart, self.chart === chart else { return }
                    self.fitPriceRange()
                }
            }
        viewportObservation = chart.viewportStream
            .compactMap { $0 }
            .sink { [weak self, weak provider, weak chart] _ in
                // Finish the transform/layout update before fitting prices or
                // publishing SwiftUI state, and use the latest completed viewport.
                Task { @MainActor [weak self, weak provider, weak chart] in
                    guard let self, let chart, self.chart === chart,
                          let viewport = chart.viewportStream.value else { return }
                    provider?.updateViewport(viewport)
                    self.updateViewport(viewport)
                }
            }
        guard CommandLine.arguments.contains("--demo") else { return }
        // Opt-in recording mode follows the same viewport stream and provider
        // policy as gestures and buttons, including remote history requests.
        demoTask = Task { [weak self, weak chart] in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, let chart, self.chart === chart else { return }
                try await self.runDemo(chart)
            } catch {
                // Replacing the native chart cancels its previous demo.
            }
        }
    }

    func updateViewport(_ viewport: ChartViewport) {
        let minutes = Int(((viewport.visibleXRange.upperBound - viewport.visibleXRange.lowerBound) / 60_000).rounded())
        let hours = minutes / 60
        let remainder = minutes % 60
        let span: String
        if hours == 0 { span = "\(minutes)m" }
        else if remainder == 0 { span = "\(hours)h" }
        else { span = "\(hours)h \(remainder)m" }
        visibleSpanText = "Viewing \(span) · UTC"
        if lastAutoFitXRange != viewport.visibleXRange {
            lastAutoFitXRange = viewport.visibleXRange
            fitPriceRange()
        }
    }

    // Application policy: fit prices after horizontal navigation or a data
    // replacement. The chart retains its exact horizontal range throughout.
    private func fitPriceRange() {
        guard let chart, let viewport = chart.viewportStream.value,
              let range = provider?.priceRange(in: viewport.visibleXRange) else { return }
        chart.setVisibleYRange(range)
    }

    func zoomIn() { scaleVisibleRange(by: 0.5) }
    func zoomOut() { scaleVisibleRange(by: 2) }
    func reset() { chart?.resetViewport() }

    private func scaleVisibleRange(by factor: Double) {
        guard let chart, let range = chart.viewportStream.value?.visibleXRange else { return }
        let center = range.lowerBound + (range.upperBound - range.lowerBound) / 2
        let halfSpan = (range.upperBound - range.lowerBound) * factor / 2
        chart.setVisibleXRange((center - halfSpan)...(center + halfSpan))
    }

    private func runDemo(_ chart: InfiniteChartBase) async throws {
        // Native layout normally finishes during the initial two-second delay.
        for _ in 0..<20 where chart.viewportStream.value == nil {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let viewport = chart.viewportStream.value else { return }
        let range = viewport.visibleXRange
        let center = range.lowerBound + (range.upperBound - range.lowerBound) / 2
        let width = Double(viewport.plotSize.width)
        let spacing = 10.0 // Also clears the app's threshold for returning to 1m.

        for (interval, duration) in [(1, 1.0), (5, 2.0), (15, 2.0), (1, 3.0)] {
            let requestedSpan = width * Double(interval) * 60_000 / spacing
            let span = chart.xSpanLimits.map {
                min(max(requestedSpan, $0.lowerBound), $0.upperBound)
            } ?? requestedSpan
            try await animate(chart, center: center, span: span, duration: duration)
            try await hold(chart, stage: "target \(interval)m", duration: 2)
        }
        chart.resetViewport()
        try await hold(chart, stage: "reset", duration: 1)
        print("BTC demo complete")
    }

    private func animate(_ chart: InfiniteChartBase, center: Double, span: Double, duration: Double) async throws {
        guard let range = chart.viewportStream.value?.visibleXRange else { return }
        let initialSpan = range.upperBound - range.lowerBound
        let frames = Int(duration * 30)
        for frame in 1...frames {
            try Task.checkCancellation()
            let progress = Double(frame) / Double(frames)
            let eased = progress * progress * (3 - 2 * progress)
            let currentSpan = exp(log(initialSpan) + (log(span) - log(initialSpan)) * eased)
            chart.setVisibleXRange((center - currentSpan / 2)...(center + currentSpan / 2))
            try await Task.sleep(nanoseconds: 33_333_333)
        }
    }

    private func hold(_ chart: InfiniteChartBase, stage: String, duration: Double) async throws {
        // Wait for debounced remote data, rather than recording only a pending
        // resolution label. Offline/error states still finish the demo.
        try await Task.sleep(nanoseconds: 100_000_000)
        for _ in 0..<300 {
            guard provider?.isLoading == true else { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if let range = chart.viewportStream.value?.visibleXRange {
            let minutes = (range.upperBound - range.lowerBound) / 60_000
            print("BTC demo \(stage): displayed \(provider?.candleIntervalMinutes ?? 1)m, visible \(String(format: "%.1f", minutes)) minutes; \(provider?.rangeText ?? "no data")")
        }
        try await Task.sleep(nanoseconds: UInt64((duration - 0.1) * 1_000_000_000))
    }
}

@MainActor
private func makeBTCChart(provider: BTCDataProvider, controls: BTCChartControls) -> InfiniteChartBase {
    let timeFormatter = DateFormatter()
    timeFormatter.locale = Locale(identifier: "en_US_POSIX")
    timeFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    timeFormatter.dateFormat = "HH:mm"

    let chart = InfiniteChartBase(
        frame: .zero,
        dataProvider: provider,
        xAxisConfig: AxisConfig(
            labelCount: 6,
            labelFont: .systemFont(ofSize: 10),
            requiredSpace: 46,
            labelFormatter: { timeFormatter.string(from: Date(timeIntervalSince1970: $0 / 1000)) }
        ),
        yAxisConfig: AxisConfig(
            labelCount: 7,
            labelFont: .systemFont(ofSize: 10),
            requiredSpace: 68,
            labelFormatter: { String(format: "%.0f", $0) }
        )
    )
    // This application's X values are Unix milliseconds. Detail selection lives
    // in BTCDataProvider; the chart only reports its viewport and renders data.
    chart.xSpanLimits = (15 * 60_000.0)...(24 * 60 * 60_000.0)
    controls.attach(chart, provider: provider)
    return chart
}

#if os(macOS)
private struct BTCNativeChart: NSViewRepresentable {
    let provider: BTCDataProvider
    let controls: BTCChartControls

    func makeNSView(context: Context) -> InfiniteChartBase { makeBTCChart(provider: provider, controls: controls) }
    func updateNSView(_ nsView: InfiniteChartBase, context: Context) {}
}
#else
private struct BTCNativeChart: UIViewRepresentable {
    let provider: BTCDataProvider
    let controls: BTCChartControls

    func makeUIView(context: Context) -> InfiniteChartBase { makeBTCChart(provider: provider, controls: controls) }
    func updateUIView(_ uiView: InfiniteChartBase, context: Context) {}
}
#endif
