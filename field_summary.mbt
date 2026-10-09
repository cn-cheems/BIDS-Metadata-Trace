///|
fn review_fields(keys : Array[String]) -> Array[String] raise TraceError {
  if keys.length() > 256 {
    reject("field_request_limit", "", "Request at most 256 metadata fields.")
  }
  let seen : Map[String, Bool] = Map([])
  for key in keys {
    if seen.contains(key) {
      reject("duplicate_field_request", key, "Request each field only once.")
    }
    seen[key] = true
  }
  keys.copy()
}

///|
fn observation_value(i : Int, path : String) -> Json {
  Json::object({
    "query_index": Json::number(i.to_double()),
    "data_path": Json::string(path),
  })
}

///|
fn history_value(history : Array[FieldOrigin]) -> Json {
  Json::array(
    history.map(origin => {
      Json::object({ "path": Json::string(origin.path), "value": origin.value })
    }),
  )
}

///|
/// Exact whole-value groups over an audit, retaining duplicate requests and errors.
pub struct FieldSummaryReport {
  priv document : Json
  priv errors : Int
}

///|
pub fn FieldSummaryReport::error_count(self : FieldSummaryReport) -> Int {
  self.errors
}

///|
/// A defensive structured view; numeric source tokens remain intact.
pub fn FieldSummaryReport::to_json_value(self : FieldSummaryReport) -> Json {
  copy_json(self.document)
}

///|
pub fn FieldSummaryReport::to_json(self : FieldSummaryReport) -> String {
  canonical_json(self.document)
}

///|
/// Missing means resolved and absent; unresolved queries are reported separately.
/// Group identity is exact canonical JSON, not numeric/scientific equivalence.
pub fn AuditReport::summarize_fields(
  self : AuditReport,
  keys : Array[String],
) -> FieldSummaryReport raise TraceError {
  let fields = review_fields(keys)
  let errors : Array[Json] = []
  for i, entry in self.entries {
    if entry.error is Some(error) {
      errors.push(
        Json::object({
          "query_index": Json::number(i.to_double()),
          "data_path": Json::string(entry.path),
          "diagnostic": error.to_json(),
        }),
      )
    }
  }
  let summaries = fields.map(key => {
    let values : Map[String, Json] = Map([])
    let groups : Map[String, Array[Json]] = Map([])
    let missing : Array[Json] = []
    for i, entry in self.entries {
      if entry.result is Some(result) {
        match result.values.get(key) {
          None => missing.push(observation_value(i, entry.path))
          Some(value) => {
            let token = canonical_json(value)
            if !groups.contains(token) {
              groups[token] = []
              values[token] = value
            }
            let history = result.origins[key]
            groups[token].push(
              Json::object({
                "query_index": Json::number(i.to_double()),
                "data_path": Json::string(entry.path),
                "winning_source": Json::string(
                  history[history.length() - 1].path,
                ),
                "trace": history_value(history),
              }),
            )
          }
        }
      }
    }
    let tokens = sorted_keys(values)
    Json::object({
      "field": Json::string(key),
      "missing": Json::array(missing),
      "groups": Json::array(
        tokens.map(token => {
          Json::object({
            "value": values[token],
            "observations": Json::array(groups[token]),
          })
        }),
      ),
    })
  })
  {
    errors: errors.length(),
    document: Json::object({
      "query_count": Json::number(self.entries.length().to_double()),
      "resolved_count": Json::number(
        (self.entries.length() - errors.length()).to_double(),
      ),
      "error_count": Json::number(errors.length().to_double()),
      "errors": Json::array(errors),
      "fields": Json::array(summaries),
    }),
  }
}
