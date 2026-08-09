# v2.0.0 Build Test Report

- Red runtime asset retained: 107-bone / 5,978-position skinned model.
- Yugi conversion rebuild: **PASS** and deterministic byte-for-byte.
- Yugi runtime asset: **27 bones, 2,111 weighted positions, 2,095 triangles**.
- Yugi source textures packed into a clamped atlas with half-pixel UV inset.
- Character selector screen registered as `RED3D_CHARACTER_SELECTOR`.
- Pause/start-menu event adds **Character Selector**.
- Selection persists through mod options/save state and switches the active renderer immediately.
- Dramatic Shape bridge uses an active-renderer proxy, so overworld, shadow, reflection and battle passes follow the selected character without reinstalling the pipeline.
- Battle pointing timer no longer keys off Dramatic Shape's changing battle token; the pose timer starts once when the trainer card appears.

Runtime note: this environment does not contain a complete Gen1Recomp + ROM runtime, so final in-game visual verification remains the user's test. The generated assets and selector wiring were structurally checked and the Yugi converter was rebuilt deterministically.
## v2.7.4 real terrain-fracture validation

- `main.lua` and every packaged Lua source pass `texluac -p`.
- Destruction capture occurs before `Map:setBlock`, so pre-destruction terrain geometry is still available.
- The active Dramatic Shape terrain mesh is modified only through its vertex map; unselected triangles remain in the same GPU mesh while the replacement is asynchronously rebuilt.
- Captured triangle vertices are recentered into per-piece local meshes without changing UV or VertexShade attributes, so local-to-world reconstruction at frame zero is exact by construction.
- Ground-level geometry is excluded from the fracture selection so the world floor remains stable while raised environment geometry breaks apart.


## v2.7.5 fracture / aiming validation

- `ActiveRenderer` now retains `voxelBridge` and `voxelChunkMesher` on the proxy itself, so changing from Red/Yugi/etc. to CJ cannot silently drop the exact Dramatic Shape fracture dependencies.
- Live-terrain triangle classification is pre-indexed incrementally while CJ is active; the impact path no longer performs `getVertex()` across the entire terrain mesh.
- A full mutable terrain vertex map is prepared before firing. Impact hides selected source triangles in-place by making only their three index slots degenerate, avoiding a map-sized index-list allocation at shot time.
- Every exact debris mesh stores the source terrain texture object and exact source `u/v/shade` values. The terrain atlas captured from Dramatic Shape's current draw pass is the fallback if the source mesh has not retained its texture yet.
- CJ ADS now uses a placed, collision-aware over-the-shoulder camera and a squared right-stick response. The aim-facing correction is applied after the normal player update, so vanilla movement no longer overwrites CJ's gun direction on the same frame.
- All packaged Lua files pass `loadfile()` under LuaTeX's Lua runtime.

## v2.8.1 Aang battle-armature / Cloud-name validation

- All packaged Lua sources plus `mod.card` pass `loadfile()` under LuaTeX's Lua runtime.
- Aang's generated 24-bone weighted model data is unchanged; the fix is isolated to the battle-intro pose layer in `main.lua`.
- Offline skeleton reconstruction confirms the old generic battle transform raised both Aang hands above his head at the start of the intro. The new Aang-specific local-Z arm rest places both hands below the shoulders before the point begins.
- At the completed point pose, the left arm remains relaxed while the right arm reaches roughly shoulder height and forward in depth, with the elbow using Aang's mirrored local-Z hinge instead of Red's local-Y hinge.
- Current user-facing selector/mod-option/mod-card text uses **Cloud**. The original `Wind-Up Cloud.dae/.fbx` source filenames and generated-source comments are intentionally retained so rebuild tooling still refers to the actual supplied files.
- Runtime note: this environment does not include the user's full Gen1Recomp + Dramatic Shape game setup, so final camera/lighting visual verification still needs an in-game launch.

## v2.8.2 Skin Selector pause-shortcut validation

