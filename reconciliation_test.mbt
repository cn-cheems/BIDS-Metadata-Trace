///|
fn reconciliation_text(
  report : @trace.MergeReport,
  sources~ : String = "[]",
  scans~ : String = "[]",
  effective~ : String = "[]",
) -> String {
  // Splice only the canonical outer envelope; core/json.parse defaults to
  // floating-point numbers and must not rewrite the bound source tokens.
  report
  .resolution_template()
  .replace_all(
    old=",\"effective\":[],\"left\":",
    new=",\"effective\":" + effective + ",\"left\":",
  )
  .replace_all(
    old=",\"scans\":[],\"sources\":[]}",
    new=",\"scans\":" + scans + ",\"sources\":" + sources + "}",
  )
}

///|
fn reconciliation_source(path : String, value : String) -> String {
  "{\"path\":" +
  Json::string(path).stringify() +
  ",\"metadata\":" +
  value +
  ",\"reason\":\"Maintainers agreed this complete replacement\"}"
}

///|
fn reconciliation_effect(
  path : String,
  key : String,
  value : String?,
) -> String {
  "{\"path\":" +
  Json::string(path).stringify() +
  ",\"key\":" +
  Json::string(key).stringify() +
  ",\"present\":" +
  (if value is Some(_) { "true" } else { "false" }) +
  ",\"value\":" +
  value.unwrap_or("null") +
  ",\"reason\":\"Reviewed inherited result\"}"
}

///|
fn resolution_error(text : String) -> String {
  try {
    ignore(@trace.MergeResolution::from_json(text))
    "success"
  } catch {
    @trace.TraceError(d) => d.code
  }
}

///|
test "reconciliation requires exact effective consent after structural source resolution" {
  try {
    let p = "sub-01/func/sub-01_task-rest_bold.nii"
    let base = merge_fixture([p], [
      ("bold.json", "{\"x\":1,\"opaque\":[null,-0,9007199254740993,1e999]}"),
      ("T1w.json", "{\"unmatched\":true}"),
    ])
    let left = merge_fixture([p], [
      ("bold.json", "{\"x\":2,\"opaque\":[null,-0,9007199254740993,1e999]}"),
      ("T1w.json", "{\"unmatched\":true}"),
    ])
    let right = merge_fixture([p], [
      ("bold.json", "{\"x\":3,\"opaque\":[null,-0,9007199254740993,1e999]}"),
      ("T1w.json", "{\"unmatched\":true}"),
    ])
    let report = base.merge(left, right)
    let source = "[" +
      reconciliation_source(
        "bold.json", "{\"x\":2.0,\"opaque\":[null,-0,9007199254740993,1e999]}",
      ) +
      "]"
    let unresolved = report.reconcile(
      @trace.MergeResolution::from_json(
        reconciliation_text(report, sources=source),
      ),
    )
    assert_true(unresolved.candidate() is None)
    assert_eq(
      unresolved.conflicts()[0].kind(),
      @trace.MergeConflictKind::EffectiveDiverged,
    )
    let input = reconciliation_text(
      report,
      sources=source,
      effective="[" + reconciliation_effect(p, "x", Some("2.0")) + "]",
    )
    let plan = @trace.MergeResolution::from_json(input)
    assert_eq(
      @trace.MergeResolution::from_json(plan.to_json()).to_json(),
      plan.to_json(),
    )
    let reviewed = report.reconcile(plan)
    let candidate = reviewed.candidate().unwrap()
    assert_eq(reviewed.conflict_count(), 0)
    assert_eq(
      candidate.resolve(p).to_json(),
      "{\"opaque\":[null,-0,9007199254740993,1e999],\"x\":2.0}",
    )
    assert_eq(candidate.source_coverage().unmatched_paths(), ["T1w.json"])
    assert_eq(
      reviewed.impact().unwrap().to_json(),
      base.compare(candidate).to_json(),
    )
    assert_true(reviewed.to_json().contains("field_diverged"))
    assert_eq(report.conflicts()[0].left_json(), Some("2"))
    let mismatched = @trace.MergeResolution::from_json(
      reconciliation_text(
        report,
        sources=source,
        effective="[" + reconciliation_effect(p, "x", Some("2")) + "]",
      ),
    )
    try report.reconcile(mismatched) catch {
      @trace.TraceError(d) => assert_eq(d.code, "resolution_value_mismatch")
    } noraise {
      _ => fail("token mismatch must reject")
    }
    assert_eq(report.reconcile(plan).to_json(), reviewed.to_json())
  } catch {
    @trace.TraceError(d) => fail(d.to_report_json())
    err => raise err
  }
}

