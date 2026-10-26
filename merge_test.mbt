///|
fn merge_fixture(
  files : Array[String],
  sources : Array[(String, String)],
) -> @trace.DatasetIndex raise {
  @trace.DatasetIndex::from_manifest(
    files,
    sources.map(p => @trace.SidecarInput::new(p.0, p.1)),
  )
}

///|
test "merge composes disjoint whole-field edits and preserves all unknown values" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let original = "{\"a\":1,\"b\":2,\"opaque\":[null,-0,9007199254740993,1e999,{\"z\":true}]}"
  let base = merge_fixture([p], [("bold.json", original), ("T1w.json", "{}")])
  let left = base
    .plan_edit(
      "bold.json",
      @trace.MetadataPatch::from_json("{\"set\":{\"a\":3},\"remove\":[]}"),
    )
    .after()
  let right = base
    .plan_edit(
      "bold.json",
      @trace.MetadataPatch::from_json("{\"set\":{\"b\":null},\"remove\":[]}"),
    )
    .after()
  let report = base.merge(left, right)
  assert_eq(report.conflict_count(), 0)
  let after = report.candidate().unwrap()
  assert_eq(
    after.resolve(p).to_json(),
    "{\"a\":3,\"b\":null,\"opaque\":[null,-0,9007199254740993,1e999,{\"z\":true}]}",
  )
  assert_eq(after.source_coverage().unmatched_paths(), ["T1w.json"])
  assert_eq(report.impact().unwrap().changed_count(), 1)
  assert_eq(report.impact().unwrap().error_count(), 0)
  assert_eq(
    base.to_manifest_json(),
    merge_fixture([p], [("bold.json", original), ("T1w.json", "{}")]).to_manifest_json(),
  )
  assert_eq(
    @trace.DatasetIndex::from_json(after.to_manifest_json()).to_manifest_json(),
    after.to_manifest_json(),
  )
  assert_eq(
    base.merge(right, left).candidate().unwrap().to_manifest_json(),
    after.to_manifest_json(),
  )
}

///|
test "merge identity and input permutation have deterministic complete output" {
  let a = "sub-01/anat/sub-01_T1w.nii"
  let b = "sub-02/func/sub-02_task-rest_bold.nii"
  let sources = [("bold.json", "{\"n\":2.0}"), ("T1w.json", "{\"n\":1e999}")]
  let base = merge_fixture([b, a], sources)
  let reordered = merge_fixture([a, b], sources.rev())
  assert_eq(
    base.merge(base, reordered).candidate().unwrap().to_manifest_json(),
    base.to_manifest_json(),
  )
  assert_eq(
    base.merge(base, base).to_json(),
    reordered.merge(reordered, reordered).to_json(),
  )
  let changed = base
    .plan_edit(
      "bold.json",
      @trace.MetadataPatch::from_json("{\"set\":{\"n\":-0},\"remove\":[]}"),
    )
    .after()
  for (l, r) in [(base, changed), (changed, base), (changed, changed)] {
    assert_eq(
      base.merge(l, r).candidate().unwrap().to_manifest_json(),
      changed.to_manifest_json(),
    )
  }
  let empty = merge_fixture([], [])
  assert_eq(
    empty.merge(empty, empty).candidate().unwrap().to_manifest_json(),
    empty.to_manifest_json(),
  )
}

