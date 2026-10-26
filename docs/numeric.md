# Exact numeric project policy

Numeric policy operates on **effective metadata after inheritance**, retaining
the complete value, winning source and assignment history. It supports scalar
intervals, numeric arrays and scalar field relations in the existing expectation,
selection and scoped acquisition workflows. It does not convert or rewrite data.

## Three complete workflows

1. A curator checks a cohort against a project-approved TR interval. The policy
   resolves every scan, checks its effective RepetitionTime, reports a local
   override's source on failure and fails the command when violations exist.
2. An acquisition reviewer checks synthetic project timing samples for a fixed
   length, positive/bounded elements and strictly increasing numeric order, then
   checks EchoTime < RepetitionTime. Both relation operands retain their own
   inherited source histories. The example adds synthetic fields to the real
   path fixture, preserving the original TaskName and RT.
3. A pipeline selects scans whose effective parameter lies in an exact numeric
   interval. Every input occurrence is classified; bad-type/out-of-range values
   are excluded with evidence, while unresolved scans remain in the returned
   audit so later checks cannot silently approve an incomplete selection. Scoped
   acquisition rules can impose the same policy on each filename-defined cohort.

## Rule format and public API

```json
{
  "fields": {
    "RepetitionTime": {"type": "number", "gt": 0, "lt": 3},
    "EchoTime": {"type": "number", "gt": 0},
    "ProjectTimingSamples": {
      "type": "array", "gte": 0, "lt": 1,
      "min_items": 3, "max_items": 3, "strictly_increasing": true
    }
  },
  "relations": [{"left": "EchoTime", "op": "lt", "right": "RepetitionTime"}]
}
```

Both root controls are required. Declare 1–256 distinct fields and at most 256
relations. Every declared field is required. A scalar uses `type: "number"`;
an array uses `type: "array"` and must contain only JSON numbers. Strings, null,
booleans, objects and nested arrays are not coerced. An empty array passes unless
`min_items` says otherwise. Strict increase uses mathematical numeric order, so
`[1, 1.0]` fails at index 1. Array order is never changed.

Bounds are optional JSON numbers: `gt`/`gte` are exclusive/inclusive lower bounds,
`lt`/`lte` are exclusive/inclusive upper bounds. Use at most one lower and one
upper control. Empty intervals are rejected using exact numeric comparison.
Array bounds apply to each element. Only arrays accept `min_items`, `max_items`
and `strictly_increasing`. Item-count controls require plain decimal integers
from 0 through 2,097,152: `1.0`, `1e0` and `-0` are rejected for these controls.
The minimum must not exceed the maximum. `strictly_increasing` is a boolean.

Relations support `lt`, `lte`, `eq`, `gte`, `gt`. Both operands must refer to
declared scalar-number fields. Array broadcasting, arithmetic expressions and
undeclared operands are rejected. Duplicate relations, duplicate decoded JSON
keys, unknown controls, malformed JSON and invalid types fail construction.
The parser validates local intervals; it is not a solver for arbitrary sets of
cross-field constraints. Fields may still participate in several conjunctive
checks, each retaining its outcome.

```text
NumericRules::from_json(text) -> NumericRules raise TraceError
NumericRules::to_json() -> String
MetadataExpectations::with_numeric(rules) -> MetadataExpectations raise TraceError
MetadataQuery::with_numeric(rules) -> MetadataQuery raise TraceError
```

`with_numeric` returns a new configuration and replaces any previous numeric
policy. Original configurations remain immutable. Alternatively add optional
`"numeric": { ...rules... }` to the existing expectation/query JSON. Original
required/allowed or present/absent/equals controls remain mandatory. Numeric
fields cannot also be declared absent. All predicates compose with AND; exact
allowed/equals checks keep their original numeric-token-sensitive behavior.
At most 256 distinct metadata fields may be referenced across all controls.
Scoped acquisition rules accept numeric policy in their existing `expect` object.
Use existing `check_expectations`, `filter_metadata`/`select_metadata` and
`check_acquisition` methods. No new filesystem command is necessary.

## Exactness and reports

Numeric policy treats `2`, `2.0`, `2e0` as the same value and `-0` as numeric zero.
It compares retained JSON tokens without rounding through Double. The private
representation uses sign, significant digits and an arbitrary-length signed
decimal order. Exponent adjustments use decimal string addition/subtraction;
comparison pads significant digits virtually rather than creating 10^exponent.
Large integers, long fractional tails, underflowing values and overflowing
exponents therefore remain distinguishable. No machine-integer exponent limit
or fixed decimal precision is introduced. Original input/snapshot limits remain.