///|
test "reconciliation checks every inherited scan and every unapproved field" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let q = "sub-02/func/sub-02_task-rest_bold.nii"
  let base = merge_fixture([p, q], [("bold.json", "{\"x\":1,\"y\":1}")])
  let left = merge_fixture([p, q], [("bold.json", "{\"x\":2,\"y\":2}")])
  let right = merge_fixture([p, q], [
    ("bold.json", "{\"x\":1,\"y\":1}"),
    ("sub-01/sub-01_bold.json", "{\"x\":1,\"y\":1}"),
    ("sub-02/sub-02_bold.json", "{\"x\":1,\"y\":1}"),
  ])
  let report = base.merge(left, right)
  assert_eq(report.conflict_count(), 4)
  let partial = report.reconcile(
    @trace.MergeResolution::from_json(
      reconciliation_text(
        report,
        effective="[" + reconciliation_effect(p, "x", Some("1")) + "]",
      ),
    ),
  )
  assert_eq(partial.conflict_count(), 3)
  assert_true(partial.candidate() is None)
  let revised = "[" +
    reconciliation_source("sub-01/sub-01_bold.json", "{}") +
    "," +
    reconciliation_source("sub-02/sub-02_bold.json", "{}") +
    "]"
  let complete = report.reconcile(
    @trace.MergeResolution::from_json(
      reconciliation_text(report, sources=revised),
    ),
  )
  assert_eq(complete.conflict_count(), 0)
  assert_eq(
    complete.candidate().unwrap().resolve(q).to_json(),
    "{\"x\":2,\"y\":2}",
  )
}

///|
test "reconciliation explicitly decides source addition deletion and scan delete edit" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let base = merge_fixture([p], [("bold.json", "{\"x\":1}")])
  let left = merge_fixture([], [("bold.json", "{\"x\":1}")])
  let right = merge_fixture([p], [("bold.json", "{\"x\":2}")])
  let report = base.merge(left, right)
  assert_eq(
    report.conflicts()[0].kind(),
    @trace.MergeConflictKind::ScanDeleteEdit,
  )
  for retained in [false, true] {
    let scans = "[{\"path\":" +
      Json::string(p).stringify() +
      ",\"include\":" +
      retained.to_string() +
      ",\"reason\":\"Reviewed scan inventory\"}]"
    let result = report.reconcile(
      @trace.MergeResolution::from_json(reconciliation_text(report, scans~)),
    )
    assert_eq(result.conflict_count(), 0)
    assert_eq(
      result.candidate().unwrap().data_paths(),
      if retained {
        [p]
      } else {
        []
      },
    )
  }
  let empty = merge_fixture([], [])
  for (b, l, r) in [(empty, base, right), (base, empty, right)] {
    let m = b.merge(l, r)
    let removed = m.reconcile(
      @trace.MergeResolution::from_json(
        reconciliation_text(
          m,
          sources="[" + reconciliation_source("bold.json", "null") + "]",
          scans="[{\"path\":" +
            Json::string(p).stringify() +
            ",\"include\":false,\"reason\":\"Remove scan and its source deliberately\"}]",
        ),
      ),
    )
    assert_eq(
      removed.candidate().unwrap().to_manifest_json(),
      empty.to_manifest_json(),
    )
  }
}

///|
test "reconciliation distinguishes absent null empty and does not mutate earlier snapshots" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let base = merge_fixture([p], [("bold.json", "{\"x\":0}")])
  let left = merge_fixture([p], [("bold.json", "{}")])
  let right = merge_fixture([p], [("bold.json", "{\"x\":null}")])
  let report = base.merge(left, right)
  for (metadata, value) in [("{}", None), ("{\"x\":null}", Some("null"))] {
    let result = report.reconcile(
      @trace.MergeResolution::from_json(
        reconciliation_text(
          report,
          sources="[" + reconciliation_source("bold.json", metadata) + "]",
          effective="[" + reconciliation_effect(p, "x", value) + "]",
        ),
      ),
    )
    assert_eq(result.candidate().unwrap().resolve(p).to_json(), metadata)
    assert_eq(result.candidate().unwrap().resolve(p).applied_sidecars(), [
      "bold.json",
    ])
  }
  assert_eq(base.resolve(p).to_json(), "{\"x\":0}")
}

///|
test "reconciliation rejects stale inputs including provenance and token changes" {
  let base = merge_fixture([], [("bold.json", "{\"x\":2}")])
  let changed = merge_fixture([], [("bold.json", "{\"x\":2.0}")])
  let plan = @trace.MergeResolution::from_json(
    base.merge(base, base).resolution_template(),
  )
  for
    report in [
      changed.merge(base, base),
      base.merge(changed, base),
      base.merge(base, changed),
    ] {
    try report.reconcile(plan) catch {
      @trace.TraceError(d) => assert_eq(d.code, "stale_merge_resolution")
    } noraise {
      _ => fail("stale bindings")
    }
  }
  assert_eq(base.merge(base, base).reconcile(plan).conflict_count(), 0)
}

