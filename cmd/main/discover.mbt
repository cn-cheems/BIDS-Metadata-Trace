///|
priv struct DiscoveryState {
  paths : Array[String]
  sources : Array[@trace.SidecarInput]
  mut visited : Int
}

///|
async fn discovery_walk(
  root : String,
  relative : String,
  state : DiscoveryState,
  depth : Int,
) -> Unit {
  if depth > 32 {
    raise @trace.TraceError({
      code: "directory_limit",
      path: relative,
      message: "Directory nesting exceeds 32 levels.",
      offset: None,
      related: [],
    })
  }
  let host = if relative.is_empty() { root } else { root + "/" + relative }
  for name in @fs.readdir(host, include_hidden=true, sort=true) {
    let path = if relative.is_empty() { name } else { relative + "/" + name }
    let host_path = root + "/" + path
    state.visited += 1
    if state.visited > 20000 {
      raise @trace.TraceError({
        code: "inventory_limit",
        path,
        message: "Discovery visited more than 20,000 entries.",
        offset: None,
        related: [],
      })
    }
    let kind = @fs.kind(host_path, follow_symlink=false)
    if kind == Directory {
      if @trace.classify_discovery_entry(path, directory=true) == Excluded {
        state.paths.push(path)
      } else {
        discovery_walk(root, path, state, depth + 1)
      }
    } else if kind == Regular {
      let role = @trace.classify_discovery_entry(path, directory=false)
      state.paths.push(path)
      if role == Sidecar {
        if @fs.file_size(host_path) > 8388608L {
          raise @trace.TraceError({
            code: "input_limit",
            path,
            message: "Sidecar exceeds 8 MiB on disk.",
            offset: None,
            related: [],
          })
        }
        let text = @fs.read_file(host_path).text() catch {
          error =>
            raise @trace.TraceError({
              code: "discovery_io_error",
              path,
              message: error.to_string(),
              offset: None,
              related: [],
            })
        }
        state.sources.push(@trace.SidecarInput::new(path, text))
      }
    } else {
      raise @trace.TraceError({
        code: "unsupported_file_kind",
        path,
        message: "Discovery requires regular files/directories; symlinks and special files are refused. Use a materialized snapshot.",
        offset: None,
        related: [],
      })
    }
  }
}

///|
async fn discover(root : String) -> @trace.DiscoveryReport {
  try {
    if @fs.kind(root, follow_symlink=false) != Directory {
      raise @trace.TraceError({
        code: "invalid_dataset_root",
        path: root,
        message: "Select a real directory, not a symlink or regular file.",
        offset: None,
        related: [],
      })
    }
    let state : DiscoveryState = { paths: [], sources: [], visited: 0, }
    discovery_walk(root, "", state, 0)
    @trace.DiscoveryReport::from_inventory(state.paths, state.sources)
  } catch {
    @trace.TraceError(d) => raise @trace.TraceError(d)
    error =>
      raise @trace.TraceError({
        code: "discovery_io_error",
        path: root,
        message: error.to_string(),
        offset: None,
        related: [],
      })
  }
}
