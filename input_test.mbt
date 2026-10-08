///|
test "malformed and duplicate keys are rejected including escaped nested duplicates" {
  let invalid = [
    ("{\"x\":1,\"x\":2}", "duplicate_json_key"),
    ("{\"x\":[{\"a\":1,\"\\u0061\":2}]}", "duplicate_json_key"),
    ("{\"x\":1,}", "invalid_json"),
    ("[]", "expected_object"),
    ("{\"x\":\"\\ud800\"}", "invalid_json"),
  ]
  for (text, expected) in invalid {
    let code = try {
      @trace.DatasetIndex::from_manifest([], [
        @trace.SidecarInput::new("bold.json", text),
      ])
      |> ignore
      "success"
    } catch {
      @trace.TraceError(info) => info.code
    }
    assert_eq(code, expected)
  }
}

///|
test "arbitrary precision numeric lexemes and unknown structures survive round trips" {
  let text = "{\"n\":9007199254740993,\"huge\":1e999,\"negative\":-0,\"nested\":[{\"z\":null,\"emoji\":\"🧠\"}],\"decimal\":0.123456789012345678901234567890}"
  let index = sample(text)
  let result = index.resolve(scan())
  let reconstructed = @trace.DatasetIndex::from_json(index.to_manifest_json())
  assert_eq(
    reconstructed.resolve(scan()).to_report_json(),
    result.to_report_json(),
  )
  assert_eq(result.get("n").unwrap().stringify(), "9007199254740993")
  assert_eq(result.get("huge").unwrap().stringify(), "1e999")
  assert_eq(result.get("negative").unwrap().stringify(), "-0")
  assert_eq(
    result.get("decimal").unwrap().stringify(),
    "0.123456789012345678901234567890",
  )
  assert_eq(reconstructed.to_manifest_json(), index.to_manifest_json())
}

///|
test "invalid paths scope and unsupported profiles never produce partial results" {
  for
    (path, expected) in [
      ("../task-rest_bold.json", "invalid_path"),
      ("C:\\data\\bold.json", "invalid_path"),
      ("sub-01/func/task-rest_bold.json", "scope_mismatch"),
      ("sub-01_bold.json", "scope_mismatch"),
      ("derivatives/bold.json", "unsupported_scope"),
      ("task-rest_space-MNI_bold.json", "unsupported_entity"),
      ("task-rest_eeg.json", "unsupported_suffix"),
      ("task-rest_task-rest_bold.json", "duplicate_entity"),
      ("run-1_task-rest_bold.json", "entity_order"),
      ("task-rest_run-A_bold.json", "invalid_entity"),
    ] {
    let code = try {
      @trace.DatasetIndex::from_manifest([], [
        @trace.SidecarInput::new(path, "{}"),
      ])
      |> ignore
      "success"
    } catch {
      @trace.TraceError(info) => info.code
    }
    assert_eq(code, expected)
  }
}

///|
test "case collisions and repeated paths fail" {
  let code = try {
    @trace.DatasetIndex::from_manifest([scan(), scan()], []) |> ignore
    "success"
  } catch {
    @trace.TraceError(info) => info.code
  }
  assert_eq(code, "path_collision")
  let code = try {
    @trace.DatasetIndex::from_manifest(
      [
        "sub-A/func/sub-A_task-rest_bold.nii", "sub-a/func/sub-a_task-other_bold.nii",
      ],
      [],
    )
    |> ignore
    "success"
  } catch {
    @trace.TraceError(info) => info.code
  }
  assert_eq(code, "label_collision")
}

///|
test "unknown manifest fields and invalid types are explicit errors" {
  for
    (text, expected) in [
      (
        "{\"files\":[],\"sidecars\":[],\"silentlyLost\":true}", "unknown_manifest_field",
      ),
      ("{\"files\":[2],\"sidecars\":[]}", "invalid_manifest"),
      (
        "{\"files\":[],\"sidecars\":[{\"path\":\"bold.json\",\"metadata\":{},\"future\":1}]}",
        "unknown_manifest_field",
      ),
      ("{\"files\":[],\"files\":[],\"sidecars\":[]}", "duplicate_json_key"),
    ] {
    let code = try {
      @trace.DatasetIndex::from_json(text) |> ignore
      "success"
    } catch {
      @trace.TraceError(info) => info.code
    }
    assert_eq(code, expected)
  }
}

///|
test "nesting boundary and delimiter characters in strings" {
  let nested = "{\"x\":" + "[".repeat(64) + "0" + "]".repeat(64) + "}"
  let code = try {
    sample(nested) |> ignore
    "success"
  } catch {
    @trace.TraceError(info) => info.code
  }
  assert_eq(code, "depth_limit")
  let accepted = "{\"x\":" +
    "[".repeat(63) +
    "0" +
    "]".repeat(63) +
    ",\"s\":\"{[\\\"}\\\\\"}"
  assert_true(sample(accepted).resolve(scan()).get("x") is Some(_))
}

///|
test "unknown query then successful query proves no sticky error state" {
  let index = sample("{\"RepetitionTime\":2}")
  let code = try {
    index.resolve("absent.nii") |> ignore
    "success"
  } catch {
    @trace.TraceError(info) => info.code
  }
  assert_eq(code, "unknown_data_path")
  assert_eq(index.resolve(scan()).to_json(), "{\"RepetitionTime\":2}")
}
