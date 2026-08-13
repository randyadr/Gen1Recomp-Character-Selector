## v3.0.38 physics smoothing note

Breast physics now uses at most 16 tiny integration substeps per frame for two spring bodies, plus constant-time exponential filters for acceleration, left/right targets, and rendered output. This is a negligible workload relative to skinning/rendering and removes visible frame-jitter sensitivity without allocating per-frame mesh data.

## v3.0.32 Wow native-rig validation

- Wow keeps 26,879 skinned control-point positions / 46,640 triangles but now uses the FBX's original normalized Mixamo skin weights instead of generic proximity weights. Random bind-pose reconstruction checks were within 2.3e-16 model units.
- Idle / Catwalk / Goofy Run clips are downsampled to a bounded 30 Hz embedded animation stream (499 / 38 / 20 frames) while the renderer continues to interpolate between keys. Arm segment lengths were checked across all three clips and remain invariant, eliminating the v3.0.31 stretched-arm failure mode.
- Breast physics adds only two helper bones and 135 localized weighted positions on Wow; the existing 120 Hz two-node spring solver is reused and does no work while Wow PHYSICS is disabled.

## v3.0.31

- Wow's generated 46,640-triangle mesh uses 26,873 unique weighted positions instead of skinning all 139,920 triangle corners independently.
- The same position-deduplication pass now applies to experimental humanoid rigs while retaining separate UVs per render corner.

## v3.0.30 Character Import / rigger notes

- Character source ZIPs are scanned only at startup or on explicit **Scan Character ZIP Folder** requests; auto-weighting is rebuilt only when opening/resetting/updating a rig, not every render frame.
- The improved rigger still caps skinning at four influences per generated vertex. Anatomical gates reduce unrelated candidate bones before normalization, keeping runtime skinning cost equivalent to the v3.0.29 four-weight path.
- Direct marker dragging updates joint coordinates only; expensive weight regeneration remains behind **UPDATE ANIMATED PREVIEW**, avoiding a full mesh re-weight on every mouse-motion event.

## v3.0.29 rigger notes

- Auto-weighting runs only when the rig preview is rebuilt/saved, not every render frame.
- Runtime rigged characters use the same compact skinned Renderer path as built-in characters; the original static import parser is not rerun per frame.
- Each imported triangle corner is initially treated as an independent skinned position for compatibility with arbitrary UV seams. This is intentionally conservative for the first experimental build and can be optimized with position/normal seam welding later.

## v3.0.28 conditional Belle physics control

The Breast Physics slider row is omitted entirely while the master PHYSICS checkbox is off. This is UI-only branching; the saved strength remains intact and no additional runtime physics work is introduced.

## v3.0.27 startup timing stabilization

Animation timing now rejects ultra-short startup movement samples, median-filters measured gait speed, uses a startup grace period, and bounds preview/world animation delta time to prevent cadence spikes.

# v3.0.20 validation note

BelleStarmon visible breast-physics strength was doubled from 0.40 to 0.80 while the 120 Hz solver, movement/impact/idle drive, response timing, damping, target clamps, and spring state remain unchanged. This makes the visible deformation approximately 2x stronger without doubling oscillation frequency or compounding the motion drive.

# v3.0.14 breast-only physics / selector input note

- Removed active thigh spring integration and thigh post-skin surface-follow work; only the two breast spring nodes are updated for BelleStarmon.
- Thigh and butt helper bones remain neutral for skeleton/import compatibility and therefore add no secondary-motion integration cost.
- The hidden physics panel is UI-only state and creates no extra per-frame physics work when closed.
- Controller legends are vector primitives/text drawn with the existing selector HUD pass; no new texture assets are loaded.

# v3.0.13 validation notes

- Selector animation sampler now safely rejects missing bone-key data instead of indexing nil matrices.
- Belle's neutral butt helper bones remain bind-only, with no spring nodes, no surface offset, and no selector control.
- Arcade breast spring remains fixed at 120 Hz with hard displacement/velocity bounds for hitch safety.

# v3.0.12 Import/Export + Physics Region Note

- Imported `.red3dskin` packages are parsed only when the mod starts or the user presses IMPORT; model compilation and render-vertex compaction happen once per newly loaded skin.
- Texture bytes from imported packages are cached on the renderer, so normal frames do not reread package files.
- Buttocks spring nodes and post-skin offsets were removed from BelleStarmon's active secondary-motion update, reducing per-frame spring work.
- Thigh/breast anatomical gates are still computed once when Belle's generated model initializes, not per rendered frame.

