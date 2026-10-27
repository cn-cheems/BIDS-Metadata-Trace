# Dependency-driven incremental impact

For repeated metadata reviews, build an immutable graph once, advance it to a
new validated snapshot and reuse unaffected resolution results. Every update
returns the same complete `ImpactReport` contract as `DatasetIndex::compare`,
plus actual invalidation/work counts and a next graph for subsequent updates.

## Library workflow

```mbt nocheck
let graph = before.dependency_graph()
let update = graph.advance(after)
update.verify_full() // optional full-report byte equality check
let impact = update.report()
let release = impact.release_check(@trace.ReleasePolicy::AllChanges)
let next = update.next()
// Feed the next immutable snapshot to next.advance(...).
```

`DatasetIndex::dependency_graph()` resolves each indexed scan once and records
all applicable source-to-scan dependencies. These include empty sources,
overwritten values and every ambiguity participant. Unmatched sources remain
in the snapshot/graph evidence with an empty dependent list.

`DependencyGraph::snapshot()`, `audit()`, `dependents(source_path)` and `to_json()`
expose the immutable snapshot, complete cached audit, sorted dependent paths for
an existing exact source path, and deterministic evidence. An unknown source
raises `unknown_sidecar_path`; an existing unmatched source returns `[]`.
Returned arrays/JSON accessors preserve the existing defensive-copy contract.

`DependencyGraph::advance(after)` accepts any validated snapshot, with no mutable
session or caller-supplied invalidation hint. It:

1. Compares complete canonical source objects, preserving exact number tokens.
   Object-key ordering alone causes no invalidation.
2. Invalidates the old dependents of edited/removed sources, including shadowed
   assignments and ambiguous scans. A source change invalidates the whole scan
   resolution; provenance requires more than comparing winning values.
3. Searches baseline ancestor/suffix scan buckets for **added** sources and
   applies the complete selector predicate. An added override has no old edge;
   normalized decimal entities and all filename restrictions still apply.
4. Invalidates scan additions/removals independently, so combined inventory and
   metadata edits are evaluated as one final transition.
5. Resolves only affected scans present after the change, reuses all other
   immutable results/errors, constructs the complete sorted-union impact report
   and rebuilds the next graph's reverse edges. It never mutates the old graph.

`IncrementalImpact::report()`, `next()`, `invalidated_paths()`, `reused_count()`,
`resolved_count()` and `to_json()` expose results and work evidence. Invalidated
means potentially affected; a value can remain unchanged after revalidation.
Removed scans are invalidated but incur no after-side resolution.
`reused_count + resolved_count` equals the after snapshot's scan count. Cached
errors remain `unresolved`, with all diagnostics; reuse never turns them into
successful unchanged scans.

`verify_full()` recomputes full comparison and checks the **entire deterministic
report byte for byte**, including unchanged/error entries, histories, source
chains, null/absence and numeric spelling. Mismatch raises `incremental_mismatch`.
This check is optional and intentionally costs a full comparison; counts alone
are not an equivalence proof. `to_json()` does not imply this check was run.

## Three usable scenarios

- A curator repeatedly edits one subject/session override. Build once from the
  published baseline, advance after each complete planned edit, review the full
  impact/release check, and retain `next()` for the following proposal. Other
  scans reuse cached metadata and histories.
- A data-tool author adds a previously absent sidecar or scan. Advancing the
  graph discovers new applicable edges, revalidates those targets and preserves
  unrelated scans. An empty source can still change provenance. Newly introduced
  ambiguity remains a diagnostic; removing the source recovers on the next step.
- A release reviewer verifies a candidate offline. Run the CLI with `--verify`,
  inspect exact invalidation counts and full evidence, then create/replay the
  existing review bundle from the same before/after snapshots. Merge
  reconciliation continues to validate all four snapshots before candidate
  export; incremental comparison is a reusable additional analysis path.

## Offline CLI demonstration

```sh
moon run cmd/main -- diff-incremental examples/ds000001/manifest.json examples/ds000001/provenance-manifest.json --verify
moon run cmd/main -- diff-incremental examples/ds000001/manifest.json examples/ds000001/changed-manifest.json --verify
moon run scripts/verify-incremental.mbtx
```

The first attributed real-path example adds the existing synthetic run01 source:
one scan resolves again, two are reused, and `full_verified:true`. The second
changes root RT: all three scans resolve again. Both outputs retain complete
before/after evidence under `incremental.impact`; work statistics are under
`incremental.analysis`. Omit `--verify` for analysis without the full oracle;
the flag then explicitly reads `false`. Errors in either snapshot exit1 with
complete indeterminate impact. Invalid input/options produce empty stdout.

The CLI creates a graph for each invocation; in-memory cache reuse across many
updates is a library feature. There is no persisted cache loader, filesystem
watcher, partial dataset input, incremental JSON text parser or disk writeback.
Sources are parsed/validated when constructing each immutable snapshot; cached
work here is inheritance resolution and provenance assembly.

## Costs, limits and portability

Core APIs execute on Wasm, Wasm-GC, JS and Native. CLI IO remains Wasm/Moonrun.
All existing path, metadata, snapshot and error semantics apply. Graphs add an
explicit limit of 1,048,576 dependency edges: overflow raises
`dependency_graph_limit` without returning a partial graph/update. Full comparison
remains available. Errors/rejected construction leave earlier graphs usable.

Graph construction and stored audit evidence cost time/memory. Each update still
compares source content, traverses scan inventory and rebuilds reverse edges;
it does not promise work proportional only to changed scans. Full report
serialization still includes every entry. A root edit can invalidate everything;
first-use cost can outweigh saved work. See [measured costs and raw data](incremental-performance.md).

## Boundary and sources

On 2026-10-27 bounded Mooncakes/GitHub searches used `MoonBit BIDS metadata merge
dependency graph` and `MoonBit BIDS metadata reconciliation`. Related generic
[bobzhang/incr](https://mooncakes.io/docs/bobzhang/incr%400.1.0) offers thunk-based
incremental computation; [MoonDepSolve](https://mooncakes.io/docs/python123/moondepsolve)
operates on package dependency resolution. This layer owns BIDS selector
dependencies, immutable metadata errors/provenance and full comparison agreement.
It neither ports those engines nor exposes a generic computation/dependency
solver. Search coverage is limited and does not establish uniqueness. Code,
synthetic benchmark workloads and tests are authored Apache-2.0; real fixtures
retain their existing CC0/PDDL attribution. No external test suite was copied.
