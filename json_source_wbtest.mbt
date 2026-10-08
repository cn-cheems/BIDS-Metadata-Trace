///|
test "canonical JSON keys are lexically sorted" {
  let keys = ["z", "a", "Custom", "EchoTime", "Gone", "Keep"]
  keys.sort_by(lexical_compare)
  assert_eq(keys, ["Custom", "EchoTime", "Gone", "Keep", "a", "z"])
  let json = parse_source(
    "test", "{\"TaskName\":\"rest\",\"RepetitionTime\":2.0}",
  )
  assert_eq(
    canonical_json(json),
    "{\"RepetitionTime\":2.0,\"TaskName\":\"rest\"}",
  )
}
