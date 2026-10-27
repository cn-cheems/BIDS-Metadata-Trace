///|
test "dependency edge count accepts exact cap rejects overflow and recovers" {
  assert_eq(graph_count_edges(1048575, 1), 1048576)
  assert_eq(graph_count_edges(1048576, 0), 1048576)
  try graph_count_edges(1048576, 1) catch {
    TraceError(d) => assert_eq(d.code, "dependency_graph_limit")
  } noraise {
    _ => fail("edge overflow")
  }
  assert_eq(graph_count_edges(0, 1), 1)
}

///|
test "full verification rejects corrupted incremental evidence and permits fresh retry" {
  let before = DatasetIndex::from_manifest(
    ["sub-01/func/sub-01_task-rest_bold.nii"],
    [SidecarInput::new("bold.json", "{\"x\":1}")],
  )
  let result = before.dependency_graph().advance(before)
  let corrupted : IncrementalImpact = {
    before: result.before,
    next: result.next,
    report: { entries: [], },
    invalidated: result.invalidated,
    changed_sources: result.changed_sources,
    reused: result.reused,
    resolved: result.resolved,
  }
  try corrupted.verify_full() catch {
    TraceError(d) => assert_eq(d.code, "incremental_mismatch")
  } noraise {
    _ => fail("corrupted evidence must fail equivalence")
  }
  result.verify_full()
  assert_eq(result.report.entries.length(), 1)
}
