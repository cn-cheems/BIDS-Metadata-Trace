///|
// Private comparison representation. No exponent is converted to a machine
// integer and no 10^exponent coefficient is ever materialized.
priv struct DecimalOrder {
  negative : Bool
  digits : String
}

///|
priv struct ExactDecimal {
  sign : Int32
  significant : String
  order : DecimalOrder
}

///|
fn decimal_trim(digits : String) -> String {
  let mut start = 0
  while start + 1 < digits.length() && digits[start] == '0' {
    start += 1
  }
  digits[start:].to_owned()
}

///|
fn decimal_unsigned_compare(a : String, b : String) -> Int32 {
  if a.length() != b.length() {
    if a.length() < b.length() {
      -1
    } else {
      1
    }
  } else {
    let c = lexical_compare(a, b)
    if c < 0 {
      -1
    } else if c > 0 {
      1
    } else {
      0
    }
  }
}

///|
fn decimal_unsigned_add(a : String, b : String) -> String {
  let out = StringBuilder()
  let mut i = a.length() - 1
  let mut j = b.length() - 1
  let mut carry = 0
  while i >= 0 || j >= 0 || carry != 0 {
    let x = if i >= 0 { a[i].to_int() - 48 } else { 0 }
    let y = if j >= 0 { b[j].to_int() - 48 } else { 0 }
    let n = x + y + carry
    out.write_string((n % 10).to_string())
    carry = n / 10
    i -= 1
    j -= 1
  }
  out.to_string().rev()
}

///|
// Requires a >= b. Result is normalized and always nonnegative.
fn decimal_unsigned_subtract(a : String, b : String) -> String {
  let out = StringBuilder()
  let mut j = b.length() - 1
  let mut borrow = 0
  for i = a.length() - 1; i >= 0; i = i - 1 {
    let y = if j >= 0 { b[j].to_int() - 48 } else { 0 }
    let n = a[i].to_int() - 48 - y - borrow
    out.write_string((if n < 0 { n + 10 } else { n }).to_string())
    borrow = if n < 0 { 1 } else { 0 }
    j -= 1
  }
  decimal_trim(out.to_string().rev())
}

///|
fn DecimalOrder::shift(self : DecimalOrder, offset : Int32) -> DecimalOrder {
  if offset == 0 {
    return self
  }
  // offset is bounded by the source's UTF-16 length, never arbitrary input int.
  let negative = offset < 0
  let amount = (if negative { -offset } else { offset }).to_string()
  if self.negative == negative {
    { negative, digits: decimal_unsigned_add(self.digits, amount), }
  } else {
    let c = decimal_unsigned_compare(self.digits, amount)
    if c == 0 {
      { negative: false, digits: "0", }
    } else if c > 0 {
      {
        negative: self.negative,
        digits: decimal_unsigned_subtract(self.digits, amount),
      }
    } else {
      { negative, digits: decimal_unsigned_subtract(amount, self.digits), }
    }
  }
}

///|
fn DecimalOrder::compare(self : DecimalOrder, other : DecimalOrder) -> Int32 {
  if self.negative != other.negative {
    if self.negative {
      -1
    } else {
      1
    }
  } else {
    let c = decimal_unsigned_compare(self.digits, other.digits)
    if self.negative {
      -c
    } else {
      c
    }
  }
}

///|
// Only called with JSON-syntax-validated tokens retained by parse_source.
fn exact_decimal(token : String) -> ExactDecimal {
  let negative = token[0] == '-'
  let mut i = if negative { 1 } else { 0 }
  let coefficient = StringBuilder()
  let mut fraction = false
  let mut fractional_digits = 0
  while i < token.length() && token[i] != 'e' && token[i] != 'E' {
    if token[i] == '.' {
      fraction = true
    } else {
      coefficient.write_string(token[i:i + 1].to_owned())
      if fraction {
        fractional_digits += 1
      }
    }
    i += 1
  }
  let significant = decimal_trim(coefficient.to_string())
  if significant == "0" {
    return { sign: 0, significant, order: { negative: false, digits: "0", }, }
  }
  let mut exponent : DecimalOrder = { negative: false, digits: "0", }
  if i < token.length() {
    i += 1
    let exp_negative = token[i] == '-'
    if token[i] == '+' || token[i] == '-' {
      i += 1
    }
    let digits = decimal_trim(token[i:].to_owned())
    exponent = { negative: exp_negative && digits != "0", digits, }
  }
  {
    sign: if negative {
      -1
    } else {
      1
    },
    significant,
    order: exponent.shift(significant.length() - fractional_digits),
  }
}

///|
fn ExactDecimal::compare(self : ExactDecimal, other : ExactDecimal) -> Int32 {
  if self.sign != other.sign {
    return if self.sign < other.sign { -1 } else { 1 }
  }
  if self.sign == 0 {
    return 0
  }
  let order = self.order.compare(other.order)
  if order != 0 {
    return order * self.sign
  }
  let limit = if self.significant.length() > other.significant.length() {
    self.significant.length()
  } else {
    other.significant.length()
  }
  for i in 0..<limit {
    let a = if i < self.significant.length() {
      self.significant[i].to_int()
    } else {
      48
    }
    let b = if i < other.significant.length() {
      other.significant[i].to_int()
    } else {
      48
    }
    if a != b {
      return (if a < b { -1 } else { 1 }) * self.sign
    }
  }
  0
}
