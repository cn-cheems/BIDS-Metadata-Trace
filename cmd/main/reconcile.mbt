///|
async fn run_reconciliation(args : Array[String]) -> Unit {
  let report = load_manifest(args[2]).merge(
    load_manifest(args[3]),
    load_manifest(args[4]),
  )
  let resolution = @trace.MergeResolution::from_json(
    read_control(args[5], large=true),
  )
  let reconciled = report.reconcile(resolution)
  let mode = if args.length() == 7 { args[6] } else { "report" }
  if mode == "report" {
    println(reconciled.to_json())
    if reconciled.conflict_count() > 0 {
      exit(1)
    }
    return
  }
  guard reconciled.candidate() is Some(candidate) else {
    raise @trace.TraceError({
      code: "reconciliation_blocked",
      path: args[5],
      message: "Unresolved conflicts block manifest/bundle export; omit the output flag to inspect revalidated conflicts.",
      offset: None,
      related: [],
    })
  }
  if mode == "--manifest-only" {
    println(candidate.to_manifest_json())
  } else {
    println(
      reconciled
      .review_bundle(
        if mode == "--effective-bundle" {
          @trace.ReleasePolicy::EffectiveValues
        } else {
          AllChanges
        },
      )
      .to_json(),
    )
  }
}
