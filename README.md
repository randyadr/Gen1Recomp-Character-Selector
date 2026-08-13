## v3.1.24 gigantic head setting

- Added a saved per-character **HEAD SIZE** control to the Skin Selector.
- Head size ranges from **100% to 400%** in 25% steps, so any rig with a standard `Head` bone can be made deliberately gigantic.
- The deformation scales the Head bone plus descendant face/hair geometry around the animated head joint and softly blends the neck seam; the torso/body keeps its existing size.
- The setting works in projected overworld rendering, Voxel3D, third person, battles, selector preview, and VR. First-person VR still uses the existing headless body map.
- Titan has no humanoid Head bone, so it intentionally does not show the HEAD SIZE control.
- v3.1.23 Gen 1 first/third-person FreeMove handoff, Android double-tap, pinch zoom, eight-way movement, and Gen 2 behavior are preserved.

## v3.1.23 Gen 1 first/third-person free-movement handoff

- Fixes Red/Blue/Yellow 1ST and 3RD person controls falling back to ordinary 2D-style tile movement.
- The Gen 1 eight-way tile helper now stands down completely while the voxel renderer's free-roam camera is driving.
- 1ST/3RD now pass movement to Dramatic/Dramaless Shape FreeMove for continuous camera-relative control and its normal walk/run animation clock.
- Regular 2D/voxel eight-way movement is unchanged. Gen 2 / Gold is unchanged.

## v3.1.22 Gen 1 overworld locomotion animation repair

Red, Blue, and Yellow now keep their 3D walk/run animation clock on the **visible voxel player render**, instead of depending on Dramatic/Dramaless Shape's optional/cached shadow pass. This removes the Gen-1-only freeze/stutter path while leaving Gold's separate Gen 2 bridge unchanged.

Gen 1 diagonal movement also no longer replaces the engine's `Player:update()`. The stock update advances `animClock`, landing poses, hop/spin timers, bump cadence, and any newer engine bookkeeping first; the mod only corrects the in-between X/Y interpolation to the diagonal target afterward. Eight-way movement, Android double-tap 3RD person, pinch zoom, VR support, and the number-3 camera cycle are retained.

## v3.1.21 Android voxel-world pinch zoom

On Android, use **two fingers on empty gameplay space and pinch/spread to zoom the voxel world**. Regular voxel/orbit views drive Gen1Recomp's survey zoom; **3RD PERSON** drives the voxel renderer's boom distance when that camera exposes its native zoom control. **1ST PERSON** intentionally ignores pinch because the camera is fixed at the player's eyes. Pinch motion is claimed before other touch wrappers can double-apply it, while press/release still reach the host so touch ids cannot get stuck. Touch-control regions are excluded, and pinch gestures cannot trigger the existing double-tap-to-3RD shortcut.

## v3.1.20 Android double-tap 3RD person shortcut

On Android, **double-tap empty gameplay screen space to jump straight to 3RD PERSON**. The gesture is captured at the physical LÖVE touch layer, before game states/mods can consume it, but the underlying touches are still forwarded normally. Touch-control regions are ignored, multi-touch/pinch gestures are ignored, and the shortcut only runs while the actual overworld is the top state. The keyboard **3** cycle remains **ZOOM -> 1ST PERSON -> 3RD PERSON -> ZOOM**.

## v3.1.19 hard 3-key camera fix

The **3 key** camera cycle is now captured before Gen1Recomp routes the press through state/menu handlers, and it no longer depends on the engine's `canToggle` gate. While the overworld is actually on screen, each physical press cycles **ZOOM -> 1ST PERSON -> 3RD PERSON -> ZOOM**. A second physical-key polling path catches `3`/keypad `3` even if another mod consumes the normal keypress event. The camera pipeline is discovered from its live 1ST/3RD labels, so compatible Dramatic/Dramaless forks do not have to use a specific pipeline id.

## v3.1.18 number 3 camera cycle

The **3 key** is now the direct camera/zoom button: **ZOOM -> 1ST PERSON -> 3RD PERSON -> ZOOM**. From another voxel camera rung, the first press enters the normal zoom/orbit view, then later presses move through first-person and third-person. Keypad `3` is supported too. The v3.1.17 F6 companion shortcut is no longer installed.

## v3.1.16 F6 camera-toggle regression fix

Restores the voxel mod's own first-person / third-person camera hotkey after the v3.1.15 VR integration. The character mod no longer eagerly loads a voxel fork's private `VR` module during bridge installation. Instead it borrows an already-loaded VR table directly from the voxel pipeline closures. This keeps camera/input ownership with Dramatic Shape / Dramaless Shape while preserving the v3.1.15 stereo/headless-body rendering when that renderer has actually initialized VR.

No movement, facing, character, animation, or selector behavior is changed from v3.1.15.

## v3.1.15 VR 3D model support

The selected custom character now participates in Dramatic Shape / Dramaless Shape VR instead of depending on the stock sprite-card behavior. Tabletop/diorama VR and VR battles use the normal complete textured model. In first-person VR, where the headset sits at the player's head and the voxel renderer intentionally hides the player's card, this mod draws a dedicated **headless animated body** so looking down shows the selected character without putting face or hair polygons around the camera.

The VR body follows headset yaw, remains grounded to the game player's feet, and uses the same idle/walk/run/jump/secondary-motion pose as the rest of the voxel renderer. The two stereo eyes share one prepared skeleton pose per rendered frame. Head-mounted accessories are omitted only from the first-person VR body to avoid HMD clipping; full accessories remain available in ordinary voxel, third-person, selector, tabletop VR, and battle VR views.
The static OceanGate Titan remains a full external model in tabletop/diorama and battle VR, but is intentionally hidden in first-person VR because its submarine hull has no humanoid head to cull and would enclose the camera.

