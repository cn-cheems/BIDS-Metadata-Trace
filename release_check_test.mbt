///|
test "identity and empty snapshots pass both policies" {
  let empty = @trace.DatasetIndex::from_manifest([], [])
  let data = sample("{\"x\":9007199254740993}")
  for impact in [empty.compare(empty), data.compare(data)] {
    for policy in [@trace.ReleasePolicy::EffectiveValues, AllChanges] {
      let check = impact.release_check(policy)
      assert_true(check.decision() == @trace.ReleaseDecision::Pass)
      assert_true(check.policy() == policy)
      assert_eq(check.affected_paths(), [])
      assert_eq(check.unresolved_paths(), [])
      assert_eq(check.impact().to_json(), impact.to_json())
    }
  }
}

///|
test "effective policy passes shadowed edits but retains their complete evidence" {
  let before = sample("{\"x\":1.0}", override_text="{\"x\":3.0}")
  let after = sample("{\"x\":2.0}", override_text="{\"x\":3.0}")
  let impact = before.compare(after)
  let effective = impact.release_check(@trace.ReleasePolicy::EffectiveValues)
  let all = impact.release_check(@trace.ReleasePolicy::AllChanges)
  assert_true(effective.decision() == @trace.ReleaseDecision::Pass)
  assert_true(all.decision() == @trace.ReleaseDecision::ChangesDetected)
  assert_eq(all.affected_paths(), [scan()])
  assert_eq(effective.impact().to_json(), impact.to_json())
  assert_true(effective.to_json().contains("provenance_changed"))
  assert_true(effective.to_json().contains("1.0"))
  assert_true(effective.to_json().contains("2.0"))
  assert_true(effective.to_json().contains("3.0"))
}

///|
test "source-chain-only changes have explicit policy semantics" {
  let impact = sample("{}").compare(sample("{}", override_text="{}"))
  assert_true(
    impact.release_check(@trace.ReleasePolicy::EffectiveValues).decision() ==
    @trace.ReleaseDecision::Pass,
  )
  assert_true(
    impact.release_check(@trace.ReleasePolicy::AllChanges).decision() ==
    @trace.ReleaseDecision::ChangesDetected,
  )
}

///|
test "effective value edits include token differences and missing versus null" {
  for
    (old, new) in [
      ("{\"x\":9007199254740992}", "{\"x\":9007199254740993}"),
      ("{\"x\":2}", "{\"x\":2.0}"),
      ("{\"x\":0}", "{\"x\":-0}"),
      ("{}", "{\"x\":null}"),
      ("{\"x\":null}", "{}"),
    ] {
    for policy in [@trace.ReleasePolicy::EffectiveValues, AllChanges] {
      let impact = sample(old).compare(sample(new))
      let check = impact.release_check(policy)
      assert_true(check.decision() == @trace.ReleaseDecision::ChangesDetected)
      assert_eq(check.affected_paths(), [scan()])
      assert_eq(check.impact().to_json(), impact.to_json())
    }
  }
}

///|
test "scan additions and removals block even when no metadata is present" {
  let anatomy = "sub-01/anat/sub-01_T1w.nii"
  let before = @trace.DatasetIndex::from_manifest([anatomy], [])
  let after = @trace.DatasetIndex::from_manifest([scan()], [])
  for impact in [before.compare(after), after.compare(before)] {
    for policy in [@trace.ReleasePolicy::EffectiveValues, AllChanges] {
      let check = impact.release_check(policy)
      assert_eq(check.affected_paths(), [anatomy, scan()])
      assert_true(check.decision() == @trace.ReleaseDecision::ChangesDetected)
    }
  }
}

///|
test "indeterminate has priority without discarding determinate changes" {
  let anatomy = "sub-01/anat/sub-01_T1w.nii"
  let before = @trace.DatasetIndex::from_manifest([scan(), anatomy], [
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
    @trace.SidecarInput::new("T1w.json", "{\"x\":1}"),
  ])
  let after = @trace.DatasetIndex::from_manifest([scan(), anatomy], [
    @trace.SidecarInput::new("bold.json", "{}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
    @trace.SidecarInput::new("T1w.json", "{\"x\":2}"),
  ])
  for impact in [before.compare(after), after.compare(before)] {
    for policy in [@trace.ReleasePolicy::EffectiveValues, AllChanges] {
      let check = impact.release_check(policy)
      assert_true(check.decision() == @trace.ReleaseDecision::Indeterminate)
      assert_eq(check.affected_paths(), [anatomy])
      assert_eq(check.unresolved_paths(), [scan()])
      assert_true(check.to_json().contains("ambiguous_inheritance"))
      assert_true(check.to_json().contains("value_changed"))
      assert_eq(check.impact().to_json(), impact.to_json())
    }
  }
  assert_true(
    before
    .compare(before)
    .release_check(@trace.ReleasePolicy::AllChanges)
    .decision() ==
    @trace.ReleaseDecision::Pass,
  )
}

///|
test "release checks are deterministic defensive and never mutate impact" {
  let before = sample("{\"x\":1}")
  let after = sample("{\"x\":2}")
  let impact = before.compare(after)
  let saved = impact.to_json()
  let check = impact.release_check(@trace.ReleasePolicy::AllChanges)
  let json = check.to_json()
  check.affected_paths().clear()
  check.unresolved_paths().push("injected")
  check.impact().entries().clear()
  assert_eq(check.to_json(), json)
  assert_eq(impact.to_json(), saved)
  assert_eq(
    @trace.DatasetIndex::from_json(before.to_manifest_json())
    .compare(@trace.DatasetIndex::from_json(after.to_manifest_json()))
    .release_check(@trace.ReleasePolicy::AllChanges)
    .to_json(),
    json,
  )
}