# v3.0.11 Simplified Physics Control Note

BelleStarmon's runtime physics remains the direct-target spring solver, but the Skin Selector no longer maintains eleven live physics-control rows. Only three persistent region-enable flags are exposed. The active solver uses one fixed 120 Hz recommended profile, which reduces UI/state branching and prevents legacy save tuning from changing spring behavior.

# v2.8.66 Runtime Optimization Report

This pass focuses on reducing CPU upload work, animation-data memory, and oversized texture memory without deleting model triangles.

## Lossless indexed render-vertex compaction

The renderer now builds one GPU/update vertex per unique `(skinned position, U, V)` tuple and keeps the exact original triangles through vertex maps.

| Character | Previous per-frame render vertices | Optimized | Reduction |
|---|---:|---:|---:|
| Red | 25,623 | 5,978 | 76.7% |
| Yugi Muto | 6,285 | 6,285 | 0.0% |
| Naruto | 10,224 | 10,224 | 0.0% |
| Roronoa Zoro | 10,422 | 2,572 | 75.3% |
| Cloud | 3,846 | 1,398 | 63.7% |
| Aang | 12,342 | 12,342 | 0.0% |
| CJ | 6,912 | 6,912 | 0.0% |
| Shrek | 25,506 | 5,437 | 78.7% |
| Ash | 21,864 | 4,858 | 77.8% |
| Yami | 147,408 | 29,320 | 80.1% |
| **Total** | **270,432** | **85,326** | **68.4%** |

Triangle counts and UV coordinates are unchanged.

## Faster skinning hot path

`Renderer:skin()` now localizes the hot arrays and has dedicated one- and two-influence code paths. This is especially useful for Yami: 22,179 of his 29,320 skinned positions use one or two influences.

## Embedded animation memory

Over-dense idle clips were resampled to at most 180 keys, and long jump clips to at most 140 keys while preserving the original clip durations. Runtime interpolation remains enabled, so animation playback remains continuous.

Combined model-Lua size fell from about **44.39 MiB to 33.41 MiB** (about **24.7% smaller**) with topology unchanged.

## Texture memory

- Yami atlas: 4096x2048 -> 2048x1024, reducing estimated RGBA GPU memory from 32 MiB to 8 MiB.
- Ash atlas: 2048x2560 -> 1536x1920, reducing estimated RGBA GPU memory from 20 MiB to 11.25 MiB.
- Preview-resolution structural similarity: Yami 0.993, Ash 0.998.

Other character atlases were left at their existing resolution.

## Validation

- All model corner indices remain in bounds.
- All triangle counts are unchanged.
- All embedded animation arrays exactly match `boneCount * frameCount * 16` after resampling.
- All four triangle-order lists remain complete and in range.
- Atlas UV coordinates remain normalized and unchanged.

## v2.8.67 BelleStarmon extension

BelleStarmon is added through the same compact indexed renderer. Its 17,485 triangles remain unchanged.

- Previous triangle-corner render vertices: **52,455**
- Compact unique `(position, U, V)` render vertices: **12,368**
- Per-frame render-vertex reduction: **76.4%**
- Updated roster total: **322,887 -> 97,694** per-frame render vertices (**69.7% reduction**)
- BelleStarmon idle keys were resampled from **526 -> 180** while preserving the full **8.75 s** duration and runtime interpolation.
## v3.0.9 fixed-rate physics note

BelleStarmon secondary motion now uses a selected 60/90/120/144/240 Hz fixed timestep with a 16-step catch-up cap. The highest 240 Hz mode performs at most 16 x 6 spring-node updates in one host frame after a hitch, while ordinary 60 FPS play performs four fixed steps per frame. Skin Selector off-screen portrait refresh is capped at 60 FPS.


## v3.0.10 direct-target physics note

v3.0.10 retains the selectable 60/90/120/144/240 Hz control but uses adaptive per-host-frame substeps rather than a fixed accumulator. The newest target is applied directly to every substep. At 60 FPS / 120 Hz this is two 1/120-second spring steps per host frame, restoring the v3.0.8 integration pattern without target smoothing. The per-frame step count is capped at 16 after the existing 50 ms dt clamp.