- Renamed the pause/start-menu shortcut to **Skin Selector** and the selector screen title to **SKIN SELECTOR**.
- Preserved the documented `ui.start_menu.items` contract: mutate the incoming list, then return `next(game, items)`.
- Added best-effort paused-overlay compatibility wrappers for common host hook names. Unknown hook names are ignored safely.
- Compatibility insertion recognizes table, tuple, and common label/callback field shapes.
- Ordering rule is **MOD MENUS → Skin Selector → MODS** when both anchors are present; if only MODS is present, Skin Selector is inserted immediately before it.
- Existing Character Selector/Skin Selector rows are treated as duplicates, so the shortcut is not inserted twice.
- v2.8.1 Aang battle-armature corrections and Cloud naming changes remain intact.

### v2.8.2 mocked menu-format results

- `{ label=... }`: PASS — `MOD MENUS → Skin Selector → MODS → QUIT`.
- `{ text=... }`: PASS — `MOD MENUS → Skin Selector → MODS → QUIT`.
- tuple `{ "LABEL", callback }`: PASS — `MOD MENUS → Skin Selector → MODS → QUIT`.
- legacy `Character Selector` duplicate: PASS — renamed in place to `Skin Selector`, no duplicate row.
- Lightweight delimiter scan of `main.lua`: PASS.

## v2.8.3 top-level Skin Selector hook-order validation

- Root cause reproduced with a mock hook chain: a downstream menu mod that returns a replacement list can erase a row inserted before `next()`.
- The fixed wrapper runs at `math.huge`, calls `next(game, items)` first, then injects into the final returned list.
- Replacement-list mock: PASS — Skin Selector survives a downstream MOD MENUS/Cheat Menu list rebuild.
- Final ordering with the screenshot-style rows: PASS — `MOD MENUS → Skin Selector → Cheat Menu → MODS → QUIT`.
- Vanilla-style list without MOD MENUS: PASS — `... → Skin Selector → MODS → QUIT`.
- Duplicate legacy `Character Selector` row: PASS — normalized to `Skin Selector` with no duplicate.
- All packaged Lua files plus `mod.card` pass Lua syntax validation.
- ZIP integrity and manifest version checks pass.



## v2.8.4 Aang overworld-armature validation

- The remaining Aang issue was traced to the **upper-arm rotation order** in the AANG-specific movement/jump paths, not the battle timer or selector hook.
- Updated AANG upper-arm transforms so the arm-drop rest matrix is applied before the swing/reach rotation in local space.
- This change covers overworld walk, manual jump, and the Dramatic Shape battle pointing pose paths.
- Lua syntax and packaged ZIP integrity checks passed.

## v2.8.5 Aang hard-guard simulation

- Parsed the packaged `data/aang_model.lua` bind hierarchy and reproduced the runtime row-major matrix multiplication.
- Known-good Aang relaxed pose places both hands around Y=8.8 with the head around Y=17.0.
- Reversing the arm signs reproduces the user's screenshot class of failure, placing both hands around Y=19.1 above the head.
- Added final-stage overrides for L/R upper arms and forearms in both `Renderer:updateSkeleton` and `Renderer:updateBattleSkeleton`, so no earlier animation branch can reintroduce the overhead pose.
- Aang's battle pointing animation is intentionally suppressed in this build in favor of a stable arms-down stance.

## v2.8.6 character persistence validation

- Reproduced the bug in the old startup precedence: a globally stored `character_3d = AANG` wins even when `selected_character_3d` in the save is another valid skin.
- Reversed startup precedence so the per-save selected skin wins.
- Tested all seven valid character IDs against a stale Aang global option.
- Tested missing/invalid save values and verified fallback to the option, then Red.

## v2.8.7 persistence + baked Aang arm validation

- Startup no longer consumes stale global character option state before restoreSave.
- `save.loaded` now re-selects the saved per-game character.
- Aang upper-arm drop is baked into boneLocal 17/21; runtime upper-arm rest is identity.
- Final hierarchy simulation verifies hands remain below head/shoulders in the packaged bind pose.

