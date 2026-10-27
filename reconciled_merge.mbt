///|
/// A proposal after replaying explicit decisions and full inheritance checks.
/// Blocked proposals expose evidence, never a partial candidate or bundle.
pub struct ReconciledMerge {
  priv original : MergeReport
  priv resolution : MergeResolution
  priv validated : MergeReport
}

///|
pub fn MergeReport::reconcile(
  self : MergeReport,
  resolution : MergeResolution,
) -> ReconciledMerge raise TraceError {
  for
    (name, expected, actual) in [
      ("base", self.base, resolution.base),
      ("left", self.left, resolution.left),
      ("right", self.right, resolution.right),
    ] {
    if expected.to_manifest_json() != actual.to_manifest_json() {
      reject(
        "stale_merge_resolution",
        "<merge-resolution>/" + name,
        "Resolution is bound to different input content; regenerate the template and review the changed evidence.",
      )
    }
  }
  {
    original: self,
    resolution,
    validated: self.base.merge_with(self.left, self.right, Some(resolution)),
  }
}

///|
pub fn ReconciledMerge::candidate(self : ReconciledMerge) -> DatasetIndex? {
  self.validated.candidate()
}

///|
pub fn ReconciledMerge::conflicts(
  self : ReconciledMerge,
) -> Array[MergeConflict] {
  self.validated.conflicts()
}

///|
pub fn ReconciledMerge::conflict_count(self : ReconciledMerge) -> Int32 {
  self.validated.conflict_count()
}

///|
pub fn ReconciledMerge::impact(self : ReconciledMerge) -> ImpactReport? {
  self.validated.impact()
}

///|
/// Original conflicts, all decisions/reasons, all three inputs and the complete
/// revalidated base-to-candidate evidence. This is not a release approval.
pub fn ReconciledMerge::to_json(self : ReconciledMerge) -> String {
  "{\"initial\":" +
  self.original.to_json() +
  ",\"resolution\":" +
  self.resolution.to_json() +
  ",\"revalidated\":" +
  self.validated.to_json() +
  "}"
}

///|
/// Self-contained reconciliation and release evidence. Replay checks agreement,
/// not authorship, signatures, dataset authenticity or release authorization.
pub struct MergeReviewBundle {
  priv reconciliation : ReconciledMerge
  priv release : ReviewBundle
  priv serialized : String
}

///|
pub fn ReconciledMerge::review_bundle(
  self : ReconciledMerge,
  policy : ReleasePolicy,
) -> MergeReviewBundle raise TraceError {
  guard self.candidate() is Some(after) else {
    reject(
      "reconciliation_blocked", "<merge-review>", "Unresolved conflicts block bundle creation; inspect revalidated conflicts and revise the explicit decisions.",
    )
    abort("reject raises")
  }
  let release = ReviewBundle::create(self.original.base, after, policy)
  let parts = [
    "{\"expected\":",
    self.to_json(),
    ",\"format\":\"bids-metadata-trace/merge-review\",\"release\":",
    release.to_json(),
    ",\"resolution\":",
    self.resolution.to_json(),
    ",\"version\":1}",
  ]
  let mut length = 0
  for part in parts {
    if part.length() > 16777216 - length {
      reject(
        "bundle_limit", "<merge-review>", "Complete merge review exceeds 16,777,216 UTF-16 units; narrow the snapshots or decisions.",
      )
    }
    length += part.length()
  }
  { reconciliation: self, release, serialized: parts.join(""), }
}

///|
/// Recompute both the initial merge and reconciled candidate, verify all
/// recorded evidence and the release bundle's exact snapshots and policy.
pub fn MergeReviewBundle::from_json(
  text : String,
) -> MergeReviewBundle raise TraceError {
  let fields = resolution_object(
    parse_source(
      "<merge-review>",
      text,
      container_limit=96,
      text_limit=16777216,
    ),
    ["expected", "format", "release", "resolution", "version"],
    "<merge-review>",
  )
  if fields["format"] != Json::string("bids-metadata-trace/merge-review") ||
    canonical_json(fields["version"]) != "1" {
    reject(
      "unsupported_merge_review", "<merge-review>", "Expected bids-metadata-trace/merge-review version 1.",
    )
  }
  let resolution = MergeResolution::from_json(
    canonical_json(fields["resolution"]),
  )
  let reconciled = resolution.base
    .merge(resolution.left, resolution.right)
    .reconcile(resolution)
  if canonical_json(fields["expected"]) != reconciled.to_json() {
    reject(
      "replay_mismatch", "<merge-review>/expected", "Initial or revalidated evidence differs from the complete recorded inputs and decisions.",
    )
  }
  let release = ReviewBundle::from_json(canonical_json(fields["release"]))
  let regenerated = reconciled.review_bundle(release.report.policy)
  if release.to_json() != regenerated.release.to_json() {
    reject(
      "replay_mismatch", "<merge-review>/release", "Release evidence must use this reconciliation's exact base and candidate snapshots.",
    )
  }
  regenerated
}

///|
pub fn MergeReviewBundle::to_json(self : MergeReviewBundle) -> String {
  self.serialized
}

///|
pub fn MergeReviewBundle::reconciliation(
  self : MergeReviewBundle,
) -> ReconciledMerge {
  self.reconciliation
}

///|
pub fn MergeReviewBundle::report(self : MergeReviewBundle) -> ReleaseCheck {
  self.release.report()
}
