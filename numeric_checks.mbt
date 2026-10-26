///|
fn numeric_value(value : Json?) -> ExactDecimal? {
  match value {
    Some(Number(_, ..) as n) => Some(exact_decimal(canonical_json(n)))
    _ => None
  }
}

///|
fn NumericFieldRule::scalar_status(
  self : NumericFieldRule,
  number : ExactDecimal,
) -> String {
  if self.lower is Some(bound) {
    let c = number.compare(bound.value)
    if c < 0 || (c == 0 && !bound.inclusive) {
      return "below_minimum"
    }
  }
  if self.upper is Some(bound) {
    let c = number.compare(bound.value)
    if c > 0 || (c == 0 && !bound.inclusive) {
      return "above_maximum"
    }
  }
  "pass"
}

///|
// One bounded outcome per field: the first failed condition plus complete
// original value/history. No array element is removed or coerced.
fn NumericFieldRule::check(
  self : NumericFieldRule,
  value : Json?,
) -> (String, Int32?) {
  guard value is Some(value) else { return ("missing_numeric_field", None) }
  if !self.array {
    return match numeric_value(Some(value)) {
      Some(number) => (self.scalar_status(number), None)
      None => ("not_number", None)
    }
  }
  guard value is Array(items) else { return ("not_array", None) }
  if items.length() < self.minimum_items {
    return ("too_few_items", None)
  }
  if self.maximum_items is Some(maximum) && items.length() > maximum {
    return ("too_many_items", None)
  }
  let mut previous : ExactDecimal? = None
  for i, item in items {
    guard numeric_value(Some(item)) is Some(number) else {
      return ("not_number", Some(i))
    }
    let status = self.scalar_status(number)
    if status != "pass" {
      return (status, Some(i))
    }
    if self.increasing &&
      previous is Some(before) &&
      before.compare(number) >= 0 {
      return ("not_strictly_increasing", Some(i))
    }
    previous = Some(number)
  }
  ("pass", None)
}

///|
fn numeric_evidence(result : ResolvedMetadata, field : String) -> Json {
  let value = result.values.get(field)
  let doc : Map[String, Json] = {
    "field": Json::string(field),
    "present": Json::boolean(value is Some(_)),
  }
  if value is Some(value) {
    doc["actual"] = value
    let history = result.origins[field]
    doc["trace"] = history_value(history)
    doc["winning_source"] = Json::string(history[history.length() - 1].path)
  }
  Json::object(doc)
}

///|
fn numeric_relation_matches(order : Int32, op : String) -> Bool {
  match op {
    "lt" => order < 0
    "lte" => order <= 0
    "eq" => order == 0
    "gte" => order >= 0
    "gt" => order > 0
    _ => abort("validated numeric operator")
  }
}

///|
fn NumericRules::evaluate(
  self : NumericRules,
  result : ResolvedMetadata,
) -> (Array[Json], Int32) {
  let checks : Array[Json] = []
  let mut violations = 0
  for rule in self.fields {
    let (status, item_index) = rule.check(result.values.get(rule.field))
    if status != "pass" {
      violations += 1
    }
    checks.push(
      Json::object({
        "kind": Json::string("field"),
        "status": Json::string(status),
        "field": Json::string(rule.field),
        "rule": Json::object(rule.document),
        "evidence": numeric_evidence(result, rule.field),
        "item_index": item_index
        .map(i => Json::number(i.to_double()))
        .unwrap_or(Json::null()),
      }),
    )
  }
  for relation in self.relations {
    let left = result.values.get(relation.left)
    let right = result.values.get(relation.right)
    let status = match (numeric_value(left), numeric_value(right)) {
      (Some(a), Some(b)) =>
        if numeric_relation_matches(a.compare(b), relation.op) {
          "pass"
        } else {
          "relation_failed"
        }
      _ => "invalid_operands"
    }
    if status != "pass" {
      violations += 1
    }
    checks.push(
      Json::object({
        "kind": Json::string("relation"),
        "status": Json::string(status),
        "op": Json::string(relation.op),
        "left": numeric_evidence(result, relation.left),
        "right": numeric_evidence(result, relation.right),
      }),
    )
  }
  (checks, violations)
}
