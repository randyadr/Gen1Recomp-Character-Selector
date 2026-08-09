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
