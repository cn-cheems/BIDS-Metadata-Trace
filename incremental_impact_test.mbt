///|
fn incremental_check(
  before : @trace.DatasetIndex,
  after : @trace.DatasetIndex,
  expected_invalidated : Array[String],
  expected_resolved : Int32,
) -> @trace.IncrementalImpact raise {
  let graph = before.dependency_graph()
  assert_eq(graph.audit().to_json(), before.audit_all().to_json())
  let advance = graph.advance(after)
  advance.verify_full()
  assert_eq(advance.report().to_json(), before.compare(after).to_json())
  assert_eq(advance.invalidated_paths(), expected_invalidated)
  assert_eq(advance.resolved_count(), expected_resolved)
  assert_eq(
    advance.reused_count(),
    after.data_paths().length() - expected_resolved,
  )
  assert_eq(advance.next().audit().to_json(), after.audit_all().to_json())
  assert_eq(advance.next().to_json(), after.dependency_graph().to_json())
  assert_eq(graph.snapshot().to_manifest_json(), before.to_manifest_json())
  advance
}

///|
test "dependency graph reuses unchanged shadowed and unmatched evidence without mutation" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let q = "sub-02/func/sub-02_task-rest_bold.nii"
  let base = merge_fixture([p, q], [
    ("bold.json", "{\"x\":1}"),
    ("sub-01/sub-01_bold.json", "{\"x\":2}"),
    ("T1w.json", "{}"),
  ])
  let graph = base.dependency_graph()
  assert_eq(graph.dependents("bold.json"), [p, q])
  assert_eq(graph.dependents("T1w.json"), [])
  let copy = graph.dependents("bold.json")
  copy.clear()
  assert_eq(graph.dependents("bold.json"), [p, q])
  try graph.dependents("absent.json") catch {
    @trace.TraceError(d) => assert_eq(d.code, "unknown_sidecar_path")
  } noraise {
    _ => fail("unknown graph source")
  }
  ignore(incremental_check(base, base, [], 0))
  let unmatched = base
    .plan_edit(
      "T1w.json",
      @trace.MetadataPatch::from_json("{\"set\":{\"x\":null},\"remove\":[]}"),
    )
    .after()
  assert_eq(
    incremental_check(base, unmatched, [], 0).report().changed_count(),
    0,
  )
  let shadowed = base
    .plan_edit(
      "bold.json",
      @trace.MetadataPatch::from_json("{\"set\":{\"x\":3},\"remove\":[]}"),
    )
    .after()
  let changed = incremental_check(base, shadowed, [p, q], 2)
  assert_true(
    changed.report().entries()[0].changes()[0].kind() ==
    @trace.FieldChangeKind::ProvenanceChanged,
  )
}

///|
test "added sources discover new edges including empty sources ambiguity and recovery" {
  let p = "sub-01/func/sub-01_task-rest_run-01_bold.nii"
  let q = "sub-02/func/sub-02_task-rest_run-02_bold.nii"
  let base = merge_fixture([p, q], [("bold.json", "{\"x\":1}")])
  let empty = merge_fixture([p, q], [
    ("bold.json", "{\"x\":1}"),
    ("sub-01/sub-01_run-1_bold.json", "{}"),
  ])
  let first = incremental_check(base, empty, [p], 1)
  assert_true(first.report().entries()[0].sources_changed())
  let ambiguous = merge_fixture([p, q], [
    ("bold.json", "{\"x\":1}"),
    ("task-rest_bold.json", "{}"),
  ])
  let second = incremental_check(base, ambiguous, [p, q], 2)
  assert_eq(second.report().error_count(), 2)
  assert_eq(second.next().dependents("task-rest_bold.json"), [p, q])
  let same_errors = incremental_check(ambiguous, ambiguous, [], 0)
  assert_eq(same_errors.report().error_count(), 2)
  let recovered = second.next().advance(base)
  recovered.verify_full()
  assert_eq(recovered.resolved_count(), 2)
  assert_eq(recovered.next().audit().error_count(), 0)
  assert_eq(second.next().audit().error_count(), 2)
}

///|
test "local edits and source removal invalidate exact scope with normalized entities" {
  let p = "sub-01/ses-pre/func/sub-01_ses-pre_task-rest_run-01_echo-002_bold.nii.gz"
  let q = "sub-01/ses-post/func/sub-01_ses-post_task-rest_run-1_echo-2_bold.nii"
  let z = "sub-01/ses-pre/dwi/sub-01_ses-pre_run-1_dwi.nii"
  let source = "sub-01/ses-pre/sub-01_ses-pre_run-001_echo-2_bold.json"
  let base = merge_fixture([q, z, p], [
    ("bold.json", "{\"x\":1}"),
    (source, "{\"x\":null}"),
  ])
  let after = merge_fixture([q, z, p], [("bold.json", "{\"x\":1}")])
  let report = incremental_check(base, after, [p], 1)
  assert_eq(report.report().changed_count(), 1)
  assert_eq(base.dependency_graph().dependents(source), [p])
  let back = report.next().advance(base)
  back.verify_full()
  assert_eq(back.invalidated_paths(), [p])
}

