# Executable library usage

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
