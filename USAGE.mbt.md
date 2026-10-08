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