VR support is automatically used when the installed Dramatic Shape or Dramaless Shape build exposes its VR/OpenXR module. No new VR setting is required in the character selector.

## v3.1.14 Third-person animation fix

Dramatic Shape third-person can skip the shadow-render pass that older builds used as the animation-frame boundary. v3.1.14 adds a visible-render fallback so third-person advances the same shared voxel locomotion controller as regular voxel mode. If shadows already prepared the frame, the visible mesh reuses that pose; if shadows are absent, the visible draw prepares it. This keeps idle/walk/run/jump animation alive in both camera modes without intentionally double-speeding the normal voxel path.

## v3.1.13 True directional movement

On-foot 3D characters can now walk in **eight real directions**, including all four diagonals. Keyboard/WASD and simultaneous d-pad directions work, and the controller left stick keeps both axes so diagonal stick input is no longer discarded by the stock four-way movement mapper.

Diagonal movement still lands on the normal Gen1Recomp cell grid, so warps, grass, encounters, scripts, NPC collision, save position, and step-complete logic continue to use the engine's normal world state. The mod validates both side cells and the diagonal destination before starting a diagonal step, preventing corner cutting. Diagonal duration is scaled by `sqrt(2)` after `movement.speed`, keeping travel speed consistent with cardinal walking.

The 3D projected renderer now rotates from the actual movement vector while a step is active. A diagonal step therefore animates the walk/run clip and visibly faces the diagonal heading rather than merely translating a four-way-facing model. The engine's cardinal `facing` value is retained separately for interactions and special tiles. Bikes, surfing, fishing, forced downhill/current movement, map-edge connections, and scripted movement remain vanilla.

## v3.1.11 Sabrina

- Adds **Sabrina** as a built-in selectable 3D character.
- Uses the supplied native 52-bone skinned FBX rig and `Sabrina.png` texture.
- Uses the supplied **Idle**, **Catwalk Walking**, **Goofy Running**, and **Jumping** clips.
- Catwalk/Goofy root travel is removed at runtime so Gen1Recomp remains authoritative over player movement.
- Sabrina uses the native FBX walk/run blend and jump path without inheriting Wow-only pose or physics controls.
- Verified default model forward direction in the selector is front-facing.

## v3.1.10 Ugandan Knuckles

Added **Ugandan Knuckles** as a built-in character using the supplied native skinned FBX model/animations. The runtime model uses the supplied Idle, Running, and Jump clips, with authored root travel removed so movement remains synchronized to the Gen1Recomp player entity.

## v3.1.8 Naruto/BelleStarmon source-basis fix

Naruto and BelleStarmon are now corrected by rotating their **skinned geometry basis** 180° around each model's own bounds centre. This is deliberately not another viewer/gameplay yaw flag. The same corrected vertices are consumed by the Gold selector, Gold overworld renderer, Dramatic Shape/Voxel3D, battles, and accessory renderer, so those paths cannot disagree about which way is forward.

The old per-renderer yaw offsets for these two characters are zeroed, and v3.1.8 clears legacy saved FACE FLIP overrides once so both characters start from the intended front-facing default.

## v3.1.7 Naruto/BelleStarmon forward-axis fix

Naruto and BelleStarmon are authored facing the opposite model-space Z direction from most built-in characters. v3.1.7 treats that as an intrinsic import-orientation issue instead of trying to solve it only in movement code.

Their Voxel3D/model path now uses a 180-degree `modelYawOffset`, so the default Skin Selector camera shows the front of each character. Gold's overworld uses the separate projected renderer, so both characters also have a 180-degree `projectYawOffset` there. This keeps their visible body direction aligned with travel in Pokémon Gold while preserving the existing FACE FLIP switch as a user override.

The v3.1.6 projected-preview centering repair is retained: models are fitted from their measured silhouette without the old second scale-dependent translation that could push some previews outside the panel.

## v3.0.62 Wow jump/run smoothing

Wow's Catwalk and Goofy Run now remove the source FBX's baked forward root travel while keeping the authored body motion, so locomotion loops stay anchored to the actual player and close cleanly. Her jump playback is slower/softer, Running Jump is used only while actually running, and its large baked forward root displacement is removed.

## v3.0.61 static OceanGate Titan test character

The supplied OceanGate Titan asset is now a normal character choice in the Skin Selector. It is deliberately unrigged/static: the submarine floats above the player position, translates with movement, and rotates with facing/travel direction, but its mesh never plays character animations.

The package uses both supplied OBJ pieces (main hull + glass). Titan_albedo is the hull texture, and the glass albedo/opacity maps are packed into the same runtime atlas. Normal/metallic/roughness maps are retained only in the original source package; the current Red 3D Player renderer uses one color/alpha atlas.

## v3.0.60 donor-rig clone test importer

This build adds the first **replace the mesh but keep the original rig** workflow for edited versions of BelleStarmon and Wow. It is meant for the exact test case where the character body/proportions are still basically the same but the mesh has been edited or extra geometry has been added.

### Quick test

1. Open the Skin Selector and choose **IMPORT CHARACTER**. The status line shows the native `red3d_characters/imports` folder.
2. Put a loose `.obj`, `.fbx`, or `.dae` in that folder. ZIP packages still work too. For OBJ, leave the `.mtl` and texture images beside the model.
3. Press **SCAN OBJ / FBX / ZIP FOLDER**.
4. Pick the source model and texture.
5. Set **DONOR RIG** to **BelleStarmon** or **Wow**.
6. The preview uses that donor's real skeleton and clips. If the export axis is wrong, use **SWAP MODEL Y / Z** or the X/Y/Z flip switches. Small **FIT SCALE / X / Y / Z** controls are included for alignment.
7. Press **CLONE RIG + IMPORT**. A new character entry is created; the original donor character is not overwritten.