These mathematical comparisons are restricted to the opted-in numeric policy.
Snapshot diff/merge, canonical serialization, exact predicates, grouping and
review-bundle replay continue to distinguish original numeric tokens. The
private comparator is not a public general-purpose decimal arithmetic library.

Resolved entries gain `numeric_checks` only when numeric rules were supplied.
Each configured field and relation contributes one check and, if it fails, one
violation per query occurrence. Legacy and numeric failures both contribute to
the existing total. A field reports its **first** failure: missing/type, array
length, then element type/bounds/increase in index order. `item_index` is a
zero-based array index, otherwise null. Complete original values and source
histories are retained even when later elements are not separately diagnosed.
Relations are evaluated independently whenever both values are numbers;
otherwise they fail with `invalid_operands` and both presence/value histories.

Resolved bad types, missing fields and failed numeric checks are determinate
violations, not runtime errors. In selection they are proven nonmatches with
evidence. Resolution errors retain the existing indeterminate priority; empty
audits remain indeterminate. Duplicate queries retain their order and outcomes.
Reports and configuration serialization are deterministic; returned JSON trees
remain defensive copies. With no numeric policy, frozen pre-feature expect,
filter and acquisition stdout are checked byte-for-byte against commit ae5ba80.

## Run without private infrastructure

```sh
moon run cmd/main --target wasm -- expect examples/ds000001/manifest.json examples/numeric/expectations.json
moon run cmd/main --target wasm -- filter examples/ds000001/manifest.json examples/numeric/query.json
moon run cmd/main --target wasm -- acquisition examples/ds000001/manifest.json examples/numeric/acquisition.json
```

These succeed on all three real paths with RT `2.0`; query bounds use `2` and
`2e0`. Replacing the manifest with `examples/ds000001/changed-manifest.json`
produces three expectation/acquisition violations and exit 1, or zero selection
matches with exit 0. That manifest's RT `3.0` is an explicitly synthetic edit.

```sh
moon run cmd/main --target wasm -- plan examples/ds000001/manifest.json task-balloonanalogrisktask_bold.json examples/numeric/synthetic-patch.json --manifest-only > timing.json
moon run cmd/main --target wasm -- expect timing.json examples/numeric/array-relation.json
```

This passes all array and cross-field checks on synthetic timing metadata. Using
`invalid-patch.json` instead produces six violations: one array and one relation
per scan. The report retains `[0.02,0.02,null]`, index 1 and both source operands.
No files in the dataset are changed. See [fixture provenance](../examples/numeric/SOURCE.md).
`moon run scripts/verify-numeric.mbtx` executes all examples, legacy equivalence,
duplicate/error query retention, invalid configuration rejection and retry. It
is also invoked by the normal acceptance gate and existing three-OS CI.

## Boundary, references and license

Core targets remain Wasm, Wasm-GC, JS and Native; filesystem CLI remains
Wasm/Moonrun. There is no unit inference/conversion, numeric tolerance, formulas,
recursive object schema, automatic repair, image-header checking or full BIDS
validation. A numerical policy pass is a verdict on supplied snapshots and
explicit project rules, not scientific correctness.

The [BIDS 1.11.2 glossary](https://bids-specification.readthedocs.io/en/stable/glossary.html)
documents scalar/array numeric metadata, units and bounds; this motivates the
workflow without making every example policy normative. A bounded 2026-10-26
search used `MoonBit BIDS numeric constraints metadata Mooncakes decimal
jsonschema`. Generic projects such as
[moonschema](https://mooncakes.io/docs/moonbitstack/moonschema),
[mizchi/jsonschema](https://mooncakes.io/docs/mizchi/jsonschema) and
[moonapi constraints](https://assets.mooncakes.io/assets/moonbitstack/moonapi%400.11.1/constraint.mbt.html)
already cover general schema or web-input validation. This capability complements
them with inherited BIDS evidence and the existing selection/acquisition workflow;
it does not claim ecosystem uniqueness or general JSON Schema compatibility.
All comparator/rule/report code and tests were independently authored under
Apache-2.0. No external implementation or tests were copied.
