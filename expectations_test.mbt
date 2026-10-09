///|
test "expectations use inherited effective values and retain all metadata and history" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new(
      "task-rest_bold.json", "{\"x\":2.0,\"unknown\":{\"nested\":[null,true]},\"n\":null}",
    ),
    @trace.SidecarInput::new(
      "sub-01/func/sub-01_task-rest_run-01_bold.json", "{\"x\":3}",
    ),
  ])
  let expected = @trace.MetadataExpectations::from_json(
    "{\"required\":[\"x\",\"n\"],\"allowed\":{\"x\":[3],\"n\":[null],\"optional\":[true]}}",
  )
  let report = index.audit_all().check_expectations(expected)
  assert_true(report.decision() == @trace.ExpectationDecision::Pass)
  assert_eq(report.violation_count(), 0)
  assert_true(report.to_json().contains("absent_optional"))
  assert_true(report.to_json().contains("\"unknown\":{\"nested\":[null,true]}"))
  assert_true(report.to_json().contains("\"value\":2.0"))
  assert_true(report.to_json().contains("\"actual\":null"))
  let exported = report.to_json_value()
  if exported is Object(fields) {
    fields.clear()
  }
  assert_true(report.to_json().contains("\"actual\":3"))
}

///|
test "expectations distinguish exact numbers missing and null without coercion" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new(
      "task-rest_bold.json", "{\"x\":2.0,\"n\":null,\"large\":9007199254740993,\"zero\":-0}",
    ),
  ])
  let expected = @trace.MetadataExpectations::from_json(
    "{\"required\":[\"missing\"],\"allowed\":{\"x\":[2],\"n\":[false],\"large\":[9007199254740992],\"zero\":[0]}}",
  )
  let report = index.audit_all().check_expectations(expected)
  assert_true(report.decision() == @trace.ExpectationDecision::Violations)
  assert_eq(report.violation_count(), 5)
  assert_eq(report.error_count(), 0)
  assert_true(report.to_json().contains("missing_required"))
  assert_true(report.to_json().contains("\"actual\":9007199254740993"))
  assert_true(report.to_json().contains("\"actual\":-0"))
  let exact = @trace.MetadataExpectations::from_json(
    "{\"required\":[],\"allowed\":{\"x\":[2,2.0,2e0]}}",
  )
  assert_true(
    index.audit_all().check_expectations(exact).decision() ==
    @trace.ExpectationDecision::Pass,
  )
}

///|
test "expectation failures keep duplicate request order and error priority with recovery" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [])
  let expected = @trace.MetadataExpectations::from_json(
    "{\"required\":[\"x\"],\"allowed\":{}}",
  )
  let report = index
    .audit([scan(), "unknown", scan()])
    .check_expectations(expected)
  assert_eq(report.violation_count(), 2)
  assert_eq(report.error_count(), 1)
  assert_true(report.decision() == @trace.ExpectationDecision::Indeterminate)
  guard report.to_json_value()
    is {
      "entries": Array(
        [
          { "query_index": Number(0.0, ..), "status": String("resolved"), .. },
          { "query_index": Number(1.0, ..), "status": String("error"), .. },
          { "query_index": Number(2.0, ..), "status": String("resolved"), .. },
        ]
      ),
      ..
    } else {
    fail("Request order or error lost")
  }
  assert_true(
    index.audit([]).check_expectations(expected).decision() ==
    @trace.ExpectationDecision::Indeterminate,
  )
  assert_true(
    index.audit_all().check_expectations(expected).decision() ==
    @trace.ExpectationDecision::Violations,
  )
  let empty = @trace.MetadataExpectations::from_json(
    "{\"required\":[],\"allowed\":{}}",
  )
  assert_true(
    index.audit_all().check_expectations(empty).decision() ==
    @trace.ExpectationDecision::Pass,
  )
  assert_true(
    index.audit(["unknown"]).check_expectations(empty).decision() ==
    @trace.ExpectationDecision::Indeterminate,
  )
}

///|
test "expectations refuse to guess values on ambiguous inheritance" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("bold.json", "{\"x\":1}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":1}"),
  ])
  let report = index
    .audit_all()
    .check_expectations(
      @trace.MetadataExpectations::from_json(
        "{\"required\":[\"x\"],\"allowed\":{\"x\":[1]}}",
      ),
    )
  assert_true(report.decision() == @trace.ExpectationDecision::Indeterminate)
  assert_eq(report.violation_count(), 0)
  assert_true(report.to_json().contains("ambiguous_inheritance"))
  assert_false(report.to_json().contains("\"actual\""))
}

