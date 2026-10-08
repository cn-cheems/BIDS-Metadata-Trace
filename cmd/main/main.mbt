///|
// Moonrun supplies the WASI process exit; core domain logic has no FFI.
extern "wasm" fn exit(code : Int) -> Unit = "wasi_snapshot_preview1" "proc_exit"

///|
async fn load_manifest(path : String) -> @trace.DatasetIndex {
  try {
    if @fs.file_size(path) > 8388608L {
      raise @trace.TraceError({
        code: "input_limit",
        path,
        message: "Manifest exceeds 8 MiB on disk; split the snapshot.",
        offset: None,
        related: [],
      })
    }
    @trace.DatasetIndex::from_json(@fs.read_file(path).text())
  } catch {
    @trace.TraceError(diagnostic) => raise @trace.TraceError(diagnostic)
    error =>
      raise @trace.TraceError({
        code: "io_error",
        path,
        message: error.to_string(),
        offset: None,
        related: [],
      })
  }
}

///|
async fn main {
  let args = @env.args()
  if args.length() == 2 && (args[1] == "--help" || args[1] == "-h") {
    println(
      "Usage: bids-metadata-trace resolve MANIFEST.json DATA_PATH | audit MANIFEST.json [DATA_PATH ...] | diff BEFORE.json AFTER.json\nOutputs JSON. Exit: 0 success, 1 input/IO/query error, 2 usage error. Audit/diff retain all outcomes on stdout. Diff exits 0 for determinate changes.",
    )
    return
  }
  if args.length() < 3 ||
    !(((args[1] == "resolve" || args[1] == "diff") && args.length() == 4) ||
    args[1] == "audit") {
    @stdio.stderr.write(
      "Usage: bids-metadata-trace resolve MANIFEST.json DATA_PATH | audit MANIFEST.json [DATA_PATH ...] | diff BEFORE.json AFTER.json\n",
    )
    exit(2)
    return
  }
  try {
    let index = load_manifest(args[2])
    if args[1] == "diff" {
      let report = index.compare(load_manifest(args[3]))
      println(report.to_json())
      if report.error_count() > 0 {
        exit(1)
      }
    } else if args[1] == "audit" {
      let report = if args.length() == 3 {
        index.audit_all()
      } else {
        index.audit(args[3:].to_owned())
      }
      println(report.to_json())
      if report.error_count() > 0 {
        exit(1)
      }
    } else {
      println(index.resolve(args[3]).to_report_json())
    }
  } catch {
    @trace.TraceError(diagnostic) => {
      @stdio.stderr.write(diagnostic.to_report_json() + "\n")
      exit(1)
    }
    error => {
      let diagnostic : @trace.Diagnostic = {
        code: "io_error",
        path: args[2],
        message: error.to_string(),
        offset: None,
        related: [],
      }
      @stdio.stderr.write(diagnostic.to_report_json() + "\n")
      exit(1)
    }
  }
}
