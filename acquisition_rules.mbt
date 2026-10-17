///|
priv struct ScopedAcquisitionRule {
  id : String
  query : ScanQuery
  expected : MetadataExpectations
}

///|
/// Every declared rule must match scans; every indexed scan must be covered.
/// Overlaps are conjunctive, never first/last-rule-wins.
pub struct AcquisitionRules {
  priv rules : Array[ScopedAcquisitionRule]
}

///|
fn AcquisitionRules::rules_value(self : AcquisitionRules) -> Json {
  Json::object({
    "rules": Json::array(
      self.rules.map(rule => {
        Json::object({
          "id": Json::string(rule.id),
          "select": rule.query.query_value(),
          "expect": rule.expected.expectations_value(),
        })
      }),
    ),
  })
}

///|
pub fn AcquisitionRules::to_json(self : AcquisitionRules) -> String {
  canonical_json(self.rules_value())
}

///|
pub fn AcquisitionRules::from_json(
  text : String,
) -> AcquisitionRules raise TraceError {
  guard parse_source("<acquisition-rules>", text, container_limit=70)
    is Object(input) else {
    reject(
      "invalid_acquisition_rules", "<acquisition-rules>", "Expected a nonempty rules array.",
    )
    abort("reject raises")
  }
  for key in sorted_keys(input) {
    if key != "rules" {
      reject(
        "unknown_acquisition_rule_field", key, "Use only the rules control.",
      )
    }
  }
  guard input.get("rules") is Some(Array(values)) &&
    !values.is_empty() &&
    values.length() <= 64 else {
    reject(
      "invalid_acquisition_rules", "<acquisition-rules>", "Declare between 1 and 64 scoped rules.",
    )
    abort("reject raises")
  }
  let seen : Map[String, String] = Map([])
  let rules = values.map(value => {
    guard value is Object(fields) else {
      reject(
        "invalid_acquisition_rule", "<acquisition-rules>/rules", "Each rule requires id, select and expect.",
      )
      abort("reject raises")
    }
    for key in sorted_keys(fields) {
      if !["id", "select", "expect"].contains(key) {
        reject(
          "unknown_acquisition_rule_field", key, "Rule controls are exactly id, select and expect.",
        )
      }
    }
    guard fields.get("id") is Some(String(id)) &&
      fields.get("select") is Some(query) &&
      fields.get("expect") is Some(expected) else {
      reject(
        "invalid_acquisition_rule", "<acquisition-rules>/rules", "Each rule requires string id plus select and expect objects.",
      )
      abort("reject raises")
    }
    if id.is_empty() ||
      id.length() > 64 ||
      !id
      .iter()
      .all(c => {
        match c {
          'a'..<='z' | 'A'..<='Z' | '0'..<='9' | '_' | '-' => true
          _ => false
        }
      }) {
      reject(
        "invalid_rule_id", id, "Use 1–64 ASCII letters, digits, underscores or hyphens for a rule id.",
      )
    }
    if seen.get(id.to_lower()) is Some(existing) {
      reject(
        "duplicate_rule_id",
        id,
        "Rule ids must be unique including case variants.",
        related=[existing],
      )
    }
    seen[id.to_lower()] = id
    {
      id,
      query: ScanQuery::from_json(canonical_json(query)),
      expected: MetadataExpectations::from_json(canonical_json(expected)),
    }
  })
  rules.sort_by((a, b) => lexical_compare(a.id, b.id))
  let result : AcquisitionRules = { rules, }
  if result.to_json().length() > 2097152 {
    reject(
      "input_limit", "<acquisition-rules>", "Canonical rules exceed 2,097,152 UTF-16 units; reduce the review scope.",
    )
  }
  result
}

///|
pub struct AcquisitionReport {
  priv outcome : ExpectationDecision
  priv violations : Int32
  priv errors : Int32
  priv uncovered : Array[String]
  priv unmatched : Array[String]
  priv document : Json
}

///|
pub fn AcquisitionReport::decision(
  self : AcquisitionReport,
) -> ExpectationDecision {
  self.outcome
}

///|
/// Failed rule/field checks; a scan covered by multiple rules can contribute to each.
pub fn AcquisitionReport::violation_count(self : AcquisitionReport) -> Int32 {
  self.violations
}

///|
/// Unresolved indexed scans, counted once irrespective of rule overlap.
pub fn AcquisitionReport::error_count(self : AcquisitionReport) -> Int32 {
  self.errors
}

///|
pub fn AcquisitionReport::uncovered_paths(
  self : AcquisitionReport,
) -> Array[String] {
  self.uncovered.copy()
}

///|
pub fn AcquisitionReport::unmatched_rule_ids(
  self : AcquisitionReport,
) -> Array[String] {
  self.unmatched.copy()
}

///|
pub fn AcquisitionReport::to_json(self : AcquisitionReport) -> String {
  canonical_json(self.document)
}

///|
pub fn AcquisitionReport::to_json_value(self : AcquisitionReport) -> Json {
  copy_json(self.document)
}

///|
/// Apply all matching filename-scoped rules, account for uncovered scans and
/// unmatched rules, and retain complete snapshot/audit/check evidence.
pub fn DatasetIndex::check_acquisition(
  self : DatasetIndex,
  rules : AcquisitionRules,
) -> AcquisitionReport {
  let audit = self.audit_all()
  let coverage : Map[String, Array[String]] = Map([])
  for path in self.data_paths() {
    coverage[path] = []
  }
  let unmatched : Array[String] = []
  let mut violations = 0
  let reports = rules.rules.map(rule => {
    let paths = self.select_scans(rule.query).paths()
    let chosen : Map[String, Bool] = Map([])
    for path in paths {
      chosen[path] = true
      coverage[path].push(rule.id)
    }
    if paths.is_empty() {
      unmatched.push(rule.id)
    }
    let selected : AuditReport = {
      entries: audit.entries.filter(entry => chosen.contains(entry.path)),
    }
    let checked = selected.check_expectations(rule.expected)
    violations += checked.violation_count()
    Json::object({
      "id": Json::string(rule.id),
      "matched_paths": Json::array(paths.map(Json::string)),
      "report": checked.to_json_value(),
    })
  })
  let paths = self.data_paths()
  let uncovered = paths.filter(path => coverage[path].is_empty())
  let errors = audit.error_count()
  let outcome : ExpectationDecision = if paths.is_empty() ||
    !uncovered.is_empty() ||
    !unmatched.is_empty() ||
    errors > 0 {
    Indeterminate
  } else if violations > 0 {
    Violations
  } else {
    Pass
  }
  let decision = match outcome {
    Pass => "pass"
    Violations => "violations"
    Indeterminate => "indeterminate"
  }
  {
    outcome,
    violations,
    errors,
    uncovered,
    unmatched,
    document: Json::object({
      "decision": Json::string(decision),
      "empty_inventory": Json::boolean(paths.is_empty()),
      "violation_count": Json::number(violations.to_double()),
      "error_count": Json::number(errors.to_double()),
      "uncovered_paths": Json::array(uncovered.map(Json::string)),
      "unmatched_rule_ids": Json::array(unmatched.map(Json::string)),
      "coverage": Json::array(
        paths.map(path => {
          Json::object({
            "data_path": Json::string(path),
            "rule_ids": Json::array(coverage[path].map(Json::string)),
          })
        }),
      ),
      "rule_set": rules.rules_value(),
      "rule_reports": Json::array(reports),
      "audit": audit.report_value(),
      "manifest": self.manifest_value(),
    }),
  }
}
