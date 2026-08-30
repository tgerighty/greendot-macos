# Performance report — 2026-08-29

## Outcome

This work found and fixed two component-tree bottlenecks:

1. The Edit panel recalculated every descendant list for every checkbox. This
   work increased faster than linearly as tree depth increased.
2. Each severity read copied and flattened the enabled component tree before it
   selected the worst severity.

The optimized release build is 53.16 times faster in the 160-level Edit
benchmark and 14.94 times faster in the large-tree severity benchmark. The
existing parser, poll, menu, icon, cache, and request-count benchmarks did not
regress.

## Method

- Baseline product code: `b567acfdebbd7fc8e8b9ddff0b17694180b8337b` on `main`.
- The baseline worktree contained the new benchmark fixtures only. It did not
  contain the product changes.
- Candidate product code: branch `perf/measured-improvements-20260829`.
- Build: Swift `release` configuration.
- Command: `make bench`.
- Samples: five baseline runs and five candidate runs. The table reports the
  median and the full range.
- Fixtures: fixed local data and a fixed simulated 80 ms network delay. The
  benchmark does not use a live service.
- Machine: Apple M4 Max, 128 GB RAM, arm64, macOS 26.6.2 (25G83), Swift 6.3.3.

The machine was not isolated from all background work. Use the large measured
differences as evidence. Treat small differences as normal run-to-run
variation.

## Before and after

<!-- markdownlint-disable MD013 -->

| Path and fixed workload | Before, median ms (range) | After, median ms (range) | Result |
| --- | ---: | ---: | ---: |
| Picker-local Edit tree, depth 80, 20 root clicks | 55.841 (54.239–70.705) | 4.418 (4.190–5.050) | 12.64× faster; 92.1% less time |
| Picker-local Edit tree, depth 160, 20 root clicks | 360.462 (350.827–396.804) | 6.781 (6.520–7.383) | 53.16× faster; 98.1% less time |
| Display severity, 840 components, 500 reads | 56.431 (53.099–68.206) | 3.777 (3.736–4.470) | 14.94× faster; 93.3% less time |

<!-- markdownlint-enable MD013 -->

Doubling the nested-tree depth increased the old benchmark time by 6.46 times.
After the change, it increased by 1.53 times. The remaining growth includes
AppKit checkbox work. This result supports the source analysis: the old refresh
path repeatedly walked descendant subtrees, while each new tree traversal is
linear.

## Bottleneck 1: Edit component state

`ComponentPicker.refreshTreeStates()` called `ComponentTree.collect()` once for
the full tree and again for every component. It then filtered each collected
subtree. A deep tree therefore caused repeated work over the same descendants.

`ComponentSelectionIndex` now calculates the enabled count and total count for
every subtree in one bottom-up pass. The picker applies each checkbox state with
a dictionary lookup. The refresh step is now linear in the number of
components.

## Bottleneck 2: Display severity

`WatchedPage.displaySeverity` previously did this for each read:

1. Copy the enabled component tree.
2. Build an array of enabled leaves.
3. Build an array of severities.
4. Scan the severity array.

The new `ComponentTree.enabledLeafSeverity` function scans the original tree
directly. It skips disabled subtrees, creates no intermediate component arrays,
and stops when it finds red. Tests preserve the existing rules for disabled
IDs, disabled names, empty selections, nested groups, and unreachable pages.

## Existing benchmark checks

These release medians stayed stable or improved. The changes did not target
these paths, so small differences are not claimed as improvements.

<!-- markdownlint-disable MD013 -->

| Existing benchmark | Before median | After median |
| --- | ---: | ---: |
| Statuspage parse, 400 parses | 29.511 ms | 28.920 ms |
| Instatus parse, 400 parses | 1.749 ms | 1.817 ms |
| Statuspal parse, 400 parses | 3.266 ms | 3.267 ms |
| Three-page poll with 80 ms delay | 86.549 ms | 83.499 ms |
| Uncached menu, 80 builds | 17.088 ms | 16.473 ms |
| Cached menu, 80 calls | 0.138 ms | 0.129 ms |
| Status-dot images, 2,000 calls | 0.094 ms | 0.078 ms |

<!-- markdownlint-enable MD013 -->

The following discrete results also stayed unchanged:

- Three known-provider pages: three GET requests.
- Mixed-provider poll: three GET requests.
- Second unchanged poll: zero parses and zero config rewrites.
- Cached menu: one unique menu object.
- Status-dot cache: four unique images.
- Reachable pulse: zero icon refreshes.

The config-save benchmark uses the real filesystem and had a wide range. Its
median was 35.480 ms before and 40.811 ms after. This work does not claim a
file-write improvement.

## Verification

- Debug tests: 174 tests, one intentional benchmark skip, zero failures.
- Release tests: 174 tests, one intentional benchmark skip, zero failures.
- SwiftLint strict mode: zero violations.
- The release app builds, its property list is valid, and its local code
  signature passes strict verification.
- The final `make bench` run passed every benchmark assertion.
- macOS UI tests: 17 tests, zero failures.

After Accessibility permission was restored, `make uitest` ran the complete UI
suite. This included clicking every Edit checkbox five times and switching Edit
between two pages five times. All tests passed.

## Benchmark coverage and limits

`make bench` now uses the release configuration by default and covers parsing,
polling, provider request counts, menu construction, component selection,
severity calculation, status-dot caching, file saves, unchanged writes, regex
reuse, parse reuse, and reachable pulse work.

The benchmark does not measure live network latency, AppKit screen compositing,
energy use, heap allocation counts, or monitor persistence during an Edit
click. The picker benchmark uses a successful in-memory callback and measures
the picker-local lookup, state update, AppKit action, and refresh. Network
latency still dominates a normal poll. A future Instruments run can add energy
and allocation evidence if the app gains longer lists or more frequent UI
updates.
