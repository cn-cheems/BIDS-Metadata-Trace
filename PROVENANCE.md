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

Scoped acquisition-rule composition, coverage semantics, operation format and tests are authored Apache-2.0 code. The example `examples/expectations/scoped-acquisition.json` is an authored project policy over the already attributed CC0 scan inventory, not a copied BIDS rule or scientific certification. It combines filename scopes, conjunctive overlapping requirements and mandatory scan/rule coverage within this project's metadata review workflow; no external rule engine, implementation or tests were copied. The bounded ecosystem searches recorded below do not establish uniqueness.

Scan inventory planning, operation format and tests are authored Apache-2.0 project code. `examples/edit-plan/scan-inventory.json` proposes excluding a path from the already attributed CC0 fixture; it is synthetic, does not delete image bytes and does not represent an observed release. This complements existing inheritance/coverage review with explicit indexed-scan additions/removals, rather than duplicating generic image reading or a full dataset manager. No external implementation or test cases were reused.

Metadata predicate selection and tests are independently authored Apache-2.0 code. The query in `examples/selection/metadata-query.json` is an authored rule over the previously attributed CC0 fixture, not a normative BIDS requirement. Follow-up search on 2026-10-18 used `MoonBit BIDS metadata selection conditional acquisition rules Mooncakes`; the bounded results do not establish ecosystem uniqueness. [PyBIDS's official tutorial](https://bids-standard.github.io/pybids/examples/pybids_tutorial.html) documents filtering by inherited metadata, confirming the underlying workflow. This implementation adds exact-token predicates with explicit unresolved-query retention to the existing BIDS review boundary; no PyBIDS code or tests were copied.

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
Scan selection and authored tests are Apache-2.0 project code. `examples/selection/later-runs.json` is an authored query over the existing CC0 ds000001 path inventory, attributed in `examples/ds000001/SOURCE.md`. On 2026-10-09 the queries "MoonBit BIDS scan query entity cohort library" and "site:bids-standard.github.io/pybids querying get subject run suffix" checked the bounded query layer. [PyBIDS tutorial](https://bids-standard.github.io/pybids/examples/pybids_tutorial.html) documents `BIDSLayout.get(subject=..., suffix=...)` and broader regex/metadata queries, supporting the workflow need. Our query deliberately covers validated filename entities in the current profile and feeds a source-preserving audit; no PyBIDS source or tests are copied, and no uniqueness or performance claim follows from the search. Generic product/entity query search results do not establish BIDS inheritance behavior; private/unindexed competitors remain uncertain.
# 2026-10-18 workflow extensions

## 2026-10-25 multi-session validation

`scripts/package-check.mbtx`, `examples/consumer/` and packaging documentation are independently authored under Apache-2.0. The consumer's subject/session paths and vendor numeric value are synthetic test inputs; no upstream consumer code or fixtures were copied. Packaging behavior was checked with `moon package --help`, `moon package --list` and the official module documentation at https://docs.moonbitlang.com/en/stable/toolchain/moon/module.html; no registry publication is performed by the verification script.

The acceptance orchestrator, its stale-evidence/invalid-control regression script, CI integration and delivery guide are independently authored Apache-2.0 work. They reuse this repository's original fixtures and source notes without copying third-party implementation. Reports record actual target subsets and local Git revision; they do not assert contest approval, package publication or remote execution.

`examples/ds006/` transcribes a pinned four-path/two-field subset from the official bids-examples ds006 fixture. Its upstream declaration dedicates data under PDDL 1.0, with OpenfMRI/NSF acknowledgement requested; see `examples/ds006/SOURCE.md` for authors, fixed links, scope and license. It is separate from the CC0 ds000001 fixture. Session-change controls, workflow checks and the 1,000-scan scale regression are independently authored Apache-2.0 code; generated scale paths are synthetic, not observed participant records. No imaging or participant tables are copied.

Atomic dataset planning, proof-based override pruning and cohort consistency code/tests are independently authored under this repository's Apache-2.0 license. No upstream implementation or test code was copied. Combined-change examples modify the existing attributed ds000001 fixture synthetically; they are not original acquisition records. Related workflow reference: https://bids-standard.github.io/pybids/layout/index.html (PyBIDS, MIT); reference only, not a port. A bounded search for “MoonBit BIDS metadata atomic changes redundant sidecar consistency cohort Mooncakes” did not establish comparable MoonBit coverage; this is not evidence of ecosystem uniqueness.
