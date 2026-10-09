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
- `index.source_coverage()` accounts for every sidecar within indexed scans: applicability, winning/fully-shadowed scan paths, per-scan winning/shadowed fields and unresolved evidence. Empty sources are retained; `unmatched_paths()` means no indexed target, not permission to delete a source.
- `before.compare(after)` reports the sorted union of scan paths, with `ImpactKind`, typed `FieldChangeKind`, full before/after evidence, per-field histories and source-chain changes. `changed_count()` excludes indeterminate scans; always also inspect `error_count()`.
- `impact.release_check(ReleasePolicy)` produces a reusable release decision, sorted affected/unresolved paths and the complete impact evidence. `AllChanges` includes provenance; `EffectiveValues` checks exact values and scan inventory. `Indeterminate` always takes priority over detected changes.
- `index.plan_edit(sidecar_path, MetadataPatch::from_json(text))` proposes an edit to one existing source, retaining complete before/after snapshots and impact evidence. `plan.updated_sidecar_json()` includes untouched metadata; `plan.after()` is a reusable candidate index.
- `EditBatch::from_patches([(path, patch), ...])` builds coordinated edits for MoonBit callers; `from_json(text)` reads the batch format below. `index.plan_edits(batch)` validates every edit against the same baseline and returns one `BatchEditPlan`, complete source replacements and final scan impacts.
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

Implemented: inheritance/provenance, recoverable batch audit, snapshot impact comparison, policy-based release checks, directory discovery with an explicit inventory report, single-source/coordinated multi-source edit planning, atomic source inventory planning, replayable review bundles, source coverage, exact-value cohort summaries, CSV review export and project-specific metadata expectation checks. Next: additional raw-data profiles backed by specification and fixtures. Planned capabilities require separate implementation. Full BIDS validation is not implemented.

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

## Preview coordinated sidecar edits

A curator changing a root parameter may also need to remove a stale run-specific override. Batch planning accepts all operations together and produces one final candidate:

```sh
moon run cmd/main --target wasm -- plan-batch examples/ds000001/provenance-manifest.json examples/edit-plan/coordinated-edits.json
moon run cmd/main --target wasm -- plan-batch examples/ds000001/provenance-manifest.json examples/edit-plan/coordinated-edits.json --manifest-only > candidate.json
moon run cmd/main --target wasm -- bundle examples/ds000001/provenance-manifest.json candidate.json > review.json
moon run cmd/main --target wasm -- replay review.json
```

The baseline combines real CC0 paths/metadata with the previously documented synthetic run-01 override. The authored batch sets root `RepetitionTime` to `3.0` and removes that field from run 01, leaving its empty sidecar in place. All three scans inherit the new root value; `TaskName` remains intact. This is a counterfactual review, not corrected acquisition data.

```json
{"edits":[
  {"path":"task-rest_bold.json","set":{"RepetitionTime":3.0},"remove":[]},
  {"path":"sub-01/func/sub-01_task-rest_run-01_bold.json","set":{},"remove":["RepetitionTime"]}
]}
```

Every entry requires `path`, `set` and `remove`; only `edits` is allowed at the envelope. The whole-field semantics are identical to single-source planning. Duplicate sidecar paths, duplicate decoded keys, unknown controls, invalid operations, unknown sources and absent removal fields are errors. No operation is silently skipped. All removals refer to the baseline, repeated edits to one source are rejected, and input order cannot change a valid plan. Empty batches preserve the baseline and any existing resolution errors.

The library/CLI never write source files. “All or nothing” means immutable snapshot planning, not a disk transaction. The final combined snapshot is rebuilt and bounded once, allowing a coordinated shrink/grow that would exceed the limit in an intermediate single edit. A failure returns no partial plan; an indeterminate final impact retains the complete plan with CLI exit 1. A determinate plan exits 0 even when changes exist. Default output contains the normalized batch, every edited source's old/new values, both full snapshots and one impact report. `--manifest-only` exports the final candidate for existing resolve/check/bundle workflows. `updated_sidecar_json(path)` returns `None` for sources not explicitly edited.

Limits: 256 distinct existing sidecars, 2,097,152 UTF-16 units per parsed/canonical batch, 67 batch containers accommodating metadata64, and the existing per-sidecar/final-snapshot limits. CLI batch files also have an 8 MiB disk bound. This patch API does not create/delete sidecars; use the separate source inventory planner below. Nested patch operations, sequential same-source operations and disk application remain unsupported. Complete reports may exceed snapshot size because they retain repeated evidence.

## Share and replay an offline review

```sh
moon run cmd/main --target wasm -- bundle examples/ds000001/manifest.json examples/ds000001/changed-manifest.json > review.json
moon run cmd/main --target wasm -- replay review.json
```

