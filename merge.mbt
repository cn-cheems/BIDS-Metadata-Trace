///|
/// Conflicts are review outcomes, never an instruction to choose a branch.
pub(all) enum MergeConflictKind {
  FieldDiverged
  SourceAddAdd
  SourceDeleteEdit
  ScanDeleteEdit
  EffectiveDiverged
  InheritanceShadow
  UnresolvedMetadata
  InvalidSnapshot
} derive(Eq, @debug.Debug)

///|
pub extend MergeConflictKind with Eq::{equal, not_equal}

///|
pub extend MergeConflictKind with @debug.Debug::{to_repr}

///|
/// Exact JSON evidence; None is absence, Some("null") is a present null.
/// For source conflicts evidence is a complete source object; for scan deletion
/// it is a complete resolution report. diagnostics identify unresolved inputs.
pub struct MergeConflict {
  priv kind : MergeConflictKind
  priv path : String
  priv key : String?
  priv base : Json?
  priv left : Json?
  priv right : Json?
  priv merged : Json?
  priv branch : String?
  priv diagnostics : Array[Diagnostic]
}

///|
pub fn MergeConflict::kind(self : MergeConflict) -> MergeConflictKind {
  self.kind
}

///|
pub fn MergeConflict::path(self : MergeConflict) -> String {
  self.path
}

///|
pub fn MergeConflict::key(self : MergeConflict) -> String? {
  self.key
}

///|
pub fn MergeConflict::base_json(self : MergeConflict) -> String? {
  self.base.map(canonical_json)
}

///|
pub fn MergeConflict::left_json(self : MergeConflict) -> String? {
  self.left.map(canonical_json)
}

///|
pub fn MergeConflict::right_json(self : MergeConflict) -> String? {
  self.right.map(canonical_json)
}

///|
pub fn MergeConflict::merged_json(self : MergeConflict) -> String? {
  self.merged.map(canonical_json)
}

///|
/// base, left, right or merged for resolution/validation errors; otherwise None.
pub fn MergeConflict::branch(self : MergeConflict) -> String? {
  self.branch
}

///|
pub fn MergeConflict::message(self : MergeConflict) -> String {
  match self.kind {
    FieldDiverged =>
      "Both branches changed this whole field differently; reconcile the values explicitly."
    SourceAddAdd =>
      "Both branches created different metadata at this source path; supply one agreed source."
    SourceDeleteEdit =>
      "One branch removed a source which the other edited; reconcile source inventory and metadata."
    ScanDeleteEdit =>
      "Removing this scan would discard the other branch's metadata or provenance change; reconcile its inclusion."
    EffectiveDiverged =>
      "Separate source edits changed this scan's effective field differently; reconcile inherited intent."
    InheritanceShadow =>
      "Combined inheritance would hide or alter a branch's effective field change; revise the overrides."
    UnresolvedMetadata =>
      "This scan cannot be resolved in the named snapshot; fix the attached diagnostic and retry."
    InvalidSnapshot =>
      "The combined snapshot violates an input invariant; fix the attached diagnostic and retry."
  }
}

///|
pub fn MergeConflict::diagnostics(self : MergeConflict) -> Array[Diagnostic] {
  self.diagnostics.map(d => {
    code: d.code,
    path: d.path,
    message: d.message,
    offset: d.offset,
    related: d.related.copy(),
  })
}

///|
/// An all-or-nothing proposal retaining all three immutable inputs.
/// A candidate exists only after structural and inheritance checks both pass.
pub struct MergeReport {
  priv base : DatasetIndex
  priv left : DatasetIndex
  priv right : DatasetIndex
  priv candidate : DatasetIndex?
  priv conflicts : Array[MergeConflict]
}

///|
pub fn MergeReport::candidate(self : MergeReport) -> DatasetIndex? {
  self.candidate
}

///|
pub fn MergeReport::conflicts(self : MergeReport) -> Array[MergeConflict] {
  self.conflicts.copy()
}

///|
pub fn MergeReport::conflict_count(self : MergeReport) -> Int32 {
  self.conflicts.length()
}

///|
/// Full base-to-candidate impact, including provenance. None when blocked.
pub fn MergeReport::impact(self : MergeReport) -> ImpactReport? {
  self.candidate.map(after => self.base.compare(after))
}

