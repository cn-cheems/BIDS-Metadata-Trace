///|
// Moonrun supplies the WASI process exit; core domain logic has no FFI.
extern "wasm" fn exit(code : Int) -> Unit = "wasi_snapshot_preview1" "proc_exit"

///|
fn usage() -> String {
  "Usage: bids-metadata-trace discover DATASET_DIR [--manifest-only] | sources MANIFEST.json | summarize MANIFEST.json FIELD... | table MANIFEST.json FIELD... | plan MANIFEST.json SIDECAR_PATH PATCH.json [--manifest-only] | plan-batch MANIFEST.json BATCH.json [--manifest-only] | bundle BEFORE.json AFTER.json [--effective-only] | replay BUNDLE.json | resolve MANIFEST.json DATA_PATH | audit MANIFEST.json [DATA_PATH ...] | diff BEFORE.json AFTER.json | check BEFORE.json AFTER.json [--effective-only]"
}

///|
async fn load_bundle(path : String) -> @trace.ReviewBundle {
  try {
    if @fs.file_size(path) > 67108864L {
      raise @trace.TraceError({
        code: "input_limit",
        path,
        message: "Review bundle exceeds 64 MiB on disk; split the snapshots.",
        offset: None,
        related: [],
      })
    }
    @trace.ReviewBundle::from_json(@fs.read_file(path).text())
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
async fn load_patch(path : String) -> @trace.MetadataPatch {
  try {
    if @fs.file_size(path) > 8388608L {
      raise @trace.TraceError({
        code: "input_limit",
        path,
        message: "Patch exceeds 8 MiB on disk; reduce the proposed edit.",
        offset: None,
        related: [],
      })
    }
    @trace.MetadataPatch::from_json(@fs.read_file(path).text())
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
      usage() +
      "\nOutputs JSON; table outputs quoted CSV with tagged JSON cells. Exit: 0 success/pass, 1 failure. check defaults to all changes; --effective-only ignores provenance-only edits but retains their evidence. bundle/replay exit 0 for successful capture/verified reproduction, regardless of release decision; use check for a release gate. JSON decision distinguishes changes_detected from indeterminate. Input/IO errors produce a diagnostic on stderr instead of a completed report.",
    )
    return
  }
  if args.length() < 3 ||
    !(((args[1] == "resolve" || args[1] == "diff") && args.length() == 4) ||
    args[1] == "audit" ||
    (args[1] == "sources" && args.length() == 3) ||
    ((args[1] == "summarize" || args[1] == "table") && args.length() >= 4) ||
    (args[1] == "replay" && args.length() == 3) ||
    (
      args[1] == "plan-batch" &&
      (
        args.length() == 4 ||
        (args.length() == 5 && args[4] == "--manifest-only")
      )
    ) ||
    (
      args[1] == "plan" &&
      (
        args.length() == 5 ||
        (args.length() == 6 && args[5] == "--manifest-only")
      )
    ) ||
    (
      args[1] == "discover" &&
      (
        args.length() == 3 ||
        (args.length() == 4 && args[3] == "--manifest-only")
      )
    ) ||
    (
      (args[1] == "check" || args[1] == "bundle") &&
      (
        args.length() == 4 ||
        (args.length() == 5 && args[4] == "--effective-only")
      )
    )) {
    @stdio.stderr.write(usage() + "\n")
    exit(1)
    return
  }
  try {
    if args[1] == "replay" {
      println(load_bundle(args[2]).report().to_json())
      return
    }
    if args[1] == "discover" {
      let report = discover(args[2])
      println(
        if args.length() == 4 {
          report.index().to_manifest_json()
        } else {
          report.to_json()
        },
      )
      return
    }
    let index = load_manifest(args[2])
    if args[1] == "table" {
      let audit = index.audit_all()
      @stdio.stdout.write(audit.to_review_csv(args[3:].to_owned()))
      if audit.error_count() > 0 {
        exit(1)
      }
    } else if args[1] == "summarize" {
      let report = index.audit_all().summarize_fields(args[3:].to_owned())
      println(report.to_json())
      if report.error_count() > 0 {
        exit(1)
      }
    } else if args[1] == "sources" {
      let report = index.source_coverage()
      println(report.to_json())
      if report.error_count() > 0 {
        exit(1)
      }
    } else if args[1] == "bundle" {
      let policy = if args.length() == 5 {
        @trace.ReleasePolicy::EffectiveValues
      } else {
        @trace.ReleasePolicy::AllChanges
      }
      println(
        @trace.ReviewBundle::create(index, load_manifest(args[3]), policy).to_json(),
      )
    } else if args[1] == "plan-batch" {
      let plan = index.plan_edits(load_edit_batch(args[3]))
      println(
        if args.length() == 5 {
          plan.after().to_manifest_json()
        } else {
          plan.to_json()
        },
      )
      if plan.impact().error_count() > 0 {
        exit(1)
      }
    } else if args[1] == "plan" {
      let plan = index.plan_edit(args[3], load_patch(args[4]))
      println(
        if args.length() == 6 {
          plan.after().to_manifest_json()
        } else {
          plan.to_json()
        },
      )
      if plan.impact().error_count() > 0 {
        exit(1)
      }
    } else if args[1] == "check" {
      let policy = if args.length() == 5 {
        @trace.ReleasePolicy::EffectiveValues
      } else {
        @trace.ReleasePolicy::AllChanges
      }
      let check = index.compare(load_manifest(args[3])).release_check(policy)
      println(check.to_json())
      match check.decision() {
        Pass => ()
        ChangesDetected => exit(1)
        Indeterminate => exit(1)
      }
    } else if args[1] == "diff" {
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
