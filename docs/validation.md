# Validation evidence

## Exact numeric project policy — 2026-10-26

The working-tree acceptance gate passed non-mutating source/script/consumer
format checks, generated-interface checks, strict all-target compilation,
portable builds and actual tests: Wasm 232; Wasm-GC and JavaScript 226 each.
WSL Ubuntu Native executed 226 tests separately. The 22 added tests/examples
include 82,369 exact scaled-integer comparison pairs, signed decimal carry/borrow,
10,000-digit exponent/fraction cases, 341 array combinations against an integer
oracle, open/closed intervals, huge integers, signed zero, scalar relations,
strict typing, null/absence, malformed/duplicate/unknown controls, empty ranges,
256/257 field/relation bounds, combined field budgets, size limits, nested
defensive evidence, replacement/immutability, retry and all three workflow APIs.

`scripts/verify-numeric.mbtx` passed real-path interval and scoped acquisition
checks, numeric selection with duplicate/unresolved query retention, synthetic
array/relation planning, exact full-value/source evidence on failure, unknown
rule rejection without partial stdout and recovery. Full legacy expect/filter/
acquisition stdout was captured by independently building commit ae5ba80 and
verified byte-for-byte against current output; frozen fixtures are checked on
every CI host. Numeric rules remain explicitly opted in. Existing diff, merge,
canonical output, exact predicates and replay retain numeric-token semantics.

Actual release-archive consumers passed Wasm, Wasm-GC and JavaScript with both
new numeric composition methods. The actual ZIP was also extracted using
Windows system tar and its independent consumer executed successfully as Native
under WSL Ubuntu with the pinned toolchain/GCC. This adapter does not claim the
Linux unzip path ran. Remote CI is checked after push. The public interface adds one opaque
NumericRules type, its parser/serializer and two composition methods. No new
core dependency, general JSON Schema compatibility claim or registry publication
is introduced. Standalone async 0.22.4 still emits its known duplicate c_buffer
import warning; project strict checks pass.

## Inheritance-aware three-way merge — 2026-10-26

The working-tree acceptance gate passed non-mutating package/script/consumer
format checks, generated-interface drift checks, strict all-target checking,
explicit portable builds, and actual tests: Wasm 210; Wasm-GC and JavaScript
204 each. WSL Ubuntu Native executed 204 tests separately. These are actual
executions, not Native compile-only evidence. Twenty new tests/examples cover
125 scalar three-way states and 144 root/local interactions against independent
oracles, identity/symmetry/permutation, source/field/scan additions and removals,
whole objects/arrays, null/absence, exact numeric tokens, inherited shadowing,
all failing branches, new ambiguity, all three MRI suffixes with participant/
session/run scope, maximum metadata depth, aggregate overflow, 1,024/1,025
conflict bounds, defensive results, failure recovery and snapshot/bundle replay.

The real CC0 path workflow passed merge -> manifest export -> resolve -> review
bundle -> replay; it also verifies blocked export has empty stdout, complete
conflict evidence, rejected unknown options, missing inputs and duplicate-key
input rejection. Synthetic edits are labeled in the fixture's source note.
The extracted release archive consumer passed Wasm, Wasm-GC and JavaScript,
including use of the new public merge API. The same actual ZIP was extracted
with Windows system tar and its independent consumer executed successfully as
Native under WSL Ubuntu with the pinned toolchain/GCC. This local adapter does
not claim Linux package-check's unzip path ran. Remote CI is checked after push.
The known standalone async
0.22.4 duplicate c_buffer import warning remains upstream; project strict checks
passed. No Mooncakes publication is performed.

## Portable benchmark startup — 2026-10-26

Actual Release startup exposed the documented Node `process.argv` extra executable entry. A JS-specific argument adapter now removes only that runtime prefix; native/WASI handling is unchanged. Target-specific regressions and real Release valid/invalid-input launches on Wasm, Wasm-GC and JavaScript guard this behavior. This follow-up changes no library API, resolver semantics or timed operations; the existing frozen Native paired measurements remain identified by their recorded binary digests. Strict checking, unchanged interfaces, formatting and end-to-end workflows passed; actual test execution passed on Wasm (190), Wasm-GC (184), JavaScript (184) and WSL Native (184).

## Indexed resolution — 2026-10-26

