///|
test "source inventory planning adds a local override and removal exposes inheritance" {
  let baseline = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new(
      "task-rest_bold.json", "{\"x\":2.0,\"unknown\":{\"a\":[null,true]}}",
    ),
  ])
  let source_path = "sub-01/func/sub-01_task-rest_run-01_bold.json"
  let add = @trace.SourceChanges::new(
    [@trace.SidecarInput::new(source_path, "{\"x\":3}")],
    [],
  )
  let plan = baseline.plan_sources(add)
  assert_true(plan.after().resolve(scan()).to_json().contains("\"x\":3"))
  assert_eq(
    baseline.resolve(scan()).to_json(),
    "{\"unknown\":{\"a\":[null,true]},\"x\":2.0}",
  )
  let remove = @trace.SourceChanges::new([], [source_path])
  let restored = plan.after().plan_sources(remove)
  assert_eq(restored.after().to_manifest_json(), baseline.to_manifest_json())
  assert_eq(plan.before().to_manifest_json(), baseline.to_manifest_json())
  assert_eq(plan.impact().changed_count(), 1)
}

///|
test "atomic source rename retains values complete snapshots and replayable evidence" {
  let baseline = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new(
      "task-rest_bold.json", "{\"x\":9007199254740993,\"y\":-0,\"n\":null}",
    ),
  ])
  let changes = @trace.SourceChanges::from_json(
    "{\"add\":[{\"path\":\"bold.json\",\"metadata\":{\"x\":9007199254740993,\"y\":-0,\"n\":null}}],\"remove\":[\"task-rest_bold.json\"]}",
  )
  let plan = baseline.plan_sources(changes)
  assert_eq(
    plan.after().resolve(scan()).to_json(),
    baseline.resolve(scan()).to_json(),
  )
  assert_true(
    plan
    .impact()
    .release_check(@trace.ReleasePolicy::EffectiveValues)
    .decision() ==
    @trace.ReleaseDecision::Pass,
  )
  assert_eq(
    changes.to_json(),
    @trace.SourceChanges::from_json(changes.to_json()).to_json(),
  )
  assert_eq(
    plan.to_json(),
    baseline
    .plan_sources(@trace.SourceChanges::from_json(changes.to_json()))
    .to_json(),
  )
  let bundle = @trace.ReviewBundle::create(
    baseline,
    plan.after(),
    @trace.ReleasePolicy::AllChanges,
  )
  assert_eq(
    @trace.ReviewBundle::from_json(bundle.to_json()).to_json(),
    bundle.to_json(),
  )
  assert_true(plan.to_json().contains("9007199254740993"))
  assert_true(plan.to_json().contains("\"y\":-0"))
}

///|
test "source planning retains empty unused sources and ambiguity without guessed impact" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
    @trace.SidecarInput::new("task-other_bold.json", "{\"unused\":true}"),
  ])
  let unused = index.plan_sources(
    @trace.SourceChanges::new([], ["task-other_bold.json"]),
  )
  assert_eq(unused.impact().changed_count(), 0)
  assert_true(unused.to_json().contains("\"unused\":true"))
  let ambiguous = index.plan_sources(
    @trace.SourceChanges::new([@trace.SidecarInput::new("bold.json", "{}")], []),
  )
  assert_eq(ambiguous.impact().error_count(), 1)
  assert_true(ambiguous.to_json().contains("ambiguous_inheritance"))
  let fixed = ambiguous
    .after()
    .plan_sources(@trace.SourceChanges::new([], ["bold.json"]))
  assert_eq(fixed.after().audit_all().error_count(), 0)
  assert_eq(fixed.impact().error_count(), 1)
}

///|
fn source_changes_error(text : String) -> String {
  try {
    ignore(@trace.SourceChanges::from_json(text))
    "accepted"
  } catch {
    @trace.TraceError(d) => d.code
  }
}

