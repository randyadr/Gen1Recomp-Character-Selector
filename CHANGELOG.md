## 2.8.9 - 2026-08-08

### 360-degree persistent body facing
- Added **persistent free-body facing** for Dramatic Shape's 1ST/3RD continuous movement. While the player is moving, the selected 3D character still follows Dramatic Shape's exact continuous travel bearing at any angle.
- Releasing movement now **keeps the last body direction** instead of snapping the model back toward the camera. The camera can orbit around a standing character without rotating the character with it, similar to modern third-person directional-movement mods.
- Starting to move in a new direction immediately updates the body bearing again, including diagonals, strafing, and backwards travel.
- Leaving free-roam, entering scripted movement, or returning to normal grid/orbit mode clears the retained bearing so normal Gen1Recomp facing rules remain untouched.
- CJ ADS remains authoritative while aiming; exiting ADS leaves the character at the last aim/body bearing until movement changes it.

### Validation
- Simulated movement → stop → camera-orbit sequences verify the visual yaw remains fixed after input release and changes again only when movement resumes.
- Verified normal non-free-roam fallback still uses `p.facing`.
- GitHub updater metadata remains `randyadr/Gen1Recomp-Character-Selector`.

## 2.8.8 - 2026-08-08

### Distribution / updater
- Added `github: randyadr/Gen1Recomp-Character-Selector` to `manifest.json` for Gen1Recomp index automatic version checks.
- Added a GitHub Actions release workflow that creates an installable ZIP with the mod files at the archive root.
- No gameplay, character rig, selector, or save behavior changed from v2.8.7.

## 2.8.7 - 2026-08-08

### Fixed
- **Character persistence:** the mod entry can run before Gen1Recomp restores the game save. v2.8.7 now listens for the documented `save.loaded` event and applies `mod.save.selected_character_3d` only after the restored save is active.
- Removed the boot fallback to the global `character_3d` option, which could keep forcing a stale Aang selection every launch. New saves default to Red; choosing a skin writes the per-save `mod.save` value.
- Removed the attempted `mod.options:set` call; the public API documents option `define/get` and `mod.options_changed`, while Skin Selector persistence belongs in `mod.save`.
- **Aang arms:** baked the verified arms-down rotation directly into Aang's upper-arm bind matrices. His runtime `armRestDeg` is now zero, so even a path that bypasses the procedural arm guard starts from arms down instead of the source T-pose/upward pose.
- Preserved Skin Selector, Cloud naming, and all other characters/features.

### Validation
- Reconstructed Aang's packaged 24-bone hierarchy from the final `aang_model.lua`: both hands are below the shoulders/head in the baked bind pose.
- Simulated save lifecycle: pre-load starts Red, `save.loaded` restores the saved skin, changing skin updates `mod.save`, and a later `save.loaded` restores that new choice regardless of a stale global Aang option.
- ZIP integrity passes.

## 2.8.6 - 2026-08-08

### Fixed
- Fixed the selected skin being reset to **Aang** after restarting the game.
- Startup now reads `selected_character_3d` from the **per-mod game save first** and only uses the global `character_3d` mod option as a fallback when the save has no valid selection.
- This prevents an older globally persisted Aang option from overriding a character selected through **Skin Selector** and saved with the game.
- Selecting a skin still updates both the save value and the mod option, so the normal options UI remains synchronized.

### Validation
- Persistence-order simulation passes: saved Red/Yugi/Naruto/Zoro/Cloud/Aang/CJ selections all win over a stale global Aang option on restart.
- Invalid or absent save values still fall back to the mod option, then Red.
- ZIP integrity passed.

## 2.8.5 - 2026-08-08

### Fixed
- Added a **final-stage Aang armature guard** in both overworld and Dramatic Shape battle skeleton updates.
- Aang's upper arms are now forcibly resolved to the verified arms-down local-Z pose **after** walk, jump, idle, or battle-point deltas are calculated, preventing any stale/generic Red-style transform from raising both arms over his head.
- Aang's forearms receive a small mirrored bend for a more natural relaxed stance.
- For reliability, Aang no longer uses the shared trainer pointing gesture; his battle intro keeps both arms down instead of risking the broken overhead pose.
- Skin Selector, Cloud naming, and all other characters remain unchanged.

### Simulation
- Reconstructed Aang's actual 24-bone hierarchy from `data/aang_model.lua` and applied the exact runtime matrix order.
- Verified relaxed pose: head Y ~17.00, left/right hand Y ~8.8 (both safely below the head).
- Verified the old wrong-sign pose reproduces the reported failure: left/right hand Y ~19.07, above the head.
- v2.8.5 final-stage guard forces the verified relaxed matrices regardless of animation branch.

## 2.8.4 - 2026-08-08

### Fixed
- Corrected **Aang's overworld/jump armature order**. His arm-drop rest transform was being multiplied in the wrong order relative to the swing/reach rotation, so movement could still fling both arms upward despite the earlier battle-only fix.
- Aang's left/right upper arms now apply the **rest drop first and then swing/reach in the lowered local frame** for walking, jumping, and the Dramatic Shape battle pointing gesture.
- Preserved the prior **Skin Selector** pause-menu shortcut behavior, **Cloud** rename, and the exact 24-bone weighted Aang rig data unchanged.

### Validation
- Static code review confirms every AANG-specific upper-arm path now uses the corrected rotation order in overworld walk, manual jump, and battle-point pose code.
- ZIP integrity and Lua syntax validation pass.

## v2.8.3 — top-level Skin Selector hook-order fix

