///|
fn bundle_error(text : String) -> String {
  try {
    @trace.ReviewBundle::from_json(text) |> ignore
    "success"
  } catch {
    @trace.TraceError(diagnostic) => diagnostic.code
  }
}

///|
fn change_bundle_control(
  text : String,
  key : String,
  value : Json,
) -> String raise {
  guard @json.parse(text) is Object(fields) else { fail("bundle object") }
  fields[key] = value
  Json::object(fields).stringify()
}

///|
test "review bundle round trip is canonical lossless and independently replayable" {
  let before = sample(
    "{\"x\":9007199254740992,\"custom\":[{\"z\":null,\"a\":true}],\"huge\":1e999}",
  )
  let after = sample(
    "{\"x\":9007199254740993,\"custom\":[{\"a\":true,\"z\":null}],\"huge\":1e999}",
  )
  for policy in [@trace.ReleasePolicy::AllChanges, EffectiveValues] {
    let bundle = @trace.ReviewBundle::create(before, after, policy)
    let restored = @trace.ReviewBundle::from_json(bundle.to_json())
    assert_eq(restored.to_json(), bundle.to_json())
    assert_eq(restored.before().to_manifest_json(), before.to_manifest_json())
    assert_eq(restored.after().to_manifest_json(), after.to_manifest_json())
    assert_eq(
      restored.report().to_json(),
      before.compare(after).release_check(policy).to_json(),
    )
    assert_true(
      restored.report().decision() == @trace.ReleaseDecision::ChangesDetected,
    )
    assert_true(restored.to_json().contains("9007199254740993"))
    assert_true(restored.to_json().contains("1e999"))
    assert_eq(
      @trace.ReviewBundle::create(
        @trace.DatasetIndex::from_json(before.to_manifest_json()),
        @trace.DatasetIndex::from_json(after.to_manifest_json()),
        policy,
      ).to_json(),
      bundle.to_json(),
    )
  }
}

///|
test "review bundle retains ignored provenance and all indeterminate errors" {
  let before = sample("{\"x\":1.0}", override_text="{\"x\":3.0}")
  let after = sample("{\"x\":2.0}", override_text="{\"x\":3.0}")
  let bundle = @trace.ReviewBundle::create(
    before,
    after,
    @trace.ReleasePolicy::EffectiveValues,
  )
  assert_true(bundle.report().decision() == @trace.ReleaseDecision::Pass)
  assert_true(bundle.to_json().contains("provenance_changed"))
  assert_eq(
    @trace.ReviewBundle::from_json(bundle.to_json()).report().to_json(),
    bundle.report().to_json(),
  )
  let ambiguous = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("bold.json", "{}"),
    @trace.SidecarInput::new("task-rest_bold.json", "{}"),
  ])
  let errors = @trace.ReviewBundle::create(
    before,
    ambiguous,
    @trace.ReleasePolicy::AllChanges,
  )
  let restored = @trace.ReviewBundle::from_json(errors.to_json())
  assert_true(
    restored.report().decision() == @trace.ReleaseDecision::Indeterminate,
  )
  assert_eq(restored.report().unresolved_paths(), [scan()])
  assert_true(restored.to_json().contains("ambiguous_inheritance"))
  assert_eq(restored.report().to_json(), errors.report().to_json())
}

///|
test "review bundle rejects stale version unknown controls missing fields and wrong types" {
  let empty = @trace.DatasetIndex::from_manifest([], [])
  let text = @trace.ReviewBundle::create(
    empty,
    empty,
    @trace.ReleasePolicy::AllChanges,
  ).to_json()
  for
    (key, value, expected) in [
      ("version", Json::number(2.0), "unsupported_bundle_version"),
      ("version", Json::number(1.0, repr="1.0"), "unsupported_bundle_version"),
      ("version", Json::string("1"), "unsupported_bundle_version"),
      ("format", Json::string("another-tool"), "invalid_review_bundle"),
      ("policy", Json::string("future"), "invalid_review_bundle"),
      ("policy", Json::number(1.0), "invalid_review_bundle"),
      ("before", Json::null(), "invalid_review_bundle"),
      ("after", Json::array([]), "invalid_review_bundle"),
      ("expected", Json::null(), "invalid_review_bundle"),
      ("extra", Json::boolean(true), "unknown_bundle_field"),
    ] {
    assert_eq(bundle_error(change_bundle_control(text, key, value)), expected)
  }
  for key in ["format", "version", "before", "after", "policy", "expected"] {
    guard @json.parse(text) is Object(fields) else { fail("bundle object") }
    fields.remove(key) |> ignore
    assert_true(bundle_error(Json::object(fields).stringify()) != "success")
  }
  assert_eq(bundle_error("[]"), "invalid_review_bundle")
}

