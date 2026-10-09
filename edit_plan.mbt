///|
/// Explicit whole-field assignments and removals. JSON null is an assignment.
/// A patch never deletes nested values implicitly or merges nested objects.
pub struct MetadataPatch {
  priv assignments : Map[String, Json]
  priv removals : Array[String]
}

///|
/// Parse {"set":object,"remove":[unique field names]}; both controls are required.
/// Unknown controls, duplicate JSON keys and contradictory operations fail.
pub fn MetadataPatch::from_json(
  text : String,
) -> MetadataPatch raise TraceError {
  // The envelope adds one container above the metadata object being assigned.
  guard parse_source("<patch>", text, container_limit=65) is Object(fields) else {
    reject(
      "invalid_patch", "<patch>", "Expected an object with set and remove controls.",
    )
    return { assignments: Map([]), removals: [], }
  }
  for key in sorted_keys(fields) {
    if key != "set" && key != "remove" {
      reject(
        "unknown_patch_field",
        "<patch>",
        "Unknown patch control " +
        Json::string(key).stringify() +
        "; use only set and remove.",
      )
    }
  }
  guard fields.get("set") is Some(Object(assignments)) &&
    fields.get("remove") is Some(Array(values)) else {
    reject(
      "invalid_patch", "<patch>", "Both set (an object) and remove (an array of field names) are required.",
    )
    return { assignments: Map([]), removals: [], }
  }
  let seen : Map[String, Bool] = Map([])
  let removals = values.map(value => {
    guard value is String(key) else {
      reject(
        "invalid_patch", "<patch>/remove", "Each removal must name one top-level field as a string.",
      )
      return ""
    }
    if seen.contains(key) {
      reject(
        "duplicate_remove",
        "<patch>/remove",
        "Field " +
        Json::string(key).stringify() +
        " is listed for removal more than once.",
      )
    }
    if assignments.contains(key) {
      reject(
        "patch_conflict",
        "<patch>",
        "Field " +
        Json::string(key).stringify() +
        " cannot be set and removed in the same patch.",
      )
    }
    seen[key] = true
    key
  })
  removals.sort_by(lexical_compare)
  { assignments, removals, }
}

///|
fn MetadataPatch::patch_value(self : MetadataPatch) -> Json {
  Json::object({
    "set": Json::object(self.assignments),
    "remove": Json::array(self.removals.map(Json::string)),
  })
}

///|
/// Deterministic patch JSON; removal order is normalized, number tokens retained.
pub fn MetadataPatch::to_json(self : MetadataPatch) -> String {
  canonical_json(self.patch_value())
}

///|
/// An immutable proposed edit with complete before/after snapshot evidence.
/// Creating or inspecting a plan never changes any filesystem entry.
pub struct EditPlan {
  priv before : DatasetIndex
  priv after : DatasetIndex
  priv sidecar_path : String
  priv patch : MetadataPatch
  priv original_metadata : Map[String, Json]
  priv updated_metadata : Map[String, Json]
  priv impact : ImpactReport
}

///|
fn apply_metadata_patch(
  original : Map[String, Json],
  patch : MetadataPatch,
  sidecar_path : String,
) -> Map[String, Json] raise TraceError {
  for key in patch.removals {
    if !original.contains(key) {
      reject(
        "missing_metadata_field",
        sidecar_path,
        "Cannot remove absent field " +
        Json::string(key).stringify() +
        "; inspect the sidecar and correct the patch.",
      )
    }
  }
  let updated : Map[String, Json] = Map([])
  for key in sorted_keys(original) {
    updated[key] = copy_json(original[key])
  }
  for key in patch.removals {
    updated.remove(key)
  }
  for key in sorted_keys(patch.assignments) {
    updated[key] = copy_json(patch.assignments[key])
  }
  updated
}

///|
/// Plan one existing sidecar edit, then revalidate the complete new snapshot.
/// Removing an absent field fails. Scan ambiguity stays visible in the impact.
pub fn DatasetIndex::plan_edit(
  self : DatasetIndex,
  sidecar_path : String,
  patch : MetadataPatch,
) -> EditPlan raise TraceError {
  guard self.sidecars.search_by(source => source.selector.path == sidecar_path)
    is Some(position) else {
    reject(
      "unknown_sidecar_path", sidecar_path, "Sidecar is absent from the snapshot; select an existing source before planning an edit.",
    )
    abort("reject raises")
  }
  let original = self.sidecars[position].metadata
  // Validate all removals before making a private replacement. Neither a failed
  // plan nor a successful one can mutate the baseline or another plan.
  let updated = apply_metadata_patch(original, patch, sidecar_path)
  let inputs = self.sidecars.map(source => {
    let metadata = if source.selector.path == sidecar_path {
      updated
    } else {
      source.metadata
    }
    SidecarInput::new(
      source.selector.path,
      canonical_json(Json::object(metadata)),
    )
  })
  // Rebuilding enforces sidecar depth and aggregate snapshot limits and ensures
  // the proposed snapshot remains reloadable through the public API.
  let after = DatasetIndex::from_manifest(self.data_paths(), inputs)
  {
    before: self,
    after,
    sidecar_path,
    patch,
    original_metadata: original,
    updated_metadata: updated,
    impact: self.compare(after),
  }
}

///|
pub fn EditPlan::before(self : EditPlan) -> DatasetIndex {
  self.before
}

///|
pub fn EditPlan::after(self : EditPlan) -> DatasetIndex {
  self.after
}

///|
pub fn EditPlan::sidecar_path(self : EditPlan) -> String {
  self.sidecar_path
}

///|
/// Complete replacement metadata for this sidecar, retaining untouched fields.
pub fn EditPlan::updated_sidecar_json(self : EditPlan) -> String {
  canonical_json(Json::object(self.updated_metadata))
}

///|
pub fn EditPlan::impact(self : EditPlan) -> ImpactReport {
  self.impact
}

///|
/// Full snapshots, explicit operations, sidecar values and per-scan provenance.
/// An error in impact marks the plan indeterminate rather than safe to apply.
pub fn EditPlan::to_json(self : EditPlan) -> String {
  canonical_json(
    Json::object({
      "sidecar_path": Json::string(self.sidecar_path),
      "patch": self.patch.patch_value(),
      "before_sidecar": Json::object(self.original_metadata),
      "after_sidecar": Json::object(self.updated_metadata),
      "before_manifest": self.before.manifest_value(),
      "after_manifest": self.after.manifest_value(),
      "impact": self.impact.report_value(),
    }),
  )
}
