# Gen1Recomp 3D Character Selector

Repository: `randyadr/Gen1Recomp-Character-Selector`

For releases, create a tag such as `v2.8.8`. The included GitHub Actions workflow builds an installable `red_3d_player-v2.8.8.zip` with `manifest.json` at the archive root, which is the layout expected by the Gen1Recomp mod manager/index.

# 3D Character Selector — Gen1Recomp / Dramatic Shape

This mod evolved from Red 3D Player into a multi-character 3D player system.


### Persistent 360° body facing

In Dramatic Shape 1ST/3RD free-roam, the 3D player model keeps the last direction it was actually travelling when movement stops. You can orbit the camera around the standing character without the model automatically snapping back to camera-forward. Moving again at any angle immediately updates the body direction.

## Characters

- **Red** — the existing polished 107-bone model and animation set.
- **Yugi Muto** — converted from the user-supplied DAE/SMD asset pack, using a 27-bone skinned humanoid rig and the same runtime movement system.

## Skin Selector

Open the normal in-game pause/start menu and choose **Skin Selector**. Select Red or Yugi Muto; the 3D overworld and Dramatic Shape battle representation switches immediately. The selected character is persisted.

The same choice is also exposed as `CHARACTER` in the mod options as a fallback.

## Battle intro

In Dramatic Shape battles, the flat player trainer card is replaced by the selected 3D character. The battle pointing timer was fixed in v2.0.0: it now starts once when the trainer model appears instead of being reset by Dramatic Shape's changing battle token. Red/Yugi raise the right arm and point toward the opponent before the trainer model disappears.

## Manual jump

`X` on Xbox / `Square` on PlayStation performs the custom jump when **MANUAL JUMP** is enabled. Valid Gen1 ledges use the engine's native hop; one-cell low border/fence obstacles can also be crossed when the landing cell is safe.

## Yugi source assets

The user-supplied `Yugi Muto.zip` source files are included under `source/yugi/` for rebuild purposes. `data/yugi_model.lua` and `assets/yugi_atlas.png` are pre-generated, so Python is not required to play.

## Rebuild Yugi

```bash
python tools/convert_yugi_dae.py source/yugi/Model.dae \
  --textures source/yugi \
  --out-lua data/yugi_model.lua \
  --out-atlas assets/yugi_atlas.png
```


## Naruto

Naruto is generated from the supplied `Naruto.smd` rather than the OBJ. The SMD provides the complete 124-bone hierarchy, per-vertex weights, UVs, and material names. The converter rotates the source Z-up/-Y-forward coordinates into the mod runtime's Y-up/+Z-forward convention before generating the bind matrices. Body, head, and eye materials are packed into independent atlas regions. Naruto also uses a dedicated local-axis animation profile so Red/Yugi joint-axis assumptions are not applied to his arms and legs.


### Added character: Carl Johnson (CJ)
CJ is imported from the supplied GTA San Andreas OBJ/FBX package with separate head, upper-body, legs, and shoes textures and a runtime skeleton derived from the named GTA rig helpers.
