///|
fn edit_run(run : String) -> String {
  "sub-01/func/sub-01_task-rest_run-" + run + "_bold.nii.gz"
}

///|
fn patch_error(text : String) -> String {
  try {
    @trace.MetadataPatch::from_json(text) |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
  }
}

///|
test "root edit covers three scans and distinguishes a shadowed assignment" {
  let paths = [edit_run("01"), edit_run("02"), edit_run("03")]
  let index = @trace.DatasetIndex::from_manifest(paths, [
    @trace.SidecarInput::new(
      "task-rest_bold.json", "{\"RepetitionTime\":2.0,\"Custom\":{\"keep\":9007199254740993}}",
    ),
    @trace.SidecarInput::new(
      "sub-01/func/sub-01_task-rest_run-01_bold.json", "{\"RepetitionTime\":4.0}",
    ),
  ])
  let baseline = index.to_manifest_json()
  let plan = index.plan_edit(
    "task-rest_bold.json",
    @trace.MetadataPatch::from_json(
      "{\"set\":{\"RepetitionTime\":3.0},\"remove\":[]}",
    ),
  )
  assert_eq(plan.sidecar_path(), "task-rest_bold.json")
  assert_eq(plan.impact().changed_count(), 3)
  assert_eq(plan.impact().error_count(), 0)
  assert_eq(plan.impact().entries().map(e => e.path()), paths)
  assert_true(
    plan.impact().entries()[0].changes()[0].kind() ==
    @trace.FieldChangeKind::ProvenanceChanged,
  )
  assert_true(
    plan.impact().entries()[1].changes()[0].kind() ==
    @trace.FieldChangeKind::ValueChanged,
  )
  assert_true(
    plan.impact().entries()[2].changes()[0].kind() ==
    @trace.FieldChangeKind::ValueChanged,
  )
  assert_eq(
    plan.after().resolve(paths[0]).get("RepetitionTime").unwrap().stringify(),
    "4.0",
  )
  assert_eq(
    plan.after().resolve(paths[1]).get("RepetitionTime").unwrap().stringify(),
    "3.0",
  )
  assert_eq(plan.before().to_manifest_json(), baseline)
  assert_eq(index.to_manifest_json(), baseline)
  assert_true(plan.updated_sidecar_json().contains("9007199254740993"))
}

///|
test "removing local override exposes inherited value and retains empty sidecar" {
  let index = sample("{\"x\":2.0}", override_text="{\"x\":3.0}")
  let local_path = "sub-01/func/sub-01_task-rest_run-01_bold.json"
  let plan = index.plan_edit(
    local_path,
    @trace.MetadataPatch::from_json("{\"set\":{},\"remove\":[\"x\"]}"),
  )
  assert_eq(plan.updated_sidecar_json(), "{}")
  assert_eq(plan.after().resolve(scan()).to_json(), "{\"x\":2.0}")
  assert_eq(plan.after().resolve(scan()).trace("x").map(o => o.path()), [
    "task-rest_bold.json",
  ])
  assert_eq(plan.after().resolve(scan()).applied_sidecars(), [
    "task-rest_bold.json", local_path,
  ])
  assert_true(!plan.impact().entries()[0].sources_changed())
  let change = plan.impact().entries()[0].changes()[0]
  assert_eq(change.before_json(), Some("3.0"))
  assert_eq(change.after_json(), Some("2.0"))
  assert_eq(index.resolve(scan()).to_json(), "{\"x\":3.0}")
}

///|
test "null assignment differs from explicit root field removal" {
  let index = sample("{\"x\":1}")
  let set_null = index.plan_edit(
    "task-rest_bold.json",
    @trace.MetadataPatch::from_json("{\"set\":{\"x\":null},\"remove\":[]}"),
  )
  let removed = index.plan_edit(
    "task-rest_bold.json",
    @trace.MetadataPatch::from_json("{\"set\":{},\"remove\":[\"x\"]}"),
  )
  assert_eq(set_null.after().resolve(scan()).to_json(), "{\"x\":null}")
  assert_eq(removed.after().resolve(scan()).to_json(), "{}")
  assert_eq(
    set_null.impact().entries()[0].changes()[0].after_json(),
    Some("null"),
  )
  assert_eq(removed.impact().entries()[0].changes()[0].after_json(), None)
  assert_true(
    removed.impact().entries()[0].changes()[0].kind() ==
    @trace.FieldChangeKind::Removed,
  )
}

///|
test "whole-field replacement preserves unknown fields nested values and number tokens" {
  let index = sample(
    "{\"Replace\":{\"old\":1,\"gone\":2},\"Untouched\":[9007199254740993,{\"zero\":-0,\"scientific\":1e3}],\"Future\":{\"空\":true}}",
  )
  let plan = index.plan_edit(
    "task-rest_bold.json",
    @trace.MetadataPatch::from_json(
      "{\"set\":{\"Replace\":{\"new\":2.0}},\"remove\":[]}",
    ),
  )
  assert_eq(
    plan.updated_sidecar_json(),
    "{\"Future\":{\"空\":true},\"Replace\":{\"new\":2.0},\"Untouched\":[9007199254740993,{\"scientific\":1e3,\"zero\":-0}]}",
  )
  assert_eq(plan.impact().entries()[0].changes().map(c => c.key()), ["Replace"])
  assert_true(!plan.updated_sidecar_json().contains("\"old\""))
  assert_true(plan.to_json().contains("9007199254740993"))
}

