///|
priv struct NumericBound {
  value : ExactDecimal
  inclusive : Bool
}

///|
priv struct NumericFieldRule {
  field : String
  array : Bool
  lower : NumericBound?
  upper : NumericBound?
  minimum_items : Int32
  maximum_items : Int32?
  increasing : Bool
  document : Map[String, Json]
}

///|
priv struct NumericRelation {
  left : String
  op : String
  right : String
}

///|
/// Project policy over inherited top-level numeric fields, with exact decimal
/// comparisons. This is not a JSON Schema implementation or unit converter.
pub struct NumericRules {
  priv fields : Array[NumericFieldRule]
  priv relations : Array[NumericRelation]
}

///|
fn NumericRules::rules_value(self : NumericRules) -> Json {
  let fields : Map[String, Json] = Map([])
  for rule in self.fields {
    fields[rule.field] = Json::object(rule.document)
  }
  Json::object({
    "fields": Json::object(fields),
    "relations": Json::array(
      self.relations.map(r => {
        Json::object({
          "left": Json::string(r.left),
          "op": Json::string(r.op),
          "right": Json::string(r.right),
        })
      }),
    ),
  })
}

///|
pub fn NumericRules::to_json(self : NumericRules) -> String {
  canonical_json(self.rules_value())
}

///|
fn numeric_bound(
  input : Map[String, Json],
  exclusive : String,
  inclusive : String,
  field : String,
) -> NumericBound? raise TraceError {
  if input.contains(exclusive) && input.contains(inclusive) {
    reject(
      "conflicting_numeric_bounds",
      field,
      "Use only one of " + exclusive + " and " + inclusive + ".",
    )
  }
  let control = if input.contains(exclusive) { exclusive } else { inclusive }
  match input.get(control) {
    None => None
    Some(Number(_, ..) as n) =>
      Some({
        value: exact_decimal(canonical_json(n)),
        inclusive: control == inclusive,
      })
    Some(_) => {
      reject(
        "invalid_numeric_bound",
        field,
        control +
        " must be a JSON number; strings and null are not numeric bounds.",
      )
      None
    }
  }
}

///|
fn numeric_item_count(
  input : Map[String, Json],
  key : String,
  field : String,
) -> Int32? raise TraceError {
  match input.get(key) {
    None => None
    Some(Number(_, ..) as n) => {
      // Configuration counts deliberately use plain decimal integer spelling.
      let text = canonical_json(n)
      if text.length() > 7 || !text.iter().all(c => c >= '0' && c <= '9') {
        reject(
          "invalid_numeric_item_count",
          field,
          key + " must be a plain nonnegative integer at most 2,097,152.",
        )
      }
      let mut value = 0
      for c in text.iter() {
        value = value * 10 + c.to_int() - 48
      }
      if value > 2097152 {
        reject(
          "invalid_numeric_item_count",
          field,
          key + " must be at most 2,097,152.",
        )
      }
      Some(value)
    }
    Some(_) => {
      reject(
        "invalid_numeric_item_count",
        field,
        key + " must be a plain nonnegative integer.",
      )
      None
    }
  }
}

