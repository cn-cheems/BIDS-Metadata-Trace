///|
/// A stable machine-readable diagnostic. Offsets count UTF-16 code units.
pub(all) struct Diagnostic {
  code : String
  path : String
  message : String
  offset : Int?
  related : Array[String]
} derive(Eq, ToJson, @debug.Debug)

///|
pub(all) suberror TraceError {
  TraceError(Diagnostic)
} derive(@debug.Debug)

///|
fn reject(
  code : String,
  path : String,
  message : String,
  offset? : Int,
  related? : Array[String] = [],
) -> Unit raise TraceError {
  raise TraceError({ code, path, message, offset, related, })
}

///|
/// Sidecar source text is retained; no caller-supplied Json can be mutated.
pub struct SidecarInput {
  priv path : String
  priv text : String
}

///|
pub fn SidecarInput::new(path : String, text : String) -> SidecarInput {
  { path, text, }
}

///|
priv struct Selector {
  path : String
  directory : String
  depth : Int
  suffix : String
  entities : Map[String, String]
}

///|
priv struct Sidecar {
  selector : Selector
  metadata : Map[String, Json]
}

///|
/// An immutable construction-time dataset snapshot, with no filesystem access.
pub struct DatasetIndex {
  priv files : Array[Selector]
  priv sidecars : Array[Sidecar]
}

///|
/// One assignment of a top-level metadata field, in root-to-leaf order.
pub struct FieldOrigin {
  priv path : String
  priv value : Json
}

///|
pub fn FieldOrigin::path(self : FieldOrigin) -> String {
  self.path
}

///|
/// Returns a defensive copy, preserving numeric source representations.
pub fn FieldOrigin::value(self : FieldOrigin) -> Json {
  copy_json(self.value)
}

///|
pub struct ResolvedMetadata {
  priv path : String
  priv values : Map[String, Json]
  priv origins : Map[String, Array[FieldOrigin]]
  priv applied : Array[String]
}

///|
pub fn ResolvedMetadata::path(self : ResolvedMetadata) -> String {
  self.path
}

///|
pub fn ResolvedMetadata::get(self : ResolvedMetadata, key : String) -> Json? {
  self.values.get(key).map(copy_json)
}

///|
pub fn ResolvedMetadata::keys(self : ResolvedMetadata) -> Array[String] {
  sorted_keys(self.values)
}

///|
pub fn ResolvedMetadata::trace(
  self : ResolvedMetadata,
  key : String,
) -> Array[FieldOrigin] {
  match self.origins.get(key) {
    Some(origins) => origins.copy()
    None => []
  }
}

///|
pub fn ResolvedMetadata::applied_sidecars(
  self : ResolvedMetadata,
) -> Array[String] {
  self.applied.copy()
}

///|
/// Sorted object keys, preserved array order and numeric lexemes; no float math.
pub fn ResolvedMetadata::to_json(self : ResolvedMetadata) -> String {
  canonical_json(Json::object(self.values))
}

///|
fn ResolvedMetadata::report_value(self : ResolvedMetadata) -> Json {
  let fields : Map[String, Json] = Map([])
  for key in self.keys() {
    fields[key] = Json::array(
      self
      .trace(key)
      .map(origin => {
        Json::object({
          "path": Json::string(origin.path),
          "value": copy_json(origin.value),
        })
      }),
    )
  }
  Json::object({
    "data_path": Json::string(self.path),
    "metadata": Json::object(self.values),
    "applied_sidecars": Json::array(self.applied.map(Json::string)),
    "fields": Json::object(fields),
  })
}

///|
pub fn ResolvedMetadata::to_report_json(self : ResolvedMetadata) -> String {
  canonical_json(self.report_value())
}

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend Diagnostic with ToJson::{to_json}

///|
/// Deterministic JSON for logs and CLI error streams.
pub fn Diagnostic::to_report_json(self : Diagnostic) -> String {
  canonical_json(self.to_json())
}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend TraceError with @debug.Debug::{to_repr}
