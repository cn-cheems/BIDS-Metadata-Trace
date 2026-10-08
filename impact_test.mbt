///|
test "snapshot identity and round trip preserve all evidence" {
  let a = sample("{\"x\":9007199254740993,\"nested\":[{\"b\":2.0,\"a\":-0}]}")
  let b = @trace.DatasetIndex::from_json(a.to_manifest_json())
  let report = a.compare(b)
  assert_eq(report.changed_count(), 0)
  assert_eq(report.error_count(), 0)
  assert_true(report.entries()[0].kind() == @trace.ImpactKind::Unchanged)
  assert_true(report.to_json().contains("9007199254740993"))
  assert_true(report.to_json().contains("2.0"))
  assert_eq(report.to_json(), a.compare(a).to_json())
}

///|
test "field addition removal null and rounded-double collisions are distinct" {
  let before = sample(
    "{\"n\":9007199254740992,\"gone\":null,\"same\":{\"a\":1,\"b\":2}}",
  )
  let after = sample(
    "{\"n\":9007199254740993,\"new\":null,\"same\":{\"b\":2,\"a\":1}}",
  )
  let changes = before.compare(after).entries()[0].changes()
  assert_eq(changes.map(c => c.key()), ["gone", "n", "new"])
  assert_true(changes[0].kind() == @trace.FieldChangeKind::Removed)
  assert_eq(changes[0].before_json(), Some("null"))
  assert_eq(changes[0].after_json(), None)
  assert_true(changes[1].kind() == @trace.FieldChangeKind::ValueChanged)
  assert_eq(changes[1].before_json(), Some("9007199254740992"))
  assert_eq(changes[1].after_json(), Some("9007199254740993"))
  assert_true(changes[2].kind() == @trace.FieldChangeKind::Added)
  assert_eq(changes[2].after_json(), Some("null"))
  let reversed = after.compare(before).entries()[0].changes()
  assert_true(reversed[0].kind() == @trace.FieldChangeKind::Added)
  assert_true(reversed[2].kind() == @trace.FieldChangeKind::Removed)
}

///|
test "numeric representations and array ordering are explicit value changes" {
  for (a, b) in [("2", "2.0"), ("0", "-0"), ("1e3", "1000"), ("[1,2]", "[2,1]")] {
    let report = sample("{\"x\":" + a + "}").compare(
      sample("{\"x\":" + b + "}"),
    )
    assert_eq(report.changed_count(), 1)
    assert_true(
      report.entries()[0].changes()[0].kind() ==
      @trace.FieldChangeKind::ValueChanged,
    )
  }
}

///|
test "shadowed assignments distinguish provenance from effective value impact" {
  let before = sample("{\"x\":1}", override_text="{\"x\":3}")
  let after = sample("{\"x\":2}", override_text="{\"x\":3}")
  let entry = before.compare(after).entries()[0]
  assert_true(entry.kind() == @trace.ImpactKind::Changed)
  assert_true(!entry.sources_changed())
  let change = entry.changes()[0]
  assert_true(change.kind() == @trace.FieldChangeKind::ProvenanceChanged)
  assert_eq(change.before_json(), Some("3"))
  assert_eq(change.after_json(), Some("3"))
  assert_eq(change.before_trace()[0].value().stringify(), "1")
  assert_eq(change.after_trace()[0].value().stringify(), "2")
}

///|
test "empty sidecar source-chain edits still appear in scan impact" {
  let before = sample("{}")
  let after = sample("{}", override_text="{}")
  let entry = before.compare(after).entries()[0]
  assert_true(entry.kind() == @trace.ImpactKind::Changed)
  assert_true(entry.sources_changed())
  assert_eq(entry.changes().length(), 0)
}

///|
test "union retains added removed and unchanged scans in sorted order" {
  let anatomy = "sub-01/anat/sub-01_T1w.nii"
  let diffusion = "sub-01/dwi/sub-01_dwi.nii"
  let before = @trace.DatasetIndex::from_manifest([scan(), anatomy], [])
  let after = @trace.DatasetIndex::from_manifest([diffusion, scan()], [])
  let report = before.compare(after)
  assert_eq(report.changed_count(), 2)
  assert_eq(report.entries().map(e => e.path()), [anatomy, diffusion, scan()])
  assert_true(report.entries()[0].kind() == @trace.ImpactKind::Removed)
  assert_true(report.entries()[1].kind() == @trace.ImpactKind::Added)
  assert_true(report.entries()[2].kind() == @trace.ImpactKind::Unchanged)
  assert_true(report.entries()[0].after() is None)
  assert_true(report.entries()[1].before() is None)
  assert_eq(before.data_paths().length(), 2)
}

///|
test "ambiguity on either side is indeterminate and does not hide unaffected scans" {
  let anatomy = "sub-01/anat/sub-01_T1w.nii"
  let bad = @trace.DatasetIndex::from_manifest([scan(), anatomy], [
    @trace.SidecarInput::new("bold.json", "{}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
  ])
  let good = @trace.DatasetIndex::from_manifest([scan(), anatomy], [])
  for report in [bad.compare(good), good.compare(bad), bad.compare(bad)] {
    assert_eq(report.error_count(), 1)
    assert_eq(report.changed_count(), 0)
    assert_true(report.entries()[1].kind() == @trace.ImpactKind::Unresolved)
    assert_eq(report.entries()[1].changes().length(), 0)
    assert_true(report.to_json().contains("ambiguous_inheritance"))
    assert_true(report.entries()[0].kind() == @trace.ImpactKind::Unchanged)
  }
  assert_eq(good.compare(good).error_count(), 0)
}

///|
test "impact collections are defensive and irrelevant sidecar edits preserve behavior" {
  let before = sample("{\"x\":{\"a\":1}}")
  let after = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":{\"a\":2}}"),
    @trace.SidecarInput::new("task-other_bold.json", "{\"ignored\":99}"),
  ])
  let report = before.compare(after)
  let saved = report.to_json()
  let entries = report.entries()
  let changes = entries[0].changes()
  changes[0].before_trace().clear()
  if changes[0].after_trace()[0].value() is Object(fields) {
    fields.clear()
  }
  changes.clear()
  entries.clear()
  assert_eq(report.to_json(), saved)
  assert_eq(after.compare(sample("{\"x\":{\"a\":2}}")).changed_count(), 0)
  assert_eq(before.resolve(scan()).to_json(), "{\"x\":{\"a\":1}}")
}

///|
test "empty snapshot comparison has no synthetic entries" {
  let empty = @trace.DatasetIndex::from_manifest([], [])
  assert_eq(
    empty.compare(empty).to_json(),
    "{\"changed_count\":0,\"entries\":[],\"error_count\":0}",
  )
}
