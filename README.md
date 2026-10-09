# BIDS Metadata Trace

A reusable MoonBit library and offline CLI for resolving **raw MRI JSON metadata inheritance**, with a complete assignment history for every top-level field. It helps data-tool authors avoid treating a missing adjacent JSON as missing metadata and lets reviewers identify the source of a parameter.

This is a bounded implementation of the [BIDS 1.11.2 inheritance principle](https://bids-specification.readthedocs.io/en/stable/common-principles.html#the-inheritance-principle), not a full BIDS validator or imaging library. It does not inspect NIfTI voxels, convert DICOM, certify datasets, or fetch remote data.

## Run the real-data example

Requires MoonBit stable v0.10.14. The CLI runs under Moonrun on the Wasm target and needs no C compiler. The module pins `moonbitlang/async` 0.22.4 for CLI filesystem access; the library uses core only. Native core compilation/testing separately requires a system C toolchain.

```sh
moon update
moon run cmd/main --target wasm -- resolve examples/ds000001/manifest.json sub-01/func/sub-01_task-balloonanalogrisktask_run-01_bold.nii.gz
```

The included manifest contains real paths and metadata from OpenNeuro ds000001 (CC0). No image downloads or private infrastructure are needed. The report contains `RepetitionTime: 2.0`, with `task-balloonanalogrisktask_bold.json` as its source. See [source and license details](examples/ds000001/SOURCE.md).

To use your own dataset, discover a supported directory as described below, or supply **all potentially applicable JSON sidecars** within the supported scope and the data paths you want to query. Explicit manifests are caller-supplied snapshots: omitted sidecars cannot be inferred by their query APIs.

```json
{
  "files": ["sub-01/func/sub-01_task-rest_bold.nii.gz"],
  "sidecars": [
    {"path": "task-rest_bold.json", "metadata": {"RepetitionTime": 2.0}},
    {"path": "sub-01/func/sub-01_task-rest_bold.json", "metadata": {"EchoTime": 0.04}}
  ]
}
```

This second manifest is an authored illustration, not an OpenNeuro fixture. Unknown manifest control fields are errors; unknown **metadata** fields and values are preserved.

## Library workflow

Import `cn-cheems/bids_metadata_trace` as `@trace` in your `moon.pkg`. This module is not yet published to Mooncakes; use a local/path dependency or this repository when evaluating it.

- `DatasetIndex::from_manifest(files, sidecars)` consumes relative data paths and `SidecarInput::new(path, json_text)` sources.
- `DatasetIndex::from_json(text)` reads the strict manifest above.
- `index.resolve(path)` returns effective metadata or a `TraceError(Diagnostic)`.
- `resolved.get(key)` returns a defensive JSON copy. `resolved.trace(key)` gives assignments in root-to-leaf order; the last assignment wins.
- `resolved.to_json()` exports effective metadata; `to_report_json()` includes applied sidecars and field history.
- `index.to_manifest_json()` exports the complete input snapshot for reproducible reloading.
- `index.audit(paths)` retains every query occurrence in request order, including duplicates. `audit_all()` uses sorted indexed paths. `report.entries()` returns success or diagnostic per query; `error_count()` and `to_json()` support release checks.
- `before.compare(after)` reports the sorted union of scan paths, with `ImpactKind`, typed `FieldChangeKind`, full before/after evidence, per-field histories and source-chain changes. `changed_count()` excludes indeterminate scans; always also inspect `error_count()`.
- `impact.release_check(ReleasePolicy)` produces a reusable release decision, sorted affected/unresolved paths and the complete impact evidence. `AllChanges` includes provenance; `EffectiveValues` checks exact values and scan inventory. `Indeterminate` always takes priority over detected changes.
- `index.plan_edit(sidecar_path, MetadataPatch::from_json(text))` proposes an edit to one existing source, retaining complete before/after snapshots and impact evidence. `plan.updated_sidecar_json()` includes untouched metadata; `plan.after()` is a reusable candidate index.
- `ReviewBundle::create(before, after, policy)` captures complete snapshots and the complete release check. `ReviewBundle::from_json(text)` recomputes and verifies all expected evidence; `bundle.report()` exposes the verified decision.

See the compiler-generated [public interface](pkg.generated.mbti) and [executable library examples](USAGE.mbt.md).

## Exact supported boundary

- Single raw MRI dataset; `bold` in `func`, `T1w` in `anat`, `dwi` in `dwi`; `.nii` and `.nii.gz` paths plus `.json` sidecars.
- Root, participant, optional session, and corresponding datatype directories. Filename participant/session entities must agree with directory scope.
- Ordered entities: `sub`, `ses`, `task`, `acq`, `ce`, `rec`, `dir`, `run`, `echo`, `part`, `chunk`. Decimal index entities compare without leading zeroes; labels compare exactly and case-colliding labels are rejected.
- UTF-8 JSON via the CLI; well-formed Unicode strings; at most 64 nested metadata containers and 2,097,152 UTF-16 code units per parsed source. The complete canonical snapshot is also bounded to 2,097,152 code units at construction, guaranteeing it can be reloaded. Manifest envelopes allow three additional containers. The CLI also rejects manifests larger than 8 MiB on disk.
- Core library: Wasm, Wasm-GC, JavaScript and Native. CLI: Wasm under Moonrun only; CI runs on Linux, macOS and Windows. The filesystem CLI is not a generic browser/WASI embedding. These are tested targets, not claims about every host or embedding runtime.

Other suffixes/entities, derivative/auxiliary trees, non-JSON inheritance, URLs, absolute paths, parent traversal and backslash dataset paths are rejected. This profile does not validate every MRI schema constraint (including modality-specific entity combinations), required acquisition fields, image headers, or dataset-wide BIDS compliance. An empty result means no applicable sidecar was supplied; it is not a validity certificate.

## Correctness and diagnostics

Applicable sidecars must be on the data file's ancestor chain, have the same suffix, and contain only matching filename entities. JSON assignments are applied from root downwards. Objects and arrays are **whole field values**, not recursively merged; absent keys leave inherited values intact, and `null` is retained rather than treated as deletion.

Multiple applicable sidecars at the same directory level fail, even if one has more entities or both contain identical metadata. Duplicate JSON keys, including escaped aliases and nested objects, fail before resolution. Diagnostics provide a stable code, source path, message, optional UTF-16 offset and related paths.

Every numeric token is explicitly retained, including `-0`, large integers, decimal precision and overflowing exponents. Do not use the approximate `Double` stored inside core `Json::Number` or `Json::equal` to compare metadata; the library performs no numeric arithmetic. Report/manifest serializers preserve number tokens, sort object keys in ordinal UTF-16 lexicographic order, and retain array order. They normalize whitespace and string escaping, so they do not reproduce source bytes verbatim.

## Verification

```sh
moon fmt
moon fmt scripts/verify.mbtx
moon info --target all
moon check --target all --deny-warn
moon test --target all --deny-warn
```

Tests cover inheritance, source histories, ambiguity, scope errors, numeric preservation, unknown nested values, manifest round trips, input permutations, defensive copies, malformed JSON, depth boundaries and recovery after errors. The real-data command above must also run successfully. CI checks formatting and generated-interface drift, executes all four core targets, and runs the Wasm CLI on three operating systems. `moon run scripts/verify.mbtx` checks the real report as well as test exit status. On a host with a portable compiler, set `BIDS_TRACE_CC` to its absolute executable path for that script.

## Roadmap

Implemented: inheritance/provenance, recoverable batch audit, snapshot impact comparison, policy-based release checks, directory discovery with an explicit inventory report, metadata edit planning and replayable review bundles. Next: additional raw-data profiles backed by specification and fixtures, then explicit multi-source edit workflows. Planned capabilities require separate implementation. Full BIDS validation is not implemented.

## Batch review example

```sh
moon run cmd/main --target wasm -- audit examples/ds000001/manifest.json
moon run cmd/main --target wasm -- audit examples/ds000001/manifest.json absent sub-01/func/sub-01_task-balloonanalogrisktask_run-01_bold.nii.gz
```

The first command reports all three real scans. The second deliberately requests an unknown path, then a real scan: stdout contains both outcomes and `error_count: 1`; process exit is 1. A query error does not stop the batch. An invalid manifest or IO failure rejects the entire batch and writes a diagnostic to stderr. Usage errors print usage to stderr and also exit 1. An empty query list in the library yields an empty report; it never implicitly audits everything.

## Snapshot impact example

```sh
moon run cmd/main --target wasm -- diff examples/ds000001/manifest.json examples/ds000001/changed-manifest.json
```

The second manifest is a **synthetic edit**, changing the real fixture's root `RepetitionTime` from `2.0` to `3.0`. It is not another real acquisition. All three real scan paths show `value_changed`; `TaskName` stays unchanged. The command exits 0 when all comparisons are determinate, even when changes exist. Exit 1 means input/IO failure or an indeterminate scan; a completed report retains all scan outcomes on stdout.

Scan kinds are `unchanged`, `changed`, `added`, `removed`, and `unresolved`. A resolution error on either side takes priority over addition/removal and suppresses speculative field differences. Reports include both sides' diagnostics. Field kinds are `added`, `removed`, `value_changed`, and `provenance_changed`; the last means the effective value is identical but its assignment history differs. Empty sidecar edits can change `sources_changed` without field differences.

Comparison sorts object keys, preserves array order, and compares **numeric tokens exactly**: `2`, `2.0` and `2e0` are distinguishable. It is a lossless metadata edit audit, not numeric or scientific equivalence analysis. JSON report presence flags distinguish a missing field from present `null`; the library's `before_json()`/`after_json()` distinguish `None` from `Some("null")`. Unchanged entries remain in the report. Omitted sidecars, image contents and edits to nonapplicable sources are outside scan-impact inference.

## Release checks in CI

`diff` is an inspection command that succeeds for determinate changes. `check` turns the comparison into a policy decision and a failing process status, suitable for a dataset release job:

```sh
moon run cmd/main --target wasm -- check baseline.json candidate.json --effective-only
```

The default policy is `AllChanges`; omit `--effective-only` to also block provenance edits. Unsupported options fail explicitly. Both policies retain the entire impact report in the JSON `impact` field, including changes ignored by the selected policy.

| Event | Default / AllChanges | --effective-only / EffectiveValues |
| --- | --- | --- |
| Effective field added, removed or value token changed | Fail | Fail |
| Scan added or removed, even without metadata | Fail | Fail |
| Assignment history or applied source chain changed only | Fail | Pass |
| Resolution error in either snapshot | Indeterminate / fail | Indeterminate / fail |
| No relevant changes or errors | Pass | Pass |

Executable examples, requiring no private data:

```sh
moon run cmd/main --target wasm -- check examples/ds000001/manifest.json examples/ds000001/changed-manifest.json
moon run cmd/main --target wasm -- check examples/ds000001/manifest.json examples/ds000001/provenance-manifest.json --effective-only
moon run cmd/main --target wasm -- check examples/release-check/ambiguous-manifest.json examples/release-check/ambiguous-manifest.json
```

The first exits 1 with `decision: "changes_detected"` and three affected paths. The second exits 0 with `decision: "pass"`, while retaining run 01's synthetic provenance edit. Without `--effective-only` that edit fails. The third exits 1 with `decision: "indeterminate"`, unresolved paths and diagnostics from both sides; it cannot pass by comparing the same invalid snapshot to itself.

The CLI uses **0 for success/pass, 1 for failure**. Current Moonrun normalizes nonzero WASI exit codes to 1, so scripts must use JSON `decision` to distinguish changes from indeterminate comparisons. Completed checks write reports to stdout; malformed input or IO failure writes a diagnostic to stderr and produces no completed report. Usage errors write usage to stderr. A `Pass` applies only to the selected policy and supplied snapshots; omitted sources remain the caller's responsibility and it does not certify BIDS compliance. Value checks retain the exact numeric-token semantics described above.

## Discover a directory

```sh
moon run cmd/main --target wasm -- discover examples/ds000001/tree
moon run cmd/main --target wasm -- discover /path/to/dataset --manifest-only > snapshot.json
moon run cmd/main --target wasm -- audit snapshot.json
```

Default output includes a reusable `manifest`, `auxiliary_paths` and `excluded_paths`. `--manifest-only` explicitly selects just the query input; inspect the default report when reviewing completeness. `DiscoveryReport::from_inventory(paths, sidecar_texts)` exposes the same validated workflow for archive or virtual-filesystem adapters. `classify_discovery_entry(path, directory=...)` tells adapters which files need source text. Every expected sidecar must have exactly one text input; missing/extra sources and collisions fail.

Discovery reads regular JSON sidecars and records `.nii`/`.nii.gz` paths without opening image bytes. It walks regular directories, includes hidden entries in its inventory and refuses symlinks/junctions and special files. It prunes and reports hidden paths and the top-level `derivatives`, `sourcedata`, `code`, `stimuli` trees. It records auxiliary TSV/TSV.GZ/BVAL/BVEC files, events/scans/sessions/participants JSON, and the documented root README/LICENSE/CHANGES and dataset_description/participants resources. Their contents do not contribute MRI metadata and are not exported in the manifest. Other files, unsupported MRI suffixes/entities, malformed JSON and read failures reject the entire discovery. `.bidsignore` is reported as a hidden exclusion and is **not interpreted**.

Limits: 20,000 visited entries, 32 directory levels, the existing snapshot/JSON limits, and 8 MiB on disk per sidecar. Run against a quiescent directory: discovery is not an atomic filesystem transaction. `complete_supported_inventory` covers the selected raw-MRI profile and recorded exclusions, not the entire BIDS ecosystem. The included tree uses real CC0 metadata and path names; image entries are explicit text placeholders for a metadata-only demonstration. It does not claim image validity.

## Preview a sidecar edit

```sh
moon run cmd/main --target wasm -- plan examples/ds000001/manifest.json task-balloonanalogrisktask_bold.json examples/edit-plan/change-repetition-time.json
moon run cmd/main --target wasm -- plan examples/ds000001/manifest.json task-balloonanalogrisktask_bold.json examples/edit-plan/change-repetition-time.json --manifest-only > candidate.json
moon run cmd/main --target wasm -- check examples/ds000001/manifest.json candidate.json
```

The authored patch is `{"set":{"RepetitionTime":3.0},"remove":[]}`. It proposes a synthetic change to the real fixture's root source, preserves `TaskName`, and reports all three affected scans. The default plan output contains the patch, full old/new sidecar metadata, both complete manifests and the full impact report. `--manifest-only` exports the candidate snapshot for subsequent audit/check workflows. Planning never writes source files or approves an edit.

Both patch controls are required. `set` replaces whole top-level field values, including explicit `null`; `remove` deletes only explicitly named fields from the selected existing sidecar. A removed local override can expose an inherited parent value. Other fields, nested unknown values and numeric tokens are preserved. Unknown controls, repeated removal names, set/remove conflicts, absent removal fields, unknown sidecar paths and depth/size violations fail before producing a plan; the baseline remains usable. Creating/removing sidecars and recursive JSON patch operations are outside this capability.

Exit 0 means the plan has determinate scan impacts, including expected changes. An indeterminate impact produces the completed plan on stdout and exit 1; input/IO errors produce only a diagnostic on stderr. Inspect impact diagnostics before using a candidate. The exported manifest has the existing reloadable snapshot bound; complete plan reports repeat provenance evidence and can be larger.

## Share and replay an offline review

```sh
moon run cmd/main --target wasm -- bundle examples/ds000001/manifest.json examples/ds000001/changed-manifest.json > review.json
moon run cmd/main --target wasm -- replay review.json
```

The reviewer needs only the bundle and this tool. The version1 format has exactly six controls: `format: "bids-metadata-trace/review-bundle"`, integer token `version: 1`, complete `before`/`after` manifests, `policy` (`all_changes` or `effective_values`) and the complete `expected` release report. Use `bundle ... --effective-only` to select the effective-value policy; the default retains all-change policy semantics. Library accessors return the immutable snapshots and recomputed report for further queries.

Import rejects unknown controls, unsupported versions, duplicate decoded keys at any depth and mismatched expected evidence. It reloads both snapshots under the original profile, recomputes the entire report and compares canonical JSON exactly, including number tokens and policy-ignored provenance. Deleted evidence, stale inputs or changed policy with a stale report fail with a diagnostic. Coordinated inputs with a matching new report are valid: this is content replay, without signatures or proof of authorship, source authenticity or filesystem completeness.

`bundle` and `replay` exit 0 for successful capture or verified reproduction, even when the retained release decision is `changes_detected` or `indeterminate`. Use `check` for a failing release gate. Invalid input, inconsistent evidence and IO failures exit 1 with a diagnostic on stderr and no completed stdout report. Bundle input/canonical output is limited to 16,777,216 UTF-16 code units and input to 80 containers; each embedded snapshot keeps its 2,097,152-unit and metadata 64-container limits. The CLI also rejects bundle files larger than 64 MiB on disk. These are input/serialization limits, not a strict memory bound for comparison, which retains complete per-scan evidence.

## Sources and license

Project implementation and authored tests: Apache-2.0, copyright 2026 cn-cheems. External data retain their own license. [PROVENANCE.md](PROVENANCE.md) records specification, dependency, fixture and ecosystem sources. This project does not claim ecosystem uniqueness, clinical suitability or a performance advantage.
