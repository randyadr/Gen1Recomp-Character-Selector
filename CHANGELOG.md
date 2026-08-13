## v3.1.21 - Android voxel-world pinch zoom

- Added two-finger pinch/spread zoom on empty Android overworld screen space while the voxel renderer is available.
- Normal voxel/orbit cameras use Gen1Recomp's survey zoom ladder; spreading fingers zooms in and pinching together zooms out.
- 3RD PERSON uses the installed voxel renderer's native continuous boom zoom (`ThirdPerson.scaleZoom`) when available, with a stepped fallback for nearby forks.
- 1ST PERSON ignores pinch because there is no external camera distance to change.
- Pinch MOVE events are claimed at the physical LOVE touch layer to prevent another touch/voxel wrapper from applying the same gesture twice; press/release still pass through so touch ids clear normally.
- Touch-control regions are excluded, and pinch participation permanently disqualifies those touches from the Android double-tap-to-3RD gesture.
- The number-3 ZOOM -> 1ST -> 3RD camera cycle, VR support, eight-way movement, animations, models, and character-specific fixes are unchanged.

## v3.1.20 - Android double-tap third-person shortcut

- Added an Android-only double-tap gesture that jumps directly to the voxel renderer's **3RD PERSON** camera rung.
- The gesture observes physical `love.touch*` callbacks before Game/state routing, so it still works when another state/mod consumes normal touch input.
- Double taps on the on-screen D-pad/A/B/control regions are ignored. Multi-touch and moved/dragged touches are excluded so camera look and pinch gestures do not trigger the shortcut.
- The shortcut only operates while the actual overworld is the top state; menus, dialogs, selector screens, battles, and launch UI are untouched.
- The v3.1.19 keyboard **3** cycle remains **ZOOM -> 1ST PERSON -> 3RD PERSON -> ZOOM**. VR, eight-way movement, animations, models, and character-specific fixes are unchanged.

## v3.1.19 - hard 3-key camera input fix

- Moved the requested **3-key** camera cycle above `Game:keypressed()` to LOVE's physical keyboard callback so a top state or another input wrapper cannot consume `3` before the camera shortcut sees it.
- Removed the `Pipelines.canToggle()` dependency that could reject the camera change even while the voxel renderer itself was active.
- Added an event-independent physical-key poll in `love.update`; if another callback swallows the keypress event, the held `3`/keypad `3` state still advances the camera exactly once per press.
- The cycle remains **ZOOM -> 1ST PERSON -> 3RD PERSON -> ZOOM** and only claims `3` while the actual overworld is the top state.
- Camera pipeline discovery is now fork-safe: it scans registered pipelines for live `1ST`/`3RD` labels instead of requiring the id to be exactly `voxel`.
- The selected pipeline level is pushed directly into the captured private VoxelState as an immediate compatibility backup, then persisted through the normal pipeline options.
- VR support, eight-way locomotion, animations, models, and all character-specific fixes are unchanged.

## v3.1.18 - number 3 camera cycle

- Replaced the v3.1.17 F6 companion shortcut with the requested **3-key** camera cycle.
- Press **3** to cycle **ZOOM -> 1ST PERSON -> 3RD PERSON -> ZOOM**.
- The cycle resolves the installed voxel renderer's live camera labels, preferring an explicit `ZOOM` level and otherwise using its normal `75` orbit rung before 1ST/3RD.
- From any other voxel camera level, the first press enters ZOOM so the three-stage sequence always starts consistently.
- Added the same edge-polling fallback used by the prior hotkey fix, including keypad `3`, while leaving menus and the Skin Selector's number keys untouched when the voxel pipeline cannot toggle.
- VR model support, third-person animation fixes, eight-way movement, and all built-in characters are unchanged.

## v3.1.16 - restore first/third-person camera hotkey

- Fixed the v3.1.15 regression where the voxel mod's own camera-cycle hotkey (F6 on the affected build) could stop switching between first-person and third-person.
- Removed the eager `V.require("VR")` call from the 3D-character bridge. Loading another mod's private VR module can install input/camera hooks as a side effect even when no headset session is running.
- VR detection is now passive: the character mod reads an already-captured `VR` table from the voxel pipeline's `drawWorld`, `update`, or render closure and never initializes VR itself.
- Preserves v3.1.15 first-person headless VR bodies, stereo pose reuse, tabletop/battle VR models, v3.1.14 third-person animation fixes, and v3.1.13 eight-way locomotion.

## v3.1.15 - VR 3D character support

- Added VR-aware rendering for the selected 3D character when Dramatic Shape or Dramaless Shape is running its OpenXR headset path.
- Diorama/tabletop VR and staged VR battles continue through the normal full-body replacement path, so the selected textured/animated model is rendered for both eyes instead of falling back to the stock player card.
- Added a dedicated first-person VR body pass because the voxel renderer intentionally suppresses the player's own card when the headset is inside the player's head.
- First-person VR uses a headless mesh: triangles primarily weighted to the Head bone and its descendants are removed so face/hair geometry cannot surround the near plane.
- The first-person body is normalized to the voxel VR rig's life scale, follows HMD yaw while keeping one grounded world transform shared by both stereo eyes.
- Both stereo eyes reuse the exact same prepared skinned pose, preventing left/right-eye gait or secondary-motion disagreement.
- Head-mounted accessories are skipped only in first-person VR to prevent hats/helmets from clipping into the headset; normal voxel, third-person, diorama VR, battle VR, shadows, selector previews, and accessories keep the full model.
- The static OceanGate Titan remains visible in tabletop/diorama and battle VR but is intentionally omitted from first-person VR because it has no humanoid Head/body rig and its hull would surround the headset.
- Added `DRAMALESS_SHAPE` as an optional dependency alongside `DRAMATIC_SHAPE`; non-VR and non-voxel rendering remains unchanged.

## v3.1.14 - third-person locomotion animation fix

- Fixed walk/run animations freezing in Dramatic Shape third-person while the same character still animated in regular voxel mode.
- Third-person/shadowless rendering now advances the exact same `beginVoxelFrame()` locomotion controller used by the normal voxel path.
- If the sun/shadow pass already prepared the current pose, the visible draw reuses it instead of advancing twice; if that pass is skipped, the visible draw becomes the frame source.
- Added a small duplicate-pass guard for renderer variants that invoke shadow or visible cast work more than once inside the same rendered frame.
- True eight-way movement, continuous travel-facing, walk/run clips, idle clips, jumping, and character-specific secondary animation all continue through the shared voxel animation state.

## v3.1.13 - directional locomotion animation fix

- Fixed eight-way movement visually sliding with the character stuck in idle on renderer paths where Gen1Recomp/Dramatic Shape did not expose a reliable `player.moving` flag.
- Locomotion now activates from the explicit diagonal-step marker, an outstanding movement target, **or actual X/Y displacement**. Real displacement is treated as the final source of truth.
- Keeps walk/run playback active for the full diagonal step, including render frames where tile interpolation repeats the same integer pixel.
- Applies to every animated built-in character while leaving static OceanGate Titan unchanged.

## v3.1.12 - true directional movement

- Added collision-safe **eight-way on-foot movement** to Gen 1 and Gen 2: up/down/left/right plus all four diagonals from keyboard, d-pad combinations, or the controller left stick.
- Diagonal steps use both map axes at once and keep the normal walking animation active for the full movement.
- Normalized diagonal step duration by `sqrt(2)` after the existing `movement.speed` hook, preventing diagonal movement from becoming ~41% faster than cardinal walking.
- Added strict corner checks: both orthogonal side cells and the diagonal destination must be legal and unoccupied, so diagonal movement cannot squeeze through walls or NPCs.
- Added continuous projected-render travel facing based on the real step vector. Characters now visibly face diagonal travel directions instead of snapping their 3D body to one of four sprite facings.
- Preserved cardinal `player.facing` for interactions, doors, ledges, scripts, and other engine systems.
- Bikes, surfing, fishing, Cycling Road/forced directions, map-edge connections, door carpets, currents, scripted steps, and special movement continue using the stock movement rules.
- Gold stores the raw left-stick X/Y pair before the stock input layer reduces it to one dominant axis, allowing real two-axis controller intent.

## v3.1.11 - Sabrina character

- Added Sabrina to the built-in Skin Selector.
- Converted the user-supplied 52-bone FBX skin (9,573 positions / 16,751 triangles).
- Added authored Idle, Catwalk Walking, Goofy Running, and Jumping animation clips.
- Generalized the existing native WOW_FBX locomotion blend so Sabrina can use its walk/run/jump sampler without inheriting Wow-specific selector/physics controls.
- Added the supplied Sabrina texture atlas and verified the source basis faces forward at the default selector camera.

## v3.1.10 - Ugandan Knuckles character

- Added **Ugandan Knuckles** as a built-in selectable character.
- Converted the supplied `Idle.fbx`, `Running(1).fbx`, and `Jump.fbx` into the mod's native 34-bone skinned animation format.
- Added the supplied `Knuckles_Texture.png` as the character atlas with FBX UV orientation corrected for the runtime.
- Preserved the authored Idle/Running/Jump poses while removing baked horizontal FBX root travel, so Gen1Recomp remains responsible for world movement and the model does not slide ahead of the player.
- Verified the converted bind pose reconstructs all 8,567 weighted positions with negligible numerical error and that the source forward axis shows the character's face without a yaw correction.

## v3.1.9 - BelleStarmon selector pose removal

- Removed BelleStarmon's selector pose option and disabled its old hidden static-pose path.
- BelleStarmon now always uses its normal animated selector idle; Wow's selector pose options are unchanged.

## v3.1.8 - source-basis forward fix (Naruto + BelleStarmon)

- Replaces the failed renderer-yaw workaround with a geometry-level 180° source-basis correction for Naruto and BelleStarmon.
- The correction is applied after skinning/secondary physics, so every rendering path receives the same canonical forward direction: Gold projected gameplay, the Gold selector fallback, Dramatic Shape/Voxel3D, selector Voxel3D, battle rendering, and rigid accessories.
- Naruto/BelleStarmon `modelYawOffset` and `projectYawOffset` are returned to zero to prevent double-compensation.
- FACE FLIP now applies consistently to projected, Voxel3D, battle, and selector rendering.
- One-time migration clears old Naruto/BelleStarmon FACE FLIP saves so v3.1.8 starts from the corrected default.
- `.red3dskin` export/import and donor-rig cloning preserve the new `sourceYaw180` metadata.

## v3.1.7 - correct intrinsic forward axis in viewer + Gold overworld

### Fixed
- Restored the intrinsic 180-degree model yaw for **Naruto** and **BelleStarmon**. Their source meshes are authored facing `-Z`, so the Voxel3D Skin Selector portrait must rotate them by pi to show their fronts at the default camera angle.
- Added a separate `projectYawOffset` for the ordinary projected renderer used by **Pokémon Gold / Gen 2**. Naruto and BelleStarmon now also receive a 180-degree correction in that path, so their bodies face the same direction they travel instead of running backward.
- Kept user **FACE FLIP** as an additional manual override rather than using it as the built-in orientation repair. Existing FACE FLIP saves therefore remain intact.
- Portable `.red3dskin` export/import now preserves `projectYawOffset`, and donor-rig clones inherit it from their donor, preventing the same forward-axis problem from returning after export/import.

### Compatibility
- Retains the v3.1.6 projected-preview centering fix and all existing selector, animation, physics, Gen 1, Gen 2, accessory, and import behavior.

## v3.1.6 - Naruto/BelleStarmon facing + reliable 3D selector previews

### Fixed
- Removed the legacy 180-degree voxel yaw corrections from **Naruto** and **BelleStarmon**. The current displacement-driven true-direction facing already supplies their travel bearing, so the extra pi rotation made both characters run while looking backward.
- Fixed the v3.1.5 non-voxel Skin Selector preview centering path. The fallback projected mesh was already fitted once, then received a second scale-dependent translation that could move differently-sized characters completely outside the preview canvas.
- The fallback now solves the projected player-foot origin from the measured silhouette centre and draws the positioned mesh without a second transform, so built-in characters remain framed even when Dramatic Shape / Voxel3D is unavailable or its portrait path fails.

### Compatibility
- Keeps the current Gen1Recomp `dev` mod API contract and the optional Dramatic Shape bridge; no engine files are bundled or replaced.
- Existing per-character SIZE, FACE FLIP, selector animation, imported skins, Gold bridge, accessories, and BelleStarmon physics settings are preserved.

## v3.0.62 - Wow slower jump + seamless root-motion-free run