- Fixed **Skin Selector** disappearing from the normal pause/start menu when another menu mod rebuilt or replaced the `ui.start_menu.items` table after this mod ran.
- The official START-menu wrapper now runs at the outermost hook priority, calls the rest of the hook chain first, then injects **Skin Selector** into the **final returned menu list**.
- When **MOD MENUS** exists, Skin Selector is inserted immediately after it, so the screenshot layout becomes **MOD MENUS → Skin Selector → Cheat Menu → MODS** when Cheat Menu is also installed.
- If MOD MENUS is absent, Skin Selector falls back to immediately before **MODS**.
- The separate paused-overlay compatibility wrappers use the same outermost priority and continue to post-process returned menu lists.
- v2.8.1 Aang armature corrections and the **Cloud** rename remain unchanged.

## v2.8.2 — Skin Selector pause shortcut

- Renamed the normal pause/start-menu shortcut from **Character Selector** to **Skin Selector** so the row is shorter.
- The selector screen heading now reads **SKIN SELECTOR**.
- Preserved the official `ui.start_menu.items` integration and its required `next(game, items)` chaining behavior.
- Added best-effort compatibility support for separate paused-overlay menu hooks and several common menu-item table/tuple formats.
- Skin Selector is anchored immediately before **MODS**, producing **MOD MENUS → Skin Selector → MODS** when the Mod Menus row is present.
- Kept the v2.8.1 Aang armature fix and **Cloud** naming change unchanged.

# Changelog

## 2.8.1 - 2026-08-08

### Aang armature / battle pose
- Fixed Aang's Dramatic Shape battle-intro armature pose. The shared Red battle transform was rotating Aang's mirrored upper-arm axes with the wrong sign, which drove both arms over his head.
- Added Aang-specific battle upper-arm and forearm transforms that reuse his correct local-Z arm drop/elbow hinge and lift only the pointing arm.
- Kept Aang's existing exact 24-bone weighted bind rig and normal overworld/jump animation profile unchanged.

### Character name
- Renamed the user-facing **Wind-Up Cloud** entry to simply **Cloud** in the character selector, mod option, and mod metadata. The original source asset filenames remain unchanged for rebuild compatibility.

## 2.8.0 - 2026-08-08

### CJ world fracture
- Removed the remaining trigger-frame route-wide fracture scan. Aiming now prewarms terrain aggressively, while idle indexing runs at a much smaller budget.
- Cold/unindexed hits react immediately with a textured fallback instead of blocking until the complete terrain index catches up.
- Exact fracture pieces begin with a tiny visible crack on the hit frame so the destroyed object and debris transition read as one continuous event.
- Reduced the exact implosion handoff to roughly two frames before the outward burst.

### Terrain textures
- Fractured chunks now prefer the exact live **TerrainAtlas** image used by Dramatic Shape for the current map every frame.
- Added per-map and per-live-mesh terrain-atlas tracking instead of depending on whatever texture state happens to be attached to the cached mesh.
- Terrain vertex UV/shade extraction now explicitly reads `VertexTexCoord` / `VertexShade` attributes when supported.
- The cold-hit fallback now samples the actual tileset tile beneath the impact instead of using the old flat green/brown placeholder material.

### Stability / performance
- Keeps the stable v2.7.9/v2.7.5 live-mesh fracture core; does not reintroduce the crashing v2.7.6 cache path.
- Debris physics suspends background fracture prewarming until the active fragments are gone.

## 2.7.9 - 2026-08-08

### Stability rollback
- Rolled CJ world destruction back to the proven **v2.7.5 real-terrain fracture/implosion path** after the v2.7.6-v2.7.8 texture/index optimizations caused first-shot crashes.
- Preserved the full environment implosion and flying real-mesh debris effects from v2.7.5.
- Removed the risky v2.7.6 terrain-atlas fallback mesh and pre-index optimization changes instead of suppressing the destruction effects.
- **L2 / LT** is now CJ ADS; R2/RT is no longer used for aiming.

## 2.7.5 - 2026-08-08

### CJ destruction responsiveness
- Fixed a bridge ownership bug that could force the exact Dramatic Shape terrain-fracture path to fall back to generic debris after switching characters.
- Terrain triangle-to-block data is now **pre-indexed incrementally while CJ is active**, instead of scanning the full live mesh when the trigger is pulled.
- The live terrain vertex map is preallocated and hit triangles are hidden by degenerating only their existing index slots, avoiding a map-sized allocation on impact.
- Reduced the exact fracture implode delay and kept the terrain edit/mesh cut on the shot frame.

### Textured fracture pieces
- Each real fracture chunk now captures and retains the **same texture object bound to the source Dramatic Shape terrain mesh**.
- Exact UV coordinates and baked face shading remain attached to the source triangles, so hedge/building/wall debris uses the texture of the environment it came from.
- The current terrain atlas is cached directly from Dramatic Shape's live draw pass as a fallback for the first frame after a map/mesh swap.

### Third-person aiming
- Replaced the old linear right-stick aim with a **squared response curve** and native-style yaw direction.
- Added a collision-aware placed over-the-shoulder camera while R2/RT is held, with a centred crosshair that matches the actual aim ray.
- CJ's continuous model yaw is kept on the weapon direction after vanilla movement resolves, allowing movement to read as strafing/backpedaling while ADS.
- Fixed aim-assist scoring so one candidate can no longer change the reference angle used to score the remaining targets; assistance now nudges rather than snaps.
- Shifted the ADS bullet origin slightly toward CJ's gun/shoulder side to better agree with the over-the-shoulder view.

### Validation
- Full Lua source tree syntax checked with LuaTeX's Lua compiler.

## 2.7.4 - 2026-08-08

