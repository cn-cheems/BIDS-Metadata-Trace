///|
// Moonrun supplies the WASI process exit; core domain logic has no FFI.
extern "wasm" fn exit(code : Int) -> Unit = "wasi_snapshot_preview1" "proc_exit"

///|
async fn main {
  let args = @env.args()
  if args.length() == 2 && (args[1] == "--help" || args[1] == "-h") {
    println(
      "Usage: bids-metadata-trace resolve MANIFEST.json DATA_PATH | audit MANIFEST.json [DATA_PATH ...]\nOutputs JSON. Exit: 0 success, 1 input/IO/query error, 2 usage error. Audit retains all query outcomes on stdout.",
    )
    return
  }
  if args.length() < 3 ||
    !((args[1] == "resolve" && args.length() == 4) || args[1] == "audit") {
    @stdio.stderr.write(
      "Usage: bids-metadata-trace resolve MANIFEST.json DATA_PATH | audit MANIFEST.json [DATA_PATH ...]\n",
    )
    exit(2)
    return
  }
  try {
    if @fs.file_size(args[2]) > 8388608L {
      @stdio.stderr.write(
        "{\"code\":\"input_limit\",\"message\":\"Manifest exceeds 8 MiB on disk.\"}\n",
      )
      exit(1)
      return
    }
    let text = @fs.read_file(args[2]).text()
    let index = @trace.DatasetIndex::from_json(text)
    if args[1] == "audit" {
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
