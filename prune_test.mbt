///|
test "prune proves whole metadata invariant and preserves empty source and provenance" {
  let path = "sub-01/func/sub-01_task-rest_run-01_bold.json"
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new(
      "bold.json", "{\"x\":2.0,\"unknown\":[null,9007199254740993]}",
    ),
    @trace.SidecarInput::new(path, "{\"x\":2.0}"),
  ])
  let before = index.to_manifest_json()
  let plan = index.plan_prune(path, ["x"])
  assert_true(
    plan
    .impact()
    .release_check(@trace.ReleasePolicy::EffectiveValues)
    .decision() ==
    @trace.ReleaseDecision::Pass,
  )
  assert_true(
    plan.impact().release_check(@trace.ReleasePolicy::AllChanges).decision() ==
    @trace.ReleaseDecision::ChangesDetected,
  )
  assert_true(plan.after().to_manifest_json().contains("\"metadata\":{}"))
  assert_eq(
    index.plan_edit(path, plan.patch()).after().to_manifest_json(),
    plan.after().to_manifest_json(),
  )
  assert_eq(
    @trace.MetadataPatch::from_json(plan.patch().to_json()).to_json(),
    plan.patch().to_json(),
  )
  assert_true(plan.to_json().contains("9007199254740993"))
  assert_eq(index.to_manifest_json(), before)
}

///|
test "prune rejects numeric spelling changes null disappearance and incomplete proof" {
  let path = "sub-01/func/sub-01_task-rest_run-01_bold.json"
  for
    (parent, child) in [
      ("{\"x\":2}", "{\"x\":2.0}"),
      ("{}", "{\"x\":null}"),
      ("{\"x\":[1,2]}", "{\"x\":[2,1]}"),
    ] {
    let index = @trace.DatasetIndex::from_manifest([scan()], [
      @trace.SidecarInput::new("bold.json", parent),
      @trace.SidecarInput::new(path, child),
    ])
    let rejected = try {
      ignore(index.plan_prune(path, ["x"]))
      false
    } catch {
      @trace.TraceError(d) => d.code == "unsafe_prune"
    }
    assert_true(rejected)
    assert_eq(
      index.resolve(scan()).get("x").unwrap().stringify(),
      @trace.DatasetIndex::from_manifest([scan()], [
        @trace.SidecarInput::new("bold.json", child),
      ])
      .resolve(scan())
      .get("x")
      .unwrap()
      .stringify(),
    )
  }
  let unmatched = @trace.DatasetIndex::from_manifest([], [
    @trace.SidecarInput::new("bold.json", "{\"x\":1}"),
  ])
  let rejected = try {
    ignore(unmatched.plan_prune("bold.json", ["x"]))
    false
  } catch {
    @trace.TraceError(d) => d.code == "unproven_prune"
  }
  assert_true(rejected)
}

///|
test "prune rejects empty duplicate absent fields and can recover" {
  let index = sample("{\"x\":1}")
  for fields in [[], ["x", "x"], ["missing"]] {
    let rejected = try {
      ignore(index.plan_prune("task-rest_bold.json", fields))
      false
    } catch {
      @trace.TraceError(_) => true
    }
    assert_true(rejected)
  }
  assert_eq(index.resolve(scan()).get("x").unwrap().stringify(), "1")
}

///|
test "prune checks every scan and rejects unresolved baseline inheritance" {
  let first = scan()
  let second = "sub-02/func/sub-02_task-rest_run-01_bold.nii.gz"
  let local_source = "sub-01/func/sub-01_task-rest_run-01_bold.json"
  let index = @trace.DatasetIndex::from_manifest([first, second], [
    @trace.SidecarInput::new("bold.json", "{\"x\":1}"),
    @trace.SidecarInput::new(local_source, "{\"x\":1}"),
    @trace.SidecarInput::new(
      "sub-02/func/sub-02_task-rest_bold.json", "{\"x\":1}",
    ),
    @trace.SidecarInput::new("sub-02/func/sub-02_run-01_bold.json", "{\"x\":1}"),
  ])
  let rejected = try {
    ignore(index.plan_prune(local_source, ["x"]))
    false
  } catch {
    @trace.TraceError(d) =>
      d.code == "unsafe_prune" && d.related.contains(second)
  }
  assert_true(rejected)
}