- Fixed Wow's Goofy Running loop by treating its final key as the duplicate closing pose it actually is and cancelling the ~1.41-unit baked forward Hips travel across the cycle.
- Applied the same root-motion cancellation to Catwalk Walk (~1.38 units per cycle), while preserving vertical pelvis bob.
- Removed horizontal Hips root travel from Wow's Jumping / Running Jump playback; Running Jump contains ~7.03 units of baked forward motion and no longer visually launches the model ahead of the player.
- Running Jump is now blended in only from Wow's actual run blend, rather than whenever the player is simply moving.
- Slowed Wow's manual cosmetic jump from 30 to 48 frames (0.8 s at 60 Hz).
- Jump playback now samples a smaller central section of the long source clips with quintic timing and smooth locomotion-to-jump fade-in/fade-out, reducing fast-forwarded motion during short Gen1 hops.
- All other characters, OceanGate Titan, donor-rig importer, textures, selector poses, and physics settings are unchanged.

## v3.0.61 - static OceanGate Titan character

- Added the supplied OceanGate Titan model as a built-in selectable character.
- Titan is intentionally static: one identity root bone, no walk/idle/run/jump animation deformation.
- Titan still follows player position and turns with movement/facing, so it behaves like a floating vehicle replacement.
- Added a fixed 4-pixel hover offset above the ground for Titan.
- Combined the supplied main-body OBJ and glass OBJ into one renderer model.
- Built a 4096x4096 atlas from Titan_albedo and Glasst_albedo; the supplied glass opacity map drives alpha.
- Kept v3.0.60 donor-rig importer and every existing character unchanged.

## v3.0.60 - donor-rig clone importer experiment

- Added **CLONE RIG + IMPORT** to Character Import for edited versions of BelleStarmon/Wow.
- Added **DONOR RIG** selection between BelleStarmon and Wow. The imported character reuses the donor's exact bone hierarchy, rest matrices, behavior profile, locomotion clips, jump clips, and selector poses.
- Added surface-based skin-weight transfer. Unchanged body vertices use a fast exact bind-space match; newly added/modified geometry blends nearby donor surface influences and keeps at most four normalized bone weights.
- Transferred Belle/Wow secondary-motion masks alongside skin weights where donor data is available.
- Added loose `.obj`, `.fbx`, and `.dae` scanning in `red3d_characters/imports`; ZIP packages remain supported. OBJ MTL/textures may sit beside the loose model.
- Added model-axis repair toggles (**Swap Y/Z**, **Flip X/Y/Z**) plus small fit scale/XYZ offsets for exports whose coordinate convention differs from the donor.
- Imported donor clones are separate character entries and do not overwrite BelleStarmon or Wow. Saved clones are rebuilt from the source file on startup.
- Kept the previous manual humanoid rigger as an advanced fallback.
- Kept v3.0.59's removal of the **EDIT PHYSICS AREA / BREAST AREA** UI.

## v3.0.59 - BelleStarmon selector-pose retarget test + physics-area editor removal

- Removed the **BREAST AREA / EDIT PHYSICS AREA** controls from both desktop and mobile Character Settings for BelleStarmon and Wow.
- Kept the underlying default anatomical physics masks so breast/body physics still works without the unreliable interactive editor.
- Added Wow's three static selector poses to BelleStarmon as a compatibility test.
- Retargeted the poses by matching 46 shared bone names across the two rigs; Belle-only pinky and secondary-motion helper bones are not index-copied.
- BelleStarmon now exposes the same **SELECTOR POSE: POSE 1 / 3 ... POSE 3 / 3** control as Wow. This changes only the Skin Selector preview.

## v3.0.58 - Wow selector poses + texture orientation fix

- Fixed Wow's Skin Selector preview context so **SELECTOR POSE** now actually applies all three supplied Female Standing Pose clips.
- Corrected the replacement Wow model's FBX/LÖVE V-axis mismatch by vertically flipping each material tile **inside its existing atlas cell** instead of flipping or rearranging the whole atlas.
- Fixes the upside-down face and the incorrect vertical orientation on body/arm/leg/nail materials while preserving the model's material assignments.
- Uses a fresh `wow_new_atlas_v3058.png` path so the corrected texture cannot be hidden by the old cached atlas.
- Keeps the v3.0.57 model, cherry-red heels/panties, authored locomotion/jump clips, and physics/settings behavior.

## v3.0.57 - Wow selector fix + cherry red heels/panties

- Fixed the replacement Wow model bounds table so the renderer can construct her and the Skin Selector can list her normally.
- Selector label remains exactly **Wow**.
- Recolored the replacement model's high-heel material and matching panties/hip-garment material to cherry red (#D2042D).
- Uses a fresh `wow_new_atlas_v3057.png` atlas path.
- Keeps the new model, animation set, and three selector poses from v3.0.56.

## v3.0.56 - new Wow model, authored animation set, 3 selector poses

- Replaced Wow with the new model from `wow new(1).zip` and rebuilt its skinning/material atlas from the supplied body, arm, leg, nail, face, heel and hair assets.
- Replaced Wow locomotion with the supplied `Standing Idle`, `Catwalk Walking`, and `Goofy Running (1)` clips.
- Added the supplied `in place Jumping` and `Running Jump` clips; jump pose blends according to movement.
- Added all three supplied Female Standing Pose files to the Skin Selector. Use **SELECTOR POSE** in Character Settings to cycle Pose 1 / 2 / 3.
- Existing Wow breast/butt/thigh/hair physics settings and dual breast-area controls remain available on the rebuilt model.

## v3.0.55 - remove breast-size deformation

- Removed the experimental BREAST SIZE slider and all breast-size geometry scaling.
- Restored the pre-size-deformation breast physics behavior from v3.0.52.
- Kept the two independently positioned/resized breast physics circles, upper/lower physics limits, improved Character Settings mouse-wheel scrolling, Wow 75% torso atlas, slower walk/run timing, and the existing secondary-physics controls.

## v3.0.52 - dual breast circles + vertical limits

- Breast Physics Area editor now has **two independent circles**, one for each breast.
- Each circle can be dragged separately and has its own radius slider.
- Mouse wheel in the preview resizes the currently active circle.
- Added **UPPER LIMIT** and **LOWER LIMIT** sliders with visible horizontal guide lines in the preview.
- Upper/lower limits softly clamp the breast physics vertically to reduce neck/abdomen spill.
- Circle positions, radii, and limits save separately for Belle and Wow.
- RESET AREA restores both circles and both limits.

## v3.0.51 - Breast Physics Area editor + true settings scrolling

- Added **BREAST AREA** editing for Belle and Wow. Entering the editor snaps the 3D preview to front view and shows a circular breast-physics mask overlay.
- Drag anywhere on the preview while the editor is active to move the circle. Mouse-wheel over the preview changes its radius, and an **AREA RADIUS** slider provides the same adjustment.
- Added **RESET AREA** and per-character saved X/Y/radius values. The custom circle multiplies the existing safe precomputed breast mask, so it cannot suddenly enable unrelated torso vertices.
- Reworked desktop mouse-wheel Character Settings browsing to scroll the visible settings window itself rather than only moving the selected row.

## v3.0.50 - forced 75% Wow torso texture

- Repacked Wow to use the user-supplied `75%.png` torso/chest texture explicitly.
- Wrote the 75% texture into the packaged Wow atlas files and switched Wow to a brand-new atlas filename: `wow_atlas_75pct_v3050.png`.
- This is a cache-busting refresh intended to make the slight torso/chest texture change actually appear in-game.
- Keeps v3.0.49 flowing hair improvements and mouse-wheel browsing for Character Settings.

## v3.0.48 - texture refresh + slower walk/run

- Kept the slower corrected Wow walk/run playback from v3.0.47.
- Repacked Wow with a fresh atlas file path so the new torso/chest texture cannot be hidden by a stale cached atlas.
- Verified the packaged Wow atlas contains the user-supplied torso/chest texture in the main upper-body region.

## v3.0.47 - Corrected Wow walk/run playback speed

- Simulated Wow's distance-driven gait timing against the supplied Catwalk Walk and Goofy Running clip durations.
- The previous run cycle could loop in roughly 0.40 seconds at full run speed even though the supplied run animation is about 0.63 seconds long.
- Changed Wow's locomotion gait distance to 52 pixels per cycle, giving roughly 1.24 seconds per walk cycle at 42 px/s and 0.65 seconds per run cycle at 80 px/s.
- High-frequency breast/butt/thigh/hair physics remains unchanged; animation speed and physics update frequency are separate.
- Keeps the v3.0.46 torso texture and flowing lower-back hair changes.

## v3.0.46 - Wow chest texture + improved flowing hair

- Replaced Wow's main torso/chest texture with the user-supplied torso texture.
- Tuned hair physics to look more flowing and natural, with extra emphasis on the lower back section of the hair.
- Increased hair motion range and softened the hair spring so the bottom rear hair can lag and sway more visibly.
- Kept the stable precomputed mask system for buttocks/thigh/hair so enabling those options does not break rendering.

## v3.0.45 - Stable precomputed butt/thigh/hair masks

- Fixed the v3.0.44 crash when enabling BUTTOCKS: the renderer no longer calls any runtime butt/thigh/hair region helper.
- Buttocks, thighs, and hair now all use precomputed per-vertex masks stored in Belle/Wow model data.
- Rebuilt Wow buttocks placement from the actual bind-pose rear/glute coordinates: 545 selected vertices, 237 strong-center.
- Wow thigh mask: 783 selected vertices; Wow hair mask uses the known separate hair geometry (6686 vertices).
- Belle retains its authored butt/thigh masks with stronger butt visibility and gains a conservative precomputed rear-head hair mask.
- Keeps breast/butt/thigh/hair toggles, sliders, independent breast/butt/thigh controls, PC mouse controls, and mobile touch controls.

## v3.0.44 - Better butt placement + thigh/hair physics

- Recentered and strengthened buttocks physics so the motion sits more clearly on the glute area instead of feeling too high/low or too weak.
- Added new **THIGHS** toggle + **THIGH PHYSICS** slider + **INDEPENDENT THIGHS** toggle for Belle and Wow.
- Added new **HAIR** toggle + **HAIR PHYSICS** slider for Belle and Wow.
- Kept breast and buttocks physics, independent toggles, PC mouse controls, and mobile controls.

## v3.0.42 - Recovery / renderer fix

- Rebuilt from v3.0.40 rather than continuing from the broken v3.0.41 renderer path.
- Removed the undefined `red3dFinitePhysicsNumber` calls that could abort model rendering.
- Belle buttocks physics now uses only the localized post-skin region; butt helper bones remain neutral to avoid double deformation/disappearing meshes.
- Desktop selector remains on the PC mouse path; only Android/iOS use the dedicated mobile layout.
- Keeps v3.0.40 breast/buttocks strength sliders and independent-movement switches.

## v3.0.40 - Independent motion switches

- Added **INDEPENDENT BREASTS** and **INDEPENDENT BUTTOCKS** toggles for Belle and Wow.
- Each toggle saves separately per character.
- Independent ON keeps separate left/right spring timing, alternating impacts and settling.
- Independent OFF synchronizes the pair, sharing vertical/depth motion and mirroring lateral motion.
- Each independent toggle only appears while its matching physics region is enabled.
- Keeps butter-smooth filtering, phone touch UI, conditional strength sliders, and v3.0.39 buttocks placement.

## v3.0.39 - Buttocks physics + saved dual-region controls

- Added a second saved physics region for Belle and Wow: **BUTTOCKS** with a conditional **BUTTOCKS PHYSICS** strength slider, matching the existing breast-physics UI behavior.
- Added independently simulated left/right buttocks motion using the same filtered/smoothed spring presentation system used for butter-smooth breast physics.
- Belle now uses the model's authored buttocks region/weights so the motion stays properly located on the glute area.
- Wow now adds a conservative rear-hip/glute surface mask so buttocks motion stays on the back of the body instead of the side chest or torso.
- Breast and buttocks checkboxes save independently for Belle and Wow, and each region can be enabled/disabled without affecting the other.
- Mobile and desktop selector layouts both show the new BUTTOCKS toggle/slider, with the slider only appearing while the toggle is enabled.

## v3.0.38 - Butter-smooth independent breast physics

- Smoothed Belle and Wow breast physics without removing the independent left/right simulation introduced in v3.0.37.
- Internally oversamples the spring integration at a minimum of 240 Hz while retaining the existing 120 Hz response profile, reducing sensitivity to uneven phone frame times.
- Added frame-rate-independent low-pass filtering to each breast's target so animation/gait sampling changes cannot become one-frame twitch impulses.
- Added filtered movement acceleration input so tiny speed/delta-time fluctuations do not jerk the breast target.
- Added a separate presentation layer: the hidden spring keeps its full independent position/velocity state while the rendered breast motion smoothly follows it, preventing the visual filter from feeding back into the physics solver.
- Left and right target filters, spring bodies, and output positions remain fully separate; the single BREAST PHYSICS slider still controls overall strength only.
- Keeps all v3.0.37 mobile/touch controls, mobile Physics reachability, Wow animation/texture fixes, character importing/renaming, and accessory support.

## v3.0.37 - Independent left/right breast physics

