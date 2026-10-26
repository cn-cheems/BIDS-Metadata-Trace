///|
// Reference candidate selection from the pre-index 2649641 resolver. This
// deliberately never consults the new acceleration maps.
fn linear_resolve(
  index : DatasetIndex,
  path : String,
) -> ResolvedMetadata raise TraceError {
  guard index.files.search_by(file => file.path == path) is Some(position) else {
    reject(
      "unknown_data_path", path, "Data path is absent from the manifest; add it before querying.",
    )
    abort("reject raises")
  }
  let candidates = index.sidecars.filter(source => {
    applies(source.selector, index.files[position])
  })
  let levels : Map[Int32, Array[String]] = Map([])
  for source in candidates {
    levels
    .get_or_init(source.selector.depth, () => [])
    .push(source.selector.path)
  }
  for source in candidates {
    let paths = levels[source.selector.depth]
    if paths.length() > 1 {
      reject(
        "ambiguous_inheritance",
        path,
        "Multiple JSON sidecars apply at the same directory level; consolidate them rather than relying on filename specificity.",
        related=paths.copy(),
      )
    }
  }
  let values : Map[String, Json] = Map([])
  let origins : Map[String, Array[FieldOrigin]] = Map([])
  let applied : Array[String] = []
  for source in candidates {
    applied.push(source.selector.path)
    for key in sorted_keys(source.metadata) {
      let value = copy_json(source.metadata[key])
      values[key] = value
      origins
      .get_or_init(key, () => [])
      .push({ path: source.selector.path, value, })
    }
  }
  { path, values, origins, applied, }
}

///|
fn linear_audit(index : DatasetIndex, paths : Array[String]) -> AuditReport {
  {
    entries: paths.map(path => {
      { path, result: Some(linear_resolve(index, path)), error: None, } catch {
        TraceError(d) => { path, result: None, error: Some(d), }
      }
    }),
  }
}

///|
fn differential_fixture(seed : Int32) -> DatasetIndex raise TraceError {
  let files : Array[String] = []
  let sources = [
    SidecarInput::new(
      "bold.json", "{\"x\":2.0,\"vendor\":[null,-0,9007199254740993,1e999]}",
    ),
    SidecarInput::new("task-other_bold.json", "{\"unused\":{\"keep\":1e-999}}"),
    SidecarInput::new("T1w.json", "{\"x\":null}"),
    SidecarInput::new("dwi.json", "{\"x\":[1,2]}"),
  ]
  for subject in ["1", "10"] {
    for session in ["1", "10"] {
      let scope = "sub-" + subject + "/ses-" + session
      let entities = "sub-" + subject + "_ses-" + session
      for run in ["01", "2"] {
        files.push(
          scope +
          "/func/" +
          entities +
          "_task-rest_acq-A_rec-fast_run-" +
          run +
          "_bold.nii.gz",
        )
      }
      files.push(scope + "/anat/" + entities + "_T1w.nii")
      files.push(scope + "/dwi/" + entities + "_run-1_dwi.nii.gz")
      if (seed + subject.length() + session.length()) % 3 != 0 {
        sources.push(
          SidecarInput::new(
            scope + "/" + entities + "_task-rest_bold.json",
            "{\"x\":{\"whole\":[null,2.0]}}",
          ),
        )
      }
      if seed % 5 == 0 {
        sources.push(
          SidecarInput::new(
            scope + "/" + entities + "_run-1_bold.json",
            "{\"x\":3.0}",
          ),
        )
      }
      if seed % 2 == 0 {
        sources.push(
          SidecarInput::new(
            scope + "/func/" + entities + "_acq-A_rec-fast_run-1_bold.json",
            "{\"x\":[3,2,1],\"new\":null}",
          ),
        )
      }
      sources.push(
        SidecarInput::new(
          scope + "/func/" + entities + "_task-motor_bold.json",
          "{\"unused\":true}",
        ),
      )
    }
    sources.push(
      SidecarInput::new(
        "sub-" + subject + "/sub-" + subject + "_acq-A_bold.json",
        "{\"subject\":1}",
      ),
    )
  }
  if seed % 7 == 0 {
    sources.push(SidecarInput::new("task-rest_bold.json", "{\"x\":2}"))
  }
  if seed % 2 == 1 {
    DatasetIndex::from_manifest(
      Array::makei(files.length(), i => files[files.length() - 1 - i]),
      Array::makei(sources.length(), i => sources[sources.length() - 1 - i]),
    )
  } else {
    DatasetIndex::from_manifest(files, sources)
  }
}

///|
test "indexed resolution is byte-identical to the linear oracle across scopes and ambiguities" {
  for seed in 0..<48 {
    let index = differential_fixture(seed)
    let before = index.to_manifest_json()
    let paths = index.data_paths() +
      ["absent", "../invalid", index.data_paths()[0]]
    assert_eq(
      index.audit(paths).to_json(),
      linear_audit(index, paths).to_json(),
    )
    assert_eq(index.to_manifest_json(), before)
    let reloaded = DatasetIndex::from_json(before)
    assert_eq(
      reloaded.audit(paths).to_json(),
      linear_audit(index, paths).to_json(),
    )
  }
}

