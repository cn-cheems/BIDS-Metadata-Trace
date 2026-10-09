///|
fn batch_error(text : String) -> String {
  try {
    @trace.EditBatch::from_json(text) |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
  }
}

///|
fn coordinated_batch() -> @trace.EditBatch raise @trace.TraceError {
  @trace.EditBatch::from_json(
    "{\"edits\":[{\"path\":\"task-rest_bold.json\",\"set\":{\"x\":2.0},\"remove\":[]},{\"path\":\"sub-01/func/sub-01_task-rest_run-01_bold.json\",\"set\":{},\"remove\":[\"x\"]}]}",
  )
}

///|
test "canonical batch size accepts its exact boundary and rejects one additional unit" {
  let small = @trace.MetadataPatch::from_json(
    "{\"set\":{\"x\":\"a\"},\"remove\":[]}",
  )
  let overhead = @trace.EditBatch::from_patches([("bold.json", small)])
    .to_json()
    .length() -
    1
  let payload = "a".repeat(2097152 - overhead)
  let patch = @trace.MetadataPatch::from_json(
    "{\"set\":{\"x\":\"" + payload + "\"},\"remove\":[]}",
  )
  let batch = @trace.EditBatch::from_patches([("bold.json", patch)])
  assert_eq(batch.to_json().length(), 2097152)
  assert_eq(
    @trace.EditBatch::from_json(batch.to_json()).to_json(),
    batch.to_json(),
  )
  let larger = @trace.MetadataPatch::from_json(
    "{\"set\":{\"x\":\"" + payload + "a\"},\"remove\":[]}",
  )
  let code = try {
    @trace.EditBatch::from_patches([("bold.json", larger)]) |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
  }
  assert_eq(code, "input_limit")
}

///|
test "coordinated root assignment and local removal share one baseline and impact" {
  let before = sample(
    "{\"x\":1.0,\"Future\":[9007199254740993,-0]}",
    override_text="{\"x\":3.0,\"Keep\":null}",
  )
  let saved = before.to_manifest_json()
  let plan = before.plan_edits(coordinated_batch())
  assert_eq(
    plan.after().resolve(scan()).to_json(),
    "{\"Future\":[9007199254740993,-0],\"Keep\":null,\"x\":2.0}",
  )
  assert_eq(
    plan.updated_sidecar_json("sub-01/func/sub-01_task-rest_run-01_bold.json"),
    Some("{\"Keep\":null}"),
  )
  assert_eq(plan.updated_sidecar_json("not-edited"), None)
  assert_eq(plan.impact().changed_count(), 1)
  assert_eq(plan.impact().entries()[0].changes()[0].before_json(), Some("3.0"))
  assert_eq(plan.impact().entries()[0].changes()[0].after_json(), Some("2.0"))
  assert_eq(plan.before().to_manifest_json(), saved)
  assert_eq(before.to_manifest_json(), saved)
  assert_eq(plan.impact().to_json(), before.compare(plan.after()).to_json())
  assert_true(plan.to_json().contains("9007199254740993"))
}

///|
test "batch permutation canonicalization round trips and recovered snapshot agree" {
  let first = coordinated_batch()
  let reverse = @trace.EditBatch::from_json(
    "{\"edits\":[{\"remove\":[\"x\"],\"set\":{},\"path\":\"sub-01/func/sub-01_task-rest_run-01_bold.json\"},{\"remove\":[],\"set\":{\"x\":2.0},\"path\":\"task-rest_bold.json\"}]}",
  )
  assert_eq(first.to_json(), reverse.to_json())
  assert_eq(
    @trace.EditBatch::from_json(first.to_json()).to_json(),
    first.to_json(),
  )
  let before = sample("{\"x\":1.0}", override_text="{\"x\":3.0}")
  let plan = before.plan_edits(first)
  assert_eq(plan.to_json(), before.plan_edits(reverse).to_json())
  let reload = @trace.DatasetIndex::from_json(plan.after().to_manifest_json())
  assert_eq(before.compare(reload).to_json(), plan.impact().to_json())
  let review = @trace.ReviewBundle::create(
    before,
    reload,
    @trace.ReleasePolicy::AllChanges,
  )
  assert_eq(
    @trace.ReviewBundle::from_json(review.to_json()).report().impact().to_json(),
    plan.impact().to_json(),
  )
}

