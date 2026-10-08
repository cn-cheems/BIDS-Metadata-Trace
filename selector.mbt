///|
fn alphanumeric(value : String, plus? : Bool = false) -> Bool {
  !value.is_empty() &&
  value
  .iter()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    (plus && c == '+')
  })
}

///|
fn parts(path : String) -> Array[String] raise TraceError {
  let parts = path.split("/").map(v => v.to_owned()).to_array()
  if parts.any(p => {
      p.is_empty() ||
      p == "." ||
      p == ".." ||
      p.contains("\\") ||
      p.contains(":")
    }) {
    reject(
      "invalid_path", path, "Use a dataset-relative slash-separated path without empty, dot, parent, drive or backslash components.",
    )
  }
  parts
}

///|
fn entity_value(
  key : String,
  value : String,
  path : String,
) -> String raise TraceError {
  match key {
    "run" | "echo" | "chunk" => {
      if value.is_empty() || !value.iter().all(c => c >= '0' && c <= '9') {
        reject(
          "invalid_entity",
          path,
          key + " requires a nonnegative decimal index.",
        )
      }
      let mut start = 0
      while start + 1 < value.length() && value[start] == '0' {
        start += 1
      }
      value[start:].to_owned()
    }
    "sub" | "ses" | "task" | "acq" | "ce" | "rec" | "dir" | "part" => {
      if !alphanumeric(value, plus=true) {
        reject(
          "invalid_entity",
          path,
          key +
          " requires a nonempty ASCII alphanumeric label (plus is permitted).",
        )
      }
      value
    }
    _ => {
      reject(
        "unsupported_entity",
        path,
        "Entity " +
        key +
        " is outside the raw-MRI profile; no metadata result was produced.",
      )
      value
    }
  }
}

///|
fn selector(path : String, sidecar~ : Bool) -> Selector raise TraceError {
  let components = parts(path)
  let filename = components[components.length() - 1]
  let extension = if sidecar {
    ".json"
  } else if filename.has_suffix(".nii.gz") {
    ".nii.gz"
  } else {
    ".nii"
  }
  if !filename.has_suffix(extension) {
    reject(
      "unsupported_extension", path, "Expected JSON sidecar or .nii/.nii.gz data path for this profile.",
    )
  }
  let stem = filename[:filename.length() - extension.length()].to_owned()
  let tokens = stem.split("_").map(v => v.to_owned()).to_array()
  let suffix = tokens[tokens.length() - 1]
  let datatype = match suffix {
    "bold" => "func"
    "T1w" => "anat"
    "dwi" => "dwi"
    _ => {
      reject(
        "unsupported_suffix", path, "Only bold, T1w and dwi are supported; select an explicit supported raw-MRI input.",
      )
      ""
    }
  }
  let entities : Map[String, String] = Map([])
  let order = [
    "sub", "ses", "task", "acq", "ce", "rec", "dir", "run", "echo", "part", "chunk",
  ]
  let mut previous = -1
  for token in tokens[:tokens.length() - 1] {
    let pair = token.split("-").map(v => v.to_owned()).to_array()
    if pair.length() != 2 {
      reject(
        "invalid_entity",
        path,
        "Expected key-label entity, found " + token,
      )
    }
    let key = pair[0]
    let value = entity_value(key, pair[1], path)
    if entities.contains(key) {
      reject("duplicate_entity", path, "Repeated filename entity " + key)
    }
    let rank = order.search(key).unwrap()
    if rank <= previous {
      reject(
        "entity_order", path, "Filename entities must follow the documented raw-MRI order.",
      )
    }
    previous = rank
    entities[key] = value
  }
  let directories = components[:components.length() - 1].to_owned()
  let mut subject : String? = None
  let mut session : String? = None
  let mut has_datatype = false
  for i, directory in directories {
    if i == 0 && directory.has_prefix("sub-") {
      subject = Some(entity_value("sub", directory[4:].to_owned(), path))
    } else if i == 1 && subject is Some(_) && directory.has_prefix("ses-") {
      session = Some(entity_value("ses", directory[4:].to_owned(), path))
    } else if directory == datatype &&
      subject is Some(_) &&
      i == directories.length() - 1 {
      has_datatype = true
    } else {
      reject(
        "unsupported_scope", path, "Use root/sub-<label>[/ses-<label>]/datatype raw-MRI directories; derived and auxiliary trees are unsupported.",
      )
    }
  }
  if entities.get("sub") != subject || entities.get("ses") != session {
    reject(
      "scope_mismatch", path, "Filename sub/ses entities must match their directory scope; participant/session-specific metadata belongs under that scope.",
    )
  }
  if !sidecar && (!has_datatype || subject is None) {
    reject(
      "invalid_data_scope", path, "Data files must be inside the matching participant datatype directory.",
    )
  }
  if !sidecar && suffix == "bold" && !entities.contains("task") {
    reject("missing_task", path, "A bold data filename requires a task entity.")
  }
  {
    path,
    directory: directories.join("/"),
    depth: directories.length(),
    suffix,
    entities,
  }
}

///|
fn applies(sidecar : Selector, data : Selector) -> Bool {
  (
    sidecar.directory.is_empty() ||
    data.directory == sidecar.directory ||
    data.directory.has_prefix(sidecar.directory + "/")
  ) &&
  sidecar.suffix == data.suffix &&
  sidecar.entities.iter().all(pair => data.entities.get(pair.0) == Some(pair.1))
}
