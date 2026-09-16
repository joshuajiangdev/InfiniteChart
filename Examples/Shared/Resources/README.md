# BTC/USD example snapshot

`btc-usd-1m.json` contains 240 actual Coinbase Exchange BTC-USD candles, with one-minute bucket start times from **2024-08-25 12:00 through 15:59 UTC**. It is historical example data, not a current quote. No prices, volumes, or gaps have been fabricated. The file preserves the endpoint's descending order; the example decoder sorts it for rendering.

Source request (public; no credentials):

```text
https://api.exchange.coinbase.com/products/BTC-USD/candles?granularity=60&start=2024-08-25T12%3A00%3A00Z&end=2024-08-25T15%3A59%3A00Z
```

Each row is `[Unix seconds, low, high, open, close, BTC volume]`. The provider converts seconds to milliseconds for InfiniteChart. The candle documentation is available at [Coinbase Developer Platform](https://docs.cdp.coinbase.com/api-reference/exchange-api/rest-api/products/get-product-candles).

Both applications display the source and UTC data range. They load this snapshot immediately and fetch recent candles only when **Refresh** is selected. The latest fetched candle may still be forming; fetching is a single request, not a streaming quote service. A network or decoding failure leaves the previous data visible with an error. Coinbase may omit intervals without trades, which the example leaves as gaps.

SMA(10) uses the close of each full ten-candle window. EMA(10) starts at the first ten closes' average and then applies `alpha = 2 / 11`. These indicators are calculated locally from loaded candles; missing intervals are not synthesized.
