///|
fn metadata_query(
  text : String,
) -> @trace.MetadataQuery raise @trace.TraceError {
  @trace.MetadataQuery::from_json(text)
}

///|
fn metadata_query_error(text : String) -> String {
  try {
    ignore(metadata_query(text))
    "accepted"
  } catch {
    @trace.TraceError(d) => d.code
  }
}

///|
test "metadata selection resolves inheritance before exact AND OR predicates" {
  let second = "sub-01/func/sub-01_task-rest_run-02_bold.nii.gz"
  let index = @trace.DatasetIndex::from_manifest([second, scan()], [
    @trace.SidecarInput::new(
      "task-rest_bold.json", "{\"x\":2.0,\"unknown\":{\"large\":9007199254740993}}",
    ),
    @trace.SidecarInput::new(
      "sub-01/func/sub-01_task-rest_run-01_bold.json", "{\"x\":-0,\"nullable\":null}",
    ),
    @trace.SidecarInput::new("task-other_bold.json", "{\"unused\":true}"),
  ])
  let before = index.to_manifest_json()
  let query = metadata_query(
    "{\"present\":[\"nullable\"],\"absent\":[\"missing\"],\"equals\":{\"x\":[2.0,-0],\"unknown\":[{\"large\":9007199254740993}]}}",
  )
  let selected = index.select_metadata(query)
  assert_eq(selected.paths(), [scan()])
  assert_eq(selected.error_count(), 0)
  assert_eq(selected.audit().to_json(), index.audit([scan()]).to_json())
  assert_true(selected.to_json().contains("\"excluded_count\":1"))
  assert_true(selected.to_json().contains("\"value\":2.0"))
  assert_true(selected.to_json().contains("9007199254740993"))
  assert_true(selected.to_json().contains(second))
  assert_eq(index.to_manifest_json(), before)
  assert_true(before.contains("unused"))
}

///|
test "metadata equality requires presence and never coerces null or numeric tokens" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("bold.json", "{\"x\":2.0,\"n\":null,\"z\":-0}"),
  ])
  for
    text in [
      "{\"present\":[],\"absent\":[],\"equals\":{\"x\":[2]}}", "{\"present\":[],\"absent\":[],\"equals\":{\"x\":[2e0]}}",
      "{\"present\":[],\"absent\":[],\"equals\":{\"z\":[0]}}", "{\"present\":[],\"absent\":[],\"equals\":{\"missing\":[null]}}",
      "{\"present\":[],\"absent\":[\"n\"],\"equals\":{}}",
    ] {
    assert_eq(index.select_metadata(metadata_query(text)).paths(), [])
  }
  let null_query = metadata_query(
    "{\"present\":[\"n\"],\"absent\":[\"missing\"],\"equals\":{\"n\":[null]}}",
  )
  assert_eq(index.select_metadata(null_query).paths(), [scan()])
}

///|
test "metadata filtering retains duplicate errors and complete excluded evidence" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("bold.json", "{\"x\":1}"),
  ])
  let query = metadata_query(
    "{\"present\":[],\"absent\":[],\"equals\":{\"x\":[2]}}",
  )
  let selected = index
    .audit(["absent", scan(), "absent"])
    .filter_metadata(query)
  assert_eq(selected.paths(), [])
  assert_eq(selected.error_count(), 2)
  assert_eq(selected.audit().entries().length(), 2)
  assert_eq(selected.audit().entries()[1].path(), "absent")
  assert_true(selected.to_json().contains("\"query_index\":2"))
  assert_true(selected.to_json().contains("\"x\":1"))
  let expected = @trace.MetadataExpectations::from_json(
    "{\"required\":[],\"allowed\":{}}",
  )
  assert_true(
    selected.audit().check_expectations(expected).decision() ==
    @trace.ExpectationDecision::Indeterminate,
  )
  let ambiguity = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("bold.json", "{}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
  ])
  assert_eq(ambiguity.select_metadata(query).error_count(), 1)
  assert_true(
    ambiguity.select_metadata(query).to_json().contains("ambiguous_inheritance"),
  )
  assert_eq(index.audit([scan()]).filter_metadata(query).error_count(), 0)
}

///|
test "metadata empty predicates match all resolved occurrences without empty fallback" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [])
  let query = metadata_query("{\"present\":[],\"absent\":[],\"equals\":{}}")
  assert_eq(index.audit([scan(), scan()]).filter_metadata(query).paths(), [
    scan(),
    scan(),
  ])
  assert_eq(
    index.audit([]).filter_metadata(query).audit().entries().length(),
    0,
  )
  assert_eq(
    index
    .select_metadata(
      metadata_query("{\"present\":[\"absent\"],\"absent\":[],\"equals\":{}}"),
    )
    .paths(),
    [],
  )
}

