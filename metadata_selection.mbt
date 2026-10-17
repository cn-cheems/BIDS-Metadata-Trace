///|
/// Exact predicates over effective, inherited top-level fields.
pub struct MetadataQuery {
  priv present : Array[String]
  priv absent : Array[String]
  priv equals : Map[String, Array[Json]]
  priv fields : Array[String]
}

///|
fn MetadataQuery::query_value(self : MetadataQuery) -> Json {
  let equals : Map[String, Json] = Map([])
  for field in sorted_keys(self.equals) {
    equals[field] = Json::array(self.equals[field])
  }
  Json::object({
    "present": Json::array(self.present.map(Json::string)),
    "absent": Json::array(self.absent.map(Json::string)),
    "equals": Json::object(equals),
  })
}

///|
pub fn MetadataQuery::to_json(self : MetadataQuery) -> String {
  canonical_json(self.query_value())
}

///|
/// All controls mandatory; AND across fields, OR within exact value choices.
/// Equality requires presence. Null is present; unknown controls never vanish.
pub fn MetadataQuery::from_json(
  text : String,
) -> MetadataQuery raise TraceError {
  guard parse_source("<metadata-query>", text, container_limit=67)
    is Object(input) else {
    reject(
      "invalid_metadata_query", "<metadata-query>", "Expected present, absent and equals controls.",
    )
    abort("reject raises")
  }
  for key in sorted_keys(input) {
    if !["present", "absent", "equals"].contains(key) {
      reject(
        "unknown_metadata_query_field", key, "Use only present, absent and equals controls.",
      )
    }
  }
  guard input.get("present") is Some(Array(present)) &&
    input.get("absent") is Some(Array(absent)) &&
    input.get("equals") is Some(Object(equals)) else {
    reject(
      "invalid_metadata_query", "<metadata-query>", "All three controls are mandatory: arrays present/absent and object equals.",
    )
    abort("reject raises")
  }
  // Reuse the strict exact-value contract, not approximate core Json equality.
  let expected = MetadataExpectations::from_json(
    canonical_json(
      Json::object({
        "required": Json::array(present),
        "allowed": Json::object(equals),
      }),
    ),
  )
  let missing = absent.map(value => {
    guard value is String(field) else {
      reject(
        "invalid_metadata_query", "<metadata-query>/absent", "Absent entries must be field names.",
      )
      abort("reject raises")
    }
    field
  })
  ignore(review_fields(missing))
  missing.sort_by(lexical_compare)
  let all : Map[String, Bool] = Map([])
  for field in expected.fields {
    all[field] = true
  }
  for field in missing {
    if all.contains(field) {
      reject(
        "conflicting_metadata_predicate", field, "A field cannot be both absent and present/equal; remove the contradictory predicate.",
      )
    }
    all[field] = true
  }
  let query : MetadataQuery = {
    present: expected.required,
    absent: missing,
    equals: expected.allowed,
    fields: review_fields(sorted_keys(all)),
  }
  if query.to_json().length() > 2097152 {
    reject(
      "input_limit", "<metadata-query>", "Canonical metadata query exceeds 2,097,152 UTF-16 units.",
    )
  }
  query
}

///|
pub struct MetadataSelection {
  priv selected : Array[String]
  priv retained : AuditReport
  priv errors : Int32
  priv document : Json
}

///|
/// Only proven matches; unresolved entries are accounted separately, never excluded.
pub fn MetadataSelection::paths(self : MetadataSelection) -> Array[String] {
  self.selected.copy()
}

///|
pub fn MetadataSelection::error_count(self : MetadataSelection) -> Int32 {
  self.errors
}

///|
/// Matches plus unresolved entries, in input order, so downstream gates see errors.
pub fn MetadataSelection::audit(self : MetadataSelection) -> AuditReport {
  self.retained
}

///|
pub fn MetadataSelection::to_json(self : MetadataSelection) -> String {
  canonical_json(self.document)
}

///|
pub fn MetadataSelection::to_json_value(self : MetadataSelection) -> Json {
  copy_json(self.document)
}

///|
/// Every input occurrence has a classification and complete resolution evidence.
/// Failed queries remain in audit(); they are not guessed to be nonmatches.
pub fn AuditReport::filter_metadata(
  self : AuditReport,
  query : MetadataQuery,
) -> MetadataSelection {
  let selected : Array[String] = []
  let retained : Array[AuditEntry] = []
  let mut errors = 0
  let mut excluded = 0
  let entries = self.entries.mapi((i, entry) => {
    let item : Map[String, Json] = {
      "query_index": Json::number(i.to_double()),
      "data_path": Json::string(entry.path),
    }
    match (entry.result, entry.error) {
      (None, Some(error)) => {
        errors += 1
        retained.push(entry)
        item["status"] = Json::string("error")
        item["diagnostic"] = error.to_json()
      }
      (Some(result), None) => {
        let mut matches = true
        let checks = query.fields.map(field => {
          let actual = result.values.get(field)
          let absent = query.absent.contains(field)
          let choices = query.equals.get(field)
          let matched = if absent {
            actual is None
          } else {
            match (actual, choices) {
              (Some(value), Some(values)) =>
                values.any(v => canonical_json(v) == canonical_json(value))
              (Some(_), None) => true
              _ => false
            }
          }
          if !matched {
            matches = false
          }
          let check : Map[String, Json] = {
            "field": Json::string(field),
            "predicate": Json::string(
              if absent {
                "absent"
              } else if choices is Some(_) {
                "equals"
              } else {
                "present"
              },
            ),
            "present": Json::boolean(actual is Some(_)),
            "matched": Json::boolean(matched),
          }
          if actual is Some(value) {
            check["actual"] = value
            check["trace"] = history_value(result.origins[field])
          }
          Json::object(check)
        })
        if matches {
          selected.push(entry.path)
          retained.push(entry)
        } else {
          excluded += 1
        }
        item["status"] = Json::string(
          if matches {
            "matched"
          } else {
            "excluded"
          },
        )
        item["checks"] = Json::array(checks)
        item["result"] = result.report_value()
      }
      _ => abort("AuditEntry invariant")
    }
    Json::object(item)
  })
  {
    selected,
    retained: { entries: retained, },
    errors,
    document: Json::object({
      "query": query.query_value(),
      "total_count": Json::number(entries.length().to_double()),
      "matched_count": Json::number(selected.length().to_double()),
      "excluded_count": Json::number(excluded.to_double()),
      "error_count": Json::number(errors.to_double()),
      "entries": Json::array(entries),
    }),
  }
}

///|
pub fn DatasetIndex::select_metadata(
  self : DatasetIndex,
  query : MetadataQuery,
) -> MetadataSelection {
  self.audit_all().filter_metadata(query)
}