### Real terrain fracture
- Replaced the synthetic full-block debris shell with an **exact live-mesh fracture path** for Dramatic Shape terrain.
- On impact, the mod reads the currently rendered terrain mesh, selects the above-ground triangles belonging to the hit 32x32 map block, and removes only those triangles from the stale cached mesh.
- The removed triangles are regrouped into small rigid chunks while preserving their original **world geometry, texture UVs, and baked face shading**.
- Those exact chunks occupy the same positions on the first destruction frame, briefly pull inward, then receive independent outward velocity, spin, gravity, bounce, and friction.
- Dramatic Shape's asynchronous refresh continues underneath, so the newly rebuilt map mesh replaces the surgically edited stale mesh without a separate particle/terrain swap.
- The older cube-grid debris remains only as a compatibility fallback when the installed Dramatic Shape build does not expose readable terrain mesh data.

### Validation
- Lua syntax checked for the complete mod tree with LuaTeX's Lua compiler.
- The fracture path uses Dramatic Shape's existing terrain vertex format (`position + atlas UV + shade`) rather than approximating environment colors with generic debris cubes.

## 2.7.3 - 2026-08-08

### World destruction
- Fixed the remaining terrain blink by matching debris to the **full 32x32 Gen1 map-block footprint**, not only the 16x16 hit cell.
- The source block is now replaced on the same frame by a dense temporary grid of 3D voxel fragments occupying its old volume.
- Fragments briefly hold the block silhouette, then implode inward and finally blast outward with the existing gravity/bounce physics.
- Terrain refresh still uses the 3D background chunk-refresh path, so 3D Always remains active.

## 2.7.2 - 2026-08-08

### CJ shooting
- Replaced the synthesized pistol crack with the supplied `gunshotjbudden.mp3` asset.
- **R2 / RT** remains ADS; **R1 / RB** now fires, with **Y / Triangle** retained as a backup fire button.
- Reduced hip-fire spread and removed ADS random spread for more consistent shot placement.
- Tightened aim assist so it corrects near-target shots without pulling too aggressively.

### Environment destruction
- Reworked voxel destruction into a staged **collapse -> break -> burst** sequence.
- The original 3D block remains visible for a short implosion phase instead of blinking out immediately.
- Debris fragments pull inward toward the actual world impact, then the terrain block is removed and the same fragments receive a strong outward physics impulse.
- Existing gravity, spin, bounce, friction, and asynchronous 3D chunk refresh are retained.

## 2.7.1 - 2026-08-08

### CJ third-person shooting overhaul
- Removed the v2.7.0 first-person/Doom-style camera override.
- R2/RT now keeps the normal third-person camera and enters a dedicated aim mode.
- CJ faces the weapon direction while aiming, allowing strafing and backpedaling while moving.
- Added an over-the-shoulder reticle placement that keeps CJ visible.
- Smoothed right-stick aim and reduced ADS sensitivity for better precision.
- Increased ADS aim assist and nearly eliminated ADS random spread.
- Reduced recoil kick and increased recoil recovery speed.
- Extended CJ's pistol arm farther forward with a softer elbow so the weapon reads as being held at arm's reach.
- Existing world destruction and voxel debris physics are retained.

## 2.7.0 - 2026-08-08

### CJ shooting / camera
- Replaced the floating right-stick cursor with a fixed **center-screen Quake/Doom-style crosshair**.
- Right stick now rotates a persistent CJ camera/aim yaw and pitch instead of moving the reticle around the screen.
- Shots always travel through the centered crosshair direction; ADS keeps the same centered-camera behavior.
- Added compatibility updates for Dramatic Shape first-person/body yaw and pitch fields when available.

### World destruction responsiveness
- Starts 3D debris on the exact impact frame instead of waiting for terrain remeshing.
- Stops invalidating CJ/player voxel caches during environment hits.
- Uses the narrowest available Dramatic Shape chunk/cell refresh API when present, falling back to background `refresh(mapId)`.
- Keeps the active 2D/3D render-mode setting unchanged.

## 2.6.9 - 2026-08-08

### CJ voxel destruction
- Replaced the implosion with an outward **3D voxel physics burst**.
- Destroyed environment blocks now break into ~42 small chunks originating inside the hit block.
- Every chunk receives independent linear velocity and three-axis angular velocity.
- Added gravity, ground collision, bounce, friction, settling, lifetime, and shrink-out behavior.
- Bullet direction adds directional impulse while radial velocity throws fragments in all directions.
- Debris remains world-space 3D geometry and does not follow the reticle.
- Keeps the existing background chunk refresh so **3D Always** remains in 3D mode.

## 2.6.8 - 2026-08-08

### CJ world destruction
- Fixed the crumble/implosion effect being incorrectly anchored to the HUD reticle.
- Destruction debris now spawns at the **actual world cell hit by the bullet**.
- Replaced screen-space rectangles with real **3D voxel debris cubes** drawn inside Dramatic Shape's voxel render pass.
- Fragments collapse toward the destroyed block's 3D center, shrink, then fall away after convergence.
- Moving the aiming reticle after a shot no longer moves the destruction effect.
- Removed the fake reticle-centered world-break ring.

## 2.6.7 - 2026-08-08

### CJ world destruction
- Replaced the outward debris burst with a true **implosion** effect.
- Destruction fragments now spawn around the outside of the impacted block and accelerate inward toward the bullet impact.
- Pieces spiral slightly as they collapse, shrink while converging, then lose cohesion and fall/fade away.
- Increased debris count and lifetime so the collapse reads clearly in motion.
- Keeps the v2.6.5+ render-mode preservation, so 3D Always remains 3D during the effect.

## 2.6.6 - 2026-08-08

### CJ world destruction
- Added a visible **crumble/debris burst** when CJ shoots and destroys solid world terrain.
- Each destroyed block throws multiple small chunks outward with randomized velocity, gravity, spin, size, and fade.
- Debris is layered over the impact while Dramatic Shape performs its background chunk refresh, preserving the selected 3D/2D render mode.
- Kept the v2.6.5 voxel-safe refresh path; world destruction still does not globally invalidate the 3D renderer.