The cloner reconstructs the donor's bind-pose surface, reuses the donor bone hierarchy/rest matrices/animation clips, and transfers up to four skin influences from nearby donor surface points. Positions that are unchanged from the original body use an exact coordinate match; newly added geometry falls back to nearby-surface weight blending. Bellestarmon/Wow selector poses remain available on the cloned entry.

This is intentionally an experimental same-character replacement path, not a universal auto-rigger. Large proportion changes or geometry far away from the body can still need the existing **MANUAL HUMANOID RIGGER**. The v3.0.59 removal of the unreliable **EDIT PHYSICS AREA** UI remains in effect.

## v3.0.59 Bellestarmon pose retarget test + physics-area UI removal

The **EDIT PHYSICS AREA** section has been removed from BelleStarmon and Wow Character Settings. The physics system still uses its built-in/default anatomical masks; only the unreliable interactive area editor is gone.

BelleStarmon now has the same three **SELECTOR POSE** choices as Wow. They are retargeted by matching bone names (46 shared bones) instead of copying raw bone indices. Bellestarmon-only pinky/secondary-motion helper bones are left neutral, while live breast helper motion can still run in the selector.

## v3.0.58 Wow pose + UV orientation fix

Wow's three authored Skin Selector poses now activate correctly. The replacement model's atlas is also corrected for the FBX-vs-LÖVE vertical UV convention on a per-material-tile basis, fixing the upside-down face and vertically inverted body textures without moving material slots.

## v3.0.57 Wow visibility/material fix

The replacement character is listed as **Wow**. This build corrects the generated model bounds format that prevented her renderer from being created, and recolors her high heels and matching panties to cherry red.

## v3.0.56 Wow replacement

Wow is rebuilt from the user-supplied replacement FBX package. Her selector preview has three authored standing poses; choose **SELECTOR POSE** under Character Settings to cycle them. Overworld animation uses the supplied Standing Idle, Catwalk Walking, Goofy Running, in-place Jumping, and Running Jump clips.

## v3.0.55 breast-size rollback

The experimental breast-size deformation has been removed. The dual breast-physics area circles and upper/lower limits remain available for controlling where breast physics applies.

## v3.0.52 dual-circle breast physics editor

The Breast Physics Area editor now uses one independently draggable circle per breast. Each circle has its own radius, and the editor includes adjustable upper/lower vertical limits with guide lines. These settings persist separately for Belle and Wow.

## v3.0.51 breast physics area editor

Belle and Wow now support a draggable breast-physics area circle in the 3D preview. Enable breast physics, choose **EDIT PHYSICS AREA**, drag the circle over the chest, and use the mouse wheel or **AREA RADIUS** slider to resize it. The area is saved separately for each character and can be reset to the original placement. Desktop Character Settings also use a persistent wheel-scroll offset so long settings lists can be browsed continuously.

## v3.0.50 75% torso texture refresh

This build explicitly uses the supplied `75%.png` torso/chest texture for Wow and points the character to a fresh atlas filename so older cached atlas data is less likely to be reused. It also keeps the flowing hair improvements and mouse-wheel browsing in Character Settings.

## v3.0.48 texture refresh

This build keeps the v3.0.47 slower walk/run timing and forces Wow to load the updated torso/chest texture from a fresh atlas filename, which helps when an older atlas appears to be cached.

## v3.0.47 slower, clip-matched Wow locomotion

Wow's walk/run animation timing is now slowed independently of the soft-body physics solver. The supplied Catwalk/Goofy clips are sampled at a gait distance chosen to stay close to their authored durations, while breast, buttocks, thigh, and hair physics retain the high-frequency smoothing used in prior builds.

## v3.0.46 chest texture and flowing hair update

This build updates Wow's main torso atlas area to use the supplied chest/body texture and improves hair physics so the back-bottom section of the hair has a more flowing look. The hair solver is softer, has more travel, and uses extra trailing emphasis on the lower rear hair section, especially for Wow.

## v3.0.45 stable secondary-motion masks

This build removes all live butt/thigh/hair location calculations from the renderer. Each supported region is precomputed into the model data, so turning a checkbox on cannot jump into a missing mask function. Wow's buttocks mask is also rebuilt around the actual rear glute coordinates rather than the incorrect v3.0.44 range.

## v3.0.44 additional soft-body options

Belle and Wow now expose four secondary-motion regions in the selector: breasts, buttocks, thighs, and hair. Buttocks physics has been re-centered and made more visible, while thighs and hair are added as new optional regions. Thighs get the same toggle/slider style plus an independent left/right option; hair gets a simple toggle and slider.

## v3.0.42 recovery build

Rebuilt from the last broadly working v3.0.40 base after v3.0.41 introduced a renderer-breaking undefined safety helper. This release restores normal model rendering, keeps buttocks physics post-skin only to prevent Belle from being double-deformed, and keeps Android/iOS touch mode separate from the PC mouse path.

## v3.0.40 independent-motion switches

Belle and Wow now have separate saved **INDEPENDENT BREASTS** and **INDEPENDENT BUTTOCKS** switches. When ON, the corresponding left/right pair keeps separate timing, impulses and settling. When OFF, that pair is synchronized: vertical/depth motion is shared and side-to-side motion mirrors cleanly across the body. The switches only appear while their corresponding Breast/Buttocks physics region is enabled, and the choice is saved separately per character.

## v3.0.39 buttocks physics / dual-region controls