Formatting, generated interfaces (unchanged public API), strict all-target checking, end-to-end workflows and actual execution passed: Wasm 189 tests; Wasm-GC, JavaScript and WSL Native 183 each. Six index regression tests include a 48-layout byte-for-byte oracle comparison, source ordering/ambiguity, all nine entity discriminators, exact query spellings, immutable plan/reload behavior and unmatched-source invariance across the small-set threshold. The paired Native release collector executed 36 cases for each of the frozen baseline and current binaries, with seven timed samples plus warmup per case, recording whole-process peak RSS. Nine complete manifest/audit/impact output pairs were byte-identical. The raw paired report and performance document include improvements and construction/memory costs. Performance thresholds are not used as CI pass criteria. This revision's remote result is checked after push; Mooncakes publication remains deferred.

## Performance measurement foundation — 2026-10-25

The new benchmark workload/phase checks passed with 183 Wasm tests and 177 each on Wasm-GC, JavaScript and actual WSL Native execution. Strict all-target checking, generated interfaces and existing end-to-end workflows passed. Release-mode invalid arguments emit one structured diagnostic and fail without a timing-success report. Linux Native release measurements collected all 36 cases (3 scales × 3 source layouts × 4 phases), seven measured samples after one warmup, plus whole-process peak RSS and complete semantic evidence. No resolver/index implementation changed in this foundation commit. The previous standalone-script dependency warning remains documented; strict project checks pass.

Scoped acquisition rules on 2026-10-18 passed 163 Wasm tests and 157 each on Wasm-GC/JavaScript on Windows and actual Native execution under WSL/Ubuntu/GCC, using stable 0.10.15+943464bfa. Formatting, generated interfaces, strict all-target package compilation and all documented CLI checks passed. New tests cover modality/entity scopes, conjunctive overlaps, exact tokens/null, unknown and unused source preservation, mandatory scan/rule coverage, empty inventories, once-per-scan errors and error priority over violations, normalized selector/rule/snapshot round trips, defensive reports, strict/duplicate controls, id/count/text/depth boundaries and byte-identical preexisting audit serialization. Real CC0-path CLI passes two overlapping rules, detects three synthetic violations, rejects unsupported policy/IO inputs without partial stdout and reports uncovered/unmatched/ambiguous/empty cases as indeterminate. The standalone verifier bootstrap emits a duplicate `c_buffer` import warning from pinned async 0.22.4's filesystem package; this is distinct from the strict package checks, which pass. Baseline `23e4b6f` passed [CI 39054227293](https://github.com/cn-cheems/BIDS-Metadata-Trace/actions/runs/39054227293); this revision's remote execution must be verified after push.

