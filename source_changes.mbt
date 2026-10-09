///|
/// Atomic source inventory changes; additions and removals name distinct paths.
pub struct SourceChanges {
  priv additions : Array[SidecarInput]
  priv removals : Array[String]
}

///|
/// Validate source paths/JSON, normalize order, retain exact unknown metadata.
pub fn SourceChanges::new(
  additions : Array[SidecarInput],
  removals : Array[String],
) -> SourceChanges raise TraceError {
  if additions.length() + removals.length() > 256 {
    reject(
      "source_changes_limit", "<source-changes>", "At most 256 added/removed sources; split the review explicitly.",
    )
  }
  let seen : Map[String, String] = Map([])
  for path in removals {
    ignore(selector(path, sidecar=true))
    let folded = path.to_lower()
    if seen.get(folded) is Some(existing) {
      reject(
        "source_change_conflict",
        path,
        "Each source path may occur only once, including case variants; use an edit for replacement.",
        related=[existing],
      )
    }
    seen[folded] = path
  }
  for input in additions {
    let folded = input.path.to_lower()
    if seen.get(folded) is Some(existing) {
      reject(
        "source_change_conflict",
        input.path,
        "Each source path may occur only once; use an edit for replacement.",
        related=[existing],
      )
    }
    seen[folded] = input.path
  }
  let sources = DatasetIndex::from_manifest([], additions)
  let removed = removals.copy()
  removed.sort_by(lexical_compare)
  let changes : SourceChanges = {
    additions: sources.sidecars.map(s => {
      SidecarInput::new(
        s.selector.path,
        canonical_json(Json::object(s.metadata)),
      )
    }),
    removals: removed,
  }
  if changes.to_json().length() > 2097152 {
    reject(
      "input_limit", "<source-changes>", "Canonical changes exceed 2,097,152 UTF-16 units; reduce the review scope.",
    )
  }
  changes
}

///|
fn SourceChanges::changes_value(self : SourceChanges) -> Json {
  Json::object({
    "add": Json::array(
      self.additions.map(input => {
        Json::object({
          "path": Json::string(input.path),
          "metadata": try! parse_source(input.path, input.text),
        })
      }),
    ),
    "remove": Json::array(self.removals.map(Json::string)),
  })
}

///|
pub fn SourceChanges::to_json(self : SourceChanges) -> String {
  canonical_json(self.changes_value())
}

///|
/// Both add and remove are mandatory; every unknown control is rejected.
pub fn SourceChanges::from_json(
  text : String,
) -> SourceChanges raise TraceError {
  guard parse_source("<source-changes>", text, container_limit=67)
    is Object(fields) else {
    reject(
      "invalid_source_changes", "<source-changes>", "Expected add and remove controls.",
    )
    abort("reject raises")
  }
  for key in sorted_keys(fields) {
    if !["add", "remove"].contains(key) {
      reject(
        "unknown_source_change_field", key, "Use only add and remove controls.",
      )
    }
  }
  guard fields.get("add") is Some(Array(add)) &&
    fields.get("remove") is Some(Array(remove)) else {
    reject(
      "invalid_source_changes", "<source-changes>", "Both add and remove must be arrays.",
    )
    abort("reject raises")
  }
  if add.length() + remove.length() > 256 {
    reject(
      "source_changes_limit", "<source-changes>", "At most 256 added/removed sources.",
    )
  }
  let additions = add.map(value => {
    guard value is Object(entry) else {
      reject(
        "invalid_source_changes", "<source-changes>/add", "Each addition requires path and object metadata.",
      )
      abort("reject raises")
    }
    for key in sorted_keys(entry) {
      if !["path", "metadata"].contains(key) {
        reject(
          "unknown_source_change_field", key, "Use only path and metadata in additions.",
        )
      }
    }
    guard entry.get("path") is Some(String(path)) &&
      entry.get("metadata") is Some(Object(metadata)) else {
      reject(
        "invalid_source_changes", "<source-changes>/add", "Each addition requires string path and object metadata.",
      )
      abort("reject raises")
    }
    SidecarInput::new(path, canonical_json(Json::object(metadata)))
  })
  let removals = remove.map(value => {
    guard value is String(path) else {
      reject(
        "invalid_source_changes", "<source-changes>/remove", "Each removal must be a source path.",
      )
      abort("reject raises")
    }
    path
  })
  SourceChanges::new(additions, removals)
}

///|
pub struct SourceChangePlan {
  priv baseline : DatasetIndex
  priv candidate : DatasetIndex
  priv changes : SourceChanges
  priv impact : ImpactReport
}

///|
/// Build/revalidate only the final inventory. Never writes/deletes disk files.
pub fn DatasetIndex::plan_sources(
  self : DatasetIndex,
  changes : SourceChanges,
) -> SourceChangePlan raise TraceError {
  let existing : Map[String, Bool] = Map([])
  for source in self.sidecars {
    existing[source.selector.path] = true
  }
  for path in changes.removals {
    if !existing.contains(path) {
      reject(
        "unknown_sidecar_path", path, "Cannot remove an absent source; inspect the baseline inventory.",
      )
    }
  }
  for input in changes.additions {
    if existing.contains(input.path) {
      reject(
        "existing_sidecar_path",
        input.path,
        "Source already exists; use metadata edit planning for replacement.",
      )
    }
  }
  let inputs = self.sidecars
    .filter(source => !changes.removals.contains(source.selector.path))
    .map(source => {
      SidecarInput::new(
        source.selector.path,
        canonical_json(Json::object(source.metadata)),
      )
    })
  for input in changes.additions {
    inputs.push(input)
  }
  let candidate = DatasetIndex::from_manifest(self.data_paths(), inputs)
  { baseline: self, candidate, changes, impact: self.compare(candidate), }
}

///|
pub fn SourceChangePlan::before(self : SourceChangePlan) -> DatasetIndex {
  self.baseline
}

///|
pub fn SourceChangePlan::after(self : SourceChangePlan) -> DatasetIndex {
  self.candidate
}

///|
pub fn SourceChangePlan::impact(self : SourceChangePlan) -> ImpactReport {
  self.impact
}

///|
/// Complete snapshots retain removed data, including sources without scan targets.
pub fn SourceChangePlan::to_json(self : SourceChangePlan) -> String {
  canonical_json(
    Json::object({
      "changes": self.changes.changes_value(),
      "before_manifest": self.baseline.manifest_value(),
      "after_manifest": self.candidate.manifest_value(),
      "impact": self.impact.report_value(),
    }),
  )
}