## 2.6.5 - 2026-08-08

### Fixed
- Fixed CJ world destruction briefly flashing the overworld back to the flat 2D renderer while voxel terrain rebuilt.
- Replaced global voxel/pipeline invalidation with Dramatic Shape's background `ChunkMesher.refresh(mapId)` path.
- CJ's destruction mechanic now preserves the player's current rendering choice: 3D/VOXEL stays 3D, and 2D stays 2D.
- Removed `Pipelines.invalidateAll()` from gun-driven terrain edits so shooting no longer resets unrelated render caches.

## 2.6.4 - 2026-08-08

### CJ shooting polish
- R2/RT now holds a sustained **arm’s-length ADS pose** instead of only posing CJ during the few firing frames.
- Straightened the pistol arm, reduced elbow tuck, aligned the wrist, and added a restrained support-arm pose.
- Added ADS aim assist, near-zero ADS spread, tighter 0.10-cell ray stepping, faster recoil recovery, and a slightly faster fire cadence.
- Hip-fire keeps a small controlled spread while ADS is nearly point-accurate.
- Reticle now reacts to recoil and recovers smoothly.

### World destruction
- CJ shots can now break a solid map block when no NPC/Pokémon/object is hit first.
- Destruction replaces the impacted 2x2-cell map block with a walkable floor block from the active tileset, so collision and the actual map data both change.
- Warp and door cells are protected from block destruction to avoid immediately breaking map transitions.
- Dramatic Shape voxel chunk invalidation is requested after a world block is destroyed so the changed block can rebuild visually.

## 2.6.3 - 2026-08-08

### CJ fixes
- Rebuilt the pistol attachment transform so the weapon sits in CJ's right hand instead of hanging backward.
- Tightened CJ's run/jog pose with lower knee/ankle travel and a more stable armed upper-body carry pose.
- Added CJ-only **ADS** support on **R2 / right trigger** (with `rightshoulder` fallback), including a closer camera zoom and a tighter reticle.
- Upgraded CJ firing so the shot follows the right-stick cursor direction as a continuous ray instead of only the four cardinal directions.
- Extended shooting to remove/destroy compatible **NPCs, Pokémon, and world objects/props** hit by the ray.

## 2.6.2 - 2026-08-08

### CJ animation
- Reduced CJ's exaggerated thigh and knee travel so his leg no longer folds backward during the run.
- Reduced CJ's arm swing/elbow amplitude for a cleaner armed running pose.

### CJ pistol mechanics
- Added a CJ-only on-screen aiming reticle.
- Right stick now moves the reticle and selects the shooting direction.
- Y / Triangle fires toward the current reticle direction.
- Added a short visible shot/tracer flash and hit-confirm reticle flash.
- Increased pistol range to nine map cells.
- Existing NPC/Pokemon hit reactions and custom `onShot` / `onHit` callbacks remain supported.

## 2.6.1 - 2026-08-08

### Fixed
- Rebuilt CJ's visible mesh using the original GTA FBX skin weights instead of approximate arm weighting.
- Corrected CJ's aiming chain so the pistol arm bends at the elbow instead of behaving like a rigid rod.
- Reduced excessive shoulder/upper-arm movement while firing and improved pistol-hand alignment.

### Shooting
- Expanded CJ's shot targeting to NPC/entity/actor/figure/Pokemon collections exposed by the overworld scene.
- Compatible NPCs and overworld Pokemon now receive a visible bump/flinch hit reaction.
- Added optional `onShot`/`onHit` cooperation for custom actors while keeping story entities non-destructive.

## 2.6.0 - 2026-08-08

### Added
- Added the supplied **Postal Redux pistol** as a real textured 3D mesh attached to CJ's right hand.
- Added **CJ shooting** on controller **Y / PlayStation Triangle**.
- Added CJ-specific aiming and recoil animation so his torso, shoulder, upper arm, elbow, wrist, and pistol move together when firing.
- Added a short forward raycast so shots stop on the first map obstacle or actor in CJ's facing direction.
- Added a lightweight synthesized gunshot sound so the feature does not depend on an external audio asset.

### Controls
- **Y / Triangle**: CJ pistol shot.
- **X / Square**: existing manual jump.

### Notes
- The shooting hit is intentionally non-destructive to Gen1Recomp story/NPC state; actors can be detected as shot targets without deleting or corrupting scripted entities.
- Other selector characters do not receive or display CJ's pistol.

## 2.5.1 - 2026-08-08

### Fixed
- Rebuilt **CJ's arm animation profile** so the elbows bend on the correct local hinge instead of rotating around the forearm axis.
- Added mirrored left/right elbow directions for CJ.
- Stabilized CJ's shoulder bones during the run so the arms no longer shoot diagonally away from the torso.
- Changed CJ's T-pose arm drop to a full 90° rest pose and reduced the upper-arm swing range.
- Kept CJ's textures, body/leg rig, scale, and all other characters unchanged.

## 2.5.0 - 2026-08-08

### Added
- Added **Carl Johnson (CJ)** as a selectable 3D character.
- Built CJ from the supplied GTA San Andreas OBJ/ASCII-FBX package and its named GTA rig-helper joints.
- Added a dedicated four-region CJ texture atlas: **upper body, head, legs, and shoes**.
- Added CJ to both the in-game Character Selector and the backup mod option list.

### CJ Rig / Texture Validation
- Uses 24 runtime bones positioned from the supplied GTA helper groups (pelvis/spine/shoulder/elbow/wrist/thigh/knee/ankle/toe).
- Uses blended arm and leg weights around the real joint chains instead of a single rigid silhouette assignment.
- Original OBJ material UVs were validated independently for all four texture sheets and mapped with half-pixel atlas inset to prevent texture bleeding.
- Source T-pose is converted to a relaxed arms-down rest pose before the shared run/jump animation is applied.