Belle and Wow now have **properly located buttocks physics** in addition to the existing butter-smooth independent breast physics. The selector now exposes a second saved toggle/slider pair: **BUTTOCKS** and **BUTTOCKS PHYSICS**. Both regions are saved separately, and each slider only appears while its matching checkbox is enabled.

Belle uses the authored butt-physics region from the model data, while Wow uses a rear-hip/glute surface mask so the motion stays on the buttocks instead of leaking into the lower back or side torso. Both sides move independently and use the same smoothed solver approach as the breasts.

## v3.0.38 butter-smooth breast physics

Belle and Wow keep the independent left/right breast simulation from v3.0.37, but the motion is now filtered for much smoother presentation on both desktop and phones. The spring solver is internally oversampled, noisy acceleration input is filtered, each breast has its own smoothed target, and the final rendered position follows the hidden spring through a frame-rate-independent presentation filter.

The smoothing does **not** couple the two sides together: left and right still have separate gait timing, idle motion, step reactions, spring position/velocity, target filters, and rendered output. The existing **PHYSICS** checkbox and single **BREAST PHYSICS** strength slider are unchanged.

All v3.0.37 mobile controls and settings reachability remain.

## v3.0.37 independent breast physics

Belle and Wow now simulate the **left and right breasts independently**. Each side has its own spring position/velocity state, gait timing, idle sway, alternating step reaction, and slightly different response/damping. The existing **BREAST PHYSICS** slider still controls the overall amount for both sides, but it no longer makes the two sides move as a synchronized pair.

All v3.0.36 phone controls remain: PHYSICS is first on small mobile layouts, the strength slider appears only while Physics is enabled, and the settings ▲/▼ buttons keep every option reachable.

## v3.0.36 mobile settings reachability

On phones, Belle and Wow now place **PHYSICS** at the top of Character Settings. If the screen is short enough that only one settings row fits, use the **▲ / ▼** buttons in the Character Settings title bar to page through every option. Enabling Physics automatically advances to the conditional **BREAST PHYSICS** slider; disabling it returns to the Physics checkbox.

### v3.0.35 Mobile Touch build

This is the phone-focused branch of the Skin Selector. On Android/iOS it automatically uses a larger touch layout; any real `input.pointer` touch event also enables mobile mode on other touchscreen hosts. Desktop mouse/controller input remains available when the same ZIP is used on PC.

Phone Skin Selector controls:

- Tap a character row to preview it and tap **USE THIS SKIN** to apply it.
- Character/settings rows, toggles, +/- buttons, scroll arrows, Back/Import/Export/Apply all use enlarged touch targets.
- **One finger** on the 3D preview uses the selected **ORBIT** or **PAN** mode.
- **Two fingers** on the preview pan with the midpoint and **pinch to zoom**.
- A permanent touch camera strip provides **ORBIT / PAN / ZOOM - / ZOOM + / RESET**, so zoom and pan remain usable even on a host that only exposes a single touch pointer.
- The desktop software mouse cursor and controller-hint strip are hidden in phone mode to free screen space.
- Starting character rename on mobile requests the phone software keyboard when the host supports LÖVE text input.
- The layout respects the game's safe viewport and scales down for lower-resolution landscape displays.

All v3.0.34 Wow run-loop, texture, breast-physics, character importer/rigger, accessory, and save features are retained.

### v3.0.34 Wow run playback repair

Wow's supplied Goofy Running animation now uses quaternion/rigid-transform interpolation and a true last-frame-to-first-frame loop. This removes matrix-shear and loop-snap artifacts without replacing the user's chosen animation. A dedicated Wow jump FBX can be added once that file is supplied.

# Gen1Recomp 3D Character Selector

### v3.0.32 additions

- **Wow** is rebuilt from the native Mixamo rig/skin inside the supplied FBXs rather than the generic auto-rigger, fixing the distorted arm chain.
- Wow directly uses the supplied **Idle**, **Catwalk Walk Forward HighKnees**, and **Goofy Running** animations.
- Wow maps the supplied body/arm/leg/nail/face textures into its runtime atlas and uses neutral fallback colors only for external maps that were not included in `wow.zip`.
- Wow now has the same simple saved **PHYSICS** checkbox and conditional **BREAST PHYSICS** slider as Belle; fresh saves start with Wow physics off.
- Every character still supports per-save display-name renaming without changing the stable internal character ID.


Repository: `randyadr/Gen1Recomp-Character-Selector`

For releases, create a tag such as `v3.0.32`. The included GitHub Actions workflow builds an installable `red_3d_player-v3.0.32.zip` with `manifest.json` at the archive root, which is the layout expected by the Gen1Recomp mod manager/index.

# 3D Character Selector — Gen1Recomp / Dramatic Shape

### Character Import humanoid rigger (v3.0.32)

Humanoid rigging is now part of the **main Character Selector**, not the Accessories editor. Open a character's **Character Settings > Import Character**, put an OBJ/FBX/DAE ZIP in the displayed `red3d_characters/imports/` folder, scan it, choose the source model/texture, and select **RIG HUMANOID CHARACTER**. After setup, press **SAVE TO CHARACTER SELECTOR** and the result becomes a normal selectable character.

The rigger now uses 17 editable markers including a dedicated Spine marker. **RE-DETECT HUMANOID JOINTS** estimates the torso centre and limb positions from mesh slices and extremity clusters. You can select joints with the list or, in Front View, click and drag the visible joint dots to move X/Y directly; Z remains available as a slider. **MIRROR L / R** mirrors limb edits, while **Weight Style (Tight / Balanced / Soft)** and **Weight Blend** tune skinning. Press **UPDATE ANIMATED PREVIEW** after joint/weight changes.

