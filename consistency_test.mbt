///|
test "consistency detects exact values within subject groups with query and origin evidence" {
  let first = scan()
  let second = "sub-01/func/sub-01_task-rest_run-02_bold.nii.gz"
  let other = "sub-02/func/sub-02_task-rest_bold.nii.gz"
  let index = @trace.DatasetIndex::from_manifest([first, second, other], [
    @trace.SidecarInput::new(
      "bold.json", "{\"x\":2.0,\"unknown\":9007199254740993}",
    ),
    @trace.SidecarInput::new(
      "sub-01/func/sub-01_task-rest_run-02_bold.json", "{\"x\":2}",
    ),
  ])
  let before = index.to_manifest_json()
  let rules = @trace.ConsistencyRules::new(["sub"], ["x"], true)
  let report = index
    .audit([other, first, second, first])
    .check_consistency(rules)
  assert_true(report.decision() == @trace.ExpectationDecision::Violations)
  assert_eq(report.violation_count(), 1)
  assert_true(report.to_json().contains("9007199254740993"))
  assert_true(report.to_json().contains("\"query_index\":3"))
  assert_true(report.to_json().contains("\"value\":2.0"))
  assert_true(report.to_json().contains("\"value\":2}"))
  assert_eq(
    report.to_json(),
    index
    .audit([other, first, second, first])
    .check_consistency(rules)
    .to_json(),
  )
  assert_eq(
    @trace.ConsistencyRules::from_json(rules.to_json()).to_json(),
    rules.to_json(),
  )
  assert_eq(index.to_manifest_json(), before)
}

///|
test "missing and null are distinct and presence policy is explicit" {
  let index = sample("{\"x\":null}")
  let optional = @trace.ConsistencyRules::new([], ["absent"], false)
  assert_true(
    index.audit_all().check_consistency(optional).decision() ==
    @trace.ExpectationDecision::Pass,
  )
  let required = @trace.ConsistencyRules::new([], ["absent"], true)
  assert_eq(index.audit_all().check_consistency(required).violation_count(), 1)
  let null_rule = @trace.ConsistencyRules::new(["ses"], ["x"], true)
  let null_report = index.audit_all().check_consistency(null_rule)
  assert_true(null_report.decision() == @trace.ExpectationDecision::Pass)
  assert_true(null_report.to_json().contains("\"ses\":null"))
  assert_true(null_report.to_json().contains("\"present\":true,\"value\":null"))
}

///|
test "unknown paths and empty selections never pass consistency" {
  let index = sample("{\"x\":1}")
  let rules = @trace.ConsistencyRules::new([], ["x"], true)
  let failed = index.audit(["unknown", scan()]).check_consistency(rules)
  assert_true(failed.decision() == @trace.ExpectationDecision::Indeterminate)
  assert_true(failed.to_json().contains("unknown"))
  assert_true(
    index.audit([]).check_consistency(rules).decision() ==
    @trace.ExpectationDecision::Indeterminate,
  )
  assert_true(
    index.audit_all().check_consistency(rules).decision() ==
    @trace.ExpectationDecision::Pass,
  )
}

///|
test "consistency controls reject malformed unsupported duplicate and oversized fields" {
  for
    text in [
      "{}", "{\"fields\":[\"x\"],\"group_by\":[],\"require_present\":0}", "{\"fields\":[],\"group_by\":[],\"require_present\":true}",
      "{\"fields\":[\"x\"],\"group_by\":[\"suffix\"],\"require_present\":true}",
      "{\"fields\":[\"x\",\"x\"],\"group_by\":[],\"require_present\":true}", "{\"fields\":[\"x\"],\"group_by\":[],\"require_present\":false,\"extra\":1}",
      "{\"fields\":[\"x\"],\"group_by\":[],\"require_present\":false,\"fields\":[\"y\"]}",
    ] {
    let rejected = try {
      ignore(@trace.ConsistencyRules::from_json(text))
      false
    } catch {
      @trace.TraceError(_) => true
    }
    assert_true(rejected)
  }
  let fields = Array::makei(256, i => "field" + i.to_string())
  let rules = @trace.ConsistencyRules::new([], fields, false)
  assert_eq(
    @trace.ConsistencyRules::from_json(rules.to_json()).to_json(),
    rules.to_json(),
  )
  fields.push("overflow")
  let rejected = try {
    ignore(@trace.ConsistencyRules::new([], fields, true))
    false
  } catch {
    @trace.TraceError(_) => true
  }
  assert_true(rejected)
}

///|
test "normalized decimal entities group together and array order is significant" {
  let first = "sub-01/func/sub-01_task-rest_run-01_bold.nii"
  let second = "sub-02/func/sub-02_task-rest_run-1_bold.nii"
  let index = @trace.DatasetIndex::from_manifest([first, second], [
    @trace.SidecarInput::new("bold.json", "{\"x\":[1,2]}"),
    @trace.SidecarInput::new(
      "sub-02/func/sub-02_task-rest_bold.json", "{\"x\":[2,1]}",
    ),
  ])
  let report = index
    .audit_all()
    .check_consistency(@trace.ConsistencyRules::new(["run"], ["x"], true))
  assert_eq(report.violation_count(), 1)
  assert_true(report.to_json().contains("\"group\":{\"run\":\"1\"}"))
}

///|
test "optional missing values cannot silently join present null and rules own their inputs" {
  let second = "sub-02/func/sub-02_task-rest_bold.nii"
  let index = @trace.DatasetIndex::from_manifest([scan(), second], [
    @trace.SidecarInput::new(
      "sub-02/func/sub-02_task-rest_bold.json", "{\"x\":null}",
    ),
  ])
  let fields = ["x"]
  let group_by : Array[String] = []
  let rules = @trace.ConsistencyRules::new(group_by, fields, false)
  fields[0] = "other"
  group_by.push("sub")
  let report = index.audit_all().check_consistency(rules)
  assert_true(report.decision() == @trace.ExpectationDecision::Violations)
  assert_eq(report.violation_count(), 1)
  assert_true(report.to_json().contains("\"present\":false"))
  assert_true(report.to_json().contains("\"present\":true,\"value\":null"))
  assert_eq(
    rules.to_json(),
    "{\"fields\":[\"x\"],\"group_by\":[],\"require_present\":false}",
  )
}
