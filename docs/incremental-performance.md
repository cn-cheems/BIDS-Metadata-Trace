# Incremental impact measurements — 2026-10-27

The [raw report](performance-data/incremental-linux-x86_64.json) contains 96
measured cases and 24 complete-report equivalence checks. The native release
benchmark compares the existing full algorithm with cold and warm graph updates
on the **same current code and toolchain**, not with timings from earlier commits.

Host: Intel i9-14900HX, WSL2 Linux x86_64. Toolchain: MoonBit
0.10.17+d971670cd, C/GCC Native release. Recorded binary SHA-256:
`816efdbba76379493cd2b142f636fd2f35fd19c758044b4ab8a575b7187bddd8`.
The report records parent revision `ceae5a5`, `working_tree:true`, changed paths,
host/toolchain details and collection time. The benchmark/core changes and this
report are committed together after collection. No performance claim applies
to other backends, hosts, real datasets or metadata distributions.

## What was measured

`cmd/impact-benchmark PHASE SHAPE SCANS SAMPLES` accepts:

- Phases: `full` (ordinary compare), `cold` (build graph then advance), `warm`
  (advance a graph built outside timing), `graph` (initial construction),
  `verify` (untimed full-report byte equality and complete evidence).
- Shapes: `local`, `root`, `add`, `remove`, `unmatched`, `noop`, `inventory`,
  `ambiguity`. Scans: 4–5000; samples: 3–31. Unknown/invalid arguments reject.

The synthetic snapshot has two runs per subject, one shared BOLD source, one
subject01 override and an unmatched T1w source. Values include null, negative
zero, a large integer and an overflowing exponent. Local changes edit the first
subject override (two affected scans); add/remove introduce/remove a scoped
source; unmatched/noop resolve no scans. Inventory replaces one scan path;
ambiguity introduces a second root source and retains unresolved diagnostic evidence
for every scan. Root edits change provenance even where values are shadowed.

Each measurement launches a separate executable, performs one untimed warmup
and seven individual timed operations, consumes the result count and emits raw
microsecond samples plus their median. Workload creation, initial immutable
snapshot validation, process startup, full verification and output serialization
are outside timing. Warm includes producing the complete impact report and
rebuilding the next graph. Cold includes graph construction. Graph measures
initial construction plus obtaining its cached audit entries. Phases rotate
execution order between shapes/sizes; samples within a phase are consecutive.
No other local builds/tests were run during collection.

`/usr/bin/time` reports **whole-process peak RSS** in KiB. Only warm holds a
prepared graph before timing. RSS includes fixture construction, initial
snapshots, warmup, live results and allocator behavior; it is not isolated cache
memory, a strict limit or a cross-platform comparison. Every shape/size also
executes `verify`: the entire impact report is compared byte for byte, including
unchanged/error evidence, exact values, histories and source chains. Matching
result counts in timed phases provides an additional check, not equivalence.

## Observations

5000-scan medians (milliseconds); RSS compares full versus warm:

| Change | Full ms | Cold ms | Warm ms | Graph ms | Full → warm RSS KiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Local edit | 44.100 | 14.311 | 5.378 | 8.686 | 21588 → 18580 |
| Root edit | 36.968 | 45.784 | 34.299 | 8.694 | 23252 → 33636 |
| Add scoped source | 43.875 | 14.210 | 5.553 | 8.789 | 22228 → 18580 |
| Remove scoped source | 44.364 | 13.671 | 5.444 | 8.608 | 21420 → 18644 |
| Edit unmatched source | 44.526 | 14.137 | 5.559 | 9.540 | 22084 → 18496 |
| No change | 43.000 | 15.470 | 5.828 | 8.880 | 21856 → 18580 |
| Replace one scan | 46.149 | 16.251 | 8.575 | 8.588 | 22100 → 20116 |
| Introduce ambiguity | 10.209 | 16.989 | 9.387 | 8.483 | 16980 → 19924 |

In this run, local warm comparison took about 8.2× less time than full compare
and resolved 2/reused 4998 scans. Warm still traverses inventory/dependencies and
allocates a complete report: this is not constant-time work. Root edits resolve
all 5000 scans; cold was about 24% slower than full, with warm peak RSS about 45%
higher. Introducing ambiguity also made cold slower and raised warm RSS. Small
or modest differences can reflect noise; no general improvement is claimed for
all-affecting changes. Initial graphs cost roughly8–10 ms at this size.

The report retains all 100/1000/5000-scan measurements, including regressions.
Serialization and complete CLI startup were not optimized or timed. Preserve
this report when rerunning; compare identical workloads on the same host with
quiet conditions and inspect raw samples, work counts and costs together.

## Reproduce

With Linux Native dependencies installed and a C toolchain:

```sh
moon build --target native --release cmd/impact-benchmark --deny-warn
moon run scripts/benchmark-incremental.mbtx -- _build/native/release/build/cmd/impact-benchmark/impact-benchmark.exe /absolute/path/to/moon _build/performance/incremental
```

Use the artifact path printed by your toolchain. The second argument identifies
the Moon binary used for the native build, for recorded toolchain metadata. On
Windows, `--wsl` at the end dispatches native commands to Ubuntu; binary/Moon
paths must then be Linux paths while the output directory is a Windows-side
path. `--quick` after `--wsl`, or by itself, selects100-scan cases only. The
collector removes stale summary evidence before work and writes it only after
every measurement/equivalence check succeeds. Individual samples and complete
verified outputs are retained under the chosen output directory. No network or
private dataset is needed after installing dependencies.

All four timing phases are executed in unit tests, and actual Wasm/Wasm-GC/JS
release launches plus invalid-argument failures run in the end-to-end gate.
Actual Native tests and measurements execute the native binary. The collector
uses Linux-specific RSS support; portable timing can run the executable directly.