///|
test "all batch shapes controls duplicates and contradictions are explicit failures" {
  assert_eq(batch_error(" ".repeat(2097153)), "input_limit")
  for
    (text, expected) in [
      ("[]", "invalid_edit_batch"),
      ("{}", "invalid_edit_batch"),
      ("{\"edits\":{}}", "invalid_edit_batch"),
      ("{\"edits\":[],\"extra\":1}", "unknown_edit_batch_field"),
      ("{\"edits\":[null]}", "invalid_edit_batch"),
      (
        "{\"edits\":[{\"path\":1,\"set\":{},\"remove\":[]}]}", "invalid_edit_batch",
      ),
      (
        "{\"edits\":[{\"path\":\"bold.json\",\"set\":{}}]}", "invalid_edit_batch",
      ),
      (
        "{\"edits\":[{\"path\":\"bold.json\",\"set\":{},\"remove\":[],\"other\":null}]}",
        "unknown_edit_batch_field",
      ),
      (
        "{\"edits\":[{\"path\":\"bold.json\",\"set\":[],\"remove\":[]}]}", "invalid_patch",
      ),
      (
        "{\"edits\":[{\"path\":\"bold.json\",\"set\":{\"x\":null},\"remove\":[\"x\"]}]}",
        "patch_conflict",
      ),
      (
        "{\"edits\":[{\"path\":\"bold.json\",\"set\":{},\"remove\":[\"x\",\"x\"]}]}",
        "duplicate_remove",
      ),
      ("{\"edits\":[],\"edits\":[]}", "duplicate_json_key"),
      (
        "{\"edits\":[{\"path\":\"bold.json\",\"set\":{\"x\":1,\"\\u0078\":2},\"remove\":[]}]}",
        "duplicate_json_key",
      ),
      (
        "{\"edits\":[{\"path\":\"bold.json\",\"set\":{},\"remove\":[]},{\"path\":\"bold.json\",\"set\":{},\"remove\":[]}]}",
        "duplicate_edit_path",
      ),
      ("{", "invalid_json"),
    ] {
    assert_eq(batch_error(text), expected)
  }
}

///|
test "later invalid source or removal never returns a partial plan and can be retried" {
  let before = sample("{\"x\":1}", override_text="{\"x\":3}")
  let saved = before.to_manifest_json()
  for
    (path, removals, expected) in [
      ("task-z_bold.json", "[]", "unknown_sidecar_path"),
      ("task-rest_bold.json", "[\"absent\"]", "missing_metadata_field"),
    ] {
    let batch = @trace.EditBatch::from_json(
      "{\"edits\":[{\"path\":\"sub-01/func/sub-01_task-rest_run-01_bold.json\",\"set\":{\"x\":5},\"remove\":[]},{\"path\":\"" +
      path +
      "\",\"set\":{},\"remove\":" +
      removals +
      "}]}",
    )
    let code = try {
      before.plan_edits(batch) |> ignore
      "success"
    } catch {
      @trace.TraceError(d) => {
        assert_eq(d.path, path)
        d.code
      }
    }
    assert_eq(code, expected)
    assert_eq(before.to_manifest_json(), saved)
  }
  assert_eq(
    before
    .plan_edits(coordinated_batch())
    .after()
    .resolve(scan())
    .get("x")
    .unwrap()
    .stringify(),
    "2.0",
  )
  assert_eq(before.to_manifest_json(), saved)
}

