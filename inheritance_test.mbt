///|
fn scan() -> String {
  "sub-01/func/sub-01_task-rest_run-01_bold.nii.gz"
}

///|
fn sample(
  root : String,
  override_text? : String,
) -> @trace.DatasetIndex raise @trace.TraceError {
  let sidecars = [@trace.SidecarInput::new("task-rest_bold.json", root)]
  if override_text is Some(text) {
    sidecars.push(
      @trace.SidecarInput::new(
        "sub-01/func/sub-01_task-rest_run-01_bold.json", text,
      ),
    )
  }
  @trace.DatasetIndex::from_manifest([scan()], sidecars)
}

///|
test "root inheritance and field provenance without adjacent JSON" {
  let result = sample("{\"RepetitionTime\":2.0,\"TaskName\":\"rest\"}").resolve(
    scan(),
  )
  assert_eq(result.to_json(), "{\"RepetitionTime\":2.0,\"TaskName\":\"rest\"}")
  assert_eq(result.trace("RepetitionTime")[0].path(), "task-rest_bold.json")
  assert_eq(result.trace("absent").length(), 0)
  assert_true(result.get("absent") is None)
}

///|
test "top-level overwrite preserves absence and never deep-merges objects" {
  let result = sample(
    "{\"EchoTime\":0.04,\"Custom\":{\"a\":1,\"b\":2},\"Keep\":[1,2],\"Gone\":7}",
    override_text="{\"Custom\":{\"a\":3},\"Gone\":null}",
  ).resolve(scan())
  assert_eq(
    result.to_json(),
    "{\"Custom\":{\"a\":3},\"EchoTime\":0.04,\"Gone\":null,\"Keep\":[1,2]}",
  )
  assert_eq(result.trace("Custom").length(), 2)
  assert_eq(result.trace("Custom")[0].value().stringify(), "{\"a\":1,\"b\":2}")
}

///|
test "same-level specificity is ambiguity even with identical values" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("bold.json", "{\"x\":1}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":1}"),
  ])
  let code = try {
    index.resolve(scan()) |> ignore
    "success"
  } catch {
    @trace.TraceError(info) => {
      assert_eq(info.related, ["bold.json", "task-rest_bold.json"])
      info.code
    }
  }
  assert_eq(code, "ambiguous_inheritance")
}

///|
test "entity mismatch does not contribute metadata" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("task-other_bold.json", "{\"Bad\":1}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{\"Good\":2}"),
  ])
  assert_eq(index.resolve(scan()).to_json(), "{\"Good\":2}")
}

///|
test "subject session and datatype levels are ordered" {
  let path = "sub-01/ses-A/func/sub-01_ses-A_task-rest_bold.nii"
  let index = @trace.DatasetIndex::from_manifest([path], [
    @trace.SidecarInput::new(
      "sub-01/ses-A/func/sub-01_ses-A_task-rest_bold.json", "{\"x\":4}",
    ),
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":1}"),
    @trace.SidecarInput::new(
      "sub-01/ses-A/sub-01_ses-A_task-rest_bold.json", "{\"x\":3}",
    ),
    @trace.SidecarInput::new("sub-01/sub-01_task-rest_bold.json", "{\"x\":2}"),
  ])
  let result = index.resolve(path)
  assert_eq(result.get("x").unwrap().stringify(), "4")
  assert_eq(result.trace("x").map(origin => origin.value().stringify()), [
    "1", "2", "3", "4",
  ])
}

///|
test "index entities match numerically without normalizing subject labels" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("task-rest_run-1_bold.json", "{\"x\":1}"),
  ])
  assert_eq(index.resolve(scan()).to_json(), "{\"x\":1}")
}

///|
test "input permutation and irrelevant sources preserve deterministic report" {
  let a = @trace.SidecarInput::new(
    "task-rest_bold.json", "{\"z\":{\"b\":2,\"a\":1},\"a\":0}",
  )
  let b = @trace.SidecarInput::new(
    "sub-01/func/sub-01_task-rest_run-01_bold.json", "{\"a\":3}",
  )
  let c = @trace.SidecarInput::new("task-other_bold.json", "{\"a\":99}")
  let expected = @trace.DatasetIndex::from_manifest([scan()], [a, b])
    .resolve(scan())
    .to_report_json()
  for sources in [[b, a], [c, a, b], [b, c, a]] {
    assert_eq(
      @trace.DatasetIndex::from_manifest([scan()], sources)
      .resolve(scan())
      .to_report_json(),
      expected,
    )
  }
}

///|
test "returned JSON collections cannot mutate the snapshot or result" {
  let index = sample("{\"x\":{\"a\":[1,2]}}")
  let result = index.resolve(scan())
  if result.get("x") is Some(Object(fields)) {
    fields["evil"] = Json::null()
  }
  if result.trace("x")[0].value() is Object(fields) {
    fields.remove("a") |> ignore
  }
  let paths = index.data_paths()
  paths.clear()
  assert_eq(result.to_json(), "{\"x\":{\"a\":[1,2]}}")
  assert_eq(index.resolve(scan()).to_json(), result.to_json())
}

///|
test "empty sidecars are valid absence not a compliance certificate" {
  let index = @trace.DatasetIndex::from_manifest(
    ["sub-01/anat/sub-01_T1w.nii"],
    [],
  )
  assert_eq(index.resolve("sub-01/anat/sub-01_T1w.nii").to_json(), "{}")
}
