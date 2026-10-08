///|
/// Build a snapshot from supported raw-MRI paths and complete JSON sources.
/// Repeated paths, scope errors, duplicate JSON keys and unknown profiles fail.
pub fn DatasetIndex::from_manifest(
  files : Array[String],
  sidecars : Array[SidecarInput],
) -> DatasetIndex raise TraceError {
  let paths : Map[String, String] = Map([])
  let labels : Map[String, String] = Map([])
  fn register(item : Selector) -> Unit raise TraceError {
    let folded = item.path.to_lower()
    if paths.get(folded) is Some(existing) {
      reject(
        "path_collision",
        item.path,
        "Duplicate or case-colliding path; supply each source once.",
        related=[existing],
      )
    }
    paths[folded] = item.path
    for key, value in item.entities {
      let folded_label = key + ":" + value.to_lower()
      if labels.get(folded_label) is Some(existing) && existing != value {
        reject(
          "label_collision",
          item.path,
          "Entity labels collide when case is ignored: " +
          existing +
          " / " +
          value,
        )
      }
      labels[folded_label] = value
    }
  }
  let data = files.map(path => {
    let item = selector(path, sidecar=false)
    register(item)
    item
  })
  let metadata = sidecars.map(input => {
    let item = selector(input.path, sidecar=true)
    register(item)
    guard parse_source(input.path, input.text) is Object(fields) else {
      reject(
        "expected_object",
        input.path,
        "A JSON sidecar must contain an object at the top level.",
      )
      return { selector: item, metadata: Map([]), }
    }
    { selector: item, metadata: fields, }
  })
  data.sort_by((a, b) => lexical_compare(a.path, b.path))
  metadata.sort_by((a, b) => {
    let depth = a.selector.depth.compare(b.selector.depth)
    if depth == 0 {
      lexical_compare(a.selector.path, b.selector.path)
    } else {
      depth
    }
  })
  let index : DatasetIndex = { files: data, sidecars: metadata, }
  // Every accepted snapshot must be reloadable through the same public API.
  if index.to_manifest_json().length() > 2097152 {
    reject(
      "snapshot_limit", "<manifest>", "Canonical snapshot exceeds 2,097,152 UTF-16 code units; split the snapshot before constructing an index.",
    )
  }
  index
}

///|
pub fn DatasetIndex::data_paths(self : DatasetIndex) -> Array[String] {
  self.files.map(file => file.path)
}

///|
/// Resolve JSON top-level assignments only. Same-level ambiguity is an error,
/// even when one filename has more entities or the values happen to agree.
pub fn DatasetIndex::resolve(
  self : DatasetIndex,
  data_path : String,
) -> ResolvedMetadata raise TraceError {
  guard self.files.search_by(file => file.path == data_path) is Some(index) else {
    reject(
      "unknown_data_path", data_path, "Data path is absent from the manifest; add it before querying.",
    )
    return { path: data_path, values: Map([]), origins: Map([]), applied: [], }
  }
  let data = self.files[index]
  let candidates = self.sidecars.filter(sidecar => {
    applies(sidecar.selector, data)
  })
  let at_depth : Map[Int, Array[String]] = Map([])
  for sidecar in candidates {
    let level = sidecar.selector.depth
    let paths = at_depth.get_or_init(level, () => [])
    paths.push(sidecar.selector.path)
  }
  for sidecar in candidates {
    let paths = at_depth[sidecar.selector.depth]
    if paths.length() > 1 {
      reject(
        "ambiguous_inheritance",
        data_path,
        "Multiple JSON sidecars apply at the same directory level; consolidate them rather than relying on filename specificity.",
        related=paths.copy(),
      )
    }
  }
  let values : Map[String, Json] = Map([])
  let origins : Map[String, Array[FieldOrigin]] = Map([])
  let applied : Array[String] = []
  for sidecar in candidates {
    applied.push(sidecar.selector.path)
    for key in sorted_keys(sidecar.metadata) {
      let value = copy_json(sidecar.metadata[key])
      values[key] = value
      origins
      .get_or_init(key, () => [])
      .push({ path: sidecar.selector.path, value, })
    }
  }
  { path: data_path, values, origins, applied, }
}