## 2.4.2 - 2026-08-08

### Fixed
- Reimplemented the **CHARACTER SELECTOR** START-menu row using Gen1Recomp's documented Tutorial 11 hook pattern.
- The mod now mutates the incoming `ui.start_menu.items` list first, inserts **CHARACTER SELECTOR** immediately before **MODS**, then returns `next(game, items)`.
- Removed the previous post-`next` insertion path that could fail to become part of the actual main pause-menu list.
- Selecting the row opens the Character Selector screen directly; it does not open the mod manager.

## 2.4.1 - 2026-08-08

### Fixed
- Fixed **Character Selector** not appearing in the normal START/pause menu.
- The previous hook incorrectly returned the result of `mod.ui.insertBefore(...)`; the helper mutates the menu list and the hook must return the list table itself.
- Character Selector is now anchored directly **before MODS**, placing it in the same normal pause-menu mod section as entries such as Cheat Menu.
- Added duplicate-row protection and a higher hook priority for reliable menu assembly with other menu mods.

## 2.4.0 - 2026-08-08

### Fixed
- **Character Selector is now injected through the real `ui.start_menu.items` hook bus**, so it appears directly in the normal START/pause menu rather than requiring the MODS screen.
- Rebuilt **Wind-Up Cloud** from the original weighted COLLADA skin instead of the fallback auto-rig.
- Corrected Cloud's repeated negative-V texture coordinates and flipped them into LÖVE image space; Cloud rest-pose skin reconstruction now validates to ~3.1e-15 average error.
- Rebuilt **Aang** texture coordinates with clamped source UVs (no repeat-wrap edge rollover), while keeping the exact 24-bone weighted rig.
- Added an **AANG-specific** leg/arm axis profile: thighs/knees use the rig's real local hinge orientation and the T-pose arms are dropped before swing.
- Reworked **Zoro's auto-rig shoulder/arm chain** from the actual horizontal T-pose extents. Shoulder, elbow, and wrist regions now use blended weights instead of rigid one-bone seams.
- Preserved Zoro's 180-degree facing correction.

### Validation
- Cloud exact weighted rig: 26 bones, 1,398 weighted positions, 1,282 triangles; average rest error ~3.1e-15, max ~1.5e-14.
- Aang exact weighted rig remains 24 bones, 1,859 weighted positions, 3,714 triangles; average rest error ~1.9e-15.

## 2.3.3 - 2026-08-08

### Fixed
- Adjusted **Zoro** so he no longer appears to walk backward; applied a character-specific 180° facing correction.
- Tuned **Zoro** shoulder/arm rest pose with a stronger arm-drop so his shoulders sit more naturally.
- Switched **Aang** to a character-specific animation profile that better matches his rig, improving his arm rest pose and leg motion while walking.
- Switched **Wind-Up Cloud** to a character-specific animation profile and arm-rest setup so he no longer uses the generic arms-out posture.
- Reduced **Wind-Up Cloud** render scale to better fit the imported minion proportions.

## 2.3.2 - 2026-08-07

### Changed
- Moved **CHARACTER SELECTOR** directly into the main Gen1Recomp START/pause menu.
- The selector is inserted next to the normal POKéMON / ITEM rows instead of being appended near the bottom of the menu.
- Kept the character choice in the mod options as a backup.

## 2.3.1 - 2026-08-08

### Fixed
- Rebuilt **Zoro's auto-rig arm chain** to follow the source T-pose correctly instead of treating the arms as already hanging down.
- Added a Zoro-specific 78-degree arm-rest drop before the run/jump swing, removing the permanent T-pose/Frankenstein silhouette.
- Rebuilt **Wind-Up Cloud** from the DAE geometry/UVs into a stable selector auto-rig because the original controller conversion could collapse/invisibly render in Dramatic Shape.
- Cloud now has a directly generated diffuse atlas and stable one-bone-per-region skin so the model always has valid visible geometry.

### Unchanged
- Red, Yugi, Naruto, and Aang data/animation profiles are unchanged.

## 2.3.0 - 2026-08-08

### Added
- Added **Aang** as a sixth selectable 3D character in the pause-menu **Character Selector**.
- Imported Aang from the supplied rigged `aang.dae` instead of approximating him from the OBJ.
- Added `data/aang_model.lua` and `assets/aang_atlas.png`.

### Validation
- Aang runtime rig: 24 bones, 1,859 weighted positions, 3,714 triangles.
- Exact weighted bind-pose reconstruction after Z-up -> Y-up conversion: average error ~1.9e-15, max ~7.1e-15 model units.
- Original Aang diffuse texture is preserved with padded/clamped atlas UV mapping to avoid texture bleeding.

## 2.2.0 - 2026-08-08

### Added
- Added **Roronoa Zoro** and **Wind-Up Cloud** as new selectable characters in the pause-menu **Character Selector**.
- Added `data/zoro_model.lua` and `assets/zoro_atlas.png` generated from the supplied `Zoro.obj` and texture set.
- Added `data/cloud_model.lua` and `assets/cloud_atlas.png` generated from the supplied `Wind-Up Cloud.dae` and diffuse texture.
- Extended the selector option list so Red, Yugi, Naruto, Zoro, and Cloud can all be swapped in-game.

### Rig / Texture Work
- Zoro uses a dedicated runtime atlas with explicit face/body material remapping so his diffuse textures resolve through the selector correctly.
- Cloud uses a dedicated runtime atlas built from the provided diffuse texture.
- Added a **GENERIC** animation profile for extra imported characters whose bind pose is closer to an arms-down rest pose than Red/Yugi's source rigs.

