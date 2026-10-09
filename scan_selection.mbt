///|
/// AND across entity names, OR across a name's choices and selected suffixes.
pub struct ScanQuery {
  priv suffixes : Array[String]
  priv entities : Map[String, Array[String]]
}

///|
fn ScanQuery::query_value(self : ScanQuery) -> Json {
  let entities : Map[String, Json] = Map([])
  for key in sorted_keys(self.entities) {
    entities[key] = Json::array(self.entities[key].map(Json::string))
  }
  Json::object({
    "suffixes": Json::array(self.suffixes.map(Json::string)),
    "entities": Json::object(entities),
  })
}

///|
pub fn ScanQuery::to_json(self : ScanQuery) -> String {
  canonical_json(self.query_value())
}

///|
/// Copies inputs, normalizes decimal indices without conversion to machine Int.
/// Empty choice lists, unsupported keys/values and normalized duplicates fail.
pub fn ScanQuery::new(
  suffixes : Array[String],
  entities : Map[String, Array[String]],
) -> ScanQuery raise TraceError {
  if suffixes.is_empty() || suffixes.length() > 3 {
    reject(
      "invalid_query_suffixes", "<scan-query>/suffixes", "Choose one or more distinct supported suffixes: bold, T1w, dwi.",
    )
  }
  let seen_suffixes : Map[String, Bool] = Map([])
  for suffix in suffixes {
    if !["bold", "T1w", "dwi"].contains(suffix) {
      reject(
        "unsupported_suffix", suffix, "Query supports only bold, T1w and dwi.",
      )
    }
    if seen_suffixes.contains(suffix) {
      reject("duplicate_query_choice", suffix, "Each suffix must occur once.")
    }
    seen_suffixes[suffix] = true
  }
  let normalized : Map[String, Array[String]] = Map([])
  let mut choices = suffixes.length()
  for key in sorted_keys(entities) {
    if ![
        "sub", "ses", "task", "acq", "ce", "rec", "dir", "run", "echo", "part", "chunk",
      ].contains(key) {
      reject(
        "unsupported_entity", key, "Use supported filename entity names; metadata predicates and wildcards are unsupported.",
      )
    }
    let values = entities[key]
    if values.is_empty() {
      reject(
        "empty_query_choices", key, "Choose at least one value or omit this entity constraint.",
      )
    }
    if values.length() > 256 - choices {
      reject(
        "scan_query_limit", "<scan-query>", "At most 256 total suffix/entity choices; reduce the selection scope.",
      )
    }
    choices += values.length()
    let seen : Map[String, String] = Map([])
    let items = values.map(value => {
      let canonical = entity_value(key, value, "<scan-query>/entities/" + key)
      let folded = canonical.to_lower()
      if seen.get(folded) is Some(existing) {
        reject(
          "duplicate_query_choice",
          key,
          "Duplicate, normalized-equal or case-colliding choices; select each value once.",
          related=[existing, value],
        )
      }
      seen[folded] = value
      canonical
    })
    items.sort_by(lexical_compare)
    normalized[key] = items
  }
  let selected_suffixes = suffixes.copy()
  selected_suffixes.sort_by(lexical_compare)
  let query : ScanQuery = { suffixes: selected_suffixes, entities: normalized, }
  if query.to_json().length() > 2097152 {
    reject(
      "input_limit", "<scan-query>", "Canonical scan query exceeds 2,097,152 UTF-16 units; reduce choices.",
    )
  }
  query
}

///|
/// Strict {suffixes:[strings],entities:{entity:[strings]}}; both mandatory.
pub fn ScanQuery::from_json(text : String) -> ScanQuery raise TraceError {
  guard parse_source("<scan-query>", text, container_limit=3) is Object(fields) else {
    reject(
      "invalid_scan_query", "<scan-query>", "Expected suffixes array and entities object.",
    )
    abort("reject raises")
  }
  for key in sorted_keys(fields) {
    if !["suffixes", "entities"].contains(key) {
      reject(
        "unknown_scan_query_field", key, "Use only suffixes and entities controls.",
      )
    }
  }
  guard fields.get("suffixes") is Some(Array(suffix_values)) &&
    fields.get("entities") is Some(Object(entity_values)) else {
    reject(
      "invalid_scan_query", "<scan-query>", "Both suffixes array and entities object are mandatory.",
    )
    abort("reject raises")
  }
  fn strings(
    values : Array[Json],
    path : String,
  ) -> Array[String] raise TraceError {
    values.map(value => {
      guard value is String(item) else {
        reject(
          "invalid_scan_query", path, "Every choice must be a string; decimal indices are strings too.",
        )
        abort("reject raises")
      }
      item
    })
  }
  let entities : Map[String, Array[String]] = Map([])
  for key in sorted_keys(entity_values) {
    guard entity_values[key] is Array(values) else {
      reject(
        "invalid_scan_query", key, "Each entity requires an array of string choices.",
      )
      abort("reject raises")
    }
    entities[key] = strings(values, key)
  }
  ScanQuery::new(strings(suffix_values, "<scan-query>/suffixes"), entities)
}

///|
pub struct ScanSelection {
  priv index : DatasetIndex
  priv query : ScanQuery
  priv selected : Array[String]
  priv excluded : Array[String]
}

///|
/// Selection depends only on validated filename entities, never metadata success.
/// The original index is retained so ancestor and unselected-source inheritance
/// remain available when auditing the selected scans.
pub fn DatasetIndex::select_scans(
  self : DatasetIndex,
  query : ScanQuery,
) -> ScanSelection {
  let selected : Array[String] = []
  let excluded : Array[String] = []
  for file in self.files {
    let matches = query.suffixes.contains(file.suffix) &&
      query.entities
      .iter()
      .all(pair => {
        match file.entities.get(pair.0) {
          Some(value) => pair.1.contains(value)
          None => false
        }
      })
    if matches {
      selected.push(file.path)
    } else {
      excluded.push(file.path)
    }
  }
  { index: self, query, selected, excluded, }
}

///|
pub fn ScanSelection::paths(self : ScanSelection) -> Array[String] {
  self.selected.copy()
}

///|
/// Empty selection returns an empty audit, not audit_all(). Errors are retained.
pub fn ScanSelection::audit(self : ScanSelection) -> AuditReport {
  self.index.audit(self.selected)
}

///|
/// Inventory accounting, not a new manifest; no sources/data are deleted.
pub fn ScanSelection::to_json(self : ScanSelection) -> String {
  canonical_json(
    Json::object({
      "scope": Json::string("indexed_scans"),
      "query": self.query.query_value(),
      "selected_count": Json::number(self.selected.length().to_double()),
      "total_count": Json::number(self.index.files.length().to_double()),
      "selected_paths": Json::array(self.selected.map(Json::string)),
      "excluded_paths": Json::array(self.excluded.map(Json::string)),
    }),
  )
}