- Split Belle and Wow breast motion into visibly independent left/right spring behavior while retaining the single saved PHYSICS checkbox and BREAST PHYSICS strength slider.
- Left and right breasts now use separate gait phases, separate idle oscillators, and alternating footfall impulses, so one side can still be settling while the other reacts to the next step.
- Each side has its own spring response/damping values and keeps completely separate position/velocity state; there is no left/right spring coupling.
- Jump/landing motion remains shared from character movement, but each side receives a slightly different drive and spring response so they do not move as a locked pair.
- Keeps v3.0.36 mobile Physics reachability, touch camera controls, Wow's native animation/texture fixes, character renaming/import rigging, and accessory importing.

## v3.0.36 - Mobile settings / Physics reachability

- Fixed Belle/Wow **PHYSICS** controls being unreachable on small phone/internal render resolutions.
- In mobile mode, **PHYSICS** is now the first Character Settings row for Belle and Wow, so it remains visible even when only one settings row fits.
- When PHYSICS is enabled, **BREAST PHYSICS** becomes the second row and mobile focus jumps directly to it. Turning Physics off returns focus to the PHYSICS row.
- Moved the mobile Character Settings **▲ / ▼** paging buttons into the settings title bar, keeping them reachable instead of allowing the lower arrow to fall behind the footer on short screens.
- Added persistent mobile settings paging so every Character Settings control can be reached one row at a time on low-resolution phone layouts.
- Updated phone hints to call out the settings ▲/▼ paging controls.
- Keeps all v3.0.35 touch camera controls and v3.0.34 Wow animation fixes.

## v3.0.35 - Mobile Touch Skin Selector

- Added an Android/iOS-aware phone layout for the Skin Selector while retaining the existing desktop layout on PC.
- Touch input automatically enables mobile mode on touchscreen hosts even when the OS name is not Android/iOS.
- Enlarged character rows, settings rows, toggles, +/- buttons, scroll arrows, and footer actions for finger-sized hit targets.
- Added a permanent 3D-preview touch camera strip: **ORBIT**, **PAN**, **ZOOM -**, **ZOOM +**, and **RESET**.
- One-finger preview drag orbits or pans according to the selected touch camera mode.
- Added two-finger gesture tracking: midpoint movement pans the camera and changing finger distance pinch-zooms the preview.
- Touch releases preserve the remaining finger during a two-finger gesture instead of cancelling the full preview interaction.
- Phone mode no longer relies on desktop mouse polling or the mod-drawn desktop cursor, preventing fake/captured mouse state from fighting touch input.
- Mobile rename requests the host software keyboard via `love.keyboard.setTextInput` when supported.
- Keeps all v3.0.34 behavior, including Wow's rigid quaternion run sampling and seamless loop.

## v3.0.34 - Wow run interpolation / loop repair

- Reworked Wow's supplied `Goofy Running (1).fbx` playback instead of changing to a different animation. The newly re-uploaded FBX is byte-for-byte identical to the clip in `wow.zip`, confirming the visible glitch came from runtime sampling rather than the source file.
- Wow now interpolates authored FBX rotations with quaternion slerp and translation-only linear interpolation, preventing temporary scale/shear artifacts caused by element-wise 4x4 matrix blending.
- The Goofy Running clip contains unique keys through its last frame rather than a duplicate closing key, so Wow now interpolates the final run frame directly back to frame zero for a seamless loop.
- Walk-to-run and idle-to-locomotion blending for Wow also use rigid-transform interpolation.
- A separate jump FBX was not present in the conversation files at build time, so this build retains v3.0.33's current jump fallback until that file is supplied.

## v3.0.32 - Wow native rig, supplied animations, textures + breast physics

- Rebuilt **Wow** from the native Mixamo skeleton and skin clusters already present in the user's supplied FBX files instead of the v3.0.31 generic auto-rig. This removes the generic arm-axis posing that caused the long/stretched/curling arms.
- Wow now uses the supplied **Idle.fbx**, **Catwalk Walk Forward HighKnees.fbx**, and **Goofy Running (1).fbx** directly. Locomotion root translation is made in-place for overworld use while preserving the authored bone motion. No unrelated generic arm animation is applied during jumps.
- Rebuilt Wow's atlas/material mapping from the textures actually supplied in `wow.zip`: `DVD Sized.png` for body, arm/leg diffuse maps, nails, and `wow1.png` for the face/head fallback. Missing external eye/hair/heel maps referenced by the FBX use neutral material colors rather than corrupting the body texture.
- Added localized `LBreast` / `RBreast` helper weights to Wow and the same simple saved **PHYSICS** checkbox + conditional **BREAST PHYSICS** strength slider used by Belle. Wow physics is OFF on a fresh save and uses its own save keys.
- Preserves per-save renaming, Character Import rigger, OBJ/FBX/DAE accessory importing, rigid bone attachments, Blender-style selector camera, right-click-safe input, and startup animation-speed stabilization.

## v3.0.31 - Wow character + saved character renaming

- Added the user-supplied `wow.zip` model as a normal built-in selectable character named **Wow**. The included character was rebuilt from `Idle.fbx`, converted from Z-up to the selector's Y-up model space, auto-rigged to the generic humanoid skeleton, and packed with a generated texture atlas using the supplied face/body/arm/leg/nail textures plus safe fallback materials for missing eye/hair/heel maps.
- Added a **NAME / RENAME** control to every normal character settings panel. Click it, type a new name, press **Enter** to save, **Backspace** to edit, or **Esc** to cancel.
- Custom names are stored per save using the stable internal character ID, so renaming never breaks selection, animations, Belle physics, rig data, accessories, or exports.
- Skin Selector rows and the large preview heading update immediately after a rename and restore the saved custom name on the next boot.
- Improved experimental humanoid-rig memory/performance by deduplicating repeated triangle-corner positions before auto-weighting while preserving per-corner UVs.

## v3.0.30 - First-class Character Import + improved humanoid rigger

- Moved humanoid rigging out of the Accessories editor. **IMPORT CHARACTER** now appears directly in every character's normal Character Settings panel.
- Added a dedicated `red3d_characters/imports/` ZIP folder for OBJ/FBX/DAE character source models. Existing v3.0.29 rigs sourced from the accessory folder still restore for backward compatibility.
- New workflow: **Character Settings > Import Character > Scan Character ZIP Folder > choose model/texture > Rig Humanoid Character > Save to Character Selector**.
- Saved rigs are normal Character Selector entries; they are not accessory attachments.
- Improved automatic humanoid setup from 16 to 17 editable markers by adding an explicit Spine marker and using mesh slices/extremity clusters to estimate torso centre, shoulders, hands, hips, knees, and feet more robustly.
- Reworked automatic skin weighting with anatomical side/limb/torso gates so arm weights are less likely to bleed into the torso and leg weights are less likely to cross the pelvis. Up to four normalized influences are retained per vertex.
- Added **Weight Style: Tight / Balanced / Soft** in addition to the Weight Blend slider.
- Added direct front-view joint editing: click and drag a joint dot to move its X/Y position; use the existing Z slider for depth. Clicking a joint marker snaps the rig view to Front for predictable editing.
- Added **Front View / Reset Camera** inside the rigger while retaining the Blender-style orbit/pan/zoom camera for inspection.
- Character Import includes texture image selection plus UV mapping/flip/swap controls before rigging.
- Retains v3.0.29/v3.0.28 startup animation stability, DAE/OBJ/FBX importing, rigid accessories, conditional Belle breast slider, and all selector camera/input fixes.

## v3.0.29 - Experimental in-game humanoid rigger

- Added an experimental **RIG AS HUMANOID** workflow for static OBJ/FBX/DAE models already scanned by the accessory importer.
- Auto-generates a 20-bone humanoid skeleton and an initial set of hips/chest/head/arm/leg joint markers from the imported mesh bounds.
- Added joint-by-joint X/Y/Z editing, optional left/right mirror editing, weight-blend softness, arm-rest tuning, and character-height tuning.
- Added **UPDATE ANIMATED PREVIEW** / auto-weight generation. The generated mesh uses up to four nearby bone influences per vertex and previews through the existing GENERIC idle/walk/jump controller.
- Added approximate front-view joint/skeleton markers over the Skin Selector preview to make joint placement easier while tuning.
- Added **SAVE RIGGED CHARACTER**. Saved rigs appear as normal selector characters and are rebuilt from the original import ZIP on later loads for that save slot.
- The rig inherits the accessory's currently selected texture and UV flip/swap choice at the time the rig editor is opened.
- Rigged-character state is isolated per game save and cleared/reloaded on save-slot changes.
- Retains v3.0.28 conditional Belle breast slider, DAE/OBJ/FBX importing, rigid accessories, texture fixes, Blender-style preview camera, and startup animation-speed stabilization.

## v3.0.28 - Conditional breast-physics slider

- BelleStarmon now shows only the **PHYSICS** checkbox while breast physics is disabled.
- The single **BREAST PHYSICS** strength slider appears directly underneath only after **PHYSICS** is checked.
- Unchecking **PHYSICS** hides the slider without erasing its saved value; re-enabling physics restores the previous slider setting.
- Keeps v3.0.27 startup animation-speed stabilization, DAE/OBJ/FBX accessory importing, rigid animated-bone attachments, texture fixes, Blender-style preview camera, and the tightened breast-only deformation area.

## v3.0.27 - Startup animation speed stabilization

- Fixed characters occasionally booting with abnormally fast locomotion animation.
- Replaced single-sample measured gait speed with a five-sample median filter and require three valid samples before measured speed can control cadence.
- Rejects ultra-short render-boundary speed samples that could interpret a one-pixel movement as near-240 px/s.
- Adds a short startup grace period where stock step timing is preferred, and clears speed history on map/position discontinuities.
- Tightened animation delta-time hitch clamping from 100 ms to 50 ms.
- Skin Selector previews now use their own bounded accumulated animation clock instead of absolute timer phase, preventing boot/focus timer jumps from altering preview playback.
- Keeps DAE/OBJ/FBX importing, rigid animated-bone accessories, the single Belle breast-physics slider, and all v3.0.26 selector features.

## v3.0.26 - Collada DAE accessories + rigid animation attachment

- Added Collada `.dae` static accessory importing alongside OBJ and FBX.
- DAE import reads common triangles/polylist/polygons geometry, source/accessor strides, UV coordinates, Y/Z/X-up conversion, material symbols, Collada effects, and external diffuse image references from the ZIP.
- Reinforced accessory attachment as bone-local placement: saved X/Y/Z, rotation, and scale are evaluated against the selected character's current animated bone every frame, so placed hats/necklaces/etc remain glued to the character through idle, walking, running, jumping, and selector animations.
- Keeps v3.0.25's single breast-physics slider and all existing camera/texture repair features.

## v3.0.25 - Single breast physics slider

- Added one BelleStarmon **BREAST PHYSICS** slider beneath the existing PHYSICS master checkbox.
- Slider range is 0%-150%; 100% exactly matches the v3.0.24 tuned breast motion.
- The slider scales the complete breast effect without exposing the old movement/impact/idle/response matrix.
- Slider value saves per game; PHYSICS remains the master on/off switch.
- Keeps the tightened breast-only region, calmer v3.0.24 spring profile, Blender-style preview camera, and accessory importer/material fixes.

## v3.0.24 - Tighter breast area, slightly calmer bounce

- Keeps BelleStarmon's tightened v3.0.22 breast-physics area so the motion stays on the breast mound instead of the side chest.
- Reduces the visible breast bounce slightly so the motion is less aggressive while keeping the same overall feel.
- Tuned the fixed PHYSICS preset from 160% visible strength to 135%, with slightly lower movement/landing/idle response and a little more damping.
- Keeps the Blender-style preview camera, right-click-safe selector input, accessory UV/material fixes, and breast-only physics checkbox behavior.

## v3.0.22 - Belle breast-region tightening

- Tightened BelleStarmon's anatomical breast-physics mask so the motion stays on the actual breast mound instead of bleeding into the lateral side chest/armpit area.
- Added a stronger front-breast gate plus new inner/outer side gates, while preserving the under-bust exclusion and upper-chest fade-out.
- Keeps v3.0.21's Blender-style orbit/pan/zoom preview camera, right-click-safe selector input, multi-material accessory texture importing, and doubled breast-physics strength.

## v3.0.20 - Double breast physics strength

- Doubled BelleStarmon visible breast-physics strength from 40% to 80%.
- Preserved the existing movement, landing, idle, response-speed, damping, and 120 Hz solver timing so this is an amplitude increase rather than a speed/frequency change.
- Retains the single saved PHYSICS checkbox, breast-only secondary motion, accessory importer, texture fixes, and preview zoom.

## v3.0.19 - Preview wheel zoom + accessory texture repair

