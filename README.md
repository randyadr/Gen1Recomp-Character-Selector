# Gen1Recomp 3D Character Selector

Repository: `randyadr/Gen1Recomp-Character-Selector`

For releases, create a tag such as `v2.8.73`. The included GitHub Actions workflow builds an installable `red_3d_player-v2.8.73.zip` with `manifest.json` at the archive root, which is the layout expected by the Gen1Recomp mod manager/index.

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



### Added character: Carl Johnson (CJ)
CJ is imported from the supplied GTA San Andreas OBJ/FBX package with separate head, upper-body, legs, and shoes textures and a runtime skeleton derived from the named GTA rig helpers.


### Ash Ketchum
- Added from the supplied rigged `Slow Run.fbx`.
- Uses the FBX's original 44-key / 60 Hz looping Slow Run animation while moving.


## Beelstarmon rebuild reset (v2.8.61)
- Rebuilt **Beelstarmon** from the original `digimon.fbx` mesh and a fresh supplied texture atlas.
- Staged new Beelstarmon source animation files in `source/beelstarmon/`: `Standing Idle (1).fbx`, `Fast Run.fbx`, and `Jumping (1).fbx`.
- Retained the existing runtime Beelstarmon secondary-motion profile, including the exaggerated **x30 breast physics** behavior.


## Beelstarmon fresh Mixamo remake (v2.8.61)
- The old procedural/static-FBX Beelstarmon build has been removed as the active source.
- Beelstarmon is now built directly from the supplied **Standing Idle**, **Fast Run**, and **Jumping** FBXs on their shared Mixamo skin/armature.
- Uses the supplied 1024x1024 Beelstarmon texture directly.
- Adds two appended chest deform bones and layers the requested **x5 breast secondary motion** over the imported animation clips.


## Naruto fresh Mixamo remake (v2.8.61)
- Added **Naruto** back as a completely new character built from the supplied `Standing Idle`, `Run`, and `Jumping` FBXs.
- Uses the shared 52-bone Mixamo deform rig from the new FBXs rather than the removed legacy Naruto armature.
- Runtime uses the supplied idle/run/jump animation clips with smooth idle-to-run and locomotion-aware jump blending.
- Uses `nrt_tex03.png` for both Naruto body material slots and `base00.png` as the default eye material; the additional supplied eye/expression frames are retained under `source/naruto/`.


## Naruto orange-material correction (v2.8.61)
- Split the new Naruto FBX body materials instead of forcing both through `nrt_tex03.png`.
- Material 0 now uses `nrt_tex01_orange_rebuilt.png`, preserving the supplied sheet detail while restoring the predominantly orange Naruto outfit.
- Material 1 keeps `nrt_tex03.png` for skin/headband/accessory details; eyes continue to use `base00.png`.
- Naruto's distance-locked run cycle was shortened from 38 to 27 world pixels per animation cycle, making the imported Run clip play about 41% faster without changing gameplay movement speed.


## Fresh Aang replacement (v2.8.61)
- Replaced the previous Aang model/rig with the user-supplied **Aang (Title Screen)** Mixamo package.
- New Aang uses the supplied `Standing Idle.fbx`, `Running.fbx`, and `Jumping.fbx` clips directly.
- Rebuilt Aang from four skinned mesh parts with the supplied 256x256 texture; the old DAE/OBJ Aang source and converter are no longer shipped.


## Shrek shirt-hem texture-slot fix (v2.8.63)

- Fixes the green strip showing along the bottom of Shrek's shirt by mapping the extra trim/accessory body mesh to the body texture instead of the head texture.
- Keeps the replacement Shrek model, idle/run/jump animations, and head setup intact.

## Naruto blinking + Shrek replacement refresh (v2.8.62)
- Naruto now has a real runtime blink by swapping between the regenerated open-eye and closed-eye atlases built from the supplied eye textures.
- Shrek is no longer the previous procedural OBJ/Red-animation build; the SHREK slot is now regenerated from the newly provided rigged Mixamo FBXs (Idle, Slow Run, Mutant Jumping) plus the newly supplied body/head texture set.
- Source assets for the replacement Shrek are stored under `source/shrek/`, and the new runtime asset build is reproduced with `tools/convert_shrek_mixamo.py`.

## Fresh CJ replacement (v2.8.64)
- Completely replaced the previous procedural/OBJ CJ runtime model with the newly supplied GTA SA rigged FBX set.
- New CJ uses `Neutral Idle.fbx` as the skinned base plus the supplied `Running.fbx` and `Jumping (1).fbx` clips.
- Preserves the original GTA material split with separate upper-body, head, shoes, and legs textures.
- Uses the full 58-bone GTA skeleton (including facial/eyelid/eyebrow bones) and 1,630 skinned positions / 2,671 skin influences / 2,304 triangles.
- Keeps the character ID `CJ`, so the existing CJ gameplay controls and pistol hooks remain attached to the replacement character, while the new rig uses its own embedded animation profile instead of the old procedural gait.

