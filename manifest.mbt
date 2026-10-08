///|
fn expect_keys(
  fields : Map[String, Json],
  allowed : Array[String],
  location : String,
) -> Unit raise TraceError {
  for key in sorted_keys(fields) {
    if !allowed.contains(key) {
      reject(
        "unknown_manifest_field",
        location,
        "Unknown manifest field " +
        key +
        "; remove it explicitly or use a supported manifest version.",
      )
    }
  }
}

///|
/// Read the strict v1 manifest: {"files":[paths],"sidecars":[{"path":path,"metadata":object}]}.
/// Duplicate keys are checked throughout, before any data is consumed.
pub fn DatasetIndex::from_json(text : String) -> DatasetIndex raise TraceError {
  // The envelope adds three containers. Each extracted sidecar is reparsed
  // at its own 64-container metadata limit during index construction.
  guard parse_source("<manifest>", text, container_limit=67) is Object(fields) else {
    reject(
      "invalid_manifest", "<manifest>", "Expected an object containing files and sidecars arrays.",
    )
    return DatasetIndex::from_manifest([], [])
  }
  expect_keys(fields, ["files", "sidecars"], "<manifest>")
  guard fields.get("files") is Some(Array(files)) &&
    fields.get("sidecars") is Some(Array(sidecars)) else {
    reject(
      "invalid_manifest", "<manifest>", "Both files and sidecars must be arrays.",
    )
    return DatasetIndex::from_manifest([], [])
  }
  let paths = files.map(value => {
    guard value is String(path) else {
      reject(
        "invalid_manifest", "<manifest>/files", "Each data path must be a string.",
      )
      return ""
    }
    path
  })
  let inputs = sidecars.map(value => {
    guard value is Object(entry) else {
      reject(
        "invalid_manifest", "<manifest>/sidecars", "Each sidecar must be a path/metadata object.",
      )
      return SidecarInput::new("", "")
    }
    expect_keys(entry, ["path", "metadata"], "<manifest>/sidecars")
    guard entry.get("path") is Some(String(path)) &&
      entry.get("metadata") is Some(Object(metadata)) else {
      reject(
        "invalid_manifest", "<manifest>/sidecars", "Expected a string path and an object metadata field.",
      )
      return SidecarInput::new("", "")
    }
    SidecarInput::new(path, canonical_json(Json::object(metadata)))
  })
  DatasetIndex::from_manifest(paths, inputs)
}

///|
/// A complete deterministic v1 manifest snapshot. Unknown metadata is retained.
pub fn DatasetIndex::to_manifest_json(self : DatasetIndex) -> String {
  canonical_json(
    Json::object({
      "files": Json::array(self.data_paths().map(Json::string)),
      "sidecars": Json::array(
        self.sidecars.map(sidecar => {
          Json::object({
            "path": Json::string(sidecar.selector.path),
            "metadata": Json::object(sidecar.metadata),
          })
        }),
      ),
    }),
  )
}
