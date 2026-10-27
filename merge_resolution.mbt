///|
priv struct SourceDecision {
  path : String
  metadata : Json?
  reason : String
}

///|
priv struct ScanDecision {
  path : String
  retained : Bool
  reason : String
}

///|
priv struct EffectiveDecision {
  path : String
  key : String
  value : Json?
  reason : String
}

///|
/// Explicit decisions bound to three complete immutable snapshots. Complete
/// source replacements (null removes a source) cannot affect unnamed sources.
/// Effective assertions compare exact JSON tokens, including absent vs null.
pub struct MergeResolution {
  priv base : DatasetIndex
  priv left : DatasetIndex
  priv right : DatasetIndex
  priv sources : Array[SourceDecision]
  priv scans : Array[ScanDecision]
  priv effective : Array[EffectiveDecision]
}

///|
fn resolution_object(
  value : Json,
  keys : Array[String],
  location : String,
) -> Map[String, Json] raise TraceError {
  guard value is Object(fields) && sorted_keys(fields) == keys else {
    reject(
      "invalid_merge_resolution",
      location,
      "Required controls: " +
      keys.join(", ") +
      "; unknown or missing controls are rejected.",
    )
    abort("reject raises")
  }
  fields
}

///|
fn decision_reason(
  fields : Map[String, Json],
  path : String,
) -> String raise TraceError {
  guard fields.get("reason") is Some(String(reason)) &&
    !reason.trim().is_empty() &&
    reason.length() <= 4096 else {
    reject(
      "invalid_resolution_reason", path, "Each decision needs a nonblank reason of at most 4,096 UTF-16 units.",
    )
    abort("reject raises")
  }
  reason
}

///|
fn decision_path(
  fields : Map[String, Json],
  source~ : Bool,
) -> String raise TraceError {
  guard fields.get("path") is Some(String(path)) else {
    reject(
      "invalid_merge_resolution", "<merge-resolution>", "Decision path must be a supported relative path string.",
    )
    abort("reject raises")
  }
  ignore(selector(path, sidecar=source))
  path
}

///|
fn resolution_coordinate(path : String, key : String) -> String {
  canonical_json(Json::array([Json::string(path), Json::string(key)]))
}

///|
/// Strict v1 control grammar. Up to 256 source/scan decisions combined and
/// 1,024 effective field assertions. Snapshot limits remain independently enforced.
pub fn MergeResolution::from_json(
  text : String,
) -> MergeResolution raise TraceError {
  let fields = resolution_object(
    parse_source(
      "<merge-resolution>",
      text,
      container_limit=80,
      text_limit=16777216,
    ),
    ["base", "effective", "left", "right", "scans", "sources"],
    "<merge-resolution>",
  )
  guard fields["sources"] is Array(sources) &&
    fields["scans"] is Array(scans) &&
    fields["effective"] is Array(effective) else {
    reject(
      "invalid_merge_resolution", "<merge-resolution>", "sources, scans and effective must be arrays.",
    )
    abort("reject raises")
  }
  if sources.length() + scans.length() > 256 || effective.length() > 1024 {
    reject(
      "resolution_limit", "<merge-resolution>", "At most 256 source/scan decisions combined and 1,024 effective assertions; narrow the review scope.",
    )
  }
  let seen_sources : Map[String, Bool] = Map([])
  let source_decisions = sources.map(value => {
    let entry = resolution_object(
      value,
      ["metadata", "path", "reason"],
      "<merge-resolution>/sources",
    )
    let path = decision_path(entry, source=true)
    if seen_sources.contains(path.to_lower()) {
      reject(
        "duplicate_resolution", path, "Each source path can be decided only once, including case variants.",
      )
    }
    seen_sources[path.to_lower()] = true
    let metadata = match entry["metadata"] {
      Null => None
      Object(_) as obj => {
        // Reapply sidecar depth and text limits, not just envelope limits.
        let parsed = parse_source(path, canonical_json(obj))
        Some(parsed)
      }
      _ => {
        reject(
          "invalid_merge_resolution", path, "metadata must be a complete object, or null to remove the source.",
        )
        None
      }
    }
    { path, metadata, reason: decision_reason(entry, path), }
  })
  let seen_scans : Map[String, Bool] = Map([])
  let scan_decisions = scans.map(value => {
    let entry = resolution_object(
      value,
      ["include", "path", "reason"],
      "<merge-resolution>/scans",
    )
    let path = decision_path(entry, source=false)
    if seen_scans.contains(path.to_lower()) {
      reject(
        "duplicate_resolution", path, "Each scan path can be decided only once, including case variants.",
      )
    }
    seen_scans[path.to_lower()] = true
    guard entry["include"] is (True | False) else {
      reject(
        "invalid_merge_resolution", path, "include must be a boolean; no coercion is performed.",
      )
      abort("reject raises")
    }
    {
      path,
      retained: entry["include"] == Json::boolean(true),
      reason: decision_reason(entry, path),
    }
  })
  let seen_effective : Map[String, Bool] = Map([])
  let effective_decisions = effective.map(value => {
    let entry = resolution_object(
      value,
      ["key", "path", "present", "reason", "value"],
      "<merge-resolution>/effective",
    )
    let path = decision_path(entry, source=false)
    guard entry["key"] is String(key) && entry["present"] is (True | False) else {
      reject(
        "invalid_merge_resolution", path, "Effective assertions require a string key and boolean present.",
      )
      abort("reject raises")
    }
    let present = entry["present"] == Json::boolean(true)
    let coordinate = resolution_coordinate(path, key)
    if seen_effective.contains(coordinate) {
      reject(
        "duplicate_resolution", path, "Each effective path/key pair can occur only once.",
      )
    }
    seen_effective[coordinate] = true
    if !present && entry["value"] != Json::null() {
      reject(
        "invalid_merge_resolution", path, "An absent-field assertion requires value:null; unsupported data is never discarded.",
      )
    }
    let value = if present {
      Some(parse_source(path, canonical_json(entry["value"])))
    } else {
      None
    }
    { path, key, value, reason: decision_reason(entry, path), }
  })
  source_decisions.sort_by((a, b) => lexical_compare(a.path, b.path))
  scan_decisions.sort_by((a, b) => lexical_compare(a.path, b.path))
  effective_decisions.sort_by((a, b) => {
    let path = lexical_compare(a.path, b.path)
    if path == 0 {
      lexical_compare(a.key, b.key)
    } else {
      path
    }
  })
  let plan : MergeResolution = {
    base: DatasetIndex::from_json(canonical_json(fields["base"])),
    left: DatasetIndex::from_json(canonical_json(fields["left"])),
    right: DatasetIndex::from_json(canonical_json(fields["right"])),
    sources: source_decisions,
    scans: scan_decisions,
    effective: effective_decisions,
  }
  if plan.to_json().length() > 16777216 {
    reject(
      "resolution_limit", "<merge-resolution>", "Canonical resolution exceeds 16,777,216 UTF-16 units.",
    )
  }
  plan
}

