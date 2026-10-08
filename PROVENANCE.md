# Sources, reuse and differentiation

## Specification

- BIDS 1.11.2 [inheritance principle](https://bids-specification.readthedocs.io/en/stable/common-principles.html#the-inheritance-principle): behavioral reference for applicability, directory precedence and same-level ambiguity. The specification is CC BY 4.0. Implementation and authored tests are not copied from its code or prose; normative behavior is implemented independently. Attribution: BIDS contributors, https://github.com/bids-standard/bids-specification.
- RFC 8259: https://www.rfc-editor.org/rfc/rfc8259. JSON syntax is delegated to MoonBit core; an additional source walk rejects duplicate decoded keys and retains every numeric token.

## Dependencies and build tooling

- MoonBit core JSON validation and scalar string encoding, Apache-2.0: https://github.com/moonbitlang/core. No core source or tests are copied. The installed v0.10.14 interfaces and source were inspected to verify numeric representations and API behavior.
- `moonbitlang/async` 0.22.4 (Apache-2.0): https://github.com/moonbitlang/async. Used for CLI IO and MoonBit automation, not for metadata semantics.
- `hustcer/setup-moonbit` (MIT): https://github.com/hustcer/setup-moonbit. Used as an action, not vendored.
- GitHub checkout action (MIT): https://github.com/actions/checkout. Used as an action, not vendored.
- Windows MSVC environment action (MIT): https://github.com/ilammy/msvc-dev-cmd. Used as an action, not vendored.

## Fixtures and tests

OpenNeuro ds000001 metadata and path subset are CC0; exact version and source are in [examples/ds000001/SOURCE.md](examples/ds000001/SOURCE.md). All other manifests and test cases are authored for this project and distributed under Apache-2.0. Synthetic mutations are not represented as real observations. No PyBIDS, bidser, BIDS validator or competing MoonBit implementation code/tests are copied.

## Related work checked on 2026-10-08

- [MoonNIfTI](https://github.com/wangjiale6036-dotcom/moonnifti), MIT: voxel access and coordinate-preserving transformations.
- [MoonDICOM](https://github.com/CCllff-jpg/MoonDICOM-MoonBit-), Apache-2.0: DICOM metadata parsing, validation and anonymization.
- [PyBIDS](https://github.com/bids-standard/pybids), MIT: mature Python BIDS querying including inherited metadata.
- [bidser](https://cran.r-project.org/web/packages/bidser/news/news.html): mature R BIDS workflow; recent releases explicitly address inherited metadata and provenance.

Our public boundary is a caller-supplied dataset snapshot -> scan path -> effective JSON plus field assignment history. It complements imaging readers and is not claimed to be globally novel. Registry keywords checked: bids, neuroimaging, nifti, sidecar, metadata, inheritance. GitHub queries included BIDS language:MoonBit and bids moonbit in:readme. This bounded search does not cover private or unindexed projects and cannot establish ecosystem uniqueness.