///|
test "candidate lookup prunes unrelated buckets and preserves canonical ambiguity order" {
  let path = "sub-1/ses-1/func/sub-1_ses-1_task-rest_acq-A_run-01_bold.nii"
  let inputs = [
    SidecarInput::new("task-z_bold.json", "{}"),
    SidecarInput::new("task-rest_bold.json", "{\"x\":2.0}"),
    SidecarInput::new("acq-A_bold.json", "{\"x\":1}"),
    SidecarInput::new("sub-10/sub-10_bold.json", "{}"),
    SidecarInput::new("sub-1/ses-10/sub-1_ses-10_bold.json", "{}"),
    SidecarInput::new("T1w.json", "{}"),
  ]
  for i in 0..<10 {
    inputs.push(
      SidecarInput::new("task-noise" + i.to_string() + "_bold.json", "{}"),
    )
  }
  let index = DatasetIndex::from_manifest([path], inputs)
  assert_eq(
    index.matching_sources(index.files[0]).map(source => source.selector.path),
    ["acq-A_bold.json", "task-rest_bold.json"],
  )
  assert_eq(index.audit_all().to_json(), linear_audit(index, [path]).to_json())
}

///|
test "typed planning rebuilds lookups without aliasing previous snapshots" {
  let first = "sub-1/func/sub-1_task-rest_run-01_bold.nii"
  let second = "sub-2/func/sub-2_task-rest_run-1_bold.nii"
  let baseline = DatasetIndex::from_manifest([first], [
    SidecarInput::new("bold.json", "{\"x\":2.0}"),
  ])
  let plan = baseline.plan_changes(
    DatasetChanges::new(
      ScanChanges::new([second], [first]),
      SourceChanges::new(
        [SidecarInput::new("sub-2/sub-2_task-rest_bold.json", "{\"x\":2.0}")],
        [],
      ),
      EditBatch::from_patches([]),
    ),
  )
  assert_eq(
    plan.after().audit([first, second]).to_json(),
    linear_audit(plan.after(), [first, second]).to_json(),
  )
  let pruned = plan.after().plan_prune("sub-2/sub-2_task-rest_bold.json", ["x"])
  assert_eq(
    pruned.after().audit_all().to_json(),
    linear_audit(pruned.after(), [second]).to_json(),
  )
  assert_eq(baseline.data_paths(), [first])
  assert_eq(
    baseline.audit_all().to_json(),
    linear_audit(baseline, [first]).to_json(),
  )
}

///|
test "empty indexes and exact query spelling retain old lookup behavior" {
  let empty = DatasetIndex::from_manifest([], [
    SidecarInput::new("bold.json", "{}"),
  ])
  assert_eq(
    empty.audit(["unknown"]).to_json(),
    linear_audit(empty, ["unknown"]).to_json(),
  )
  let path = "sub-1/func/sub-1_task-rest_run-01_bold.nii"
  let index = DatasetIndex::from_manifest([path], [
    SidecarInput::new("run-1_bold.json", "{\"x\":-0}"),
  ])
  let paths = [path, "sub-1/func/sub-1_task-rest_run-1_bold.nii"]
  assert_eq(index.audit(paths).to_json(), linear_audit(index, paths).to_json())
}

///|
test "every discriminator keeps normalized matches and full remaining entity constraints" {
  let path = "sub-1/ses-1/func/sub-1_ses-1_task-rest_acq-A_ce-Gd_rec-fast_dir-AP_run-01_echo-01_part-mag_chunk-01_bold.nii"
  for
    (key, label, other) in [
      ("task", "rest", "other"),
      ("acq", "A", "B"),
      ("ce", "Gd", "Other"),
      ("rec", "fast", "slow"),
      ("dir", "AP", "PA"),
      ("run", "1", "2"),
      ("echo", "1", "2"),
      ("part", "mag", "phase"),
      ("chunk", "1", "2"),
    ] {
    let inputs = [
      SidecarInput::new(
        key + "-" + label + "_bold.json",
        "{\"x\":1e999,\"unknown\":null}",
      ),
      SidecarInput::new(key + "-" + other + "_bold.json", "{\"unused\":true}"),
    ]
    for i in 2..<11 {
      let suffix = if ["run", "echo", "chunk"].contains(key) {
        (i + 10).to_string()
      } else {
        other + i.to_string()
      }
      inputs.push(SidecarInput::new(key + "-" + suffix + "_bold.json", "{}"))
    }
    let index = DatasetIndex::from_manifest([path], inputs)
    assert_eq(index.matching_sources(index.files[0]).length(), 1)
    assert_eq(
      index.audit_all().to_json(),
      linear_audit(index, [path]).to_json(),
    )
  }
  let index = DatasetIndex::from_manifest([path], [
    SidecarInput::new("task-rest_acq-B_bold.json", "{\"wrong\":true}"),
    SidecarInput::new("task-rest_rec-slow_bold.json", "{\"wrong\":true}"),
    SidecarInput::new("task-rest_run-1_bold.json", "{\"x\":2.0}"),
  ])
  assert_eq(
    index.matching_sources(index.files[0]).map(source => source.selector.path),
    ["task-rest_run-1_bold.json"],
  )
  assert_eq(index.audit_all().to_json(), linear_audit(index, [path]).to_json())
}

///|
test "unmatched sources preserve reports across small-set and entity-index boundaries" {
  let path = "sub-1/func/sub-1_task-rest_bold.nii"
  let baseline = DatasetIndex::from_manifest([path], [
    SidecarInput::new("task-rest_bold.json", "{\"x\":2.0}"),
  ])
  let expected = baseline.audit_all().to_json()
  for count in [0, 1, 6, 7, 8, 9, 16] {
    let sources = [SidecarInput::new("task-rest_bold.json", "{\"x\":2.0}")]
    for i in 0..<count {
      sources.push(
        SidecarInput::new(
          "acq-A" + i.to_string() + "_bold.json",
          "{\"must_not_apply\":true}",
        ),
      )
    }
    let index = DatasetIndex::from_manifest([path], sources)
    assert_eq(index.audit_all().to_json(), expected)
    assert_eq(
      index.audit_all().to_json(),
      linear_audit(index, [path]).to_json(),
    )
    assert_eq(index.source_coverage().unmatched_paths().length(), count)
  }
}
