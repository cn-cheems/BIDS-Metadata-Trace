///|
fn number_rules(text : String) -> @trace.NumericRules raise @trace.TraceError {
  @trace.NumericRules::from_json(text)
}

///|
fn number_policy(
  rules : @trace.NumericRules,
) -> @trace.MetadataExpectations raise @trace.TraceError {
  @trace.MetadataExpectations::from_json("{\"required\":[],\"allowed\":{}}").with_numeric(
    rules,
  )
}

///|
fn number_index(
  metadata : String,
) -> @trace.DatasetIndex raise @trace.TraceError {
  @trace.DatasetIndex::from_manifest(
    ["sub-01/func/sub-01_task-rest_bold.nii"],
    [@trace.SidecarInput::new("bold.json", metadata)],
  )
}

///|
test "numeric scalar intervals compare exact values and keep original report tokens" {
  let policy = number_policy(
    number_rules(
      "{\"fields\":{\"x\":{\"type\":\"number\",\"gte\":2,\"lte\":2e0}},\"relations\":[]}",
    ),
  )
  for token in ["2", "2.0", "2e0", "0.2e1", "200e-2"] {
    let index = number_index(
      "{\"x\":" + token + ",\"unknown\":[null,-0,1e999]}",
    )
    let before = index.to_manifest_json()
    let report = index.audit_all().check_expectations(policy)
    assert_true(report.decision() == @trace.ExpectationDecision::Pass)
    assert_eq(report.violation_count(), 0)
    assert_true(report.to_json().contains("\"actual\":" + token))
    assert_true(report.to_json().contains("\"unknown\":[null,-0,1e999]"))
    assert_eq(index.to_manifest_json(), before)
  }
  for
    (token, status) in [
      ("1.99999999999999999999", "below_minimum"),
      ("2.00000000000000000001", "above_maximum"),
      ("null", "not_number"),
      ("\"2\"", "not_number"),
      ("[]", "not_number"),
      ("true", "not_number"),
    ] {
    let report = number_index("{\"x\":" + token + "}")
      .audit_all()
      .check_expectations(policy)
    assert_eq(report.violation_count(), 1)
    assert_true(report.to_json().contains("\"status\":\"" + status + "\""))
  }
  assert_eq(
    number_index("{}").audit_all().check_expectations(policy).violation_count(),
    1,
  )
}

///|
test "numeric open bounds large integers exponents and signed zero have no float rounding" {
  for
    (rule, passing, failing) in [
      ("\"gt\":9007199254740992", "9007199254740993", "9007199254740992"),
      ("\"lt\":-9007199254740992", "-9007199254740993", "-9007199254740992"),
      ("\"gt\":1e999", "2e999", "1e999"),
      ("\"lt\":1e-999", "9e-1000", "1e-999"),
      ("\"gte\":0,\"lte\":0", "-0", "-1e-999999999999999999999"),
    ] {
    let policy = number_policy(
      number_rules(
        "{\"fields\":{\"x\":{\"type\":\"number\"," +
        rule +
        "}},\"relations\":[]}",
      ),
    )
    assert_eq(
      number_index("{\"x\":" + passing + "}")
      .audit_all()
      .check_expectations(policy)
      .violation_count(),
      0,
    )
    assert_eq(
      number_index("{\"x\":" + failing + "}")
      .audit_all()
      .check_expectations(policy)
      .violation_count(),
      1,
    )
  }
}

///|
test "numeric arrays validate length each element and strict mathematical order" {
  let policy = number_policy(
    number_rules(
      "{\"fields\":{\"x\":{\"type\":\"array\",\"gte\":0,\"lt\":2,\"min_items\":2,\"max_items\":3,\"strictly_increasing\":true}},\"relations\":[]}",
    ),
  )
  for
    (value, status) in [
      ("[-0,1.0]", "pass"),
      ("[0,0.01,1.999999999999999999]", "pass"),
      ("[]", "too_few_items"),
      ("[0]", "too_few_items"),
      ("[0,1,1,1]", "too_many_items"),
      ("[0,null]", "not_number"),
      ("[0,[1]]", "not_number"),
      ("[0,2]", "above_maximum"),
      ("[-1,0]", "below_minimum"),
      ("[1,1.0]", "not_strictly_increasing"),
      ("[1,0]", "not_strictly_increasing"),
      ("null", "not_array"),
      ("2", "not_array"),
    ] {
    let report = number_index("{\"x\":" + value + "}")
      .audit_all()
      .check_expectations(policy)
    assert_eq(report.violation_count(), if status == "pass" { 0 } else { 1 })
    assert_true(report.to_json().contains("\"status\":\"" + status + "\""))
    assert_true(report.to_json().contains("\"actual\":" + value))
    if status == "not_number" ||
      status == "above_maximum" ||
      status == "not_strictly_increasing" {
      assert_true(report.to_json().contains("\"item_index\":1"))
    }
  }
  let empty = number_policy(
    number_rules("{\"fields\":{\"x\":{\"type\":\"array\"}},\"relations\":[]}"),
  )
  assert_eq(
    number_index("{\"x\":[]}")
    .audit_all()
    .check_expectations(empty)
    .violation_count(),
    0,
  )
}