## v2.8.9 persistent 360-degree body-facing simulation

Simulated the visual-facing state machine used by `Renderer:voxelModelMatrix`:

- Enter 3RD facing south, stand still: retained yaw initializes to south.
- Move northeast: retained yaw follows the continuous Dramatic Shape `bodyYaw`.
- Release movement and rotate the camera through multiple headings: retained/model yaw stays northeast instead of returning to camera-forward.
- Resume movement west: retained/model yaw immediately changes west.
- Leave free-roam or lose `bodyYaw`: retained yaw clears and ordinary `p.facing` resumes.
- CJ ADS still overrides the retained yaw while aiming.

This targets only the selected 3D model's visual orientation; collision, interaction facing, map scripts, and Dramatic Shape's camera-relative movement remain owned by the host.

## v2.8.11 Shrek texture + arm rig validation

- Source OBJ material UV audit: both Shrek materials use negative V coordinates (`-1..0`). The new converter maps them into the complete runtime atlas instead of clamping them to one row.
- Generated runtime UV span: U ~0.0024..0.9972, V ~0.0044..0.9979, with 3,397 distinct rounded V samples.
- Arm weighting now covers 1,725 positions across shoulder, upper-arm, forearm, and hand bones.
- Focused skeleton simulation moves 1,586 arm-weighted positions by more than 0.02 units, with maximum displacement ~0.148 units.
- The focused test leaves non-arm torso vertices stationary, confirming the new arm weights do not drag the vest/torso with the limbs.

## v2.8.12 Shrek rig / atlas validation

- Updated Shrek to use a 72-degree runtime arm rest so his source spread-arm pose no longer appears unrigged in-game.
- Rebuilt the Shrek runtime atlas with alpha-bleed padding to remove black fringe / dark texture contamination from transparent source background pixels.
- Regenerated `data/shrek_model.lua` and `assets/shrek_atlas.png`; packaged ZIP integrity passed.

## v2.8.13 Shrek UV validation

- Compared both candidate mappings against the original OBJ and diffuse textures.
- `1 + v` reproduces the broken vertically flipped texture islands.
- `-v` reconstructs the expected green skin, cream shirt, brown vest, plaid pants, boots, and face placement.
- Runtime Shrek model data was regenerated from the corrected converter.

## v2.8.14 Shrek arm-rest validation

- Reduced Shrek runtime `armRestDeg` from 72 to 0 because his source mesh is already posed with the arms hanging outward/down.
- This prevents the runtime from folding the arms behind the body at idle.
- ZIP integrity checks passed for both release and repo-ready packages.

## v2.8.15 Shrek Red-style animation validation

- Reconfigured Shrek to use the same default Red animation path rather than the `GENERIC` profile.
- Set Shrek `armRestDeg` to 36 so his source pose aligns better with Red-style arm swing and idle posture.
- Release ZIP and repo-ready ZIP integrity checks passed.

## v2.8.16 Shrek full-body Red-style animation

- Added a dedicated `SHREK_RED` animation profile.
- Shrek now receives Red-style whole-body motion for hips, waist, spine, neck/head, shoulders, arms, hands, and legs, with torso/head amplitudes damped for his larger build.
- ZIP integrity checks passed.

## v2.8.17 Shrek gait simulation

- The previous SHREK_RED walk used Red local-Y thigh/knee rotations on Shrek's world-aligned procedural skeleton. Simulation showed this rotates the legs sideways instead of fore/aft.
- Dedicated Shrek walking now uses local X pitch for thighs/knees/feet and local X fore/aft swing for the arms, with reduced amplitudes for Shrek's proportions.
- Full 12-pose skeleton simulation was completed before packaging.
- ZIP integrity checks passed.

## v2.8.18 Shrek arm-profile validation

- Added dedicated `SHREK_RED` arm rest/swing tuning so Shrek's upper arms rotate inward and his forearms/hands follow a milder Red-style motion.
- Added matching `SHREK_RED` jump-arm branches for upper arms and forearms.
- Release ZIP and repo-ready ZIP integrity checks passed.

