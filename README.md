# entities-anny-creator

A character creator with sliders over the ANNY parametric human that exports the shaped character as VRM.

## What it is for

A one-time bake turns the ANNY model into the mesh, morph targets and joint tables the engine project loads. At runtime the sliders and the joint math run in the engine alone. RFD 2253 in [manuals-weftspun](https://github.com/V-Sekai-fire/manuals-weftspun) owns the design.

## Build and run

```sh
pixi run -e bake bake
checks/run.sh <engine binary>
```

The bake reads the workspace's `anny` checkout, as `pixi.toml` names it. Open the project in the editor to use the creator; the check script runs every check with its planted control.

## Licence

Apache-2.0 OR MIT, at your option; see LICENSE-APACHE and LICENSE-MIT.

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in this work by you shall be dual licensed as above, without any additional terms or conditions.