///|
fn merge_kind_text(kind : MergeConflictKind) -> String {
  match kind {
    FieldDiverged => "field_diverged"
    SourceAddAdd => "source_add_add"
    SourceDeleteEdit => "source_delete_edit"
    ScanDeleteEdit => "scan_delete_edit"
    EffectiveDiverged => "effective_diverged"
    InheritanceShadow => "inheritance_shadow"
    UnresolvedMetadata => "unresolved_metadata"
    InvalidSnapshot => "invalid_snapshot"
  }
}

///|
fn merge_optional_value(value : Json?) -> Json {
  // Presence remains explicit, since absent and present-null are distinct.
  Json::object({
    "present": Json::boolean(value is Some(_)),
    "value": value.unwrap_or(Json::null()),
  })
}

///|
fn MergeConflict::report_value(self : MergeConflict) -> Json {
  Json::object({
    "kind": Json::string(merge_kind_text(self.kind)),
    "message": Json::string(self.message()),
    "path": Json::string(self.path),
    "key": self.key.map(Json::string).unwrap_or(Json::null()),
    "base": merge_optional_value(self.base),
    "left": merge_optional_value(self.left),
    "right": merge_optional_value(self.right),
    "merged": merge_optional_value(self.merged),
    "branch": self.branch.map(Json::string).unwrap_or(Json::null()),
    "diagnostics": Json::array(self.diagnostics.map(d => d.to_json())),
  })
}

///|
/// Deterministic complete evidence. No partially merged manifest is exposed
/// when conflicts exist. Recompute with merge() from the three embedded inputs.
pub fn MergeReport::to_json(self : MergeReport) -> String {
  canonical_json(
    Json::object({
      "status": Json::string(
        if self.candidate is Some(_) {
          "merged"
        } else {
          "conflicts"
        },
      ),
      "conflict_count": Json::number(self.conflict_count().to_double()),
      "conflicts": Json::array(self.conflicts.map(c => c.report_value())),
      "base_manifest": self.base.manifest_value(),
      "left_manifest": self.left.manifest_value(),
      "right_manifest": self.right.manifest_value(),
      "merged_manifest": self.candidate
      .map(i => i.manifest_value())
      .unwrap_or(Json::null()),
      "impact": self.impact().map(i => i.report_value()).unwrap_or(Json::null()),
    }),
  )
}

///|
fn merge_equal(a : Json?, b : Json?) -> Bool {
  a.map(canonical_json) == b.map(canonical_json)
}

///|
fn merge_conflict(
  conflicts : Array[MergeConflict],
  kind : MergeConflictKind,
  path : String,
  key? : String,
  base? : Json,
  left? : Json,
  right? : Json,
  merged? : Json,
  branch? : String,
  diagnostics~ : Array[Diagnostic] = [],
) -> Unit raise TraceError {
  if conflicts.length() >= 1024 {
    reject(
      "merge_conflict_limit", "<merge>", "More than 1,024 conflicts; narrow the snapshots or reconcile conflicts before retrying. No candidate was produced.",
    )
  }
  conflicts.push({
    kind,
    path,
    key,
    base,
    left,
    right,
    merged,
    branch,
    diagnostics,
  })
}

///|
fn merge_sources(index : DatasetIndex) -> Map[String, Json] {
  let sources : Map[String, Json] = Map([])
  for source in index.sidecars {
    sources[source.selector.path] = Json::object(source.metadata)
  }
  sources
}

///|
/// Three-way metadata merge over a shared ancestor, followed by per-scan
/// inheritance validation. Values are atomic at the top-level field boundary.
/// Conflicts block the entire candidate. More than 1,024 conflicts raises.
/// This is a conservative review policy, not a BIDS conformance certificate.
pub fn DatasetIndex::merge(
  self : DatasetIndex,
  left : DatasetIndex,
  right : DatasetIndex,
) -> MergeReport raise TraceError {
  self.merge_with(left, right, None)
}

