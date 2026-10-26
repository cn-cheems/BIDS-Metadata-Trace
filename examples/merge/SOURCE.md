# Merge demonstration sources

`right-manifest.json` retains the three scan paths, `TaskName` and RT `2.0`
from the existing [OpenNeuro ds000001 CC0 subset](../ds000001/SOURCE.md).
The `ReviewNote` object and its exact-number values are synthetic authored
Apache-2.0 demonstration data, not observed acquisition metadata.

The workflow uses `../ds000001/changed-manifest.json` as a synthetic left
branch, and `../ds000001/provenance-manifest.json` as a conflicting right
branch. Their mutations and attribution are recorded in that directory's
source note. No image data or private infrastructure is needed. No external
implementation or test cases are reused.
