///|
test "complete inventory feeds reusable audit without image bytes" {
  let report = @trace.DiscoveryReport::from_inventory(
    [
      scan(),
      "task-rest_bold.json",
      "participants.tsv",
      "dataset_description.json",
      "derivatives",
      ".git",
    ],
    [
      @trace.SidecarInput::new(
        "task-rest_bold.json", "{\"x\":9007199254740993,\"RT\":2.0}",
      ),
    ],
  )
  assert_eq(
    report.index().resolve(scan()).to_json(),
    "{\"RT\":2.0,\"x\":9007199254740993}",
  )
  assert_eq(report.index().audit_all().error_count(), 0)
  assert_eq(report.auxiliary_paths(), [
    "dataset_description.json", "participants.tsv",
  ])
  assert_eq(report.excluded_paths(), [".git", "derivatives"])
  assert_true(report.to_json().contains("9007199254740993"))
  report.auxiliary_paths().clear()
  report.excluded_paths().clear()
  assert_eq(report.excluded_paths().length(), 2)
}

///|
test "inventory permutations preserve manifest report and reload behavior" {
  let inputs = [@trace.SidecarInput::new("task-rest_bold.json", "{\"x\":-0}")]
  let a = @trace.DiscoveryReport::from_inventory(
    [scan(), "task-rest_bold.json", "README"],
    inputs,
  )
  let b = @trace.DiscoveryReport::from_inventory(
    ["README", "task-rest_bold.json", scan()],
    inputs,
  )
  assert_eq(a.to_json(), b.to_json())
  assert_eq(
    @trace.DatasetIndex::from_json(a.index().to_manifest_json())
    .audit_all()
    .to_json(),
    a.index().audit_all().to_json(),
  )
}

///|
test "missing extra and duplicate source text reject incomplete inventories" {
  for
    (paths, inputs, expected) in [
      (["bold.json"], [], "missing_sidecar_text"),
      (
        [],
        [@trace.SidecarInput::new("bold.json", "{}")],
        "unexpected_sidecar_text",
      ),
      (
        ["bold.json"],
        [
          @trace.SidecarInput::new("bold.json", "{}"),
          @trace.SidecarInput::new("bold.json", "{}"),
        ],
        "path_collision",
      ),
      (["README", "README"], [], "path_collision"),
      (["README", "readme"], [], "path_collision"),
    ] {
    let code = try {
      @trace.DiscoveryReport::from_inventory(paths, inputs) |> ignore
      "success"
    } catch {
      @trace.TraceError(d) => d.code
    }
    assert_eq(code, expected)
  }
}

///|
test "unsupported candidates never silently disappear from discovery" {
  for
    (path, expected) in [
      ("sub-01/anat/sub-01_T2w.nii", "unsupported_suffix"),
      ("unknown.json", "unsupported_suffix"),
      ("sub-01/func/task-rest_bold.json", "scope_mismatch"),
      ("sub-01/func/sub-01_task-rest_space-MNI_bold.nii", "unsupported_entity"),
      ("notes.pdf", "unsupported_inventory_file"),
      ("../bold.json", "invalid_path"),
    ] {
    let code = try {
      @trace.classify_discovery_entry(path, directory=false) |> ignore
      "success"
    } catch {
      @trace.TraceError(d) => d.code
    }
    assert_eq(code, expected)
  }
}

///|
test "explicit exclusions and auxiliary resources do not masquerade as MRI sources" {
  for
    path in [
      "derivatives/anything.json", "sourcedata/scan.dcm", "code/tool.py", "stimuli/movie.mp4",
      "sub-01/.hidden/unknown.json",
    ] {
    assert_true(
      @trace.classify_discovery_entry(path, directory=false) ==
      @trace.DiscoveryRole::Excluded,
    )
  }
  for
    path in [
      "sub-01/func/sub-01_task-rest_events.json", "sub-01/dwi/sub-01_dwi.bval", "participants.json",
      "sub-01/sub-01_scans.tsv",
    ] {
    assert_true(
      @trace.classify_discovery_entry(path, directory=false) ==
      @trace.DiscoveryRole::Auxiliary,
    )
  }
  assert_true(
    @trace.classify_discovery_entry("sub-01/func", directory=true) ==
    @trace.DiscoveryRole::Directory,
  )
}

///|
test "malformed sidecar text fails then corrected inventory recovers" {
  let paths = [scan(), "task-rest_bold.json"]
  let code = try {
    @trace.DiscoveryReport::from_inventory(paths, [
      @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":1,\"x\":2}"),
    ])
    |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
  }
  assert_eq(code, "duplicate_json_key")
  assert_eq(
    @trace.DiscoveryReport::from_inventory(paths, [
      @trace.SidecarInput::new("task-rest_bold.json", "{}"),
    ])
    .index()
    .audit_all()
    .error_count(),
    0,
  )
}

///|
test "empty inventory is explicit and bounded" {
  assert_eq(
    @trace.DiscoveryReport::from_inventory([], []).index().data_paths(),
    [],
  )
  let paths = Array::make(20001, "README")
  let code = try {
    @trace.DiscoveryReport::from_inventory(paths, []) |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
  }
  assert_eq(code, "inventory_limit")
}
