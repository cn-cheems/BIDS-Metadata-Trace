# Reproduce the declared workflows

The acceptance boundary is offline raw-MRI metadata review: supported paths and complete supplied JSON snapshots → effective values and provenance → reviewed candidate changes → policy checks and replay. This is not an image converter, full BIDS validator or a certificate of scientific correctness. Current implemented boundaries are in README; publication is deferred by the owner.

From a clean checkout, install the pinned CI toolchain (0.10.17+d971670cd), run `moon update`, then:

```sh
moon run scripts/acceptance.mbtx
```

This performs non-mutating format checks, generated-interface drift checks, strict all-target compilation, explicit build and actual test execution for all four core targets, real-data CLI workflows, and archive-based downstream execution. Native requires a C compiler (Windows: MSVC C++ tools/Windows SDK). ZIP extraction requires Windows system `tar` or Linux/macOS `unzip`. Dependency installation needs network access initially; fixtures need no network or private infrastructure afterwards.

Success writes `_build/acceptance.json` containing the Git revision, actual selected targets, toolchain and publication status. Every attempt removes an old report first; failure cannot leave a stale success at that path. CI uploads the report. `--portable-only` and `--native-only` select explicitly recorded subsets. `--working-tree` allows a development check with pending changes and marks it as such; it is not evidence of a clean committed release. These options follow `--`.

`moon run scripts/check-acceptance-guards.mbtx` verifies unknown, duplicate and conflicting options reject with useful diagnostics and remove stale success evidence. It intentionally replaces/removes `_build/acceptance.json`; run it before the full gate, as CI does. Format/interface checks cover the generated public API and all shipped automation.

The [three-way merge workflow](merge.md) is also exercised by the gate: independent
edits on the attributed real paths merge, export, resolve and replay, while
inherited shadowing blocks the entire candidate. The archive consumer invokes
the merge API as a downstream module.

The [numeric policy workflow](numeric.md) runs through `scripts/verify-numeric.mbtx`:
real-path interval checks, numeric filtering, scoped acquisition, synthetic array/
relation checks, actionable rejection/retry and frozen full legacy reports.
The archive consumer exercises both numeric composition methods.

## Three complete demonstrations

| User/workflow | Reproduction | Expected evidence |
| --- | --- | --- |
| Tool author needs a parameter with no adjacent JSON | `moon run cmd/main -- resolve examples/ds000001/manifest.json sub-01/func/sub-01_task-balloonanalogrisktask_run-01_bold.nii.gz` | RT token `2.0`, original TaskName and root source history; exit 0 |
| Curator proposes a session-specific override | Export `plan-changes examples/ds006/manifest.json examples/ds006/post-session-changes.json --manifest-only` into a new manifest; run `check BEFORE AFTER --effective-only`, then `consistency AFTER examples/ds006/consistency.json` | Exactly one subject-01/post-session scan changes, one RT group-field violation; both gates deliberately exit 1 |
| Reviewer independently verifies a release decision | `moon run cmd/main -- bundle BEFORE AFTER --effective-only > review.json`, then `moon run cmd/main -- replay review.json` | Complete snapshots and exact evidence reproduce `changes_detected`; replay exits 0 for successful reproduction, without approving the release |

`scripts/verify.mbtx` automates all three and additional failure/recovery workflows, checks both reports and exit codes, and safely cleans its dedicated temporary directories. The second workflow's override is synthetic; ds006's original paths/task metadata are attributed under PDDL 1.0. ds000001 metadata is CC0. Imaging bytes are neither required nor inspected. The 1,000-scan synthetic test proves deterministic behavior at that size; there is no performance advantage claim.

## Delivery state and remaining external actions

- Implemented and tested: inheritance, provenance, lossless numeric-token handling, audit recovery, discovery, selection, summaries/CSV, expectation/acquisition gates, scan/source/edit/combined planning, proven redundant override removal, grouped consistency and offline review bundles.
- Packaged locally: `cn-cheems/bids_metadata_trace@0.1.0`, with an independent downstream consumer. See [packaging](packaging.md).
- Deferred: Mooncakes publication, registry-installed consumer validation, Git/release tag and remote push. No acceptance script publishes or pushes anything. Authentication must permit the retained `cn-cheems` namespace.
- Separate submission checks: reconcile final functionality against the actual submitted proposal and the rules of the specific contest; mirror to another host only if those rules require it. This document does not assert organizer approval or that every submission condition has been satisfied.

Additional modalities, larger snapshot limits and schema-level BIDS validation remain future work. They are not required to demonstrate the declared profile, and are not represented as completed features.
## Explicit conflict decisions

`moon run scripts/verify-reconciliation.mbtx` demonstrates blocked merge ->
content-bound decisions -> full revalidation -> manifest export -> merge review
replay. The unified gate runs it automatically. See [the complete example](reconciliation.md).
