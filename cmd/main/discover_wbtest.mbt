///|
async fn clean_test_directory(root : String) -> Unit {
  let absolute = @fs.realpath(root)
  let normalized = absolute.replace_all(old="\\", new="/")
  guard normalized
    .split("/")
    .last()
    .unwrap()
    .has_prefix("bids-trace-discovery.") else {
    fail("Refusing cleanup outside the explicitly created test directory.")
  }
  @fs.rmdir(absolute, recursive=true)
}

///|
async test "filesystem discovery reads sidecars but never reads image contents" {
  let root = @fs.tmpdir(prefix="bids-trace-discovery")
  @fs.mkdir(root + "/sub-01/func", recursive=true)
  let path = "sub-01/func/sub-01_task-rest_bold.nii.gz"
  @fs.write_file(root + "/" + path, b"\xff\xfe\x00")
  @fs.write_file(
    root + "/task-rest_bold.json",
    "{\"x\":9007199254740993,\"RT\":2.0}",
  )
  @fs.write_file(root + "/dataset_description.json", "not inspected")
  @fs.mkdir(root + "/derivatives")
  @fs.write_file(root + "/derivatives/unknown.json", "malformed")
  let report = discover(root)
  assert_eq(
    report.index().resolve(path).to_json(),
    "{\"RT\":2.0,\"x\":9007199254740993}",
  )
  assert_eq(report.excluded_paths(), ["derivatives"])
  assert_eq(report.auxiliary_paths(), ["dataset_description.json"])
  clean_test_directory(root)
}

///|
async test "unsupported input blocks discovery and removal permits a fresh retry" {
  let root = @fs.tmpdir(prefix="bids-trace-discovery")
  @fs.write_file(root + "/unknown.json", "{}")
  let code = try {
    discover(root) |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
    _ => "unexpected"
  }
  assert_eq(code, "unsupported_suffix")
  @fs.remove(root + "/unknown.json")
  assert_eq(discover(root).index().data_paths(), [])
  clean_test_directory(root)
}

///|
async test "invalid sidecar encoding is an explicit discovery error" {
  let root = @fs.tmpdir(prefix="bids-trace-discovery")
  @fs.write_file(root + "/bold.json", b"\xff")
  let code = try {
    discover(root) |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => {
      assert_eq(d.path, "bold.json")
      d.code
    }
    _ => "unexpected"
  }
  assert_eq(code, "discovery_io_error")
  clean_test_directory(root)
}

///|
async test "directory depth is bounded before unbounded recursion" {
  let root = @fs.tmpdir(prefix="bids-trace-discovery")
  @fs.mkdir(root + "/" + Array::make(33, "x").join("/"), recursive=true)
  let code = try {
    discover(root) |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
    _ => "unexpected"
  }
  assert_eq(code, "directory_limit")
  clean_test_directory(root)
}

///|
async test "non-directory dataset roots fail" {
  let root = @fs.tmpdir(prefix="bids-trace-discovery")
  @fs.write_file(root + "/file", "")
  let code = try {
    discover(root + "/file") |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
    _ => "unexpected"
  }
  assert_eq(code, "invalid_dataset_root")
  clean_test_directory(root)
}

///|
async test "symlink or Windows junction traversal is refused" {
  let root = @fs.tmpdir(prefix="bids-trace-discovery")
  @fs.mkdir(root + "/target")
  @fs.symlink(target=root + "/target", root + "/alias")
  let code = try {
    discover(root) |> ignore
    "success"
  } catch {
    @trace.TraceError(d) => d.code
    _ => "unexpected"
  }
  assert_eq(code, "unsupported_file_kind")
  @fs.remove(root + "/alias")
  clean_test_directory(root)
}
