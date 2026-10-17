///|
fn scan_changes_error(text : String) -> String {
  try {
    ignore(@trace.ScanChanges::from_json(text))
    "accepted"
  } catch {
    @trace.TraceError(d) => d.code
  }
}

///|
test "scan inventory planning adds inherited scans removes indexed scans and retains all sources" {
  let second = "sub-01/func/sub-01_task-rest_run-02_bold.nii.gz"
  let local_source = "sub-01/func/sub-01_task-rest_run-01_bold.json"
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new(
      "task-rest_bold.json", "{\"x\":2.0,\"unknown\":{\"large\":9007199254740993}}",
    ),
    @trace.SidecarInput::new(local_source, "{\"x\":-0}"),
    @trace.SidecarInput::new("dwi.json", "{}"),
  ])
  let before = index.to_manifest_json()
  let plan = index.plan_scans(@trace.ScanChanges::new([second], [scan()]))
  assert_eq(plan.after().data_paths(), [second])
  assert_eq(plan.after().resolve(second).get("x").unwrap().stringify(), "2.0")
  assert_eq(plan.before().resolve(scan()).get("x").unwrap().stringify(), "-0")
  assert_eq(plan.impact().changed_count(), 2)
  assert_eq(plan.impact().error_count(), 0)
  assert_true(plan.after_coverage().unmatched_paths().contains(local_source))
  assert_true(plan.after_coverage().unmatched_paths().contains("dwi.json"))
  assert_true(!plan.before_coverage().unmatched_paths().contains(local_source))
  assert_true(plan.to_json().contains("9007199254740993"))
  assert_true(plan.to_json().contains("\"x\":-0"))
  assert_true(plan.to_json().contains("\"kind\":\"removed\""))
  assert_true(plan.to_json().contains("\"kind\":\"added\""))
  assert_eq(plan.before().to_manifest_json(), before)
  assert_eq(index.to_manifest_json(), before)
}

///|
test "removing every scan preserves unmatched unknown metadata and replay evidence" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("bold.json", "{\"unknown\":[null,1e999,2.0]}"),
    @trace.SidecarInput::new("dwi.json", "{}"),
  ])
  let plan = index.plan_scans(@trace.ScanChanges::new([], [scan()]))
  assert_eq(plan.after().data_paths(), [])
  assert_eq(plan.after_coverage().unmatched_paths().length(), 2)
  assert_true(plan.after().to_manifest_json().contains("[null,1e999,2.0]"))
  let bundle = @trace.ReviewBundle::create(
    index,
    plan.after(),
    @trace.ReleasePolicy::EffectiveValues,
  )
  let replay = @trace.ReviewBundle::from_json(bundle.to_json())
  assert_true(
    replay.report().decision() == @trace.ReleaseDecision::ChangesDetected,
  )
  assert_eq(replay.to_json(), bundle.to_json())
  assert_eq(
    @trace.DatasetIndex::from_json(plan.after().to_manifest_json()).to_manifest_json(),
    plan.after().to_manifest_json(),
  )
}

