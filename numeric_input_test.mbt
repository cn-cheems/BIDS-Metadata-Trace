///|
fn number_rule_error(text : String) -> String {
  try {
    ignore(@trace.NumericRules::from_json(text))
    "accepted"
  } catch {
    @trace.TraceError(d) => d.code
  }
}

///|
test "numeric controls reject malformed unsupported and contradictory instructions" {
  for
    (text, code) in [
      ("[]", "invalid_numeric_rules"),
      ("{}", "invalid_numeric_rules"),
      (
        "{\"fields\":{},\"relations\":[],\"unknown\":1}", "invalid_numeric_rules",
      ),
      ("{\"fields\":{},\"relations\":[]}", "numeric_rules_limit"),
      ("{\"fields\":null,\"relations\":[]}", "invalid_numeric_rules"),
      ("{\"fields\":{\"x\":{}},\"relations\":[]}", "invalid_numeric_type"),
      (
        "{\"fields\":{\"x\":{\"type\":\"integer\"}},\"relations\":[]}", "invalid_numeric_type",
      ),
      ("{\"fields\":{\"x\":null},\"relations\":[]}", "invalid_numeric_field"),
      (
        "{\"fields\":{\"x\":{\"type\":\"number\",\"gte\":null}},\"relations\":[]}",
        "invalid_numeric_bound",
      ),
      (
        "{\"fields\":{\"x\":{\"type\":\"number\",\"gt\":\"0\"}},\"relations\":[]}",
        "invalid_numeric_bound",
      ),
      (
        "{\"fields\":{\"x\":{\"type\":\"number\",\"gt\":0,\"gte\":0}},\"relations\":[]}",
        "conflicting_numeric_bounds",
      ),
      (
        "{\"fields\":{\"x\":{\"type\":\"number\",\"lt\":1,\"lte\":2}},\"relations\":[]}",
        "conflicting_numeric_bounds",
      ),
      (
        "{\"fields\":{\"x\":{\"type\":\"number\",\"gte\":1,\"lte\":0}},\"relations\":[]}",
        "empty_numeric_interval",
      ),
      (
        "{\"fields\":{\"x\":{\"type\":\"number\",\"gt\":1,\"lte\":1.0}},\"relations\":[]}",
        "empty_numeric_interval",
      ),
      (
        "{\"fields\":{\"x\":{\"type\":\"number\",\"gte\":-0,\"lt\":0}},\"relations\":[]}",
        "empty_numeric_interval",
      ),
      (
        "{\"fields\":{\"x\":{\"type\":\"number\",\"min_items\":1}},\"relations\":[]}",
        "invalid_numeric_field",
      ),
      (
        "{\"fields\":{\"x\":{\"type\":\"array\",\"min_items\":2,\"max_items\":1}},\"relations\":[]}",
        "empty_numeric_item_range",
      ),
      (
        "{\"fields\":{\"x\":{\"type\":\"array\",\"strictly_increasing\":null}},\"relations\":[]}",
        "invalid_numeric_field",
      ),
      (
        "{\"fields\":{\"x\":{\"type\":\"number\",\"multiple_of\":2}},\"relations\":[]}",
        "unknown_numeric_field_control",
      ),
      (
        "{\"fields\":{\"x\":{\"type\":\"number\",\"type\":\"array\"}},\"relations\":[]}",
        "duplicate_json_key",
      ),
      (
        "{\"fields\":{\"x\":{\"type\":\"number\"}},\"relations\":[{}]}", "invalid_numeric_relation",
      ),
      (
        "{\"fields\":{\"x\":{\"type\":\"number\"}},\"relations\":[{\"left\":\"x\",\"op\":\"ne\",\"right\":\"x\"}]}",
        "invalid_numeric_relation",
      ),
      (
        "{\"fields\":{\"x\":{\"type\":\"number\"}},\"relations\":[{\"left\":\"x\",\"op\":\"eq\",\"right\":\"missing\"}]}",
        "invalid_numeric_operand",
      ),
      (
        "{\"fields\":{\"x\":{\"type\":\"array\"}},\"relations\":[{\"left\":\"x\",\"op\":\"eq\",\"right\":\"x\"}]}",
        "invalid_numeric_operand",
      ),
    ] {
    assert_eq(number_rule_error(text), code)
  }
  // A failed parse must not poison later configuration construction.
  assert_eq(
    number_rule_error(
      "{\"fields\":{\"x\":{\"type\":\"number\",\"gte\":2,\"lte\":2e0}},\"relations\":[]}",
    ),
    "accepted",
  )
}

///|
test "numeric item count controls have explicit integer spelling and upper bounds" {
  for
    token in [
      "-1", "-0", "1.0", "1e0", "2097153", "99999999999999999999999", "null", "\"1\"",
    ] {
    assert_eq(
      number_rule_error(
        "{\"fields\":{\"x\":{\"type\":\"array\",\"min_items\":" +
        token +
        "}},\"relations\":[]}",
      ),
      "invalid_numeric_item_count",
    )
  }
  for token in ["0", "1", "2097152"] {
    assert_eq(
      number_rule_error(
        "{\"fields\":{\"x\":{\"type\":\"array\",\"max_items\":" +
        token +
        "}},\"relations\":[]}",
      ),
      "accepted",
    )
  }
}