///|
test "merge distinguishes exact numeric tokens, null, absence, arrays and atomic objects" {
  for
    (old, a, b) in [
      ("2", "2.0", "2e0"),
      ("null", "-0", "0"),
      ("9007199254740993", "9007199254740992", "9007199254740994"),
      ("1e999", "2e999", "3e999"),
      ("[1,2]", "[2,1]", "[1]"),
      ("{\"a\":0,\"b\":0}", "{\"a\":1,\"b\":0}", "{\"a\":0,\"b\":1}"),
    ] {
    let base = merge_fixture([], [("bold.json", "{\"x\":" + old + "}")])
    let l = merge_fixture([], [("bold.json", "{\"x\":" + a + "}")])
    let r = merge_fixture([], [("bold.json", "{\"x\":" + b + "}")])
    let report = base.merge(l, r)
    assert_true(report.candidate() is None)
    assert_true(report.impact() is None)
    assert_eq(report.conflict_count(), 1)
    let c = report.conflicts()[0]
    assert_eq(c.kind(), @trace.MergeConflictKind::FieldDiverged)
    assert_eq(c.path(), "bold.json")
    assert_eq(c.key(), Some("x"))
    assert_eq(c.base_json(), Some(old))
    assert_eq(c.left_json(), Some(a))
    assert_eq(c.right_json(), Some(b))
    assert_eq(c.merged_json(), None)
    assert_eq(c.branch(), None)
    assert_false(c.message().is_empty())
  }
  let base = merge_fixture([], [("bold.json", "{\"x\":0}")])
  let deleted = merge_fixture([], [("bold.json", "{}")])
  let nulled = merge_fixture([], [("bold.json", "{\"x\":null}")])
  let conflict = base.merge(deleted, nulled).conflicts()[0]
  assert_eq(conflict.left_json(), None)
  assert_eq(conflict.right_json(), Some("null"))
  assert_eq(
    base.merge(deleted, base).candidate().unwrap().to_manifest_json(),
    deleted.to_manifest_json(),
  )
  let absent = merge_fixture([], [("bold.json", "{}")])
  assert_eq(
    absent.merge(nulled, absent).candidate().unwrap().to_manifest_json(),
    nulled.to_manifest_json(),
  )
}

///|
test "merge source additions are atomic and source deletion does not erase edits" {
  let empty = merge_fixture([], [])
  let a = merge_fixture([], [("bold.json", "{}")])
  let b = merge_fixture([], [("bold.json", "{\"x\":null}")])
  assert_eq(
    empty.merge(a, a).candidate().unwrap().to_manifest_json(),
    a.to_manifest_json(),
  )
  assert_eq(
    empty.merge(a, empty).candidate().unwrap().to_manifest_json(),
    a.to_manifest_json(),
  )
  let add = empty.merge(a, b)
  assert_eq(add.conflicts()[0].kind(), @trace.MergeConflictKind::SourceAddAdd)
  assert_eq(add.conflicts()[0].base_json(), None)
  assert_eq(add.conflicts()[0].left_json(), Some("{}"))
  let del = a.merge(empty, b)
  assert_eq(
    del.conflicts()[0].kind(),
    @trace.MergeConflictKind::SourceDeleteEdit,
  )
  assert_eq(
    a.merge(empty, a).candidate().unwrap().to_manifest_json(),
    empty.to_manifest_json(),
  )
  assert_eq(
    a.merge(empty, empty).candidate().unwrap().to_manifest_json(),
    empty.to_manifest_json(),
  )
}

///|
test "merge detects effective divergence across distinct source paths" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let base = merge_fixture([p], [("bold.json", "{\"x\":0}")])
  let l = merge_fixture([p], [("bold.json", "{\"x\":1}")])
  let r = merge_fixture([p], [
    ("bold.json", "{\"x\":0}"),
    ("sub-01/sub-01_bold.json", "{\"x\":2}"),
  ])
  let report = base.merge(l, r)
  assert_eq(report.conflict_count(), 1)
  assert_eq(
    report.conflicts()[0].kind(),
    @trace.MergeConflictKind::EffectiveDiverged,
  )
  assert_eq(report.conflicts()[0].path(), p)
  assert_eq(report.conflicts()[0].merged_json(), Some("2"))
  assert_true(report.candidate() is None)
}