### Notes
- Red, Yugi, and Naruto remain available and keep their existing texture/animation fixes.

## 2.1.1 - 2026-08-07

### Fixed
- Fixed Yugi's upper-arm run animation pulling an arm too far behind the torso.
- Reduced Yugi-only backswing and wrist amplitude while keeping a natural forward arm pump.
- Softened Yugi elbow movement and reduced his jump-arm extremes.
- Red and Naruto animation profiles are unchanged.

## 2.1.0 - 2026-08-07

### Added
- Added **Naruto** as a third selectable 3D character.
- Naruto is converted from the supplied `Naruto.smd`, with exact weighted bind-pose reconstruction.
- Added dedicated Naruto body/head/eye atlas mapping and a Naruto-specific animation-axis profile.

### Validation
- Naruto rest-pose reconstruction: average error ~8.9e-15, max ~3.6e-14 model units.
- Source coordinates converted from Z-up/-Y-forward into the selector runtime's Y-up/+Z-forward convention before skinning.

## 2.0.5 - 2026-08-07

### Fixed
- Corrected Yugi's mirrored elbow hinge: left forearm flexes on negative local Y and right forearm on positive local Y, matching the source SMD skeleton.
- Reduced Yugi-only upper-arm run swing so his stylized long arms no longer overextend.
- Adjusted Yugi's resting upper-arm drop closer to the source idle pose.
- Added Yugi-specific wrist motion and mirrored jump elbow behavior.
- Red's animation profile is unchanged.

## 2.0.4 - 2026-08-07

### Fixed
- Corrected Yugi SMD **V-axis texture orientation**.
- Fixed Yugi's face sampling the wrong half of the face sheet (including eye texture problems).
- Fixed hair/body/clothing/gold accessory colors sampling vertically incorrect parts of the body texture.
- Kept the validated SMD bind pose and armature from v2.0.3 unchanged.

## 2.0.3 - 2026-08-07

### Fixed
- Rebuilt **Yugi Muto from `Model.smd`** instead of the problematic COLLADA conversion.
- Uses the SMD's exact bind hierarchy, per-vertex weights, UVs, and body/face material assignments.
- Rest-pose validation is now effectively exact: average reconstruction error ~2.5e-16, maximum ~3.6e-15.
- Corrected Yugi's T-pose arm rest to 90 degrees using a character-specific setting; Red remains unchanged.
- Keeps Yugi on his own animation-axis profile rather than sharing Red's leg-axis assumptions.

## 2.0.2 - 2026-08-07

### Fixed
- Fixed Yugi's COLLADA UV extraction: his UVs are stored on the `<vertices>` element rather than directly on `<triangles>`.
- Fixed Yugi texture coordinates so the body and face sample their real atlas regions instead of one fallback texel.
- Added a Yugi-specific animation-axis profile instead of driving his skeleton with Red's joint axes.
- Yugi's thighs, knees, feet and toes now animate around his actual local X hinge axis; upper-arm swing and torso lean were remapped as well.
- Reduced Yugi's rendered height slightly to better match Red and the voxel world.

## 2.0.1 - 2026-08-07

### Fixed
- Corrected Yugi Muto's COLLADA inverse-bind matrix conversion. The source matrices were column-major and were previously being used without transposition, which collapsed the skinned mesh around the head/hair.
- Regenerated Yugi's complete 27-bone runtime skin and atlas with the corrected bind matrices.
- Rest-pose reconstruction now matches the source mesh to floating-point precision.

## 2.0.0 - 2026-08-07

### Added
- Converted the mod into a **3D Character Selector**.
- Added a new **Character Selector** entry to the normal pause/start menu.
- Added **Yugi Muto** as a second fully skinned 3D character from the user-supplied model pack.
- Added persistent Red / Yugi selection with immediate renderer switching.
- Added a fallback `CHARACTER` choice in the mod options.

### Fixed
- Fixed the Dramatic Shape pre-battle pointing animation timer. The previous implementation used a battle token that could change during the intro and repeatedly reset the pointing pose, leaving the arm down.

### Retained
- Polished Red running/jump/head/hand animation.
- Dramatic Shape voxel rendering, shadows, reflections, battle trainer replacement, and flicker fixes.
- Optional X/Square manual jump and one-cell border/fence crossing.

## 1.8.1 - 2026-08-07

### Added
- Added a Dramatic Shape **pre-battle pointing animation** for the 3D player model.
- Red now raises his right arm, extends his index finger toward the wild Pokemon, and holds the gesture until the trainer model disappears.
- Added subtle torso, shoulder, neck, head, elbow, wrist, thumb, and finger posing so the point reads as a full-body gesture rather than a rigid arm rotation.

## 1.8.0 - 2026-08-07

### Added
- Replaces Dramatic Shape's **player trainer back-picture card in staged 3D battles** with the same real skinned 3D Red model used in the overworld.
- **Manual X / PlayStation Square jump can now clear one-cell-thick solid borders/fences** when the cell beyond is empty and walkable.
- The manual-jump option continues to enable/disable the custom jump feature as a whole.

### Safety / compatibility
- Vanilla ledges still use Gen1Recomp's native `checkLedgeHop()` first.
- Custom border jumping refuses occupied middle/landing cells and requires a normal walkable landing two cells ahead.
- Player Pokémon battle cards are not replaced; the 3D trainer replacement is active only while the battle texture is marked as the trainer back picture.

## 1.7.5 - 2026-08-07

### Added
- **MANUAL JUMP** toggle in the mod manager options; enabled by default and persisted by Gen1Recomp.
- Pressing Xbox **X** / PlayStation **Square** while facing a valid Gen1 ledge now uses the engine's real ledge-hop movement, including the two-cell crossing, collision-safe landing, SFX, and connected-map edge handling.

