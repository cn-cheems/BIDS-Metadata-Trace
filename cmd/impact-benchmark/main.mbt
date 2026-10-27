///|
fn impact_workload(
  count : Int32,
  shape : String,
) -> (@trace.DatasetIndex, @trace.DatasetIndex) raise {
  let files = Array::makei(count, i => {
    let subject = (i / 2 + 1).to_string()
    "sub-" +
    subject +
    "/func/sub-" +
    subject +
    "_task-rest_run-" +
    (i % 2 + 1).to_string() +
    "_bold.nii"
  })
  let root = "{\"RT\":2.0,\"opaque\":[null,-0,9007199254740993,1e999]}"
  let base = @trace.DatasetIndex::from_manifest(files, [
    @trace.SidecarInput::new("bold.json", root),
    @trace.SidecarInput::new("sub-1/sub-1_bold.json", "{\"RT\":3.0}"),
    @trace.SidecarInput::new("T1w.json", "{\"RT\":1}"),
  ])
  let sources = [
    @trace.SidecarInput::new(
      "bold.json",
      if shape == "root" {
        root.replace_all(old="2.0", new="4.0")
      } else {
        root
      },
    ),
  ]
  if shape != "remove" {
    sources.push(
      @trace.SidecarInput::new(
        "sub-1/sub-1_bold.json",
        if shape == "local" {
          "{\"RT\":4.0}"
        } else {
          "{\"RT\":3.0}"
        },
      ),
    )
  }
  sources.push(
    @trace.SidecarInput::new(
      "T1w.json",
      if shape == "unmatched" {
        "{\"RT\":9}"
      } else {
        "{\"RT\":1}"
      },
    ),
  )
  if shape == "add" {
    sources.push(@trace.SidecarInput::new("sub-2/sub-2_bold.json", "{}"))
  }
  if shape == "ambiguity" {
    sources.push(@trace.SidecarInput::new("task-rest_bold.json", "{}"))
  }
  let paths = if shape == "inventory" {
    files[:files.length() - 1].to_owned() +
    ["sub-new/func/sub-new_task-rest_bold.nii"]
  } else {
    files
  }
  (base, @trace.DatasetIndex::from_manifest(paths, sources))
}

///|
#cfg(target="js")
fn impact_args(raw : Array[String]) -> Array[String] {
  if raw.length() >= 2 {
    raw[1:].to_owned()
  } else {
    raw
  }
}

///|
#cfg(not(target="js"))
fn impact_args(raw : Array[String]) -> Array[String] {
  raw
}

///|
fn impact_argument_error(message : String) -> Unit raise {
  println(
    Json::object({
      "code": Json::string("invalid_impact_benchmark_arguments"),
      "message": Json::string(message),
    }).stringify(),
  )
  fail(message)
}

///|
fn impact_execute(
  phase : String,
  before : @trace.DatasetIndex,
  after : @trace.DatasetIndex,
  graph : @trace.DependencyGraph?,
) -> Int32 raise {
  match phase {
    "full" => {
      let report = before.compare(after)
      report.changed_count() + report.error_count()
    }
    "cold" => {
      let report = before.dependency_graph().advance(after).report()
      report.changed_count() + report.error_count()
    }
    "warm" => {
      let report = graph.unwrap().advance(after).report()
      report.changed_count() + report.error_count()
    }
    "graph" => before.dependency_graph().audit().entries().length()
    _ => abort("validated phase")
  }
}

///|
fn main raise {
  let args = impact_args(@env.args())
  guard args.length() == 5 else {
    impact_argument_error(
      "Usage: impact-benchmark full|cold|warm|graph|verify local|root|add|remove|unmatched|noop|inventory|ambiguity SCANS SAMPLES",
    )
    return
  }
  let phase = args[1]
  let shape = args[2]
  guard ["full", "cold", "warm", "graph", "verify"].contains(phase) &&
    [
      "local", "root", "add", "remove", "unmatched", "noop", "inventory", "ambiguity",
    ].contains(shape) else {
    impact_argument_error("Unsupported phase or shape")
    return
  }
  let count = @string.parse_int(args[3]) catch {
    _ => {
      impact_argument_error("SCANS must be an integer")
      0
    }
  }
  let samples = @string.parse_int(args[4]) catch {
    _ => {
      impact_argument_error("SAMPLES must be an integer")
      0
    }
  }
  guard count >= 4 && count <= 5000 && samples >= 3 && samples <= 31 else {
    impact_argument_error("SCANS must be 4..5000; SAMPLES must be 3..31")
    return
  }
  let (before, after) = impact_workload(count, shape)
  if phase == "verify" {
    let result = before.dependency_graph().advance(after)
    result.verify_full()
    println(result.to_json())
    return
  }
  // Only warm holds a prepared graph. Full/cold process RSS does not include
  // an untimed graph or full verification report from another phase.
  let graph = if phase == "warm" {
    Some(before.dependency_graph())
  } else {
    None
  }
  ignore(impact_execute(phase, before, after, graph))
  let elapsed : Array[Double] = []
  let mut checksum = 0L
  for _ in 0..<samples {
    let start = @bench.monotonic_clock_start()
    checksum += impact_execute(phase, before, after, graph).to_int64()
    elapsed.push(@bench.monotonic_clock_end(start))
  }
  let sorted = elapsed.copy()
  sorted.sort()
  println(
    Json::object({
      "phase": Json::string(phase),
      "shape": Json::string(shape),
      "scans": Json::number(count.to_double()),
      "samples_us": Json::array(elapsed.map(v => Json::number(v))),
      "median_us": Json::number(sorted[sorted.length() / 2]),
      "checksum": Json::string(checksum.to_string()),
    }).stringify(),
  )
}
