Nightly's asset viewer plays `<asset>.anim.json` beside a weapon model. Packs bake it from the code the game runs; this addon owns the writer so a track means the same thing in every pack.

## Document (version 1)

| Key | Meaning |
| --- | --- |
| `version`, `weapon`, `model`, `asset`, `fps` | 1; the weapon id; the model's file stem; Nightly's asset name (`GSWeaponAnimSidecar.asset_of(pack, path)`: the pack, then the path under `res://` with `/` as `__`); 60 |
| `lens` | `GSWeaponAnimSidecar.lens(viewmodel_fov_h, world_fov_h)` for a pack with a hands lens, `lens_identity()` for one without |
| `nodes` | `{bolt, magazine}`: the GLB node the track drives, or `""` |
| `clips` | `[{name, length, frames, loop, tracks[{target, path, values}]}]`; `length` is frames over fps to the millisecond |
| extras | `third_person`, `props`, `magazine_*`, `alias_of`: pack data the writer passes through |

## Spaces and widths

| Target | Space |
| --- | --- |
| `weapon`, `hand.*`, `prop.*` | view (camera) space: the rig's own kick is the clip, so read relative to the camera, not the rig |
| `magazine`, `bolt` | the weapon's own frame (weapon-local) |
| `<part>.visible` | one float a frame, 1 shown |

Path widths a frame: `transform` 7 (position, then quaternion `xyzw`), `position` 3, `visible` 1, `vec2` 2. Values round to 0.00001.

## Use

A pack's baker owns a `GSWeaponAnimSidecar` as its recorder: `begin()`, then per frame `put(key, path, values)` for each part and `frame_done()`, then `finish(name, loop)`. A track that starts late is backfilled; one that stops (a part the game freed) holds its last values, hidden when visible. A baker that keeps its own arrays builds with the static `t7`, `rounded`, `track`, `clip`. `sidecar(...)` assembles the document. The pack's `tools/export_anim_tracks.gd` extends `tools/gs_weapon_anim_export.gd`, overrides `_bake_all` and calls `emit`; with `-` as the directory it prints `SIDECAR<TAB>asset<TAB>json` lines, which is how an offloaded run returns its files.
