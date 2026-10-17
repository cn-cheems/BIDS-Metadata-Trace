///|
fn scoped_rule(
  id : String,
  suffix : String,
  expected : String,
  entities~ : String = "{}",
) -> String {
  "{\"id\":" +
  Json::string(id).stringify() +
  ",\"select\":{\"suffixes\":[" +
  Json::string(suffix).stringify() +
  "],\"entities\":" +
  entities +
  "},\"expect\":" +
  expected +
  "}"
}

///|
fn scoped_rules(
  values : Array[String],
) -> @trace.AcquisitionRules raise @trace.TraceError {
  @trace.AcquisitionRules::from_json("{\"rules\":[" + values.join(",") + "]}")
}

///|
fn acquisition_error(text : String) -> String {
  try {
    ignore(@trace.AcquisitionRules::from_json(text))
    "accepted"
  } catch {
    @trace.TraceError(d) => d.code
  }
}

///|
test "scoped acquisition rules check separate modalities against inherited exact values" {
  let anatomy = "sub-01/anat/sub-01_T1w.nii"
  let index = @trace.DatasetIndex::from_manifest([scan(), anatomy], [
    @trace.SidecarInput::new(
      "task-rest_bold.json", "{\"RepetitionTime\":2.0,\"unknown\":[-0,9007199254740993]}",
    ),
    @trace.SidecarInput::new("T1w.json", "{\"EchoTime\":0.004}"),
    @trace.SidecarInput::new("dwi.json", "{\"unused\":1e999}"),
  ])
  let before = index.to_manifest_json()
  let rules = scoped_rules([
    scoped_rule(
      "func", "bold", "{\"required\":[\"RepetitionTime\"],\"allowed\":{\"RepetitionTime\":[2.0]}}",
    ),
    scoped_rule(
      "anat", "T1w", "{\"required\":[\"EchoTime\"],\"allowed\":{\"EchoTime\":[0.004]}}",
    ),
  ])
  let report = index.check_acquisition(rules)
  assert_true(report.decision() == @trace.ExpectationDecision::Pass)
  assert_eq(report.error_count(), 0)
  assert_eq(report.violation_count(), 0)
  assert_eq(report.uncovered_paths(), [])
  assert_eq(report.unmatched_rule_ids(), [])
  assert_true(report.to_json().contains("[-0,9007199254740993]"))
  assert_true(report.to_json().contains("\"unused\":1e999"))
  assert_true(report.to_json().contains("task-rest_bold.json"))
  assert_eq(index.to_manifest_json(), before)
}

///|
test "overlapping rules are conjunctive and count each failing rule field" {
  let index = sample("{\"x\":2.0,\"n\":null}")
  let rules = scoped_rules([
    scoped_rule(
      "pass", "bold", "{\"required\":[\"x\",\"n\"],\"allowed\":{\"n\":[null],\"x\":[2.0]}}",
    ),
    scoped_rule(
      "fail", "bold", "{\"required\":[\"missing\"],\"allowed\":{\"x\":[2]}}",
    ),
  ])
  let report = index.check_acquisition(rules)
  assert_true(report.decision() == @trace.ExpectationDecision::Violations)
  assert_eq(report.violation_count(), 2)
  assert_eq(report.error_count(), 0)
  assert_true(report.to_json().contains("\"rule_ids\":[\"fail\",\"pass\"]"))
  assert_true(report.to_json().contains("missing_required"))
  assert_true(report.to_json().contains("unexpected_value"))
}

