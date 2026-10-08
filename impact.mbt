///|
pub(all) enum ImpactKind {
  Unchanged
  Changed
  Added
  Removed
  Unresolved
} derive(Eq)

///|
pub extend ImpactKind with Eq::{equal, not_equal}

///|
pub(all) enum FieldChangeKind {
  Added
  Removed
  ValueChanged
  ProvenanceChanged
} derive(Eq)

///|
pub extend FieldChangeKind with Eq::{equal, not_equal}

///|
pub struct FieldChange {
  priv key : String
  priv kind : FieldChangeKind
  priv before : Json?
  priv after : Json?
  priv before_origins : Array[FieldOrigin]
  priv after_origins : Array[FieldOrigin]
}

///|
pub fn FieldChange::key(self : FieldChange) -> String {
  self.key
}

///|
pub fn FieldChange::kind(self : FieldChange) -> FieldChangeKind {
  self.kind
}

///|
/// None means absent; Some("null") is a present JSON null. Number tokens matter.
pub fn FieldChange::before_json(self : FieldChange) -> String? {
  self.before.map(canonical_json)
}

///|
pub fn FieldChange::after_json(self : FieldChange) -> String? {
  self.after.map(canonical_json)
}

///|
pub fn FieldChange::before_trace(self : FieldChange) -> Array[FieldOrigin] {
  self.before_origins.copy()
}

///|
pub fn FieldChange::after_trace(self : FieldChange) -> Array[FieldOrigin] {
  self.after_origins.copy()
}

///|
pub struct ImpactEntry {
  priv path : String
  priv kind : ImpactKind
  priv before : AuditEntry?
  priv after : AuditEntry?
  priv changes : Array[FieldChange]
  priv sources_changed : Bool
}

///|
pub fn ImpactEntry::path(self : ImpactEntry) -> String {
  self.path
}

///|
pub fn ImpactEntry::kind(self : ImpactEntry) -> ImpactKind {
  self.kind
}

///|
pub fn ImpactEntry::before(self : ImpactEntry) -> AuditEntry? {
  self.before
}

///|
pub fn ImpactEntry::after(self : ImpactEntry) -> AuditEntry? {
  self.after
}

///|
pub fn ImpactEntry::changes(self : ImpactEntry) -> Array[FieldChange] {
  self.changes.copy()
}

///|
/// Meaningful only when neither side has a resolution error.
pub fn ImpactEntry::sources_changed(self : ImpactEntry) -> Bool {
  self.sources_changed
}

///|
pub struct ImpactReport {
  priv entries : Array[ImpactEntry]
}

///|
pub fn ImpactReport::entries(self : ImpactReport) -> Array[ImpactEntry] {
  self.entries.copy()
}

///|
pub fn ImpactReport::changed_count(self : ImpactReport) -> Int {
  self.entries
  .filter(e => e.kind == Changed || e.kind == Added || e.kind == Removed)
  .length()
}

///|
/// Count indeterminate scan paths, not individual diagnostics.
pub fn ImpactReport::error_count(self : ImpactReport) -> Int {
  self.entries.filter(e => e.kind == Unresolved).length()
}

///|
fn origins_json(origins : Array[FieldOrigin]) -> Json {
  Json::array(
    origins.map(o => {
      Json::object({ "path": Json::string(o.path), "value": o.value })
    }),
  )
}

///|
fn field_changes(
  before : ResolvedMetadata?,
  after : ResolvedMetadata?,
) -> Array[FieldChange] {
  let keys : Map[String, Bool] = Map([])
  for result in [before, after] {
    if result is Some(result) {
      for key in result.keys() {
        keys[key] = true
      }
    }
  }
  let changes : Array[FieldChange] = []
  for key in sorted_keys(keys) {
    let old = match before {
      Some(r) => r.get(key)
      None => None
    }
    let new = match after {
      Some(r) => r.get(key)
      None => None
    }
    let old_origins = match before {
      Some(r) => r.trace(key)
      None => []
    }
    let new_origins = match after {
      Some(r) => r.trace(key)
      None => []
    }
    let kind = match (old, new) {
      (None, Some(_)) => Some(FieldChangeKind::Added)
      (Some(_), None) => Some(FieldChangeKind::Removed)
      (Some(a), Some(b)) =>
        if canonical_json(a) != canonical_json(b) {
          Some(ValueChanged)
        } else if canonical_json(origins_json(old_origins)) !=
          canonical_json(origins_json(new_origins)) {
          Some(ProvenanceChanged)
        } else {
          None
        }
      (None, None) => None
    }
    if kind is Some(kind) {
      changes.push({
        key,
        kind,
        before: old,
        after: new,
        before_origins: old_origins,
        after_origins: new_origins,
      })
    }
  }
  changes
}

