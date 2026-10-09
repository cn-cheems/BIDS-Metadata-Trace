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

The release-check ambiguity example is an authored Apache-2.0 fixture. The effective-value and provenance policy rules are project behavior, not additional BIDS conformance rules. The two CC0 counterfactual manifests are explicitly marked in their source record.

The filesystem fixture materializes the same CC0 metadata/path subset. Image-named entries are marked text placeholders (Apache-2.0) and are not represented as images. Discovery classification/exclusion rules are the project's bounded profile, not the full BIDS inventory specification.

Edit-plan patches and tests are authored Apache-2.0 resources. The sample repetition-time assignment is explicitly synthetic; it is not a corrected scientific observation or an external acquisition. The patch contract is a project-specific whole-field operation format, not an implementation of RFC 6902 or RFC 7396.

The review-bundle format, implementation and replay tests are authored Apache-2.0 resources. They use this project's existing manifests, canonical JSON and release semantics. No external signing, archival or provenance standard is implemented; the bundle makes no authenticity claim.

Coordinated edit fixtures, tests and batch semantics are authored Apache-2.0 resources. The example combines the existing CC0 scan-path subset and synthetic override with an explicitly synthetic root assignment/local removal. It does not modify or reinterpret the original acquisition.

## Related work

Source-coverage accounting and tests are authored Apache-2.0 resources. Coverage classification is project behavior over indexed scans, not a BIDS deletion rule. Follow-up queries on 2026-10-09 included `MoonBit BIDS metadata provenance source coverage cohort CSV`; [PyBIDS's official tutorial](https://bids-standard.github.io/pybids/examples/pybids_tutorial.html) documents cross-file metadata indexing and queries. This motivates curator review workflows but does not establish MoonBit ecosystem uniqueness. No PyBIDS code or tests are copied.

Follow-up boundary review on 2026-10-09 searched `MoonBit BIDS metadata edit batch GitHub Mooncakes`. [moonbit-notary 0.1.0](https://mooncakes.io/docs/hcjbat/moonbit-notary) (Apache-2.0) documents evidence manifests, fingerprints and policy assessment (`ManifestBuilder`, `EvidenceBatch::from_manifest`, `assess_batch`); the checked public description does not cover MRI sidecar applicability or inherited-field edit planning. The contribution here is coordinated BIDS-source editing with final scan provenance, rather than a general evidence or hashing toolkit. This bounded review cannot establish absence of private/unindexed overlapping projects. No notary implementation, tests or format are reused.

The following projects were checked on 2026-10-08:

- [MoonNIfTI](https://github.com/wangjiale6036-dotcom/moonnifti), MIT: voxel access and coordinate-preserving transformations.
- [MoonDICOM](https://github.com/CCllff-jpg/MoonDICOM-MoonBit-), Apache-2.0: DICOM metadata parsing, validation and anonymization.
- [PyBIDS](https://github.com/bids-standard/pybids), MIT: mature Python BIDS querying including inherited metadata.
- [bidser](https://cran.r-project.org/web/packages/bidser/news/news.html): mature R BIDS workflow; recent releases explicitly address inherited metadata and provenance.

Our public boundary is a caller-supplied dataset snapshot -> scan path -> effective JSON plus field assignment history. It complements imaging readers and is not claimed to be globally novel. Registry keywords checked: bids, neuroimaging, nifti, sidecar, metadata, inheritance. GitHub queries included BIDS language:MoonBit and bids moonbit in:readme. This bounded search does not cover private or unindexed projects and cannot establish ecosystem uniqueness.
Field-summary implementation and its authored tests are Apache-2.0 project code. The cohort review follows existing exact-token semantics; no PyBIDS implementation or tests were copied.
CSV review implementation and independent quoted-record test reader are authored Apache-2.0 project code. CSV record conventions follow [RFC 4180](https://www.rfc-editor.org/rfc/rfc4180); the `json:` cell convention is this project's documented format. No third-party CSV implementation/tests are copied. Existing CC0 OpenNeuro fixture paths and explicitly synthetic provenance edits are reused for CLI validation.
Source inventory planning and tests are authored Apache-2.0 code. `examples/edit-plan/rename-source.json` is an authored counterfactual rename, reusing the CC0 OpenNeuro ds000001 metadata already attributed in `examples/ds000001/SOURCE.md`; it does not represent another acquisition. Search on 2026-10-09 used "MoonBit BIDS metadata validation contract sidecar inheritance" and "site:bids-standard.github.io pybids metadata querying get_metadata". [PyBIDS tutorial](https://bids-standard.github.io/pybids/examples/pybids_tutorial.html) confirms metadata-query workflows; no code/tests were copied. [MoonContract](https://github.com/Han-Wentao/mooncontract), MIT, documents OpenAPI/HTTP validation (`parse_json`, `compile`, `validate_request`, mock responses), a different boundary from BIDS inheritance/source inventory planning. Search results are bounded, not proof of absence or uniqueness.
Metadata expectation implementation, controls and tests are authored Apache-2.0 project code. `examples/expectations/acquisition.json` is an authored project policy selecting exact existing CC0 ds000001 values, not a copied normative BIDS rule or evidence of scientific validity. MoonContract's OpenAPI/HTTP routing, request/response validation and mock API remain outside this library's BIDS audit/field-provenance boundary. No validator source or tests were ported. Previously recorded bounded searches do not establish absence of private/unindexed competitors.