### Changed
- X/Square still performs the polished visual jump in place when there is no valid jumpable ledge ahead.
- Disabling MANUAL JUMP immediately cancels a cosmetic jump in progress, while vanilla automatic ledge hops remain untouched.

## 1.7.4 - 2026-08-07

### Added
- Added a **manual jump** on the controller west-face button: Xbox **X** / PlayStation **Square** (`x` in LÖVE/SDL).
- Manual jump is cosmetic and preserves map collision, so it cannot jump through walls, NPCs, warps, or other blocked tiles.

### Changed
- Rebuilt the ledge/manual jump into an 11-pose takeoff, tuck, apex, extension, landing and recovery cycle.
- Improved airborne knee tuck and pre-landing leg extension.
- Lower, more natural balancing arm motion so the jump does not create the Frankenstein-arm silhouette.
- Added a smoother manual vertical arc while leaving the normal engine ledge-hop translation intact.

## 1.7.3 - 2026-08-07

### Added
- Dedicated **ledge-hop jump animation** for jumping over the overworld border/fence/ledge tiles.
- Takeoff crouch, launch, mid-air leg tuck, balanced arm pose, landing reach, compression, and recovery.
- Jump pose is driven directly by Gen1Recomp's `hopFrames` / `hopTotal`, so it stays synchronized with the existing fixed-step ledge arc.
- Preserves the v1.7.2 running animation, eye/atlas fix, hand animation, head motion, shadows, reflections, and Dramatic Shape rendering.

## 1.7.2 - 2026-08-07

### Fixed
- Fixed the eye mesh sampling outside its atlas region. The source eye UVs intentionally use repeated V coordinates around 1.75–2.0, which now wrap correctly before atlas remapping.
- Fixed the yellow/incorrect face-hat patch caused by those invalid eye atlas coordinates.
- Added half-texel atlas insets to prevent linear-filter bleeding between body, skin, eye, hair, and object texture regions.
- Clamped the final atlas texture at runtime as an additional guard against edge sampling artifacts.

## 1.7.1 - 2026-08-07

### Changed
- Refined the 12-pose gait toward a more natural relaxed running animation.
- Shortened the heavy stance feel and gave the recovery/swing leg a clearer fold-and-drive phase.
- Increased forward body lean slightly while reducing excessive head motion.
- Lowered and softened the arm pump so the hands stay nearer the torso instead of marching upward.
- Improved ankle/toe follow-through and slightly tightened cadence while preserving movement-speed synchronization.

## 1.7.0 - 2026-08-07

### Changed
- Rebuilt the successful light-jog baseline from **8 key poses to 12 biomechanical phases**.
- Added distinct contact, loading, mid-stance, heel-rise, toe-off, recovery, mid-swing, late-swing, and pre-contact timing.
- Improved stance-foot stability so the planted foot stays close to the ground while the body passes over it.
- Smoothed knee recovery and reduced abrupt high-knee transitions.
- Reworked the arm curve into a restrained shoulder-led pump with elbow and wrist follow-through.
- Reduced shoulder lift and forearm pronation so the upper body looks relaxed rather than march-like.
- Refined hip/head vertical rhythm so the entire body carries weight as one connected motion.

## 1.6.6 - 2026-08-07

### Changed
- Lowered the forward arm pump so Red no longer raises his arms into a Frankenstein-like pose.
- Reduced shoulder lift while preserving shoulder follow-through.
- Tightened the upper-arm swing range and kept the hands closer to waist/chest height.
- Rebalanced elbow bend so the arms remain relaxed through the jog instead of reaching straight forward.
- Kept the v1.6.5 head bobbing and the v1.6.4+ running mechanics unchanged.

## 1.6.5 - 2026-08-07

### Changed
- Added subtle **head bobbing** to the refined light-jog cycle.
- Added small **head nod**, **head turn**, and **head roll** components so the head moves more naturally during the run.
- Split the motion across **Neck** and **Head** bones so the movement feels connected instead of wobbling from a single joint.
- Kept the v1.6.4 running/jog baseline and only refined the upper body/head motion.

## 1.6.4 - 2026-08-07

### Changed
- Locked the gait cadence to **32 world pixels per full left/right cycle**, matching Gen1Recomp's native 16-pixel / 16-frame tile movement: one full jog cycle now spans exactly two normal tiles.
- Corrected the sign of the distal follow-through offsets. Knee, ankle, toe, elbow, and wrist now genuinely **lag** the joint above them instead of accidentally arriving early.
- Re-authored the arm/elbow relationship so the **forward arm folds more** and the **rear arm opens slightly** during backswing.
- Extended the rear arm sweep a little while keeping the forward arm compact, producing a more natural relaxed-jog silhouette.
- Reduced forearm pronation so the hands follow the arms without twisting mechanically.
- Kept the v1.6.3 corrected forward leg direction and all voxel flicker/shadow/reflection fixes.

### Validation
- Rechecked the side-view skeleton cycle against Gen1Recomp's native movement rate (1 pixel per logic frame, 16 frames per 16-pixel tile).
- Verified the front-contact leg still sweeps backward under the hips and the opposite arm remains forward through stance.

## 1.6.3 - 2026-08-07

### Fixed
- Corrected the source rig's thigh rotation direction. The previous gait could read as a backward walk translated forward because the intended front-contact thigh angle actually moved the knee behind the hips.
- Re-authored the thigh stride around the correct forward axis while preserving the smoother knee/ankle/toe follow-through from v1.6.2.
- Restored proper opposite arm/leg readability: when a leg plants forward, the same-side arm is now visibly in its backswing.

