///|
fn merge_audit(index : DatasetIndex, path : String) -> AuditEntry? {
  if index.file_positions.contains(path) {
    Some(index.audit([path]).entries[0])
  } else {
    None
  }
}

///|
fn merge_resolution(entry : AuditEntry?) -> ResolvedMetadata? {
  match entry {
    Some(e) => e.result
    None => None
  }
}

///|
fn merge_metadata(result : ResolvedMetadata?) -> Json? {
  result.map(r => r.report_value())
}

///|
fn merge_field(result : ResolvedMetadata?, key : String) -> Json? {
  match result {
    Some(r) => r.values.get(key)
    None => None
  }
}

///|
fn merge_check_scans(
  base : DatasetIndex,
  left : DatasetIndex,
  right : DatasetIndex,
  candidate : DatasetIndex,
  paths : Array[String],
  conflicts : Array[MergeConflict],
  resolution~ : MergeResolution?,
) -> Unit raise TraceError {
  for path in paths {
    let be = merge_audit(base, path)
    let le = merge_audit(left, path)
    let re = merge_audit(right, path)
    let ce = merge_audit(candidate, path)
    let prior_count = conflicts.length()
    for
      (branch, entry) in [
        ("base", be),
        ("left", le),
        ("right", re),
        ("merged", ce),
      ] {
      if entry is Some(e) && e.error is Some(d) {
        merge_conflict(conflicts, UnresolvedMetadata, path, branch~, diagnostics=[
          d,
        ])
      }
    }
    if conflicts.length() != prior_count {
      continue
    }
    let b = merge_resolution(be)
    let l = merge_resolution(le)
    let r = merge_resolution(re)
    let c = merge_resolution(ce)
    if c is None {
      // A removed scan must not silently erase the other side's provenance or
      // effective edit. Even an empty applied source is observable evidence.
      if !(resolution is Some(plan) && plan.scan_at(path) is Some(_)) &&
        b is Some(_) &&
        (
          (l is Some(_) && !merge_equal(merge_metadata(b), merge_metadata(l))) ||
          (r is Some(_) && !merge_equal(merge_metadata(b), merge_metadata(r)))
        ) {
        merge_conflict(
          conflicts,
          ScanDeleteEdit,
          path,
          base?=merge_metadata(b),
          left?=merge_metadata(l),
          right?=merge_metadata(r),
        )
      }
      continue
    }
    let keys : Map[String, Bool] = Map([])
    for result in [b, l, r, c] {
      if result is Some(result) {
        for key in result.keys() {
          keys[key] = true
        }
      }
    }
    for key in sorted_keys(keys) {
      let bv = merge_field(b, key)
      let lv = merge_field(l, key)
      let rv = merge_field(r, key)
      let cv = merge_field(c, key)
      // Assertions are checked against the resolved candidate before entering
      // this pass. They authorize exactly this effective field, never a whole
      // scan, another field, or any unresolved historical input.
      if resolution is Some(plan) && plan.has_effective(path, key) {
        continue
      }
      // For a newly introduced scan, only snapshots which actually contain it
      // establish intent. A change in the other branch may alter its inherited
      // values; require review rather than guessing that intent.
      let expected = if l is None {
        rv
      } else if r is None {
        lv
      } else if merge_equal(lv, rv) {
        lv
      } else if merge_equal(bv, lv) {
        rv
      } else if merge_equal(bv, rv) {
        lv
      } else {
        merge_conflict(
          conflicts,
          EffectiveDiverged,
          path,
          key~,
          base?=bv,
          left?=lv,
          right?=rv,
          merged?=cv,
        )
        continue
      }
      if !merge_equal(expected, cv) {
        merge_conflict(
          conflicts,
          InheritanceShadow,
          path,
          key~,
          base?=bv,
          left?=lv,
          right?=rv,
          merged?=cv,
        )
      }
    }
  }
}
