///|
priv struct SourceUse {
  path : String
  winning : Array[String]
  shadowed : Array[String]
  error : Diagnostic?
}

///|
fn copy_diagnostic(d : Diagnostic) -> Diagnostic {
  {
    code: d.code,
    path: d.path,
    message: d.message,
    offset: d.offset,
    related: d.related.copy(),
  }
}

///|
/// Applicability and field contribution for one source within indexed scans.
pub struct SourceCoverageEntry {
  priv path : String
  priv keys : Array[String]
  priv scans : Array[SourceUse]
}

///|
pub fn SourceCoverageEntry::path(self : SourceCoverageEntry) -> String {
  self.path
}

///|
pub fn SourceCoverageEntry::metadata_keys(
  self : SourceCoverageEntry,
) -> Array[String] {
  self.keys.copy()
}

///|
pub fn SourceCoverageEntry::applicable_paths(
  self : SourceCoverageEntry,
) -> Array[String] {
  self.scans.map(s => s.path)
}

///|
pub fn SourceCoverageEntry::winning_paths(
  self : SourceCoverageEntry,
) -> Array[String] {
  self.scans.filter(s => !s.winning.is_empty()).map(s => s.path)
}

///|
pub fn SourceCoverageEntry::fully_shadowed_paths(
  self : SourceCoverageEntry,
) -> Array[String] {
  self.scans
  .filter(s => s.error is None && !self.keys.is_empty() && s.winning.is_empty())
  .map(s => s.path)
}

///|
pub fn SourceCoverageEntry::unresolved_paths(
  self : SourceCoverageEntry,
) -> Array[String] {
  self.scans.filter(s => s.error is Some(_)).map(s => s.path)
}

///|
pub struct SourceCoverageReport {
  priv entries : Array[SourceCoverageEntry]
  priv scan_count : Int
  priv errors : Array[Diagnostic]
}

///|
pub fn SourceCoverageReport::entries(
  self : SourceCoverageReport,
) -> Array[SourceCoverageEntry] {
  self.entries.copy()
}

///|
pub fn SourceCoverageReport::error_count(self : SourceCoverageReport) -> Int {
  self.errors.length()
}

///|
pub fn SourceCoverageReport::diagnostics(
  self : SourceCoverageReport,
) -> Array[Diagnostic] {
  self.errors.map(copy_diagnostic)
}

///|
/// Sources without any applicable indexed scan; this is not a deletion verdict.
pub fn SourceCoverageReport::unmatched_paths(
  self : SourceCoverageReport,
) -> Array[String] {
  self.entries.filter(e => e.scans.is_empty()).map(e => e.path)
}

///|
/// Account for every supplied sidecar, including empty and ambiguous sources.
/// Failed scans never produce speculative winning/shadowed assignments.
pub fn DatasetIndex::source_coverage(
  self : DatasetIndex,
) -> SourceCoverageReport {
  let audit = self.audit_all()
  let sources = self.sidecars.copy()
  sources.sort_by((a, b) => lexical_compare(a.selector.path, b.selector.path))
  let entries = sources.map(source => {
    let keys = sorted_keys(source.metadata)
    let scans : Array[SourceUse] = []
    for i, data in self.files {
      if applies(source.selector, data) {
        let outcome = audit.entries[i]
        match outcome.result {
          Some(result) => {
            let winning : Array[String] = []
            let shadowed : Array[String] = []
            for key in keys {
              let history = result.origins[key]
              if history[history.length() - 1].path == source.selector.path {
                winning.push(key)
              } else {
                shadowed.push(key)
              }
            }
            scans.push({ path: data.path, winning, shadowed, error: None, })
          }
          None =>
            scans.push({
              path: data.path,
              winning: [],
              shadowed: [],
              error: outcome.error,
            })
        }
      }
    }
    { path: source.selector.path, keys, scans, }
  })
  let errors : Array[Diagnostic] = []
  for outcome in audit.entries {
    if outcome.error is Some(error) {
      errors.push(error)
    }
  }
  { entries, scan_count: self.files.length(), errors, }
}

///|
pub fn SourceCoverageReport::to_json(self : SourceCoverageReport) -> String {
  canonical_json(
    Json::object({
      "scope": Json::string("indexed_scans"),
      "scan_count": Json::number(self.scan_count.to_double()),
      "error_count": Json::number(self.error_count().to_double()),
      "unmatched_paths": Json::array(self.unmatched_paths().map(Json::string)),
      "diagnostics": Json::array(self.errors.map(d => d.to_json())),
      "entries": Json::array(
        self.entries.map(entry => {
          Json::object({
            "path": Json::string(entry.path),
            "metadata_keys": Json::array(entry.keys.map(Json::string)),
            "applicable_paths": Json::array(
              entry.applicable_paths().map(Json::string),
            ),
            "winning_paths": Json::array(
              entry.winning_paths().map(Json::string),
            ),
            "fully_shadowed_paths": Json::array(
              entry.fully_shadowed_paths().map(Json::string),
            ),
            "unresolved_paths": Json::array(
              entry.unresolved_paths().map(Json::string),
            ),
            "scans": Json::array(
              entry.scans.map(scan => {
                let fields : Map[String, Json] = {
                  "data_path": Json::string(scan.path),
                  "status": Json::string(
                    if scan.error is Some(_) {
                      "error"
                    } else {
                      "resolved"
                    },
                  ),
                  "winning_fields": Json::array(scan.winning.map(Json::string)),
                  "shadowed_fields": Json::array(
                    scan.shadowed.map(Json::string),
                  ),
                }
                if scan.error is Some(error) {
                  fields["diagnostic"] = error.to_json()
                }
                Json::object(fields)
              }),
            ),
          })
        }),
      ),
    }),
  )
}