///|
fn numeric_field_rule(
  field : String,
  value : Json,
) -> NumericFieldRule raise TraceError {
  guard value is Object(input) else {
    reject(
      "invalid_numeric_field", field, "Expected an object declaring type number or array.",
    )
    abort("reject raises")
  }
  for key in sorted_keys(input) {
    if ![
        "type", "gt", "gte", "lt", "lte", "min_items", "max_items", "strictly_increasing",
      ].contains(key) {
      reject(
        "unknown_numeric_field_control",
        field,
        "Unsupported numeric control " + key + "; no rule was produced.",
      )
    }
  }
  let array = match input.get("type") {
    Some(String("number")) => false
    Some(String("array")) => true
    _ => {
      reject(
        "invalid_numeric_type", field, "type must be number or array; no coercion is performed.",
      )
      false
    }
  }
  if !array &&
    ["min_items", "max_items", "strictly_increasing"].any(key => {
      input.contains(key)
    }) {
    reject("invalid_numeric_field", field, "Array controls require type array.")
  }
  let lower = numeric_bound(input, "gt", "gte", field)
  let upper = numeric_bound(input, "lt", "lte", field)
  if lower is Some(a) && upper is Some(b) {
    let c = a.value.compare(b.value)
    if c > 0 || (c == 0 && (!a.inclusive || !b.inclusive)) {
      reject(
        "empty_numeric_interval", field, "Lower and upper bounds define an empty interval; correct the bounds.",
      )
    }
  }
  let minimum_items = numeric_item_count(input, "min_items", field).unwrap_or(0)
  let maximum_items = numeric_item_count(input, "max_items", field)
  if maximum_items is Some(maximum) && minimum_items > maximum {
    reject(
      "empty_numeric_item_range", field, "min_items must not exceed max_items.",
    )
  }
  let increasing = match input.get("strictly_increasing") {
    None | Some(False) => false
    Some(True) => true
    _ => {
      reject(
        "invalid_numeric_field", field, "strictly_increasing must be a boolean.",
      )
      false
    }
  }
  {
    field,
    array,
    lower,
    upper,
    minimum_items,
    maximum_items,
    increasing,
    document: input,
  }
}

///|
/// Strict {fields:{name:{type,...}},relations:[{left,op,right}]}.
/// Every declared field is required. Relations reference declared scalar fields.
pub fn NumericRules::from_json(text : String) -> NumericRules raise TraceError {
  guard parse_source("<numeric-rules>", text) is Object(input) else {
    reject(
      "invalid_numeric_rules", "<numeric-rules>", "Expected fields and relations controls.",
    )
    abort("reject raises")
  }
  if sorted_keys(input) != ["fields", "relations"] {
    reject(
      "invalid_numeric_rules", "<numeric-rules>", "Exactly fields and relations are required; unknown controls are rejected.",
    )
  }
  guard input.get("fields") is Some(Object(fields)) &&
    input.get("relations") is Some(Array(relations)) else {
    reject(
      "invalid_numeric_rules", "<numeric-rules>", "fields must be an object and relations an array.",
    )
    abort("reject raises")
  }
  let names = review_fields(sorted_keys(fields))
  if names.is_empty() || relations.length() > 256 {
    reject(
      "numeric_rules_limit", "<numeric-rules>", "Declare 1–256 fields and at most 256 relations.",
    )
  }
  let rules = names.map(name => numeric_field_rule(name, fields[name]))
  let seen : Map[String, Bool] = Map([])
  let parsed = relations.map(value => {
    guard value is Object(r) &&
      sorted_keys(r) == ["left", "op", "right"] &&
      r.get("left") is Some(String(left)) &&
      r.get("op") is Some(String(op)) &&
      r.get("right") is Some(String(right)) else {
      reject(
        "invalid_numeric_relation", "<numeric-rules>/relations", "Each relation requires exactly string left, op and right.",
      )
      abort("reject raises")
    }
    if !["lt", "lte", "eq", "gte", "gt"].contains(op) {
      reject(
        "invalid_numeric_relation", left, "op must be lt, lte, eq, gte or gt.",
      )
    }
    for field in [left, right] {
      if !rules.any(rule => rule.field == field && !rule.array) {
        reject(
          "invalid_numeric_operand", field, "Relations require explicitly declared number fields; arrays and missing declarations are unsupported.",
        )
      }
    }
    let token = canonical_json(value)
    if seen.contains(token) {
      reject(
        "duplicate_numeric_relation", left, "This relation is declared more than once.",
      )
    }
    seen[token] = true
    { left, op, right, }
  })
  parsed.sort_by((a, b) => {
    let left = lexical_compare(a.left, b.left)
    if left != 0 {
      left
    } else {
      let op = lexical_compare(a.op, b.op)
      if op != 0 {
        op
      } else {
        lexical_compare(a.right, b.right)
      }
    }
  })
  let result : NumericRules = { fields: rules, relations: parsed, }
  if result.to_json().length() > 2097152 {
    reject(
      "input_limit", "<numeric-rules>", "Canonical numeric rules exceed 2,097,152 UTF-16 units.",
    )
  }
  result
}