///|
test "review bundle rejects modified inputs policy and complete expected evidence" {
  let before = sample("{\"x\":1}", override_text="{\"x\":3}")
  let after = sample("{\"x\":2}", override_text="{\"x\":3}")
  let text = @trace.ReviewBundle::create(
    before,
    after,
    @trace.ReleasePolicy::AllChanges,
  ).to_json()
  assert_eq(
    bundle_error(
      change_bundle_control(text, "policy", Json::string("effective_values")),
    ),
    "replay_mismatch",
  )
  assert_eq(
    bundle_error(
      change_bundle_control(
        text,
        "after",
        @json.parse(before.to_manifest_json()),
      ),
    ),
    "replay_mismatch",
  )
  guard @json.parse(text) is Object(fields) &&
    fields.get("expected") is Some(Object(expected)) else {
    fail("expected report")
  }
  expected.remove("impact") |> ignore
  assert_eq(bundle_error(Json::object(fields).stringify()), "replay_mismatch")
  let empty = @trace.DatasetIndex::from_manifest([], [])
  let valid = @trace.ReviewBundle::create(
    empty,
    empty,
    @trace.ReleasePolicy::AllChanges,
  ).to_json()
  guard @json.parse(valid) is Object(fields) &&
    fields.get("expected") is Some(Object(expected)) else {
    fail("expected report")
  }
  expected["silentlyIgnored"] = Json::boolean(true)
  assert_eq(bundle_error(Json::object(fields).stringify()), "replay_mismatch")
  assert_eq(@trace.ReviewBundle::from_json(valid).to_json(), valid)
}

///|
test "review replay compares expected numeric tokens rather than rounded doubles" {
  for
    (original, replacement) in [
      ("2.0", "2"),
      ("-0", "0"),
      ("9007199254740993", "9007199254740992"),
      ("0.123456789012345678901234567890", "0.123456789012345678901234567891"),
    ] {
    let index = sample("{\"x\":" + original + "}")
    let bundle = @trace.ReviewBundle::create(
      index,
      index,
      @trace.ReleasePolicy::AllChanges,
    )
    let expected = bundle
      .report()
      .to_json()
      .replace(old="\"x\":" + original, new="\"x\":" + replacement)
    assert_true(expected != bundle.report().to_json())
    let bad = "{\"format\":\"bids-metadata-trace/review-bundle\",\"version\":1,\"before\":" +
      index.to_manifest_json() +
      ",\"after\":" +
      index.to_manifest_json() +
      ",\"policy\":\"all_changes\",\"expected\":" +
      expected +
      "}"
    assert_eq(bundle_error(bad), "replay_mismatch")
    assert_eq(
      @trace.ReviewBundle::from_json(bundle.to_json()).to_json(),
      bundle.to_json(),
    )
  }
}

///|
test "review bundle detects duplicate and escaped duplicate keys throughout input" {
  let empty = @trace.DatasetIndex::from_manifest([], [])
  let text = @trace.ReviewBundle::create(
    empty,
    empty,
    @trace.ReleasePolicy::AllChanges,
  ).to_json()
  assert_eq(
    bundle_error(
      text.replace(old="\"version\":1", new="\"version\":1,\"version\":1"),
    ),
    "duplicate_json_key",
  )
  assert_eq(
    bundle_error(
      text.replace(old="\"files\":[]", new="\"files\":[],\"\\u0066iles\":[]"),
    ),
    "duplicate_json_key",
  )
  assert_eq(
    bundle_error(
      text.replace(
        old="\"decision\":\"pass\"",
        new="\"decision\":\"pass\",\"decision\":\"pass\"",
      ),
    ),
    "duplicate_json_key",
  )
  assert_eq(bundle_error("{\"version\":1,}"), "invalid_json")
}

