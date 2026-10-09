///|
fn csv_record(cells : Array[String]) -> String {
  cells
  .map(cell => "\"" + cell.replace_all(old="\"", new="\"\"") + "\"")
  .join(",") +
  "\r\n"
}

///|
fn json_cell(value : Json) -> String {
  "json:" + canonical_json(value)
}

///|
/// RFC 4180 quoted UTF-8 review projection; dynamic cells contain tagged JSON.
/// Absence (false), null (true/json:null) and unresolved (empty presence) differ.
/// Rejects output above 16 Mi UTF-16 units rather than returning partial rows.
pub fn AuditReport::to_review_csv(
  self : AuditReport,
  keys : Array[String],
) -> String raise TraceError {
  let fields = review_fields(keys)
  let headers = ["query_index", "data_path", "status", "diagnostic"]
  for key in fields {
    let tag = canonical_json(Json::string(key))
    for column in ["present:", "value:", "winning_source:", "trace:"] {
      headers.push(column + tag)
    }
  }
  let header = csv_record(headers)
  let lines = [header]
  let mut length = header.length()
  if length > 16777216 {
    reject(
      "review_csv_limit", "", "CSV exceeds 16 Mi UTF-16 units; reduce requested fields or scans.",
    )
  }
  for i, entry in self.entries {
    let cells = [i.to_string(), json_cell(Json::string(entry.path))]
    match (entry.result, entry.error) {
      (Some(result), None) => {
        cells.push("resolved")
        cells.push("")
        for key in fields {
          match result.values.get(key) {
            None => {
              cells.push("false")
              for _ in 0..<3 {
                cells.push("")
              }
            }
            Some(value) => {
              let history = result.origins[key]
              cells.push("true")
              cells.push(json_cell(value))
              cells.push(
                json_cell(Json::string(history[history.length() - 1].path)),
              )
              cells.push(json_cell(history_value(history)))
            }
          }
        }
      }
      (None, Some(error)) => {
        cells.push("error")
        cells.push(json_cell(error.to_json()))
        for _ in fields {
          for _ in 0..<4 {
            cells.push("")
          }
        }
      }
      _ => abort("AuditEntry invariant")
    }
    let line = csv_record(cells)
    if line.length() > 16777216 - length {
      reject(
        "review_csv_limit",
        entry.path,
        "CSV exceeds 16 Mi UTF-16 units; reduce requested fields or scans.",
      )
    }
    length += line.length()
    lines.push(line)
  }
  lines.join("")
}
