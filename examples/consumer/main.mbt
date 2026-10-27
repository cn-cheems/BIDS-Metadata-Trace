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
  let annotation = baseline
    .plan_edit(
      "bold.json",
      @trace.MetadataPatch::from_json(
        "{\"set\":{\"ReviewNote\":null},\"remove\":[]}",
      ),
    )
    .after()
  let merge = baseline.merge(plan.after(), annotation)
  guard merge.conflict_count() == 0 && merge.candidate() is Some(merged) else {
    fail("Independent public API consumer could not merge disjoint fields")
  }
  guard merged.resolve(post).to_json().contains("\"ReviewNote\":null") &&
    merge.impact().unwrap().error_count() == 0 else {
    fail("Merge dropped metadata or failed inheritance validation")
  }
  let numeric = @trace.NumericRules::from_json(
    "{\"fields\":{\"RepetitionTime\":{\"type\":\"number\",\"gt\":2,\"lte\":3}},\"relations\":[]}",
  )
  let query = @trace.MetadataQuery::from_json(
    "{\"present\":[],\"absent\":[],\"equals\":{}}",
  ).with_numeric(numeric)
  guard merged.select_metadata(query).paths() == [post] else {
    fail("Numeric predicates lost inherited session scope")
  }
  let expected = @trace.MetadataExpectations::from_json(
    "{\"required\":[],\"allowed\":{}}",
  ).with_numeric(
    @trace.NumericRules::from_json(
      "{\"fields\":{\"RepetitionTime\":{\"type\":\"number\",\"gt\":0,\"lte\":3}},\"relations\":[]}",
    ),
  )
  guard merged.audit_all().check_expectations(expected).violation_count() == 0 else {
    fail("Numeric expectations failed in independent archive consumer")
  }
  let resolution = @trace.MergeResolution::from_json(
    merge.resolution_template(),
  )
  let reconciled = merge.reconcile(resolution)
  let merge_bundle = reconciled.review_bundle(@trace.ReleasePolicy::AllChanges)
  guard @trace.MergeReviewBundle::from_json(merge_bundle.to_json()).to_json() ==
    merge_bundle.to_json() &&
    reconciled.conflict_count() == 0 else {
    fail("Archive consumer failed explicit merge review replay")
  }
  println("{\"consumer\":\"passed\",\"changed_scans\":1,\"scans\":2}")
}