- Added mouse-wheel zoom for the Skin Selector 3D preview. Hover the portrait and wheel up/down to zoom; zoom is clamped to a safe 0.55x-2.60x camera range and never affects gameplay/world zoom while the pointer is over the preview.
- Updated the preview hover/footer help to advertise wheel zoom alongside drag-to-rotate.
- Accessory ZIP importing now keeps up to 16 plausible texture images instead of permanently choosing one file. The importer prioritizes OBJ MTL references, FBX-embedded filenames, matching model stems, and diffuse/albedo/base-color names while de-prioritizing normal/roughness/metal/specular/mask maps.
- Added saved per-character/per-accessory **TEXTURE IMAGE** selection so a wrong automatic texture can be corrected live without repacking the ZIP.
- Added saved texture-fix checkboxes: **FLIP TEXTURE U**, **FLIP TEXTURE V**, **SWAP U/V**, **REPEAT TEXTURE**, and **PIXEL FILTER**. These update the live preview immediately and are applied in gameplay too.
- Added **RESET TEXTURE FIXES** to return to the importer's preferred image and normal UV/filter/wrap behavior without changing attachment position/rotation/scale.
- Rescanning a ZIP now rebuilds texture GPU resources so replacing an image inside a same-named ZIP actually refreshes instead of reusing the old cached texture.
- Retains v3.0.18's working Belle PHYSICS checkbox, accessory bone attachment editor, manual preview rotation, and skin import/export.

## v3.0.18 - Belle Physics checkbox visible-motion fix

- Fixed the PHYSICS checkbox appearing to turn on while the breast motion remained effectively invisible.
- Kept the fixed 40% Strength / 44% Movement / 113% Jump-Landing / 92% Idle / 83% Response preset requested by the user.
- Removed the second over-damped attenuation layer that was suppressing that preset in v3.0.16/v3.0.17.
- Uses a responsive 120 Hz direct-target spring with tight travel limits and mostly vertical/front-back motion.
- Turning PHYSICS ON seeds a tiny one-time preview impulse so the selector gives immediate visual confirmation.
- PHYSICS OFF still clears breast spring position and velocity immediately; thigh/buttocks physics remain disabled.

## v3.0.16 - Belle Physics checkbox runtime fix

- Fixed the BelleStarmon **PHYSICS** checkbox changing saved/UI state without reliably driving the live renderer.
- Added one dedicated `runtimeBellePhysicsEnabled` boolean shared by selector UI, preview springs, gameplay skeleton deformation, and post-skin breast follow.
- Checkbox UI now reads the live renderer state immediately instead of round-tripping through `mod.save`, so a click takes effect on the same frame.
- Enabling Physics reapplies the fixed breast preset and resets stale spring momentum; disabling Physics zeros spring position/velocity immediately.
- Uses a new v3.0.16 per-save enable key so upgrades start OFF until deliberately enabled, then persist normally.
- Corrected the fixed preset to the values shown in the user's reference screenshot: 40% Breast Strength, 44% Movement Bounce, 113% Jump/Landing, 92% Idle Sway, 83% Response Speed, at 120 Hz.
- Thigh and buttocks physics remain disabled; unified selector layout and manual-only preview rotation remain unchanged.

## v3.0.14 - Hidden breast physics panel + controller icons

- BelleStarmon now has **breast physics only**. `LThighSoft/RThighSoft` and `LButt/RButt` remain neutral bind-compatible helper bones; there are no thigh/butt spring nodes or post-skin offsets.
- Belle's normal settings view is intentionally clean and shows only **SIZE** plus a small unlabeled gear button. Clicking the gear, pressing keyboard **P**, or pressing controller **R3** opens/closes the hidden breast physics panel.
- Restored live slider bars for **Breast Strength**, **Movement Bounce**, **Jump / Landing**, **Idle Sway**, and **Response Speed**, plus a Breast Physics ON/OFF checkbox.
- The underlying DOA-inspired spring profile and 120 Hz direct-target stepping remain fixed; the sliders tune amplitude/drive without reintroducing style/rate clutter.
- Added drawn controller-button icons and matching live controls in the Skin Selector footer: D-pad navigation/rotation, L3 setting cycle, X/Y adjustment, LB export, RB import, A use skin, B back, and Belle-only R3 physics options.
- Existing mouse cursor, slider dragging, preview rotation, import/export, Alt-Tab recovery, and selector-only Belle animation are retained.

## v3.0.13 - Belle preview repair + arcade breast physics

- Fixed BelleStarmon selector preview failure introduced when buttocks physics was removed. Neutral `LButt/RButt` helper bones are held at bind pose rather than sampled from the shorter selector FBX.
- Added bounds checking to embedded animation sampling so short imported/selector clips cannot crash the whole preview.
- Buttocks physics stays removed.
- Breast physics now uses a DOA-inspired arcade response with faster spring stiffness, lower damping, independent left/right timing, stronger movement/impact targets, and explicit takeoff/landing velocity kicks.
- Added conservative translation/velocity clamps so the more energetic profile remains stable after hitches.
- Retained the v3.0.12 lower-breast and upper-thigh anatomical masks and the simple checkbox-only UI.

## v3.0.12 - Portable skin packages + Belle physics region cleanup

- Added single-file `.red3dskin` export/import support to the Skin Selector.
- **EXPORT** packages the highlighted character's generated model Lua, texture atlas frames, and renderer metadata into the writable `red3d_skins/exports/` directory.
- **IMPORT** scans `red3d_skins/imports/`, validates new packages, compiles their model data, creates renderers, and adds them to the live selector without overwriting built-ins with matching IDs.
- Declared the Gen1Recomp `filesystem` manifest permission required by the portable package workflow; imported model chunks execute in an empty environment and package/model/atlas payloads have explicit safety-size caps.
- Removed BelleStarmon buttocks secondary motion from the solver, skeletal helper-bone animation path, post-skin surface follow layer, and selector controls.
- Raised BelleStarmon's lower thigh physics cutoff from the knee-side region to a smooth 0.815-0.875 model-Y fade so only upper/mid thigh tissue participates.
- Added a smooth 1.710-1.755 model-Y upper breast cutoff so the physics sits lower on the chest while preserving the under-bust exclusion.
- BelleStarmon selector controls are now SIZE, BREAST PHYSICS, and THIGH PHYSICS only.
- Fixed recommended fixed strengths to 102% breast and 104% thigh on the existing 120 Hz classic direct-target solver.

## v3.0.11 - Simplified Belle physics checkboxes

- Replaced BelleStarmon's exposed physics tuning matrix with three persistent on/off checkboxes: breast, thigh, and buttocks physics.
- All three regions default ON. OFF sets that region's amplitude to zero; ON restores the built-in recommended amplitude.
- Uses one fixed recommended profile: 120 Hz classic direct-target substepping, full 3D targets, responsive medium-low damping, stronger locomotion/landing drive, and reduced idle sway.
- Fixed internal region amplitudes to 108% breast, 90% thigh, and 108% buttocks.
- Legacy style/axes/rate/movement/impact/idle/response save values are ignored by the active solver so old tuning cannot degrade the current feel.
- Kept the SIZE control because it is character scale, not a physics tuning slider.
- Updated mouse hit testing/drawing so the new physics rows are real clickable checkboxes while keyboard/controller navigation remains available.

## v3.0.10 - Restore classic direct-target Belle physics

- Restored the punchier pre-v3.0.9 direct-target spring behavior for breast, thigh, and buttock secondary motion.
- PHYSICS RATE now sets the maximum spring integration step (60/90/120/144/240 Hz) instead of running a target-interpolating fixed accumulator.
- Every host/game update applies its newest movement, acceleration, jump, and landing target immediately to all spring substeps, preserving sharp impulses and visible overshoot.
- Default 120 Hz at 60 FPS produces two direct substeps per frame, matching the v3.0.8 spring integration pattern.
- Removed v3.0.9 previous-target interpolation/accumulator state from the active solver while retaining all v3.0.8+ anatomy, cursor, Alt-Tab, selector animation, and mouse fixes.

## v3.0.9 - BelleStarmon fixed high-rate physics

- Added a persistent **PHYSICS RATE** setting with **60 / 90 / 120 / 144 / 240 Hz** options; new/old saves without the setting default to **120 Hz**.
- Replaced the previous automatic 90-Hz-ish spring sub-step rule with a true fixed-rate accumulator so the selected value is the actual secondary-physics integration frequency.
- Interpolates breast, thigh, and buttock target vectors between game/animation updates on every internal physics tick, improving high-rate motion continuity instead of repeating the same low-rate target.
- Caps catch-up work to 16 physics steps after a hitch or focus transition, preventing large burst updates.
- Raised the Skin Selector portrait refresh ceiling from **30 FPS to 60 FPS** so the higher-rate physics is visible more clearly while tuning.
- Keeps **RESPONSE SPEED** separate from simulation rate: rate changes temporal sampling/smoothness; response changes spring frequency/damping behavior.
- BelleStarmon now exposes eleven selector rows, with PHYSICS RATE inserted after PHYSICS AXES. Mouse/controller/Tab navigation reaches all eleven rows; keyboard 1-9/0 still jumps directly to the first ten.

## v3.0.8 - Skin Selector Alt-Tab / multi-monitor mouse recovery

- Refined BelleStarmon’s secondary-motion skinning in bind-pose/model space so each physics region stays on the intended anatomy.
- Breast helper influence now smoothly fades out across the under-bust edge and front torso wall, removing the upper-abdominal strip that could move with breast bounce. Remaining skin weights are renormalized so the neutral/bind body shape does not change.
- Upper-thigh physics now trims only the extreme knee/groin fringe, and buttock physics now softens the lower/top pelvis and forward seam edges to prevent region bleed without shrinking the main soft-tissue areas.
- Fixed Alt-Tab from the Skin Selector leaving the mouse hidden, captured, or stuck in a stale drag state on another monitor.
- The selector now releases LÖVE mouse grab and relative mode while it is open, while remembering their previous values for restoration on close.
- Focus loss immediately cancels slider/model drags, clears polled button state, restores the native OS cursor, and releases capture.
- Focus regain re-seeds the live cursor position, restores the selector's software-cursor presentation, and suppresses synthetic menu input from the transition.
- Mouse polling is completely paused while the game is unfocused so clicks on another monitor cannot become phantom selector input when returning.

## v3.0.7 - Skin Selector mouse drag rotation fix

- Fixed preview drag rotation on mouse backends where pointer movement events provide missing/zero `dx` values by calculating delta from the previous absolute cursor X coordinate.
- Fixed the older polling fallback so movement is forwarded while either a slider **or the 3D model preview** is being dragged.
- Added compatibility for `moved`, `move`, and `dragged` pointer phase names.
- Pause the model viewer's automatic showroom spin while dragging, then resume it on release/close for direct 1:1-feeling mouse control.

## v3.0.6 - Skin Selector left-click close fix

- Fixed desktop left-clicks being mirrored into the hidden native `ListMenu` confirm/cancel input and immediately closing the HD Skin Selector.
- Mouse/touch presses handled by the custom selector now suppress the underlying native menu update for a short input window, so character preview rows, physics controls, sliders, arrows, and model dragging stay inside the selector.
- **USE THIS SKIN**, **BACK**, right-click Back, keyboard/controller selection, and the existing custom cursor behavior remain intact.

## v3.0.5 - Visible custom cursor + BelleStarmon selector animation

- Added a high-contrast cursor drawn by the mod itself at the live mouse position, fixing Gen1Recomp hosts where mouse clicks worked but the captured OS cursor remained invisible.
- Hide the native cursor only while the selector is active and restore its prior visibility when the selector closes.
- Converted the supplied `Goofy Running.fbx` 39-key / 60 Hz Mixamo clip into an embedded BelleStarmon selector-only animation. Root translation is removed so the preview stays centered and the first pose is duplicated as the closing key for a clean loop.
- Retargeted all 52 imported BelleStarmon bones from source FBX axes into the mod runtime axes. The six secondary-motion helper bones remain driven by the existing spring physics while the clip plays.
- The preview sets the selector animation flag only for its own skeleton update and clears it immediately afterward, including the error path, so gameplay animations cannot inherit the menu-only clip.

## v3.0.4 - Mouse-first Skin Selector UI

- Rebuilt the Skin Selector layout around a clearer character list and dedicated settings card. On normal desktop resolutions BelleStarmon now shows the live 3D preview beside the complete physics/body control panel instead of cramming controls below the model.
- Added Gen1Recomp `input.pointer` integration for real mouse/touch pointer events while the selector is active, without changing pointer behavior elsewhere in the game.
- Added mouse hover feedback and visible system cursor states.
- Character rows are clickable for preview; **USE THIS SKIN** applies the highlighted character, **BACK** closes the menu, and right-click also acts as Back.
- Numeric settings now have clickable minus/plus buttons plus click-and-drag slider tracks with 1% mouse precision.
- Choice settings (PHYSICS STYLE / PHYSICS AXES) now have dedicated clickable previous/next controls.
- The live 3D preview can be dragged horizontally with the mouse to rotate the model.
- Added clickable list/settings scroll arrows so hidden rows remain accessible with mouse-only navigation at small window sizes.
- Kept all existing keyboard/controller navigation and adjustment bindings intact.
- Added a polling mouse fallback for older Gen1Recomp builds that do not emit the pointer hook.