///|
test "merge refuses a redundant local override that hides the other branch correction" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let base = merge_fixture([p], [("bold.json", "{\"x\":0}")])
  let l = merge_fixture([p], [("bold.json", "{\"x\":1}")])
  let r = merge_fixture([p], [
    ("bold.json", "{\"x\":0}"),
    ("sub-01/sub-01_bold.json", "{\"x\":0}"),
  ])
  let report = base.merge(l, r)
  assert_eq(
    report.conflicts()[0].kind(),
    @trace.MergeConflictKind::InheritanceShadow,
  )
  assert_eq(report.conflicts()[0].base_json(), Some("0"))
  assert_eq(report.conflicts()[0].left_json(), Some("1"))
  assert_eq(report.conflicts()[0].right_json(), Some("0"))
  assert_eq(report.conflicts()[0].merged_json(), Some("0"))
  // Reconciliation is explicit, and a previous conflict did not mutate inputs.
  let fixed = merge_fixture([p], [
    ("bold.json", "{\"x\":0}"),
    ("sub-01/sub-01_bold.json", "{\"x\":1}"),
  ])
  assert_eq(
    base.merge(l, fixed).candidate().unwrap().resolve(p).to_json(),
    "{\"x\":1}",
  )
  assert_eq(base.resolve(p).to_json(), "{\"x\":0}")
}

///|
test "merge detects interactions between root changes and removed local overrides" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let base = merge_fixture([p], [
    ("bold.json", "{\"x\":0}"),
    ("sub-01/sub-01_bold.json", "{\"x\":2}"),
  ])
  let l = merge_fixture([p], [
    ("bold.json", "{\"x\":1}"),
    ("sub-01/sub-01_bold.json", "{\"x\":2}"),
  ])
  let r = merge_fixture([p], [("bold.json", "{\"x\":0}")])
  assert_eq(
    base.merge(l, r).conflicts()[0].kind(),
    @trace.MergeConflictKind::InheritanceShadow,
  )
}

///|
test "merge combines independent participant edits and retains provenance-only intent" {
  let a = "sub-01/func/sub-01_task-rest_bold.nii"
  let b = "sub-02/func/sub-02_task-rest_bold.nii"
  let base = merge_fixture([a, b], [("bold.json", "{\"x\":0}")])
  let l = merge_fixture([a, b], [
    ("bold.json", "{\"x\":0}"),
    ("sub-01/sub-01_bold.json", "{\"x\":1}"),
  ])
  let r = merge_fixture([a, b], [
    ("bold.json", "{\"x\":0}"),
    ("sub-02/sub-02_bold.json", "{\"x\":0}"),
  ])
  let report = base.merge(l, r)
  let after = report.candidate().unwrap()
  assert_eq(after.resolve(a).to_json(), "{\"x\":1}")
  assert_eq(after.resolve(b).trace("x").length(), 2)
  assert_eq(report.impact().unwrap().changed_count(), 2)
  let bundle = @trace.ReviewBundle::create(
    base,
    after,
    @trace.ReleasePolicy::AllChanges,
  )
  assert_eq(
    @trace.ReviewBundle::from_json(bundle.to_json()).to_json(),
    bundle.to_json(),
  )
}

///|
test "merge scan removal checks effective and provenance edits before dropping inventory" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let base = merge_fixture([p], [("bold.json", "{\"x\":0}")])
  let removed = merge_fixture([], [("bold.json", "{\"x\":0}")])
  assert_eq(base.merge(removed, base).candidate().unwrap().data_paths(), [])
  assert_eq(base.merge(removed, removed).candidate().unwrap().data_paths(), [])
  for extra in ["{}", "{\"x\":0}", "{\"x\":1}"] {
    let edited = merge_fixture([p], [
      ("bold.json", "{\"x\":0}"),
      ("sub-01/sub-01_bold.json", extra),
    ])
    let report = base.merge(removed, edited)
    assert_eq(
      report.conflicts()[0].kind(),
      @trace.MergeConflictKind::ScanDeleteEdit,
    )
    assert_true(report.conflicts()[0].left_json() is None)
    assert_true(report.conflicts()[0].right_json() is Some(_))
  }
}

///|
test "merge newly added scans reject accidental changes from the other branch ancestry" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let base = merge_fixture([], [("bold.json", "{\"x\":0}")])
  let added = merge_fixture([p], [("bold.json", "{\"x\":0}")])
  let edited = merge_fixture([], [("bold.json", "{\"x\":1}")])
  assert_eq(base.merge(added, base).candidate().unwrap().data_paths(), [p])
  assert_eq(
    base.merge(added, edited).conflicts()[0].kind(),
    @trace.MergeConflictKind::InheritanceShadow,
  )
  assert_eq(
    base.merge(edited, added).conflicts()[0].kind(),
    @trace.MergeConflictKind::InheritanceShadow,
  )
}

