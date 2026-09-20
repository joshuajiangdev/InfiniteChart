# Rendering core audit

Audited `main` at `42dcb0e` (2026-09-20). Scope: library sources, public provider and
viewport contracts, transforms, renderer composition, axis layout, native gestures,
package/CI integration, and regression coverage. No unmerged feature branches were
included. Examples were used only to validate consumer compatibility.

The library owns drawing, coordinate conversion, axes, gestures, and viewport
reporting. Applications own data fetching, storage, aggregation, indicator
calculation, and product-specific navigation limits.

## Findings addressed

| Area | Defect | Change |
| --- | --- | --- |
| Coordinates | Per-point arrays and 3×3 BLAS multiplication; unchecked LAPACK inversion | `CGAffineTransform` and a cached inverse, with finite/invertible validation; legacy public names remain aliases |
| Zoom | A 60,000-unit / 300-minute limit affected arbitrary data and vertical zoom | Removed time-unit policy; reject invalid numerical updates |
| Data traversal | Fixed one-minute strides and rounding dropped fractional/irregular samples | Traverse available provider neighbors with finite, forward-progress checks |
| Native drawing | Line provider rendering was disabled; content could spill into axes | Enable line rendering and clip all plot content |
| Samples | Nonfinite values entered paths; missing line data could bridge gaps | Skip invalid candles/volumes and break line/overlay paths at invalid samples |
| Candles/volume | Flat candles were invisible; offscreen volume could alter scaling; graphics state leaked | Minimum one-point candle bodies, visible finite volume normalization, balanced graphics state |
| Loading | Optional initial ranges caused a fatal error | Keep the viewport unavailable and labels empty until valid ranges arrive through a redraw |
| Invalidation | `CombineLatest` waited for a provider's first redraw before navigation invalidated drawing | Merge independent transform/redraw events |
| Resize | Layout restored original ranges and discarded navigation | Scale the pixel transform while preserving visible data ranges |
| Axes | Invalid counts/ranges could trap or produce unbounded ticks; Y labels ignored width; color was unused | Shared bounded tick generation, normalized spacing, actual label width, colored axis lines |
| Setup | Repeated public setup accumulated subscriptions | Axis setup cancels prior subscriptions |
| Provider surface | Unused delegate and overlays were mandatory boilerplate | Default nil delegate and empty overlays |
| Structure | Dead axis placeholders/numeric utilities and an embedded overlay renderer | Remove unused internals and keep the overlay renderer with the render modules |

Core Graphics is a direct fit for this scale/translation mapping; see Apple's
[CGAffineTransform documentation](https://developer.apple.com/documentation/corefoundation/cgaffinetransform).
No layer transforms, caching policy, data services, or additional dependencies were added.

## Deliberate API limits

- Composition enables built-in renderers through one provider conforming to multiple
  protocols. Independent renderer injection is not public yet. A future renderer
  protocol should stay small and separate from data loading.
- Line/candle/bar widths, line color, and the volume panel fraction remain fixed.
  Style/layout configuration is a useful follow-up, separate from these correctness fixes.
- `viewportStream` remains a public `CurrentValueSubject` for source compatibility;
  consumers must only read/subscribe. A read-only current-value abstraction would
  prevent external sends/completion but requires a deliberate API migration.
- The misspelled legacy `tranformerUpdatedDelegate` is unused and retained with a
  default nil implementation. Use `viewportStream` for observations.
- Rendering scales with the number of supplied samples, including complete overlay
  series. Applications still select their data detail; no library aggregation or
  frame-latency guarantee is introduced.

## Validation

Regression tests cover both native platforms: loading and silent providers, resize
preservation, timestamp precision and anchored zoom, invalid gestures/ranges, arbitrary
sample spacing, path gaps, flat candles, volume normalization, clipping, and axis
configuration. Validation passed with 51 tests on macOS, 51 tests on iOS 27 Simulator, and 13
standalone example tests. The standalone iOS example also built successfully.
Swift source builds produced no warnings; Xcode's unrelated App Intents metadata
step reports that the library has no App Intents dependency.

The reproducible conversion microbenchmark is run with:

```sh
swiftc -O -whole-module-optimization Benchmarks/TransformerBenchmark.swift -o /tmp/infinitechart-transform-benchmark
/tmp/infinitechart-transform-benchmark 1720000000000
```

On Apple M4 / Swift 6.4, seven alternating rounds of 400 batches × 5,000 timestamp
points measured a median **0.337117 ms per batch** for the prior vDSP implementation
and **0.005026 ms** for affine conversion (67.08×). All checked coordinates and
checksums matched. This isolates forward point conversion and legacy allocation
cost; it is not an end-to-end chart or frame-time measurement.