///|
test "reconciliation cannot waive unresolved historical inputs or invalid final inventory" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let bad = merge_fixture([p], [
    ("bold.json", "{}"),
    ("task-rest_bold.json", "{}"),
  ])
  let fixed = merge_fixture([p], [("bold.json", "{}")])
  let report = bad.merge(fixed, fixed)
  let reviewed = report.reconcile(
    @trace.MergeResolution::from_json(report.resolution_template()),
  )
  assert_true(reviewed.candidate() is None)
  assert_eq(reviewed.conflicts()[0].branch(), Some("base"))
  try reviewed.review_bundle(@trace.ReleasePolicy::AllChanges) catch {
    @trace.TraceError(d) => assert_eq(d.code, "reconciliation_blocked")
  } noraise {
    _ => fail("blocked bundle")
  }
  let clean = fixed.merge(fixed, fixed)
  let invalid = clean.reconcile(
    @trace.MergeResolution::from_json(
      reconciliation_text(
        clean,
        sources="[" + reconciliation_source("task-Rest_bold.json", "{}") + "]",
      ),
    ),
  )
  assert_eq(
    invalid.conflicts()[0].kind(),
    @trace.MergeConflictKind::InvalidSnapshot,
  )
  assert_true(invalid.candidate() is None)
}

///|
test "merge review bundle independently replays all decisions evidence and policy" {
  let base = merge_fixture([], [("bold.json", "{\"x\":1e999}")])
  let left = merge_fixture([], [("bold.json", "{\"x\":2e999}")])
  let right = merge_fixture([], [("bold.json", "{\"x\":3e999}")])
  let report = base.merge(left, right)
  let plan = @trace.MergeResolution::from_json(
    reconciliation_text(
      report,
      sources="[" + reconciliation_source("bold.json", "{\"x\":-0}") + "]",
    ),
  )
  let reviewed = report.reconcile(plan)
  for policy in [@trace.ReleasePolicy::AllChanges, EffectiveValues] {
    let bundle = reviewed.review_bundle(policy)
    let restored = @trace.MergeReviewBundle::from_json(bundle.to_json())
    assert_eq(restored.to_json(), bundle.to_json())
    assert_eq(restored.reconciliation().to_json(), reviewed.to_json())
    assert_eq(restored.report().to_json(), bundle.report().to_json())
    for
      (key, value) in [
        ("version", Json::number(2)),
        ("format", Json::string("unknown")),
        ("extra", Json::null()),
        ("expected", Json::object({})),
      ] {
      let corrupted = change_bundle_control(bundle.to_json(), key, value)
      try @trace.MergeReviewBundle::from_json(corrupted) catch {
        @trace.TraceError(_) => ()
      } noraise {
        _ => fail("tampered bundle")
      }
    }
    let other = @trace.ReviewBundle::create(base, base, policy)
    let wrong_binding = change_bundle_control(
      bundle.to_json(),
      "release",
      @json.parse(other.to_json()),
    )
    try @trace.MergeReviewBundle::from_json(wrong_binding) catch {
      @trace.TraceError(d) => assert_eq(d.code, "replay_mismatch")
    } noraise {
      _ => fail("wrong release binding")
    }
  }
}

///|
test "resolution parser rejects malformed unknown duplicate unsupported and ambiguous decisions" {
  let empty = merge_fixture([], [])
  let report = empty.merge(empty, empty)
  let valid = report.resolution_template()
  for
    text in [
      "{",
      "[]",
      valid.replace_all(
        old="\"sources\":[]",
        new="\"sources\":[],\"sources\":[]",
      ),
    ] {
    assert_true(resolution_error(text) != "success")
  }
  for
    sources in [
      "[1]", "[{\"path\":\"bold.json\",\"metadata\":[],\"reason\":\"x\"}]", "[{\"path\":\"bold.json\",\"metadata\":{},\"reason\":\" \"}]",
      "[{\"path\":\"bold.json\",\"metadata\":{},\"reason\":\"x\",\"force\":true}]",
    ] {
    assert_true(
      resolution_error(reconciliation_text(report, sources~)) != "success",
    )
  }
  let one = reconciliation_source("bold.json", "{}")
  assert_eq(
    resolution_error(
      reconciliation_text(report, sources="[" + one + "," + one + "]"),
    ),
    "duplicate_resolution",
  )
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let effect = reconciliation_effect(p, "x", None)
  assert_eq(
    resolution_error(
      reconciliation_text(report, effective="[" + effect + "," + effect + "]"),
    ),
    "duplicate_resolution",
  )
  assert_eq(
    resolution_error(
      reconciliation_text(
        report,
        effective="[" +
          effect.replace_all(old="\"value\":null", new="\"value\":1") +
          "]",
      ),
    ),
    "invalid_merge_resolution",
  )
  assert_eq(resolution_error(valid), "success")
}