## v2.8.19 True Directional Movement validation

- Body yaw is calculated from the actual camera-space move vector rotated into world space, not from Dramatic Shape's standing `bodyYaw`.
- Simulated cardinal and diagonal inputs at multiple camera yaws; the computed body bearing matches travel direction continuously.
- Simulated move -> release -> camera orbit; the retained model yaw remains unchanged until movement resumes.
- CJ ADS remains an explicit body-yaw override.
- Release and repo-ready ZIP integrity checks passed.

## v2.8.20 true-directional movement validation

- Model yaw now comes from consecutive world-space player positions (`px`,`py`) rather than Dramatic Shape `bodyYaw`.
- Continuous `atan2(dx,dz)` yaw supports arbitrary 360-degree travel angles and is retained at rest.
- Same-frame shadow/model matrix calls do not clear the retained direction.
- Large movement discontinuities are ignored as probable warps.
- ZIP integrity checks passed for release and repo-ready packages.

## v2.8.21 CJ shooting crash guard

- Exact live terrain vertex-map fracture is disabled by default (`cjExactTerrainFracture=false`).
- CJ shot dispatch is protected with `pcall`; world debris and block destruction are individually protected too.
- Release and repo-ready ZIP integrity checks passed.

## v2.8.22 CJ trigger crash isolation

- CJ trigger path no longer invokes live terrain Mesh/vertex-map mutation.
- Terrain-fracture prewarm removed from the CJ update path.
- Whole `fireCJShot()` callback is protected by `pcall`.
- Trigger-time MP3 decode replaced by cached generated audio.
- ZIP integrity passed for release and repo-ready packages.

## v2.8.23 Red scale validation

- Red render height changed from 27 to 20.25, exactly 75% of the previous value.
- Other character definitions were left unchanged.
- Release ZIP and repo-ready ZIP integrity checks passed.

## v2.8.24 Red scale validation

- Red height changed from `20.25` to `15.1875`, exactly 25% smaller than v2.8.23.
- Other character definitions were left unchanged.
- ZIP integrity checks passed.

## v2.8.25 Red scale / run validation

- Red render height: `18.984375` (25% larger than v2.8.24).
- Red now uses an isolated `RED` runtime animation profile.
- Run gait receives Red-only stride, knee, foot, toe, arm, torso, lean, and head-motion tuning.
- ZIP integrity checks passed for both packages.

## v2.8.26 Red longer-stride run tuning

- Increased Red-only run amplitudes for thighs, knees, feet, toes, arms, elbows, and wrists.
- Increased Red-only torso lean, bob, and twist slightly to match the longer stride.
- Release ZIP and repo-ready ZIP integrity checks passed.

## v2.8.27 Red ground-contact tuning

- Reduced Red-only gait bob to 46% of the previous value.
- Reduced Red waist vertical translation to 28% of the damped bob and hip translation to 5%, keeping the feet visually closer to the world ground plane during the long-stride run.
- Preserved v2.8.26 long-stride limb amplitudes.
- Release ZIP and repo-ready ZIP integrity checks passed.

## v2.8.28 Red GTA-style fast walk

- Red-only gait cycle length: 42 world pixels (other characters remain at the shared 30-pixel cycle).
- Red retains the same movement/root speed; only animation cadence and pose amplitudes change.
- Reduced knee lift/vertical bounce and increased counter-sway for a grounded walking silhouette.
- ZIP integrity checks pass.

## v2.8.29 Red relaxed-arm walk

- Added Red-only shoulder, upper-arm, elbow and wrist walk tuning to prevent rigid straight-arm motion.
- Preserved v2.8.28 cadence and grounded leg tuning.
- ZIP integrity checks passed.

## v2.8.30 Red arm + Naruto ninja-run validation

- Restored an arm-down rest rotation for Red's upper arms so his motion no longer falls back to a T-pose-like bind state.
- Added a dedicated moving Naruto ninja-run branch with forward torso lean and backward-swept arms using Naruto's rig-specific axes.
- Release ZIP and repo-ready ZIP integrity checks passed.

