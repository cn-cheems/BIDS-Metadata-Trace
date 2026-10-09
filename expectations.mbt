///|
/// Project-specific whole-field expectations over effective inherited metadata.
/// This is not a BIDS schema, unit validator or numeric tolerance engine.
pub struct MetadataExpectations {
  priv required : Array[String]
  priv allowed : Map[String, Array[Json]]
  priv fields : Array[String]
}

///|
fn MetadataExpectations::expectations_value(
  self : MetadataExpectations,
) -> Json {
  let allowed : Map[String, Json] = Map([])
  for field in self.fields {
    if self.allowed.get(field) is Some(values) {
      allowed[field] = Json::array(values)
    }
  }
  Json::object({
    "required": Json::array(self.required.map(Json::string)),
    "allowed": Json::object(allowed),
  })
}

///|
pub fn MetadataExpectations::to_json(self : MetadataExpectations) -> String {
  canonical_json(self.expectations_value())
}

///|
/// Strict {required:[fields],allowed:{field:[exact JSON choices]}}.
/// Allowed-only fields may be absent; explicit null is a present value.
pub fn MetadataExpectations::from_json(
  text : String,
) -> MetadataExpectations raise TraceError {
  guard parse_source("<expectations>", text, container_limit=67)
    is Object(input) else {
    reject(
      "invalid_expectations", "<expectations>", "Expected required and allowed controls.",
    )
    abort("reject raises")
  }
  for key in sorted_keys(input) {
    if !["required", "allowed"].contains(key) {
      reject(
        "unknown_expectation_field", key, "Use only required and allowed controls.",
      )
    }
  }
  guard input.get("required") is Some(Array(values)) &&
    input.get("allowed") is Some(Object(choices)) else {
    reject(
      "invalid_expectations", "<expectations>", "Both required array and allowed object are mandatory.",
    )
    abort("reject raises")
  }
  let required = values.map(value => {
    guard value is String(field) else {
      reject(
        "invalid_expectations", "<expectations>/required", "Required entries must be field names.",
      )
      abort("reject raises")
    }
    field
  })
  ignore(review_fields(required))
  required.sort_by(lexical_compare)
  let all : Map[String, Bool] = Map([])
  for field in required {
    all[field] = true
  }
  let allowed : Map[String, Array[Json]] = Map([])
  for field in sorted_keys(choices) {
    all[field] = true
    guard choices[field] is Array(items) &&
      !items.is_empty() &&
      items.length() <= 256 else {
      reject(
        "invalid_allowed_values", field, "Allowed values must be a nonempty array with at most 256 exact choices.",
      )
      abort("reject raises")
    }
    let tokens : Map[String, Json] = Map([])
    for item in items {
      let token = canonical_json(item)
      if tokens.contains(token) {
        reject(
          "duplicate_allowed_value", field, "Allowed value occurs more than once; remove the duplicate choice.",
        )
      }
      tokens[token] = item
    }
    allowed[field] = sorted_keys(tokens).map(token => tokens[token])
  }
  let fields = review_fields(sorted_keys(all))
  let expectations : MetadataExpectations = { required, allowed, fields, }
  if expectations.to_json().length() > 2097152 {
    reject(
      "input_limit", "<expectations>", "Canonical expectations exceed 2,097,152 UTF-16 units; reduce the review scope.",
    )
  }
  expectations
}

///|
pub(all) enum ExpectationDecision {
  Pass
  Violations
  Indeterminate
} derive(Eq)

///|
pub extend ExpectationDecision with Eq::{equal, not_equal}

///|
pub struct ExpectationReport {
  priv outcome : ExpectationDecision
  priv violations : Int
  priv errors : Int
  priv document : Json
}

///|
pub fn ExpectationReport::decision(
  self : ExpectationReport,
) -> ExpectationDecision {
  self.outcome
}

///|
/// Counts failed field checks, including repeated query occurrences.
pub fn ExpectationReport::violation_count(self : ExpectationReport) -> Int {
  self.violations
}

///|
pub fn ExpectationReport::error_count(self : ExpectationReport) -> Int {
  self.errors
}

///|
pub fn ExpectationReport::to_json(self : ExpectationReport) -> String {
  canonical_json(self.document)
}

///|
pub fn ExpectationReport::to_json_value(self : ExpectationReport) -> Json {
  copy_json(self.document)
}

///|
/// Errors take priority. An empty audit is indeterminate, never vacuous approval.
/// Every requested occurrence retains complete effective/source/error evidence.
pub fn AuditReport::check_expectations(
  self : AuditReport,
  expectations : MetadataExpectations,
) -> ExpectationReport {
  let mut violations = 0
  let mut errors = 0
  let entries = self.entries.mapi((i, entry) => {
    let document : Map[String, Json] = {
      "query_index": Json::number(i.to_double()),
      "data_path": Json::string(entry.path),
    }
    match (entry.result, entry.error) {
      (None, Some(error)) => {
        errors += 1
        document["status"] = Json::string("error")
        document["diagnostic"] = error.to_json()
      }
      (Some(result), None) => {
        let checks = expectations.fields.map(field => {
          let required = expectations.required.contains(field)
          let choices = expectations.allowed.get(field)
          let actual = result.values.get(field)
          let check : Map[String, Json] = {
            "field": Json::string(field),
            "required": Json::boolean(required),
            "present": Json::boolean(actual is Some(_)),
            "allowed": match choices {
              Some(values) => Json::array(values)
              None => Json::null()
            },
          }
          let status = match actual {
            None =>
              if required {
                "missing_required"
              } else {
                "absent_optional"
              }
            Some(value) => {
              check["actual"] = value
              let history = result.origins[field]
              check["trace"] = history_value(history)
              check["winning_source"] = Json::string(
                history[history.length() - 1].path,
              )
              match choices {
                Some(values) =>
                  if values.any(v => canonical_json(v) == canonical_json(value)) {
                    "pass"
                  } else {
                    "unexpected_value"
                  }
                None => "pass"
              }
            }
          }
          if status == "missing_required" || status == "unexpected_value" {
            violations += 1
          }
          check["status"] = Json::string(status)
          Json::object(check)
        })
        document["status"] = Json::string("resolved")
        document["result"] = result.report_value()
        document["checks"] = Json::array(checks)
      }
      _ => abort("AuditEntry invariant")
    }
    Json::object(document)
  })
  let outcome : ExpectationDecision = if errors > 0 || entries.is_empty() {
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
    document: Json::object({
      "decision": Json::string(decision),
      "empty_audit": Json::boolean(entries.is_empty()),
      "violation_count": Json::number(violations.to_double()),
      "error_count": Json::number(errors.to_double()),
      "expectations": expectations.expectations_value(),
      "entries": Json::array(entries),
    }),
  }
}