///|
test "numeric assignments detect double rounding collisions and representation edits" {
  let index = sample("{\"x\":9007199254740992,\"decimal\":2}")
  let plan = index.plan_edit(
    "task-rest_bold.json",
    @trace.MetadataPatch::from_json(
      "{\"set\":{\"x\":9007199254740993,\"decimal\":2.0},\"remove\":[]}",
    ),
  )
  let changes = plan.impact().entries()[0].changes()
  assert_eq(changes.map(c => c.key()), ["decimal", "x"])
  assert_eq(changes[0].after_json(), Some("2.0"))
  assert_eq(changes[1].before_json(), Some("9007199254740992"))
  assert_eq(changes[1].after_json(), Some("9007199254740993"))
  assert_true(
    changes.iter().all(c => c.kind() == @trace.FieldChangeKind::ValueChanged),
  )
}

///|
test "malformed patches reject unknown controls invalid shapes and conflicting operations" {
  for
    (text, expected) in [
      ("[]", "invalid_patch"),
      ("{}", "invalid_patch"),
      ("{\"set\":{}}", "invalid_patch"),
      ("{\"set\":[],\"remove\":[]}", "invalid_patch"),
      ("{\"set\":{},\"remove\":{}}", "invalid_patch"),
      ("{\"set\":{},\"remove\":[null]}", "invalid_patch"),
      ("{\"set\":{},\"remove\":[],\"merge\":{}}", "unknown_patch_field"),
      ("{\"set\":{\"x\":null},\"remove\":[\"x\"]}", "patch_conflict"),
      ("{\"set\":{},\"remove\":[\"x\",\"x\"]}", "duplicate_remove"),
      ("{\"set\":{},\"remove\":[\"x\",\"\\u0078\"]}", "duplicate_remove"),
      ("{", "invalid_json"),
    ] {
    assert_eq(patch_error(text), expected)
  }
}

///|
test "duplicate patch JSON keys fail throughout nested assignments" {
  for
    text in [
      "{\"set\":{},\"set\":{},\"remove\":[]}", "{\"set\":{\"x\":1,\"\\u0078\":2},\"remove\":[]}",
      "{\"set\":{\"deep\":[{\"a\":1,\"a\":2}]},\"remove\":[]}",
    ] {
    assert_eq(patch_error(text), "duplicate_json_key")
  }
}

///|
test "patch canonical round trip normalizes operation ordering without numeric loss" {
  let first = @trace.MetadataPatch::from_json(
    "{\"set\":{\"z\":-0,\"aa\":9007199254740993},\"remove\":[\"zebra\",\"a\",\"ab\"]}",
  )
  let saved = first.to_json()
  assert_eq(
    saved, "{\"remove\":[\"a\",\"ab\",\"zebra\"],\"set\":{\"aa\":9007199254740993,\"z\":-0}}",
  )
  assert_eq(@trace.MetadataPatch::from_json(saved).to_json(), saved)
  assert_eq(
    @trace.MetadataPatch::from_json(
      "{\"remove\":[\"ab\",\"a\",\"zebra\"],\"set\":{\"aa\":9007199254740993,\"z\":-0}}",
    ).to_json(),
    saved,
  )
}

///|
test "unknown sidecar and absent removals roll back completely and allow later recovery" {
  let index = sample("{\"x\":1,\"Keep\":true}")
  let baseline = index.to_manifest_json()
  let patch = @trace.MetadataPatch::from_json(
    "{\"set\":{\"x\":2},\"remove\":[]}",
  )
  let missing_path = try {
    index.plan_edit("task-other_bold.json", patch) |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => {
      assert_eq(d.path, "task-other_bold.json")
      d.code
    }
  }
  assert_eq(missing_path, "unknown_sidecar_path")
  let missing_field = try {
    index.plan_edit(
      "task-rest_bold.json",
      @trace.MetadataPatch::from_json(
        "{\"set\":{\"x\":2},\"remove\":[\"Keep\",\"absent\"]}",
      ),
    )
    |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
  }
  assert_eq(missing_field, "missing_metadata_field")
  assert_eq(index.to_manifest_json(), baseline)
  let recovered = index.plan_edit("task-rest_bold.json", patch)
  assert_eq(
    recovered.after().resolve(scan()).to_json(),
    "{\"Keep\":true,\"x\":2}",
  )
  assert_eq(index.to_manifest_json(), baseline)
}

