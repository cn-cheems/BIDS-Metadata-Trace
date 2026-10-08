# Real metadata fixture: OpenNeuro ds000001

Source repository: https://github.com/OpenNeuroDatasets/ds000001

Pinned commit: `f8e27ac909e50b5b5e311f6be271f0b1757ebb7b` (retrieved 2026-10-08).

The three data paths are the actual `sub-01/func/*bold.nii.gz` paths in that snapshot. The JSON values are transcribed without numeric conversion from:

https://github.com/OpenNeuroDatasets/ds000001/blob/f8e27ac909e50b5b5e311f6be271f0b1757ebb7b/task-balloonanalogrisktask_bold.json

The source `dataset_description.json` declares `License: CC0`, identifies the Balloon Analog Risk-taking Task dataset, and lists Tom Schonberg, Christopher Fox, Craig Fox and Russell A. Poldrack as authors:

https://github.com/OpenNeuroDatasets/ds000001/blob/f8e27ac909e50b5b5e311f6be271f0b1757ebb7b/dataset_description.json

Dataset DOI: https://doi.org/10.18112/openneuro.ds000001.v1.0.0

CC0 terms: https://creativecommons.org/publicdomain/zero/1.0/

No imaging bytes are redistributed. The manifest is an explicit subset containing subject 01's three BOLD paths and the root BOLD sidecar; it is not a complete dataset inventory or a BIDS compliance certificate. The original dataset declares BIDS 1.0.0; this example exercises inheritance rules, not migration or validation against the entire 1.11.2 schema.