///|
test "incremental scan inventory changes and source changes are one atomic transition" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let q = "sub-02/anat/sub-02_T1w.nii.gz"
  let base = merge_fixture([p], [("bold.json", "{}")])
  let after = merge_fixture([q], [
    ("T1w.json", "{\"x\":[null,-0,9007199254740993,1e999]}"),
  ])
  let report = incremental_check(base, after, [p, q], 1)
  assert_eq(report.report().changed_count(), 2)
  let repeated = report.next().advance(base)
  repeated.verify_full()
  assert_eq(repeated.resolved_count(), 1)
  assert_eq(repeated.reused_count(), 0)
  let empty = merge_fixture([], [])
  ignore(incremental_check(empty, empty, [], 0))
  ignore(incremental_check(empty, base, [p], 1))
  ignore(incremental_check(base, empty, [p], 0))
}

///|
test "incremental exact numeric null unknown nested and deterministic ordering" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  for
    (before, after) in [
      ("2", "2.0"),
      ("-0", "0"),
      ("9007199254740992", "9007199254740993"),
      ("1e999", "2e999"),
      ("null", "[null,{\"x\":[1,2]}]"),
    ] {
    let base = merge_fixture([p], [("bold.json", "{\"x\":" + before + "}")])
    let changed = merge_fixture([p], [("bold.json", "{\"x\":" + after + "}")])
    assert_eq(
      incremental_check(base, changed, [p], 1).report().changed_count(),
      1,
    )
  }
  let base = merge_fixture([p], [
    ("bold.json", "{\"b\":2.0,\"a\":1}"),
    ("T1w.json", "{}"),
  ])
  let reordered = merge_fixture([p], [
    ("T1w.json", "{}"),
    ("bold.json", "{\"a\":1,\"b\":2.0}"),
  ])
  let same = incremental_check(base, reordered, [], 0)
  let evidence = same.to_json()
  let invalidated = same.invalidated_paths()
  invalidated.push(p)
  assert_eq(same.to_json(), evidence)
  assert_eq(
    base.dependency_graph().to_json(),
    reordered.dependency_graph().to_json(),
  )
}

///|
test "incremental mixed MRI profiles and long chained updates match full oracle" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let q = "sub-02/anat/sub-02_T1w.nii"
  let z = "sub-03/dwi/sub-03_dwi.nii.gz"
  let values = [
    "{}", "{\"x\":null}", "{\"x\":2.0}", "{\"x\":-0}", "{\"x\":1e999}",
  ]
  let initial = merge_fixture([p, q, z], [])
  let mut graph = initial.dependency_graph()
  let mut count = 0
  for bold in values {
    for anat in values {
      for dwi in values {
        let after = merge_fixture(
          if count % 3 == 0 {
            [p, z]
          } else {
            [z, q, p]
          },
          [("bold.json", bold), ("T1w.json", anat), ("dwi.json", dwi)],
        )
        let update = graph.advance(after)
        update.verify_full()
        assert_eq(update.next().audit().to_json(), after.audit_all().to_json())
        graph = update.next()
        count += 1
      }
    }
  }
  assert_eq(count, 125)
  assert_eq(initial.audit_all().error_count(), 0)
}

///|
test "incremental local source insertion cannot silently evade new target sets" {
  // All 48 combinations exercise absent/empty/shadowed/ambiguous source chains,
  // matching and nonmatching root entities, and retained unknown evidence.
  let p = "sub-01/func/sub-01_task-rest_run-01_bold.nii"
  let q = "sub-02/func/sub-02_task-other_run-02_bold.nii"
  for root in ["bold.json", "task-rest_bold.json", "run-1_bold.json"] {
    for old_local in [None, Some("{}"), Some("{\"x\":2}"), Some("{\"x\":null}")] {
      let source = "sub-01/sub-01_bold.json"
      let base_sources = [(root, "{\"x\":1}")]
      if old_local is Some(value) {
        base_sources.push((source, value))
      }
      let base = merge_fixture([p, q], base_sources)
      for
        target in [
          None,
          Some("{}"),
          Some("{\"x\":2.0}"),
          Some("{\"x\":[1,null]}"),
        ] {
        let inputs = [(root, "{\"x\":1}")]
        if target is Some(value) {
          inputs.push((source, value))
        }
        let after = merge_fixture([p, q], inputs)
        let update = base.dependency_graph().advance(after)
        update.verify_full()
        assert_eq(
          update.invalidated_paths(),
          if old_local == target {
            []
          } else {
            [p]
          },
        )
      }
    }
  }
}
