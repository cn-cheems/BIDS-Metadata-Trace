///|
#cfg(target="js")
test "Node benchmark argv removes only the runtime executable" {
  assert_eq(
    benchmark_args(["node", "benchmark.js", "audit", "scoped", "100", "3"]),
    ["benchmark.js", "audit", "scoped", "100", "3"],
  )
  assert_eq(benchmark_args(["node", "benchmark.js"]), ["benchmark.js"])
  assert_eq(benchmark_args([]), [])
}

///|
#cfg(not(target="js"))
test "native and WASI benchmark argv preserve the program entry" {
  let raw = ["benchmark", "audit", "scoped", "100", "3"]
  assert_eq(benchmark_args(raw), raw)
  assert_eq(benchmark_args([]), [])
}

///|
test "benchmark workloads exercise distinct source distributions with exact metadata" {
  for (shape, expected) in [("sparse", 1), ("scoped", 76), ("root-heavy", 101)] {
    let (files, sources) = workload(100, shape, false)
    assert_eq(files.length(), 100)
    assert_eq(sources.length(), expected)
    let index = @trace.DatasetIndex::from_manifest(files, sources)
    assert_eq(index.audit_all().error_count(), 0)
    assert_eq(
      index.resolve(files[0]).get("vendor").unwrap().stringify(),
      "[null,-0,9007199254740993,1e999]",
    )
    let (paths, changed) = workload(100, shape, true)
    assert_eq(
      index
      .compare(@trace.DatasetIndex::from_manifest(paths, changed))
      .changed_count(),
      100,
    )
  }
}

///|
test "benchmark phase checks consume real results including serialized evidence" {
  let (files, sources) = workload(4, "scoped", false)
  let index = @trace.DatasetIndex::from_manifest(files, sources)
  let (paths, changed) = workload(4, "scoped", true)
  let after = @trace.DatasetIndex::from_manifest(paths, changed)
  let audit = index.audit_all()
  for phase in ["build", "audit", "compare"] {
    assert_eq(execute(phase, files, sources, index, after, audit), 4)
  }
  assert_eq(
    execute("serialize", files, sources, index, after, audit),
    audit.to_json().length(),
  )
}
