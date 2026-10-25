///|
fn main raise {
  let pre = "sub-01/ses-pre/func/sub-01_ses-pre_task-rest_bold.nii"
  let post = "sub-01/ses-post/func/sub-01_ses-post_task-rest_bold.nii"
  let baseline = @trace.DatasetIndex::from_manifest([pre, post], [
    @trace.SidecarInput::new(
      "bold.json", "{\"RepetitionTime\":2.0,\"vendor\":9007199254740993}",
    ),
  ])
  let before = baseline.to_manifest_json()
  let changes = @trace.DatasetChanges::new(
    @trace.ScanChanges::new([], []),
    @trace.SourceChanges::new(
      [
        @trace.SidecarInput::new(
          "sub-01/ses-post/sub-01_ses-post_task-rest_bold.json", "{\"RepetitionTime\":3.0}",
        ),
      ],
      [],
    ),
    @trace.EditBatch::from_patches([]),
  )
  let plan = baseline.plan_changes(changes)
  guard plan.impact().changed_count() == 1 && plan.impact().error_count() == 0 else {
    fail("Expected exactly one determinate scan change")
  }
  guard plan.after().resolve(pre).get("RepetitionTime").unwrap().stringify() ==
    "2.0" &&
    plan.after().resolve(post).get("RepetitionTime").unwrap().stringify() ==
    "3.0" else {
    fail("Session override escaped its scope")
  }
  guard plan.after().resolve(post).get("vendor").unwrap().stringify() ==
    "9007199254740993" else {
    fail("Unknown metadata or exact numeric value was lost")
  }
  let rules = @trace.ConsistencyRules::new(["sub"], ["RepetitionTime"], true)
  guard plan.after().audit_all().check_consistency(rules).violation_count() == 1 else {
    fail("Consumer failed to detect cross-session mismatch")
  }
  guard baseline.audit(["missing", pre]).error_count() == 1 &&
    baseline.audit_all().error_count() == 0 else {
    fail("Audit errors did not remain isolated")
  }
  let bundle = @trace.ReviewBundle::create(
    baseline,
    plan.after(),
    @trace.ReleasePolicy::EffectiveValues,
  )
  guard @trace.ReviewBundle::from_json(bundle.to_json()).to_json() ==
    bundle.to_json() &&
    baseline.to_manifest_json() == before else {
    fail("Replay or immutable baseline contract failed")
  }
  println("{\"consumer\":\"passed\",\"changed_scans\":1,\"scans\":2}")
}