///|
test "metadata predicates round trip deterministically and report access is defensive" {
  let first = metadata_query(
    "{\"present\":[\"z\",\"a\"],\"absent\":[\"q\",\"p\"],\"equals\":{\"x\":[{\"b\":2.0,\"a\":1},-0]}}",
  )
  let second = metadata_query(
    "{\"equals\":{\"x\":[-0,{\"a\":1,\"b\":2.0}]},\"absent\":[\"p\",\"q\"],\"present\":[\"a\",\"z\"]}",
  )
  assert_eq(first.to_json(), second.to_json())
  assert_eq(metadata_query(first.to_json()).to_json(), first.to_json())
  let index = @trace.DatasetIndex::from_manifest([scan()], [])
  let selected = index.select_metadata(
    metadata_query("{\"present\":[],\"absent\":[],\"equals\":{}}"),
  )
  let before = selected.to_json()
  selected.paths().clear()
  selected.audit().entries().clear()
  if selected.to_json_value() is Object(fields) {
    fields.clear()
  }
  assert_eq(selected.paths(), [scan()])
  assert_eq(selected.to_json(), before)
  assert_eq(
    @trace.DatasetIndex::from_json(index.to_manifest_json())
    .select_metadata(
      metadata_query("{\"present\":[],\"absent\":[],\"equals\":{}}"),
    )
    .to_json(),
    before,
  )
}

///|
test "metadata queries reject unknown contradictory duplicate and malformed controls" {
  for
    text in [
      "[]", "{}", "{\"present\":[],\"absent\":{},\"equals\":{}}", "{\"present\":[],\"absent\":[2],\"equals\":{}}",
    ] {
    assert_eq(metadata_query_error(text), "invalid_metadata_query")
  }
  assert_eq(
    metadata_query_error(
      "{\"present\":[],\"absent\":[],\"equals\":{},\"regex\":true}",
    ),
    "unknown_metadata_query_field",
  )
  assert_eq(
    metadata_query_error(
      "{\"present\":[\"x\"],\"absent\":[\"x\"],\"equals\":{}}",
    ),
    "conflicting_metadata_predicate",
  )
  assert_eq(
    metadata_query_error(
      "{\"present\":[],\"absent\":[\"x\"],\"equals\":{\"x\":[1]}}",
    ),
    "conflicting_metadata_predicate",
  )
  assert_eq(
    metadata_query_error("{\"present\":[],\"absent\":[],\"equals\":{\"x\":[]}}"),
    "invalid_allowed_values",
  )
  assert_eq(
    metadata_query_error(
      "{\"present\":[],\"absent\":[],\"equals\":{\"x\":[1,1]}}",
    ),
    "duplicate_allowed_value",
  )
  assert_eq(
    metadata_query_error(
      "{\"present\":[],\"absent\":[],\"equals\":{\"x\":[{\"a\":1,\"\\u0061\":2}]}}",
    ),
    "duplicate_json_key",
  )
  assert_true(
    metadata_query_error(
      "{\"present\":[],\"absent\":[\"x\",\"x\"],\"equals\":{}}",
    ) !=
    "accepted",
  )
  assert_true(
    metadata_query_error(
      "{\"present\":[\"x\",\"x\"],\"absent\":[],\"equals\":{}}",
    ) !=
    "accepted",
  )
}

///|
test "metadata query total field choice text and nesting limits are recoverable" {
  let names = Array::makei(256, i => Json::string("f" + i.to_string()))
  let text = Json::object({
    "present": Json::array(names),
    "absent": Json::array([]),
    "equals": Json::object(Map([])),
  }).stringify()
  ignore(metadata_query(text))
  names.push(Json::string("overflow"))
  assert_true(
    metadata_query_error(
      Json::object({
        "present": Json::array(names),
        "absent": Json::array([]),
        "equals": Json::object(Map([])),
      }).stringify(),
    ) !=
    "accepted",
  )
  let choices = Array::makei(256, i => Json::number(i.to_double()))
  ignore(
    metadata_query(
      Json::object({
        "present": Json::array([]),
        "absent": Json::array([]),
        "equals": Json::object({ "x": Json::array(choices) }),
      }).stringify(),
    ),
  )
  choices.push(Json::number(256))
  assert_eq(
    metadata_query_error(
      Json::object({
        "present": Json::array([]),
        "absent": Json::array([]),
        "equals": Json::object({ "x": Json::array(choices) }),
      }).stringify(),
    ),
    "invalid_allowed_values",
  )
  assert_eq(metadata_query_error(" ".repeat(2097153)), "input_limit")
  let nested = "[".repeat(64) + "0" + "]".repeat(64)
  ignore(
    metadata_query(
      "{\"present\":[],\"absent\":[],\"equals\":{\"x\":[" + nested + "]}}",
    ),
  )
  assert_eq(
    metadata_query_error(
      "{\"present\":[],\"absent\":[],\"equals\":{\"x\":[[" + nested + "]]}}",
    ),
    "depth_limit",
  )
  ignore(metadata_query("{\"present\":[],\"absent\":[],\"equals\":{}}"))
}
