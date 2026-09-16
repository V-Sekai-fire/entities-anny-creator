A character creator on ANNY: sliders over a permissive parametric human, in one Godot binary, exporting pure-data VRM.

RFD 2253 is the decision record. This repository is the Godot project the
RFD 2239 binary runs: the scenes, the panels, the slider math ported from
`anny`'s Python, and the checks that gate every one of them.

What a person gets: the canonical ANNY fixture (19,158 vertices, 104
joints, 317 shapes) under three panels, eleven phenotype axes, 52 facial
actions named by FACS action unit, and 254 local dials grouped by body
region; joints that follow the shape through the JointCubes helper
geometry; an export that carries morph targets, skin weights and one
humanoid bone map and nothing that runs.

What it feeds: RFD 2251's `rig`, `expressions`, `animate` and `render`
blocks, unchanged, so the creator and the image front door land in the
same chain.

## Build and check

```sh
pixi install -e bake
pixi run -e bake bake                      # assets/anny_base.glb and the joint tables
<godot> --path . scenes/creator.tscn       # the creator
checks/run.sh <godot>                      # every check and its planted control
```

The bake reads the workspace's ANNY fork at `../../3-interactor/anny`. The checks: slider
parity against the Python model on 20 seeded parameter vectors (0.2 mm tolerance, a quarter
of a credit card), topology pinned at 13,718 vertices, export with no extension outside
`KHR_*` and `VRMC_*`, and the shaped export re-importing to the shape the sliders described.

## Licence

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT License ([LICENSE-MIT](LICENSE-MIT))

at your option.

`SPDX-License-Identifier: Apache-2.0 OR MIT`

ANNY itself is Copyright (C) 2025 NAVER Corporation, Apache-2.0. The
SMPL-X interop topology and the non-commercial optional assets its
`[examples]` extra can fetch are not used here and must not be.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally
submitted for inclusion in this work by you shall be dual licensed as
above, without any additional terms or conditions.