## v2.8.31 armature simulation validation

- Expanded Red's `animBone` map from the partial limb set to include torso, shoulder, hand, head, and toe joints used by the light-jog controller.
- Simulated Red at phases 0.00, 0.25, 0.50, and 0.75 in front/side projections using the generated model's real bind matrices.
- Solved Naruto's shoulder/arm/forearm ninja-run pose numerically against the real SMD hierarchy, then simulated the complete gait at the same four phases.
- Naruto's hands remain behind the hips throughout the simulated cycle; Red's arms remain down and bent with alternating jog pump.
- Release ZIP and repo-ready ZIP integrity checks pass.

## v2.8.32 Red light-jog + Naruto ninja-run retune

- Simulated the current Red and Naruto armatures and adjusted the moving-profile transforms from those observations.
- Red: reduced upper-arm amplitude, softened elbow flex, and reduced wrist follow-through for a more natural jog.
- Naruto: increased torso lean and set the shoulder/arm chain to a straighter horizontal rearward pose.
- Release ZIP and repo-ready ZIP integrity checks passed.

## v2.8.33 Naruto arm visibility / ninja-run validation

- Re-solved Naruto shoulder rotations from the current SMD bind hierarchy instead of applying the previous large Z-roll.
- Simulated bind-chain endpoints place the left/right hands around x=+/-10, y~91.7, z~-35.5 while shoulders remain around x=+/-8, y~95.8, z~-4.8, producing a visible rearward near-horizontal arm line.
- Release ZIP and repo-ready ZIP integrity checks passed.

## v2.8.34 Naruto rear-view arm fix

- Numerically solved the Naruto shoulder/upper-arm/forearm chain against the runtime bind matrices.
- Simulated hands stay outside the body and at shoulder height behind the hips rather than intersecting the pelvis.
- Release ZIP and repo-ready ZIP integrity checks pass.

## v2.8.35 Beelstarmon procedural rig validation

- Parsed the supplied binary FBX 7.4 mesh and UV layer directly.
- Generated a 26-bone runtime armature with dedicated LBreast/RBreast secondary bones.
- 17,130 source positions / 23,715 runtime triangles converted.
- Beelstarmon added to Skin Selector and character order.
- 5x chest secondary-motion profile added for movement and jump phases.
- ZIP integrity checks passed.

## v2.8.36 Beelstarmon rig / secondary-motion validation

- 31-bone Beelstarmon procedural rig: body + left/right chest + 2 hair + 3 cape bones.
- Chest weighted region mean is approximately Y=1.67, Z=-0.16, correcting the previous upper-abdomen placement.
- HairRoot/HairTip and CapeTop/CapeMid/CapeBottom have dedicated mesh influences.
- Hand/forearm and lower-leg/foot weighting was tightened for cleaner elbows, wrists, knees and planted feet.
- Beelstarmon character config now includes a 180-degree yaw offset to correct backwards walking.
- ZIP integrity checks passed for both packages.

## v2.8.38 Beelstarmon skinning recovery

- Restored the last intact 31-bone Beelstarmon model from v2.8.36 after v2.8.37 shifted existing skin indices.
- Verified Beelstarmon `infBone` values remain within the valid 31-bone range.
- Applied leg-walk improvements without adding/removing/reordering bones.
- Release ZIP and repo-ready ZIP integrity checks passed.

## v2.8.39 Beelstarmon jump + hair validation

- Removed Beelstarmon-specific downward Waist/Hips jump translation so her mesh stays centered on the real airborne player position.
- Added Beelstarmon-specific world-axis jump motion for limbs.
- Increased two-stage HairRoot/HairTip lag during movement and takeoff/landing.
- ZIP integrity checks passed for both packages.

## v2.8.40 Beelstarmon cape-cloth simulation pass

- Simulated Beelstarmon's cape chain and increased top/mid/bottom cloth lag progressively.
- Added more visible rearward trail, lower-section sway, and stronger jump follow-through.
- Release ZIP and repo-ready ZIP integrity checks passed.

