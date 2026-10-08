# BIDS Metadata Trace

A reusable MoonBit library and offline CLI for resolving **raw MRI JSON metadata inheritance**, with a complete assignment history for every top-level field. It helps data-tool authors avoid treating a missing adjacent JSON as missing metadata and lets reviewers identify the source of a parameter.

This is a bounded implementation of the [BIDS 1.11.2 inheritance principle](https://bids-specification.readthedocs.io/en/stable/common-principles.html#the-inheritance-principle), not a full BIDS validator or imaging library. It does not inspect NIfTI voxels, convert DICOM, certify datasets, or fetch remote data.

## Run the real-data example

Requires MoonBit stable v0.10.14. The CLI runs under Moonrun on the Wasm target and needs no C compiler. The module pins `moonbitlang/async` 0.22.4 for CLI filesystem access; the library uses core only. Native core compilation/testing separately requires a system C toolchain.

```sh
moon run cmd/main --target wasm -- resolve examples/ds000001/manifest.json sub-01/func/sub-01_task-balloonanalogrisktask_run-01_bold.nii.gz
```

The included manifest contains real paths and metadata from OpenNeuro ds000001 (CC0). No image downloads or private infrastructure are needed. The report contains `RepetitionTime: 2.0`, with `task-balloonanalogrisktask_bold.json` as its source. See [source and license details](examples/ds000001/SOURCE.md).

To use your own dataset, supply **all potentially applicable JSON sidecars** within the supported scope and the data paths you want to query. The CLI accepts any manifest in the format below; it never substitutes demo data. A manifest is a caller-supplied snapshot: omitted sidecars cannot be discovered or reported by this tool.

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

See the compiler-generated [public interface](pkg.generated.mbti) and [executable library examples](USAGE.mbt.md).

## Exact supported boundary

- Single raw MRI dataset; `bold` in `func`, `T1w` in `anat`, `dwi` in `dwi`; `.nii` and `.nii.gz` paths plus `.json` sidecars.
- Root, participant, optional session, and corresponding datatype directories. Filename participant/session entities must agree with directory scope.
- Ordered entities: `sub`, `ses`, `task`, `acq`, `ce`, `rec`, `dir`, `run`, `echo`, `part`, `chunk`. Decimal index entities compare without leading zeroes; labels compare exactly and case-colliding labels are rejected.
- UTF-8 JSON via the CLI; well-formed Unicode strings; at most 64 nested containers and 2,097,152 UTF-16 code units per parsed source. The CLI also rejects manifests larger than 8 MiB on disk.
- Core library: Wasm, Wasm-GC, JavaScript and Native. CLI: Wasm under Moonrun only; CI runs on Linux, macOS and Windows. The filesystem CLI is not a generic browser/WASI embedding. These are tested targets, not claims about every host or embedding runtime.

Other suffixes/entities, derivative/auxiliary trees, non-JSON inheritance, URLs, absolute paths, parent traversal and backslash dataset paths are rejected. This profile does not validate every MRI schema constraint (including modality-specific entity combinations), required acquisition fields, image headers, or dataset-wide BIDS compliance. An empty result means no applicable sidecar was supplied; it is not a validity certificate.

## Correctness and diagnostics

Applicable sidecars must be on the data file's ancestor chain, have the same suffix, and contain only matching filename entities. JSON assignments are applied from root downwards. Objects and arrays are **whole field values**, not recursively merged; absent keys leave inherited values intact, and `null` is retained rather than treated as deletion.

Multiple applicable sidecars at the same directory level fail, even if one has more entities or both contain identical metadata. Duplicate JSON keys, including escaped aliases and nested objects, fail before resolution. Diagnostics provide a stable code, source path, message, optional UTF-16 offset and related paths.

Every numeric token is explicitly retained, including `-0`, large integers, decimal precision and overflowing exponents. Do not use the approximate `Double` stored inside core `Json::Number` or `Json::equal` to compare metadata; the library performs no numeric arithmetic. Report/manifest serializers preserve number tokens, sort object keys in ordinal UTF-16 lexicographic order, and retain array order. They normalize whitespace and string escaping, so they do not reproduce source bytes verbatim.

## Verification

```sh
moon fmt
moon info --target all
moon check --target all --deny-warn
moon test --target all --deny-warn
```

Tests cover inheritance, source histories, ambiguity, scope errors, numeric preservation, unknown nested values, manifest round trips, input permutations, defensive copies, malformed JSON, depth boundaries and recovery after errors. The real-data command above must also run successfully. CI checks formatting and generated-interface drift, executes all four core targets, and runs the Wasm CLI on three operating systems. `moon run scripts/verify.mbtx` checks the real report as well as test exit status. On a host with a portable compiler, set `BIDS_TRACE_CC` to its absolute executable path for that script.

## Roadmap

Next: recoverable batch audit of query results, then comparison of two snapshots to identify changed effective values and provenance. Broader data profiles will require explicit specification and test coverage. Filesystem discovery and full BIDS validation are not implemented.

## Sources and license

Project implementation and authored tests: Apache-2.0, copyright 2026 cn-cheems. External data retain their own license. [PROVENANCE.md](PROVENANCE.md) records specification, dependency, fixture and ecosystem sources. This project does not claim ecosystem uniqueness, clinical suitability or a performance advantage.
