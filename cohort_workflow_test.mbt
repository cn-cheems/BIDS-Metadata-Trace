///|
fn cohort_path(subject : String, session : String, run : String) -> String {
  "sub-" +
  subject +
  "/ses-" +
  session +
  "/func/sub-" +
  subject +
  "_ses-" +
  session +
  "_task-rest_run-" +
  run +
  "_bold.nii.gz"
}

///|
test "subject session overrides isolate impact and ambiguous scans recover" {
  let paths = [
    cohort_path("01", "pre", "01"),
    cohort_path("01", "post", "01"),
    cohort_path("02", "pre", "01"),
    cohort_path("02", "post", "01"),
  ]
  let index = @trace.DatasetIndex::from_manifest(paths, [
    @trace.SidecarInput::new(
      "task-rest_bold.json", "{\"RepetitionTime\":2.0,\"vendor\":{\"raw\":9007199254740993}}",
    ),
  ])
  let before = index.to_manifest_json()
  let local_source = "sub-01/ses-post/sub-01_ses-post_task-rest_bold.json"
  let plan = index.plan_sources(
    @trace.SourceChanges::new(
      [@trace.SidecarInput::new(local_source, "{\"RepetitionTime\":3.0}")],
      [],
    ),
  )
  assert_eq(plan.impact().changed_count(), 1)
  for path in paths {
    let result = plan.after().resolve(path)
    assert_eq(
      result.get("RepetitionTime").unwrap().stringify(),
      if path == paths[1] {
        "3.0"
      } else {
        "2.0"
      },
    )
    assert_eq(
      result.get("vendor").unwrap().stringify(),
      "{\"raw\":9007199254740993}",
    )
  }
  assert_eq(plan.after().resolve(paths[1]).trace("RepetitionTime").length(), 2)
  let broken = plan
    .after()
    .plan_sources(
      @trace.SourceChanges::new(
        [
          @trace.SidecarInput::new(
            "sub-01/ses-post/sub-01_ses-post_run-01_bold.json", "{\"RepetitionTime\":3.0}",
          ),
        ],
        [],
      ),
    )
  assert_eq(broken.after().audit_all().error_count(), 1)
  let recovered = broken
    .after()
    .plan_sources(
      @trace.SourceChanges::new([], [
        "sub-01/ses-post/sub-01_ses-post_run-01_bold.json",
      ]),
    )
  assert_eq(
    recovered.after().to_manifest_json(),
    plan.after().to_manifest_json(),
  )
  let bundle = @trace.ReviewBundle::create(
    index,
    plan.after(),
    @trace.ReleasePolicy::EffectiveValues,
  )
  assert_eq(
    @trace.ReviewBundle::from_json(bundle.to_json()).to_json(),
    bundle.to_json(),
  )
  assert_eq(index.to_manifest_json(), before)
}

///|
test "one thousand synthetic cohort scans retain deterministic snapshots and scoped impacts" {
  let paths : Array[String] = []
  for participant in 1..<251 {
    for session in ["pre", "post"] {
      for run in ["01", "02"] {
        paths.push(cohort_path(participant.to_string(), session, run))
      }
    }
  }
  let index = @trace.DatasetIndex::from_manifest(paths, [
    @trace.SidecarInput::new(
      "task-rest_bold.json", "{\"RepetitionTime\":2.0,\"unknown\":[null,-0,1e999]}",
    ),
  ])
  assert_eq(index.data_paths().length(), 1000)
  assert_eq(index.audit_all().error_count(), 0)
  let rules = @trace.ConsistencyRules::new(
    ["sub", "ses"],
    ["RepetitionTime"],
    true,
  )
  assert_true(
    index.audit_all().check_consistency(rules).decision() ==
    @trace.ExpectationDecision::Pass,
  )
  let plan = index.plan_sources(
    @trace.SourceChanges::new(
      [
        @trace.SidecarInput::new(
          "sub-1/ses-post/sub-1_ses-post_task-rest_bold.json", "{\"RepetitionTime\":3.0}",
        ),
      ],
      [],
    ),
  )
  assert_eq(plan.impact().changed_count(), 2)
  assert_eq(
    @trace.DatasetIndex::from_json(index.to_manifest_json()).to_manifest_json(),
    index.to_manifest_json(),
  )
  let reversed = Array::makei(paths.length(), i => paths[paths.length() - 1 - i])
  assert_eq(
    @trace.DatasetIndex::from_manifest(reversed, [
      @trace.SidecarInput::new(
        "task-rest_bold.json", "{\"RepetitionTime\":2.0,\"unknown\":[null,-0,1e999]}",
      ),
    ]).to_manifest_json(),
    index.to_manifest_json(),
  )
}
