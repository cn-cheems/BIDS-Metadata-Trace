///|
fn[V] sorted_keys(map : Map[String, V]) -> Array[String] {
  let keys = map.keys().to_array()
  keys.sort_by(lexical_compare)
  keys
}

///|
// String::compare in this toolchain orders by length first. Reports explicitly
// use ordinal UTF-16 lexicographic order, independent of that implementation.
fn lexical_compare(a : String, b : String) -> Int {
  let limit = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<limit {
    if a[i] != b[i] {
      return a[i].to_int() - b[i].to_int()
    }
  }
  a.length() - b.length()
}

///|
// Core Json keeps number lexemes, but Json::equal compares rounded doubles.
// We never use that equality for metadata. Rebuilding also prevents aliases.
fn copy_json(value : Json) -> Json {
  match value {
    Object(fields) => {
      let copy : Map[String, Json] = Map([])
      for key in sorted_keys(fields) {
        copy[key] = copy_json(fields[key])
      }
      Json::object(copy)
    }
    Array(values) => Json::array(values.map(copy_json))
    Number(number, repr~) => Json::number(number, repr?)
    String(text) => Json::string(text)
    True => Json::boolean(true)
    False => Json::boolean(false)
    Null => Json::null()
  }
}

///|
// Json::stringify does not promise object-key order. Sort explicitly here.
fn canonical_json(value : Json) -> String {
  match value {
    Object(fields) =>
      "{" +
      sorted_keys(fields)
      .map(key => {
        Json::string(key).stringify() + ":" + canonical_json(fields[key])
      })
      .join(",") +
      "}"
    Array(values) => "[" + values.map(canonical_json).join(",") + "]"
    _ => value.stringify()
  }
}

///|
priv struct KeyScanner {
  source : String
  path : String
  mut position : Int
}

///|
fn KeyScanner::space(self : KeyScanner) -> Unit {
  while self.position < self.source.length() &&
        (
          self.source[self.position] == ' ' ||
          self.source[self.position] == '\n' ||
          self.source[self.position] == '\r' ||
          self.source[self.position] == '\t'
        ) {
    self.position += 1
  }
}

///|
// Called only after core JSON syntax validation, so boundaries are known valid.
fn KeyScanner::string_end(self : KeyScanner) -> Int {
  self.position += 1
  while self.source[self.position] != '"' {
    if self.source[self.position] == '\\' {
      self.position += 1
    }
    self.position += 1
  }
  self.position += 1
  self.position
}

///|
fn KeyScanner::value(self : KeyScanner) -> Json raise TraceError {
  self.space()
  match self.source[self.position] {
    '"' => {
      let start = self.position
      let end = self.string_end()
      try! @json.parse(self.source[start:end])
    }
    '{' => {
      self.position += 1
      self.space()
      let seen : Map[String, Int] = Map([])
      let fields : Map[String, Json] = Map([])
      if self.source[self.position] != '}' {
        for ;; {
          self.space()
          let start = self.position
          let end = self.string_end()
          let key = match (try! @json.parse(self.source[start:end])) {
            String(key) => key
            _ => abort("validated object key")
          }
          if seen.contains(key) {
            reject(
              "duplicate_json_key",
              self.path,
              "Duplicate object key " +
              Json::string(key).stringify() +
              "; remove or rename it before resolving metadata.",
              offset=start,
            )
          }
          seen[key] = start
          self.space()
          self.position += 1 // colon
          fields[key] = self.value()
          self.space()
          if self.source[self.position] == '}' {
            break
          }
          self.position += 1 // comma
        }
      }
      self.position += 1
      Json::object(fields)
    }
    '[' => {
      self.position += 1
      self.space()
      let values : Array[Json] = []
      if self.source[self.position] != ']' {
        for ;; {
          values.push(self.value())
          self.space()
          if self.source[self.position] == ']' {
            break
          }
          self.position += 1
        }
      }
      self.position += 1
      Json::array(values)
    }
    _ => {
      let start = self.position
      while self.position < self.source.length() &&
            self.source[self.position] != ',' &&
            self.source[self.position] != '}' &&
            self.source[self.position] != ']' &&
            self.source[self.position] != ' ' &&
            self.source[self.position] != '\n' &&
            self.source[self.position] != '\r' &&
            self.source[self.position] != '\t' {
        self.position += 1
      }
      let token = self.source[start:self.position].to_owned()
      match (try! @json.parse(token)) {
        Number(number, ..) => Json::number(number, repr=token)
        value => value
      }
    }
  }
}

///|
fn parse_source(
  path : String,
  text : String,
  container_limit? : Int = 64,
  text_limit? : Int = 2097152,
) -> Json raise TraceError {
  if text.length() > text_limit {
    reject(
      "input_limit",
      path,
      if text_limit == 2097152 {
        "JSON exceeds 2,097,152 UTF-16 code units; split this input."
      } else {
        "JSON exceeds " +
        text_limit.to_string() +
        " UTF-16 code units; split this input."
      },
    )
  }
  // Bound recursion before parsing. Delimiters inside JSON strings do not count.
  let mut depth = 0
  let mut quoted = false
  let mut escaped = false
  for offset = 0; offset < text.length(); offset = offset + 1 {
    let c = text[offset]
    if quoted {
      if escaped {
        escaped = false
      } else if c == '\\' {
        escaped = true
      } else if c == '"' {
        quoted = false
      }
    } else if c == '"' {
      quoted = true
    } else if c == '{' || c == '[' {
      depth += 1
      if depth > container_limit {
        reject(
          "depth_limit",
          path,
          "JSON nesting exceeds " +
          container_limit.to_string() +
          " containers; simplify this source.",
          offset~,
        )
      }
    } else if c == '}' || c == ']' {
      depth -= 1
    }
  }
  try @json.parse(text) |> ignore catch {
    error => reject("invalid_json", path, "Invalid JSON: " + error.to_string())
  }
  let scanner : KeyScanner = { source: text, path, position: 0, }
  scanner.value()
}