///|
test "merge retains every unresolved branch and resulting same-level ambiguity" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let empty = merge_fixture([p], [])
  let l = merge_fixture([p], [("bold.json", "{}")])
  let r = merge_fixture([p], [("task-rest_bold.json", "{}")])
  let combined = empty.merge(l, r)
  assert_true(combined.candidate() is None)
  assert_eq(combined.conflicts()[0].branch(), Some("merged"))
  assert_eq(
    combined.conflicts()[0].kind(),
    @trace.MergeConflictKind::UnresolvedMetadata,
  )
  let invalid = merge_fixture([p], [
    ("bold.json", "{}"),
    ("task-rest_bold.json", "{}"),
  ])
  let report = invalid.merge(invalid, invalid)
  assert_eq(report.conflict_count(), 4)
  assert_eq(report.conflicts().map(c => c.branch()), [
    Some("base"),
    Some("left"),
    Some("right"),
    Some("merged"),
  ])
  let diagnostics = report.conflicts()[0].diagnostics()
  diagnostics[0].related.clear()
  diagnostics.clear()
  assert_false(report.conflicts()[0].diagnostics().is_empty())
  assert_false(report.conflicts()[0].diagnostics()[0].related.is_empty())
  let conflicts = report.conflicts()
  conflicts.clear()
  assert_eq(report.conflict_count(), 4)
}

///|
test "merge revalidates final case collisions and does not return partial success" {
  let base = merge_fixture([], [])
  let l = merge_fixture(["sub-a/anat/sub-a_T1w.nii"], [])
  let r = merge_fixture(["sub-A/anat/sub-A_T1w.nii"], [])
  let report = base.merge(l, r)
  assert_eq(
    report.conflicts()[0].kind(),
    @trace.MergeConflictKind::InvalidSnapshot,
  )
  assert_eq(report.conflicts()[0].branch(), Some("merged"))
  assert_false(report.conflicts()[0].diagnostics().is_empty())
  assert_true(report.candidate() is None)
  assert_eq(
    base.merge(l, base).candidate().unwrap().data_paths(),
    l.data_paths(),
  )
}

///|
test "merge structural conflicts are ordered before semantic validation" {
  let p = "sub-01/func/sub-01_task-rest_bold.nii"
  let base = merge_fixture([p], [("bold.json", "{\"z\":0,\"a\":0}")])
  let l = merge_fixture([p], [
    ("bold.json", "{\"z\":1,\"a\":1}"),
    ("task-rest_bold.json", "{}"),
  ])
  let r = merge_fixture([p], [("bold.json", "{\"z\":2,\"a\":2}")])
  let report = base.merge(l, r)
  assert_eq(report.conflict_count(), 2)
  assert_eq(report.conflicts().map(c => c.key()), [Some("a"), Some("z")])
  assert_eq(report.conflicts().map(c => c.kind()), [
    @trace.MergeConflictKind::FieldDiverged,
    @trace.MergeConflictKind::FieldDiverged,
  ])
  assert_eq(report.to_json(), base.merge(l, r).to_json())
}

///|
test "merge conflict limit is explicit at 1024 and recovery preserves inputs" {
  let make = (count, value) => {
    let fields = Array::makei(count, i => "\"k" + i.to_string() + "\":" + value)
    "{" + fields.join(",") + "}"
  }
  for count in [1024, 1025] {
    let base = merge_fixture([], [("bold.json", make(count, "0"))])
    let l = merge_fixture([], [("bold.json", make(count, "1"))])
    let r = merge_fixture([], [("bold.json", make(count, "2"))])
    if count == 1024 {
      assert_eq(base.merge(l, r).conflict_count(), count)
    } else {
      try base.merge(l, r) catch {
        @trace.TraceError(d) => assert_eq(d.code, "merge_conflict_limit")
      } noraise {
        _ => fail("Expected bounded conflict rejection")
      }
    }
    assert_eq(
      base.merge(l, base).candidate().unwrap().to_manifest_json(),
      l.to_manifest_json(),
    )
  }
}
