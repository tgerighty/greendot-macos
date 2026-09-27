# Performance report — 2026-09-26

## Outcome

One CPU bottleneck remains in the Edit component list.

A click on an allowed region group called `RegionFilter.allowedIDs` once for every descendant. Each call walks the whole tree. Doubling the leaf count multiplied that time by 3.92.

The release build is 39.55 times faster on the 800-leaf click. The slowest run after the change is 2.204 ms. The fastest run before the change is 74.917 ms. Those ranges do not overlap.

Parser, poll, menu, icon, cache, and request-count results stay inside the run-to-run spread. This report does not treat those differences as improvements.

## Method

- Baseline product code: `afa8be22c335ee4d26dcf1462cdc7ffea6f51c49` on `perf/region-filter-scan-20260926`.
- That revision contains the new benchmark workloads. It does not contain the one-scan change.
- Candidate product code: `aa6a8e04fc0080c4eb5678cdc38f4bd31d7e3803`.
- Build: Swift `release` configuration.
- Command: `make bench`.
- Samples: five baseline runs and five candidate runs. Each table shows the median and the full range.
- Fixtures: fixed local data and a fixed simulated 80 ms network delay. The benchmark does not call a live service.
- Machine: Apple M4 Max, 128 GB RAM, arm64, macOS 27.0 (26A428), Swift 6.4 (swiftlang-6.4.0.34.1).

The machine was not isolated from other work. Use the large measured difference as evidence. Treat a gap inside one run's spread as normal variation.

## Before and after

<!-- markdownlint-disable MD013 -->

| Path and fixed workload | Before, median ms (range) | After, median ms (range) | Result |
| --- | ---: | ---: | --- |
| Region-filter click, 800 leaves, 1 click | 75.615 (74.917–80.838) | 1.912 (1.831–2.204) | 39.55× faster. 97.5% less time. Ranges do not overlap. |
| Region-filter click, 400 leaves, 1 click | 19.281 (19.019–21.497) | 0.958 (0.935–1.080) | Same fix at half the tree. 20.13× faster. Ranges do not overlap. |

<!-- markdownlint-enable MD013 -->

Doubling the leaf count raised the old median from 19.281 ms to 75.615 ms. After the change, the same doubling raised the median from 0.958 ms to 1.912 ms. The new ratio is 2.00. That matches one walk of the tree.

## Bottleneck: repeated region scan

`ComponentPicker` handles a click on a row that is not a top-level region. It collects that component and its descendants. It then asks whether the user enabled every descendant.

The old check called `RegionFilter.allowedIDs` for each descendant. `allowedIDs` walks the full tree. It compares each component name and id with the region list. An allowed group of 800 leaves walked the tree about 800 times.

The 80 ms probe delay is not part of this workload. The before-run spread on the 800-leaf click is 74.917–80.838 ms. The 3.92 times growth from 400 leaves to 800 leaves sits far outside that spread.

The click now builds the allowed id set once and reuses that set. The mute result stays the same. `testGroupClickEnablesEveryAllowedDescendantWhenOneLeafIsMuted` clicks a group that has one muted leaf. The click enables every allowed descendant. A region outside the allowlist stays out of the mute list.

## New parser workload

The harness also parses a fixed AWS Health payload. The AWS Health parser arrived after the 2026-08-29 report. The payload has 200 events. Each event has 8 services. The benchmark parses that payload 30 times.

This path is not the bottleneck. The before median is 57.466 ms (range 56.167–64.335). The after median is 58.262 ms (range 56.586–61.844). The ranges overlap. This report does not claim a parser improvement.

## Existing benchmark checks

These paths were already in the 2026-08-29 harness. This change did not target them. Every before range overlaps the after range. The differences are noise.

<!-- markdownlint-disable MD013 -->

| Existing benchmark | Before, median ms (range) | After, median ms (range) |
| --- | ---: | ---: |
| Statuspage parse, 400 parses | 30.833 (29.617–32.610) | 30.094 (29.019–31.791) |
| Instatus parse, 400 parses | 1.588 (1.572–1.724) | 1.740 (1.618–1.785) |
| Statuspal parse, 400 parses | 3.082 (2.905–3.502) | 3.096 (2.978–3.300) |
| Three-page poll with 80 ms delay | 89.426 (85.413–92.378) | 84.988 (82.827–91.988) |
| Uncached menu, 80 builds | 30.437 (21.461–37.531) | 20.493 (18.160–29.006) |
| Cached menu, 80 calls | 0.154 (0.141–0.167) | 0.136 (0.116–0.148) |
| Edit tree, depth 80, 20 root clicks | 3.512 (3.430–3.631) | 3.446 (3.336–3.889) |
| Edit tree, depth 160, 20 root clicks | 6.382 (6.320–6.656) | 6.484 (6.380–7.354) |
| Severity read, 840 components, 500 reads | 2.326 (2.210–2.334) | 2.360 (2.208–2.538) |
| Status-dot images, 2,000 calls | 0.051 (0.048–0.064) | 0.047 (0.045–0.057) |

<!-- markdownlint-enable MD013 -->

The config-save benchmark uses the real filesystem. Its before median is 75.549 ms (range 41.144–80.382). Its after median is 55.384 ms (range 43.175–73.662). The ranges overlap. This work does not claim a file-write improvement.

The printed line `pollAll_3page_delay_expected_sequential_ms` is 240.000 in every run. It is 3 times the fixed 80 ms delay. It is not a measured CPU path.

The following counts also stayed the same in every run:

- Three known-provider pages: 3 GET requests.
- Mixed-provider poll: 3 GET requests.
- Second unchanged poll: 0 parses and 0 config rewrites.
- Cached menu: 1 menu object.
- Status-dot cache: 4 images.
- Known Statuspal host: 4 GET requests.
- Statuspal regex: 1 compile.
- Reachable pulse: 0 icon refreshes.

## Verification

- Debug `swift test`, with `GREENDOT_BENCH` unset: 520 tests, 1 intentional benchmark skip, 0 failures.
- SwiftLint strict mode: 0 violations.
- Each of the ten `make bench` runs passed every harness assertion.

## Benchmark coverage and limits

`make bench` uses the release configuration. It covers the 2026-08-29 workloads. It also covers a region-filtered group click at 400 leaves and at 800 leaves, and one large AWS Health parse.

The benchmark does not measure live network latency, AppKit screen compositing, energy use, or heap allocation counts. The region-filter click includes the region scan and the checkbox update. Network latency still dominates a normal poll.
