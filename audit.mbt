///|
pub struct AuditEntry {
  priv path : String
  priv result : ResolvedMetadata?
  priv error : Diagnostic?
}

///|
pub fn AuditEntry::path(self : AuditEntry) -> String {
  self.path
}

///|
pub fn AuditEntry::result(self : AuditEntry) -> ResolvedMetadata? {
  self.result
}

///|
pub fn AuditEntry::diagnostic(self : AuditEntry) -> Diagnostic? {
  self.error.map(d => {
    code: d.code,
    path: d.path,
    message: d.message,
    offset: d.offset,
    related: d.related.copy(),
  })
}

///|
pub struct AuditReport {
  priv entries : Array[AuditEntry]
}

///|
pub fn AuditReport::entries(self : AuditReport) -> Array[AuditEntry] {
  self.entries.copy()
}

///|
pub fn AuditReport::error_count(self : AuditReport) -> Int {
  self.entries.filter(e => e.error is Some(_)).length()
}

///|
/// Every requested occurrence is retained in request order, including duplicates.
/// Resolution errors are isolated; invalid manifests still fail at construction.
pub fn DatasetIndex::audit(
  self : DatasetIndex,
  paths : Array[String],
) -> AuditReport {
  let entries = paths.map(path => {
    { path, result: Some(self.resolve(path)), error: None, } catch {
      TraceError(diagnostic) => { path, result: None, error: Some(diagnostic), }
    }
  })
  { entries, }
}

///|
pub fn DatasetIndex::audit_all(self : DatasetIndex) -> AuditReport {
  self.audit(self.data_paths())
}

///|
pub fn AuditReport::to_json(self : AuditReport) -> String {
  canonical_json(
    Json::object({
      "error_count": Json::number(self.error_count().to_double()),
      "entries": Json::array(
        self.entries.map(e => {
          let fields : Map[String, Json] = { "data_path": Json::string(e.path) }
          match (e.result, e.error) {
            (Some(result), None) => {
              fields["status"] = Json::string("resolved")
              fields["result"] = result.report_value()
            }
            (None, Some(diagnostic)) => {
              fields["status"] = Json::string("error")
              fields["diagnostic"] = diagnostic.to_json()
            }
            _ => abort("AuditEntry invariant")
          }
          Json::object(fields)
        }),
      ),
    }),
  )
}
