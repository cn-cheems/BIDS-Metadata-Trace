///|
/// Atomic changes to the indexed scan inventory; sources are never removed.
pub struct ScanChanges {
  priv additions : Array[String]
  priv removals : Array[String]
}

///|
pub fn ScanChanges::new(
  additions : Array[String],
  removals : Array[String],
) -> ScanChanges raise TraceError {
  if additions.length() + removals.length() > 256 {
    reject(
      "scan_changes_limit", "<scan-changes>", "At most 256 combined additions/removals; split the review explicitly.",
    )
  }
  let seen : Map[String, String] = Map([])
  for path in additions + removals {
    ignore(selector(path, sidecar=false))
    let folded = path.to_lower()
    if seen.get(folded) is Some(existing) {
      reject(
        "scan_change_conflict",
        path,
        "Each scan path may occur only once, including case variants and both operations.",
        related=[existing],
      )
    }
    seen[folded] = path
  }
  let changes : ScanChanges = {
    additions: DatasetIndex::from_manifest(additions, []).data_paths(),
    removals: removals.copy(),
  }
  changes.removals.sort_by(lexical_compare)
  if changes.to_json().length() > 2097152 {
    reject(
      "input_limit", "<scan-changes>", "Canonical scan changes exceed 2,097,152 UTF-16 units.",
    )
  }
  changes
}

///|
fn ScanChanges::changes_value(self : ScanChanges) -> Json {
  Json::object({
    "add": Json::array(self.additions.map(Json::string)),
    "remove": Json::array(self.removals.map(Json::string)),
  })
}

///|
pub fn ScanChanges::to_json(self : ScanChanges) -> String {
  canonical_json(self.changes_value())
}

///|
pub fn ScanChanges::from_json(text : String) -> ScanChanges raise TraceError {
  guard parse_source("<scan-changes>", text, container_limit=2) is Object(input) else {
    reject(
      "invalid_scan_changes", "<scan-changes>", "Expected arrays add and remove.",
    )
    abort("reject raises")
  }
  for key in sorted_keys(input) {
    if !["add", "remove"].contains(key) {
      reject(
        "unknown_scan_change_field", key, "Use only add and remove controls; sources are preserved.",
      )
    }
  }
  guard input.get("add") is Some(Array(additions)) &&
    input.get("remove") is Some(Array(removals)) else {
    reject(
      "invalid_scan_changes", "<scan-changes>", "Both add and remove arrays are mandatory.",
    )
    abort("reject raises")
  }
  fn paths(values : Array[Json]) -> Array[String] raise TraceError {
    values.map(value => {
      guard value is String(path) else {
        reject(
          "invalid_scan_changes", "<scan-changes>", "Every operation names a supported relative scan path.",
        )
        abort("reject raises")
      }
      path
    })
  }
  ScanChanges::new(paths(additions), paths(removals))
}

///|
pub struct ScanChangePlan {
  priv baseline : DatasetIndex
  priv candidate : DatasetIndex
  priv changes : ScanChanges
  priv impact : ImpactReport
  priv before_coverage : SourceCoverageReport
  priv after_coverage : SourceCoverageReport
}

///|
/// Validate the final snapshot only, then expose impacts and source coverage.
/// Removed scans keep before evidence; unmatched sources remain in the candidate.
pub fn DatasetIndex::plan_scans(
  self : DatasetIndex,
  changes : ScanChanges,
) -> ScanChangePlan raise TraceError {
  let existing : Map[String, Bool] = Map([])
  for file in self.files {
    existing[file.path] = true
  }
  for path in changes.removals {
    if !existing.contains(path) {
      reject(
        "unknown_data_path", path, "Cannot remove an absent scan; inspect the baseline inventory.",
      )
    }
  }
  for path in changes.additions {
    if existing.contains(path) {
      reject(
        "existing_data_path", path, "Cannot add an indexed scan; each inventory path is unique.",
      )
    }
  }
  let paths = self.data_paths().filter(path => !changes.removals.contains(path))
  let sources = self.sidecars.map(source => {
    SidecarInput::new(
      source.selector.path,
      canonical_json(Json::object(source.metadata)),
    )
  })
  let candidate = DatasetIndex::from_manifest(
    paths + changes.additions,
    sources,
  )
  {
    baseline: self,
    candidate,
    changes,
    impact: self.compare(candidate),
    before_coverage: self.source_coverage(),
    after_coverage: candidate.source_coverage(),
  }
}

///|
pub fn ScanChangePlan::before(self : ScanChangePlan) -> DatasetIndex {
  self.baseline
}

///|
pub fn ScanChangePlan::after(self : ScanChangePlan) -> DatasetIndex {
  self.candidate
}

///|
pub fn ScanChangePlan::impact(self : ScanChangePlan) -> ImpactReport {
  self.impact
}

///|
pub fn ScanChangePlan::before_coverage(
  self : ScanChangePlan,
) -> SourceCoverageReport {
  self.before_coverage
}

///|
pub fn ScanChangePlan::after_coverage(
  self : ScanChangePlan,
) -> SourceCoverageReport {
  self.after_coverage
}

///|
/// Complete evidence with already canonical components; never rounds numbers.
pub fn ScanChangePlan::to_json(self : ScanChangePlan) -> String {
  "{\"after_coverage\":" +
  self.after_coverage.to_json() +
  ",\"after_manifest\":" +
  self.candidate.to_manifest_json() +
  ",\"before_coverage\":" +
  self.before_coverage.to_json() +
  ",\"before_manifest\":" +
  self.baseline.to_manifest_json() +
  ",\"changes\":" +
  self.changes.to_json() +
  ",\"impact\":" +
  self.impact.to_json() +
  "}"
}
