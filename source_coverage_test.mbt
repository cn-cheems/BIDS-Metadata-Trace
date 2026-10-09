///|
test "coverage distinguishes winning shadowed unmatched and empty sources" {
  let second = "sub-01/func/sub-01_task-rest_run-02_bold.nii.gz"
  let index = @trace.DatasetIndex::from_manifest([second, scan()], [
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":2.0}"),
    @trace.SidecarInput::new(
      "sub-01/func/sub-01_task-rest_run-01_bold.json", "{\"x\":3.0}",
    ),
    @trace.SidecarInput::new("task-other_bold.json", "{\"unused\":null}"),
    @trace.SidecarInput::new(
      "sub-01/func/sub-01_task-rest_run-02_bold.json", "{}",
    ),
  ])
  let report = index.source_coverage()
  assert_eq(report.error_count(), 0)
  assert_eq(report.unmatched_paths(), ["task-other_bold.json"])
  let entries = report.entries()
  assert_eq(entries.length(), 4)
  let root = entries[3]
  assert_eq(root.path(), "task-rest_bold.json")
  assert_eq(root.applicable_paths(), [scan(), second])
  assert_eq(root.winning_paths(), [second])
  assert_eq(root.fully_shadowed_paths(), [scan()])
  assert_eq(entries[1].metadata_keys(), [])
  assert_eq(entries[1].applicable_paths(), [second])
  assert_eq(entries[1].fully_shadowed_paths(), [])
}

///|
test "coverage preserves ambiguity and unaffected scans without speculative fields" {
  let anatomy = "sub-01/anat/sub-01_T1w.nii"
  let index = @trace.DatasetIndex::from_manifest([scan(), anatomy], [
    @trace.SidecarInput::new("bold.json", "{\"x\":1}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":1}"),
    @trace.SidecarInput::new("T1w.json", "{\"y\":2}"),
  ])
  let report = index.source_coverage()
  assert_eq(report.error_count(), 1)
  assert_eq(report.diagnostics()[0].path, scan())
  assert_eq(report.entries()[0].winning_paths(), [anatomy])
  for entry in report.entries()[1:] {
    assert_eq(entry.unresolved_paths(), [scan()])
    assert_eq(entry.winning_paths(), [])
    assert_eq(entry.fully_shadowed_paths(), [])
  }
  assert_true(report.to_json().contains("ambiguous_inheritance"))
}

///|
test "coverage records partial field shadowing rather than classifying the whole source" {
  let report = sample("{\"x\":1,\"y\":null}", override_text="{\"x\":2}").source_coverage()
  let root = report.entries()[1]
  assert_eq(root.winning_paths(), [scan()])
  assert_eq(root.fully_shadowed_paths(), [])
  guard @json.parse(report.to_json())
    is {
      "entries": Array(
        [
          _,
          {
            "scans": Array(
              [
                {
                  "winning_fields": Array([String("y")]),
                  "shadowed_fields": Array([String("x")]),
                  ..
                },
              ]
            ),
            ..
          },
        ]
      ),
      ..
    } else {
    fail("Expected exact per-field coverage")
  }
}

///|
test "coverage is deterministic across input order and snapshot reload" {
  let a = sample("{\"x\":9007199254740993}", override_text="{\"x\":-0}")
  let b = @trace.DatasetIndex::from_json(a.to_manifest_json())
  let saved = a.to_manifest_json()
  assert_eq(a.source_coverage().to_json(), b.source_coverage().to_json())
  assert_eq(a.to_manifest_json(), saved)
  let inputs = [
    @trace.SidecarInput::new(
      "sub-01/func/sub-01_task-rest_run-01_bold.json", "{\"x\":-0}",
    ),
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":9007199254740993}"),
  ]
  assert_eq(
    @trace.DatasetIndex::from_manifest([scan()], inputs)
    .source_coverage()
    .to_json(),
    a.source_coverage().to_json(),
  )
}

///|
test "coverage accessors cannot alter stored evidence or diagnostics" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("bold.json", "{}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
  ])
  let report = index.source_coverage()
  let saved = report.to_json()
  report.entries()[0].metadata_keys().clear()
  report.entries()[0].applicable_paths().clear()
  report.diagnostics()[0].related.clear()
  report.entries().clear()
  assert_eq(report.to_json(), saved)
}

///|
test "empty inventory and no applicable scans retain every input source" {
  let empty = @trace.DatasetIndex::from_manifest([], []).source_coverage()
  assert_eq(empty.entries().length(), 0)
  assert_eq(empty.error_count(), 0)
  let report = @trace.DatasetIndex::from_manifest([], [
    @trace.SidecarInput::new("bold.json", "{}"),
  ]).source_coverage()
  assert_eq(report.unmatched_paths(), ["bold.json"])
  assert_eq(report.entries()[0].applicable_paths(), [])
}

///|
test "correcting ambiguous input allows a fresh complete coverage report" {
  let bad = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("bold.json", "{}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
  ])
  assert_eq(bad.source_coverage().error_count(), 1)
  let good = sample("{\"x\":1}").source_coverage()
  assert_eq(good.error_count(), 0)
  assert_eq(good.entries()[0].winning_paths(), [scan()])
  assert_eq(bad.source_coverage().error_count(), 1)
}
