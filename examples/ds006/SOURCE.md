# Multi-subject, multi-session metadata fixture

Source: [bids-standard/bids-examples, ds006](https://github.com/bids-standard/bids-examples/tree/5e00d47b6f1db106dda1b776d5243eb41b4cb95b/ds006), pinned commit `5e00d47b6f1db106dda1b776d5243eb41b4cb95b` (read 2026-10-25).

`manifest.json` selects the actual run-01 BOLD path in each of sub-01/sub-02 and ses-pre/ses-post, and transcribes the complete [root task sidecar](https://github.com/bids-standard/bids-examples/blob/5e00d47b6f1db106dda1b776d5243eb41b4cb95b/ds006/task-livingnonlivingdecisionwithplainormirrorreversedtext_bold.json). Its independently recorded expected result is RT token `2.0`, TaskName `living-nonliving decision with plain or mirror-reversed text`, and exactly that root source for all four scans. The supplied snapshot includes only this task sidecar. This is an explicit subset, not a complete dataset inventory.

The upstream [dataset_description.json](https://github.com/bids-standard/bids-examples/blob/5e00d47b6f1db106dda1b776d5243eb41b4cb95b/ds006/dataset_description.json) identifies ds000006 and authors K Jimura, E Stover, F Cazalis and RA Poldrack. It dedicates the dataset under the [Public Domain Dedication and License 1.0 (PDDL)](https://opendatacommons.org/licenses/pddl/1-0/) and requests acknowledgement of OpenfMRI and NSF Grant OCI-1131441 (R. Poldrack, PI). These metadata/path selections retain those terms; they are not relicensed as Apache-2.0. The upstream example uses empty image files; this repository redistributes no images or participant tables. It does not claim to exercise image processing or BIDS compliance.

`post-session-changes.json` is an independently authored **synthetic** proposal (Apache-2.0), adding a subject-01/post-session override with RT `3.0`. It is not an observed upstream source. Expected impact: exactly one scan changes; the other subject and pre-session remain at `2.0`. `consistency.json` checks RT agreement across sessions within each subject, so the candidate yields exactly one group-field violation.

Run from the repository root:

```sh
moon run cmd/main -- audit examples/ds006/manifest.json
moon run cmd/main -- consistency examples/ds006/manifest.json examples/ds006/consistency.json
moon run cmd/main -- plan-changes examples/ds006/manifest.json examples/ds006/post-session-changes.json --manifest-only > candidate.json
moon run cmd/main -- consistency candidate.json examples/ds006/consistency.json
```

The final command deliberately exits 1. `scripts/verify.mbtx` checks root provenance, scoped impact, the failing consistency decision, bundle replay and recovery on the original fixture without a network connection.
