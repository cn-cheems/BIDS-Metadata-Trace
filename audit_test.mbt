///|
test "batch continues after ambiguity and unknown paths without losing occurrences" {
  let anatomy = "sub-01/anat/sub-01_T1w.nii"
  let index = @trace.DatasetIndex::from_manifest([scan(), anatomy], [
    @trace.SidecarInput::new("bold.json", "{\"x\":1}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":2}"),
    @trace.SidecarInput::new("T1w.json", "{\"Custom\":9007199254740993}"),
  ])
  let report = index.audit([scan(), "absent", anatomy, anatomy])
  assert_eq(report.error_count(), 2)
  let entries = report.entries()
  assert_eq(entries.map(e => e.path()), [scan(), "absent", anatomy, anatomy])
  assert_eq(entries[0].diagnostic().unwrap().code, "ambiguous_inheritance")
  assert_eq(entries[1].diagnostic().unwrap().code, "unknown_data_path")
  assert_eq(
    entries[2].result().unwrap().to_json(),
    "{\"Custom\":9007199254740993}",
  )
  assert_true(report.to_json().contains("9007199254740993"))
  let copy = entries[0].diagnostic().unwrap()
  copy.related.clear()
  entries.clear()
  assert_eq(report.entries()[0].diagnostic().unwrap().related.length(), 2)
  assert_eq(report.entries().length(), 4)
}

///|
test "audit all is sorted deterministic and empty queries remain empty" {
  let a = sample("{\"x\":-0,\"z\":2.0}")
  assert_eq(a.audit_all().to_json(), a.audit([scan()]).to_json())
  assert_true(a.audit_all().to_json().contains("\"x\":-0"))
  assert_true(a.audit_all().to_json().contains("\"z\":2.0"))
  assert_eq(a.audit([]).to_json(), "{\"entries\":[],\"error_count\":0}")
  let restored = @trace.DatasetIndex::from_json(a.to_manifest_json())
  assert_eq(restored.audit_all().to_json(), a.audit_all().to_json())
}

///|
test "audit errors are reproducible and recovery does not alter earlier reports" {
  let invalid = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("bold.json", "{}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
  ])
  let failed = invalid.audit_all()
  let snapshot = failed.to_json()
  assert_eq(sample("{}").audit_all().error_count(), 0)
  assert_eq(invalid.audit_all().to_json(), snapshot)
  assert_eq(failed.to_json(), snapshot)
}
