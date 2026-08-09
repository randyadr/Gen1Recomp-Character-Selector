# Skin Selector Live Model Viewer (v2.8.70)

The Skin Selector now uses the same off-screen true-color Voxel3D technique that made `STADIUM_UI_MODEL_VIEWER` reliable, but it no longer replaces the Skin Selector's menu renderer.

## Modern UI integration

1. The selector state is an ordinary Gen1Recomp `ListMenu` with no per-instance `draw()` override.
2. Because the state remains structurally standard, `gen1_modern_ui` can recognize it as a supported list and render its normal themed high-resolution menu.
3. This mod registers a `render.hud` wrapper at `math.huge`, calls the rest of the HUD chain first, and only then draws the 3D portrait. Gen 1 Modern UI therefore finishes its themed screen before the portrait card is added.
4. If Gen 1 Modern UI is not installed, the selector stays a usable native `ListMenu`; the HD portrait companion is intentionally not drawn over the classic 160x144 screen.

## High-resolution render path

1. Reuse the already-loaded selected character `Renderer` and its optimized indexed Voxel3D mesh.
2. Animate the highlighted character's authored idle pose and skin the current weighted positions.
3. Render into an adaptive true-color off-screen scene (normally 512-900 px wide and 640-1000 px high) with `Voxel3D.beginScene(...)` / `Voxel3D.endScene()`.
4. Clear the active Game Boy palette shader before that off-screen render.
5. Save and restore LÖVE canvas/shader/color/blend/depth/cull/scissor state and Voxel3D camera/cull/tint/fog/firefly state.
6. Draw the resulting Canvas directly in the full-resolution `render.hud` pass instead of shrinking it into the 160x144 UI and enlarging it again.
7. Use premultiplied alpha for the portrait and linear filtering for the final canvas only. Character source textures and geometry remain unchanged.
8. Invalidate the shared renderer upload keys after UI skinning so the overworld refreshes its own pose when the selector closes.

## Why v2.8.68 looked blocky

The 3D scene was rendered to 128x128 and then drawn into a 64x66 rectangle inside the Game Boy's 160x144 UI canvas. The entire game UI was subsequently scaled to the desktop window, so the portrait was effectively a tiny raster sprite even though the underlying model was high-detail. v2.8.70 removes that downsample step.

## Controls

- Up / Down: highlight a character.
- Left / Right: rotate the 3D preview by 18 degrees.
- Preview also auto-rotates slowly.
- A: select highlighted skin.
- B: back out without changing the current skin.

## Performance

The viewer still reuses the losslessly compacted indexed character meshes and caches the off-screen Canvas between refreshes. Rendering is capped at 30 FPS while the selector is open.
