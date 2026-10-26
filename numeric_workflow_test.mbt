///|
test "numeric policy composes with legacy token equality and keeps input immutable" {
  let index = number_index("{\"x\":2.0}")
  let base = @trace.MetadataExpectations::from_json(
    "{\"required\":[\"x\"],\"allowed\":{\"x\":[2]}}",
  )
  let before = base.to_json()
  let combined = base.with_numeric(
    number_rules(
      "{\"fields\":{\"x\":{\"type\":\"number\",\"gte\":2,\"lte\":2}},\"relations\":[]}",
    ),
  )
  let report = index.audit_all().check_expectations(combined)
  assert_eq(report.violation_count(), 1)
  assert_true(report.to_json().contains("unexpected_value"))
  assert_true(report.to_json().contains("\"numeric_checks\":[{\"evidence\":"))
  assert_eq(base.to_json(), before)
  assert_eq(
    @trace.MetadataExpectations::from_json(combined.to_json()).to_json(),
    combined.to_json(),
  )
  let copy = report.to_json_value()
  if copy is Object(fields) {
    fields.clear()
  }
  assert_false(report.to_json().is_empty())
}

///|
test "numeric filtering retains failed query occurrences and rejects absent contradictions" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let index = number_index("{\"x\":2.0}")
  let rules = number_rules(
    "{\"fields\":{\"x\":{\"type\":\"number\",\"gt\":1,\"lt\":3}},\"relations\":[]}",
  )
  let original = @trace.MetadataQuery::from_json(
    "{\"present\":[],\"absent\":[],\"equals\":{}}",
  )
  let query = original.with_numeric(rules)
  let selected = index.audit([p, "missing", p]).filter_metadata(query)
  assert_eq(selected.paths(), [p, p])
  assert_eq(selected.error_count(), 1)
  assert_eq(selected.audit().entries().length(), 3)
  assert_eq(selected.audit().entries()[1].path(), "missing")
  assert_eq(
    @trace.MetadataQuery::from_json(query.to_json()).to_json(),
    query.to_json(),
  )
  assert_eq(original.to_json(), "{\"absent\":[],\"equals\":{},\"present\":[]}")
  let policy = number_policy(rules)
  let report = selected.audit().check_expectations(policy)
  assert_true(report.decision() == @trace.ExpectationDecision::Indeterminate)
  assert_true(
    index.audit([]).check_expectations(policy).decision() ==
    @trace.ExpectationDecision::Indeterminate,
  )
  let absent = @trace.MetadataQuery::from_json(
    "{\"present\":[],\"absent\":[\"x\"],\"equals\":{}}",
  )
  try absent.with_numeric(rules) catch {
    @trace.TraceError(d) => assert_eq(d.code, "conflicting_metadata_predicate")
  } noraise {
    _ => fail("Expected contradictory predicate rejection")
  }
  assert_eq(index.select_metadata(query).paths(), [p])
}

///|
test "numeric filtering accounts for invalid values rather than hiding unresolved metadata" {
  let query = @trace.MetadataQuery::from_json(
    "{\"present\":[],\"absent\":[],\"equals\":{},\"numeric\":{\"fields\":{\"x\":{\"type\":\"number\",\"gt\":0}},\"relations\":[]}}",
  )
  for value in ["null", "\"2\"", "[]", "0", "-1e999"] {
    let selected = number_index("{\"x\":" + value + "}").select_metadata(query)
    assert_eq(selected.paths(), [])
    assert_eq(selected.error_count(), 0)
    assert_true(selected.to_json().contains("\"excluded_count\":1"))
    assert_true(selected.to_json().contains("\"actual\":" + value))
  }
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let ambiguous = @trace.DatasetIndex::from_manifest([p], [
    @trace.SidecarInput::new("bold.json", "{}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
  ])
  let selected = ambiguous.select_metadata(query)
  assert_eq(selected.paths(), [])
  assert_eq(selected.error_count(), 1)
  assert_eq(selected.audit().entries().length(), 1)
}

///|
test "scoped acquisition composes overlapping numeric and exact requirements" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let rules = @trace.AcquisitionRules::from_json(
    "{\"rules\":[{\"id\":\"numeric\",\"select\":{\"suffixes\":[\"bold\"],\"entities\":{}},\"expect\":{\"required\":[],\"allowed\":{},\"numeric\":{\"fields\":{\"x\":{\"type\":\"number\",\"gt\":0,\"lte\":2e0}},\"relations\":[]}}},{\"id\":\"exact\",\"select\":{\"suffixes\":[\"bold\"],\"entities\":{}},\"expect\":{\"required\":[\"x\"],\"allowed\":{\"x\":[2.0]}}}]}",
  )
  let index = number_index("{\"x\":2.0}")
  assert_true(
    index.check_acquisition(rules).decision() ==
    @trace.ExpectationDecision::Pass,
  )
  let changed = number_index("{\"x\":3}").check_acquisition(rules)
  assert_true(changed.decision() == @trace.ExpectationDecision::Violations)
  assert_eq(changed.violation_count(), 2)
  assert_eq(changed.error_count(), 0)
  assert_eq(changed.uncovered_paths(), [])
  assert_eq(
    @trace.AcquisitionRules::from_json(rules.to_json()).to_json(),
    rules.to_json(),
  )
  let ambiguous = @trace.DatasetIndex::from_manifest([p], [
    @trace.SidecarInput::new("bold.json", "{}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
  ])
  assert_true(
    ambiguous.check_acquisition(rules).decision() ==
    @trace.ExpectationDecision::Indeterminate,
  )
  assert_eq(ambiguous.check_acquisition(rules).error_count(), 1)
}

///|
test "numeric nested reports are defensive and replacement policy preserves source behavior" {
  let rules = number_rules(
    "{\"fields\":{\"x\":{\"type\":\"array\",\"gt\":0}},\"relations\":[]}",
  )
  let index = number_index(
    "{\"x\":[1e999,9007199254740993],\"unselected\":{\"deep\":[null,-0]}}",
  )
  let policy = number_policy(rules)
  let report = index.audit_all().check_expectations(policy)
  let before = report.to_json()
  guard report.to_json_value() is { "entries": Array([Object(entry)]), .. } &&
    entry.get("numeric_checks") is Some(Array([Object(check)])) &&
    check.get("evidence") is Some(Object(evidence)) &&
    evidence.get("actual") is Some(Array(values)) else {
    fail("Expected nested evidence")
  }
  values.clear()
  evidence.clear()
  check.clear()
  assert_eq(report.to_json(), before)
  assert_eq(
    index.resolve("sub-01/func/sub-01_task-rest_bold.nii").to_json(),
    "{\"unselected\":{\"deep\":[null,-0]},\"x\":[1e999,9007199254740993]}",
  )
  let replacement = number_rules(
    "{\"fields\":{\"x\":{\"type\":\"number\"}},\"relations\":[]}",
  )
  assert_eq(
    index
    .audit_all()
    .check_expectations(policy.with_numeric(replacement))
    .violation_count(),
    1,
  )
  assert_eq(index.audit_all().check_expectations(policy).violation_count(), 0)
}