## v3.0.3 - BelleStarmon advanced physics lab

- Expanded **PHYSICS STYLE** from three to seven saved profiles: **SOFT**, **NATURAL**, **SPRINGY**, **TIGHT**, **HEAVY**, **FLOATY**, and **JELLY**.
- Added a saved **PHYSICS AXES** mode with **FULL 3D**, **VERTICAL**, **FRONT / BACK**, and **SIDE / SIDE** choices. Disabled axes are zeroed at the spring target and switching modes clears old axis momentum.
- Added saved **MOVEMENT BOUNCE** (0%-200%) so walk/run/acceleration-driven motion can be tuned separately from jumps and idle.
- Added saved **JUMP / LANDING** (0%-200%) for takeoff/landing impulse strength. The selector preview now injects a periodic test impulse so this setting is visible live.
- Added saved **IDLE SWAY** (0%-200%) to independently reduce or exaggerate standing secondary motion.
- Added saved **RESPONSE SPEED** (50%-200%). Stiffness scales with speed squared and damping scales with speed so each style keeps roughly the same damping character while reacting faster or slower.
- BelleStarmon's selector now has ten controls and automatically scrolls the control stack while retaining the large 3D preview. Tab/L3 cycles rows; keyboard **1-9** and **0** jump directly to rows 1-10.
- Existing breast, thigh, and buttock 0%-200% strength controls remain independent and compatible with every new style/axis/advanced setting.

## v3.0.2 - BelleStarmon selectable physics styles

- Added a persistent **PHYSICS STYLE** control to BelleStarmon with **SOFT**, **NATURAL**, and **SPRINGY** response profiles.
- **SOFT** uses lower stiffness and much higher damping for slower, cushioned body motion with minimal rebound.
- **NATURAL** keeps the v3.0.1 under-damped response as the default style.
- **SPRINGY** uses higher stiffness, lower damping, and a slightly stronger target response for faster rebound and longer visible overshoot.
- Physics style changes apply to the existing weighted breast, upper-thigh, and buttock helper bones while preserving the separate 0%-200% strength sliders for each region.
- Added spring sub-stepping so low-FPS frames remain stable, especially in SPRINGY mode. Switching style clears old spring velocity so the new response starts cleanly.
- Skin Selector now has five BelleStarmon controls: SIZE, PHYSICS STYLE, BREAST PHYSICS, THIGH PHYSICS, and BUTTOCKS PHYSICS. Keyboard 1/2/3/4/5 selects each row directly.

## v3.0.1 - BelleStarmon weighted-bone bounce fix

- Fixed BelleStarmon body physics so the six real weighted helper bones (`LBreast`, `RBreast`, `LThighSoft`, `RThighSoft`, `LButt`, `RButt`) now receive the spring simulation directly instead of being forced to bind pose.
- Added spring-driven translation plus small local flex rotations to make breast, upper-thigh, and buttock motion visibly deform the actual skinned body.
- Kept a reduced anatomical per-vertex follow layer around each region for smoother surrounding-tissue motion without double-deforming the mesh.
- Increased locomotion/jump impulses for clearer bounce while preserving the existing 0%-200% per-region sliders.
- Fixed the non-voxel idle path so BelleStarmon's spring solver continues advancing while standing instead of being skipped by the idle early return.

## v3.0.0 - BelleStarmon real soft-body bounce refresh

- Replaced the previous helper-bone-only motion with an actual per-vertex spring deformation pass so the BREAST, THIGH, and BUTTOCKS sliders visibly deform BelleStarmon's body.
- Rebuilt BelleStarmon's runtime masks from the original Mixamo skin weights: 457 breast vertices, 276 upper-thigh vertices, and 237 buttock/rear-pelvis vertices now receive dedicated soft-body motion.
- Added under-damped spring/inertia response driven by walk/run cadence, acceleration, jumping, and landing; motion continues to settle after the driving impulse instead of following a canned pose exactly.
- The same spring solver runs in the Skin Selector preview, so 0%-200% slider changes can be seen live before selecting the character.
- Version intentionally remains 3.0.0 for this requested refresh.

## v3.0.0 - BelleStarmon physics controls refresh

- Added BelleStarmon-only BREAST PHYSICS, THIGH PHYSICS, and BUTTOCKS PHYSICS sliders to the self-contained Skin Selector.
- Physics strengths range from 0% to 200% and persist per save; 100% is the default and 0% disables that region.
- Rebuilt BelleStarmon with six dedicated secondary-motion bones (left/right chest, upper-thigh soft tissue, and rear pelvis) so all three sliders drive real weighted mesh motion.
- The physics changes are visible live in the 3D selector preview and also apply during idle, walking, running, and jumping in gameplay.
- Slider controls: Tab or L3 cycles the active slider; keyboard 1/2/3/4 selects SIZE/BREAST/THIGH/BUTTOCKS directly; X/Y or -/+ adjusts the active slider.
- Version intentionally remains 3.0.0 for this requested refresh.

## v3.0.0 control refresh

- Kept release version at 3.0.0.
- Changed Skin Selector SIZE controls from LB/RB to X/Y (Square/Triangle).
- Added keyboard -/+ and numpad -/+ controls; [/] remain aliases.

## v3.0.0

### Major release
- Forced the release version to **3.0.0** and alphabetized the complete Skin Selector roster and CHARACTER option list.
- Added per-character persistent visual scaling from **50% to 150%** with a live SIZE slider in the high-resolution 3D selector. Keyboard `[`/`]` and controller LB/RB adjust scale in 5% steps.
- The saved scale is applied to the same renderer in overworld and Dramatic Shape battles; movement/collision are unchanged.
- BelleStarmon Ctrl WALK mode now doubles on-foot step duration for keyboard/digital input, producing exactly half the resolved normal movement speed while retaining the Catwalk animation. Analog-stick pressure blending remains independent.
- Rebuilt Naruto's atlas with the previously flat dark shoulder-accessory patch replaced by textured navy cloth detail; the authored/original headband mapping from v2.8.74 is retained.

## v2.8.74

### BelleStarmon / Yami / Naruto / Zoro / roster cleanup
- Added Ctrl-toggle walking for BelleStarmon keyboard/digital movement while preserving analog idle/walk/run pressure blending.
- Fixed Yami's black eye sockets by restoring transparency to the source lens and eyeshadow overlay materials.
- Fixed Naruto's forehead protector by using the original headband sheet with authored UVs, removing the previous double-correction.
- Removed Carl Johnson (CJ) from the character roster, selector/options list, and packaged runtime/source assets.
- Rebuilt D.O.N. Zoro with lower-body opposite-leg weight cleanup plus side-specific centre-seam duplicates to stop vertices welding across the legs during run animation.

## v2.8.73

### Battle Stadium D.O.N. Zoro replacement
- Removed the old OBJ/procedural Zoro implementation from the active `ZORO` slot.
- Rebuilt Roronoa Zoro from the supplied Battle Stadium D.O.N. `Unarmed Idle.fbx`, `Fast Run.fbx`, and `Jump.fbx` files.
- Replaced the old source tree with the new FBX/PS2 texture package and added `tools/convert_zoro_don_fbx.py`.
- New model: 52 deform bones, 1,397 skinned positions, 3,536 skin influences, 2,618 triangles.
- Uses the authored idle/run/jump clips and the Z-up runtime conversion; removed the old 180-degree model-facing correction and legacy arm-rest gait.

## v2.8.72

### Self-contained modern Skin Selector
- Removed the Skin Selector's runtime dependency on `gen1_modern_ui`; the selector now always paints its own responsive high-resolution clean UI.
- Kept the native `ListMenu` underneath as the input/state owner while covering its classic presentation with a full-window modern overlay.
- Added responsive list rows, selected-row accenting, ACTIVE badges, high-resolution fonts, controller hints, and a dedicated live 3D portrait card.
- Increased the Skin Selector portrait renderer ceiling from 960x1080 to 1152x1280 for sharper desktop model previews.
- Removed `gen1_modern_ui` from `optional_dependencies`; Dramatic Shape remains the only optional renderer integration.

## v2.8.71

### BelleStarmon analog idle / walk / run blending
- BelleStarmon now keeps separate authored walk and run clips: `Catwalk Walk Forward HighKnees.fbx` for light analog movement and `Fast Run.fbx` for full-stick movement.
- Left-stick magnitude now drives a smooth walk-to-run crossfade: light tilt stays on walk, 0.55-0.92 stick magnitude blends toward run, and near-full/full tilt reaches the fast run.
- Keyboard and D-pad movement continue to target the fast run because they have no analog magnitude.
- Existing movement blending still fades smoothly between idle and locomotion, so transitions are idle -> walk -> run and back rather than hard animation switches.
- BelleStarmon's gait cadence now blends from a 72-pixel walk cycle to a 31-pixel run cycle without snapping the gait phase.

## v2.8.70

### Modern UI Skin Selector + high-resolution viewer
- Removed the selector-specific classic `ListMenu:draw()` override so Gen 1 Modern UI 0.8.4 can present the Skin Selector using its normal modern list pipeline.
- Moved the 3D model portrait into a post-Modern-UI `render.hud` companion card instead of rendering it inside the 160x144 Game Boy UI canvas.
- Increased the portrait scene to an adaptive 512-900 x 640-1000 render target and draws it directly in window pixels, eliminating the blocky 64x66 enlarged preview.
- The portrait card reads the active Modern UI theme colors when available, while keeping the proven true-color Voxel3D/PaletteFX bypass and the v2.8.66+ indexed-model optimization.
- Added `gen1_modern_ui` as an optional dependency; standalone behavior remains a normal native ListMenu.

## v2.8.69

### Shrek texture cleanup
- Restored the untouched original `ShrekBody_Col.png`; the previous shirt-hem padding experiment had accidentally baked large smeared light patches into the shirt/sleeve islands.
- Kept the corrected Shrek geometry-to-material classifier, so the lower shirt hem still uses the body texture instead of turning green.
- Rebuilt `shrek_model.lua` / `shrek_atlas.png` from the clean texture.

### BelleStarmon locomotion
- Replaced BelleStarmon's Fast Run locomotion with the supplied `Catwalk Walk Forward HighKnees.fbx` as her normal walking animation.
- Tuned her gait cadence to about 72 world pixels per animation cycle so the 1.233s authored walk does not play at run speed.
- Slowed/smoothed BelleStarmon's jump pose playback by sampling a narrower section of the supplied Jumping clip with quintic easing and longer landing blend.
- Extended BelleStarmon's cosmetic manual jump from 30 to 42 frames for a less abrupt rise/fall while leaving other characters unchanged.

## v2.8.68

### Live Skin Selector 3D viewer
- Added a live rotating 3D preview of the currently highlighted Skin Selector character.
- Ported the working Stadium UI Model Viewer technique: transparent off-screen Voxel3D render, PaletteFX shader bypass, premultiplied-alpha UI draw, true-color region marking, and complete LÖVE/Voxel3D state restoration.
- Kept the stock Gen1Recomp ListMenu update/input behavior while replacing only the Skin Selector draw layout with a split list + preview panel.
- Left/Right rotates the highlighted model; Up/Down changes the highlighted character; A selects; B backs out.
- Preview rendering reuses the existing losslessly compacted character mesh and throttles off-screen refreshes to 30 FPS.
- Preview mesh uploads explicitly invalidate the overworld skin/upload keys so closing the menu cannot leave the world model stuck in a preview pose.

## v2.8.67

### Added
- Added **BelleStarmon** as a new selectable character.
- Imported the supplied Neutral Idle, Fast Run, and Jumping clips on the supplied skinned FBX character.
- Added `source/bellestarmon/`, `tools/convert_bellestarmon_mixamo.py`, `data/bellestarmon_model.lua`, and `assets/bellestarmon_atlas.png`.
- Preserved the v2.8.66 indexed render-buffer optimization for the new character.

## v2.8.66 - 2026-08-09

### Performance optimization without mesh decimation
- Added lossless indexed render-vertex compaction. The renderer now updates one vertex per unique position+UV pair instead of rewriting every duplicate triangle corner. Across the roster this cuts the per-frame render-vertex update set from 270,432 to 85,326 (~68.4%) while preserving every triangle and UV.
- Yami's render update set drops from 147,408 vertices to 29,320; Shrek 25,506 to 5,437; Ash 21,864 to 4,858; Red 25,623 to 5,978.
- Optimized the skinning hot loop with localized arrays and direct one-/two-influence paths; most Yami vertices use these fast paths.
- Resampled overly dense embedded idle/jump keys while preserving clip duration and runtime interpolation. Combined model-Lua size drops by ~24.7% (44.39 MiB -> 33.41 MiB).
- Reduced only the two oversized runtime atlases: Yami 4096x2048 -> 2048x1024 and Ash 2048x2560 -> 1536x1920. No model triangles were removed.
- Added `tools/optimize_runtime_assets.py` so regenerated source assets can be returned to the optimized release profile.