///|
test "uncovered scans and unmatched rules preclude vacuous approval and retain full evidence" {
  let anatomy = "sub-01/anat/sub-01_T1w.nii"
  let index = @trace.DatasetIndex::from_manifest([scan(), anatomy], [
    @trace.SidecarInput::new("T1w.json", "{\"unknown\":-0}"),
  ])
  let rules = scoped_rules([
    scoped_rule("func", "bold", "{\"required\":[],\"allowed\":{}}"),
    scoped_rule("diffusion", "dwi", "{\"required\":[],\"allowed\":{}}"),
  ])
  let report = index.check_acquisition(rules)
  assert_true(report.decision() == @trace.ExpectationDecision::Indeterminate)
  assert_eq(report.uncovered_paths(), [anatomy])
  assert_eq(report.unmatched_rule_ids(), ["diffusion"])
  assert_eq(report.error_count(), 0)
  assert_true(report.to_json().contains("\"unknown\":-0"))
  assert_true(report.to_json().contains("\"empty_audit\":true"))
  let empty = @trace.DatasetIndex::from_manifest([], []).check_acquisition(
    rules,
  )
  assert_true(empty.decision() == @trace.ExpectationDecision::Indeterminate)
  assert_eq(empty.unmatched_rule_ids(), ["diffusion", "func"])
  assert_true(empty.to_json().contains("\"empty_inventory\":true"))
}

