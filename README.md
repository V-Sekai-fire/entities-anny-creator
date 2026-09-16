A character creator on ANNY: sliders over a permissive parametric human, in one Godot binary, exporting pure-data VRM.

## Build and check

```sh
pixi install -e bake
pixi run -e bake bake                      # assets/anny_base.glb and the joint tables
<godot> --path . scenes/creator.tscn       # the creator
checks/run.sh <godot>                      # every check and its planted control
```

### Contribution

Unless you explicitly state otherwise, any contribution intentionally
submitted for inclusion in this work by you shall be dual licensed as
above, without any additional terms or conditions.