///|
test "added and removed ambiguous scans retain errors rather than becoming successful inventory edits" {
  let sources = [
    @trace.SidecarInput::new("bold.json", "{}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
  ]
  let empty = @trace.DatasetIndex::from_manifest([], sources)
  let add = empty.plan_scans(@trace.ScanChanges::new([scan()], []))
  assert_eq(add.impact().error_count(), 1)
  assert_eq(add.after_coverage().error_count(), 1)
  assert_true(add.to_json().contains("ambiguous_inheritance"))
  let remove = add.after().plan_scans(@trace.ScanChanges::new([], [scan()]))
  assert_eq(remove.impact().error_count(), 1)
  assert_eq(remove.before_coverage().error_count(), 1)
  assert_eq(remove.after_coverage().error_count(), 0)
  assert_true(remove.to_json().contains("ambiguous_inheritance"))
  assert_eq(empty.data_paths(), [])
}

///|
test "scan operations reject malformed unknown duplicate conflicting and unsupported inputs" {
  for
    text in [
      "[]", "{}", "{\"add\":[],\"remove\":null}", "{\"add\":[2],\"remove\":[]}",
    ] {
    assert_eq(scan_changes_error(text), "invalid_scan_changes")
  }
  assert_eq(
    scan_changes_error("{\"add\":[],\"remove\":[],\"sidecars\":[]}"),
    "unknown_scan_change_field",
  )
  assert_eq(
    scan_changes_error("{\"add\":[],\"\\u0061dd\":[],\"remove\":[]}"),
    "duplicate_json_key",
  )
  let encoded = Json::string(scan()).stringify()
  assert_eq(
    scan_changes_error(
      "{\"add\":[" + encoded + "],\"remove\":[" + encoded + "]}",
    ),
    "scan_change_conflict",
  )
  assert_eq(
    scan_changes_error(
      "{\"add\":[" + encoded + "," + encoded + "],\"remove\":[]}",
    ),
    "scan_change_conflict",
  )
  assert_eq(
    scan_changes_error("{\"add\":[],\"remove\":[\"../outside.nii\"]}"),
    "invalid_path",
  )
  assert_eq(
    scan_changes_error(
      "{\"add\":[\"sub-01/func/sub-01_events.tsv\"],\"remove\":[]}",
    ),
    "unsupported_extension",
  )
  assert_eq(
    scan_changes_error("{\"add\":[\"bold.json\"],\"remove\":[]}"),
    "unsupported_extension",
  )
  assert_eq(scan_changes_error("{\"add\":[],\"remove\":[[]]}"), "depth_limit")
}

///|
test "failed scan planning preserves baseline and allows recovery with an identity plan" {
  let index = sample("{\"x\":2.0}")
  let before = index.to_manifest_json()
  let absent = "sub-02/func/sub-02_task-rest_bold.nii"
  for
    (changes, expected) in [
      (@trace.ScanChanges::new([], [absent]), "unknown_data_path"),
      (@trace.ScanChanges::new([scan()], []), "existing_data_path"),
      (
        @trace.ScanChanges::new(
          ["sub-01/func/sub-01_task-REST_run-02_bold.nii"],
          [],
        ),
        "label_collision",
      ),
    ] {
    try {
      ignore(index.plan_scans(changes))
      fail("invalid plan accepted")
    } catch {
      @trace.TraceError(d) => assert_eq(d.code, expected)
      error => fail(error.to_string())
    }
    assert_eq(index.to_manifest_json(), before)
  }
  let identity = index.plan_scans(@trace.ScanChanges::new([], []))
  assert_eq(identity.after().to_manifest_json(), before)
  assert_eq(identity.impact().changed_count(), 0)
  assert_eq(
    identity.before_coverage().to_json(),
    identity.after_coverage().to_json(),
  )
}

///|
test "scan control round trips permutation and copied inputs produce deterministic plans" {
  let second = "sub-01/func/sub-01_task-rest_run-02_bold.nii"
  let third = "sub-01/func/sub-01_task-rest_run-03_bold.nii"
  let add = [third, second]
  let remove = [scan()]
  let changes = @trace.ScanChanges::new(add, remove)
  let equivalent = @trace.ScanChanges::new(add.rev(), remove.rev())
  add.clear()
  remove.clear()
  assert_eq(changes.to_json(), equivalent.to_json())
  assert_eq(
    @trace.ScanChanges::from_json(changes.to_json()).to_json(),
    changes.to_json(),
  )
  let index = sample("{\"x\":-0}")
  let plan = index.plan_scans(changes)
  assert_eq(plan.to_json(), index.plan_scans(equivalent).to_json())
  assert_eq(
    @trace.DatasetIndex::from_json(index.to_manifest_json())
    .plan_scans(@trace.ScanChanges::from_json(changes.to_json()))
    .to_json(),
    plan.to_json(),
  )
  plan.after().data_paths().clear()
  plan.after_coverage().entries().clear()
  assert_eq(plan.after().data_paths(), [second, third])
}

///|
test "scan changes enforce combined operation input and canonical size limits" {
  let paths = Array::makei(256, i => {
    "sub-01/func/sub-01_task-rest_run-" + i.to_string() + "_bold.nii"
  })
  ignore(@trace.ScanChanges::new(paths, []))
  try {
    ignore(@trace.ScanChanges::new(paths, [scan()]))
    fail("count accepted")
  } catch {
    @trace.TraceError(d) => assert_eq(d.code, "scan_changes_limit")
    error => fail(error.to_string())
  }
  assert_eq(scan_changes_error(" ".repeat(2097153)), "input_limit")
  assert_eq(scan_changes_error("[[[0]]]"), "depth_limit")
  ignore(@trace.ScanChanges::new([], []))
}

///|
test "scan planning rejects final overflow but permits atomic inventory shrink grow" {
  let old = "sub-01/func/sub-01_task-rest_run-12345678901234567890_bold.nii"
  let next = "sub-01/func/sub-01_task-rest_run-2_bold.nii"
  let empty = @trace.DatasetIndex::from_manifest([old], [
    @trace.SidecarInput::new("bold.json", "{\"padding\":\"\"}"),
  ])
  let pad = "a".repeat(2097152 - empty.to_manifest_json().length())
  let index = @trace.DatasetIndex::from_manifest([old], [
    @trace.SidecarInput::new("bold.json", "{\"padding\":\"" + pad + "\"}"),
  ])
  assert_eq(index.to_manifest_json().length(), 2097152)
  try {
    ignore(index.plan_scans(@trace.ScanChanges::new([next], [])))
    fail("overflow accepted")
  } catch {
    @trace.TraceError(d) => assert_eq(d.code, "snapshot_limit")
    error => fail(error.to_string())
  }
  let plan = index.plan_scans(@trace.ScanChanges::new([next], [old]))
  assert_eq(plan.after().data_paths(), [next])
  assert_eq(plan.after().resolve(next).to_json(), index.resolve(old).to_json())
  assert_eq(index.data_paths(), [old])
}