///|
test "resolution errors count once across overlaps and take priority over violations" {
  let second = "sub-02/func/sub-02_task-rest_bold.nii"
  let index = @trace.DatasetIndex::from_manifest([scan(), second], [
    @trace.SidecarInput::new("bold.json", "{}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
  ])
  let rules = scoped_rules([
    scoped_rule("one", "bold", "{\"required\":[\"x\"],\"allowed\":{}}"),
    scoped_rule("two", "bold", "{\"required\":[\"y\"],\"allowed\":{}}"),
  ])
  let report = index.check_acquisition(rules)
  assert_true(report.decision() == @trace.ExpectationDecision::Indeterminate)
  assert_eq(report.error_count(), 2)
  assert_eq(report.violation_count(), 0)
  assert_true(report.to_json().contains("ambiguous_inheritance"))
  let fixed = sample("{\"x\":1,\"y\":1}").check_acquisition(rules)
  assert_true(fixed.decision() == @trace.ExpectationDecision::Pass)
  assert_eq(report.error_count(), 2)
  let mixed = @trace.DatasetIndex::from_manifest(
    [scan(), "sub-01/anat/sub-01_T1w.nii"],
    [
      @trace.SidecarInput::new("bold.json", "{}"),
      @trace.SidecarInput::new("task-rest_bold.json", "{}"),
    ],
  )
  let mixed_rules = scoped_rules([
    scoped_rule("func", "bold", "{\"required\":[],\"allowed\":{}}"),
    scoped_rule("anat", "T1w", "{\"required\":[\"missing\"],\"allowed\":{}}"),
  ])
  let mixed_report = mixed.check_acquisition(mixed_rules)
  assert_eq(mixed_report.error_count(), 1)
  assert_eq(mixed_report.violation_count(), 1)
  assert_true(
    mixed_report.decision() == @trace.ExpectationDecision::Indeterminate,
  )
}

///|
test "scoped rules normalize entity indices and ignore input and rule order" {
  let rule = scoped_rule(
    "later",
    "bold",
    "{\"required\":[\"x\"],\"allowed\":{\"x\":[-0,2.0]}}",
    entities="{\"run\":[\"0001\"]}",
  )
  let extra = scoped_rule("base", "bold", "{\"required\":[],\"allowed\":{}}")
  let rules = scoped_rules([rule, extra])
  let reverse = scoped_rules([extra, rule])
  assert_eq(rules.to_json(), reverse.to_json())
  let restored = @trace.AcquisitionRules::from_json(rules.to_json())
  assert_eq(restored.to_json(), rules.to_json())
  let index = sample("{\"x\":2.0}")
  let report = index.check_acquisition(rules)
  assert_true(report.decision() == @trace.ExpectationDecision::Pass)
  assert_eq(report.to_json(), index.check_acquisition(reverse).to_json())
  assert_eq(
    report.to_json(),
    @trace.DatasetIndex::from_json(index.to_manifest_json())
    .check_acquisition(restored)
    .to_json(),
  )
  let before = report.to_json()
  report.uncovered_paths().push("changed")
  report.unmatched_rule_ids().push("changed")
  if report.to_json_value() is Object(fields) {
    fields.clear()
  }
  assert_eq(report.to_json(), before)
}

///|
test "rule parser rejects unknown controls missing inputs duplicates and invalid ids" {
  let valid = scoped_rule("ok", "bold", "{\"required\":[],\"allowed\":{}}")
  for text in ["[]", "{}", "{\"rules\":[]}", "{\"rules\":{}}"] {
    assert_eq(acquisition_error(text), "invalid_acquisition_rules")
  }
  assert_eq(acquisition_error("{\"rules\":[{}]}"), "invalid_acquisition_rule")
  assert_eq(acquisition_error("{\"rules\":[2]}"), "invalid_acquisition_rule")
  assert_eq(
    acquisition_error("{\"rules\":[" + valid + "],\"ignore_uncovered\":true}"),
    "unknown_acquisition_rule_field",
  )
  assert_eq(
    acquisition_error(
      "{\"rules\":[" +
      valid.replace(old="\"id\":", new="\"priority\":1,\"id\":") +
      "]}",
    ),
    "unknown_acquisition_rule_field",
  )
  assert_eq(
    acquisition_error(
      "{\"rules\":[" +
      valid +
      "," +
      valid.replace(old="\"ok\"", new="\"OK\"") +
      "]}",
    ),
    "duplicate_rule_id",
  )
  for id in ["", "has space", "🧠", "a".repeat(65)] {
    assert_eq(
      acquisition_error(
        "{\"rules\":[" +
        scoped_rule(id, "bold", "{\"required\":[],\"allowed\":{}}") +
        "]}",
      ),
      "invalid_rule_id",
    )
  }
  assert_eq(
    acquisition_error("{\"rules\":[],\"\\u0072ules\":[]}"),
    "duplicate_json_key",
  )
  assert_eq(
    acquisition_error(
      "{\"rules\":[" +
      scoped_rule(
        "bad", "bold", "{\"required\":[],\"allowed\":{},\"tolerance\":1}",
      ) +
      "]}",
    ),
    "unknown_expectation_field",
  )
  assert_eq(
    acquisition_error(
      "{\"rules\":[" +
      scoped_rule(
        "bad",
        "bold",
        "{\"required\":[],\"allowed\":{}}",
        entities="{\"run\":[\"1\",\"01\"]}",
      ) +
      "]}",
    ),
    "duplicate_query_choice",
  )
}

///|
test "acquisition rule bounds preserve metadata depth and recover from excess input" {
  let values = Array::makei(64, i => {
    scoped_rule(
      "rule" + i.to_string(),
      "bold",
      "{\"required\":[],\"allowed\":{}}",
    )
  })
  ignore(scoped_rules(values))
  values.push(
    scoped_rule("overflow", "bold", "{\"required\":[],\"allowed\":{}}"),
  )
  assert_eq(
    acquisition_error("{\"rules\":[" + values.join(",") + "]}"),
    "invalid_acquisition_rules",
  )
  assert_eq(acquisition_error(" ".repeat(2097153)), "input_limit")
  let nested = "[".repeat(64) + "-0" + "]".repeat(64)
  let allowed = "{\"required\":[],\"allowed\":{\"x\":[" + nested + "]}}"
  let rules = scoped_rules([scoped_rule("deep", "bold", allowed)])
  assert_true(rules.to_json().contains("-0"))
  assert_eq(
    acquisition_error(
      "{\"rules\":[" +
      scoped_rule(
        "too-deep",
        "bold",
        "{\"required\":[],\"allowed\":{\"x\":[[" + nested + "]]}}",
      ) +
      "]}",
    ),
    "depth_limit",
  )
  ignore(
    scoped_rules([
      scoped_rule("a".repeat(64), "bold", "{\"required\":[],\"allowed\":{}}"),
    ]),
  )
}

///|
test "audit structured view extraction preserves existing serialized bytes" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [])
  let path = Json::string(scan()).stringify()
  assert_eq(
    index.audit_all().to_json(),
    "{\"entries\":[{\"data_path\":" +
    path +
    ",\"result\":{\"applied_sidecars\":[],\"data_path\":" +
    path +
    ",\"fields\":{},\"metadata\":{}},\"status\":\"resolved\"}],\"error_count\":0}",
  )
}
