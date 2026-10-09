///|
pub(all) enum DiscoveryRole {
  Directory
  Data
  Sidecar
  Auxiliary
  Excluded
} derive(Eq)

///|
pub extend DiscoveryRole with Eq::{equal, not_equal}

///|
/// Classify an inventory entry before reading it. Unsupported candidates fail;
/// exclusions are explicit profile boundaries, never implicit .bidsignore rules.
pub fn classify_discovery_entry(
  path : String,
  directory~ : Bool,
) -> DiscoveryRole raise TraceError {
  let components = parts(path)
  if ["derivatives", "sourcedata", "code", "stimuli"].contains(components[0]) ||
    components.any(c => c.has_prefix(".")) {
    return Excluded
  }
  if directory {
    return Directory
  }
  let name = components[components.length() - 1]
  if name.has_suffix(".nii") || name.has_suffix(".nii.gz") {
    selector(path, sidecar=false) |> ignore
    return Data
  }
  let root_auxiliary = components.length() == 1 &&
    [
      "dataset_description.json", "participants.json", "participants.tsv", "README",
      "README.md", "README.txt", "LICENSE", "LICENSE.txt", "CHANGES", "CHANGES.md",
      "CHANGES.txt",
    ].contains(name)
  let table_auxiliary = name.has_suffix(".tsv") ||
    name.has_suffix(".tsv.gz") ||
    name.has_suffix(".bval") ||
    name.has_suffix(".bvec")
  let json_auxiliary = ["events", "scans", "sessions", "participants"].any(suffix => {
    name == suffix + ".json" || name.has_suffix("_" + suffix + ".json")
  })
  if root_auxiliary || table_auxiliary || json_auxiliary {
    return Auxiliary
  }
  if name.has_suffix(".json") {
    selector(path, sidecar=true) |> ignore
    return Sidecar
  }
  reject(
    "unsupported_inventory_file", path, "File is outside the documented discovery profile; no complete snapshot was returned. Select a supported dataset tree or extend the profile explicitly.",
  )
  Auxiliary
}

///|
pub struct DiscoveryReport {
  priv index : DatasetIndex
  priv auxiliary : Array[String]
  priv excluded : Array[String]
}

///|
/// The caller supplies a full inventory of regular files and explicit excluded
/// subtree paths, plus text for every classified MRI sidecar. Image bytes unused.
pub fn DiscoveryReport::from_inventory(
  paths : Array[String],
  sidecars : Array[SidecarInput],
) -> DiscoveryReport raise TraceError {
  if paths.length() > 20000 {
    reject(
      "inventory_limit", "<inventory>", "Inventory exceeds 20,000 entries; select a smaller supported tree.",
    )
  }
  let seen : Map[String, String] = Map([])
  let files : Array[String] = []
  let expected : Map[String, Bool] = Map([])
  let auxiliary : Array[String] = []
  let excluded : Array[String] = []
  for path in paths {
    if seen.get(path.to_lower()) is Some(existing) {
      reject(
        "path_collision",
        path,
        "Inventory contains a repeated or case-colliding entry.",
        related=[existing],
      )
    }
    seen[path.to_lower()] = path
    match classify_discovery_entry(path, directory=false) {
      Data => files.push(path)
      Sidecar => expected[path] = true
      Auxiliary => auxiliary.push(path)
      Excluded => excluded.push(path)
      Directory => abort("file classifier invariant")
    }
  }
  let provided : Map[String, Bool] = Map([])
  for input in sidecars {
    if !expected.contains(input.path) {
      reject(
        "unexpected_sidecar_text",
        input.path,
        "Source text must correspond to a classified MRI sidecar in the inventory.",
      )
    }
    if provided.contains(input.path) {
      reject(
        "path_collision",
        input.path,
        "Sidecar source text was supplied more than once.",
      )
    }
    provided[input.path] = true
  }
  for path in sorted_keys(expected) {
    if !provided.contains(path) {
      reject(
        "missing_sidecar_text", path, "Read this inventoried sidecar before constructing the snapshot; no partial result was returned.",
      )
    }
  }
  let index = DatasetIndex::from_manifest(files, sidecars)
  auxiliary.sort_by(lexical_compare)
  excluded.sort_by(lexical_compare)
  { index, auxiliary, excluded, }
}

///|
pub fn DiscoveryReport::index(self : DiscoveryReport) -> DatasetIndex {
  self.index
}

///|
pub fn DiscoveryReport::auxiliary_paths(
  self : DiscoveryReport,
) -> Array[String] {
  self.auxiliary.copy()
}

///|
pub fn DiscoveryReport::excluded_paths(self : DiscoveryReport) -> Array[String] {
  self.excluded.copy()
}

///|
pub fn DiscoveryReport::to_json(self : DiscoveryReport) -> String {
  canonical_json(
    Json::object({
      "profile": Json::string("raw_mri_v1"),
      "status": Json::string("complete_supported_inventory"),
      "manifest": self.index.manifest_value(),
      "auxiliary_paths": Json::array(self.auxiliary.map(Json::string)),
      "excluded_paths": Json::array(self.excluded.map(Json::string)),
    }),
  )
}
