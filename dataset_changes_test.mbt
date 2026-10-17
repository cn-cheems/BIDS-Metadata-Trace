///|
test "combined source and scan rename avoids an invalid intermediate label collision" {
  let old = "sub-aa/func/sub-aa_task-rest_bold.nii.gz"
  let next = "sub-AA/func/sub-AA_task-rest_run-02_bold.nii.gz"
  let source = "sub-aa/func/sub-aa_task-rest_bold.json"
  let target = "sub-AA/func/sub-AA_task-rest_run-02_bold.json"
  let index = @trace.DatasetIndex::from_manifest([old], [
    @trace.SidecarInput::new(source, "{\"x\":9007199254740993}"),
  ])
  let original = index.to_manifest_json()
  let changes = @trace.DatasetChanges::new(
    @trace.ScanChanges::new([next], [old]),
    @trace.SourceChanges::new(
      [@trace.SidecarInput::new(target, "{\"x\":9007199254740993}")],
      [source],
    ),
    @trace.EditBatch::from_patches([]),
  )
  let plan = index.plan_changes(changes)
  assert_eq(plan.after().data_paths(), [next])
  assert_eq(
    plan.after().resolve(next).get("x").unwrap().stringify(),
    "9007199254740993",
  )
  assert_eq(
    @trace.DatasetChanges::from_json(changes.to_json()).to_json(),
    changes.to_json(),
  )
  assert_eq(
    @trace.DatasetIndex::from_json(plan.after().to_manifest_json()).to_manifest_json(),
    plan.after().to_manifest_json(),
  )
  assert_eq(index.to_manifest_json(), original)
  assert_true(plan.to_json().contains(source))
}

///|
test "combined edits preserve unrelated metadata and fail atomically" {
  let index = sample("{\"x\":2.0,\"unknown\":[null,1e999]}")
  let before = index.to_manifest_json()
  let patch = @trace.MetadataPatch::from_json(
    "{\"set\":{\"x\":3.0},\"remove\":[]}",
  )
  let changes = @trace.DatasetChanges::new(
    @trace.ScanChanges::new([], []),
    @trace.SourceChanges::new([], []),
    @trace.EditBatch::from_patches([("task-rest_bold.json", patch)]),
  )
  let plan = index.plan_changes(changes)
  assert_true(plan.after().to_manifest_json().contains("[null,1e999]"))
  assert_eq(plan.impact().changed_count(), 1)
  let invalid = @trace.DatasetChanges::new(
    @trace.ScanChanges::new([], ["sub-02/func/sub-02_task-rest_bold.nii"]),
    @trace.SourceChanges::new([], []),
    @trace.EditBatch::from_patches([]),
  )
  let code = try {
    ignore(index.plan_changes(invalid))
    "accepted"
  } catch {
    @trace.TraceError(d) => d.code
  }
  assert_eq(code, "unknown_data_path")
  assert_eq(index.to_manifest_json(), before)
  assert_eq(index.plan_changes(changes).to_json(), plan.to_json())
}

///|
test "combined controls reject unknown duplicate missing and conflicting operations" {
  for
    text in [
      "{}", "{\"scans\":{},\"sources\":{},\"edits\":{},\"extra\":0}", "{\"scans\":{},\"scans\":{},\"sources\":{},\"edits\":{}}",
    ] {
    let rejected = try {
      ignore(@trace.DatasetChanges::from_json(text))
      false
    } catch {
      @trace.TraceError(_) => true
    }
    assert_true(rejected)
  }
  let rejected = try {
    ignore(
      @trace.DatasetChanges::new(
        @trace.ScanChanges::new([], []),
        @trace.SourceChanges::new([], ["bold.json"]),
        @trace.EditBatch::from_patches([
          (
            "bold.json",
            @trace.MetadataPatch::from_json("{\"set\":{},\"remove\":[]}"),
          ),
        ]),
      ),
    )
    false
  } catch {
    @trace.TraceError(d) => d.code == "dataset_change_conflict"
  }
  assert_true(rejected)
}
