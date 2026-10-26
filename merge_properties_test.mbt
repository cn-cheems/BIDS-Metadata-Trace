///|
test "merge enumerates whole-field three-way states against a scalar oracle" {
  // Empty string represents an absent field, distinct from every JSON token.
  let states = ["", "null", "0", "-0", "[1,2]"]
  let make = token => {
    @trace.DatasetIndex::from_manifest([], [
      @trace.SidecarInput::new(
        "bold.json",
        if token == "" {
          "{}"
        } else {
          "{\"x\":" + token + "}"
        },
      ),
    ])
  }
  for b in states {
    for l in states {
      for r in states {
        let base = make(b)
        let report = base.merge(make(l), make(r))
        let expected = if l == r {
          Some(l)
        } else if b == l {
          Some(r)
        } else if b == r {
          Some(l)
        } else {
          None
        }
        match expected {
          Some(token) => {
            assert_eq(report.conflict_count(), 0)
            assert_eq(
              report.candidate().unwrap().to_manifest_json(),
              make(token).to_manifest_json(),
            )
          }
          None => {
            assert_true(report.candidate() is None)
            assert_eq(
              report.conflicts()[0].kind(),
              @trace.MergeConflictKind::FieldDiverged,
            )
          }
        }
      }
    }
  }
}

///|
test "merge enumerates root and local interactions against an independent intent oracle" {
  let path = "sub-01/func/sub-01_task-rest_bold.nii"
  let make = (root, override_value) => {
    let sources = [
      @trace.SidecarInput::new("bold.json", "{\"x\":" + root + "}"),
    ]
    if override_value != "" {
      sources.push(
        @trace.SidecarInput::new(
          "sub-01/sub-01_bold.json",
          "{\"x\":" + override_value + "}",
        ),
      )
    }
    @trace.DatasetIndex::from_manifest([path], sources)
  }
  let base = make("0", "")
  for lr in ["0", "1", "2"] {
    for ll in ["", "0", "1", "2"] {
      for rr in ["0", "1", "2"] {
        for rl in ["", "0", "1", "2"] {
          let l = make(lr, ll)
          let r = make(rr, rl)
          let report = base.merge(l, r)
          let root_conflict = lr != "0" && rr != "0" && lr != rr
          let local_conflict = ll != "" && rl != "" && ll != rl
          let lv = if ll == "" { lr } else { ll }
          let rv = if rl == "" { rr } else { rl }
          let divergent = lv != "0" && rv != "0" && lv != rv
          let wanted = if lv == "0" { rv } else { lv }
          let merged_root = if lr == "0" { rr } else { lr }
          let merged_local = if ll == "" { rl } else { ll }
          let actual = if merged_local == "" {
            merged_root
          } else {
            merged_local
          }
          let blocked = root_conflict ||
            local_conflict ||
            divergent ||
            actual != wanted
          assert_eq(report.candidate() is None, blocked)
          if !blocked {
            assert_eq(
              report.candidate().unwrap().resolve(path).to_json(),
              "{\"x\":" + wanted + "}",
            )
            assert_eq(
              report.candidate().unwrap().to_manifest_json(),
              base.merge(r, l).candidate().unwrap().to_manifest_json(),
            )
          }
        }
      }
    }
  }
}

///|
test "merge preserves maximum-depth values and recomputes complete embedded snapshots" {
  let nested = "[".repeat(63) + "1e999" + "]".repeat(63)
  let base = @trace.DatasetIndex::from_manifest([], [
    @trace.SidecarInput::new("bold.json", "{}"),
  ])
  let l = @trace.DatasetIndex::from_manifest([], [
    @trace.SidecarInput::new("bold.json", "{\"opaque\":" + nested + "}"),
  ])
  let r = @trace.DatasetIndex::from_manifest([], [
    @trace.SidecarInput::new("bold.json", "{\"new\":null}"),
  ])
  let report = base.merge(l, r)
  let after = report.candidate().unwrap()
  assert_eq(
    @trace.DatasetIndex::from_json(after.to_manifest_json()).to_manifest_json(),
    after.to_manifest_json(),
  )
  guard @json.parse(report.to_json()) is Object(fields) else {
    fail("Expected complete report object")
  }
  let replay = @trace.DatasetIndex::from_json(
    fields["base_manifest"].stringify(),
  ).merge(
    @trace.DatasetIndex::from_json(fields["left_manifest"].stringify()),
    @trace.DatasetIndex::from_json(fields["right_manifest"].stringify()),
  )
  assert_eq(replay.to_json(), report.to_json())
}

///|
test "merge rejects combined size overflow and recovers without losing source data" {
  let base = @trace.DatasetIndex::from_manifest([], [])
  let make = name => {
    @trace.DatasetIndex::from_manifest([], [
      @trace.SidecarInput::new(
        name,
        "{\"opaque\":\"" + "x".repeat(1050000) + "\"}",
      ),
    ])
  }
  let l = make("bold.json")
  let r = make("T1w.json")
  let report = base.merge(l, r)
  assert_true(report.candidate() is None)
  assert_eq(
    report.conflicts()[0].kind(),
    @trace.MergeConflictKind::InvalidSnapshot,
  )
  assert_eq(report.conflicts()[0].diagnostics()[0].code, "snapshot_limit")
  assert_eq(
    base.merge(l, base).candidate().unwrap().to_manifest_json(),
    l.to_manifest_json(),
  )
}

///|
test "merge keeps MRI suffix, participant, session and normalized run scopes separate" {
  let a = "sub-01/ses-01/func/sub-01_ses-01_task-rest_run-01_bold.nii.gz"
  let b = "sub-01/ses-02/func/sub-01_ses-02_task-rest_run-01_bold.nii.gz"
  let c = "sub-010/ses-01/func/sub-010_ses-01_task-rest_run-01_bold.nii.gz"
  let d = "sub-02/anat/sub-02_T1w.nii"
  let e = "sub-02/dwi/sub-02_dwi.nii.gz"
  let sources = [
    @trace.SidecarInput::new("bold.json", "{\"x\":0}"),
    @trace.SidecarInput::new("T1w.json", "{\"y\":0}"),
    @trace.SidecarInput::new("dwi.json", "{\"z\":0}"),
  ]
  let base = @trace.DatasetIndex::from_manifest([a, b, c, d, e], sources)
  let left = @trace.DatasetIndex::from_manifest(
    [e, d, c, b, a],
    sources +
    [
      @trace.SidecarInput::new(
        "sub-01/ses-01/sub-01_ses-01_run-1_bold.json", "{\"x\":1}",
      ),
    ],
  )
  let right = base
    .plan_edits(
      @trace.EditBatch::from_patches([
        (
          "T1w.json",
          @trace.MetadataPatch::from_json(
            "{\"set\":{\"y\":null},\"remove\":[]}",
          ),
        ),
        (
          "dwi.json",
          @trace.MetadataPatch::from_json(
            "{\"set\":{\"z\":[-0,1e999]},\"remove\":[]}",
          ),
        ),
      ]),
    )
    .after()
  let report = base.merge(left, right)
  assert_eq(report.conflict_count(), 0)
  let after = report.candidate().unwrap()
  assert_eq(after.resolve(a).to_json(), "{\"x\":1}")
  assert_eq(after.resolve(b).to_json(), "{\"x\":0}")
  assert_eq(after.resolve(c).to_json(), "{\"x\":0}")
  assert_eq(after.resolve(d).to_json(), "{\"y\":null}")
  assert_eq(after.resolve(e).to_json(), "{\"z\":[-0,1e999]}")
  assert_eq(report.impact().unwrap().changed_count(), 3)
}