## v2.8.65

### Added Yami
- Added **Yami** as a new selectable character while retaining the existing Yugi Muto slot.
- Imported the supplied 127-bone FBX rig with authored Standing Idle (361 frames / 6.0s), Running (43 frames / 0.7s), and Jump (156 frames / 2.583s) clips.
- Exported the normal body + facial meshes only, avoiding overlapping damage geometry.
- Built a material atlas from the supplied skin, cloth, weapon, hair, eye, lens, and eyeshadow diffuse textures.
- Added `tools/convert_yami_fbx.py` and reproducible source files under `source/yami/`.

## v2.8.64

### Fresh CJ replacement
- Removed the old active CJ model conversion and replaced it with the newly supplied GTA SA FBXs.
- Imported the supplied Neutral Idle, Running, and Jumping clips onto the original 58-bone GTA skeleton.
- Rebuilt CJ's runtime atlas from the supplied upper-body, head, shoes, and legs material textures.
- Added `tools/convert_cj_fbx.py`; the old `convert_cj_obj.py` workflow is no longer shipped.
- CJ now uses the `CJ_FBX` embedded-animation profile while retaining the `CJ` character ID for the existing gameplay/shooting hooks.

## v2.8.63

- Fixed Shrek's lower shirt hem/trim rendering green by correcting the geometry-to-texture slot mapping so the accessory body trim uses the body texture instead of the head texture.

## v2.8.61

### Fresh Aang replacement
- Removed the previous Aang model, atlas source, DAE/OBJ source files, and `convert_aang_dae.py` workflow.
- Rebuilt Aang from the supplied **Aang (Title Screen)** Mixamo package: four skinned meshes, 52 deform bones, 2,172 positions, 5,345 skin influences, and 4,114 triangles.
- Imported the supplied authored animations directly: Standing Idle (361 frames / 6.0s), Running (28 frames / 0.45s), and Jumping (71 frames / 1.1667s).
- Added smooth Aang-specific idle/run blending and a locomotion-aware jump blend so running continues underneath takeoff/landing.
- Battle intro uses Aang's authored standing pose instead of the legacy Aang/Red arm overrides.

## v2.8.60

### Root-cause custom-model fixes
- Reverted the broad v2.8.58/v2.8.59 UV/filter/leg-spacing experiments.
- Fixed the shared **yellow polygon / lighting artifact** at the renderer level: custom character draws now explicitly disable Dramatic Shape's tileset-only window-glass mask before rendering. The upstream shader can otherwise treat unrelated character UVs as lit-window mask coordinates and replace those fragments with warm lamp light.
- Fixed Naruto's **mirrored Konoha headband** by mirroring only the eight forehead-plate UV triangles inside their real metal-texture strip. The face texture itself is no longer globally flipped.
- Rebuilt Naruto's lower body with **100 side-specific seam positions**. Shared centre-seam positions are duplicated per leg and opposite-leg weights are stripped, so the legs/feet deform independently instead of stretching connected polygons between them during the run.
- Naruto remains on the existing imported idle/run/jump clips and faster locomotion cadence.

### Validation
- Naruto runtime mesh: 52 bones, 1,948 positions, 5,060 influences, 3,408 triangles.
- The previous severe lower-shin bridge stretch (about 4–5x bind length in the run) is eliminated from the lower-leg region after side-specific seam splitting.
- Release and repo-ready ZIP integrity checks pass.

## v2.8.57

### Naruto headband + artifact cleanup
- Switched Naruto back to the correctly oriented secondary face/headband texture so the Leaf Village logo is no longer reversed on the headband.
- Rebuilt Naruto's atlas from the corrected texture pairing, which removes the stray yellow artifact patches that were showing up on the body/clothing.
- Preserved the orange clothing texture correction, faster run direction/cadence fix, and Beelstarmon removal from the roster.

## v2.8.57

### Naruto clothing texture slot fix
- Replaced the incorrect Naruto clothing/body texture slot with the newly supplied 256x256 texture sheet from the user.
- Regenerated `assets/naruto_atlas.png` and `data/naruto_model.lua` so Naruto's jacket, torso yoke, pants, and pouch now sample the intended clothing texture instead of the previous mismatched one.
- Kept the headband mirror fix, faster run cadence, and Beelstarmon removal from the active roster.

## v2.8.57

### Naruto headband texture fix
- Fixed Naruto's mirrored forehead-protector texture by flipping the source metal-plate region used by the model's mirrored UVs before atlas baking.
- Regenerated `assets/naruto_atlas.png` and `data/naruto_model.lua` from the corrected source texture so the headband emblem no longer appears reversed in-game.
- Kept the v2.8.54 Naruto orange-outfit texture pass, faster run cadence, and the removal of Beelstarmon from the roster.

## v2.8.57

### Naruto texture pass + roster cleanup
- Removed **Beelstarmon** from the active Skin Selector roster, character-order table, pause-menu selector list, and packaged character assets.
- Deleted the packaged `data/beelstarmon_model.lua`, `assets/beelstarmon_atlas.png`, and `source/beelstarmon/` content from the release/repo-ready build.
- Rebuilt Naruto's atlas from a refined orange body texture so his outfit reads much closer to the intended orange-and-blue look from the supplied reference image.
- Increased Naruto's run animation cadence again by changing the movement cycle from **27 px to 22 px** so he no longer looks sluggish while moving.

## 2.8.53 - 2026-08-09

### Fixed Naruto
- Corrected the new Naruto remake's main clothing material to a predominantly **orange** outfit instead of mapping the blue `nrt_tex03` sheet across both body material slots.
- The converter now supports separate textures for body material 0 and body material 1.
- Kept the v2.8.52 180-degree Naruto model-facing correction.

### Improved
- Sped up Naruto's imported Run animation by reducing the distance-locked gait cycle from **38 to 27 world pixels per cycle**. World movement speed itself is unchanged.

### Source research
- The original Dragon Blade Chronicles Naruto asset pack lists separate `nrt_tex01.png`, `nrt_tex02.png`, and `nrt_tex03.png` textures. The current rebuild uses an orange material-0 reconstruction derived from the supplied texture detail until the exact first two sheets are locally available.

## 2.8.52 - 2026-08-09

### Fixed Naruto
- Corrected Naruto's facing direction with a Naruto-only 180-degree model yaw offset, so the imported Run clip faces Gen1Recomp travel direction instead of appearing to run backward.
- Rebuilt Naruto's texture conversion as a per-triangle baked atlas. Each triangle now gets an isolated padded texture cell sampled from the supplied `nrt_tex03.png` / `base00.png`, eliminating body-material sharing and UV/filter bleed.
- Preserved Naruto's supplied Standing Idle, Run, Jumping clips and locomotion-aware jump blending.

### Validation
- Rebuilt Naruto from source FBXs using the new baked-atlas converter.
- Release ZIP and repo-ready ZIP pass integrity checks.

## 2.8.51 - 2026-08-09

### Changed
- Increased fresh Beelstarmon's localized breast secondary motion from **x20 to x30**.
- Scaled the idle, run, and jump chest responses by **1.5x** while keeping idle more restrained than locomotion.
- Preserved the v2.8.50 Naruto character and Beelstarmon's run/jump locomotion blending unchanged.

### Validation
- Confirmed Beelstarmon still uses only the two appended `LBreast` / `RBreast` secondary-motion bones; buttock physics remains removed.
- Release ZIP and repo-ready ZIP passed integrity checks.

## 2.8.50 - 2026-08-09

### Added Naruto remake
- Added **Naruto** back as a new character using the newly supplied Mixamo model/skin from `Standing Idle.fbx`; this does not restore the removed legacy Naruto rig.
- Imported the supplied **Standing Idle**, **Run**, and **Jumping** animation clips directly onto the shared 52-bone deform skeleton.
- Added smooth idle/run interpolation and locomotion-aware jump blending so the running gait remains partially active through moving jumps and blends back into the run on landing.
- Added the new Naruto body/eye texture setup: `nrt_tex03.png` supplies both body material slots and `base00.png` supplies the default eye material. Additional supplied eye/expression frames are retained as source assets.

### Validation
- New Naruto conversion: 52 deform bones, 1,848 skinned positions, 4,808 skin influences, and 3,408 triangles.
- Imported clips: Standing Idle = 361 keys / 6.0 s; Run = 39 keys / 0.6333 s; Jumping = 114 keys / 1.8833 s.
- Naruto atlas material mapping preserves separate body and eye UV regions without UV collapse.

## 2.8.49 - 2026-08-09

### Removed
- Removed **Naruto** from the active 3D Character Selector roster.
- Removed Naruto from the Skin Selector character list and runtime character-order table.
- Removed `data/naruto_model.lua`, `assets/naruto_atlas.png`, the Naruto source folder, and the Naruto converter from the packaged project.
- Historical changelog/test notes are retained for project history, but Naruto is no longer selectable or shipped as a character asset.

### Validation
- Confirmed Naruto is absent from the active character config and selector choices.
- Release ZIP and repo-ready ZIP integrity checks pass.

## 2.8.48 - 2026-08-09

### Changed
- Removed Beelstarmon's buttock secondary-motion system completely, including the appended `LButt` / `RButt` deform bones and their custom skin weights.
- Increased Beelstarmon's breast secondary motion from **x10 to x20** for running and jumping, with a stronger but still restrained idle response.
- Preserved the v2.8.47 locomotion-aware **Fast Run + Jump** blending so run movement continues underneath the airborne jump pose.

### Validation
- Regenerated the fresh Mixamo Beelstarmon model with only the two appended breast bones.
- Release ZIP and repo-ready ZIP integrity checks passed.

## 2.8.47 - 2026-08-09

### Beelstarmon secondary motion + locomotion jump
- Increased Beelstarmon's localized chest secondary motion from **x5 to x10**.
- Added appended **LButt/RButt deform bones** with localized **x10 buttock secondary motion**. Existing imported Mixamo bone indices remain unchanged.
- Reweighted only the rear pelvis/glute region to the new butt bones; the long coat/cape is excluded from that region.
- Reworked the imported Jumping clip blend so moving jumps retain **Fast Run locomotion underneath the jump**: hips keep ~65% run motion, legs ~50%, and the upper body takes more of the authored jump pose.
- Extended landing blend-out for a smoother jump -> run transition.

### Validation
- Rebuilt Beelstarmon from the fresh supplied Mixamo Standing Idle / Fast Run / Jumping sources.
- Both release and repo-ready ZIPs passed integrity checks.

## 2.8.46 - 2026-08-09

### Rebuilt Beelstarmon from the new FBXs
- Replaced the previous Beelstarmon mesh/rig with the actual model and Mixamo skin contained in the newly supplied `Standing Idle.fbx`.
- Imported the supplied `Standing Idle.fbx`, `Fast Run.fbx`, and `Jumping.fbx` as Beelstarmon's real idle, run, and jump clips.
- Converted the new FBX Z-up coordinate system into Gen1Recomp's Y-up runtime orientation.
- Replaced the old Beelstarmon source set in the repo; the clean source folder now contains only the three new animation FBXs plus the supplied texture and the new Mixamo converter.
- Added two chest deform bones at the end of the imported skeleton and localized 950 mesh positions to the new chest weights for the requested **x5 breast secondary motion**.
- Added smoothstep idle/run blending and jump clip crossfades so the imported animations transition without hard pose snaps.

### Validation
- Fresh model: 54 runtime bones, 12,368 positions, 33,179 skin influences, 17,485 triangles.
- Imported clips: idle 361 frames / 6.0 s; run 32 frames / 0.5167 s; jump 114 frames / 1.8833 s.
- UVs remain within the supplied 0..1 texture atlas.

## 2.8.45 - 2026-08-09

### Changed
- Reset **Beelstarmon** to a fresh rebuild from the original `source/beelstarmon/digimon.fbx` mesh instead of continuing from the previously iterated output.
- Replaced the Beelstarmon atlas with the newly supplied rebuild texture.
- Added the newly supplied source animation files to `source/beelstarmon/` for the remake workflow: `Standing Idle (1).fbx`, `Fast Run.fbx`, and `Jumping (1).fbx`.
- Kept the existing runtime **x5 breast physics** secondary-motion behavior on Beelstarmon.

### Notes
- This is a clean Beelstarmon content reset intended as the new base for further remaking/tuning.

## 2.8.44 - 2026-08-09

### Fixed Ash textures
- Corrected Ash Ketchum's authored UV conventions instead of clamping them. The body FBX stores V one tile below the normal range (`-1..0`), so it now maps with the proper shifted/flipped V conversion instead of collapsing to one texture row.
- Preserved wrapped negative face U coordinates instead of clamping them to the atlas edge. This restores the face/eye material sampling.
- Kept ordinary FBX V flipping for the arms/hat/hair and face materials.

