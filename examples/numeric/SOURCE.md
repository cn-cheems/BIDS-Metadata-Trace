# Numeric workflow sources

The workflows read the existing [OpenNeuro ds000001 CC0 subset](../ds000001/SOURCE.md).
Original scan paths, TaskName and RepetitionTime 2.0 are reused unchanged.
The interval/query/acquisition policies are authored Apache-2.0 project rules,
not a normative BIDS schema or a claim of scientific suitability.

`synthetic-patch.json` and `invalid-patch.json` add explicitly synthetic EchoTime
and project-specific timing samples. These are not observed acquisitions or
real corrections. The latter intentionally includes duplicate samples and null.

`legacy-expect.json`, `legacy-filter.json` and `legacy-acquisition.json` are full
stdout captured by executing this repository's Apache-2.0 implementation at
commit `ae5ba8062e4773d0708d508c65ff33f6cd6cc072` with, respectively:

- `expect examples/ds000001/manifest.json examples/expectations/acquisition.json`
- `filter examples/ds000001/manifest.json examples/selection/metadata-query.json`
- `acquisition examples/ds000001/manifest.json examples/expectations/scoped-acquisition.json`

They contain the same attributed CC0 metadata and project-authored report
structure. Before recording them, current output was checked byte-for-byte
against that independently built commit. The verification script compares them
unchanged; it does not regenerate expected output from the new implementation.
No third-party implementation, decimal algorithm code or test suite was copied.