///|
pub fn MergeResolution::to_json(self : MergeResolution) -> String {
  canonical_json(
    Json::object({
      "base": self.base.manifest_value(),
      "left": self.left.manifest_value(),
      "right": self.right.manifest_value(),
      "sources": Json::array(
        self.sources.map(d => {
          Json::object({
            "path": Json::string(d.path),
            "metadata": d.metadata.unwrap_or(Json::null()),
            "reason": Json::string(d.reason),
          })
        }),
      ),
      "scans": Json::array(
        self.scans.map(d => {
          Json::object({
            "path": Json::string(d.path),
            "include": Json::boolean(d.retained),
            "reason": Json::string(d.reason),
          })
        }),
      ),
      "effective": Json::array(
        self.effective.map(d => {
          Json::object({
            "path": Json::string(d.path),
            "key": Json::string(d.key),
            "present": Json::boolean(d.value is Some(_)),
            "value": d.value.unwrap_or(Json::null()),
            "reason": Json::string(d.reason),
          })
        }),
      ),
    }),
  )
}

///|
/// A directly editable binding document; empty decisions do not waive conflicts.
pub fn MergeReport::resolution_template(self : MergeReport) -> String {
  let plan : MergeResolution = {
    base: self.base,
    left: self.left,
    right: self.right,
    sources: [],
    scans: [],
    effective: [],
  }
  plan.to_json()
}

///|
fn MergeResolution::source_at(
  self : MergeResolution,
  path : String,
) -> SourceDecision? {
  self.sources.search_by(d => d.path == path).map(i => self.sources[i])
}

///|
fn MergeResolution::scan_at(
  self : MergeResolution,
  path : String,
) -> ScanDecision? {
  self.scans.search_by(d => d.path == path).map(i => self.scans[i])
}

///|
fn MergeResolution::has_effective(
  self : MergeResolution,
  path : String,
  key : String,
) -> Bool {
  self.effective.any(d => d.path == path && d.key == key)
}

///|
fn MergeResolution::check_effective(
  self : MergeResolution,
  candidate : DatasetIndex,
) -> Unit raise TraceError {
  for decision in self.effective {
    let result = candidate.resolve(decision.path)
    if !merge_equal(result.values.get(decision.key), decision.value) {
      reject(
        "resolution_value_mismatch",
        decision.path,
        "Effective assertion for " +
        Json::string(decision.key).stringify() +
        " does not match the resolved candidate, including exact number tokens and presence; revise sources or the assertion explicitly.",
      )
    }
  }
}

///|
fn paths_in_inputs(
  base : DatasetIndex,
  left : DatasetIndex,
  right : DatasetIndex,
  path : String,
  source~ : Bool,
) -> Bool {
  [base, left, right].any(index => {
    if source {
      index.sidecars.any(s => s.selector.path == path)
    } else {
      index.file_positions.contains(path)
    }
  })
}
