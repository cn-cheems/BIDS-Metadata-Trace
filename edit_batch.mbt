///|
priv struct SidecarPatch {
  path : String
  patch : MetadataPatch
}

///|
/// A bounded, unordered set of edits to distinct existing sidecars.
/// Every patch is evaluated against the same original snapshot.
pub struct EditBatch {
  priv edits : Array[SidecarPatch]
}

///|
/// Build a batch directly from typed patches. Copies/normalizes the input list.
/// A successful batch always reloads through from_json(to_json()).
pub fn EditBatch::from_patches(
  patches : Array[(String, MetadataPatch)],
) -> EditBatch raise TraceError {
  if patches.length() > 256 {
    reject(
      "edit_batch_limit", "<edit-batch>/edits", "At most 256 distinct sidecars can be edited in one plan; split the review scope explicitly.",
    )
  }
  let seen : Map[String, Bool] = Map([])
  // Count canonical envelope/entry sizes before allocating a combined JSON.
  // Each entry is patch JSON plus a path member; commas separate entries.
  let mut serialized_length = 12 // {"edits":[]}
  let edits = patches.map(pair => {
    let (path, patch) = pair
    if seen.contains(path) {
      reject(
        "duplicate_edit_path", path, "Sidecar occurs more than once; combine its operations into one unambiguous patch.",
      )
    }
    if path.length() > 2097152 {
      reject(
        "input_limit", "<edit-batch>", "Sidecar path exceeds the edit batch input limit; correct the target path.",
      )
    }
    let entry_length = patch.to_json().length() +
      Json::string(path).stringify().length() +
      8
    let separator = if seen.is_empty() { 0 } else { 1 }
    if entry_length > 2097152 - serialized_length - separator {
      reject(
        "input_limit", "<edit-batch>", "Canonical edit batch exceeds 2,097,152 UTF-16 code units; split the review scope explicitly.",
      )
    }
    serialized_length += entry_length + separator
    seen[path] = true
    { path, patch, }
  })
  edits.sort_by((left, right) => lexical_compare(left.path, right.path))
  let batch : EditBatch = { edits, }
  if batch.to_json().length() > 2097152 {
    reject(
      "input_limit", "<edit-batch>", "Canonical edit batch exceeds 2,097,152 UTF-16 code units; split the review scope explicitly.",
    )
  }
  batch
}

///|
/// Read {"edits":[{"path":relative_path,"set":object,"remove":[field_names]}]}.
/// Unknown controls and duplicate paths/decoded JSON keys fail. Empty is a no-op.
pub fn EditBatch::from_json(text : String) -> EditBatch raise TraceError {
  guard parse_source("<edit-batch>", text, container_limit=67) is Object(fields) else {
    reject(
      "invalid_edit_batch", "<edit-batch>", "Expected an object containing an edits array.",
    )
    return { edits: [], }
  }
  for key in sorted_keys(fields) {
    if key != "edits" {
      reject(
        "unknown_edit_batch_field",
        "<edit-batch>",
        "Unknown batch control " +
        Json::string(key).stringify() +
        "; use only edits.",
      )
    }
  }
  guard fields.get("edits") is Some(Array(values)) else {
    reject(
      "invalid_edit_batch", "<edit-batch>/edits", "Required edits control must be an array.",
    )
    return { edits: [], }
  }
  if values.length() > 256 {
    reject(
      "edit_batch_limit", "<edit-batch>/edits", "At most 256 distinct sidecars can be edited in one plan; split the review scope explicitly.",
    )
  }
  let edits = values.map(value => {
    guard value is Object(entry) else {
      reject(
        "invalid_edit_batch", "<edit-batch>/edits", "Each edit must be an object containing path, set and remove.",
      )
      abort("reject raises")
    }
    for key in sorted_keys(entry) {
      if !["path", "set", "remove"].contains(key) {
        reject(
          "unknown_edit_batch_field",
          "<edit-batch>/edits",
          "Unknown edit control " +
          Json::string(key).stringify() +
          "; use path, set and remove.",
        )
      }
    }
    guard entry.get("path") is Some(String(path)) &&
      entry.get("set") is Some(assignments) &&
      entry.get("remove") is Some(removals) else {
      reject(
        "invalid_edit_batch", "<edit-batch>/edits", "Every edit requires a string path and both set and remove controls.",
      )
      abort("reject raises")
    }
    let patch = MetadataPatch::from_json(
      canonical_json(Json::object({ "set": assignments, "remove": removals })),
    )
    { path, patch, }
  })
  EditBatch::from_patches(edits.map(edit => (edit.path, edit.patch)))
}

