///|
/// EffectiveValues includes scan additions/removals and exact value-token edits.
/// AllChanges additionally includes assignment-history and source-chain edits.
pub(all) enum ReleasePolicy {
  EffectiveValues
  AllChanges
} derive(Eq)

///|
pub extend ReleasePolicy with Eq::{equal, not_equal}

///|
pub(all) enum ReleaseDecision {
  Pass
  ChangesDetected
  Indeterminate
} derive(Eq)

///|
pub extend ReleaseDecision with Eq::{equal, not_equal}

///|
pub struct ReleaseCheck {
  priv policy : ReleasePolicy
  priv impact : ImpactReport
  priv affected : Array[String]
  priv unresolved : Array[String]
}

///|
/// Errors take precedence over changes. A pass refers only to this policy and
/// these explicit snapshots; it is not a BIDS compliance or completeness claim.
pub fn ReleaseCheck::decision(self : ReleaseCheck) -> ReleaseDecision {
  if !self.unresolved.is_empty() {
    Indeterminate
  } else if !self.affected.is_empty() {
    ChangesDetected
  } else {
    Pass
  }
}

///|
pub fn ReleaseCheck::policy(self : ReleaseCheck) -> ReleasePolicy {
  self.policy
}

///|
/// Sorted scan paths meeting the selected change policy, even when errors exist.
pub fn ReleaseCheck::affected_paths(self : ReleaseCheck) -> Array[String] {
  self.affected.copy()
}

///|
pub fn ReleaseCheck::unresolved_paths(self : ReleaseCheck) -> Array[String] {
  self.unresolved.copy()
}

///|
/// Full evidence, including policy-ignored provenance changes and diagnostics.
pub fn ReleaseCheck::impact(self : ReleaseCheck) -> ImpactReport {
  self.impact
}

///|
pub fn ImpactReport::release_check(
  self : ImpactReport,
  policy : ReleasePolicy,
) -> ReleaseCheck {
  let affected : Array[String] = []
  let unresolved : Array[String] = []
  for entry in self.entries {
    match entry.kind {
      Unresolved => unresolved.push(entry.path)
      Added | Removed => affected.push(entry.path)
      Changed => {
        let relevant = policy == AllChanges ||
          entry.changes.iter().any(c => c.kind != ProvenanceChanged)
        if relevant {
          affected.push(entry.path)
        }
      }
      Unchanged => ()
    }
  }
  { policy, impact: self, affected, unresolved, }
}

///|
fn release_policy_name(policy : ReleasePolicy) -> String {
  match policy {
    EffectiveValues => "effective_values"
    AllChanges => "all_changes"
  }
}

///|
fn release_decision_name(decision : ReleaseDecision) -> String {
  match decision {
    Pass => "pass"
    ChangesDetected => "changes_detected"
    Indeterminate => "indeterminate"
  }
}

///|
pub fn ReleaseCheck::to_json(self : ReleaseCheck) -> String {
  canonical_json(
    Json::object({
      "policy": Json::string(release_policy_name(self.policy)),
      "decision": Json::string(release_decision_name(self.decision())),
      "affected_paths": Json::array(self.affected.map(Json::string)),
      "unresolved_paths": Json::array(self.unresolved.map(Json::string)),
      "impact": self.impact.report_value(),
    }),
  )
}
