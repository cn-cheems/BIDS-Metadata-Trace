///|
async fn load_edit_batch(path : String) -> @trace.EditBatch {
  try {
    if @fs.file_size(path) > 8388608L {
      raise @trace.TraceError({
        code: "input_limit",
        path,
        message: "Edit batch exceeds 8 MiB on disk; reduce the review scope.",
        offset: None,
        related: [],
      })
    }
    @trace.EditBatch::from_json(@fs.read_file(path).text())
  } catch {
    @trace.TraceError(diagnostic) => raise @trace.TraceError(diagnostic)
    error =>
      raise @trace.TraceError({
        code: "io_error",
        path,
        message: error.to_string(),
        offset: None,
        related: [],
      })
  }
}
