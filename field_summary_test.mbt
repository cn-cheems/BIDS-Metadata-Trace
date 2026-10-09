///|
test "summary keeps exact values provenance duplicates missing and errors" {
  let other = "sub-01/func/sub-01_task-rest_run-02_bold.nii.gz"
  let anatomy = "sub-01/anat/sub-01_T1w.nii"
  let index = @trace.DatasetIndex::from_manifest([scan(), other, anatomy], [
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":2.0,\"n\":null}"),
    @trace.SidecarInput::new(
      "sub-01/func/sub-01_task-rest_run-01_bold.json", "{\"x\":2}",
    ),
  ])
  let report = index
    .audit([scan(), other, anatomy, "unknown.nii", scan()])
    .summarize_fields(["x", "n"])
  assert_eq(report.error_count(), 1)
  guard report.to_json_value()
    is {
      "query_count": Number(5.0, ..),
      "resolved_count": Number(4.0, ..),
      "errors": Array([{ "query_index": Number(3.0, ..), .. }]),
      "fields": Array(
        [
          {
            "missing": Array([{ "data_path": String(a), .. }]),
            "groups": Array(
              [
                { "observations": Array(first), .. },
                { "observations": Array(second), .. },
              ]
            ),
            ..
          },
          {
            "groups": Array(
              [{ "value": Null, "observations": Array(nulls), .. }]
            ),
            ..
          },
        ]
      ),
      ..
    } else {
    fail("Summary shape")
  }
  assert_eq(a, anatomy)
  assert_eq(first.length(), 2)
  assert_eq(second.length(), 1)
  assert_eq(nulls.length(), 3)
  assert_true(report.to_json().contains("\"value\":2.0"))
  assert_true(
    report
    .to_json()
    .contains("\"trace\":[{\"path\":\"task-rest_bold.json\",\"value\":2.0}"),
  )
}

///|
test "summary snapshot round trip preserves large integers negative zero and nested values" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new(
      "task-rest_bold.json", "{\"large\":9007199254740993,\"zero\":-0,\"unknown\":{\"array\":[true,null,2.0]}}",
    ),
  ])
  let keys = ["large", "zero", "unknown"]
  let report = index.audit_all().summarize_fields(keys)
  assert_true(report.to_json().contains("9007199254740993"))
  assert_true(report.to_json().contains("\"value\":-0"))
  assert_eq(
    report.to_json(),
    @trace.DatasetIndex::from_json(index.to_manifest_json())
    .audit_all()
    .summarize_fields(keys)
    .to_json(),
  )
  let value = report.to_json_value()
  if value is Object(fields) {
    fields.clear()
  }
  assert_true(report.to_json().contains("9007199254740993"))
}

///|
test "summary rejects duplicate and oversized projections then recovers" {
  let audit = @trace.DatasetIndex::from_manifest([], []).audit_all()
  try {
    ignore(audit.summarize_fields(["x", "x"]))
    fail("duplicate accepted")
  } catch {
    @trace.TraceError(d) => assert_eq(d.code, "duplicate_field_request")
    error => fail(error.to_string())
  }
  let keys = Array::makei(256, i => i.to_string())
  assert_eq(audit.summarize_fields(keys).error_count(), 0)
  keys.push("extra")
  try {
    ignore(audit.summarize_fields(keys))
    fail("limit accepted")
  } catch {
    @trace.TraceError(d) => assert_eq(d.code, "field_request_limit")
    error => fail(error.to_string())
  }
  assert_true(audit.summarize_fields([]).to_json().contains("\"fields\":[]"))
}

///|
test "summary ambiguity remains an error rather than absent metadata" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("bold.json", "{}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
  ])
  let report = index.audit_all().summarize_fields(["missing"])
  assert_eq(report.error_count(), 1)
  assert_true(report.to_json().contains("\"missing\":[]"))
  assert_true(report.to_json().contains("ambiguous_inheritance"))
}