## v2.8.42 Beelstarmon real cloth-rig pass

- Expanded Beelstarmon cape coverage from 4,556 to 6,072 skinned positions.
- Expanded cape influences from 6,426 to 9,990.
- Added six side-tail cloth bones at the end of the skeleton, preserving all original body bone indices.
- Added stateful spring/damping cape motion with movement acceleration and stopping inertia.
- Simulated the actual weighted cape mesh across start, steady movement, and stop phases before packaging.
- Converter syntax, manifest JSON, and ZIP integrity checks pass.

## v2.8.42 functional knee rig

- Appended left/right knee deform joints after the existing 37-bone rig.
- Reweighted the knee/upper-shin transition and retuned walk/jump knee flex.
- Package integrity checks passed.

## v2.8.43 Ash Ketchum embedded-run validation

- Parsed the supplied binary FBX directly and preserved its exact cluster skinning.
- Detected the looping Mixamo Slow Run clip: 44 keys, 60 Hz key spacing, 0.7166667 s duration, with matching first/last rotation keys.
- Converted 52 weighted bones, 3,819 control-point positions, 9,124 skin influences, and 7,288 triangles.
- Root X/Z translation is intentionally discarded so the game controls movement; Hips vertical motion and all source rotations are retained.
- ZIP integrity checks passed for both package layouts.

## v2.8.44 Ash texture / idle / jump validation

- Fixed body negative-V UV mapping and face negative-U wrapping from the source FBX.
- Imported `source/ash/Standing Idle.fbx` on the same 52 deform-bone runtime skeleton.
- Standing Idle: 344 keys / ~5.7167 s; Slow Run: 44 keys / ~0.7167 s.
- Added smoothstep idle/run transitions and a zero-at-endpoints jump overlay for seamless takeoff/landing blending.
- Weighted-mesh simulation across idle, run transition, airborne pose, landing, and stop stayed within sane model bounds.
- Release and repo-ready ZIP integrity checks passed.

## v2.8.45 Beelstarmon fresh-rebuild reset
- Rebuilt `beelstarmon_model.lua` and `beelstarmon_atlas.png` from the clean original mesh plus the newly supplied texture.
- Staged the newly supplied Beelstarmon source animation FBXs under `source/beelstarmon/`.
- Preserved existing x5 Beelstarmon breast-secondary-motion behavior in runtime profile.

## v2.8.46 Beelstarmon fresh Mixamo remake
- Verified the new Standing Idle / Fast Run / Jumping FBXs share the same 12,368-vertex mesh, 65-node Mixamo source skeleton, and single-material UV layout.
- Generated a 54-bone runtime skin (52 deforming imported bones + LBreast/RBreast).
- Validated clip array lengths against all frame counts and bones.
- 950 mesh positions receive localized chest secondary-motion weighting.
- Python converter passes `py_compile`.

## v2.8.47 Beelstarmon x10 secondary motion + locomotion jump
- Added appended LButt/RButt deform bones and localized rear-pelvis weights without shifting the imported Mixamo skeleton indices.
- Doubled chest run/jump secondary-motion amplitude from the prior x5 pass to x10.
- Added x10 side-phased buttock secondary motion.
- Jump blending now preserves Fast Run locomotion in the hips/legs while crossfading the authored Jumping clip over it.

## v2.8.48 Beelstarmon secondary-motion cleanup
- Removed both buttock physics bones and all buttock-specific vertex weighting.
- Doubled Beelstarmon chest secondary-motion amplitudes from x10 to x20.
- Preserved locomotion-aware run/jump blending.
- Package integrity checks passed.

## v2.8.49 Naruto removal

- Naruto removed from active character config/order/selector.
- Naruto runtime model, atlas, source assets, and converter removed from the package.
- Historical test entries remain as archive text only.

