///|
/// A complete impact report and the next immutable cache. Invalidated means
/// potentially affected, not necessarily changed. Counts describe actual work.
pub struct IncrementalImpact {
  priv before : DatasetIndex
  priv next : DependencyGraph
  priv report : ImpactReport
  priv invalidated : Array[String]
  priv changed_sources : Array[String]
  priv reused : Int32
  priv resolved : Int32
}

///|
pub fn IncrementalImpact::report(self : IncrementalImpact) -> ImpactReport {
  self.report
}

///|
pub fn IncrementalImpact::next(self : IncrementalImpact) -> DependencyGraph {
  self.next
}

///|
pub fn IncrementalImpact::invalidated_paths(
  self : IncrementalImpact,
) -> Array[String] {
  self.invalidated.copy()
}

///|
/// Entries reused in the AFTER snapshot, including unchanged cached errors.
pub fn IncrementalImpact::reused_count(self : IncrementalImpact) -> Int32 {
  self.reused
}

///|
/// Actual after-side resolution attempts, including new and unresolved scans.
pub fn IncrementalImpact::resolved_count(self : IncrementalImpact) -> Int32 {
  self.resolved
}

///|
/// Optional full-oracle verification. Compares the entire deterministic report,
/// including all before/after metadata, histories and diagnostics, byte for byte.
pub fn IncrementalImpact::verify_full(
  self : IncrementalImpact,
) -> Unit raise TraceError {
  if self.report.to_json() != self.before.compare(self.next.index).to_json() {
    reject(
      "incremental_mismatch", "<incremental-impact>", "Incremental evidence differs from full comparison; discard the cache and use full compare. No equivalence was established.",
    )
  }
}

///|
pub fn IncrementalImpact::to_json(self : IncrementalImpact) -> String {
  canonical_json(
    Json::object({
      "analysis": Json::object({
        "changed_sources": Json::array(self.changed_sources.map(Json::string)),
        "invalidated_paths": Json::array(self.invalidated.map(Json::string)),
        "reused_count": Json::number(self.reused.to_double()),
        "resolved_count": Json::number(self.resolved.to_double()),
      }),
      "impact": self.report.report_value(),
    }),
  )
}

///|
// Build the same one-path report as full compare; the cached unchanged fast
// path is explicit and retains unresolved status instead of inventing success.
fn incremental_entry(
  path : String,
  before : AuditEntry?,
  after : AuditEntry?,
  reused~ : Bool,
) -> ImpactEntry {
  if before is Some({ error: Some(_), .. }) ||
    after is Some({ error: Some(_), .. }) {
    return {
      path,
      kind: Unresolved,
      before,
      after,
      changes: [],
      sources_changed: false,
    }
  }
  if reused {
    return {
      path,
      kind: Unchanged,
      before,
      after,
      changes: [],
      sources_changed: false,
    }
  }
  let old = match before {
    Some(e) => e.result
    None => None
  }
  let new = match after {
    Some(e) => e.result
    None => None
  }
  let changes = field_changes(old, new)
  let sources_changed = old.map(r => r.applied).unwrap_or([]) !=
    new.map(r => r.applied).unwrap_or([])
  let kind = match (before, after) {
    (None, Some(_)) => ImpactKind::Added
    (Some(_), None) => Removed
    _ =>
      if changes.is_empty() && !sources_changed {
        Unchanged
      } else {
        Changed
      }
  }
  { path, kind, before, after, changes, sources_changed, }
}

///|
/// Advance to arbitrary validated snapshot content. Changed/removed sources
/// invalidate all old edges; added sources also search potential dependencies.
/// Scan additions/removals invalidate their own paths. Untouched results/errors
/// are reused without resolution. Never mutates this graph or either snapshot.
pub fn DependencyGraph::advance(
  self : DependencyGraph,
  after : DatasetIndex,
) -> IncrementalImpact raise TraceError {
  let texts = graph_source_texts(after)
  let source_paths : Map[String, Bool] = Map([])
  for source in [self.source_texts, texts] {
    for path, _ in source {
      source_paths[path] = true
    }
  }
  let changed_sources = sorted_keys(source_paths).filter(path => {
    self.source_texts.get(path) != texts.get(path)
  })
  let invalidated : Map[String, Bool] = Map([])
  for path in changed_sources {
    for scan in self.dependents.get(path).unwrap_or([]) {
      invalidated[scan] = true
    }
    if !self.source_texts.contains(path) {
      let source = selector(path, sidecar=true)
      for scan in self.potential_dependents(source) {
        invalidated[scan] = true
      }
    }
  }
  let paths : Map[String, Bool] = Map([])
  for index in [self.index, after] {
    for path in index.data_paths() {
      paths[path] = true
    }
  }
  for path, _ in paths {
    if self.index.file_positions.contains(path) !=
      after.file_positions.contains(path) {
      invalidated[path] = true
    }
  }
  let cached : Map[String, AuditEntry] = Map([])
  let dependencies : Map[String, Array[String]] = Map([])
  let mut reused = 0
  let mut resolved = 0
  let mut edges = 0
  for scan in after.files {
    if !invalidated.contains(scan.path) {
      edges = graph_count_edges(edges, self.dependencies[scan.path].length())
      cached[scan.path] = self.cached[scan.path]
      dependencies[scan.path] = self.dependencies[scan.path]
      reused += 1
    } else {
      let sources = after.matching_sources(scan)
      edges = graph_count_edges(edges, sources.length())
      cached[scan.path] = graph_entry(scan.path, sources)
      dependencies[scan.path] = sources.map(s => s.selector.path)
      resolved += 1
    }
  }
  let report : ImpactReport = {
    entries: sorted_keys(paths).map(path => {
      incremental_entry(
        path,
        self.cached.get(path),
        cached.get(path),
        reused=!invalidated.contains(path),
      )
    }),
  }
  let next : DependencyGraph = {
    index: after,
    cached,
    dependencies,
    dependents: graph_reverse(dependencies),
    scan_scopes: if self.index.data_paths() == after.data_paths() {
      self.scan_scopes
    } else {
      graph_scopes(after)
    },
    source_texts: texts,
  }
  {
    before: self.index,
    next,
    report,
    invalidated: sorted_keys(invalidated),
    changed_sources,
    reused,
    resolved,
  }
}