///|
test "numeric rules canonical round trips preserve controls exact bounds and relation ordering" {
  let a = number_rules(
    "{\"relations\":[{\"right\":\"b\",\"op\":\"lt\",\"left\":\"a\"},{\"left\":\"b\",\"op\":\"gte\",\"right\":\"a\"}],\"fields\":{\"b\":{\"type\":\"number\",\"gt\":-0},\"a\":{\"lte\":1e999,\"gte\":9007199254740993,\"type\":\"number\"}}}",
  )
  let b = number_rules(
    "{\"fields\":{\"a\":{\"type\":\"number\",\"gte\":9007199254740993,\"lte\":1e999},\"b\":{\"gt\":-0,\"type\":\"number\"}},\"relations\":[{\"left\":\"b\",\"op\":\"gte\",\"right\":\"a\"},{\"left\":\"a\",\"op\":\"lt\",\"right\":\"b\"}]}",
  )
  assert_eq(a.to_json(), b.to_json())
  assert_eq(number_rules(a.to_json()).to_json(), a.to_json())
  assert_true(a.to_json().contains("9007199254740993"))
  assert_true(a.to_json().contains("1e999"))
  assert_true(a.to_json().contains("-0"))
  let duplicate = "{\"fields\":{\"x\":{\"type\":\"number\"}},\"relations\":[{\"left\":\"x\",\"op\":\"eq\",\"right\":\"x\"},{\"right\":\"x\",\"op\":\"eq\",\"left\":\"x\"}]}"
  assert_eq(number_rule_error(duplicate), "duplicate_numeric_relation")
}

///|
test "numeric field and relation limits are checked at 256 and 257" {
  for count in [256, 257] {
    let fields = Array::makei(count, i => {
      "\"x" + i.to_string() + "\":{\"type\":\"number\"}"
    })
    let code = number_rule_error(
      "{\"fields\":{" + fields.join(",") + "},\"relations\":[]}",
    )
    assert_eq(
      code,
      if count == 256 {
        "accepted"
      } else {
        "field_request_limit"
      },
    )
    let operands = Array::makei(17, i => {
      "\"x" + i.to_string() + "\":{\"type\":\"number\"}"
    })
    let relations = Array::makei(count, i => {
      "{\"left\":\"x" +
      (i / 17).to_string() +
      "\",\"op\":\"lte\",\"right\":\"x" +
      (i % 17).to_string() +
      "\"}"
    })
    assert_eq(
      number_rule_error(
        "{\"fields\":{" +
        operands.join(",") +
        "},\"relations\":[" +
        relations.join(",") +
        "]}",
      ),
      if count == 256 {
        "accepted"
      } else {
        "numeric_rules_limit"
      },
    )
  }
}

///|
test "numeric and legacy controls share a 256-field budget in both composition APIs" {
  let fields = Array::makei(256, i => {
    "\"n" + i.to_string() + "\":{\"type\":\"number\"}"
  })
  let numeric = number_rules(
    "{\"fields\":{" + fields.join(",") + "},\"relations\":[]}",
  )
  let allowed = @trace.MetadataExpectations::from_json(
    "{\"required\":[\"n0\"],\"allowed\":{}}",
  )
  ignore(allowed.with_numeric(numeric))
  let excessive = @trace.MetadataExpectations::from_json(
    "{\"required\":[\"extra\"],\"allowed\":{}}",
  )
  try excessive.with_numeric(numeric) catch {
    @trace.TraceError(d) => assert_eq(d.code, "field_request_limit")
  } noraise {
    _ => fail("Expected combined field limit")
  }
  let query = @trace.MetadataQuery::from_json(
    "{\"present\":[\"n0\"],\"absent\":[],\"equals\":{}}",
  )
  ignore(query.with_numeric(numeric))
  let over_query = @trace.MetadataQuery::from_json(
    "{\"present\":[\"extra\"],\"absent\":[],\"equals\":{}}",
  )
  try over_query.with_numeric(numeric) catch {
    @trace.TraceError(d) => assert_eq(d.code, "field_request_limit")
  } noraise {
    _ => fail("Expected combined query field limit")
  }
  assert_eq(excessive.to_json(), "{\"allowed\":{},\"required\":[\"extra\"]}")
}

///|
test "numeric config size limits reject instead of dropping rules and recover" {
  let text = "{\"fields\":{\"" +
    "x".repeat(2097152) +
    "\":{\"type\":\"number\"}},\"relations\":[]}"
  assert_eq(number_rule_error(text), "input_limit")
  let numeric = number_rules(
    "{\"fields\":{\"n\":{\"type\":\"number\"}},\"relations\":[]}",
  )
  let value = "{\"payload\":\"" + "x".repeat(2097050) + "\"}"
  let original = @trace.MetadataExpectations::from_json(
    "{\"required\":[],\"allowed\":{\"opaque\":[" + value + "]}}",
  )
  try original.with_numeric(numeric) catch {
    @trace.TraceError(d) => assert_eq(d.code, "input_limit")
  } noraise {
    _ => fail("Expected complete augmented document size rejection")
  }
  assert_false(original.to_json().contains("\"numeric\""))
  ignore(number_policy(numeric))
}