///|
test "numeric cross-field relations retain both inherited winners and exact operands" {
  for
    (op, left, right, violations) in [
      ("lt", "0.03", "2.0", 0),
      ("lte", "2e0", "2.0", 0),
      ("eq", "9007199254740993", "9007199254740992", 1),
      ("eq", "-0", "0.0", 0),
      ("gte", "1e999", "1e998", 0),
      ("gt", "1e-999", "2e-999", 1),
    ] {
    let rules = number_rules(
      "{\"fields\":{\"TE\":{\"type\":\"number\"},\"TR\":{\"type\":\"number\"}},\"relations\":[{\"left\":\"TE\",\"op\":\"" +
      op +
      "\",\"right\":\"TR\"}]}",
    )
    let p = "sub-01/func/sub-01_task-rest_bold.nii"
    let index = @trace.DatasetIndex::from_manifest([p], [
      @trace.SidecarInput::new("bold.json", "{\"TE\":" + left + "}"),
      @trace.SidecarInput::new(
        "sub-01/sub-01_bold.json",
        "{\"TR\":" + right + "}",
      ),
    ])
    let report = index.audit_all().check_expectations(number_policy(rules))
    assert_eq(report.violation_count(), violations)
    assert_true(report.to_json().contains("\"winning_source\":\"bold.json\""))
    assert_true(
      report
      .to_json()
      .contains("\"winning_source\":\"sub-01/sub-01_bold.json\""),
    )
  }
  let rules = number_rules(
    "{\"fields\":{\"a\":{\"type\":\"number\"},\"b\":{\"type\":\"number\"}},\"relations\":[{\"left\":\"a\",\"op\":\"lt\",\"right\":\"b\"}]}",
  )
  let report = number_index("{\"a\":null}")
    .audit_all()
    .check_expectations(number_policy(rules))
  assert_eq(report.violation_count(), 3)
  assert_true(report.to_json().contains("invalid_operands"))
}

///|
test "numeric array rules agree with an exhaustive integer oracle" {
  let policy = number_policy(
    number_rules(
      "{\"fields\":{\"x\":{\"type\":\"array\",\"gt\":0,\"lte\":2,\"min_items\":1,\"max_items\":3,\"strictly_increasing\":true}},\"relations\":[]}",
    ),
  )
  let mut cases = 1
  for length in 0..<=4 {
    for encoded in 0..<cases {
      let values : Array[Int32] = []
      let mut bits = encoded
      for _ in 0..<length {
        values.push(bits % 4 - 1)
        bits /= 4
      }
      let mut passing = length >= 1 && length <= 3
      for i, value in values {
        if value <= 0 || value > 2 || (i > 0 && values[i - 1] >= value) {
          passing = false
        }
      }
      let json = values.map(v => v.to_string()).join(",")
      let report = number_index("{\"x\":[" + json + "]}")
        .audit_all()
        .check_expectations(policy)
      assert_eq(report.violation_count() == 0, passing)
    }
    cases *= 4
  }
}

///|
test "numeric public policy handles long exponents while preserving all original tokens" {
  let exponent = "9".repeat(10000)
  let lower = "1e" + exponent
  let equivalent = "10e" + "9".repeat(9999) + "8"
  let rules = number_rules(
    "{\"fields\":{\"x\":{\"type\":\"number\",\"gte\":" +
    lower +
    ",\"lte\":" +
    equivalent +
    "}},\"relations\":[]}",
  )
  let report = number_index("{\"x\":" + equivalent + "}")
    .audit_all()
    .check_expectations(number_policy(rules))
  assert_eq(report.violation_count(), 0)
  assert_true(report.to_json().contains("\"actual\":" + equivalent))
  assert_eq(number_rules(rules.to_json()).to_json(), rules.to_json())
}