The reviewer needs only the bundle and this tool. The version1 format has exactly six controls: `format: "bids-metadata-trace/review-bundle"`, integer token `version: 1`, complete `before`/`after` manifests, `policy` (`all_changes` or `effective_values`) and the complete `expected` release report. Use `bundle ... --effective-only` to select the effective-value policy; the default retains all-change policy semantics. Library accessors return the immutable snapshots and recomputed report for further queries.

Import rejects unknown controls, unsupported versions, duplicate decoded keys at any depth and mismatched expected evidence. It reloads both snapshots under the original profile, recomputes the entire report and compares canonical JSON exactly, including number tokens and policy-ignored provenance. Deleted evidence, stale inputs or changed policy with a stale report fail with a diagnostic. Coordinated inputs with a matching new report are valid: this is content replay, without signatures or proof of authorship, source authenticity or filesystem completeness.

`bundle` and `replay` exit 0 for successful capture or verified reproduction, even when the retained release decision is `changes_detected` or `indeterminate`. Use `check` for a failing release gate. Invalid input, inconsistent evidence and IO failures exit 1 with a diagnostic on stderr and no completed stdout report. Bundle input/canonical output is limited to 16,777,216 UTF-16 code units and input to 80 containers; each embedded snapshot keeps its 2,097,152-unit and metadata 64-container limits. The CLI also rejects bundle files larger than 64 MiB on disk. These are input/serialization limits, not a strict memory bound for comparison, which retains complete per-scan evidence.

## Review source coverage

```sh
moon run cmd/main --target wasm -- sources examples/ds000001/provenance-manifest.json
```

The real-path fixture's synthetic run-01 source wins `RepetitionTime` for that scan. The root source still wins `TaskName` there and both fields for runs 02/03. Coverage reports each field separately, so a partially shadowed source is not mislabeled as wholly unused. Every supplied source appears, including empty sources and sources without applicable indexed scans. Source and scan ordering is deterministic. Resolution failures retain diagnostics and applicable paths, with no guessed winner or shadowed assignment; a completed report exits 1 if any scan is unresolved, otherwise 0.

This is a projection over the supplied snapshot's indexed scans. Unmatched sources may serve unindexed data; coverage neither inspects other files nor recommends automatic deletion. Empty applicable sources affect the applied chain even though they assign no fields. Correcting input and rerunning starts a fresh report. The library and command use the existing supported raw-MRI boundary.

## Summarize a scan cohort

```sh
moon run cmd/main --target wasm -- summarize examples/ds000001/provenance-manifest.json RepetitionTime TaskName MissingField
```

`AuditReport::summarize_fields(fields)` groups exact canonical whole JSON values, retains every request occurrence with its query index, winning source and complete assignment trace, and lists resolved-but-absent fields separately from failed queries. Null is a value; `2` and `2.0` are separate groups. Objects/arrays and unknown metadata are supported without numerical conversion. Field order follows the explicit request; groups are ordered by canonical token, not numeric magnitude. At most 256 distinct fields may be requested; duplicate/oversized requests fail. An empty library projection is valid. The CLI requires at least one field and exits 1 when the completed report contains resolution errors, otherwise 0. This reviews consistency; it does not validate BIDS field units or establish scientific equivalence. Existing resolution and input limits apply. JSON evidence can be consumed through the report's defensive `to_json_value()` accessor.

## Export a review table

```sh
moon run cmd/main --target wasm -- table examples/ds000001/provenance-manifest.json RepetitionTime TaskName MissingField > review.csv
```

`AuditReport::to_review_csv(fields)` exports every query occurrence in request order, including errors. Four fixed columns (`query_index`, `data_path`, `status`, `diagnostic`) precede four columns per explicit field: `present`, `value`, `winning_source`, `trace`; their headers include the JSON-encoded field name. All cells are quoted, quotes doubled, records end with CRLF, and CLI output is UTF-8 without a BOM. This is a review CSV, not a BIDS TSV or a complete snapshot replacement; only requested fields are projected.

Dynamic path/value/source/trace/diagnostic cells start with `json:` followed by exact canonical JSON. After CSV decoding, remove exactly that prefix and parse the remainder as JSON (use a token-preserving parser for exact numbers). This preserves `2.0`, `-0`, large integers, unknown nested data, commas, quotes and escaped newlines; formula-like strings remain JSON strings behind a text prefix. It does not claim all spreadsheet applications preserve text automatically. Presence `true` with `json:null` means explicit null; `false` with empty value/source/trace means absent from a resolved scan. An error row has its complete diagnostic and empty presence/value/source/trace cells, meaning unknown rather than absent. Full assignment traces retain shadowed values.

The CLI requires one or more distinct fields, audits all indexed scans, and exits 1 if any exported row is unresolved; library callers can select scans through `audit(paths)`. Empty library field selection exports the four base columns. Projection limits match cohort summaries (256 unique fields); complete CSV output is limited to 16,777,216 UTF-16 units including quoting and CRLF. Exceeding the limit fails before any completed CSV reaches stdout; reduce fields or split queries. No CSV import, disk edits or automatic spreadsheet formatting are implemented.

