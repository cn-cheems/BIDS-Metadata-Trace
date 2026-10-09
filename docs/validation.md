# Validation evidence

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
