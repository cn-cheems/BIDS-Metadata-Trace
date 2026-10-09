///|
// Independent test reader for quoted RFC 4180 records, including embedded CRLF.
fn read_review_csv(text : String) -> Array[Array[String]] raise {
  let rows : Array[Array[String]] = []
  let mut row : Array[String] = []
  let mut i = 0
  while i < text.length() {
    assert_eq(text[i], '"')
    i += 1
    let mut cell = ""
    while i < text.length() {
      if text[i] == '"' {
        i += 1
        if i < text.length() && text[i] == '"' {
          cell += "\""
          i += 1
        } else {
          break
        }
      } else {
        cell += text[i:i + 1].to_owned()
        i += 1
      }
    }
    row.push(cell)
    if text[i] == ',' {
      i += 1
    } else {
      assert_eq(text[i:i + 2].to_owned(), "\r\n")
      i += 2
      rows.push(row)
      row = []
    }
  }
  rows
}

///|
test "CSV round trip keeps nested values quotes unicode and formula-like strings" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new(
      "task-rest_bold.json", "{\"x\":\"=SUM(1,2)\\r\\n\\\"汉字\\\"\",\"large\":9007199254740993,\"zero\":-0,\"decimal\":2.0,\"nested\":{\"a\":[null,true]}}",
    ),
  ])
  let csv = index
    .audit_all()
    .to_review_csv(["x", "large", "zero", "decimal", "nested"])
  let rows = read_review_csv(csv)
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].length(), 24)
  assert_eq(rows[1].length(), 24)
  assert_eq(rows[1][5], "json:\"=SUM(1,2)\\r\\n\\\"汉字\\\"\"")
  assert_eq(rows[1][9], "json:9007199254740993")
  assert_eq(rows[1][13], "json:-0")
  assert_eq(rows[1][17], "json:2.0")
  assert_eq(rows[1][21], "json:{\"a\":[null,true]}")
  assert_eq(
    csv,
    @trace.DatasetIndex::from_json(index.to_manifest_json())
    .audit_all()
    .to_review_csv(["x", "large", "zero", "decimal", "nested"]),
  )
}

///|
test "CSV preserves duplicate requests missing null errors and recovery" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("task-rest_bold.json", "{\"n\":null}"),
  ])
  let audit = index.audit([scan(), "absent", scan()])
  let rows = read_review_csv(audit.to_review_csv(["n", "missing"]))
  assert_eq(rows.length(), 4)
  assert_eq(rows[1][4], "true")
  assert_eq(rows[1][5], "json:null")
  assert_eq(rows[1][8], "false")
  assert_eq(rows[1][9], "")
  assert_eq(rows[2][2], "error")
  assert_true(rows[2][3].has_prefix("json:{"))
  for cell in rows[2][4:] {
    assert_eq(cell, "")
  }
  assert_eq(rows[3][2], "resolved")
  assert_eq(rows[3][0], "2")
  assert_eq(index.audit_all().error_count(), 0)
}

///|
test "CSV escapes arbitrary requested field names and rejects invalid projections" {
  let index = @trace.DatasetIndex::from_manifest([], [])
  let audit = index.audit_all()
  let rows = read_review_csv(audit.to_review_csv(["=x,\"\r\n", ""]))
  assert_eq(rows[0][4], "present:\"=x,\\\"\\r\\n\"")
  assert_eq(read_review_csv(audit.to_review_csv([]))[0].length(), 4)
  try {
    ignore(audit.to_review_csv(["x", "x"]))
    fail("accepted duplicate")
  } catch {
    @trace.TraceError(d) => assert_eq(d.code, "duplicate_field_request")
    error => fail(error.to_string())
  }
  assert_eq(
    read_review_csv(audit.to_review_csv(Array::makei(256, i => i.to_string())))[0].length(),
    1028,
  )
  try {
    ignore(audit.to_review_csv(Array::makei(257, i => i.to_string())))
    fail("accepted too many")
  } catch {
    @trace.TraceError(d) => assert_eq(d.code, "field_request_limit")
    error => fail(error.to_string())
  }
}

///|
test "CSV retains full shadowed history and bounds expanded evidence without partial output" {
  let index = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new("task-rest_bold.json", "{\"x\":2.0}"),
    @trace.SidecarInput::new(
      "sub-01/func/sub-01_task-rest_run-01_bold.json", "{\"x\":2}",
    ),
  ])
  let row = read_review_csv(index.audit_all().to_review_csv(["x"]))[1]
  assert_eq(row[5], "json:2")
  assert_true(row[7].contains("\"value\":2.0"))
  assert_true(row[7].contains("\"value\":2}"))
  let large = @trace.DatasetIndex::from_manifest([scan()], [
    @trace.SidecarInput::new(
      "task-rest_bold.json",
      "{\"x\":\"" + "a".repeat(1000000) + "\"}",
    ),
  ])
  try {
    ignore(large.audit(Array::make(9, scan())).to_review_csv(["x"]))
    fail("accepted expanded evidence")
  } catch {
    @trace.TraceError(d) => assert_eq(d.code, "review_csv_limit")
    error => fail(error.to_string())
  }
  assert_true(large.audit_all().to_review_csv(["x"]).length() > 2000000)
}
