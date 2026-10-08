///|
test "T1w and DWI profiles preserve arbitrary metadata and do not cross suffixes" {
  let t1 = "sub-01/anat/sub-01_T1w.nii.gz"
  let dwi = "sub-01/dwi/sub-01_dir-AP_dwi.nii"
  let index = @trace.DatasetIndex::from_manifest([t1, dwi], [
    @trace.SidecarInput::new(
      "T1w.json", "{\"Manufacturer\":\"Example\",\"Unknown\":{\"x\":true}}",
    ),
    @trace.SidecarInput::new(
      "dir-AP_dwi.json", "{\"PhaseEncodingDirection\":\"j-\"}",
    ),
  ])
  assert_eq(index.resolve(dwi).to_json(), "{\"PhaseEncodingDirection\":\"j-\"}")
  assert_eq(
    index.resolve(t1).to_json(),
    "{\"Manufacturer\":\"Example\",\"Unknown\":{\"x\":true}}",
  )
}

///|
test "participant metadata is isolated and similarly prefixed paths do not leak" {
  let first = "sub-01/func/sub-01_task-rest_bold.nii"
  let other = "sub-010/func/sub-010_task-rest_bold.nii"
  let index = @trace.DatasetIndex::from_manifest([other, first], [
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":1}"),
    @trace.SidecarInput::new("sub-01/sub-01_task-rest_bold.json", "{\"x\":2}"),
  ])
  assert_eq(index.resolve(first).to_json(), "{\"x\":2}")
  assert_eq(index.resolve(other).to_json(), "{\"x\":1}")
  assert_eq(index.data_paths(), [first, other])
}

///|
test "resource limit is enforced before parsing oversized values" {
  let text = "{\"x\":\"" + "a".repeat(2097152) + "\"}"
  let code = try {
    sample(text) |> ignore
    "success"
  } catch {
    @trace.TraceError(info) => info.code
  }
  assert_eq(code, "input_limit")
}

///|
test "diagnostic serialization is stable and includes a duplicate key location" {
  let output = try {
    sample("{\"x\":1,\"x\":2}") |> ignore
    "success"
  } catch {
    @trace.TraceError(info) => {
      assert_eq(info.offset, Some(7))
      info.to_report_json()
    }
  }
  assert_true(
    output.has_prefix("{\"code\":\"duplicate_json_key\",\"message\":"),
  )
  assert_true(output.contains("\"offset\":7"))
}