This remains a local semi-automatic rigger rather than Mixamo's cloud solver. Upright T-pose/A-pose humanoids are the best input. The improved anatomical weighting keeps arm/leg influence more isolated from the torso and supports up to four normalized bone influences per vertex, but unusual clothing, crossed limbs, non-humanoids, or highly non-neutral poses can still need manual tuning. Keep the original character ZIP in the character import folder so saved rigs can be reconstructed on future loads.


## v3.0.28

- BelleStarmon's **BREAST PHYSICS** slider is now conditional: it is hidden while the **PHYSICS** checkbox is off and appears immediately underneath when physics is enabled.
- Hiding the slider does not reset its saved strength value.

## v3.0.20

- Doubled BelleStarmon breast-physics visible strength from 40% to 80%.
- Kept the same 44% movement, 113% jump/landing, 92% idle sway, 83% response, and 120 Hz spring timing so the motion is stronger without becoming artificially faster.
- PHYSICS remains a single saved ON/OFF checkbox; thigh and buttocks physics remain disabled.
- Retains v3.0.19 mouse-wheel preview zoom and imported accessory texture-repair controls.

## v3.0.19

- Hover the Skin Selector's 3D portrait and use the **mouse wheel** to zoom in/out. Drag remains rotation-only, and the preview no longer auto-rotates.
- The accessory editor now includes a **TEXTURE IMAGE** chooser plus repair checkboxes for **FLIP TEXTURE U**, **FLIP TEXTURE V**, **SWAP U/V**, **REPEAT TEXTURE**, and **PIXEL FILTER**.
- Texture repairs save per character/accessory and affect both selector preview and gameplay. **RESET TEXTURE FIXES** returns only the texture settings to their defaults.
- ZIP scanning keeps multiple plausible images and uses stronger diffuse/albedo/base-color selection heuristics, which helps FBX packages that contain normal/specular/roughness maps next to the real color texture.
- v3.0.18's Belle PHYSICS checkbox fix and accessory attachment/position controls are retained.

## v3.0.18

- Fixed BelleStarmon PHYSICS so checking the box produces clearly visible breast jiggle in both selector preview and gameplay.
- The fixed preset remains 40% Strength, 44% Movement, 113% Jump/Landing, 92% Idle, 83% Response at 120 Hz.
- The underlying spring is responsive again rather than doubly over-damped; travel remains tightly limited and mostly vertical/front-back.
- Enabling PHYSICS gives a small immediate preview impulse; disabling it resets the springs to neutral.


This mod evolved from Red 3D Player into a multi-character 3D player system.

## v3.0.16

- Fixed BelleStarmon's **PHYSICS** checkbox so it controls a dedicated live runtime boolean used by both preview and gameplay rendering.
- Physics starts OFF when v3.0.16 has no saved choice; after toggling it, the ON/OFF choice persists per save.
- ON reapplies the fixed breast-only preset immediately: 40% strength, 44% movement, 113% jump/landing, 92% idle sway, 83% response, 120 Hz.
- OFF immediately zeros breast spring position and velocity. Thigh/buttocks physics remain disabled.
- Every character keeps the unified right-side settings panel and preview rotation remains manual only.





## v3.0.14

- BelleStarmon now uses **breast physics only**; thigh and buttocks secondary motion are disabled while their compatibility helper bones remain neutral.
- Belle's main settings panel shows only **SIZE** and a subtle gear button. Click the gear, press **P**, or press controller **R3** to reveal/hide the breast physics options.
- Hidden physics options: **BREAST PHYSICS**, **BREAST STRENGTH**, **MOVEMENT BOUNCE**, **JUMP / LANDING**, **IDLE SWAY**, and **RESPONSE SPEED**. The DOA-inspired 120 Hz spring profile remains fixed underneath.
- Added controller button icons to the selector footer and real matching shortcuts: D-pad navigation/rotation, L3 setting cycle, X/Y adjustment, LB export, RB import, A use skin, B back, and Belle-only R3 physics panel.
- Mouse slider dragging, custom cursor, preview drag rotation, import/export, Alt-Tab recovery, and Belle's selector-only FBX animation are unchanged.

## v3.0.13

- Fixed BelleStarmon showing **3D PREVIEW UNAVAILABLE** after buttocks physics was removed. The selector-only FBX contains the original humanoid rig but Belle still has neutral `LButt/RButt` compatibility bones; those bones now remain at bind pose and short animation clips are bounds-checked instead of aborting the preview.
- Buttocks physics remains completely removed.
- Retuned breast physics to a **DOA-inspired arcade profile**: faster under-damped rebound, independent left/right phase, stronger step/jump/landing response, and real landing velocity impulses. Safety clamps prevent runaway motion after frame hitches.
- Kept the lower anatomical breast mask and upper-thigh-only mask from v3.0.12.
- The Skin Selector still exposes only Breast Physics and Thigh Physics checkboxes; the new arcade tuning is built in.

## v3.0.12

### Portable skin import/export + BelleStarmon physics placement cleanup
- Added **EXPORT** and **IMPORT** buttons directly to the Skin Selector. Export writes the highlighted character as one portable `.red3dskin` file containing its generated model data, texture atlas/atlases, and renderer metadata.
- Exported packages are written under LÖVE's writable save directory in `red3d_skins/exports/`.
- To import, copy `.red3dskin` packages into `red3d_skins/imports/` and press **IMPORT**. New valid packages are compiled, validated, and appended to the selector without replacing built-in characters that use the same ID.
- Imported skins can be selected, scaled, saved as the active character, and exported again.
- The manifest now declares Gen1Recomp's `filesystem` permission for these portable package folders, and imported model Lua is compiled in an empty sandbox environment before renderer validation. Packages are capped at 256 MB with 64 MB per model/atlas payload.
- Removed **BUTTOCKS PHYSICS** from BelleStarmon completely. Rear helper bones remain at neutral bind pose so removing secondary motion does not reshape the body.
- BelleStarmon's thigh secondary-motion region now begins substantially higher on the leg, fading in around model Y 0.815-0.875 instead of the old knee-side ~0.68-0.72 region.
- BelleStarmon's breast secondary-motion region now fades out across model Y 1.710-1.755 so the upper chest no longer participates; the under-bust/upper-abdomen exclusion remains in place.
- BelleStarmon now exposes only **SIZE**, **BREAST PHYSICS**, and **THIGH PHYSICS** in the selector. Breast/thigh strengths use the built-in recommended profile.

