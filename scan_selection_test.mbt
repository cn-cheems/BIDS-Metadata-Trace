///|
test "scan selection ANDs entities ORs choices and normalizes decimal indices" {
  let first = "sub-01/ses-A/func/sub-01_ses-A_task-rest_run-01_bold.nii.gz"
  let second = "sub-01/ses-A/func/sub-01_ses-A_task-rest_run-02_bold.nii"
  let third = "sub-02/ses-A/func/sub-02_ses-A_task-rest_run-02_bold.nii"
  let anatomy = "sub-01/ses-A/anat/sub-01_ses-A_T1w.nii"
  let index = @trace.DatasetIndex::from_manifest(
    [third, anatomy, second, first],
    [],
  )
  let query = @trace.ScanQuery::from_json(
    "{\"suffixes\":[\"bold\",\"T1w\"],\"entities\":{\"sub\":[\"01\"],\"ses\":[\"A\"],\"run\":[\"0001\",\"2\"]}}",
  )
  let selection = index.select_scans(query)
  assert_eq(selection.paths(), [first, second])
  assert_eq(selection.audit().entries().length(), 2)
  assert_true(query.to_json().contains("\"run\":[\"1\",\"2\"]"))
  assert_true(selection.to_json().contains("\"total_count\":4"))
  assert_true(selection.to_json().contains(anatomy))
  assert_true(selection.to_json().contains(third))
}

///|
test "selected audits retain all parent sources exact metadata and downstream review workflows" {
  let second = "sub-01/func/sub-01_task-rest_run-02_bold.nii.gz"
  let index = @trace.DatasetIndex::from_manifest([second, scan()], [
    @trace.SidecarInput::new(
      "task-rest_bold.json", "{\"x\":2.0,\"unknown\":{\"large\":9007199254740993}}",
    ),
    @trace.SidecarInput::new(
      "sub-01/func/sub-01_task-rest_run-01_bold.json", "{\"x\":-0}",
    ),
    @trace.SidecarInput::new("task-other_bold.json", "{\"unused\":true}"),
  ])
  let original = index.to_manifest_json()
  let selection = index.select_scans(
    @trace.ScanQuery::new(["bold"], { "run": ["0001"] }),
  )
  let audit = selection.audit()
  assert_eq(audit.to_json(), index.audit([scan()]).to_json())
  assert_true(audit.to_json().contains("9007199254740993"))
  assert_true(audit.to_json().contains("\"value\":2.0"))
  assert_true(audit.to_json().contains("\"x\":-0"))
  assert_true(audit.summarize_fields(["x"]).to_json().contains("\"value\":-0"))
  assert_true(audit.to_review_csv(["x"]).contains("json:-0"))
  let expected = @trace.MetadataExpectations::from_json(
    "{\"required\":[\"x\"],\"allowed\":{\"x\":[-0]}}",
  )
  assert_true(
    audit.check_expectations(expected).decision() ==
    @trace.ExpectationDecision::Pass,
  )
  assert_eq(index.to_manifest_json(), original)
  assert_true(original.contains("unused"))
}

///|
test "selection keeps chosen ambiguous scans rather than filtering by resolution success" {
  let anatomy = "sub-01/anat/sub-01_T1w.nii"
  let index = @trace.DatasetIndex::from_manifest([anatomy, scan()], [
    @trace.SidecarInput::new("bold.json", "{}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
  ])
  let chosen = index.select_scans(@trace.ScanQuery::new(["bold"], Map([])))
  assert_eq(chosen.paths(), [scan()])
  assert_eq(chosen.audit().error_count(), 1)
  assert_true(chosen.audit().to_json().contains("ambiguous_inheritance"))
  let unaffected = index.select_scans(@trace.ScanQuery::new(["T1w"], Map([])))
  assert_eq(unaffected.paths(), [anatomy])
  assert_eq(unaffected.audit().error_count(), 0)
  assert_eq(chosen.audit().error_count(), 1)
}

///|
test "empty selection never falls back to auditing the entire index or grants approval" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [])
  let query = @trace.ScanQuery::new(["bold"], { "task": ["other"] })
  let chosen = index.select_scans(query)
  assert_eq(chosen.paths(), [])
  assert_eq(chosen.audit().entries().length(), 0)
  let expected = @trace.MetadataExpectations::from_json(
    "{\"required\":[],\"allowed\":{}}",
  )
  assert_true(
    chosen.audit().check_expectations(expected).decision() ==
    @trace.ExpectationDecision::Indeterminate,
  )
  assert_eq(
    index.select_scans(@trace.ScanQuery::new(["bold"], Map([]))).paths(),
    [scan()],
  )
  assert_eq(
    @trace.DatasetIndex::from_manifest([], []).select_scans(query).paths(),
    [],
  )
}

///|
fn scan_query_error(text : String) -> String {
  try {
    ignore(@trace.ScanQuery::from_json(text))
    "accepted"
  } catch {
    @trace.TraceError(d) => d.code
  }
}

