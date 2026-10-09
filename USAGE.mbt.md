# Executable library usage

```mbt check
///|
test "source coverage accounts for a completely shadowed parent" {
  let path = "sub-01/func/sub-01_task-rest_bold.nii"
  let index = @trace.DatasetIndex::from_manifest([path], [
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":1}"),
    @trace.SidecarInput::new(
      "sub-01/func/sub-01_task-rest_bold.json", "{\"x\":2}",
    ),
  ])
  let coverage = index.source_coverage()
  assert_eq(coverage.entries()[1].fully_shadowed_paths(), [path])
  assert_eq(coverage.entries()[1].winning_paths(), [])
  assert_eq(coverage.error_count(), 0)
}
```

Build a coordinated plan directly from typed MoonBit patches.

```mbt check
///|
test "typed coordinated edits expose the edited root without rewriting the baseline" {
  let path = "sub-01/func/sub-01_task-rest_bold.nii"
  let source = "sub-01/func/sub-01_task-rest_bold.json"
  let before = @trace.DatasetIndex::from_manifest([path], [
    @trace.SidecarInput::new("task-rest_bold.json", "{\"RepetitionTime\":2.0}"),
    @trace.SidecarInput::new(source, "{\"RepetitionTime\":4.0,\"Custom\":null}"),
  ])
  let root_patch = @trace.MetadataPatch::from_json(
    "{\"set\":{\"RepetitionTime\":3.0},\"remove\":[]}",
  )
  let local_patch = @trace.MetadataPatch::from_json(
    "{\"set\":{},\"remove\":[\"RepetitionTime\"]}",
  )
  let batch = @trace.EditBatch::from_patches([
    ("task-rest_bold.json", root_patch),
    (source, local_patch),
  ])
  let plan = before.plan_edits(batch)
  assert_eq(
    plan.after().resolve(path).to_json(),
    "{\"Custom\":null,\"RepetitionTime\":3.0}",
  )
  assert_eq(
    before.resolve(path).to_json(),
    "{\"Custom\":null,\"RepetitionTime\":4.0}",
  )
  assert_eq(plan.updated_sidecar_json(source), Some("{\"Custom\":null}"))
  assert_eq(plan.impact().changed_count(), 1)
  assert_eq(
    @trace.EditBatch::from_json(batch.to_json()).to_json(),
    batch.to_json(),
  )
}
```

Review bundles carry every input needed to reproduce a release decision.

```mbt check
///|
test "an offline review round trip retains exact changes and full evidence" {
  let path = "sub-01/func/sub-01_task-rest_bold.nii"
  let before = @trace.DatasetIndex::from_manifest([path], [
    @trace.SidecarInput::new("task-rest_bold.json", "{\"RepetitionTime\":2.0}"),
  ])
  let after = before
    .plan_edit(
      "task-rest_bold.json",
      @trace.MetadataPatch::from_json(
        "{\"set\":{\"RepetitionTime\":3.0},\"remove\":[]}",
      ),
    )
    .after()
  let captured = @trace.ReviewBundle::create(
    before,
    after,
    @trace.ReleasePolicy::AllChanges,
  )
  let replayed = @trace.ReviewBundle::from_json(captured.to_json())
  assert_eq(replayed.to_json(), captured.to_json())
  assert_true(
    replayed.report().decision() == @trace.ReleaseDecision::ChangesDetected,
  )
  assert_eq(replayed.report().affected_paths(), [path])
  assert_eq(replayed.before().to_manifest_json(), before.to_manifest_json())
  assert_eq(
    replayed.report().to_json(),
    before
    .compare(after)
    .release_check(@trace.ReleasePolicy::AllChanges)
    .to_json(),
  )
}
```

Plan a local removal and inspect its inherited result without changing the baseline.

```mbt check
///|
test "removing an override exposes its parent without mutating the baseline" {
  let path = "sub-01/func/sub-01_task-rest_bold.nii"
  let local_path = "sub-01/func/sub-01_task-rest_bold.json"
  let index = @trace.DatasetIndex::from_manifest([path], [
    @trace.SidecarInput::new("task-rest_bold.json", "{\"RepetitionTime\":2.0}"),
    @trace.SidecarInput::new(
      local_path, "{\"RepetitionTime\":3.0,\"Custom\":null}",
    ),
  ])
  let patch = @trace.MetadataPatch::from_json(
    "{\"set\":{},\"remove\":[\"RepetitionTime\"]}",
  )
  let plan = index.plan_edit(local_path, patch)
  assert_eq(plan.updated_sidecar_json(), "{\"Custom\":null}")
  assert_eq(
    plan.after().resolve(path).to_json(),
    "{\"Custom\":null,\"RepetitionTime\":2.0}",
  )
  assert_eq(
    index.resolve(path).to_json(),
    "{\"Custom\":null,\"RepetitionTime\":3.0}",
  )
  assert_eq(plan.impact().changed_count(), 1)
}
```

```mbt check
///|
test "a lower sidecar overrides one field without deleting another" {
  let path = "sub-01/func/sub-01_task-rest_bold.nii.gz"
  let index = @trace.DatasetIndex::from_manifest([path], [
    @trace.SidecarInput::new(
      "task-rest_bold.json", "{\"RepetitionTime\":2.0,\"EchoTime\":0.04}",
    ),
    @trace.SidecarInput::new(
      "sub-01/func/sub-01_task-rest_bold.json", "{\"RepetitionTime\":3.0}",
    ),
  ])
  let result = index.resolve(path)
  assert_eq(result.to_json(), "{\"EchoTime\":0.04,\"RepetitionTime\":3.0}")
  assert_eq(result.trace("RepetitionTime").length(), 2)
  assert_eq(
    result.trace("RepetitionTime")[1].path(),
    "sub-01/func/sub-01_task-rest_bold.json",
  )
  let reload = @trace.DatasetIndex::from_json(index.to_manifest_json())
  assert_eq(reload.resolve(path).to_report_json(), result.to_report_json())
}
```

Release checks consume existing comparison evidence without dropping it.

```mbt check
///|
test "release policy distinguishes shadowed provenance from effective changes" {
  let path = "sub-01/func/sub-01_task-rest_bold.nii"
  let before = @trace.DatasetIndex::from_manifest([path], [
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":1}"),
    @trace.SidecarInput::new(
      "sub-01/func/sub-01_task-rest_bold.json", "{\"x\":3}",
    ),
  ])
  let after = @trace.DatasetIndex::from_manifest([path], [
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":2}"),
    @trace.SidecarInput::new(
      "sub-01/func/sub-01_task-rest_bold.json", "{\"x\":3}",
    ),
  ])
  let impact = before.compare(after)
  let effective = impact.release_check(@trace.ReleasePolicy::EffectiveValues)
  assert_true(effective.decision() == @trace.ReleaseDecision::Pass)
  assert_true(
    impact.release_check(@trace.ReleasePolicy::AllChanges).decision() ==
    @trace.ReleaseDecision::ChangesDetected,
  )
  assert_eq(effective.impact().to_json(), impact.to_json())
}
```
