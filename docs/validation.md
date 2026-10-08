# Validation evidence

Local host: Windows x86_64, 2026-10-08. Toolchain: moon 0.1.20260920; moonc v0.10.14+7d59c7ec9.

The first slice's 22 tests were executed on Wasm, Wasm-GC, JS and Native, including the executable documentation test. The native test executable ran; this is not merely `moon check --target native`. `scripts/verify.mbtx` checks the real-data CLI's returned path, repetition time and provenance source.

For local Native tests, a removable [LLVM-MinGW 20261006 UCRT x86_64](https://github.com/mstorsjo/llvm-mingw/releases/tag/20261006) toolchain was used outside the repository. Archive SHA256: `317492c456aa27ee607a5919f1d2d38dcdc1112516a24d0bf4b00d078f52d17a`, matching the publisher's digest. The dedicated compiler's `clang.cfg` enables `_CRT_RAND_S`, the MinGW header opt-in needed by MoonBit's Windows runtime `rand_s` declaration. No MoonBit runtime/dependency source was patched. These compiler files are not redistributed.

The file CLI runs on Wasm under Moonrun. The initial Native IO experiment failed because async's Windows native stubs require MSVC; it is not counted as a successful native CLI run. The core Native tests and Wasm CLI are separate evidence.

CI is configured to run on Linux, macOS and Windows. A configuration alone is not proof of successful execution: consult the [actual Actions runs](https://github.com/cn-cheems/BIDS-Metadata-Trace/actions). This document does not claim a remote run has passed before its completion.