## v3.0.11

### Simplified BelleStarmon physics controls
- Removed the exposed physics style, axes, rate, movement, impact, idle, response, and per-region strength tuning from the live Skin Selector.
- BelleStarmon now has only three physics checkboxes: **BREAST PHYSICS**, **THIGH PHYSICS**, and **BUTTOCKS PHYSICS**. All three default ON and persist per save.
- Kept the separate **SIZE** control because it changes character scale rather than physics.
- Added one fixed recommended physics profile: 120 Hz classic direct-target stepping, full 3D motion, responsive medium-low damping, slightly stronger movement/landing drive, and restrained idle sway.
- Recommended region amplitudes are fixed internally at 108% breast, 90% thigh, and 108% buttocks. Turning a checkbox OFF makes that region exactly 0%; turning it back ON restores the recommended value.
- Legacy advanced physics save values are intentionally ignored so older tuning cannot make the current motion unexpectedly slow, floaty, or over-damped.

## v3.0.10

### Classic direct-target bounce restored
- Restored BelleStarmon’s pre-v3.0.9 **direct-target** secondary-motion response. New gait, acceleration, jump, and landing targets now hit the springs immediately instead of being averaged from the previous frame.
- Kept the **60 / 90 / 120 / 144 / 240 Hz** PHYSICS RATE control, but it now controls spring sub-step size only. It no longer interpolates/softens the body-motion target.
- At 60 FPS with the default **120 Hz** setting, the solver performs two direct spring steps per frame, matching the characteristic v3.0.8 integration pattern while retaining the newer anatomy, selector, cursor, and Alt-Tab fixes.
- Removed the v3.0.9 accumulator/previous-target dependency, eliminating skipped low-delta frames and the smoothed/slow-feeling impulse response.
- Skin Selector preview remains capped at 60 FPS so the restored bounce is easy to judge while tuning.

## v3.0.9

### High-rate BelleStarmon secondary physics
- Added a saved **PHYSICS RATE** selector with **60, 90, 120, 144, and 240 Hz** choices. **120 Hz** is the new default for saves that do not already have a rate.
- Replaced the old hidden spring sub-step heuristic with a true fixed-timestep accumulator. The selected rate now directly controls how often breast, upper-thigh, and buttock springs integrate.
- Every internal physics tick interpolates from the previous motion target to the newest animation/player target, so rates above 60 Hz smooth the driving signal instead of simply repeating one stale 60 Hz target.
- Solver backlog is capped after hitches/focus changes so a long frame cannot cause a burst of catch-up physics.
- The Skin Selector 3D preview refresh ceiling is raised from **30 FPS to 60 FPS**, making high-rate physics visibly smoother in the menu.
- **RESPONSE SPEED** remains independent: PHYSICS RATE controls simulation smoothness/latency, while RESPONSE SPEED controls spring reaction/rebound speed.
- BelleStarmon now has eleven selector controls: SIZE, PHYSICS STYLE, PHYSICS AXES, PHYSICS RATE, BREAST PHYSICS, THIGH PHYSICS, BUTTOCKS PHYSICS, MOVEMENT BOUNCE, JUMP / LANDING, IDLE SWAY, and RESPONSE SPEED.

## v3.0.8

### BelleStarmon anatomical physics cleanup
- Breast/thigh/buttock helper weights are now refined from the model’s bind-pose coordinates before animation begins, so secondary motion stays attached to the correct body regions.
- Breast physics has a smooth under-bust/front-torso falloff that removes the upper-abdominal spill while retaining the lower breast volume.
- Thigh and buttock masks get lighter edge cleanup around the knee/groin and pelvis/hamstring/lower-back seams.
- Helper-bone skin weights are renormalized after trimming, preserving the neutral body shape instead of creating dents or seams.

### Alt-Tab / multi-monitor mouse recovery
- The Skin Selector now treats window focus as part of its mouse lifecycle instead of assuming every pressed pointer will receive a normal release.
- On focus loss, active slider/model drags are cancelled, polled button state is cleared, native cursor visibility is restored, and mouse grab/relative mode are disabled so the pointer is free on another monitor.
- On focus return, cursor coordinates are re-seeded and the selector resumes its custom cursor without inheriting stale click/drag state.
- The selector remembers and restores the mouse visibility/grab/relative-mode values that existed before it opened.
- Mouse polling is suspended while unfocused, preventing clicks made in another app from leaking back into the selector.

## v3.0.7

### Mouse drag-to-rotate reliability fix
- Fixed the compatibility mouse polling path so it emits movement while the **3D preview** is being dragged, not only while a settings slider is being dragged.
- Preview rotation now derives horizontal motion from the pointer's previous absolute X coordinate and falls back to `event.dx`, so hosts that omit or zero movement deltas still rotate correctly.
- Accepts `moved`, `move`, and `dragged` pointer phases for broader host compatibility.
- Automatic showroom spin pauses during an active mouse drag so the character follows the cursor directly, then resumes after release.
- Existing left-click suppression, custom cursor, settings controls, and BelleStarmon selector-only animation remain unchanged.