///|
fn expectations_error(text : String) -> String {
  try {
    ignore(@trace.MetadataExpectations::from_json(text))
    "accepted"
  } catch {
    @trace.TraceError(d) => d.code
  }
}

///|
test "expectations reject malformed unsupported duplicate and meaningless controls" {
  for
    text in [
      "[]", "{}", "{\"required\":[2],\"allowed\":{}}", "{\"required\":[],\"allowed\":[]}",
    ] {
    assert_eq(expectations_error(text), "invalid_expectations")
  }
  assert_eq(
    expectations_error("{\"required\":[],\"allowed\":{},\"tolerance\":0.1}"),
    "unknown_expectation_field",
  )
  assert_eq(
    expectations_error("{\"required\":[\"x\",\"x\"],\"allowed\":{}}"),
    "duplicate_field_request",
  )
  assert_eq(
    expectations_error("{\"required\":[],\"allowed\":{\"x\":[]}}"),
    "invalid_allowed_values",
  )
  assert_eq(
    expectations_error(
      "{\"required\":[],\"allowed\":{\"x\":[{\"a\":1,\"b\":2},{\"b\":2,\"a\":1}]}}",
    ),
    "duplicate_allowed_value",
  )
  assert_eq(
    expectations_error("{\"required\":[],\"allowed\":{\"x\":[2.0,2.0]}}"),
    "duplicate_allowed_value",
  )
  assert_eq(
    expectations_error(
      "{\"required\":[],\"allowed\":{\"x\":[{\"a\":1,\"\\u0061\":2}]}}",
    ),
    "duplicate_json_key",
  )
  assert_true(
    @trace.MetadataExpectations::from_json(
      "{\"required\":[],\"allowed\":{\"x\":[null]}}",
    )
    .to_json()
    .contains("null"),
  )
}

///|
test "expectations canonical round trips and permutation preserve nested exact values" {
  let first = @trace.MetadataExpectations::from_json(
    "{\"required\":[\"y\",\"x\"],\"allowed\":{\"x\":[{\"b\":-0,\"a\":[2.0,true]},null]}}",
  )
  let second = @trace.MetadataExpectations::from_json(
    "{\"allowed\":{\"x\":[null,{\"a\":[2.0,true],\"b\":-0}]},\"required\":[\"x\",\"y\"]}",
  )
  assert_eq(first.to_json(), second.to_json())
  assert_eq(
    first.to_json(),
    @trace.MetadataExpectations::from_json(first.to_json()).to_json(),
  )
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new(
      "task-rest_bold.json", "{\"x\":{\"a\":[2.0,true],\"b\":-0},\"y\":null}",
    ),
  ])
  let report = index.audit_all().check_expectations(first)
  assert_true(report.decision() == @trace.ExpectationDecision::Pass)
  assert_eq(
    report.to_json(),
    @trace.DatasetIndex::from_json(index.to_manifest_json())
    .audit_all()
    .check_expectations(second)
    .to_json(),
  )
}

///|
test "expectation field choice depth and text limits fail explicitly and recover" {
  let fields = Array::makei(256, i => "\"k" + i.to_string() + "\"")
  ignore(
    @trace.MetadataExpectations::from_json(
      "{\"required\":[" + fields.join(",") + "],\"allowed\":{}}",
    ),
  )
  assert_eq(
    expectations_error(
      "{\"required\":[" + fields.join(",") + "],\"allowed\":{\"extra\":[1]}}",
    ),
    "field_request_limit",
  )
  let choices = Array::makei(256, i => i.to_string())
  ignore(
    @trace.MetadataExpectations::from_json(
      "{\"required\":[],\"allowed\":{\"x\":[" + choices.join(",") + "]}}",
    ),
  )
  choices.push("256")
  assert_eq(
    expectations_error(
      "{\"required\":[],\"allowed\":{\"x\":[" + choices.join(",") + "]}}",
    ),
    "invalid_allowed_values",
  )
  assert_eq(expectations_error(" ".repeat(2097153)), "input_limit")
  assert_eq(
    expectations_error("[".repeat(68) + "0" + "]".repeat(68)),
    "depth_limit",
  )
  let nested = "[".repeat(63) + "-0" + "]".repeat(63)
  let expected = @trace.MetadataExpectations::from_json(
    "{\"required\":[\"x\"],\"allowed\":{\"x\":[" + nested + "]}}",
  )
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":" + nested + "}"),
  ])
  assert_true(
    index.audit_all().check_expectations(expected).decision() ==
    @trace.ExpectationDecision::Pass,
  )
}