///|
test "single batch edit preserves existing single plan behavior and empty batch identity" {
  let before = sample("{\"x\":2.0,\"Keep\":null}")
  let patch = @trace.MetadataPatch::from_json(
    "{\"set\":{\"x\":3.0},\"remove\":[]}",
  )
  let single = before.plan_edit("task-rest_bold.json", patch)
  let batch = before.plan_edits(
    @trace.EditBatch::from_json(
      "{\"edits\":[{\"path\":\"task-rest_bold.json\",\"set\":{\"x\":3.0},\"remove\":[]}]}",
    ),
  )
  assert_eq(single.after().to_manifest_json(), batch.after().to_manifest_json())
  assert_eq(
    single.updated_sidecar_json(),
    batch.updated_sidecar_json("task-rest_bold.json").unwrap(),
  )
  assert_eq(single.impact().to_json(), batch.impact().to_json())
  let empty = before.plan_edits(@trace.EditBatch::from_json("{\"edits\":[]}"))
  assert_eq(empty.after().to_manifest_json(), before.to_manifest_json())
  assert_eq(empty.sidecar_paths(), [])
  assert_eq(empty.impact().changed_count(), 0)
}

///|
test "batch accessors cannot mutate sources results or evidence" {
  let batch = coordinated_batch()
  let saved_batch = batch.to_json()
  batch.sidecar_paths().clear()
  assert_eq(batch.to_json(), saved_batch)
  let plan = sample("{\"x\":1}", override_text="{\"x\":3}").plan_edits(batch)
  let saved = plan.to_json()
  plan.sidecar_paths().clear()
  plan.after().data_paths().clear()
  plan.impact().entries().clear()
  plan.after().resolve(scan()).trace("x").clear()
  assert_eq(plan.to_json(), saved)
}

///|
test "metadata maximum depth and numeric token differences survive batch envelopes" {
  let nested = "[".repeat(63) + "-0" + "]".repeat(63)
  let batch = @trace.EditBatch::from_json(
    "{\"edits\":[{\"path\":\"task-rest_bold.json\",\"set\":{\"deep\":" +
    nested +
    ",\"x\":9007199254740993},\"remove\":[]}]}",
  )
  let before = sample("{\"x\":9007199254740992}")
  let plan = before.plan_edits(batch)
  assert_true(
    plan.updated_sidecar_json("task-rest_bold.json").unwrap().contains(nested),
  )
  assert_eq(
    @trace.EditBatch::from_json(batch.to_json()).to_json(),
    batch.to_json(),
  )
  assert_eq(
    @trace.DatasetIndex::from_json(plan.after().to_manifest_json()).to_manifest_json(),
    plan.after().to_manifest_json(),
  )
  assert_eq(
    plan.impact().entries()[0].changes()[1].after_json(),
    Some("9007199254740993"),
  )
  assert_eq(
    batch_error(
      "{\"edits\":[{\"path\":\"task-rest_bold.json\",\"set\":{\"deep\":[" +
      nested +
      "]},\"remove\":[]}] }",
    ),
    "depth_limit",
  )
}

///|
test "batch counts accept exactly 256 and reject 257 entries without truncation" {
  let entries = Array::makei(256, i => {
    "{\"path\":\"task-t" +
    i.to_string() +
    "_bold.json\",\"set\":{},\"remove\":[]}"
  })
  let text = "{\"edits\":[" + entries.join(",") + "]}"
  let batch = @trace.EditBatch::from_json(text)
  assert_eq(batch.sidecar_paths().length(), 256)
  entries.push(
    "{\"path\":\"task-overflow_bold.json\",\"set\":{},\"remove\":[]}",
  )
  assert_eq(
    batch_error("{\"edits\":[" + entries.join(",") + "]}"),
    "edit_batch_limit",
  )
  let inputs = batch
    .sidecar_paths()
    .map(path => @trace.SidecarInput::new(path, "{}"))
  let before = @trace.DatasetIndex::from_manifest([], inputs)
  assert_eq(before.plan_edits(batch).sidecar_paths().length(), 256)
}

