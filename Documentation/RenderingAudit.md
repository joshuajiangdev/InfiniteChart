# Rendering core audit

The original audit examined `main` at `42dcb0e` on 2026-09-20. Its scope was library
sources, public provider and viewport contracts, transforms, renderer composition,
axis layout, native gestures, package/CI integration, and regression coverage.
That audit excluded unmerged feature branches and used examples to validate consumer
compatibility. This document was updated on 2026-09-22 for the viewport ownership
cleanup, SwiftDoc audit, and remaining stack based on `main` at `460d335`.

The library owns drawing, coordinate conversion, axes, gestures, and viewport
reporting. Applications own data fetching, storage, aggregation, indicator
calculation, and product-specific navigation limits.

## Review order

The original combined PR #4 is superseded by the split changes. The coordinate
foundation ([#12](https://github.com/joshuajiangdev/InfiniteChart/pull/12)), viewport
lifecycle fixes ([#13](https://github.com/joshuajiangdev/InfiniteChart/pull/13)),
provider defaults ([#14](https://github.com/joshuajiangdev/InfiniteChart/pull/14)), and
viewport ownership ([#19](https://github.com/joshuajiangdev/InfiniteChart/pull/19))
are merged into `main` at `460d335`.

PR #15 now starts directly at that `main`; the remaining PRs follow in the order
below. Each code PR contains one commit relative to its parent branch. Merge in
this order, then retarget/restack the next PR onto `main` after its parent lands.
The documentation PR follows the axis PR and introduces no runtime changes.

| Order | Responsibility | macOS tests at that branch |
| --- | --- | --- |
| 1 | [Render provider-defined samples and handle invalid values](https://github.com/joshuajiangdev/InfiniteChart/pull/15) | 49 passed |
| 2 | [Compose built-in drawing inside the plot bounds](https://github.com/joshuajiangdev/InfiniteChart/pull/16) | 51 passed |
| 3 | [Make axis ticks and layout safe and configurable](https://github.com/joshuajiangdev/InfiniteChart/pull/17) | 55 passed |
| 4 | [Architecture and audit documentation (this change)](https://github.com/joshuajiangdev/InfiniteChart/pull/18) | Same code as step 3 |

The remaining stack retains the original rendering fixes and derives viewport
snapshots from the transform provider's own committed state.
The [architecture review](Architecture.md) explains current composition limits and
proposes a small public drawing interface; that proposal is not implemented here.

## Findings addressed

| Area | Defect | Change |
| --- | --- | --- |
| Coordinates | Per-point arrays and 3×3 BLAS multiplication; unchecked LAPACK inversion | `CGAffineTransform` and a cached inverse, with finite/invertible validation; legacy public names remain aliases |
| Zoom | A 60,000-unit / 300-minute limit affected arbitrary data and vertical zoom | Removed time-unit policy; reject invalid numerical updates |
| Viewport ownership | Callers passed a transformer back to its provider; publication preceded stored-state updates | Derive `provider.viewport` from its current transformer; use private current-value storage that commits before notifying, and validate candidate geometry before mutation |
| Data traversal | Fixed one-minute strides and rounding dropped fractional/irregular samples | Traverse available provider neighbors with finite, forward-progress checks |
| Native drawing | Line provider rendering was disabled; content could spill into axes | Enable line rendering and clip all plot content |
| Samples | Nonfinite values entered paths; missing line data could bridge gaps | Skip invalid candles/volumes and break line/overlay paths at invalid samples |
| Candles/volume | Flat candles were invisible; offscreen volume could alter scaling; graphics state leaked | Minimum one-point candle bodies, visible finite volume normalization, balanced graphics state |
| Loading | Optional initial ranges caused a fatal error | Keep the viewport unavailable and labels empty until valid ranges arrive through a redraw |
| Invalidation | `CombineLatest` waited for a provider's first redraw before navigation invalidated drawing | Merge independent transform/redraw events |
| Resize | Layout restored original ranges and discarded navigation | Scale the pixel transform while preserving visible data ranges |
| Axes | Invalid counts/ranges could trap or produce unbounded ticks; Y labels ignored width; color was unused | Shared bounded tick generation, normalized spacing, actual label width, colored axis lines |
| Setup | Repeated public setup accumulated subscriptions | Axis setup cancels prior subscriptions |
| Provider surface | Unused delegate and overlays were mandatory boilerplate | Remove the delegate protocol/property and default to empty overlays |
| Structure | Dead axis placeholders/numeric utilities, an embedded overlay renderer, and unused gesture-view stream plumbing | Remove unused internals and the gesture protocol's publisher/associated type; keep the overlay renderer with the render modules |
| API documentation | Missing callable contracts and malformed provider parameter documentation | Add SwiftDoc to public/internal functions in the touched code, describe non-obvious private helpers, and document sampling, coordinate, invalid-input, and graphics-state behavior |

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
- The unused `ChartDataProviderDelegate` protocol and misspelled
  `tranformerUpdatedDelegate` property are removed. Consumers referencing them must
  delete those declarations; observe `viewportStream` for ranges and plot-size changes.
- Rendering scales with the number of supplied samples, including complete overlay
  series. Applications still select their data detail; no library aggregation or
  frame-latency guarantee is introduced.

## Validation

Regression tests cover both native platforms: loading and silent providers, resize
preservation, timestamp precision and anchored zoom, invalid gestures/ranges, arbitrary
sample spacing, path gaps, flat candles, volume normalization, clipping, and axis
configuration. The viewport ownership regressions additionally cover synchronous
reads of committed state, first valid ranges matching the placeholder transform,
late subscribers, and rejected or unchanged updates.

On 2026-09-22, the new foundation passed 43 tests on both macOS and iOS Simulator.
The restacked code through PR #17 passed 55 tests on macOS and 55 tests on iOS 27
Simulator; PR #18 has identical runtime code. All 13 standalone example tests
passed, and the standalone iOS example built successfully.

The SwiftDoc audit changed comments only in the Swift sources. Comparing each
updated branch with its prior revision confirmed that all non-documentation source
remained identical.

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
