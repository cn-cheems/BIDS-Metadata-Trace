# Local package and downstream verification

Publication is intentionally deferred. The module remains `cn-cheems/bids_metadata_trace@0.1.0`; no namespace, login or registry state is changed by these checks.

```sh
moon package --frozen --list
moon run scripts/package-check.mbtx
```

The script validates archive contents, extracts the actual ZIP into an isolated temporary directory and creates an independent `local/bids_trace_consumer` module using a workspace dependency on the extracted library. It never points the consumer at the working checkout. The consumer exercises public resolution, exact unknown values, atomic planning, cross-session consistency, isolated errors, baseline immutability and bundle replay. Its code is in `examples/consumer/`. The script runs Wasm, Wasm-GC, JavaScript and Native; the last requires the platform C toolchain. Windows extraction uses system `tar`; Linux/macOS use `unzip`. Existing MoonBit dependencies must be cached for offline operation.

Use `--portable-only` or `--native-only` after `--` to execute a documented subset; a subset is not evidence that omitted targets ran. Temporary cleanup checks its dedicated directory name. `.moonignore` excludes caches, automation and the separate consumer module, and preserves library/CLI sources, fixtures, licenses and source notes. The versioned archive filename is intentional: changing the release version requires updating the consumer dependency and package verification together.

This proves local package usability, not installation from Mooncakes. Formal publication, a registry-installed consumer check, a release tag and remote synchronization remain pending user instruction. The last observed Mooncakes login differs from the `cn-cheems` namespace; use an account authorized for `cn-cheems` at release time. Do not change namespaces to work around authentication.
