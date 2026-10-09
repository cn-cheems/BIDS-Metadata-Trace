///|
/// A self-contained release review whose report can be recomputed from its
/// complete immutable snapshots. Replay verifies content agreement, not who
/// produced the bundle or whether its snapshots represent a real dataset.
pub struct ReviewBundle {
  priv before : DatasetIndex
  priv after : DatasetIndex
  priv report : ReleaseCheck
  priv serialized : String
}

///|
fn bundle_snapshot_text(
  index : DatasetIndex,
  location : String,
) -> String raise TraceError {
  let text = index.to_manifest_json()
  if text.length() > 2097152 {
    reject(
      "bundle_snapshot_limit", location, "Embedded snapshot exceeds 2,097,152 UTF-16 code units; split it before creating a review bundle.",
    )
  }
  text
}

///|
// Components come exclusively from the canonical serializers. Check the
// combined output size before concatenating repeated report evidence.
fn bundle_text(
  before : String,
  after : String,
  expected : String,
  policy : ReleasePolicy,
) -> String raise TraceError {
  let pieces = [
    "{\"after\":",
    after,
    ",\"before\":",
    before,
    ",\"expected\":",
    expected,
    ",\"format\":\"bids-metadata-trace/review-bundle\",\"policy\":",
    Json::string(release_policy_name(policy)).stringify(),
    ",\"version\":1}",
  ]
  let mut length = 0
  for piece in pieces {
    if piece.length() > 16777216 - length {
      reject(
        "bundle_limit", "<review-bundle>", "Complete review bundle exceeds 16,777,216 UTF-16 code units; split the snapshots before creating it.",
      )
    }
    length += piece.length()
  }
  pieces.join("")
}

///|
/// Capture both complete snapshots and a policy-specific release check. An
/// indeterminate check is retained with all diagnostics, never made into pass.
pub fn ReviewBundle::create(
  before : DatasetIndex,
  after : DatasetIndex,
  policy : ReleasePolicy,
) -> ReviewBundle raise TraceError {
  let before_text = bundle_snapshot_text(before, "<review-bundle>/before")
  let after_text = bundle_snapshot_text(after, "<review-bundle>/after")
  let report = before.compare(after).release_check(policy)
  let serialized = bundle_text(
    before_text,
    after_text,
    report.to_json(),
    policy,
  )
  { before, after, report, serialized, }
}

///|
/// Strictly decode a v1 bundle and recompute its complete expected report.
/// Duplicate keys, unknown controls, unsupported versions, and stale evidence
/// are errors. Numeric source tokens are compared exactly, without float math.
pub fn ReviewBundle::from_json(text : String) -> ReviewBundle raise TraceError {
  guard parse_source(
      "<review-bundle>",
      text,
      container_limit=80,
      text_limit=16777216,
    )
    is Object(fields) else {
    reject(
      "invalid_review_bundle", "<review-bundle>", "Expected a review bundle object with format, version, before, after, policy, and expected fields.",
    )
    return ReviewBundle::create(
      DatasetIndex::from_manifest([], []),
      DatasetIndex::from_manifest([], []),
      AllChanges,
    )
  }
  for key in sorted_keys(fields) {
    if !["format", "version", "before", "after", "policy", "expected"].contains(
        key,
      ) {
      reject(
        "unknown_bundle_field",
        "<review-bundle>/" + key,
        "Unknown review bundle control field; remove it explicitly or use a supported bundle version.",
      )
    }
  }
  guard fields.get("format") is Some(String(format)) &&
    format == "bids-metadata-trace/review-bundle" else {
    reject(
      "invalid_review_bundle", "<review-bundle>/format", "Expected format bids-metadata-trace/review-bundle.",
    )
    return ReviewBundle::create(
      DatasetIndex::from_manifest([], []),
      DatasetIndex::from_manifest([], []),
      AllChanges,
    )
  }
  guard fields.get("version") is Some(version) && canonical_json(version) == "1" else {
    reject(
      "unsupported_bundle_version", "<review-bundle>/version", "Only review bundle version 1 is supported; regenerate with this version before replaying.",
    )
    return ReviewBundle::create(
      DatasetIndex::from_manifest([], []),
      DatasetIndex::from_manifest([], []),
      AllChanges,
    )
  }
  guard fields.get("policy") is Some(String(policy_text)) else {
    reject(
      "invalid_review_bundle", "<review-bundle>/policy", "Expected policy all_changes or effective_values.",
    )
    return ReviewBundle::create(
      DatasetIndex::from_manifest([], []),
      DatasetIndex::from_manifest([], []),
      AllChanges,
    )
  }
  let policy = match policy_text {
    "all_changes" => ReleasePolicy::AllChanges
    "effective_values" => EffectiveValues
    _ => {
      reject(
        "invalid_review_bundle", "<review-bundle>/policy", "Expected policy all_changes or effective_values.",
      )
      AllChanges
    }
  }
  guard fields.get("before") is Some(Object(before)) &&
    fields.get("after") is Some(Object(after)) &&
    fields.get("expected") is Some(Object(expected)) else {
    reject(
      "invalid_review_bundle", "<review-bundle>", "Both snapshots and the complete expected release report must be JSON objects.",
    )
    return ReviewBundle::create(
      DatasetIndex::from_manifest([], []),
      DatasetIndex::from_manifest([], []),
      AllChanges,
    )
  }
  let bundle = ReviewBundle::create(
    DatasetIndex::from_json(canonical_json(Json::object(before))),
    DatasetIndex::from_json(canonical_json(Json::object(after))),
    policy,
  )
  if canonical_json(Json::object(expected)) != bundle.report.to_json() {
    reject(
      "replay_mismatch", "<review-bundle>/expected", "Expected report does not match these snapshots and policy; regenerate the complete bundle from the intended inputs.",
    )
  }
  bundle
}

///|
/// Deterministic complete v1 document; creation has already checked its size.
pub fn ReviewBundle::to_json(self : ReviewBundle) -> String {
  self.serialized
}

///|
pub fn ReviewBundle::before(self : ReviewBundle) -> DatasetIndex {
  self.before
}

///|
pub fn ReviewBundle::after(self : ReviewBundle) -> DatasetIndex {
  self.after
}

///|
/// The recomputed check, including policy-ignored changes and diagnostics.
pub fn ReviewBundle::report(self : ReviewBundle) -> ReleaseCheck {
  self.report
}