## v3.0.6

### Mouse click no longer closes the selector
- Fixed the hidden native `ListMenu` receiving a duplicate A/B-style input from desktop left-clicks after the custom HD selector had already handled the pointer event.
- Left-click now stays entirely inside the custom selector for character preview, sliders, arrows, physics settings, scrolling, and 3D preview dragging.
- **USE THIS SKIN** and **BACK** still close intentionally; right-click remains a Back shortcut and keyboard/controller controls are preserved.

## v3.0.5

### Always-visible mouse cursor + BelleStarmon selector-only FBX idle
- Replaced reliance on the captured OS pointer with a **mod-drawn high-contrast cursor** rendered above the Skin Selector. Mouse coordinates/clicks continue using Gen1Recomp pointer input, but visibility no longer depends on the host showing the native cursor.
- The native OS cursor is hidden only while the Skin Selector is open to prevent a double pointer on hosts that do display it, then its previous visibility state is restored on close.
- Added the user-supplied **Goofy Running.fbx** as BelleStarmon's **Skin Selector-only idle/preview animation**. The 39-key / 60 Hz source clip is converted into an in-place loop and embedded as runtime Lua animation data.
- Retargeted all 52 imported BelleStarmon skeleton bones while leaving the six breast/thigh/buttock helper bones under the live physics solver.
- The selector-only animation flag exists only around the preview skeleton update and is cleared immediately afterward, so overworld/battle idle, walking, running, jumping, and movement behavior are unchanged.

## v3.0.4

### Mouse-first Skin Selector controls
- Reworked the high-resolution Skin Selector into a clearer **character browser + dedicated settings panel** layout. BelleStarmon uses a side-by-side 3D preview and physics/body panel on normal desktop resolutions so the controls are much easier to read.
- Added full desktop mouse cursor support through Gen1Recomp's `input.pointer` hook, with a polling fallback for older engine builds.
- Click any character row to preview it without immediately closing the selector. Click **USE THIS SKIN** to apply the highlighted model; **BACK** and right-click close the selector.
- Numeric settings have clickable **− / +** buttons and a draggable slider. Dragging uses 1% resolution while keyboard/controller buttons keep their faster stepped adjustment.
- PHYSICS STYLE and PHYSICS AXES use dedicated clickable previous/next arrow buttons instead of inline text arrows.
- Drag directly on the 3D preview to rotate the highlighted model. The cursor changes to a hand over controls and a horizontal-drag cursor while rotating.
- Added clickable up/down scroll controls to both the character list and settings panel, so every skin and every BelleStarmon option remains reachable using only a mouse even on smaller windows.
- Existing keyboard/controller controls remain available and unchanged.

## v3.0.3

### BelleStarmon advanced physics options
- Physics styles now include **SOFT, NATURAL, SPRINGY, TIGHT, HEAVY, FLOATY, and JELLY**.
- **PHYSICS AXES** can be **FULL 3D**, **VERTICAL**, **FRONT / BACK**, or **SIDE / SIDE**.
- Independent 0%-200% **BREAST**, **THIGH**, and **BUTTOCKS** strength sliders are retained.
- **MOVEMENT BOUNCE** separately controls walk/run/acceleration drive from 0%-200%.
- **JUMP / LANDING** separately controls takeoff/landing impulse from 0%-200%.
- **IDLE SWAY** separately controls standing secondary motion from 0%-200%.
- **RESPONSE SPEED** changes how quickly the selected spring style reacts from 50%-200% without simply changing amplitude.
- BelleStarmon's ten selector rows are: SIZE, PHYSICS STYLE, PHYSICS AXES, BREAST PHYSICS, THIGH PHYSICS, BUTTOCKS PHYSICS, MOVEMENT BOUNCE, JUMP / LANDING, IDLE SWAY, RESPONSE SPEED.
- Tab/L3 cycles rows, keyboard **1-9** and **0** select rows directly, and X/Y or -/+ adjusts the selected value. All physics options persist per save.

## v3.0.2

### BelleStarmon selectable physics styles
- Added a saved **PHYSICS STYLE** row with **SOFT**, **NATURAL**, and **SPRINGY** modes.
- **SOFT** gives slower, cushioned motion with heavy damping and very little rebound.
- **NATURAL** is the default and preserves the v3.0.1 body-bounce character.
- **SPRINGY** rebounds faster, overshoots farther, and continues oscillating longer after steps and jumps.
- Style affects breast, upper-thigh, and buttock spring response globally; the existing 0%-200% sliders still set each region's amplitude independently.
- BelleStarmon's selector rows are now SIZE, PHYSICS STYLE, BREAST PHYSICS, THIGH PHYSICS, and BUTTOCKS PHYSICS. Tab/L3 cycles rows, keyboard 1-5 jumps directly, and X/Y or -/+ changes the selected row.

## v3.0.1

### BelleStarmon weighted-bone bounce fix
- Breast, upper-thigh, and buttock spring motion now drives the six dedicated weighted helper bones directly, so the actual skinned body deforms with the physics.
- A reduced anatomical vertex-follow pass remains around each region to keep the deformation soft instead of rigid.
- Locomotion and jump impulses are stronger and the ordinary non-voxel idle path now keeps the spring solver advancing while standing.
- Existing 0%-200% BREAST / THIGH / BUTTOCKS PHYSICS sliders are unchanged and continue to control the final amplitude.


## v3.0.0

