///|
/// Immutable resolution cache with all applicable source edges, including
/// ambiguity participants and empty/shadowed sources. No filesystem state.
pub struct DependencyGraph {
  priv index : DatasetIndex
  priv cached : Map[String, AuditEntry]
  priv dependencies : Map[String, Array[String]]
  priv dependents : Map[String, Array[String]]
  priv scan_scopes : Map[String, Map[String, Array[Int32]]]
  priv source_texts : Map[String, String]
}

///|
fn graph_source_texts(index : DatasetIndex) -> Map[String, String] {
  let texts : Map[String, String] = Map([])
  for source in index.sidecars {
    texts[source.selector.path] = canonical_json(Json::object(source.metadata))
  }
  texts
}

///|
fn graph_scopes(index : DatasetIndex) -> Map[String, Map[String, Array[Int32]]] {
  let scopes : Map[String, Map[String, Array[Int32]]] = Map([])
  for position, scan in index.files {
    let ancestors = [""]
    let mut directory = ""
    for part in scan.directory.split("/") {
      directory = if directory.is_empty() {
        part.to_owned()
      } else {
        directory + "/" + part.to_owned()
      }
      ancestors.push(directory)
    }
    for ancestor in ancestors {
      scopes
      .get_or_init(ancestor, () => Map([]))
      .get_or_init(scan.suffix, () => [])
      .push(position)
    }
  }
  scopes
}

///|
fn graph_entry(path : String, sources : Array[Sidecar]) -> AuditEntry {
  { path, result: Some(resolve_candidates(path, sources)), error: None, } catch {
    TraceError(diagnostic) => { path, result: None, error: Some(diagnostic), }
  }
}

///|
fn graph_reverse(
  dependencies : Map[String, Array[String]],
) -> Map[String, Array[String]] raise TraceError {
  let reverse : Map[String, Array[String]] = Map([])
  let mut edges = 0
  for path in sorted_keys(dependencies) {
    for source in dependencies[path] {
      if edges >= 1048576 {
        reject(
          "dependency_graph_limit", "<dependency-graph>", "More than 1,048,576 source-to-scan edges; narrow the snapshot or use full compare. No partial graph was returned.",
        )
      }
      edges += 1
      reverse.get_or_init(source, () => []).push(path)
    }
  }
  reverse
}

///|
fn graph_count_edges(
  count : Int32,
  additional : Int32,
) -> Int32 raise TraceError {
  if additional > 1048576 - count {
    reject(
      "dependency_graph_limit", "<dependency-graph>", "More than 1,048,576 source-to-scan edges; narrow the snapshot or use full compare. No partial graph was returned.",
    )
  }
  count + additional
}

///|
/// Resolve once and retain immutable results/errors plus complete dependencies.
/// Graph construction is explicit and can cost more than one full comparison.
pub fn DatasetIndex::dependency_graph(
  self : DatasetIndex,
) -> DependencyGraph raise TraceError {
  let cached : Map[String, AuditEntry] = Map([])
  let dependencies : Map[String, Array[String]] = Map([])
  let mut edges = 0
  for scan in self.files {
    let sources = self.matching_sources(scan)
    edges = graph_count_edges(edges, sources.length())
    cached[scan.path] = graph_entry(scan.path, sources)
    dependencies[scan.path] = sources.map(s => s.selector.path)
  }
  {
    index: self,
    cached,
    dependencies,
    dependents: graph_reverse(dependencies),
    scan_scopes: graph_scopes(self),
    source_texts: graph_source_texts(self),
  }
}

///|
pub fn DependencyGraph::snapshot(self : DependencyGraph) -> DatasetIndex {
  self.index
}

///|
/// Cached audit in the snapshot's sorted scan order, including errors.
pub fn DependencyGraph::audit(self : DependencyGraph) -> AuditReport {
  { entries: self.index.data_paths().map(path => self.cached[path]), }
}

///|
/// Current applicable dependents of an existing source, even if resolution is
/// ambiguous. Unknown paths are errors rather than an empty graph answer.
pub fn DependencyGraph::dependents(
  self : DependencyGraph,
  source_path : String,
) -> Array[String] raise TraceError {
  if !self.source_texts.contains(source_path) {
    reject(
      "unknown_sidecar_path", source_path, "Graph dependents require an existing exact source path.",
    )
  }
  self.dependents.get(source_path).unwrap_or([]).copy()
}

///|
/// Deterministic dependency evidence with full snapshot and cached audit.
pub fn DependencyGraph::to_json(self : DependencyGraph) -> String {
  canonical_json(
    Json::object({
      "manifest": self.index.manifest_value(),
      "audit": self.audit().report_value(),
      "sources": Json::array(
        sorted_keys(self.source_texts).map(path => {
          Json::object({
            "path": Json::string(path),
            "scans": Json::array(
              self.dependents.get(path).unwrap_or([]).map(Json::string),
            ),
          })
        }),
      ),
    }),
  )
}

///|
// A newly added source has no old edge. Query baseline scan scope/suffix
// buckets, then apply the complete selector predicate (including normalized
// decimal entities). New scans are independently invalidated below.
fn DependencyGraph::potential_dependents(
  self : DependencyGraph,
  source : Selector,
) -> Array[String] {
  match self.scan_scopes.get(source.directory) {
    Some(suffixes) =>
      match suffixes.get(source.suffix) {
        Some(positions) =>
          positions
          .filter(i => applies(source, self.index.files[i]))
          .map(i => self.index.files[i].path)
        None => []
      }
    None => []
  }
}