///|
/// Compare the sorted union of indexed scans. Errors remain indeterminate;
/// nothing is inferred about omitted sidecars or image content.
pub fn DatasetIndex::compare(
  self : DatasetIndex,
  after : DatasetIndex,
) -> ImpactReport {
  let old : Map[String, AuditEntry] = Map([])
  let new : Map[String, AuditEntry] = Map([])
  let paths : Map[String, Bool] = Map([])
  for e in self.audit_all().entries {
    old[e.path] = e
    paths[e.path] = true
  }
  for e in after.audit_all().entries {
    new[e.path] = e
    paths[e.path] = true
  }
  let entries = sorted_keys(paths).map(path => {
    let before = old.get(path)
    let after = new.get(path)
    let old_result = match before {
      Some(e) => e.result
      None => None
    }
    let new_result = match after {
      Some(e) => e.result
      None => None
    }
    if before is Some({ error: Some(_), .. }) ||
      after is Some({ error: Some(_), .. }) {
      {
        path,
        kind: Unresolved,
        before,
        after,
        changes: [],
        sources_changed: false,
      }
    } else {
      let changes = field_changes(old_result, new_result)
      let old_sources = match old_result {
        Some(r) => r.applied
        None => []
      }
      let new_sources = match new_result {
        Some(r) => r.applied
        None => []
      }
      let sources_changed = old_sources != new_sources
      let kind = match (before, after) {
        (None, Some(_)) => ImpactKind::Added
        (Some(_), None) => ImpactKind::Removed
        _ =>
          if changes.is_empty() && !sources_changed {
            Unchanged
          } else {
            Changed
          }
      }
      { path, kind, before, after, changes, sources_changed, }
    }
  })
  { entries, }
}

///|
fn impact_kind_name(kind : ImpactKind) -> String {
  match kind {
    Unchanged => "unchanged"
    Changed => "changed"
    Added => "added"
    Removed => "removed"
    Unresolved => "unresolved"
  }
}

///|
fn change_kind_name(kind : FieldChangeKind) -> String {
  match kind {
    Added => "added"
    Removed => "removed"
    ValueChanged => "value_changed"
    ProvenanceChanged => "provenance_changed"
  }
}

///|
fn AuditEntry::impact_value(self : AuditEntry) -> Json {
  match (self.result, self.error) {
    (Some(r), None) =>
      Json::object({
        "status": Json::string("resolved"),
        "result": r.report_value(),
      })
    (None, Some(d)) =>
      Json::object({
        "status": Json::string("error"),
        "diagnostic": d.to_json(),
      })
    _ => abort("AuditEntry invariant")
  }
}

///|
/// Includes full before/after evidence even for unchanged and unresolved scans.
pub fn ImpactReport::to_json(self : ImpactReport) -> String {
  canonical_json(
    Json::object({
      "changed_count": Json::number(self.changed_count().to_double()),
      "error_count": Json::number(self.error_count().to_double()),
      "entries": Json::array(
        self.entries.map(e => {
          Json::object({
            "data_path": Json::string(e.path),
            "kind": Json::string(impact_kind_name(e.kind)),
            "before": e.before
            .map(AuditEntry::impact_value)
            .unwrap_or(Json::null()),
            "after": e.after
            .map(AuditEntry::impact_value)
            .unwrap_or(Json::null()),
            "sources_changed": Json::boolean(e.sources_changed),
            "changes": Json::array(
              e.changes.map(c => {
                Json::object({
                  "field": Json::string(c.key),
                  "kind": Json::string(change_kind_name(c.kind)),
                  "before_present": Json::boolean(c.before is Some(_)),
                  "after_present": Json::boolean(c.after is Some(_)),
                  "before": c.before.unwrap_or(Json::null()),
                  "after": c.after.unwrap_or(Json::null()),
                  "before_trace": origins_json(c.before_origins),
                  "after_trace": origins_json(c.after_origins),
                })
              }),
            ),
          })
        }),
      ),
    }),
  )
}
