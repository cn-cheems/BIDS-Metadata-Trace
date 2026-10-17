///|
/// One final snapshot transaction. Every operation refers to the baseline.
pub struct DatasetChanges {
  priv scans : ScanChanges
  priv sources : SourceChanges
  priv edits : EditBatch
}

///|
pub fn DatasetChanges::new(
  scans : ScanChanges,
  sources : SourceChanges,
  edits : EditBatch,
) -> DatasetChanges raise TraceError {
  if scans.additions.length() +
    scans.removals.length() +
    sources.additions.length() +
    sources.removals.length() +
    edits.edits.length() >
    256 {
    reject(
      "dataset_changes_limit", "<dataset-changes>", "At most 256 combined operations are permitted.",
    )
  }
  let seen : Map[String, Bool] = Map([])
  for
    path in sources.additions.map(s => s.path) +
    sources.removals +
    edits.sidecar_paths() {
    ignore(selector(path, sidecar=true))
    let folded = path.to_lower()
    if seen.contains(folded) {
      reject(
        "dataset_change_conflict", path, "A source may participate in only one operation; supply new sources with their final metadata.",
      )
    }
    seen[folded] = true
  }
  let changes : DatasetChanges = { scans, sources, edits, }
  if changes.to_json().length() > 2097152 {
    reject(
      "input_limit", "<dataset-changes>", "Combined controls exceed 2,097,152 UTF-16 units.",
    )
  }
  changes
}

///|
pub fn DatasetChanges::to_json(self : DatasetChanges) -> String {
  canonical_json(
    Json::object({
      "scans": self.scans.changes_value(),
      "sources": self.sources.changes_value(),
      "edits": self.edits.batch_value(),
    }),
  )
}

///|
pub fn DatasetChanges::from_json(
  text : String,
) -> DatasetChanges raise TraceError {
  guard parse_source("<dataset-changes>", text, container_limit=68)
    is Object(fields) else {
    reject(
      "invalid_dataset_changes", "<dataset-changes>", "Expected scans, sources and edits objects.",
    )
    abort("reject raises")
  }
  if sorted_keys(fields) != ["edits", "scans", "sources"] {
    reject(
      "invalid_dataset_changes", "<dataset-changes>", "Exactly scans, sources and edits are required; unknown controls are rejected.",
    )
  }
  DatasetChanges::new(
    ScanChanges::from_json(canonical_json(fields["scans"])),
    SourceChanges::from_json(canonical_json(fields["sources"])),
    EditBatch::from_json(canonical_json(fields["edits"])),
  )
}

///|
pub struct DatasetChangePlan {
  priv before : DatasetIndex
  priv after : DatasetIndex
  priv changes : DatasetChanges
}

///|
pub fn DatasetIndex::plan_changes(
  self : DatasetIndex,
  changes : DatasetChanges,
) -> DatasetChangePlan raise TraceError {
  let paths = self.data_paths()
  for path in changes.scans.removals {
    if !paths.contains(path) {
      reject(
        "unknown_data_path", path, "Cannot remove a scan absent from the baseline.",
      )
    }
  }
  for path in changes.scans.additions {
    if paths.contains(path) {
      reject(
        "existing_data_path", path, "Added scan already exists in the baseline.",
      )
    }
  }
  let existing = self.sidecars.map(s => s.selector.path)
  for path in changes.sources.removals + changes.edits.sidecar_paths() {
    if !existing.contains(path) {
      reject(
        "unknown_sidecar_path", path, "Source operation requires an existing baseline source.",
      )
    }
  }
  for source in changes.sources.additions {
    if existing.contains(source.path) {
      reject(
        "existing_sidecar_path",
        source.path,
        "Added source already exists in the baseline.",
      )
    }
  }
  let inputs : Array[SidecarInput] = []
  for source in self.sidecars {
    if !changes.sources.removals.contains(source.selector.path) {
      let metadata = match
        changes.edits.edits.search_by(e => e.path == source.selector.path) {
        Some(i) =>
          apply_metadata_patch(
            source.metadata,
            changes.edits.edits[i].patch,
            source.selector.path,
          )
        None => source.metadata
      }
      inputs.push(
        SidecarInput::new(
          source.selector.path,
          canonical_json(Json::object(metadata)),
        ),
      )
    }
  }
  let after = DatasetIndex::from_manifest(
    paths.filter(p => !changes.scans.removals.contains(p)) +
    changes.scans.additions,
    inputs + changes.sources.additions,
  )
  { before: self, after, changes, }
}

///|
pub fn DatasetChangePlan::before(self : DatasetChangePlan) -> DatasetIndex {
  self.before
}

///|
pub fn DatasetChangePlan::after(self : DatasetChangePlan) -> DatasetIndex {
  self.after
}

///|
pub fn DatasetChangePlan::impact(self : DatasetChangePlan) -> ImpactReport {
  self.before.compare(self.after)
}

///|
pub fn DatasetChangePlan::to_json(self : DatasetChangePlan) -> String {
  "{\"after_manifest\":" +
  self.after.to_manifest_json() +
  ",\"before_manifest\":" +
  self.before.to_manifest_json() +
  ",\"changes\":" +
  self.changes.to_json() +
  ",\"impact\":" +
  self.impact().to_json() +
  "}"
}
