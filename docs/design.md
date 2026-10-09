# Design boundary

## Users and three workflows

1. A scientific-data tool reads a BOLD scan's acquisition parameters even when no adjacent JSON exists. It submits a complete supported manifest, resolves the scan, and consumes fields with their winning source.
2. A curator reviews a local acquisition override. Resolving before and after the edit reveals which assignment replaced which field, while fields absent from the local source stay inherited.
3. A dataset release reviewer audits multiple scans. Same-level ambiguity and malformed or wrongly scoped sidecars must produce actionable diagnostics rather than arbitrary precedence. Correcting the source allows a fresh run without retained error state.

## First independently useful capability

The first slice is a complete manifest -> validated source snapshot -> inheritance -> field history -> deterministic report workflow. Both the public library and Wasm CLI accept arbitrary supported inputs. A real CC0 dataset subset is checked end to end. Filesystem discovery is deliberately separate: the snapshot's completeness is the caller's responsibility.

Recoverable query auditing is implemented: every requested occurrence retains a success or diagnostic, and ambiguity does not stop unaffected queries. Snapshot impact comparison is also implemented: the sorted scan union distinguishes value, history and source-chain edits, retaining errors as indeterminate rather than claiming no change. These are coherent additions, not parser fragments or commit-count milestones.

Release checks complete the release-review workflow: a curator selects whether to block effective-value/inventory changes or all provenance changes; CI receives a process failure and downstream library users receive a typed decision. Errors always take priority, while determinate changes and policy-ignored evidence remain available. Decisions do not certify source completeness or BIDS conformance.

Directory discovery completes the input workflow. An inventory classifier records explicit auxiliary/excluded resources and requires every MRI sidecar's text; the CLI supplies a bounded filesystem walk. Unsupported candidates and incomplete inventories reject the full operation. Image content is unused. Quiescent regular directories are supported; symlinks/junctions are refused and discovery is not an atomic capture.

## Safety of interpretation

Edit planning completes the curator's proposed-change workflow: strict whole-field assignments/removals target one existing sidecar, then the complete candidate snapshot is revalidated and compared against the immutable baseline. The plan retains both source values, all snapshot inputs and per-scan evidence. It neither writes files nor treats an indeterminate impact as approval. Sidecar creation/deletion and recursive patch semantics remain outside the public boundary.

The raw MRI profile is versioned by documented scope rather than a claim of complete BIDS conformance. Unknown metadata values are preserved; unsupported selectors and unknown manifest controls fail. No input source is rewritten. Same-level ambiguity is a resolution error, so an index can still be used for unaffected scans. JSON syntax and Unicode validation use MoonBit core; duplicate decoded keys and number lexeme preservation are handled by a bounded additional source walk.

## Architecture

Offline review bundles close the handoff between a curator and reviewer. Version1 embeds the complete before/after manifests, selected policy and expected full report; loading recomputes the report and rejects any evidence mismatch using canonical numeric-token-sensitive JSON. An indeterminate decision remains indeterminate. The bundle proves reproducibility of its contents, without attesting who supplied the snapshots or how they were captured. Both library and CLI work without remote services.

- Root package owns all public types and domain behavior; its private files separate source handling, selectors, manifests, resolution and reports.
- `cmd/main` is the Moonrun/Wasm filesystem adapter. The root core has no filesystem, network, clock or process dependency.
- Generated interfaces are committed and regenerated with `moon info --target all`.
- `scripts/verify.mbtx` orchestrates validation using MoonBit, not shell parsing or generated Python/JavaScript scripts.

Core targets are Wasm, Wasm-GC, JS and Native. The CLI uses Moonrun host IO on Wasm because current async Windows native IO requires MSVC; MinGW is not supported by that dependency. CI runs core tests and a checked Wasm CLI example on Linux, macOS and Windows; local evidence and remote results must be reported separately.