## Yami character (v2.8.65)
- Added **Yami** as a new Skin Selector character without replacing Yugi Muto or any existing character.
- Uses the supplied `Standing Idle.fbx`, `Running.fbx`, and `Jump.fbx` directly on their shared 127-bone character rig.
- Runtime exports the normal `chr0400_form0` body plus `chr0400_facial1` face mesh while intentionally excluding the overlapping damage-shell meshes.
- Uses the supplied skin, two clothing, weapon, hair, eye, lens, and eyeshadow color textures in a generated 4096x2048 material atlas.
- Converted model contains 29,320 weighted positions, 58,857 skin influences, and 49,136 triangles.

## Performance pass (v2.8.66)
- Lossless indexed render buffers reduce duplicate per-frame vertex updates by about **68% across the complete roster** without deleting triangles.
- Yami is the largest win: **147,408 -> 29,320** render vertices updated per frame while keeping all 49,136 triangles.
- Skinning now has optimized one-/two-weight fast paths.
- Excessively dense idle/jump clip data is resampled with duration preserved and runtime interpolation unchanged.
- Only the oversized Yami and Ash atlases were reduced; all other runtime texture resolutions are unchanged.
- Run `python tools/optimize_runtime_assets.py` after regenerating FBX/DAE-derived assets.

## BelleStarmon character (v2.8.67)
- Added **BelleStarmon** as a new Skin Selector character without replacing any existing character.
- Uses the supplied `Neutral Idle.fbx`, `Fast Run.fbx`, and `Jumping (1).fbx` on the 52-bone Mixamo deformation rig.
- Uses the supplied 1024x1024 `beiersitashou_base.png` texture as the runtime diffuse atlas.
- Runs through the v2.8.66 compact indexed renderer optimization so the new model does not restore the old duplicate-corner per-frame cost.

## Live Skin Selector model viewer (v2.8.68; superseded by v2.8.70)
- Introduced the proven true-color off-screen Voxel3D portrait path from `STADIUM_UI_MODEL_VIEWER`.
- v2.8.70 keeps that working 3D render path but removes v2.8.68's custom 160x144 selector drawing so Gen 1 Modern UI can own the actual menu presentation.

## Shrek cleanup + BelleStarmon catwalk (v2.8.69)
- Restores Shrek's untouched body diffuse while retaining the corrected body/head mesh material routing.
- BelleStarmon now uses `Catwalk Walk Forward HighKnees.fbx` for walking, with a slower authored cadence.
- BelleStarmon jump playback is eased and slowed, and her manual jump lasts 42 frames instead of the global 30-frame cosmetic jump.


## Self-contained modern Skin Selector UI (v2.8.72)

- The Skin Selector no longer requires **Gen 1 Modern UI** to get the clean high-resolution layout.
- Added a built-in responsive dark-glass selector with a high-resolution character list, active-skin badge, controller hints, and the existing live 3D portrait.
- The underlying Gen1Recomp `ListMenu` still owns Up/Down/A/B input and callbacks, so this remains compatible with the normal game state system.
- The 3D portrait now renders up to **1152x1280** before downsampling into the preview card for sharper desktop output.
- If Gen 1 Modern UI is installed, it is no longer a dependency for this screen; the Skin Selector uses its own consistent presentation either way.

## Gen 1 Modern UI + HD Skin Selector viewer (v2.8.70)

- Removed the Skin Selector's custom 160x144 `ListMenu:draw()` override. This lets installed `gen1_modern_ui` builds recognize the selector as a normal live `ListMenu` and render it with the user's selected Modern UI theme/frame/font/layout.
- Moved the 3D portrait to a separate `render.hud` pass that runs after Gen 1 Modern UI. The selector still owns only the character list/input; Modern UI owns the themed menu presentation.
- Raised the model portrait from the old 128x128 off-screen scene / 64x66 Game Boy display rectangle to an adaptive 512-900 x 640-1000 true-color render target drawn directly at window resolution.
- The preview is supersampled, uses linear filtering only for the final 3D portrait canvas, keeps the working PaletteFX bypass, and still reuses the optimized indexed meshes.
- Left/Right rotates the highlighted model; Up/Down changes the highlighted character; A selects; B backs out.
- Gen 1 Modern UI is optional. Without it, the selector remains a standard native `ListMenu`; the HD portrait HUD is only added when Modern UI is present.

## BelleStarmon analog locomotion (v2.8.71)
- Light left-stick input uses the supplied Catwalk walk animation.
- Full left-stick input uses the supplied Fast Run animation.
- Intermediate stick pressure smoothly crossfades between walk and run while the normal movement blend handles idle-to-locomotion transitions.
- Keyboard/D-pad movement uses Fast Run.


## Battle Stadium D.O.N. Zoro replacement (v2.8.73)
- Removed the previous OBJ/auto-rig Zoro implementation from the active ZORO slot.
- Replaced it with the supplied **Battle Stadium D.O.N.** rigged Zoro FBXs and original PS2 texture set.
- Uses `Unarmed Idle.fbx`, `Fast Run.fbx`, and `Jump.fbx` as authored embedded animations.
- New runtime model contains **52 deform bones, 1,397 skinned positions, 3,536 skin influences, and 2,618 triangles**.
- Preserves all five supplied material groups (`face1`, `tex1`, `tex2`, `tex3`, `tex4`) through a padded generated atlas.
- The new source is Z-up, so the ZORO slot now uses the post-skin Z-up conversion and no longer needs the old 180-degree facing correction.