///|
test "resolution decision limits canonical ordering and recovery" {
  let empty = merge_fixture([], [])
  let report = empty.merge(empty, empty)
  let sources = Array::makei(256, i => {
    reconciliation_source("task-t" + i.to_string() + "_bold.json", "{}")
  })
  let text = reconciliation_text(report, sources="[" + sources.join(",") + "]")
  let plan = @trace.MergeResolution::from_json(text)
  let reversed = @trace.MergeResolution::from_json(
    reconciliation_text(report, sources="[" + sources.rev().join(",") + "]"),
  )
  assert_eq(plan.to_json(), reversed.to_json())
  assert_eq(
    report
    .reconcile(plan)
    .candidate()
    .unwrap()
    .source_coverage()
    .unmatched_paths()
    .length(),
    256,
  )
  sources.push(reconciliation_source("bold.json", "{}"))
  assert_eq(
    resolution_error(
      reconciliation_text(report, sources="[" + sources.join(",") + "]"),
    ),
    "resolution_limit",
  )
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let effects = Array::makei(1024, i => {
    reconciliation_effect(p, "field" + i.to_string(), None)
  })
  assert_eq(
    resolution_error(
      reconciliation_text(report, effective="[" + effects.join(",") + "]"),
    ),
    "success",
  )
  effects.push(reconciliation_effect(p, "overflow", None))
  assert_eq(
    resolution_error(
      reconciliation_text(report, effective="[" + effects.join(",") + "]"),
    ),
    "resolution_limit",
  )
  assert_eq(
    report
    .reconcile(@trace.MergeResolution::from_json(report.resolution_template()))
    .candidate()
    .unwrap()
    .to_manifest_json(),
    empty.to_manifest_json(),
  )
}

///|
test "reconciliation exhaustive exact scalar choices preserve agreed candidate and stable replay" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let values = ["null", "-0", "2.0", "9007199254740993", "[1,{\"x\":true}]"]
  for bv in values {
    let base = merge_fixture([p], [("bold.json", "{\"x\":" + bv + "}")])
    for lv in values {
      let left = merge_fixture([p], [("bold.json", "{\"x\":" + lv + "}")])
      for rv in values {
        let right = merge_fixture([p], [("bold.json", "{\"x\":" + rv + "}")])
        let report = base.merge(left, right)
        let resolution = @trace.MergeResolution::from_json(
          reconciliation_text(
            report,
            sources="[" +
              reconciliation_source("bold.json", "{\"x\":" + rv + "}") +
              "]",
            effective="[" + reconciliation_effect(p, "x", Some(rv)) + "]",
          ),
        )
        let reviewed = report.reconcile(resolution)
        assert_eq(
          reviewed.candidate().unwrap().resolve(p).to_json(),
          "{\"x\":" + rv + "}",
        )
        let bundle = reviewed.review_bundle(@trace.ReleasePolicy::AllChanges)
        assert_eq(
          @trace.MergeReviewBundle::from_json(bundle.to_json()).to_json(),
          bundle.to_json(),
        )
      }
    }
  }
}

///|
test "reconciliation enforces source depth reason and input size without poisoning retry" {
  let empty = merge_fixture([], [])
  let report = empty.merge(empty, empty)
  let mut nested = "0"
  for _ in 0..<63 {
    nested = "[" + nested + "]"
  }
  let accepted = reconciliation_text(
    report,
    sources="[" +
      reconciliation_source("bold.json", "{\"x\":" + nested + "}") +
      "]",
  )
  let plan = @trace.MergeResolution::from_json(accepted)
  let bundle = report
    .reconcile(plan)
    .review_bundle(@trace.ReleasePolicy::AllChanges)
  assert_eq(
    @trace.MergeReviewBundle::from_json(bundle.to_json()).to_json(),
    bundle.to_json(),
  )
  assert_true(
    resolution_error(
      reconciliation_text(
        report,
        sources="[" +
          reconciliation_source("bold.json", "{\"x\":[" + nested + "]}") +
          "]",
      ),
    ) !=
    "success",
  )
  let short = reconciliation_text(
    report,
    sources="[" + reconciliation_source("bold.json", "{}") + "]",
  )
  let reason = "Maintainers agreed this complete replacement"
  assert_eq(
    resolution_error(short.replace_all(old=reason, new="r".repeat(4096))),
    "success",
  )
  assert_eq(
    resolution_error(short.replace_all(old=reason, new="r".repeat(4097))),
    "invalid_resolution_reason",
  )
  assert_eq(resolution_error(" ".repeat(16777217)), "input_limit")
  assert_eq(resolution_error(accepted), "success")
}