///|
test "plan report is deterministic and new snapshot reloads with identical evidence" {
  let index = sample("{\"x\":1,\"old\":false}")
  let patch = @trace.MetadataPatch::from_json(
    "{\"set\":{\"x\":2.0,\"New\":null},\"remove\":[\"old\"]}",
  )
  let plan = index.plan_edit("task-rest_bold.json", patch)
  let restored = @trace.DatasetIndex::from_json(plan.after().to_manifest_json())
  assert_eq(restored.to_manifest_json(), plan.after().to_manifest_json())
  assert_eq(index.compare(restored).to_json(), plan.impact().to_json())
  assert_eq(
    plan.to_json(),
    index.plan_edit("task-rest_bold.json", patch).to_json(),
  )
  guard @json.parse(plan.to_json()) is Object(report) else {
    fail("Expected plan object")
  }
  assert_eq(report["sidecar_path"].stringify(), "\"task-rest_bold.json\"")
  assert_true(report["before_manifest"] is Object(_))
  assert_true(report["after_manifest"] is Object(_))
  assert_true(report["before_sidecar"] is Object(_))
  assert_true(report["after_sidecar"] is Object(_))
  assert_true(plan.to_json().contains("\"before_trace\""))
  assert_true(plan.to_json().contains("\"after_trace\""))
}

///|
test "plan and snapshot accessors prevent mutations through returned collections" {
  let plan = sample("{\"x\":{\"a\":1}}").plan_edit(
    "task-rest_bold.json",
    @trace.MetadataPatch::from_json("{\"set\":{\"x\":{\"a\":2}},\"remove\":[]}"),
  )
  let saved = plan.to_json()
  plan.before().data_paths().clear()
  plan.after().data_paths().clear()
  let entries = plan.impact().entries()
  let changes = entries[0].changes()
  changes[0].before_trace().clear()
  if changes[0].after_trace()[0].value() is Object(fields) {
    fields.clear()
  }
  if plan.after().resolve(scan()).get("x") is Some(Object(fields)) {
    fields.clear()
  }
  changes.clear()
  entries.clear()
  assert_eq(plan.to_json(), saved)
}

///|
test "empty and equivalent patches preserve prior behavior with no synthetic changes" {
  let index = sample("{\"x\":2.0,\"nested\":{\"b\":1,\"a\":2}}")
  for
    text in [
      "{\"set\":{},\"remove\":[]}", "{\"set\":{\"x\":2.0,\"nested\":{\"a\":2,\"b\":1}},\"remove\":[]}",
    ] {
    let plan = index.plan_edit(
      "task-rest_bold.json",
      @trace.MetadataPatch::from_json(text),
    )
    assert_eq(plan.impact().changed_count(), 0)
    assert_eq(plan.after().to_manifest_json(), index.to_manifest_json())
  }
}

///|
test "ambiguity remains indeterminate without concealing unaffected scans" {
  let anatomy = "sub-01/anat/sub-01_T1w.nii.gz"
  let index = @trace.DatasetIndex::from_manifest([scan(), anatomy], [
    @trace.SidecarInput::new("bold.json", "{\"x\":1}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":1}"),
  ])
  let plan = index.plan_edit(
    "bold.json",
    @trace.MetadataPatch::from_json("{\"set\":{\"x\":2},\"remove\":[]}"),
  )
  assert_eq(plan.impact().error_count(), 1)
  assert_eq(plan.impact().changed_count(), 0)
  assert_eq(plan.impact().entries().length(), 2)
  assert_true(plan.impact().entries()[0].kind() == @trace.ImpactKind::Unchanged)
  assert_true(
    plan.impact().entries()[1].kind() == @trace.ImpactKind::Unresolved,
  )
  assert_true(plan.to_json().contains("ambiguous_inheritance"))
}

///|
test "maximum metadata depth is accepted through the patch envelope and remains reloadable" {
  let nested = "[".repeat(63) + "0" + "]".repeat(63)
  let patch = @trace.MetadataPatch::from_json(
    "{\"set\":{\"x\":" + nested + "},\"remove\":[]}",
  )
  let plan = sample("{}").plan_edit("task-rest_bold.json", patch)
  assert_eq(plan.updated_sidecar_json(), "{\"x\":" + nested + "}")
  let restored = @trace.DatasetIndex::from_json(plan.after().to_manifest_json())
  assert_eq(restored.to_manifest_json(), plan.after().to_manifest_json())
  assert_eq(
    patch_error("{\"set\":{\"x\":[" + nested + "]},\"remove\":[]}"),
    "depth_limit",
  )
}

///|
test "merged metadata and aggregate snapshot limits reject oversized plans without baseline changes" {
  let part = "a".repeat(1100000)
  let index = sample("{\"keep\":\"" + part + "\"}")
  let baseline = index.to_manifest_json()
  let patch = @trace.MetadataPatch::from_json(
    "{\"set\":{\"add\":\"" + part + "\"},\"remove\":[]}",
  )
  let code = try {
    index.plan_edit("task-rest_bold.json", patch) |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
  }
  assert_eq(code, "input_limit")
  assert_eq(index.to_manifest_json(), baseline)
  let aggregate = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
    @trace.SidecarInput::new("T1w.json", "{\"keep\":\"" + part + "\"}"),
  ])
  let aggregate_code = try {
    aggregate.plan_edit("task-rest_bold.json", patch) |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
  }
  assert_eq(aggregate_code, "snapshot_limit")
  assert_eq(aggregate.resolve(scan()).to_json(), "{}")
}