### Simulation
- Verified both stance legs sweep backward relative to the hips during ground contact: approximately `+17.7 -> -6.0` source-model Z units across the sampled stance phase.
- Re-ran the full weighted 5,978-point skin through the corrected cycle before packaging.

## 1.6.2 - 2026-08-07

### Changed
- Reworked the leg key poses into a more natural light-jog sequence: contact, loading, mid-stance, toe-off, recovery, swing, and pre-contact.
- Shifted knee, ankle, and toe timing slightly behind the hip so motion travels down the leg instead of every joint hitting its pose together.
- Rebalanced the arm pump so the forward arm bends more while the back arm opens slightly.
- Added elbow and wrist follow-through behind the shoulder/upper-arm motion for a less mechanical chain.
- Reduced forearm pronation and shoulder exaggeration so the extra movement reads as natural rather than floppy.
- Validated 24 fully weighted skin samples and 96 skeleton continuity samples with no invalid positions.

## 1.3.2 - 2026-08-07

### Changed
- Reduced Red's overall rendered size so he sits better in the voxel world and no longer feels oversized.
- Increased arm swing amplitude and follow-through so the walk reads less stiff in the upper body.
- Boosted elbow and wrist motion slightly to make the arms feel more alive without breaking the smoother v1.3 walk cycle.
- Increased shoulder contribution so the upper body has more natural walk energy.

## 1.3.1 - 2026-08-07

### Fixed
- Corrected the Red source rig's **knee hinge direction**. `LLeg` / `RLeg` were flexing with the wrong local sign in previous builds, so the shin extended in the same direction as the thigh and produced the straight/locked-leg silhouette.
- Kept the smoother v1.3 keyframed gait, but now the knees fold in the anatomically correct direction.
- Verified across the full cycle that the toe joints stay close to ground height instead of lifting unnaturally during the forward step.

## 1.3.0 - 2026-08-07

### Animation rewrite
- Replaced the sine-wave procedural walk with an **8-pose keyframed gait**.
- Added separate contact, loading, passing, toe-off, swing, and return behavior for each leg.
- Uses Catmull-Rom interpolation between poses for continuous motion instead of rigid pose stepping.
- The gait now runs from continuous render time rather than restarting at each tile movement boundary.
- Reworked knees and ankles so the swing leg compresses while the planted leg stays controlled.
- Reworked shoulders, elbows, wrists, fingers, hips, and spine to follow the gait on separate timing curves.
- Reduced cadence to a brisk natural walk rather than a mechanical jog.

## 1.2.5 - 2026-08-07

### Changed
- Reworked the walk again to feel less robotic and more like a natural human gait.
- Added smoother easing through each step, including a soft secondary harmonic in the walk cycle.
- Improved leg flow with shorter stride, softer always-bent knees, and better mid-swing compression.
- Added light shoulder motion and smoother arm timing so the upper body follows through instead of swinging like a metronome.
- Improved support for fractional movement progress when available, which smooths the cycle beyond a rigid 16-pose feel.

## 1.2.4 - 2026-08-07

### Changed
- Smoothed the entire walk cycle so it flows better from pose to pose instead of feeling choppy.
- Added a soft secondary harmonic to the gait for easier in/out motion through each step.
- Tightened the stride and rebalanced the knee timing for a more natural side-view walk.
- Improved hand flow with smoother wrist timing and finger motion that follows the arm swing more naturally.

## 1.2.3 - 2026-08-07

### Changed
- Shortened the leg stride again to remove the stretched front-leg pose visible in side view.
- Reduced foot pitch so the leading shoe stays much flatter instead of pointing upward.
- Simplified the knee timing: the trailing leg bends on push-off while the leading leg stays softly unlocked.
- Added wrist twist/flex animation through `LHand` / `RHand`.
- Added subtle animated finger curl across all five finger chains on both hands so the hands no longer look frozen.

## 1.2.2 - 2026-08-07

### Changed
- Reworked the walk/jog pose again to remove the backward-leaning, goose-step look visible in side view.
- Greatly reduced torso lean, hip bob, arm swing, and stride amplitude.
- Retimed the knees so both legs keep a more natural bend during the step cycle.
- Softened foot rotation and simplified the arm pose for a more neutral overworld walk.

## 1.2.1 - 2026-08-07

### Changed
- Corrected the **arm swing direction** so the shoulders and elbows move the right way in side views.
- Reworked the **leg cycle** to reduce the awkward look: cleaner thigh swing, better knee timing, and softer foot planting.
- Slightly reduced the exaggerated jog amplitude so the motion reads more naturally in Dramatic Shape.

## 1.2.0 - 2026-08-07

### Changed
- Reworked the overworld procedural movement from a stiff walk into a jog-style cycle.
- Added explicit **elbow** articulation through `LForeArm` / `RForeArm`.
- Added stronger **knee** articulation through `LLeg` / `RLeg` plus foot planting on `LFoot` / `RFoot`.
- Added torso lean, hip bob, and subtle waist/hip twist so the animation reads more like forward motion and less like a flat shuffle.

## 1.1.0 - 2026-08-07

### Added
- Dramatic Shape / voxel-mode bridge so the real skinned Red model renders in the voxel pipeline instead of the stock player sprite card.
- Voxel visible-pass rendering, water reflection support, and volumetric shadow submission for the player model.

## 1.0.0 - 2026-08-07

### Added
- Full 107-joint runtime armature generated from the supplied Red COLLADA skin.
- CPU skinning for all 5,978 source points and 8,541 textured triangles.
- T-pose-to-idle arm posing plus procedural 16-frame walk-cycle limb motion.
- Four-direction facing, spinning-facing compatibility, and ledge-hop positioning/shadow support.
- Automatic fallback to stock rendering for fishing, surfing, and bicycle states.
