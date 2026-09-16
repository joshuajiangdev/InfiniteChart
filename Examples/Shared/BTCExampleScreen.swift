import SwiftUI
import InfiniteChart

/// The same chart/data provider hosted by a native view on each platform.
public struct BTCExampleScreen: View {
    @StateObject private var provider: BTCDataProvider

    public init() {
        #if os(iOS)
        _provider = StateObject(wrappedValue: BTCDataProvider(visibleCandleCount: 60))
        #else
        _provider = StateObject(wrappedValue: BTCDataProvider(visibleCandleCount: 120))
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
                    Text("Bitcoin · 1 minute candles")
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

            if provider.getInitDataRanges() != nil {
                BTCNativeChart(provider: provider)
                    .id(provider.revision)
                    .frame(minHeight: 180, maxHeight: .infinity)
                    .background(Color.white)
                    .accessibilityLabel("Bitcoin price candlesticks with trading volume")
            } else {
                Text("BTC data is unavailable. Refresh to load candles.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(provider.statusText)
                    .font(.caption.weight(.medium))
                Text(provider.sourceText + " · " + provider.rangeText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let message = provider.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                        .accessibilityLabel("Data refresh error: " + message)
                }
                Text("Drag to pan · Pinch to zoom · Drag an axis to adjust it")
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
private func makeBTCChart(provider: BTCDataProvider) -> InfiniteChartBase {
    let timeFormatter = DateFormatter()
    timeFormatter.locale = Locale(identifier: "en_US_POSIX")
    timeFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    timeFormatter.dateFormat = "HH:mm"

    return InfiniteChartBase(
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
}

#if os(macOS)
private struct BTCNativeChart: NSViewRepresentable {
    let provider: BTCDataProvider

    func makeNSView(context: Context) -> InfiniteChartBase { makeBTCChart(provider: provider) }
    func updateNSView(_ nsView: InfiniteChartBase, context: Context) {}
}
#else
private struct BTCNativeChart: UIViewRepresentable {
    let provider: BTCDataProvider

    func makeUIView(context: Context) -> InfiniteChartBase { makeBTCChart(provider: provider) }
    func updateUIView(_ uiView: InfiniteChartBase, context: Context) {}
}
#endif
