///|
/// Each source occurs in exactly one directory/suffix bucket and optionally
/// one entity/value sub-bucket. This is a candidate filter, not precedence.
priv struct SourceBucket {
  unconditional : Array[Int32]
  by_entity : Map[String, Map[String, Array[Int32]]]
}

///|
fn source_discriminator(source : Selector) -> (String, String)? {
  // sub/ses are already enforced by validated directory scope.
  for key in ["task", "acq", "ce", "rec", "dir", "run", "echo", "part", "chunk"] {
    if source.entities.get(key) is Some(value) {
      return Some((key, value))
    }
  }
  None
}

///|
fn make_source_buckets(
  sidecars : Array[Sidecar],
) -> Map[String, Map[String, SourceBucket]] {
  if sidecars.length() <= 8 {
    return Map([])
  }
  let directories : Map[String, Map[String, SourceBucket]] = Map([])
  for position, source in sidecars {
    let suffixes = directories.get_or_init(source.selector.directory, () => {
      Map([])
    })
    let bucket = suffixes.get_or_init(source.selector.suffix, () => {
      unconditional: [],
      by_entity: Map([]),
    })
    bucket.unconditional.push(position)
  }
  // Small scope buckets already prune most sources. Avoid nested entity maps
  // for ordinary one-source subject/session directories.
  for _, suffixes in directories {
    for _, bucket in suffixes {
      if bucket.unconditional.length() >= 8 {
        let positions = bucket.unconditional.copy()
        bucket.unconditional.clear()
        for position in positions {
          match source_discriminator(sidecars[position].selector) {
            None => bucket.unconditional.push(position)
            Some((key, value)) =>
              bucket.by_entity
              .get_or_init(key, () => Map([]))
              .get_or_init(value, () => [])
              .push(position)
          }
        }
      }
    }
  }
  directories
}

///|
fn DatasetIndex::matching_sources(
  self : DatasetIndex,
  data : Selector,
) -> Array[Sidecar] {
  if self.sidecars.length() <= 8 {
    return self.sidecars.filter(source => applies(source.selector, data))
  }
  let ancestors = [""]
  let mut path = ""
  for part in data.directory.split("/") {
    path = if path.is_empty() {
      part.to_owned()
    } else {
      path + "/" + part.to_owned()
    }
    ancestors.push(path)
  }
  let positions : Array[Int32] = []
  for directory in ancestors {
    if self.source_buckets.get(directory) is Some(suffixes) &&
      suffixes.get(data.suffix) is Some(bucket) {
      for position in bucket.unconditional {
        positions.push(position)
      }
      for key, values in bucket.by_entity {
        if data.entities.get(key) is Some(value) &&
          values.get(value) is Some(matches) {
          for position in matches {
            positions.push(position)
          }
        }
      }
    }
  }
  // Source positions already encode the original depth/ordinal-path order.
  positions.sort()
  positions
  .map(position => self.sidecars[position])
  .filter(source => applies(source.selector, data))
}