## v2.8.50 Naruto fresh Mixamo remake
- Converted the supplied Naruto Standing Idle FBX as the new mesh/skin base.
- Imported Standing Idle (361 frames / 6.0 s), Run (39 frames / 0.6333 s), and Jumping (114 frames / 1.8833 s) onto the shared 52-bone deform skeleton.
- Generated 1,848 skinned positions, 4,808 skin influences, and 3,408 triangles.
- Mapped body materials 0/1 to the supplied `nrt_tex03.png` atlas and the eye material to `base00.png`; additional expression textures are retained in source.
- Added smooth idle/run and locomotion-aware jump blending for the new `NARUTO_MIXAMO` runtime profile.

## v2.8.51 Beelstarmon x30 chest secondary motion

- Increased Beelstarmon chest secondary-motion amplitudes from x20 to x30 (1.5x).
- Buttock secondary-motion bones/weights remain absent.
- Naruto and Beelstarmon locomotion-aware jump blending were not changed.
- Release ZIP and repo-ready ZIP integrity checks passed.

## v2.8.52 Naruto facing + baked texture validation
- Naruto model yaw offset changed to pi radians to correct backward-facing locomotion.
- Naruto atlas rebuilt as isolated per-triangle cells with edge extrusion to avoid UV/material bleed.
- Imported idle/run/jump clips remain present after rebuild.

## v2.8.54 Naruto orange material + faster run
- Rebuilt Naruto atlas with separate body material slots: orange reconstructed material 0, supplied `nrt_tex03.png` material 1, and `base00.png` eyes.
- Naruto run gait distance reduced from 38 to 27 world pixels per cycle (~40.7% faster cadence) without changing player movement speed.
- Package ZIP integrity validated for direct-install and repo-ready builds.

## v2.8.61 renderer/headband/leg-seam pass
- Verified Dramatic Shape custom draw path explicitly sends `Voxel3D.glass(false)` before custom character meshes.
- Naruto headband correction is localized to the forehead-plate UV strip; no global face-texture flip.
- Naruto regenerated with 100 side-specific lower-body seam positions to remove cross-leg skin contamination.
- ZIP integrity tests passed.

## v2.8.61 fresh Aang replacement validation
- New Aang converter completed with 4 geometries / 52 bones / 2,172 positions / 5,345 influences / 4,114 triangles.
- Imported clip data: idle 361 frames (6.0s), run 28 frames (0.45s), jump 71 frames (1.1667s).
- Weighted-mesh idle/run/jump simulation completed without skeleton blow-up.
- Old `source/aang` DAE/OBJ model files and `tools/convert_aang_dae.py` were removed.

## v2.8.64 fresh CJ replacement
- 58 runtime bones, 1,630 positions, 2,671 influences, 2,304 triangles.
- Animation arrays validate exactly: idle 284 frames, run 43 frames, jump 250 frames.
- All influence bone indices are within 1..58 and per-position weights sum to ~1.0.
- Weighted-mesh idle/run/jump simulation completed without NaN/Inf or skeleton blow-up.

## v2.8.65 Yami validation
- Generated Yami data: 127 bones, 29,320 positions, 58,857 skin influences, 49,136 triangles.
- Animation arrays imported at 361 idle frames, 43 run frames, and 156 jump frames.
- Weighted-mesh simulation stayed finite across sampled idle/run/jump frames; no armature explosion was observed.
- Runtime atlas is 4096x2048 and maps the supplied Yami diffuse material set.

## v2.8.66 optimization validation
- Triangle topology unchanged for every character.
- Total runtime render-vertex update set: 270,432 -> 85,326 unique position/UV vertices (68.4% reduction).
- Yami: 147,408 -> 29,320 update vertices with all 49,136 triangles retained.
- Embedded clip array lengths validated against `boneCount * frameCount * 16` for all imported animation models.
- Combined generated model-Lua footprint: ~44.39 MiB -> ~33.41 MiB.
- Yami atlas estimated RGBA GPU footprint: 32 MiB -> 8 MiB. Ash: 20 MiB -> 11.25 MiB.
- Atlas downscale preview SSIM: Yami ~0.993; Ash ~0.998.
