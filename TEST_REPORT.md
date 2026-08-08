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
