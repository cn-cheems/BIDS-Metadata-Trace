# Three-way metadata review

`base.merge(left, right)` proposes a merge of complete supported-profile snapshots
derived from a shared ancestor. It retains all three inputs. The caller supplies
the intended ancestor and all potentially applicable sources. No ancestry is
inferred and no files are written.

The independent value is inheritance-aware concurrent-edit review: edits to
different source files can collide in the effective metadata of the same scan.
This complements the existing edit plans, impact checks and replay bundles.

## Three practical workflows

1. Two curators edit different fields in a shared root sidecar. One corrects a
   parameter, the other adds an annotation. Merge the snapshots, inspect the
   base-to-candidate impact, then capture a `ReviewBundle`. Untouched unknown
   fields, exact numeric tokens and resulting provenance stay in the candidate.
2. Two sites add participant/session overrides independently. Disjoint scopes
   can merge; disagreeing effective assignments block the candidate. Even a new
   override equal to the old root value blocks if it would hide the other
   branch's root correction. Reconcile the override explicitly and retry.
3. One curator removes a scan or sidecar while another edits its metadata.
   Source deletion versus modification conflicts. Scan removal versus an
   effective or provenance edit also conflicts. Unmatched and empty sources
   participate in structural merging even with no indexed scans.

## Public API and contract

```text
DatasetIndex::merge(base, left, right) -> MergeReport raise TraceError
MergeReport::candidate() -> DatasetIndex?
MergeReport::conflicts() -> Array[MergeConflict]
MergeReport::conflict_count() -> Int
MergeReport::impact() -> ImpactReport?
MergeReport::to_json() -> String
```

Conflicts expose kind, path, optional field key, actionable message, exact
base/left/right/merged JSON evidence, optional failing branch and defensive
diagnostic copies. `None` is absence; `Some("null")` is a present null. Source
conflicts contain whole source objects; scan-deletion conflicts contain complete
resolution reports. Other value conflicts contain top-level field values.

Structural merging compares canonical JSON including exact numeric tokens.
Equal branch values agree; a branch unchanged from base yields to the other.
Otherwise, existing sources merge independently by top-level field. Nested
objects and arrays are atomic values. Removal is distinct from assigning null.
Empty sidecars differ from absent sidecars. Differing concurrent source
additions conflict as whole objects; deletion versus modification conflicts.
Scan inventory uses the same three-way presence rule. Every source participates,
including shadowed sources. The candidate is rebuilt through the normal
constructor, enforcing filename, case collision, depth and aggregate size rules.

Only after structural checks pass does the engine resolve the sorted union of
scan paths in base, left, right and candidate:

- Any resolution failure blocks the merge, retaining every failing branch's
  diagnostic. An unresolved base blocks even when a branch fixes it: this
  conservative policy requires a clean ancestor or separate explicit review.
- Removing a scan conflicts when the retained branch changed its values,
  assignment history or applied source chain, including an empty source.
- For retained scans each effective field must satisfy three-way intent:
  disagreeing independent changes conflict; otherwise the candidate must equal
  the agreed/changed value. This detects changes hidden by combined inheritance.
- A scan introduced in only one branch uses that branch's effective metadata
  as its expectation. An ancestor edit from the other branch which changes it
  requires review. If both introduce it, their effective fields must agree or
  compose against absent base fields.

Provenance-only edits can compose when structural and effective checks agree;
the engine does not promise to preserve both branches' exact histories. The
complete candidate impact exposes resulting history. A release policy can
still reject a successfully merged candidate.

Ordering is deterministic: sorted source paths/keys first; once clear, sorted
scan paths, branch order base/left/right/merged for resolution errors, then
sorted effective keys. Structural conflicts stop speculative semantic analysis.
Every conflict blocks the entire candidate and impact. More than 1,024 conflicts
raises `merge_conflict_limit` without a partial report. Combined constructor
failures become `invalid_snapshot` with the original diagnostic. Inputs remain
immutable after success, conflicts and raised errors.

Supported inputs/targets are the existing core raw MRI profile: Wasm, Wasm-GC,
JS and Native. There is no numeric/scientific equivalence, image-byte merge,
recursive JSON merge, automatic conflict resolution, filesystem writeback,
general Git merge driver or BIDS validity certificate. Omitted sources cannot
be inferred. Exact number spelling and array order remain significant.

## Offline end-to-end example

The base and left use the attributed CC0 ds000001 subset; left is its existing
synthetic RT edit. Right adds a synthetic annotation. These are demonstrations,
not observed scientific corrections. See [source notes](../examples/merge/SOURCE.md).

```sh
moon run cmd/main --target wasm -- merge examples/ds000001/manifest.json examples/ds000001/changed-manifest.json examples/merge/right-manifest.json
moon run cmd/main --target wasm -- merge examples/ds000001/manifest.json examples/ds000001/changed-manifest.json examples/merge/right-manifest.json --manifest-only > merged.json
moon run cmd/main --target wasm -- resolve merged.json sub-01/func/sub-01_task-balloonanalogrisktask_run-01_bold.nii.gz
moon run cmd/main --target wasm -- bundle examples/ds000001/manifest.json merged.json > review.json
moon run cmd/main --target wasm -- replay review.json
```

Merge exits 0 with `status: "merged"`, no conflicts and three scan impacts.
Resolution contains RT `3.0`, the original `TaskName` and `ReviewNote`, retaining
`-0`, `9007199254740993` and `1e999`.

This command deliberately blocks a hidden root correction:

```sh
moon run cmd/main --target wasm -- merge examples/ds000001/manifest.json examples/ds000001/changed-manifest.json examples/ds000001/provenance-manifest.json
```

It exits 1 with one `inheritance_shadow` at run 01's `RepetitionTime`: base
`2.0`, left `3.0`, right `2.0`, tentative merged `2.0`. `merged_manifest` and
`impact` are null. Conflicts normally produce a complete report on stdout.
With `--manifest-only`, blocked merges instead emit `merge_blocked` on stderr
and **empty stdout**, preventing partial snapshot use. Missing/malformed inputs,
unsupported options and excessive conflict counts also fail without a candidate.
The CLI remains Wasm/Moonrun only. `scripts/verify.mbtx --e2e-only` executes
export, resolve, bundle/replay, blocked export, unknown-option and missing-input
checks on every existing CI host.

## Boundary review

On 2026-10-26 bounded searches used `MoonBit BIDS metadata inheritance merge
snapshot Mooncakes GitHub`, and inspected [PyBIDS](https://github.com/bids-standard/pybids)
(MIT), its [workflow documentation](https://bids-standard.github.io/pybids/user_guide.html),
and the [validator inheritance model](https://bids-validator.readthedocs.io/en/latest/validation-model/inheritance-principle.html).
Generic MoonBit merge code exists, for example
[mizchi/bitx_kv](https://assets.mooncakes.io/assets/mizchi/bitx_kv%400.48.0/merge.mbt.html).
This API operates on the existing bounded BIDS snapshots and rechecks inherited
scan intent; it is not a generic version-control store or replacement for
PyBIDS/full validation. Limited searches do not establish ecosystem uniqueness.
No external implementation or test cases were copied; this merge policy,
implementation and tests are authored under Apache-2.0.
