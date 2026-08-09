# Skin Selector v2.8.72 — self-contained modern UI

The Skin Selector no longer depends on Gen 1 Modern UI.

## Architecture

- Gen1Recomp `ListMenu` remains the source of truth for cursor movement, A/B actions, sounds, closing, and selection callbacks.
- `render.hud` runs after the native HUD and paints a responsive high-resolution modal over the classic 160x144 menu.
- The overlay is implemented entirely inside the Character Selector mod using LÖVE primitives and runtime fonts; no external UI assets or UI mod are required.
- The live 3D portrait continues to use the proven transparent Voxel3D off-screen render + PaletteFX bypass path.
- Portrait render size is adaptive and capped at 1152x1280, then downsampled once into the preview panel.

## Result

Users only need this character-selector mod (plus Dramatic Shape if they want the 3D world renderer). Gen 1 Modern UI can be absent or disabled and the Skin Selector still gets the clean modern layout and HD 3D viewer.