///|
fn DatasetIndex::merge_with(
  self : DatasetIndex,
  left : DatasetIndex,
  right : DatasetIndex,
  resolution : MergeResolution?,
) -> MergeReport raise TraceError {
  let conflicts : Array[MergeConflict] = []
  let b = merge_sources(self)
  let l = merge_sources(left)
  let r = merge_sources(right)
  let paths : Map[String, Bool] = Map([])
  for sources in [b, l, r] {
    for path in sorted_keys(sources) {
      paths[path] = true
    }
  }
  if resolution is Some(plan) {
    for decision in plan.sources {
      paths[decision.path] = true
    }
  }
  let inputs : Array[SidecarInput] = []
  for path in sorted_keys(paths) {
    if resolution is Some(plan) && plan.source_at(path) is Some(decision) {
      if decision.metadata is Some(metadata) {
        inputs.push(SidecarInput::new(path, canonical_json(metadata)))
      } else if !paths_in_inputs(self, left, right, path, source=true) {
        reject(
          "unused_resolution", path, "Cannot remove a source absent from all three inputs.",
        )
      }
      continue
    }
    let bv = b.get(path)
    let lv = l.get(path)
    let rv = r.get(path)
    let selected = if merge_equal(lv, rv) {
      lv
    } else if merge_equal(bv, lv) {
      rv
    } else if merge_equal(bv, rv) {
      lv
    } else {
      match (bv, lv, rv) {
        (Some(Object(bf)), Some(Object(lf)), Some(Object(rf))) => {
          let keys : Map[String, Bool] = Map([])
          for fields in [bf, lf, rf] {
            for key in sorted_keys(fields) {
              keys[key] = true
            }
          }
          let merged : Map[String, Json] = Map([])
          for key in sorted_keys(keys) {
            let before = bf.get(key)
            let a = lf.get(key)
            let z = rf.get(key)
            let value = if merge_equal(a, z) {
              a
            } else if merge_equal(before, a) {
              z
            } else if merge_equal(before, z) {
              a
            } else {
              merge_conflict(
                conflicts,
                FieldDiverged,
                path,
                key~,
                base?=before,
                left?=a,
                right?=z,
              )
              None
            }
            if value is Some(value) {
              merged[key] = value
            }
          }
          Some(Json::object(merged))
        }
        _ => {
          merge_conflict(
            conflicts,
            if bv is None {
              SourceAddAdd
            } else {
              SourceDeleteEdit
            },
            path,
            base?=bv,
            left?=lv,
            right?=rv,
          )
          None
        }
      }
    }
    if selected is Some(metadata) {
      inputs.push(SidecarInput::new(path, canonical_json(metadata)))
    }
  }
  // Structural conflicts take precedence. Do not audit a speculative choice.
  if !conflicts.is_empty() {
    return { base: self, left, right, candidate: None, conflicts, }
  }
  let scans : Map[String, Bool] = Map([])
  for index in [self, left, right] {
    for path in index.data_paths() {
      scans[path] = true
    }
  }
  if resolution is Some(plan) {
    for decision in plan.scans {
      if !decision.retained && !scans.contains(decision.path) {
        reject(
          "unused_resolution",
          decision.path,
          "Cannot remove a scan absent from all three inputs.",
        )
      }
      scans[decision.path] = true
    }
  }
  let files = sorted_keys(scans).filter(path => {
    if resolution is Some(plan) && plan.scan_at(path) is Some(decision) {
      return decision.retained
    }
    let bp = self.file_positions.contains(path)
    let lp = left.file_positions.contains(path)
    let rp = right.file_positions.contains(path)
    if lp == rp {
      lp
    } else if lp == bp {
      rp
    } else {
      lp
    }
  })
  let candidate = DatasetIndex::from_manifest(files, inputs) catch {
    TraceError(d) => {
      merge_conflict(conflicts, InvalidSnapshot, d.path, branch="merged", diagnostics=[
        d,
      ])
      return { base: self, left, right, candidate: None, conflicts, }
    }
  }
  if resolution is Some(plan) {
    plan.check_effective(candidate)
  }
  merge_check_scans(
    self,
    left,
    right,
    candidate,
    sorted_keys(scans),
    conflicts,
    resolution~,
  )
  {
    base: self,
    left,
    right,
    candidate: if conflicts.is_empty() {
      Some(candidate)
    } else {
      None
    },
    conflicts,
  }
}
