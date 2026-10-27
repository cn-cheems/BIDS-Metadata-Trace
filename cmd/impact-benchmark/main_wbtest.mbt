///|
test "benchmark workload full equivalence and expected invalidation work" {
  for
    shape in [
      "local", "root", "add", "remove", "unmatched", "noop", "inventory", "ambiguity",
    ] {
    let (before, after) = impact_workload(100, shape)
    let graph = before.dependency_graph()
    let update = graph.advance(after)
    update.verify_full()
    let expected = match shape {
      "root" | "ambiguity" => 100
      "unmatched" | "noop" => 0
      "inventory" => 1
      _ => 2
    }
    assert_eq(update.resolved_count(), expected)
    assert_eq(update.reused_count(), 100 - expected)
    assert_eq(
      impact_execute("cold", before, after, None),
      impact_execute("full", before, after, None),
    )
    assert_eq(
      impact_execute("warm", before, after, Some(graph)),
      impact_execute("full", before, after, None),
    )
  }
}

///|
#cfg(target="js")
test "benchmark Node argument adapter" {
  assert_eq(impact_args(["node", "script.js", "warm"]), ["script.js", "warm"])
}

///|
#cfg(not(target="js"))
test "benchmark process argument adapter" {
  assert_eq(impact_args(["benchmark", "warm"]), ["benchmark", "warm"])
}