///|
test "source controls reject malformed unsupported duplicate and conflicting inputs" {
  for
    text in [
      "[]", "{}", "{\"add\":[],\"remove\":null}", "{\"add\":[{}],\"remove\":[]}",
      "{\"add\":[],\"remove\":[2]}",
    ] {
    assert_eq(source_changes_error(text), "invalid_source_changes")
  }
  assert_eq(
    source_changes_error("{\"add\":[],\"remove\":[],\"other\":true}"),
    "unknown_source_change_field",
  )
  assert_eq(
    source_changes_error("{\"add\":[],\"add\":[],\"remove\":[]}"),
    "duplicate_json_key",
  )
  assert_eq(
    source_changes_error(
      "{\"add\":[{\"path\":\"bold.json\",\"metadata\":{\"x\":1,\"x\":2}}],\"remove\":[]}",
    ),
    "duplicate_json_key",
  )
  assert_eq(
    source_changes_error(
      "{\"add\":[],\"remove\":[\"bold.json\",\"bold.json\"]}",
    ),
    "source_change_conflict",
  )
  assert_eq(
    source_changes_error(
      "{\"add\":[{\"path\":\"bold.json\",\"metadata\":{}}],\"remove\":[\"bold.json\"]}",
    ),
    "source_change_conflict",
  )
  assert_eq(
    source_changes_error("{\"add\":[],\"remove\":[\"events.json\"]}"),
    "unsupported_suffix",
  )
}

///|
test "invalid baseline operations fail atomically and leave prior behavior unchanged" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":2.0}"),
  ])
  let original = index.to_manifest_json()
  for
    changes in [
      @trace.SourceChanges::new([], ["bold.json"]),
      @trace.SourceChanges::new(
        [@trace.SidecarInput::new("task-rest_bold.json", "{}")],
        [],
      ),
    ] {
    try {
      ignore(index.plan_sources(changes))
      fail("invalid operation accepted")
    } catch {
      @trace.TraceError(d) =>
        assert_true(
          ["unknown_sidecar_path", "existing_sidecar_path"].contains(d.code),
        )
      error => fail(error.to_string())
    }
    assert_eq(index.to_manifest_json(), original)
  }
  let empty = index.plan_sources(@trace.SourceChanges::new([], []))
  assert_eq(empty.after().to_manifest_json(), original)
  assert_eq(empty.impact().changed_count(), 0)
}

///|
test "source changes normalize order copy input lists and honor count depth size boundaries" {
  let nested = "{\"x\":" + "[".repeat(63) + "-0" + "]".repeat(63) + "}"
  let additions = [
    @trace.SidecarInput::new("task-rest_bold.json", nested),
    @trace.SidecarInput::new("T1w.json", "{}"),
  ]
  let removals = ["dwi.json", "bold.json"]
  let changes = @trace.SourceChanges::new(additions, removals)
  assert_eq(
    changes.to_json(),
    @trace.SourceChanges::new(additions.rev(), removals.rev()).to_json(),
  )
  additions.clear()
  removals.clear()
  assert_true(changes.to_json().contains("-0"))
  assert_eq(
    @trace.SourceChanges::from_json(changes.to_json()).to_json(),
    changes.to_json(),
  )
  let paths = Array::makei(256, i => "task-t" + i.to_string() + "_bold.json")
  ignore(@trace.SourceChanges::new([], paths))
  paths.push("task-extra_bold.json")
  try {
    ignore(@trace.SourceChanges::new([], paths))
    fail("count accepted")
  } catch {
    @trace.TraceError(d) => assert_eq(d.code, "source_changes_limit")
    error => fail(error.to_string())
  }
  assert_eq(source_changes_error(" ".repeat(2097153)), "input_limit")
  assert_eq(
    source_changes_error("[".repeat(68) + "0" + "]".repeat(68)),
    "depth_limit",
  )
}

///|
test "source planning rejects final collisions and overflow but allows atomic shrink grow" {
  let large = "{\"x\":\"" + "a".repeat(1100000) + "\"}"
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("task-rest_bold.json", large),
  ])
  try {
    ignore(
      index.plan_sources(
        @trace.SourceChanges::new(
          [@trace.SidecarInput::new("bold.json", large)],
          [],
        ),
      ),
    )
    fail("oversized final snapshot accepted")
  } catch {
    @trace.TraceError(d) => assert_eq(d.code, "snapshot_limit")
    error => fail(error.to_string())
  }
  let rename = index.plan_sources(
    @trace.SourceChanges::new([@trace.SidecarInput::new("bold.json", large)], [
      "task-rest_bold.json",
    ]),
  )
  assert_eq(
    rename.after().resolve(scan()).to_json(),
    index.resolve(scan()).to_json(),
  )
  try {
    ignore(
      index.plan_sources(
        @trace.SourceChanges::new(
          [@trace.SidecarInput::new("task-REST_bold.json", "{}")],
          [],
        ),
      ),
    )
    fail("case collision accepted")
  } catch {
    @trace.TraceError(d) => assert_eq(d.code, "path_collision")
    error => fail(error.to_string())
  }
  assert_eq(index.audit_all().error_count(), 0)
}