///|
fn EditBatch::batch_value(self : EditBatch) -> Json {
  Json::object({
    "edits": Json::array(
      self.edits.map(edit => {
        Json::object({
          "path": Json::string(edit.path),
          "set": Json::object(edit.patch.assignments),
          "remove": Json::array(edit.patch.removals.map(Json::string)),
        })
      }),
    ),
  })
}

///|
/// Normalize sidecar/removal ordering while preserving exact metadata tokens.
pub fn EditBatch::to_json(self : EditBatch) -> String {
  canonical_json(self.batch_value())
}

///|
pub fn EditBatch::sidecar_paths(self : EditBatch) -> Array[String] {
  self.edits.map(edit => edit.path)
}

///|
/// One immutable candidate snapshot, never a collection of partial plans.
pub struct BatchEditPlan {
  priv before : DatasetIndex
  priv after : DatasetIndex
  priv batch : EditBatch
  priv originals : Map[String, Map[String, Json]]
  priv updates : Map[String, Map[String, Json]]
  priv impact : ImpactReport
}

///|
/// Validate all operations against the baseline, rebuild once, then compare.
/// Failures never mutate the baseline or return a partially updated snapshot.
pub fn DatasetIndex::plan_edits(
  self : DatasetIndex,
  batch : EditBatch,
) -> BatchEditPlan raise TraceError {
  let originals : Map[String, Map[String, Json]] = Map([])
  let updates : Map[String, Map[String, Json]] = Map([])
  for edit in batch.edits {
    guard self.sidecars.search_by(source => source.selector.path == edit.path)
      is Some(position) else {
      reject(
        "unknown_sidecar_path",
        edit.path,
        "Sidecar is absent from the snapshot; select an existing source before planning an edit.",
      )
      abort("reject raises")
    }
    let original = self.sidecars[position].metadata
    originals[edit.path] = original
    updates[edit.path] = apply_metadata_patch(original, edit.patch, edit.path)
  }
  let inputs = self.sidecars.map(source => {
    let metadata = match updates.get(source.selector.path) {
      Some(updated) => updated
      None => source.metadata
    }
    SidecarInput::new(
      source.selector.path,
      canonical_json(Json::object(metadata)),
    )
  })
  // Only the final combined snapshot is bounded/revalidated. A coordinated
  // shrink/grow can succeed even if one isolated intermediate plan is too big.
  let after = DatasetIndex::from_manifest(self.data_paths(), inputs)
  {
    before: self,
    after,
    batch,
    originals,
    updates,
    impact: self.compare(after),
  }
}

///|
pub fn BatchEditPlan::before(self : BatchEditPlan) -> DatasetIndex {
  self.before
}

///|
pub fn BatchEditPlan::after(self : BatchEditPlan) -> DatasetIndex {
  self.after
}

///|
pub fn BatchEditPlan::sidecar_paths(self : BatchEditPlan) -> Array[String] {
  self.batch.sidecar_paths()
}

///|
/// Return complete replacement metadata only for an explicitly edited source.
pub fn BatchEditPlan::updated_sidecar_json(
  self : BatchEditPlan,
  path : String,
) -> String? {
  match self.updates.get(path) {
    Some(metadata) => Some(canonical_json(Json::object(metadata)))
    None => None
  }
}

///|
pub fn BatchEditPlan::impact(self : BatchEditPlan) -> ImpactReport {
  self.impact
}

///|
/// Retain every patch, old/new source values, complete snapshots and impacts.
pub fn BatchEditPlan::to_json(self : BatchEditPlan) -> String {
  canonical_json(
    Json::object({
      "batch": self.batch.batch_value(),
      "sidecars": Json::array(
        self.batch.edits.map(edit => {
          Json::object({
            "path": Json::string(edit.path),
            "patch": edit.patch.patch_value(),
            "before_sidecar": Json::object(self.originals[edit.path]),
            "after_sidecar": Json::object(self.updates[edit.path]),
          })
        }),
      ),
      "before_manifest": self.before.manifest_value(),
      "after_manifest": self.after.manifest_value(),
      "impact": self.impact.report_value(),
    }),
  )
}