### Added Ash idle + jump
- Imported the supplied **Standing Idle.fbx** directly onto Ash's existing Mixamo skeleton: 344 keys over ~5.7167 seconds.
- Ash now uses the supplied Standing Idle while stopped and the supplied Slow Run while moving.
- Added smoothstep idle/run blending so starts and stops ease between the two imported clips.
- Added a custom Ash jump pose layered over the currently blended idle/run pose. The jump envelope returns to zero at takeoff/landing, so jumping blends back into the imported animations instead of popping to a separate pose.
- Jump keeps Gen1Recomp's world-space jump arc; the embedded pose only handles body articulation.

### Validation
- Reconverted Ash: 52 deform bones, 3,819 skinned positions, 9,124 skin influences, 7,288 triangles.
- Imported idle: 344 frames, ~5.7167 seconds. Imported Slow Run remains 44 frames, ~0.7167 seconds.
- Simulated the weighted Ash mesh through idle -> run blend -> jump -> run -> idle without invalid bounds or skin explosions.
- Release ZIP and repo-ready ZIP integrity checks pass.

## 2.8.43 - 2026-08-09

### Added
- Added **Ash Ketchum** to the Skin Selector from the supplied `Slow Run.fbx` package.
- Preserved the FBX's exact weighted Mixamo skin instead of procedurally re-rigging Ash.
- Added support for a character-specific **embedded animation clip** and wired Ash to the supplied looping Slow Run animation.
- The source run contains **44 synchronized keys at 60 Hz** over about **0.7167 seconds**; root X/Z locomotion is removed so Gen1Recomp remains responsible for world movement while the original body motion is retained.
- Built a three-texture Ash atlas from the supplied body, arms/hat/hair, and face textures.

### Validation
- Ash conversion produced 52 deform bones, 3,819 skinned positions, 9,124 influences, and 7,288 triangles.
- Both release and repo-ready ZIPs passed integrity checks.

## 2.8.42 - 2026-08-08

### Fixed
- Retuned **Beelstarmon's leg animation** so the knees now articulate much more clearly instead of reading as straight, rigid stilts.
- Shifted more motion into the **shin/knee segment** while reducing raw thigh swing, which gives the legs a more readable knee break and a more planted foot roll.
- Updated Beelstarmon's **jump leg pose** to preserve visible knee flex instead of snapping toward a straight lower leg.

### Validation
- Release ZIP and repo-ready ZIP both passed integrity checks.

## 2.8.41 - 2026-08-08

### Rebuilt Beelstarmon cloth
- Rebuilt Beelstarmon's cape/coat deformation instead of only increasing the old three-bone flap angles.
- Expanded the actual cloth skinning region down to the ground-length tails and farther out to both sides.
- Preserved the original 31 bone indices and **appended six new cloth bones** (`CapeLTop/Mid/Tip`, `CapeRTop/Mid/Tip`) so existing body skinning cannot shift.
- The cloth rig now has three independent deformation chains: center, left tail, and right tail.
- Replaced the gait-sine-only cape motion with a **stateful spring/damping simulation** driven by movement speed, acceleration, gait sway, and stopping inertia.
- Jumping layers an additional cloth impulse on top of the live spring state instead of replacing it with a rigid canned pose.

### Validation
- Beelstarmon rig: 31 -> 37 bones, with the six new bones appended after all previous indices.
- Cape-influenced positions: 4,556 -> 6,072.
- Cape skin influences: 6,426 -> 9,990.
- Python converter syntax, manifest JSON, and both ZIP integrity checks pass.

## 2.8.40 - 2026-08-08

### Improved
- Added a stronger three-stage **cape cloth simulation** for Beelstarmon, with distinct top/mid/bottom lag, rearward trail, and lateral sway while moving.
- Retuned Beelstarmon's **jump cape response** so the cape opens farther and follows through more clearly on takeoff and landing.
- Simulated the cape chain before packaging to tune the top/mid/bottom response progressively instead of using nearly-uniform flap values.

### Validation
- Release ZIP and repo-ready ZIP both passed integrity checks.

## 2.8.39 - 2026-08-08

### Fixed
- Fixed **Beelstarmon sinking into the ground while jumping**. Her jump pose no longer applies the stock downward Waist/Hips translations on top of the actual world-space jump. Jump compression now comes from the arms and legs instead of moving the entire body below the floor.
- Added dedicated Beelstarmon jump transforms for arms, forearms, hands, thighs, knees, feet, and toes using her world-aligned procedural rig axes.

### Improved
- Strengthened **Beelstarmon hair physics**. HairRoot now follows the head with a small delayed translation/rotation, while HairTip uses a larger delayed swing.
- Hair also receives a stronger takeoff/landing recoil during jumps so the long hair visibly trails the body.

### Validation
- Preserved the intact 31-bone v2.8.38 skinning layout.
- Release ZIP and repo-ready ZIP both passed integrity checks.

## 2.8.38 - 2026-08-08

### Fixed
- Reverted the unsafe v2.8.37 Beelstarmon skeleton insertion that shifted existing skin-weight bone indices and caused the mesh to collapse/explode.
- Restored the intact **31-bone v2.8.36 Beelstarmon armature and vertex weights**.
- Retuned Beelstarmon's legs using the existing thigh/knee/foot/toe bones only: smaller hip arcs, smoother knee bend, gentler ankle roll, and less toe exaggeration so the long coat stays stable.
- Preserved Beelstarmon's corrected facing, chest secondary motion, hair motion, and cape/cloth motion from v2.8.36.

### Validation
- Beelstarmon model reports 31 bones and all skin influence indices remain within 3..31.
- Release ZIP and repo-ready ZIP both passed integrity checks.

## 2.8.36 - 2026-08-08

### Fixed Beelstarmon
- Corrected Beelstarmon's facing by applying a 180-degree model yaw offset so her forward travel matches the direction the character model is looking.
- Moved the secondary chest weighting upward onto the actual bust instead of the upper abdomen. The new chest region averages around Y=1.67 and uses a tighter front-surface falloff.
- Reweighted the hand, elbow, knee, shin, foot and toe regions so the limb joints bend more cleanly and planted feet stay more stable during walking.
- Retuned Beelstarmon's walk with softer shoulders, more natural elbow flex, wrist follow-through and a cleaner knee/foot cycle.

### Added secondary motion
- Added a two-bone hair chain (`HairRoot` / `HairTip`) for delayed head/hair follow-through while moving and jumping.
- Added a three-bone cape/cloth chain (`CapeTop` / `CapeMid` / `CapeBottom`) with progressively stronger lag toward the bottom of the cloth.
- Preserved the requested exaggerated 5x chest secondary-motion effect, now localized to the correct chest vertices.

### Validation
- Beelstarmon procedural rig increased from 26 to 31 bones.
- Chest influences now target the upper/front chest; hair and cape regions have dedicated weighted bones.
- Release ZIP and repo-ready ZIP integrity checks passed.

## 2.8.35 - 2026-08-08

### Added Beelstarmon
- Added **Beelstarmon** as a ninth Skin Selector character from the supplied `digimon.fbx` and texture.
- The FBX is a static mesh (no embedded armature/deformers), so the converter now builds a **26-bone procedural humanoid rig** with hips, spine, head, arms, hands, legs, feet, toes, plus dedicated left/right chest secondary-motion bones.
- Added a dedicated `BEELSTARMON` movement profile for full-body walking/jogging animation.
- Added intentionally exaggerated **5x chest secondary motion** during movement and jumping, with separate weighted chest bones rather than deforming the entire torso.
- Added `tools/convert_beelstarmon_fbx.py` and preserved the original FBX/texture under `source/beelstarmon/`.

### Validation
- Converter Python syntax check passes.
- Generated model contains 17,130 positions and 23,715 triangles.
- Release ZIP and repo-ready ZIP integrity checks pass.

## 2.8.34 - 2026-08-08

### Fixed
- Re-solved **Naruto's ninja-run arm rig** after the rear-view test showed his fingers collapsing into the torso/pelvis.
- Naruto's hands now target positions outside the body, nearly shoulder-height, and well behind the hips instead of following the centerline down through his back.
- Reduced secondary sway to keep the straight-back arm silhouette stable while running.
- Preserved Red's current light-jog animation unchanged.

### Validation
- Solved against Naruto's runtime SMD bind matrices: simulated shoulders remain near X ±8 / Y 94.5 / Z -8 while hands land near X ±20 / Y 94.4 / Z -37.
- Release ZIP and repo-ready ZIP integrity checks pass.

## 2.8.33 - 2026-08-08

### Fixed
- Fixed **Naruto's disappearing ninja-run arms**. v2.8.32 used a large shoulder roll that folded the arm chains through/behind the torso.
- Re-solved Naruto's shoulder pose against the actual SMD bind hierarchy. The first arm bones now rotate primarily around their local X axes, placing both hands behind the hips with the arms visible and nearly horizontal.
- Kept the elbows almost straight with only tiny step-synchronous drift so the classic arms-back pose remains readable while moving.
- Preserved Red's v2.8.32 light-jog tuning unchanged.

### Validation
- Verified the bind-chain positions after the new shoulder transforms: both hands sit behind the torso at approximately the same height and remain separated from the body centerline.
- Release ZIP and repo-ready ZIP both pass integrity checks.

## 2.8.32 - 2026-08-08

### Improved
- Retuned **Red's light jog** after armature simulation. The jog keeps the v2.8.31 feel, but the arms now move a little less, keep a softer bend, and have a smaller wrist/forearm follow-through for a more natural human swing.
- Retuned **Naruto's ninja run** after armature simulation. Naruto now leans farther forward and holds both arms much straighter and more level behind himself in a classic ninja-run silhouette.

### Validation
- Simulated both Red and Naruto against their current runtime armatures before tuning the motion.
- Release ZIP and repo-ready ZIP both passed integrity checks.

## 2.8.31 - 2026-08-08

### Red light jog
- Rebuilt Red's moving animation as a **light jog** instead of the previous heavy walk/T-pose-prone hybrid.
- Expanded Red's runtime armature map to expose `Spine2`, `Spine3`, `Neck`, `Head`, both shoulders, both hands, and both toe bones so the full skeleton can participate in the animation.
- Tuned a restrained jog cadence, moderate stride, bent-elbow arm pump, subtle wrist follow-through, small torso lean, and controlled vertical bounce.
- Red's distance-locked animation cycle is now 34 world pixels per cycle, faster than the prior 42-pixel walking cadence while remaining lighter than a sprint.

### Naruto ninja run
- Rebuilt Naruto's moving upper-body pose against the **actual SMD armature** instead of stacking generic arm-axis rotations.
- Solved shoulder/upper-arm/forearm rotations so both hands sit **behind the hips** in the classic ninja-run silhouette.
- Added a stronger forward torso lean, flatter head motion, quick leg cycle, and only subtle arm sway so the arms remain swept backward while running.

### Simulation validation
- Simulated both armatures at four phases of a full movement cycle in front and side views before packaging.
- Red's simulated hands stay beside the torso with alternating fore/aft pump instead of returning to a T-pose.
- Naruto's simulated hands remain behind the body through the complete cycle while the legs alternate normally.
- Release ZIP and repo-ready ZIP integrity checks pass.

## 2.8.30 - 2026-08-08

### Fixed
- Corrected **Red's arm pose**. The previous v2.8.29 Red arm branch dropped the normal arm-down rest rotation, which let his bind-pose T-arms show through while moving. Red now keeps a proper arm-down rest orientation and layers the looser walk swing on top.

### Added
- Added a dedicated **Naruto ninja-run** moving profile. Naruto now leans forward more aggressively, keeps a flatter torso trajectory, and sweeps both arms backward in the classic ninja-run silhouette while moving.

### Validation
- Release ZIP and repo-ready ZIP both passed integrity checks after the Red arm fix and Naruto ninja-run update.

## 2.8.29 - 2026-08-08

### Improved Red arm motion
- Reworked Red's fast-walk arm animation to remove the stiff **C-3PO-like** look.
- Added a dedicated Red shoulder/upper-arm/forearm/hand path with softer shoulder motion, smaller upper-arm swing, a permanent natural elbow bend, and delayed forearm/wrist follow-through.
- Kept the v2.8.28 grounded GTA-IV-style walk cadence and leg motion intact.

### Validation
- Release ZIP and repo-ready ZIP passed integrity checks.

## 2.8.28 - 2026-08-08

### Improved Red movement
- Reworked Red's fast movement animation into a **grounded, weighty GTA-IV-style walk** instead of a jog. Gameplay/root movement speed is unchanged.
- Increased Red's gait cycle distance from 30 to **42 world pixels per cycle**, giving each foot more time on the ground and a slower, heavier step cadence while the character still travels quickly.
- Reduced knee lift, ankle/toe kick, arm pump, forward lean, and vertical bounce.
- Increased pelvis/shoulder counter-sway and kept a long forward leg reach so the walk feels loose and human rather than robotic or floaty.
- Changes are isolated to Red and preserve the existing size, true-directional facing, Shrek fixes, and CJ safety changes.