## Plan source inventory changes

```sh
moon run cmd/main --target wasm -- plan-sources examples/ds000001/manifest.json examples/edit-plan/rename-source.json
moon run cmd/main --target wasm -- plan-sources examples/ds000001/manifest.json examples/edit-plan/rename-source.json --manifest-only > candidate.json
moon run cmd/main --target wasm -- check examples/ds000001/manifest.json candidate.json --effective-only
```

The authored counterfactual renames the real fixture's root source to `bold.json` with the same CC0 metadata. All three scans retain their exact values, while their source histories change. No disk source is renamed: the command only exports an immutable candidate and evidence. The final effective-value check passes; the default all-change gate detects the provenance change.

`SourceChanges::new(additions, removals)` or `from_json(text)` accepts `{"add":[{"path":"bold.json","metadata":{}}],"remove":["task-rest_bold.json"]}`. Both controls are required. Unknown controls, duplicate decoded keys, malformed metadata, unsupported paths and duplicate/case-colliding operations fail. An addition must name a source absent from the baseline; removal must name an existing source. Adding and removing the same path is rejected: use metadata edits for replacement. `index.plan_sources(changes)` validates/rebuilds the final inventory once, with unchanged scan paths, then returns `before()`, `after()`, `impact()` and a complete JSON report. Removed empty/unmatched source data remain in the before snapshot even when scan impact is zero.

At most 256 combined operations and 2,097,152 UTF-16 units of canonical change input; JSON envelope depth67 accommodates metadata64. Existing source/final snapshot limits apply. The CLI rejects change files above 8 MiB on disk. Atomic shrink/grow can succeed without constructing an oversized intermediate snapshot. Empty changes are an identity. Failures return no partial plan; resolution ambiguity retains both snapshots and diagnostics, with CLI exit1. Determinate changes exit0. Source disk application and scan creation/deletion remain unsupported; source creation/removal planning is now implemented separately from existing-source patch planning.

## Check acquisition expectations

```sh
moon run cmd/main --target wasm -- expect examples/ds000001/manifest.json examples/expectations/acquisition.json
moon run cmd/main --target wasm -- expect examples/ds000001/changed-manifest.json examples/expectations/acquisition.json
```

The authored project rule requires `RepetitionTime` and `TaskName`, and permits the exact values from the existing real CC0 fixture. All three real scans pass; the synthetic repetition-time edit fails with three `unexpected_value` checks. This gate checks acquisition expectations directly, including errors already present in a baseline; a before/after comparison alone can only describe changes. The command accepts optional scan paths after the expectation file; otherwise it audits every indexed scan. Duplicate queries keep their request positions. `Pass` exits0; `Violations` and `Indeterminate` exit1 with the complete report on stdout. Bad input/IO errors emit a diagnostic on stderr without a completed report.

Load `MetadataExpectations::from_json(text)` using exactly `{"required":["RepetitionTime"],"allowed":{"RepetitionTime":[2.0]}}`. Both controls are mandatory. Required fields must be present after inheritance; explicit null counts as present. An allowed-only field may be absent; when present, its complete JSON value must match one of the exact canonical choices. Unknown metadata, arrays and objects are supported without coercion or nested merging. `2`, `2.0`, `2e0` and negative zero remain distinct. Whitespace, object key order and equivalent string escapes do not distinguish choices. Unknown controls, duplicate required fields/decoded keys/canonical choices, empty or non-array choice sets fail rather than being ignored.

`audit.check_expectations(expected)` returns a report with `decision()`, failed field `violation_count()`, unresolved query `error_count()`, deterministic `to_json()` and defensive `to_json_value()`. Every resolved query retains its complete metadata, applied sources and field assignment history, including unselected fields. Checks include presence, actual value, allowed choices, winner and full trace. Failed queries retain diagnostics without speculative checks. Errors take priority over violations. An empty audit is `Indeterminate` with `empty_audit:true` and zero query errors; select at least one scan to obtain a decision. Empty rules impose no field restrictions on a nonempty resolved audit, while still retaining errors.

Limits: 256 distinct fields across both controls, 1–256 choices per allowed field, 2,097,152 UTF-16 units per input/canonical expectation document and 67 JSON containers; CLI file size at most 8 MiB. This is an explicit project rule, not BIDS schema compliance, image/header validation, numeric tolerance, unit conversion, ranges, cross-field predicates or clinical suitability. Complete repeated evidence can expand beyond input size. Source planning, expectation checks and existing comparison/replay remain separate, composable workflows.

## Sources and license

Project implementation and authored tests: Apache-2.0, copyright 2026 cn-cheems. External data retain their own license. [PROVENANCE.md](PROVENANCE.md) records specification, dependency, fixture and ecosystem sources. This project does not claim ecosystem uniqueness, clinical suitability or a performance advantage.
