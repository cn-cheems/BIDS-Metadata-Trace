///|
test "exact decimal comparison retains mathematical ordering without float or exponent overflow" {
  for
    (a, b, expected) in [
      ("2", "2.0", 0),
      ("2e0", "200e-2", 0),
      ("1200", "1.200e3", 0),
      ("-0", "0.000e-9999999999999999999999", 0),
      ("0e999999999999999999999999", "-0.0e+999999999999999999999", 0),
      ("9007199254740993", "9007199254740992", 1),
      ("-9007199254740993", "-9007199254740992", -1),
      ("1e999", "9e998", 1),
      ("1e-999", "9e-1000", 1),
      ("1e9999999999999999999999", "10e9999999999999999999998", 0),
      ("1e-9999999999999999999999", "10e-10000000000000000000000", 0),
      ("1e-1", "0.1", 0),
      ("0.0012", "12e-4", 0),
      ("0.00000000000000000000000000001", "1e-29", 0),
      ("1.000000000000000000000000001", "1", 1),
      ("-1.000000000000000000000000001", "-1", -1),
      ("1e+0000000000000000", "0.1e1", 0),
      ("1.23", "1.23000000000000000001", -1),
      ("-2", "0", -1),
      ("0", "2e-9999999999999999999999", -1),
    ] {
    // Ensure every independently authored vector is valid JSON first.
    ignore(parse_source("<decimal-vector>", a))
    ignore(parse_source("<decimal-vector>", b))
    assert_eq(exact_decimal(a).compare(exact_decimal(b)), expected)
    assert_eq(exact_decimal(b).compare(exact_decimal(a)), -expected)
  }
}

///|
test "exact decimal scaled-integer oracle covers 82369 ordered pairs" {
  let cases : Array[(ExactDecimal, Int32)] = []
  let powers = [1, 10, 100, 1000, 10000, 100000, 1000000]
  for coefficient in -20..<=20 {
    for exponent in -3..<=3 {
      let token = coefficient.to_string() + ".00e" + exponent.to_string()
      cases.push((exact_decimal(token), coefficient * powers[exponent + 3]))
    }
  }
  for (a, ai) in cases {
    for (b, bi) in cases {
      let expected = if ai < bi { -1 } else if ai > bi { 1 } else { 0 }
      assert_eq(a.compare(b), expected)
    }
  }
}

///|
test "decimal order signed arithmetic handles carry borrow and zero normalization" {
  for
    (magnitude, negative, offset, wanted, wanted_negative) in [
      ("0", false, -1, "1", true),
      ("1", true, 1, "0", false),
      ("999999999999999999999999", false, 1, "1000000000000000000000000", false),
      (
        "1000000000000000000000000", false, -1, "999999999999999999999999", false,
      ),
      ("999999999999999999999999", true, -1, "1000000000000000000000000", true),
      ("1000000000000000000000000", true, 1, "999999999999999999999999", true),
      ("9", true, 10, "1", false),
      ("9", false, -10, "1", true),
      ("2097152", false, -2097152, "0", false),
    ] {
    let input : DecimalOrder = { negative, digits: magnitude, }
    let got = input.shift(offset)
    assert_eq(got.digits, wanted)
    assert_eq(got.negative, wanted_negative)
  }
}

///|
test "decimal comparisons handle long significands and exponents without power expansion" {
  let exponent = "9".repeat(10000)
  let a = exact_decimal("1e" + exponent)
  let b = exact_decimal("10e" + "9".repeat(9999) + "8")
  assert_eq(a.compare(b), 0)
  let tiny = exact_decimal("1e-" + exponent)
  let tinier = exact_decimal("1e-1" + "0".repeat(10000))
  assert_eq(tiny.compare(tinier), 1)
  assert_eq(
    exact_decimal("0." + "0".repeat(10000) + "1").compare(
      exact_decimal("1e-10001"),
    ),
    0,
  )
  assert_eq(
    exact_decimal("1." + "0".repeat(10000) + "1").compare(exact_decimal("1")),
    1,
  )
}