### Validation
- Release ZIP and repo-ready ZIP integrity checks pass.

## 2.8.27 - 2026-08-08

### Fixed
- Reduced **Red's vertical run bob** so the whole hip/leg chain no longer lifts visibly above the ground during each stride.
- Added Red-specific waist and hip bob damping while preserving the longer arm/leg stride introduced in v2.8.26.
- Reduced Red head bob slightly so the run feels planted rather than buoyant.

### Validation
- Release ZIP and repo-ready ZIP both passed integrity checks.

## 2.8.26 - 2026-08-08

### Improved
- Increased **Red's running stride** so both his legs and arms take longer, clearer reaches while moving.
- Boosted Red-specific thigh, knee, foot, toe, arm, elbow, and wrist swing amounts for a more athletic run silhouette.
- Added a bit more Red-only torso lean, bob, and counter-rotation to support the larger stride without changing gameplay speed.

### Validation
- Packaged release ZIP and repo-ready ZIP both passed integrity checks.

## 2.8.25 - 2026-08-08

### Red
- Scaled **Red back up by 25% from v2.8.24**, changing his render height from `15.1875` to `18.984375`.
- Added a dedicated **RED animation profile** so Red can be tuned without changing the other selectable characters.
- Improved Red's running gait with a longer stride, slightly stronger knee lift and toe-off, stronger opposite-arm pump, more readable torso counter-rotation, and a little more forward athletic lean.
- Dampened excess head movement so the faster gait reads cleaner instead of looking bouncy.
- Movement speed and collision behavior are unchanged; this update changes model scale and animation presentation only.

### Validation
- Release ZIP and repo-ready ZIP both passed integrity checks.

## 2.8.24 - 2026-08-08

### Changed
- Scaled **Red down another 25% from his v2.8.23 size**. His render height is now `15.1875` instead of `20.25` (56.25% of the original `27` height).
- No other character scales were changed.

## 2.8.23 - 2026-08-08

### Changed
- Scaled **Red** down by exactly **25%** in the 3D Character Selector. Red's runtime render height is now `20.25` instead of `27`.
- No other character scales or animation settings were changed.

### Validation
- Release ZIP and repo-ready ZIP both passed integrity checks.

## 2.8.22 - 2026-08-08

### Fixed CJ shooting crash
- Removed the **live Dramatic Shape terrain Mesh fracture path** from CJ's trigger flow completely. v2.8.21 still called `captureTerrainBlockDebris()` on world hits despite the intended safety change.
- Removed CJ's incremental terrain-fracture **prewarm** from `Player:update`, so simply aiming/firing no longer reads terrain vertex maps.
- Wrapped the complete `fireCJShot()` invocation in `pcall`; Lua-side shot errors are now logged and safely aborted instead of escaping through the gamepad callback.
- Replaced trigger-time MP3 decoding with a cached procedural pistol crack to avoid native audio-decoder failures that Lua `pcall` cannot reliably contain.
- World hits now use a stability-first impact-only path: recoil, raycast and HUD feedback remain, but gunshots do not mutate Dramatic Shape terrain meshes or map blocks. Actor hit behavior remains available.
- Preserved v2.8.20 true 360-degree movement and all current Shrek fixes.

### Validation
- Confirmed the CJ trigger handler no longer calls `captureTerrainBlockDebris()` or `red3dPrewarmFracture`.
- Release and repo-ready ZIP integrity checks pass.

## 2.8.21 - 2026-08-08

### Fixed
- Fixed a **CJ shooting crash** by disabling the experimental live terrain `Mesh:setVertexMap` fracture path by default. That mutation can hard-fail on some Gen1Recomp/Dramatic Shape/LÖVE combinations when a bullet hits world geometry.
- CJ now uses the safer fallback debris path for destructible world hits while keeping gun audio, recoil, actors, hit detection, and block destruction.
- Wrapped CJ shot execution, debris creation, and world-block destruction in protected calls so a failed effect is logged instead of crashing the game.
- Preserved the v2.8.20 true 360-degree directional-facing changes and all current Shrek fixes.

## 2.8.20 - 2026-08-08

### Fixed
- Rebuilt **True Directional Movement** around the player model's actual world-space displacement instead of Dramatic Shape's live `bodyYaw` / input-vector exposure.
- The 3D character can now face a **continuous 360-degree travel direction**: forward, backward, sideways, and every diagonal angle in between.
- When movement stops, the model **keeps its last exact yaw** while the camera orbits independently instead of snapping back to camera-forward.
- The displacement tracker ignores large warp/teleport jumps and preserves CJ's ADS body-facing override.
- Preserved the Shrek texture, body, walk, and arm fixes from v2.8.13-v2.8.18.

### Validation
- Direction calculations were simulated for cardinal and diagonal world-space trajectories.
- Release ZIP and repo-ready ZIP integrity checks passed.

## 2.8.19 - 2026-08-08

### Fixed
- Restored **True Directional Movement** for all 3D player skins. The previous implementation still trusted Dramatic Shape's live `bodyYaw`, which intentionally returns to camera-forward while standing.
- The Character Selector now derives the model's continuous **360-degree body yaw directly from the actual movement vector transformed into world space**.
- Releasing movement now preserves the last travel bearing while the camera orbits independently, so the character no longer snaps back to camera-forward.
- Added a compatibility fallback that reconstructs the world movement vector from `moveVector` + camera `yaw` when `moveWorld` is unavailable.
- CJ ADS still overrides the retained body bearing while aiming.
- Preserved the v2.8.18 Shrek arm fixes and all previous Shrek rig/texture corrections.

### Validation
- Simulated camera-relative forward, backward, left, right, and diagonal movement bearings plus stop-and-orbit retention.
- Release ZIP and repo-ready ZIP integrity checks passed.

## 2.8.18 - 2026-08-08

### Fixed
- Reworked **Shrek's arms** in the `SHREK_RED` profile. The previous pass copied Red's timing but still left the upper arms too spread and the forearms too stiff for Shrek's generated bind pose.
- Added a dedicated **inward upper-arm rest rotation** and a milder Red-style swing so Shrek's hands stay beside his torso instead of winging outward.
- Added matching **forearm and hand rest angles** plus dedicated `SHREK_RED` jump-arm branches so the same correction applies while jumping, not just walking.
- Preserved the v2.8.17 leg/body walk-axis fix and the v2.8.13 Shrek texture correction.

### Validation
- Release ZIP and repo-ready ZIP both passed integrity checks after the Shrek arm-profile update.

## 2.8.17 - 2026-08-08

### Fixed
- Rebuilt **Shrek's walk mapping after simulating his actual 24-bone bind skeleton**. The v2.8.16 Red-style path was using Red's local-Y leg axes on Shrek's world-aligned generated rig, twisting his thighs/knees sideways and producing the crippled walk.
- Shrek now keeps **Red's gait timing**, but maps thighs, knees, feet, arms, elbows, torso lean, hips and head onto the axes that match Shrek's generated skeleton.
- Reduced Shrek stride and knee amplitudes to fit his shorter, wider proportions while keeping an alternating Red-like walk.
- Removed an erroneous SHREK_RED block from the jump function that referenced walk-only variables; Shrek jump now uses the correct rig-axis path as well.

### Validation
- Simulated the full Shrek joint hierarchy across a complete 12-pose gait cycle before packaging.
- Release ZIP and repo-ready ZIP integrity checks passed.

## 2.8.16 - 2026-08-08

### Changed
- Extended Shrek's Red-style animation from just the arms to his **whole body**. Shrek now gets Red-like hips, waist bob, torso twist/lean, shoulders, head counter-motion, legs, and arm swing through a dedicated `SHREK_RED` profile.
- The torso/head motion is slightly damped compared with Red so Shrek keeps his heavier proportions instead of looking too springy.
- Preserved Shrek's corrected textures and existing rig.

### Validation
- Release and repo-ready ZIP integrity checks passed.

## 2.8.15 - 2026-08-08

### Fixed
- Switched **Shrek** from the shared `GENERIC` profile to the same **default/Red-style arm and walk animation path** used by the Pokémon trainer Red. This gives Shrek the same baseline upper-arm, forearm, and hand animation behavior as Red instead of the looser generic profile.
- Tuned Shrek to use **`armRestDeg=36`** so his already-relaxed source arms settle into a more Red-like hanging pose without being pushed behind the torso.
- Preserved the v2.8.13 Shrek texture fix and the existing Shrek rig/atlas assets.

### Validation
- Release ZIP and repo-ready ZIP both passed integrity checks after the Shrek animation-profile change.

## 2.8.14 - 2026-08-08

### Fixed
- Corrected **Shrek's arm rest pose**. The previous `armRestDeg=72` was over-rotating his already-down source arms behind his torso, which is why they looked pinned behind his back in-game.
- Shrek now uses **`armRestDeg=0`** so the shared animation system starts from his original relaxed source arm pose instead of applying an extra downward/backward drop.
- Preserved the v2.8.13 Shrek texture UV fix and atlas content unchanged.

### Validation
- Packaged release ZIP and repo-ready ZIP both passed integrity checks.

## 2.8.13 - 2026-08-08

### Fixed
- Corrected **Shrek's diffuse UV vertical mapping**. The extracted OBJ stores V in `-1..0`; the previous converter used `1 + v`, which vertically flipped every texture island. The correct conversion is `-v`.
- This fixes the visibly wrong shirt, vest, skin, pants, and face texture placement seen in-game.
- Kept the v2.8.12 Shrek arm-drop rig and alpha-bleed atlas padding.

### Validation
- Rendered the original Shrek OBJ with both UV formulas. The old `1 + v` mapping reproduces the broken texture placement; `-v` reconstructs the expected Shrek appearance.
- Regenerated `data/shrek_model.lua` and the runtime atlas, then passed ZIP integrity checks.

## 2.8.12 - 2026-08-08

### Fixed
- Reworked **Shrek** again. His source mesh is posed with the arms spread wide, so using the generic `armRestDeg=0` left him looking unrigged at runtime. Shrek now uses a **72-degree arm-drop rest pose** in the shared animation system so his arms hang down instead of staying stuck out sideways.
- Rebuilt **Shrek's atlas with alpha-bleed padding** around the diffuse islands. This prevents the transparent black background in the source body/head textures from bleeding into the sleeves and hands when the model is minified in-game.
- Regenerated `data/shrek_model.lua` and `assets/shrek_atlas.png` from the updated converter while keeping the same original Shrek source OBJ and textures.

### Validation
- Package integrity passed after regenerating the Shrek model and atlas.
- Shrek remains selectable in Skin Selector and keeps the same source asset set.

## 2.8.11 - 2026-08-08

### Fixed Shrek
- Corrected Shrek's texture UV conversion. The extracted OBJ stores V coordinates in the range `-1..0`; v2.8.10 clamped those values to zero, which collapsed almost the whole mesh onto a single horizontal row of the diffuse textures. The converter now maps the source negative-V convention correctly across the full atlas.
- Rebuilt Shrek's procedural skin weights so the complete sleeves/upper arms are attached to the armature. The old `abs(x) > 0.43` cutoff left inner upper-arm vertices stuck to the torso.
- Arm weights now follow a shoulder -> upper arm -> forearm -> hand polyline with smooth joint blending and rigid palm/finger weighting.
- Preserved the original supplied Shrek body/head diffuse textures and the existing Skin Selector/save/directional-facing behavior.

### Validation
- Runtime UVs now span approximately `0.002..0.997` horizontally and `0.004..0.998` vertically instead of collapsing to one texture row.
- 1,725 Shrek positions are arm-weighted; 1,586 of them move more than 0.02 model units in the simulated arm-swing pose.
- Simulated arm deformation reaches ~0.148 model units while non-arm torso vertices remain stationary in the focused arm test.
- Release ZIP integrity checks pass.

## 2.8.10 - 2026-08-08

### Added
- Added **Shrek** to Skin Selector.
- Imported the supplied *Shrek Forever After* PC OBJ and original diffuse textures.
- Built a new 24-bone procedural humanoid skin rig around Shrek's supplied rest pose, with weighted arms/legs, torso, neck, and head for the selector's walking/jump/battle animation system.
- Added `data/shrek_model.lua`, `assets/shrek_atlas.png`, the original source files under `source/shrek/`, and `tools/convert_shrek_obj.py`.

### Validation
- The generated Shrek mesh contains 4,933 weighted positions and 8,502 triangles.
- Bind-pose weighted reconstruction is exact within floating-point tolerance because every generated influence is stored in its bone-local bind coordinates.
- The release remains configured for `randyadr/Gen1Recomp-Character-Selector` GitHub auto-updates.

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
