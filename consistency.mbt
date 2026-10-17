///|
/// Exact metadata equality within filename-entity groups, without a fixed
/// expected value. Missing grouping entities form an explicit null group.
pub struct ConsistencyRules {
  priv group_by : Array[String]
  priv fields : Array[String]
  priv require_present : Bool
}

///|
pub fn ConsistencyRules::new(
  group_by : Array[String],
  fields : Array[String],
  require_present : Bool,
) -> ConsistencyRules raise TraceError {
  let group_by = review_fields(group_by)
  let fields = review_fields(fields)
  if fields.is_empty() {
    reject(
      "empty_consistency_fields", "<consistency>", "Specify at least one metadata field.",
    )
  }
  for key in group_by {
    if ![
        "sub", "ses", "task", "acq", "ce", "rec", "dir", "run", "echo", "part", "chunk",
      ].contains(key) {
      reject(
        "invalid_group_entity", key, "Group by supported filename entities only; select a suffix scope before auditing mixed modalities.",
      )
    }
  }
  group_by.sort_by(lexical_compare)
  fields.sort_by(lexical_compare)
  let rules : ConsistencyRules = { group_by, fields, require_present, }
  ignore(parse_source("<consistency>", rules.to_json(), container_limit=2))
  rules
}

///|
fn ConsistencyRules::rules_value(self : ConsistencyRules) -> Json {
  Json::object({
    "group_by": Json::array(self.group_by.map(Json::string)),
    "fields": Json::array(self.fields.map(Json::string)),
    "require_present": Json::boolean(self.require_present),
  })
}

///|
pub fn ConsistencyRules::to_json(self : ConsistencyRules) -> String {
  canonical_json(self.rules_value())
}

///|
pub fn ConsistencyRules::from_json(
  text : String,
) -> ConsistencyRules raise TraceError {
  guard parse_source("<consistency>", text, container_limit=2) is Object(input) else {
    reject(
      "invalid_consistency_rules", "<consistency>", "Expected group_by, fields and require_present.",
    )
    abort("reject raises")
  }
  if sorted_keys(input) != ["fields", "group_by", "require_present"] {
    reject(
      "invalid_consistency_rules", "<consistency>", "Exactly fields, group_by and require_present must be supplied.",
    )
  }
  guard input["fields"] is Array(fields) && input["group_by"] is Array(groups) else {
    reject(
      "invalid_consistency_rules", "<consistency>", "fields and group_by must be string arrays.",
    )
    abort("reject raises")
  }
  let strings = fn(values : Array[Json]) -> Array[String] raise TraceError {
    values.map(value => {
      match value {
        String(s) => s
        _ => {
          reject(
            "invalid_consistency_rules", "<consistency>", "Array entries must be strings.",
          )
          abort("reject raises")
        }
      }
    })
  }
  let present = match input["require_present"] {
    True => true
    False => false
    _ => {
      reject(
        "invalid_consistency_rules", "<consistency>", "require_present must be boolean.",
      )
      abort("reject raises")
    }
  }
  ConsistencyRules::new(strings(groups), strings(fields), present)
}

///|
pub struct ConsistencyReport {
  priv decision : ExpectationDecision
  priv violations : Int32
  priv value : Json
}

///|
pub fn ConsistencyReport::decision(
  self : ConsistencyReport,
) -> ExpectationDecision {
  self.decision
}

///|
pub fn ConsistencyReport::violation_count(self : ConsistencyReport) -> Int32 {
  self.violations
}

///|
pub fn ConsistencyReport::to_json(self : ConsistencyReport) -> String {
  canonical_json(self.value)
}

///|
pub fn AuditReport::check_consistency(
  self : AuditReport,
  rules : ConsistencyRules,
) -> ConsistencyReport {
  let groups : Map[String, Array[Int32]] = Map([])
  let keys : Map[String, Json] = Map([])
  for i, entry in self.entries {
    if entry.result is Some(_) {
      let selected = try! selector(entry.path, sidecar=false)
      let key : Map[String, Json] = Map([])
      for entity in rules.group_by {
        key[entity] = match selected.entities.get(entity) {
          Some(v) => Json::string(v)
          None => Json::null()
        }
      }
      let value = Json::object(key)
      let token = canonical_json(value)
      keys[token] = value
      match groups.get(token) {
        Some(indices) => indices.push(i)
        None => groups[token] = [i]
      }
    }
  }
  let mut violations = 0
  let reports = sorted_keys(groups).map(key => {
    let checks = rules.fields.map(field => {
      let buckets : Map[String, Array[Int32]] = Map([])
      let values : Map[String, Json] = Map([])
      let mut missing = 0
      for i in groups[key] {
        let result = self.entries[i].result.unwrap()
        let state = match result.get(field) {
          Some(value) =>
            Json::object({ "present": Json::boolean(true), "value": value })
          None => {
            missing += 1
            Json::object({ "present": Json::boolean(false) })
          }
        }
        let token = canonical_json(state)
        values[token] = state
        match buckets.get(token) {
          Some(indices) => indices.push(i)
          None => buckets[token] = [i]
        }
      }
      let passed = buckets.length() == 1 &&
        (!rules.require_present || missing == 0)
      if !passed {
        violations += 1
      }
      Json::object({
        "field": Json::string(field),
        "pass": Json::boolean(passed),
        "missing_count": Json::number(missing.to_double()),
        "states": Json::array(
          sorted_keys(buckets).map(token => {
            Json::object({
              "state": values[token],
              "occurrences": Json::array(
                buckets[token].map(i => {
                  Json::object({
                    "query_index": Json::number(i.to_double()),
                    "data_path": Json::string(self.entries[i].path),
                    "trace": history_value(
                      self.entries[i].result.unwrap().trace(field),
                    ),
                  })
                }),
              ),
            })
          }),
        ),
      })
    })
    Json::object({ "group": keys[key], "checks": Json::array(checks) })
  })
  let decision : ExpectationDecision = if self.entries.is_empty() ||
    self.error_count() > 0 {
    Indeterminate
  } else if violations > 0 {
    Violations
  } else {
    Pass
  }
  let name = match decision {
    Pass => "pass"
    Violations => "violations"
    Indeterminate => "indeterminate"
  }
  {
    decision,
    violations,
    value: Json::object({
      "decision": Json::string(name),
      "violation_count": Json::number(violations.to_double()),
      "rules": rules.rules_value(),
      "audit": self.report_value(),
      "groups": Json::array(reports),
    }),
  }
}
