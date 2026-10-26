///|
fn workload(
  count : Int32,
  shape : String,
  changed : Bool,
) -> (Array[String], Array[@trace.SidecarInput]) {
  let files : Array[String] = []
  let sources = [
    @trace.SidecarInput::new(
      "bold.json",
      if changed {
        "{\"RepetitionTime\":3.0,\"vendor\":[null,-0,9007199254740993,1e999]}"
      } else {
        "{\"RepetitionTime\":2.0,\"vendor\":[null,-0,9007199254740993,1e999]}"
      },
    ),
  ]
  for i in 0..<count {
    let subject = (i / 4 + 1).to_string()
    let session = if i % 4 < 2 { "pre" } else { "post" }
    let run = (i % 2 + 1).to_string()
    let scope = "sub-" + subject + "/ses-" + session
    let entities = "sub-" + subject + "_ses-" + session
    files.push(
      scope + "/func/" + entities + "_task-rest_run-" + run + "_bold.nii.gz",
    )
    if shape == "scoped" && i % 2 == 0 {
      sources.push(
        @trace.SidecarInput::new(
          scope + "/" + entities + "_task-rest_bold.json",
          "{\"EchoTime\":0.03,\"PhaseEncodingDirection\":\"j\"}",
        ),
      )
    }
    if shape == "scoped" && i % 4 == 0 {
      sources.push(
        @trace.SidecarInput::new(
          "sub-" + subject + "/anat/sub-" + subject + "_T1w.json",
          "{\"EchoTime\":0.004}",
        ),
      )
    }
    if shape == "root-heavy" {
      sources.push(
        @trace.SidecarInput::new(
          "task-noise" + i.to_string() + "_bold.json",
          "{\"EchoTime\":0.01}",
        ),
      )
    }
  }
  (files, sources)
}

///|
fn execute(
  phase : String,
  files : Array[String],
  sources : Array[@trace.SidecarInput],
  index : @trace.DatasetIndex,
  after : @trace.DatasetIndex,
  audit : @trace.AuditReport,
) -> Int32 raise {
  match phase {
    "build" =>
      @trace.DatasetIndex::from_manifest(files, sources).data_paths().length()
    "audit" => {
      let report = index.audit_all()
      assert_eq(report.error_count(), 0)
      report.entries().length()
    }
    "compare" => {
      let report = index.compare(after)
      assert_eq(report.error_count(), 0)
      report.changed_count()
    }
    "serialize" => audit.to_json().length()
    _ => abort("validated phase")
  }
}

///|
fn argument_error(message : String) -> Unit raise {
  // Release Wasm may strip failure strings; retain one complete diagnostic.
  println(
    Json::object({
      "status": Json::string("error"),
      "code": Json::string("invalid_benchmark_arguments"),
      "message": Json::string(message),
    }).stringify(),
  )
  fail(message)
}

///|
#cfg(target="js")
fn benchmark_args(raw : Array[String]) -> Array[String] {
  // core/env exposes Node's [node, script, ...], unlike native/WASI argv.
  if raw.length() >= 2 {
    raw[1:].to_owned()
  } else {
    raw
  }
}

///|
#cfg(not(target="js"))
fn benchmark_args(raw : Array[String]) -> Array[String] {
  raw
}

///|
fn main raise {
  let args = benchmark_args(@env.args())
  guard args.length() == 5 else {
    argument_error(
      "Usage: benchmark build|audit|compare|serialize|evidence sparse|scoped|root-heavy SCANS SAMPLES",
    )
    return
  }
  let phase = args[1]
  let shape = args[2]
  guard ["build", "audit", "compare", "serialize", "evidence"].contains(phase) &&
    ["sparse", "scoped", "root-heavy"].contains(shape) else {
    argument_error("Unknown phase or workload shape")
    return
  }
  let count = @string.parse_int(args[3]) catch {
    _ => {
      argument_error("SCANS must be an integer")
      0
    }
  }
  let samples = @string.parse_int(args[4]) catch {
    _ => {
      argument_error("SAMPLES must be an integer")
      0
    }
  }
  guard count > 0 && count <= 5000 && samples >= 3 && samples <= 31 else {
    argument_error("SCANS must be 1..5000; SAMPLES must be 3..31")
    return
  }
  let (files, sources) = workload(count, shape, false)
  let index = @trace.DatasetIndex::from_manifest(files, sources)
  let after = if phase == "compare" || phase == "evidence" {
    let (paths, inputs) = workload(count, shape, true)
    @trace.DatasetIndex::from_manifest(paths, inputs)
  } else {
    index
  }
  let audit = if phase == "serialize" || phase == "evidence" {
    index.audit_all()
  } else {
    index.audit([])
  }
  if phase == "evidence" {
    println(
      "{\"audit\":" +
      audit.to_json() +
      ",\"impact\":" +
      index.compare(after).to_json() +
      ",\"manifest\":" +
      index.to_manifest_json() +
      "}",
    )
    return
  }
  ignore(execute(phase, files, sources, index, after, audit)) // one untimed warmup
  let elapsed : Array[Double] = []
  let mut checksum = 0L
  for _ in 0..<samples {
    let start = @bench.monotonic_clock_start()
    checksum += execute(phase, files, sources, index, after, audit).to_int64()
    elapsed.push(@bench.monotonic_clock_end(start))
  }
  let sorted = elapsed.copy()
  sorted.sort()
  println(
    Json::object({
      "phase": Json::string(phase),
      "shape": Json::string(shape),
      "scans": Json::number(count.to_double()),
      "sources": Json::number(sources.length().to_double()),
      "snapshot_utf16_units": Json::number(
        index.to_manifest_json().length().to_double(),
      ),
      "samples_us": Json::array(elapsed.map(value => Json::number(value))),
      "median_us": Json::number(sorted[sorted.length() / 2]),
      "checksum": Json::string(checksum.to_string()),
    }).stringify(),
  )
}