///|
test "maximum metadata nesting survives bundle envelope and all report histories" {
  let text = "{\"x\":" + "[".repeat(63) + "-0" + "]".repeat(63) + "}"
  let index = sample(text)
  let bundle = @trace.ReviewBundle::create(
    index,
    index,
    @trace.ReleasePolicy::AllChanges,
  )
  let restored = @trace.ReviewBundle::from_json(bundle.to_json())
  assert_eq(restored.to_json(), bundle.to_json())
  assert_eq(restored.after().resolve(scan()).to_json(), text)
  assert_eq(bundle_error("[".repeat(81) + "0" + "]".repeat(81)), "depth_limit")
}

///|
test "review bundle limits reject large input and repeated evidence without dropping scans" {
  assert_eq(bundle_error(" ".repeat(16777217)), "input_limit")
  let metadata = "{\"x\":\"" + "a".repeat(1000000) + "\"}"
  let files = [
    "sub-01/func/sub-01_task-rest_run-1_bold.nii", "sub-01/func/sub-01_task-rest_run-2_bold.nii",
    "sub-01/func/sub-01_task-rest_run-3_bold.nii", "sub-01/func/sub-01_task-rest_run-4_bold.nii",
  ]
  let index = @trace.DatasetIndex::from_manifest(files, [
    @trace.SidecarInput::new("task-rest_bold.json", metadata),
  ])
  let code = try {
    @trace.ReviewBundle::create(index, index, @trace.ReleasePolicy::AllChanges)
    |> ignore
    "success"
  } catch {
    @trace.TraceError(diagnostic) => diagnostic.code
  }
  assert_eq(code, "bundle_limit")
  assert_eq(index.data_paths(), files)
  assert_eq(
    index.resolve(files[0]).get("x").unwrap().stringify().length(),
    1000002,
  )
}

///|
test "review bundle enforces embedded snapshot limits before accepting replay" {
  let empty = @trace.DatasetIndex::from_manifest([], [])
  let valid = @trace.ReviewBundle::create(
    empty,
    empty,
    @trace.ReleasePolicy::AllChanges,
  ).to_json()
  let oversized = Json::object({
    "files": Json::array([]),
    "sidecars": Json::array([
      Json::object({
        "path": Json::string("bold.json"),
        "metadata": Json::object({ "x": Json::string("a".repeat(2097152)) }),
      }),
    ]),
  })
  assert_eq(
    bundle_error(change_bundle_control(valid, "before", oversized)),
    "input_limit",
  )
  let too_deep = "{\"files\":[],\"sidecars\":[{\"path\":\"bold.json\",\"metadata\":{\"x\":" +
    "[".repeat(64) +
    "0" +
    "]".repeat(64) +
    "}}]}"
  assert_eq(
    bundle_error(change_bundle_control(valid, "after", @json.parse(too_deep))),
    "depth_limit",
  )
  assert_eq(@trace.ReviewBundle::from_json(valid).to_json(), valid)
}

///|
test "review bundle accessors cannot mutate snapshots or stored evidence" {
  let bundle = @trace.ReviewBundle::create(
    sample("{\"x\":{\"a\":[1]}}"),
    sample("{\"x\":{\"a\":[2]}}"),
    @trace.ReleasePolicy::AllChanges,
  )
  let saved = bundle.to_json()
  bundle.before().data_paths().clear()
  bundle.report().affected_paths().clear()
  bundle.report().impact().entries().clear()
  if bundle.after().resolve(scan()).get("x") is Some(Object(fields)) {
    fields.remove("a") |> ignore
  }
  assert_eq(bundle.to_json(), saved)
  assert_eq(
    @trace.ReviewBundle::from_json(saved).report().to_json(),
    bundle.report().to_json(),
  )
}