### Major Skin Selector update
- Promoted the mod to **v3.0.0**.
- Skin Selector and mod-option character choices are now alphabetized while preserving the existing stable character IDs used by saves.
- Added a persistent **per-character SIZE slider** from 50% to 150% in 5% steps. The highlighted 3D preview updates live, and the same saved scale is used in overworld and Dramatic Shape battle rendering without changing collision or movement.
- Keyboard controls for size are `[` / `]`; controller controls are LB / RB. L/R remains model rotation.
- BelleStarmon's Ctrl WALK toggle now also changes actual keyboard/digital movement to **half the resolved normal on-foot speed**. Analog-stick locomotion remains pressure-sensitive and unchanged.
- Rebuilt Naruto's material atlas after replacing the flat dark shoulder accessory patch with nearby authored navy cloth detail, while keeping the v2.8.74 forehead-protector UV fix intact.

### Persistent 360° body facing

In Dramatic Shape 1ST/3RD free-roam, the 3D player model keeps the last direction it was actually travelling when movement stops. You can orbit the camera around the standing character without the model automatically snapping back to camera-forward. Moving again at any angle immediately updates the body direction.

## Characters

- **Aang**
- **Ash Ketchum**
- **BelleStarmon**
- **Cloud**
- **Naruto**
- **Red**
- **Roronoa Zoro**
- **Shrek**
- **OceanGate Titan**
- **Ugandan Knuckles**
- **Yami**
- **Yugi Muto**

## Skin Selector

Open the normal in-game pause/start menu and choose **Skin Selector**. The selector includes its own clean high-resolution UI and rotating 3D preview; no separate UI mod is required. Choose any listed character and the 3D overworld and Dramatic Shape battle representation switches immediately. The selected character is persisted.

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



## v2.8.74 cleanup / character fixes
- BelleStarmon: pressing either **Ctrl** key toggles keyboard/digital movement between Catwalk Walk and Fast Run; analog-stick pressure still blends continuously from idle to walk to run.
- Yami: rebuilt lens/eyeshadow overlays with proper transparency so the eye texture remains visible instead of rendering black eye sockets.
- Naruto: restored the original `nrt_tex03.png` headband mapping and removed the old double UV flip that pulled skin pixels into the forehead plate.
- Roronoa Zoro: cleaned opposite-leg skin weights below the pelvis and duplicated the remaining centre-seam controls per leg, removing the cross-leg welded vertex during running.
- Carl Johnson (CJ) has been removed from the active roster and release assets.

## Battle Stadium D.O.N. Zoro replacement (v2.8.73)
- Removed the previous OBJ/auto-rig Zoro implementation from the active ZORO slot.
- Replaced it with the supplied **Battle Stadium D.O.N.** rigged Zoro FBXs and original PS2 texture set.
- Uses `Unarmed Idle.fbx`, `Fast Run.fbx`, and `Jump.fbx` as authored embedded animations.
- New runtime model contains **52 deform bones, 1,397 skinned positions, 3,536 skin influences, and 2,618 triangles**.
- Preserves all five supplied material groups (`face1`, `tex1`, `tex2`, `tex3`, `tex4`) through a padded generated atlas.
- The new source is Z-up, so the ZORO slot now uses the post-skin Z-up conversion and no longer needs the old 180-degree facing correction.

## v3.0.0 scale-control refresh
- SIZE slider: controller X/Y (Square/Triangle), keyboard -/+; LB/RB are not used.
## BelleStarmon physics controls
When BelleStarmon is highlighted, the normal settings view stays minimal: **SIZE** plus a small gear button. Click the gear, press keyboard **P**, or press controller **R3** to open the hidden **BREAST PHYSICS** panel. Belle now has no active thigh or buttocks secondary motion.

The hidden panel contains **BREAST PHYSICS** ON/OFF plus sliders for **BREAST STRENGTH** (0%-200%), **MOVEMENT BOUNCE** (0%-200%), **JUMP / LANDING** (0%-200%), **IDLE SWAY** (0%-200%), and **RESPONSE SPEED** (50%-200%). The DOA-inspired spring response and 120 Hz direct-target stepping remain fixed. Slider values persist with the game.

Controller icons are drawn in the selector footer: **D-pad** navigation/rotation, **L3** cycle setting, **X/Y** decrease/increase, **LB** export, **RB** import, **A** use skin, **B** back, and Belle-only **R3** physics options. Mouse users can click/drag the same controls directly.

The selector also has **EXPORT** and **IMPORT** buttons. **EXPORT** creates one `.red3dskin` package in `red3d_skins/exports/` under the LÖVE save directory. Put shareable `.red3dskin` files in `red3d_skins/imports/`, then press **IMPORT** (or controller **RB**) to add them to the selector.

## BelleStarmon real body bounce (v3.0.1)
- BREAST PHYSICS, THIGH PHYSICS, and BUTTOCKS PHYSICS drive six dedicated weighted soft-tissue bones through an under-damped spring solver, with a smaller per-vertex follow layer for the surrounding anatomy.
- 100% is the default visible bounce, 0% disables a region, and 200% doubles the deformation amplitude.
- The body reacts to locomotion cadence, acceleration, jumping, and landing, and the same motion is previewed live in the Skin Selector.



### v3.0.25 Belle physics control
BelleStarmon has a PHYSICS master checkbox and one BREAST PHYSICS strength slider. 100% is the tuned v3.0.24 behavior; the slider is limited to 0%-150% and saves per game.


### v3.0.27 Collada accessories
Accessory ZIP scanning also accepts `.dae` Collada models. DAE accessories use the same texture selection/fix controls and are always rigidly parented to the selected animated attachment bone, so saved placement follows character animation.


### v3.0.27 animation timing stability
Locomotion speed sampling is median-filtered and startup-gated so render scheduling cannot make characters animate abnormally fast after boot. Selector preview animation uses a bounded local clock for the same reason.