///|
test "queries reject unknown malformed duplicate and ambiguous controls" {
  for
    text in [
      "[]", "{}", "{\"suffixes\":[],\"entities\":[]}", "{\"suffixes\":[2],\"entities\":{}}",
      "{\"suffixes\":[\"bold\"],\"entities\":{\"run\":[2]}}",
    ] {
    assert_eq(scan_query_error(text), "invalid_scan_query")
  }
  assert_eq(
    scan_query_error("{\"suffixes\":[],\"entities\":{}}"),
    "invalid_query_suffixes",
  )
  assert_eq(
    scan_query_error("{\"suffixes\":[\"bold\"],\"entities\":{},\"regex\":true}"),
    "unknown_scan_query_field",
  )
  assert_eq(
    scan_query_error("{\"suffixes\":[\"events\"],\"entities\":{}}"),
    "unsupported_suffix",
  )
  assert_eq(
    scan_query_error("{\"suffixes\":[\"bold\",\"bold\"],\"entities\":{}}"),
    "duplicate_query_choice",
  )
  assert_eq(
    scan_query_error(
      "{\"suffixes\":[\"bold\"],\"entities\":{\"run\":[\"01\",\"1\"]}}",
    ),
    "duplicate_query_choice",
  )
  assert_eq(
    scan_query_error(
      "{\"suffixes\":[\"bold\"],\"entities\":{\"task\":[\"REST\",\"rest\"]}}",
    ),
    "duplicate_query_choice",
  )
  assert_eq(
    scan_query_error("{\"suffixes\":[\"bold\"],\"entities\":{\"run\":[]}}"),
    "empty_query_choices",
  )
  assert_eq(
    scan_query_error(
      "{\"suffixes\":[\"bold\"],\"entities\":{\"run\":[\"-1\"]}}",
    ),
    "invalid_entity",
  )
  assert_eq(
    scan_query_error(
      "{\"suffixes\":[\"bold\"],\"entities\":{\"RepetitionTime\":[\"2.0\"]}}",
    ),
    "unsupported_entity",
  )
  assert_eq(
    scan_query_error(
      "{\"suffixes\":[\"bold\"],\"entities\":{\"task\":[\"rest\"],\"\\u0074ask\":[\"other\"]}}",
    ),
    "duplicate_json_key",
  )
}

///|
test "query and snapshot round trips permutation and defensive copies preserve selection" {
  let suffixes = ["dwi", "bold"]
  let values = ["2", "0001"]
  let entities : Map[String, Array[String]] = { "run": values }
  let query = @trace.ScanQuery::new(suffixes, entities)
  let equivalent = @trace.ScanQuery::new(["bold", "dwi"], {
    "run": ["01", "02"],
  })
  assert_eq(query.to_json(), equivalent.to_json())
  suffixes.clear()
  values.clear()
  entities.clear()
  assert_eq(query.to_json(), equivalent.to_json())
  let index = @trace.DatasetIndex::from_manifest([scan()], [])
  let selection = index.select_scans(query)
  let exported = selection.paths()
  exported.clear()
  assert_eq(selection.paths(), [scan()])
  assert_eq(
    selection.to_json(),
    @trace.DatasetIndex::from_json(index.to_manifest_json())
    .select_scans(@trace.ScanQuery::from_json(query.to_json()))
    .to_json(),
  )
}

///|
test "selection handles missing optional entities and exact label and arbitrary decimal strings" {
  let path = "sub-01/func/sub-01_task-REST_run-123456789012345678901234567890_bold.nii"
  let index = @trace.DatasetIndex::from_manifest([path], [])
  assert_eq(
    index
    .select_scans(@trace.ScanQuery::new(["bold"], { "task": ["REST"] }))
    .paths(),
    [path],
  )
  assert_eq(
    index
    .select_scans(@trace.ScanQuery::new(["bold"], { "task": ["Rest"] }))
    .paths(),
    [],
  )
  assert_eq(
    index
    .select_scans(@trace.ScanQuery::new(["bold"], { "echo": ["1"] }))
    .paths(),
    [],
  )
  assert_eq(
    index
    .select_scans(
      @trace.ScanQuery::new(["bold"], {
        "run": ["000123456789012345678901234567890"],
      }),
    )
    .paths(),
    [path],
  )
}

///|
test "query count depth and text limits reject explicitly and permit recovery" {
  let choices = Array::makei(255, i => i.to_string())
  ignore(@trace.ScanQuery::new(["bold"], { "run": choices }))
  choices.push("255")
  try {
    ignore(@trace.ScanQuery::new(["bold"], { "run": choices }))
    fail("query limit accepted")
  } catch {
    @trace.TraceError(d) => assert_eq(d.code, "scan_query_limit")
    error => fail(error.to_string())
  }
  assert_eq(scan_query_error(" ".repeat(2097153)), "input_limit")
  assert_eq(scan_query_error("[[[[0]]]]"), "depth_limit")
  assert_true(
    @trace.ScanQuery::new(["bold"], { "run": ["0"] })
    .to_json()
    .contains("\"0\""),
  )
}
