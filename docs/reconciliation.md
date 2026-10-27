# Explicit merge reconciliation

Maintainers can resolve blocked three-way merges with content-bound decisions,
revalidate every scan's inheritance, export the candidate and exchange a
self-contained replayable merge review. Core targets: Wasm, Wasm-GC, JS, Native.
The CLI uses Wasm/Moonrun and the existing bounded raw MRI profile.

## API and contract

1. `base.merge(left, right)` detects structural and inherited conflicts.
2. `merge.resolution_template()` returns complete `base`, `left`, `right`
   manifests and empty `sources`, `scans`, `effective` arrays. Edit this document.
3. `MergeResolution::from_json(text)` validates the decisions.
   `merge.reconcile(resolution)` checks the three exact snapshot bindings,
   constructs one final snapshot and checks the sorted scan union in all four
   snapshots. `to_json()` canonicalizes the plan without changing numeric tokens.
4. `ReconciledMerge::candidate()` and `impact()` return `None` while blocked.
   `conflicts()`, `conflict_count()` and `to_json()` expose the original conflicts,
   all decisions/reasons and complete revalidated evidence.
5. `reconciled.review_bundle(policy)` requires zero conflicts and returns a
   `MergeReviewBundle`. `MergeReviewBundle::from_json(text)` reruns the initial
   merge, explicit decisions, assertions, inheritance and release comparison;
   stale evidence is rejected. `to_json()`, `reconciliation()` and `report()`
   expose the verified document, reconciliation and release check.

An empty plan preserves the initial merge result. Successful reconciliation is
not release approval: the release check can still report `changes_detected`.

## Decision arrays

The outer plan requires exactly the three complete manifests and these arrays:

```json
{
  "sources": [{
    "path": "sub-01/sub-01_bold.json", "metadata": {},
    "reason": "Remove the stale local field; inherit the root correction"
  }],
  "scans": [{
    "path": "sub-01/func/sub-01_task-rest_bold.nii", "include": true,
    "reason": "Keep this scan after reviewing the other branch changes"
  }],
  "effective": [{
    "path": "sub-01/func/sub-01_task-rest_bold.nii", "key": "RepetitionTime",
    "present": true, "value": 3.0, "reason": "Reviewed this inherited outcome"
  }]
}
```

This fragment illustrates the arrays; obtain required bindings from a template.
Reasons must be nonblank and at most 4,096 UTF-16 units. Unknown/missing controls,
duplicate decoded keys/decision coordinates and invalid paths are errors.

- A source decision gives a **complete replacement object**; `metadata:null`
  removes that source, while `{}` retains an empty applied source. New sources
  are permitted. Unnamed sources follow the structural merge and remain in the
  inventory, including unmatched sources. Replacements can deliberately remove
  fields: review their complete before/after evidence.
- Scan decisions retain/add (`include:true`) or remove a path. Explicit removal
  can acknowledge `scan_delete_edit`. No image bytes or disk files are changed.
- An effective assertion authorizes only one exact scan/field outcome.
  `present:false` requires `value:null` and means absence; a present null differs.
  Arrays/objects are atomic; `2` differs from `2.0`. Incorrect assertions raise
  `resolution_value_mismatch`; missing/unresolved candidate scans reject too.
  A structural field decision can reveal conflicts across many scans: address
  each through revised sources or its own assertion. Another field's conflict
  and historical input errors remain blockers.

At most 256 source/scan decisions combined and 1,024 effective assertions are
accepted. Plans and merge bundles are limited to 16,777,216 UTF-16 units (CLI
disk limit64 MiB). Sources independently retain depth64/2,097,152-unit limits.
Canonical ordering and round trips retain every supported control/value.
Avoid JSON editors that round numbers through floating point.

Binding changes raise `stale_merge_resolution`. Partial plans retain conflicts;
invalid final inventories retain `invalid_snapshot` diagnostics. Unresolved
historical base/branch scans remain blockers even if the candidate fixes them:
repair the inputs and regenerate the plan first. This v1 policy conservatively
requires interpretable branch evidence. No force option bypasses checks.

## Offline real-path demonstration

The attributed CC0 ds000001 paths/TaskName/RT are reused; all proposed edits and
decisions are synthetic. Right introduces a stale run01 RT override. The plan
replaces its metadata with `{}`, retains its source-chain evidence and inherits
the left's proposed RT `3.0`. See [source notes](../examples/merge/SOURCE.md).

```sh
moon run cmd/main -- merge examples/ds000001/manifest.json examples/ds000001/changed-manifest.json examples/ds000001/provenance-manifest.json --resolution-template > template.json
moon run cmd/main -- reconcile examples/ds000001/manifest.json examples/ds000001/changed-manifest.json examples/ds000001/provenance-manifest.json examples/merge/resolution.json
moon run cmd/main -- reconcile examples/ds000001/manifest.json examples/ds000001/changed-manifest.json examples/ds000001/provenance-manifest.json examples/merge/resolution.json --manifest-only > reconciled.json
moon run cmd/main -- reconcile examples/ds000001/manifest.json examples/ds000001/changed-manifest.json examples/ds000001/provenance-manifest.json examples/merge/resolution.json --bundle > merge-review.json
moon run cmd/main -- replay-merge merge-review.json
moon run scripts/verify-reconciliation.mbtx
```

The result has zero revalidated conflicts and three determinate scan changes.
Replay exits0 for agreement; its release decision remains `changes_detected`.
Empty decisions retain `inheritance_shadow` and exit1. Blocked manifest/bundle
export, malformed controls, stale bindings and unsupported options produce empty
stdout and diagnostics/usage on stderr. The script verifies these and recovery
on each CI OS. `--effective-bundle` records the effective-values release policy.

Reviews verify content agreement, not identity, signatures or authenticity.
There is no generic Git merge driver, automatic conflict choice, recursive merge,
scientific numeric equivalence or filesystem writeback.

## Boundary review

Bounded searches on 2026-10-27 used `site:mooncakes.io BIDS metadata merge dependency
graph` and `site:github.com MoonBit BIDS metadata reconciliation`. Generic
[mizchi/bitx_hub conflict policies](https://assets.mooncakes.io/assets/mizchi/bitx_hub%400.48.0/store.mbt.html)
operate on records/vector clocks. This layer coordinates inherited BIDS scan
intent. No external implementation/tests were copied; no ecosystem uniqueness
is claimed. Code, policy, tests and synthetic decisions are Apache-2.0.