///|
test "combined shrink and grow validate only the final reloadable snapshot" {
  let payload = "a".repeat(1100000)
  let before = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("bold.json", "{}"),
    @trace.SidecarInput::new("T1w.json", "{\"old\":\"" + payload + "\"}"),
  ])
  let grow = @trace.MetadataPatch::from_json(
    "{\"set\":{\"new\":\"" + payload + "\"},\"remove\":[]}",
  )
  let code = try {
    before.plan_edit("bold.json", grow) |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
  }
  assert_eq(code, "snapshot_limit")
  let batch = @trace.EditBatch::from_json(
    "{\"edits\":[{\"path\":\"bold.json\",\"set\":{\"new\":\"" +
    payload +
    "\"},\"remove\":[]},{\"path\":\"T1w.json\",\"set\":{},\"remove\":[\"old\"]}]}",
  )
  let plan = before.plan_edits(batch)
  assert_eq(plan.updated_sidecar_json("T1w.json"), Some("{}"))
  assert_eq(
    @trace.DatasetIndex::from_json(plan.after().to_manifest_json()).to_manifest_json(),
    plan.after().to_manifest_json(),
  )
  assert_true(before.to_manifest_json().contains("\"old\""))
  let too_large = @trace.EditBatch::from_json(
    "{\"edits\":[{\"path\":\"bold.json\",\"set\":{\"new\":\"" +
    payload +
    "\"},\"remove\":[]}]}",
  )
  let failure = try {
    before.plan_edits(too_large) |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
  }
  assert_eq(failure, "snapshot_limit")
  let merged = sample("{\"old\":\"" + payload + "\"}")
  let source_limit = try {
    merged.plan_edits(
      @trace.EditBatch::from_patches([("task-rest_bold.json", grow)]),
    )
    |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
  }
  assert_eq(source_limit, "input_limit")
}

///|
test "typed batch construction copies its list rejects duplicates and guarantees reloadability" {
  let patch = @trace.MetadataPatch::from_json(
    "{\"set\":{\"x\":2.0},\"remove\":[]}",
  )
  let inputs = [("task-rest_bold.json", patch)]
  let batch = @trace.EditBatch::from_patches(inputs)
  inputs.clear()
  assert_eq(batch.sidecar_paths(), ["task-rest_bold.json"])
  assert_eq(
    @trace.EditBatch::from_json(batch.to_json()).to_json(),
    batch.to_json(),
  )
  let code = try {
    @trace.EditBatch::from_patches([
      ("task-rest_bold.json", patch),
      ("task-rest_bold.json", patch),
    ])
    |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
  }
  assert_eq(code, "duplicate_edit_path")
  let large = @trace.MetadataPatch::from_json(
    "{\"set\":{\"x\":\"" + "a".repeat(1100000) + "\"},\"remove\":[]}",
  )
  let limit = try {
    @trace.EditBatch::from_patches([("bold.json", large), ("T1w.json", large)])
    |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
  }
  assert_eq(limit, "input_limit")
  assert_eq(
    sample("{}").plan_edits(batch).after().resolve(scan()).to_json(),
    "{\"x\":2.0}",
  )
}

///|
test "batch reports retain ambiguity without hiding unaffected scans" {
  let anatomy = "sub-01/anat/sub-01_T1w.nii"
  let before = @trace.DatasetIndex::from_manifest([scan(), anatomy], [
    @trace.SidecarInput::new("bold.json", "{}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
    @trace.SidecarInput::new("T1w.json", "{\"x\":1}"),
  ])
  let batch = @trace.EditBatch::from_json(
    "{\"edits\":[{\"path\":\"bold.json\",\"set\":{\"x\":2},\"remove\":[]},{\"path\":\"T1w.json\",\"set\":{\"x\":2},\"remove\":[]}]}",
  )
  let plan = before.plan_edits(batch)
  assert_eq(plan.impact().error_count(), 1)
  assert_eq(plan.impact().changed_count(), 1)
  assert_true(plan.to_json().contains("ambiguous_inheritance"))
  assert_true(
    plan.impact().release_check(@trace.ReleasePolicy::AllChanges).decision() ==
    @trace.ReleaseDecision::Indeterminate,
  )
}
