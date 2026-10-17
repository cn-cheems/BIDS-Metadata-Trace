///|
/// A removal proposal whose effective metadata is proven unchanged for every
/// indexed scan. This makes no statement about scans outside the manifest.
pub struct PrunePlan {
  priv edit : EditPlan
}

///|
pub fn DatasetIndex::plan_prune(
  self : DatasetIndex,
  source_path : String,
  fields : Array[String],
) -> PrunePlan raise TraceError {
  let fields = review_fields(fields)
  if fields.is_empty() {
    reject(
      "empty_prune_fields", source_path, "Name at least one field to remove.",
    )
  }
  guard self.sidecars.search_by(s => s.selector.path == source_path)
    is Some(position) else {
    reject("unknown_sidecar_path", source_path, "Choose an existing source.")
    abort("reject raises")
  }
  if !self.files
    .iter()
    .any(file => applies(self.sidecars[position].selector, file)) {
    reject(
      "unproven_prune", source_path, "No indexed scan uses this source; preservation cannot be demonstrated.",
    )
  }
  let patch = MetadataPatch::from_json(
    canonical_json(
      Json::object({
        "set": Json::object({}),
        "remove": Json::array(fields.map(Json::string)),
      }),
    ),
  )
  let edit = self.plan_edit(source_path, patch)
  let check = edit.impact().release_check(EffectiveValues)
  if check.decision() != Pass {
    reject(
      "unsafe_prune",
      source_path,
      "Removal changes exact effective values or encounters unresolved inheritance; inspect a normal edit plan instead.",
      related=check.affected_paths() + check.unresolved_paths(),
    )
  }
  { edit, }
}

///|
pub fn PrunePlan::after(self : PrunePlan) -> DatasetIndex {
  self.edit.after()
}

///|
pub fn PrunePlan::impact(self : PrunePlan) -> ImpactReport {
  self.edit.impact()
}

///|
pub fn PrunePlan::patch(self : PrunePlan) -> MetadataPatch {
  self.edit.patch
}

///|
pub fn PrunePlan::to_json(self : PrunePlan) -> String {
  "{\"edit\":" +
  self.edit.to_json() +
  ",\"guarantee\":\"exact_effective_values_for_all_indexed_scans\"}"
}