Scan inventory planning on 2026-10-18 passed 154 Wasm tests and 148 each on Wasm-GC and JavaScript on Windows, plus actual execution of 148 Native tests under WSL/Ubuntu/GCC, using stable 0.10.15+943464bfa. Formatting, generated interfaces, strict all-target compilation and all real-data CLI workflows passed. New coverage verifies inherited added scans, removed-scan evidence, retained unmatched/empty/unknown sources, before/after coverage, unresolved additions/removals, strict controls, atomic errors/recovery, identity, deterministic operation/snapshot round trips, defensive inputs/accessors, 256/257 operations, text/depth limits, exact final snapshot size and final-only shrink/grow. The documented CC0-path counterfactual exports a two-scan candidate and the effective-value release check detects the removed scan. Baseline `64fe57d` passed [CI 39053907804](https://github.com/cn-cheems/BIDS-Metadata-Trace/actions/runs/39053907804). This revision's remote execution must be verified after push.

Inherited-metadata selection on 2026-10-18 passed 146 Wasm tests and 140 each on Wasm-GC and JavaScript on Windows using stable moon 0.1.20261012 / moonc 0.10.15+943464bfa. The official latest Windows checksum matched the isolated toolchain's `moon.exe`. All 140 Native tests actually ran under local WSL/Ubuntu with the same stable compiler and GCC; Windows local Native execution was not possible without MSVC, which this compiler now requires. CI retains MSVC setup on Windows and all three operating systems, pinned to this stable version. Formatting, generated interfaces, strict all-target compilation and all documented CLI end-to-end checks passed. The new workflow checks inherited real CC0 metadata, exact-token matching, complete excluded evidence, duplicate occurrences, recovery, malformed controls and actionable IO paths. Core tests additionally cover missing versus null, arbitrary JSON values, contradictory constraints, empty audits, retained ambiguity, deterministic query/snapshot round trips, defensive access and field/choice/text/depth limits. Stable formatting normalizes `Int`/defaulted optional labels without changing the existing generated API. Remote validation must be checked against the pushed commit.

Entity-based scan selection on 2026-10-09 passed 138 Wasm tests and 132 each on Wasm-GC, JavaScript and Native, with actual native test execution. Coverage includes AND/OR matching, suffix/session/subject scopes, normalized arbitrary-length decimal indices, exact labels, missing optional entities, ancestor and unselected-source preservation, unknown metadata and numeric tokens, downstream summary/CSV/expectation checks, selected ambiguity and recovery, empty selection without fallback/approval, malformed/unknown/duplicate/case-colliding controls, 256/257 total choices, text/depth limits, query/snapshot round trips, input permutations and defensive copies. Formatting, interface generation and strict all-target compilation passed. Real CC0-path CLI selects runs02/03, accounts for excluded run01 and audits inherited exact metadata; ambiguous selected scans retain errors with exit1, zero matches stay empty, and duplicate query/IO errors emit no partial stdout. Baseline `126fcd9` passed [CI 37904645119](https://github.com/cn-cheems/BIDS-Metadata-Trace/actions/runs/37904645119) on Linux, macOS and Windows; this revision's remote execution must be verified after push.

Metadata expectations on 2026-10-09 passed 129 Wasm tests and 123 each on Wasm-GC, JavaScript and Native, including actual native execution. Tests check inherited effective values, complete unselected metadata/history, exact numeric tokens, null/presence, optional absence, duplicate query positions, unresolved error priority, empty-scope indeterminacy, recovery, canonical rule/snapshot round trips and permutations, defensive report trees, malformed/unknown/duplicate controls and canonical choices, 256/257 field/choice limits, metadata64 and text/depth bounds. Formatting, generated interfaces and strict all-target compilation passed. Real-data CLI expectation checks pass all three scans; the synthetic edit yields three violations, unknown-then-valid query recovers, ambiguous/empty cohorts fail indeterminately, and unknown controls reject with no partial stdout. Source planning commit `8eb4dca` passed [CI 37903934526](https://github.com/cn-cheems/BIDS-Metadata-Trace/actions/runs/37903934526) on Linux, macOS and Windows. Expectation revision CI must be checked after push.

Source inventory planning on 2026-10-09 passed 121 Wasm tests and 115 each on Wasm-GC, JavaScript and Native (actual execution). Added tests cover local creation/removal exposing inheritance, exact-value source rename, complete removed/unmatched/empty source evidence, ambiguity and recovery, baseline immutability, deterministic control round trips and input permutation, review-bundle replay, defensive lists, malformed/unknown/duplicate controls, 256/257 operations, metadata64 and input/depth bounds, final snapshot overflow, case collisions and atomic shrink/grow. Formatting, interface generation and strict all-target compilation passed. Real CC0-path CLI plan-sources -> candidate export -> effective-value release check passed; missing change-file errors produced no partial stdout. CSV commit `d009c1d` passed [CI 37902380605](https://github.com/cn-cheems/BIDS-Metadata-Trace/actions/runs/37902380605) on all three operating systems.

CSV review validation on 2026-10-09 passed 113 Wasm tests and 107 each on Wasm-GC, JS and actual Native execution. An independent quoted-record test reader checks cell recovery, Unicode/quotes/commas, formula-like strings, exact large integers/negative zero/decimal tokens, unknown nested values, snapshot round trips, duplicate request order, missing/null/unresolved distinctions and complete shadowed history. Tests cover empty and 256/257-field projections, expanded evidence exceeding the 16 Mi-unit output limit and successful retry. Formatting, interface generation and strict compilation passed. Real-path Wasm CLI CSV export checks every scan, exact repetition time and missingness, retains an ambiguous row with exit1, and rejects duplicate fields with no partial stdout.

Field-summary commit `a657302` passed [CI 37901906815](https://github.com/cn-cheems/BIDS-Metadata-Trace/actions/runs/37901906815) on Linux, macOS and Windows. CSV revision remote execution must be verified after push.

Source-coverage commit `c18cd22` passed [CI 37901514542](https://github.com/cn-cheems/BIDS-Metadata-Trace/actions/runs/37901514542) on Linux, macOS and Windows.

Field-cohort summary validation on 2026-10-09 passed 109 Wasm tests and 103 each on Wasm-GC, JS and actual Native execution. Exact decimal/large integer/negative-zero tokens, nested unknown values, missing/null/unresolved distinctions, duplicate requests, full provenance, snapshot round trips, defensive trees, 256/257 field limits and recovery were checked. Formatting, interface generation, strict all-target compilation and real-data/ambiguous-cohort CLI workflows passed.

Source coverage validation on 2026-10-09 passed 105 Wasm tests and 99 each on Wasm-GC, JS and Native, including actual native execution. Tests cover partial/full shadowing, empty/unmatched sources, ambiguity, deterministic round trips, defensive copies and recovery. Formatting, generated interfaces, strict compilation and real-data CLI coverage checks passed. Baseline batch-planning commit `753e226` passed [CI 37887317168](https://github.com/cn-cheems/BIDS-Metadata-Trace/actions/runs/37887317168) on all three operating systems.

Local host: Windows x86_64, 2026-10-08. Toolchain: moon 0.1.20260920; moonc v0.10.14+7d59c7ec9.

The first slice's 22 tests were executed on Wasm, Wasm-GC, JS and Native, including the executable documentation test. The native test executable ran; this is not merely `moon check --target native`. `scripts/verify.mbtx` checks the real-data CLI's returned path, repetition time and provenance source.

For local Native tests, a removable [LLVM-MinGW 20261006 UCRT x86_64](https://github.com/mstorsjo/llvm-mingw/releases/tag/20261006) toolchain was used outside the repository. Archive SHA256: `317492c456aa27ee607a5919f1d2d38dcdc1112516a24d0bf4b00d078f52d17a`, matching the publisher's digest. The dedicated compiler's `clang.cfg` enables `_CRT_RAND_S`, the MinGW header opt-in needed by MoonBit's Windows runtime `rand_s` declaration. No MoonBit runtime/dependency source was patched. These compiler files are not redistributed.

The file CLI runs on Wasm under Moonrun. The initial Native IO experiment failed because async's Windows native stubs require MSVC; it is not counted as a successful native CLI run. The core Native tests and Wasm CLI are separate evidence.

CI is configured to run on Linux, macOS and Windows. A configuration alone is not proof of successful execution: consult the [actual Actions runs](https://github.com/cn-cheems/BIDS-Metadata-Trace/actions). This document does not claim a remote run has passed before its completion.

The batch audit slice extends the suite to 25 tests per target, executed locally on all four targets. The checked CLI workflow includes all three OpenNeuro scan paths and an unknown query followed by a successful query, verifying recovery and nonzero exit without losing the report. CI uses the script's `--e2e-only` mode after its own formatting, interface and core checks, avoiding duplicate test execution.

The initial remote run failed before compilation because fresh runners lacked a Mooncakes registry index (`module was not found in the registry`). CI now explicitly runs `moon update`; the initial failed run is not counted as platform validation.

The impact slice's 36 tests were executed locally on all four targets. Additional checks cover snapshot identity, before/after inversion, numeric-token differences, absent versus null fields, shadowed provenance, source-chain-only changes, scan additions/removals, indeterminate comparisons and defensive copies. Maximum-depth sidecars remain reloadable through the manifest envelope; oversized aggregate snapshots fail explicitly at construction. The end-to-end comparison checks that the explicitly synthetic root edit affects exactly the three real fixture paths and only `RepetitionTime`.

The batch audit commit `5ff8fc0` passed [remote CI run 37791214809](https://github.com/cn-cheems/BIDS-Metadata-Trace/actions/runs/37791214809) on Linux, macOS and Windows. The impact commit must be evaluated by its own run; prior success does not establish the latest revision's status.

The impact commit `a1cf30b` passed [remote CI run 37792513486](https://github.com/cn-cheems/BIDS-Metadata-Trace/actions/runs/37792513486) on Linux, macOS and Windows.

Release-check validation covers both policies, unchanged/empty snapshots, numeric tokens, absent/null values, empty-metadata scan inventory changes, shadowed provenance, source-chain-only edits, error priority, retained determinate changes, recovery and defensive copies. The suite contains 44 tests including executable library documentation. The end-to-end script checks seven release decisions against both JSON evidence and exact process status, plus missing-file and unsupported-option failures. Current Moonrun normalizes nonzero WASI process exits to 1; documentation and checks use JSON decisions rather than claiming distinct observable failure codes. Existing diff reports retain their original serialization; the internal JSON value helper avoids reparsing and rounding number tokens in nested reports.

Directory discovery adds seven portable core tests and six filesystem tests on the Wasm CLI: inventory/source agreement, unsupported candidates, collisions, numeric preservation, deterministic reload, recovery, actual disk IO, malformed UTF-8, directory depth, non-directory roots and symlink/junction refusal. Local execution: 57 tests on Wasm, 51 each on Wasm-GC, JS and Native. The metadata-only OpenNeuro tree is also discovered through the CLI and its exported manifest is checked. Native core tests run actual executables; CLI IO remains Wasm-only.

Directory discovery commit `670803d` passed [remote CI run 37871899628](https://github.com/cn-cheems/BIDS-Metadata-Trace/actions/runs/37871899628) on Linux, macOS and Windows.

Edit-plan validation on 2026-10-09 adds 15 core tests and an executable library example. Cases include shadowed root edits, removal exposing parent inheritance, null/absence, unknown nested metadata, exact numeric tokens, deterministic patch/snapshot round trips, defensive copies, rejected conflicting or malformed operations, recovery after failure, unchanged plans, retained ambiguity, metadata depth64 and individual/aggregate size limits. The end-to-end workflow proposes the synthetic root edit against real scan paths, checks retained TaskName and all three impacts, exports the candidate snapshot, retains indeterminate evidence with exit1 and checks the actual patch path on IO failure. Complete local execution passed: Wasm 73 tests; Wasm-GC, JS and Native 67 each. Formatting, interface generation, strict all-target compilation and all documented CLI workflow checks passed.

Edit-plan commit `b953044` passed [remote CI run 37872736054](https://github.com/cn-cheems/BIDS-Metadata-Trace/actions/runs/37872736054) on Linux, macOS and Windows.

Review-bundle validation on 2026-10-09 adds 10 core tests and one executable library example. They cover both policies, deterministic lossless round trips, complete ignored provenance/error evidence, unsupported or missing controls, duplicate/escaped keys, changed inputs/policy with stale evidence, removed/extra report fields, exact decimal/negative-zero/large-integer token mismatches, metadata64 round trips, excessive nesting, bundle/embedded-snapshot limits and recovery, and defensive accessors. Full local execution passed: Wasm 84 tests; Wasm-GC, JS and Native 78 each, including actual native test executables. Strict all-target compilation, package/script formatting and generated interfaces passed. CLI checks capture/replay the real-path synthetic edit, an effective-policy pass and an indeterminate comparison; modifying the expected decision rejects replay. Replay exit0 means faithful reproduction, not release approval. CI now also checks standalone verification-script formatting; remote execution of this revision must be checked after push.

Review-bundle commit `def1a46` passed [remote CI run 37873264886](https://github.com/cn-cheems/BIDS-Metadata-Trace/actions/runs/37873264886) on Linux, macOS and Windows.

Coordinated batch planning on 2026-10-09 adds 12 core tests and an executable typed-library example. Coverage includes coupled root/local edits, input permutation, canonical batch and snapshot round trips, review-bundle integration, null/unknown/numeric-token preservation, malformed/duplicate/conflicting controls, all-or-nothing failure and retry, single-edit equivalence, empty-batch identity, defensive copies, metadata64, 256/257-entry and exact 2,097,152/2,097,153-unit boundaries, individual/final aggregate limits, final-only shrink/grow validation and retained ambiguous plus unaffected scans. Local complete verification passed: Wasm 97 tests; Wasm-GC, JS and Native 91 each. Native executables ran. Formatting, interface generation and strict all-target compilation passed. The Wasm CLI uses real CC0 scan paths plus explicitly synthetic edits; plan-batch -> export -> resolve -> bundle -> replay passed, along with missing-file diagnostics, rejected invalid batches with no partial stdout and indeterminate empty-batch reporting. Existing single-source planning tests remain passing after extraction of its shared patch helper. This latest revision's remote status is established only by its own completed CI run.
# Atomic dataset planning — 2026-10-18

## Multi-session and cohort regression — 2026-10-25

## Local archive adoption — 2026-10-25

## Reproducible acceptance gate — 2026-10-25

The unified gate passed a portable working-tree run: non-mutating package/script/consumer format checks, unchanged generated interfaces, strict all-target checking, explicit Wasm/Wasm-GC/JavaScript builds and 181/175/175 actual tests, real-data workflows and archive-based consumers. Native core tests (175) and the archive consumer were executed separately under WSL as recorded above; a portable report does not claim Native coverage. Invalid/duplicate/conflicting option regressions verify actionable failures and stale-success removal. The CI matrix now invokes the same full gate and uploads revision-bound evidence, but no new remote CI run is claimed because the owner requested local commits with publication/push deferred. The delivery document maps three complete workflows to commands, reports and exit codes; outdated source-inventory boundaries were corrected. No API expansion or registry publication was needed.

`moon package --frozen --list` and `.moonignore` preserve domain/CLI sources, fixtures and license/source notes while excluding caches, scripts and the separate consumer module. `scripts/package-check.mbtx --portable-only` extracted the actual ZIP into a temporary workspace and executed the independent public-API consumer successfully on Wasm, Wasm-GC and JavaScript. The same archive/consumer was extracted with Windows system tar and executed as Native under WSL Ubuntu with the pinned Linux toolchain, producing `consumer: passed`; this was actual execution, not compilation alone. WSL lacks unzip and its package repository was unavailable, so the native extraction adapter used Windows tar instead of claiming the Linux `package-check --native-only` command passed. Root strict checking and interface generation passed unchanged. Publication, remote push and registry-installed consumer checks were intentionally not performed.

Pinned toolchain 0.10.15+943464bfa passed strict all-target checking and actual execution: Wasm 181 tests, Wasm-GC/JavaScript/WSL Ubuntu native 175 each. The newly attributed PDDL-1.0 ds006 subset checks four actual paths, exact task values and root provenance, followed by a synthetic subject/session override affecting exactly one scan, a failed consistency gate and verified review-bundle replay. A separate 1,000-scan synthetic regression covers audit completeness, deterministic snapshot permutations/round trips and two-run scoped impact; it establishes correctness at that size, not throughput or a memory bound. The CLI verification completed offline. Cleanup is idempotent so an already removed temporary directory cannot mask the original verification error. API generation is unchanged. No remote CI was run for these local-only commits.

Stable MoonBit 0.10.15+943464bfa: formatting, generated interfaces, strict all-target checking, Wasm 167/167 tests, Wasm-GC and JavaScript 161/161 each, and actual WSL Ubuntu native execution 161/161 passed. `scripts/verify.mbtx --e2e-only` also checks `plan-changes` against ds000001: all three scan paths and TaskName survive the synthetic RT edit. A case-sensitive subject-label migration is tested as one final snapshot; unknown controls, duplicate controls, conflicting source operations and atomic failure/recovery are covered. The external async script dependency still emits its previously documented duplicate-import warning; project strict checking passes. CI results are checked after push.

## Proven override pruning — 2026-10-18

Strict checking and execution passed on Wasm (172 tests), Wasm-GC, JavaScript and WSL Ubuntu native (166 each). Tests cover raw numeric token differences, null versus absence, whole-array changes, empty/unmatched sources, duplicate/missing removal fields, unchanged baselines, patch round trips and an unrelated scan with unresolved inheritance. The CLI end-to-end suite proves successful redundant pruning on the attributed fixture and checks unsafe removal exits 1 with no partial stdout. Generated interfaces and formatting were refreshed. No claim is made for scans outside the explicit manifest.

## Grouped consistency review — 2026-10-18

Stable-toolchain formatting, interface generation and strict all-target checking passed. Tests executed on Wasm (179), Wasm-GC (173), JavaScript (173) and actual WSL Ubuntu native (173). Coverage includes exact numeric spelling, whole-array order, absent versus null fields, absent grouping entities, normalized decimal entities, duplicate query occurrences, errors/empty scopes, deterministic output, copied constructor inputs, malformed controls, 256/257-field boundaries and config round trips. The documented ds000001 CLI workflow passes on original/provenance/uniformly changed fixtures and rejects a synthetic run-specific RT difference with exactly one group-field violation. Full original audit evidence remains in every report. This checks agreement, not scientific validity or full BIDS compliance. The preceding pruning revision's Linux/macOS/Windows CI run passed: https://github.com/cn-cheems/BIDS-Metadata-Trace/actions/runs/39055601173.
