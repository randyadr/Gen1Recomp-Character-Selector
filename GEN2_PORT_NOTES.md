# Gen 2 (Gold) port — v3.1.0

## The short version

`bryanthaboi/gen1recomp` **already contains Gen 2**. It is not a separate repo.
Upstream added `src/core/Game2.lua`, `src/world/gen2/`, `src/ui/gen2/` and
`src/battle/gen2/`, and `GameVersion` now lists `gold` with `generation = 2`.
`main.lua:248` builds `Game2.new()` when the imported ROM is Gold.

So this is not a fork-and-rewrite. It is one new file plus two small edits.

There is also a third-party fork, `UNDERdecoded/Gen2Recomped`. It is an **older
snapshot** — its `Game.lua` is 894 lines and raises no `input.pointer` hook at
all, so the mobile touch layer would be dead there. Target upstream Gold.

## What carries over untouched

The mod platform is shared between the two boots. Gold raises `input.pointer`,
`render.hud`, `movement.speed` and `ui.start_menu.items` under the same names,
with the same payloads, at the same point in the frame. `Screens.push` uses
`game.stack`, which `Game2` has.

That means the Skin Selector screen, touch controls, `mod.save`, mod options,
all 13 character models, physics, accessories and imports need **no port**.

`Renderer:motionSample` reads `player.moving` and px/py deltas — both of which
Gen 2's player has — so walk/run animation timing works as-is.

## What actually differed, and what was done about it

| # | Gen 1 | Gen 2 | Fix |
|---|-------|-------|-----|
| 1 | `Player:draw(camX, camY)`, world pixels, inside an already-scaled transform | `Player:draw(ox, oy, scale)`, **screen** pixels, callee sets up its own transform (`World.lua:drawPeople`) | Bridge pushes `translate(ox,oy)` + `scale(s,s)` and hands the renderer a **zero camera** — inside that transform the mesh's own world-pixel projection lands correctly with no second scale factor threaded through `Renderer:project` |
| 2 | `Player:pose()` returns six values | no such method; values live in `moving` / `stepFlip` / `jumping` / `spriteYOffset` / `walkPhase()` | `gen2Pose()` rebuilds the tuple |
| 3 | `Game.overworld`, `Game.wheelmoved` | world lives on the **Game2 instance** as `world`; wheel is `Game2:wheelmoved` | `Gen2Bridge.world()` walks the state stack; wheel handler hoisted and shared |
| 4 | `PaletteFX.markTrueColor` | PaletteFX is not in Gold's render path — `markTrueColor` silently no-ops | `render.zones` entry with `colors = false` (`Game2:blitZones`). Only matters in CLASSIC colour mode; in normal Gold colour the palettes are per-sprite and nothing would have re-shaded the mesh |
| 5 | surf/bike read off the player object | Gold keeps mount state on `World.playerState`, read via `FieldMoves` | `specialCard()` checks the world, not the player — your `playerUsesSpecialCard` field test would never have fired |

## Files changed

- **`lib/Gen2Bridge.lua`** — new. The entire Gen 2 layer, ~290 lines.
- **`main.lua`** — two surgical edits:
  - the mouse-wheel handler is hoisted out of the Gen 1 `do` block into
    `renderer.red3dSelectorWheel` so `Game2` can reuse the identical logic.
    Behaviour is unchanged; it returns `true` when it consumed the event.
  - a `do ... end` block after the Gen 1 `Player:draw` install that loads and
    installs the bridge. No-ops on Red/Blue/Yellow, costing a Gen 1 boot one
    `GameVersion` check.
- **`manifest.json`** — name, version `3.1.0`, description.

### Watch out: the 200-local ceiling

The mod entry function (`return function(mod)`, line 4988) sits **exactly at
LuaJIT's 200-local limit**. Adding two `local`s to it fails to compile with
`function at line 4988 has more than 200 local variables`.

That is why the wheel handler is a **field on the already-in-scope `renderer`
object** rather than a new local. If you extend this function later, attach to
an existing table or wrap in `do ... end`; do not add top-level locals.

Verify with: `luajit -bl main.lua /dev/null`

## Known gaps

- **No 3D Ethan/Chris model.** The port makes your existing characters render
  over Gold's player. A Gold-specific default would need its own asset.
- **Manual jump is cosmetic only under Gold.** Gen 1 first asks the overworld
  for a real ledge crossing (`checkLedgeHop`); Gold's equivalent is
  `World:tryLedgeJump`, a different signature with its own two-cell `STEP_LEDGE`
  — and it is already reachable by simply walking into a ledge. The Gen 2 path
  deliberately offers only the visual hop. Nothing can move the player through
  geometry.
- **CJ aim/shoot and the Dramatic Shape voxel bridge stay Gen 1 only.** Both are
  patched onto `Game`/`Pipelines` and are never reached on a Gold boot. They
  degrade silently rather than erroring.
- **`tryOneCellBorderJump` is Gen 1 only** — it uses `src.world.Collision`,
  which Gold does not use (it has `gen2/Permissions.lua`).

## Testing

`luajit -bl` clean on every `.lua` in the package. A 20-assertion harness stubs
LOVE and the engine modules and exercises the bridge end to end: transform math
(world px 64 at cam 32, scale 3 → screen px 96), zero-camera handoff,
`spriteYOffset` folding, surf fallback, zone opt-out, jump gating, renderer-failure
fallback, and stack resolution.

Not yet run against a real Gold boot — the ROM-derived cache is yours to supply.

## v3.1.1 — the manifest gate (why the badge said GEN 1)

The manager badge is not cosmetic. `ModTargets.label(manifest)` draws it, and
the **same call gates loading**: `Loader:_gateGeneration` skips any mod that
does not claim a Gen 2 game, with the reason `not marked gen2compat; this is a
Gen 2 game`. A GEN 1 badge means the bridge would never have run on Gold at all.

Fixed by declaring it, per `docs/preparing-your-mod-for-gen2.md` step 2:

```json
"games": ["gen1", "gen2"],
"gen2compat": true
```

`games` is the current key; `gen2compat` is the legacy flag and is purely
additive, so both together is safe and maximally compatible with older engine
builds. The badge should now read **Gen 1+2**.

## The official compat layer

Upstream ships `src/mods/Gen2Compat.lua` (2140 lines) and a documented contract
in `docs/mod-api-gen2-compat.md`. While mods load, the loader replaces
`_G.require`: for mod-owned code on a Gen 2 boot, a served Gen 1 module name is
answered by a Gen 2-backed facade.

Two consequences that shaped this port:

- **`src.world.Player` is NOT served.** There is no player facade, so reaching
  `src.world.gen2.Player` directly — as the bridge does — is the correct and
  only route.
- **`src.core.Game` IS served, by a translating facade** (`buildGame`), and the
  file's own rule is that a facade is a *copy*: monkey-patching it does not land
  on the table Gold runs. That is why the wheel patch targets `src.core.Game2`
  directly rather than the facade.

The facade does give one thing cleanly: `.overworld` is documented as the Gen 1
spelling of `Game2.world`, resolved at call time off the live game. `Gen2Bridge.world()`
now asks that first and keeps the state-stack walk as a fallback for when the
shim does not recognise the caller.

## Official checker results

Upstream ships `tools/modkit.py`:

```
$ python3 tools/modkit.py gen2check <mod>
-- red_3d_player: api 2, profile content, games gen1+gen2, ...
MK403 WARN main.lua:5646: requires src.world.Player, but a Gen 2 game runs
      src.world.gen2.Player; the require succeeds and hands back a module
      nothing instantiates
ok red_3d_player on gen 2: will load but degrade (1 warning)

$ python3 tools/modkit.py validate <mod>   -> ok red_3d_player valid
$ python3 tools/modkit.py lint <mod>       -> ok mod: no ROM-derived content
```

The single MK403 is **expected and intentional**: the Gen 1 `Player:draw` patch
must stay for Red/Blue/Yellow boots. On Gold that module loads and is never
instantiated, which is exactly what the warning describes — dead, not broken.
Run `gen2check` yourself after any further edit; it is the authoritative answer.

## v3.1.2 — reversed run direction (root cause)

**Symptom:** some characters ran the right way, some ran backwards.

**Cause:** a pre-existing bug in `Renderer:project()`, the ordinary non-voxel
render path. It computed yaw as:

```lua
local yaw = YAW[facing] or 0        -- modelYawOffset dropped
```

while the other two paths that place the same mesh both apply it:

- `Renderer:voxelModelMatrix()` — `(liveYaw or YAW[p.facing] or 0) + self.modelYawOffset`
- `Renderer:battleModelMatrix()` — `atan2(...) + self.modelYawOffset`

`modelYawOffset` exists because not every source mesh faces +Z. Two shipped
characters set it to pi — **Naruto** and **BelleStarmon** — and an imported
character can set any value through the import controls. Those rendered 180
degrees around: the body pointed opposite the direction of travel. Every
`modelYawOffset = 0` character looked correct, which is exactly the "some fine,
some backwards" split.

**Why it surfaced now:** the bug only bites when the ordinary path is the one
drawing. Under Gen 1 with Dramatic Shape installed, the voxel path ran instead
and applied the offset correctly. Gold has no voxel pipeline at all, so the
ordinary path is the *only* path — the bug went from intermittent to constant.

**Fix:** one line in `Renderer:project()`:

```lua
local yaw = (YAW[facing] or 0) + (self.modelYawOffset or 0)
```

Verified against the projection maths standalone: with the model's nose at
`z = +1`, an `offset = pi` character now yields the exact negated facing vector
of an `offset = 0` character for all four facings, and `offset = 0` output is
bit-identical to before, so nothing that already looked right moved.

This also fixes Gen 1 for anyone running without Dramatic Shape, and makes the
importer's yaw control behave in the ordinary path.

## v3.1.2 — WOW removed

Removed from the registry, the selector order, the mod-options character
dropdown, the donor-rig source list (`DONOR_RIG_IDS`, now BelleStarmon only)
and the import hint text. `data/wow_model.lua` and the five `wow_*` atlases are
deleted — the package drops from 111 MB to 67 MB uncompressed.

`storedCharacter()` now retires a saved `"WOW"` id to the default rather than
handing `buildCharacterRenderer` a def that no longer exists, which would have
returned nil and left the player with no character at all.

The ~58 internal `behaviorId == "WOW"` branches are left in place. They are
unreachable with no def to set that id, and tearing them out would touch the
shared BelleStarmon physics code for no functional gain.

## v3.1.4 — reverting the yaw guesses, adding FACE FLIP

**v3.1.2 and v3.1.3 were wrong.** Both assumed `modelYawOffset` had been
"dropped" from `Renderer:project()` and should be added back. It should not.

The two render paths rotate in **opposite senses**:

```lua
-- Renderer:project()          -- rotation by -yaw
xr =  c*x + s*z
zr = -s*x + c*z

-- Renderer:voxelModelMatrix() -- rotation by +yaw
m = Mat4.mul(m, Mat4.rotateY(yaw))
```

`modelYawOffset` is authored against the voxel path. Feeding it into `project()`
reversed exactly the characters that were already correct — Naruto and
BelleStarmon, the two that carry a pi offset — which is why BelleStarmon started
running backwards after v3.1.2. The v3.1.3 guess of giving Zoro and Yami a pi
offset was the same mistake extended to two more characters.

Both are reverted. `project()` is back to the shipped yaw, verified bit-identical.

**The real fix is a per-character switch, not a guess.** Source rigs genuinely
disagree about which way is forward, and the mod already accepts arbitrary
user-imported models, so no fixed table of offsets can be right for everyone.
Character Settings now has a **FACE FLIP** toggle, next to SIZE, shown for every
character including imports:

- `Renderer:setFaceFlip(on)` sets `faceFlipYaw` to `pi` or `0` and clears the
  skin/voxel cache keys so the change shows immediately.
- `project()` adds `self.faceFlipYaw`.
- Saved per character as `face_flip_<id>`, restored in `buildCharacterRenderer`
  so it survives reloads and applies to imported characters too.
- **Default is OFF for every character**, so nothing that already looked right
  can move.

Turn it on for whichever characters face the wrong way. No code edit needed, and
it works for characters that do not exist yet.

### Why this could not be settled by reading the code

`postSkinZUp` maps `x,y,z -> x,z,-y`, which sends a source +Y forward to world
-Z. That predicts Zoro and Yami need a flip — but only if those particular
exports use +Y forward, which the model data does not state. The correct answer
depends on each asset, not on the engine, so it belongs in a setting.

## v3.1.5 — Skin Selector 3D preview on Gold

**"3D PREVIEW UNAVAILABLE" was not a Gold bug in the selector; it was a missing
dependency.** `lib/SkinSelectorModelViewer.lua:227` opens with:

```lua
function Viewer:render(r,bridge,requestedW,requestedH)
  if not (r and bridge and type(bridge)=="table") then return nil end
  local Voxel3D=bridge.Voxel3D
  local Mat4=bridge.Mat4
```

`bridge` is `renderer.voxelBridge`, built by `installVoxelBridge()` from
**Dramatic Shape**'s registered `voxel` pipeline. Gold has no voxel pipeline at
all, so the bridge is always nil there and the portrait could never render.

This is also why the physics controls looked broken: the checkboxes were saving
fine, but the only place their effect is visible in the selector is that
portrait — `updateBelleBodyPhysics(nil,false,dt,true)` runs inside the viewer.
No portrait, nothing to see.

**Fix:** `Renderer:previewCanvas(w,h,facing)` — a fallback portrait drawn with
the mod's *own* projected mesh, the same renderer the overworld player uses. No
Voxel3D, no Mat4, no Dramatic Shape. It mirrors the voxel viewer's per-frame
sequence exactly — preview physics, `runtimeSkinSelectorPreview` pose flag,
selector idle phase, `updateSkeleton`, `skin()` — so BelleStarmon's physics
controls animate in the portrait the way they do with Dramatic Shape installed.

The selector tries the voxel viewer first and only falls back when it returns
nil, so a Gen 1 boot with Dramatic Shape is completely unaffected.

The silhouette is measured per frame and fitted to the panel rather than assuming
a scale, since characters range from 10.5 to 29 units tall. Verified across all
four facings: the projected bounds always land inside the canvas, and FACE FLIP
changes only the direction faced, not the fitted size.

`skinKey` is cleared after each portrait frame so the world renderer does not
inherit the preview pose.
## v3.1.6 — facing cleanup + projected-preview centering

Naruto and BelleStarmon no longer carry the old `modelYawOffset = pi` values.
With the current displacement-based true-direction voxel path those historical
corrections are now a second 180-degree turn, so both characters can appear to
run backward. Their built-in definitions now use zero model yaw offset.

The v3.1.5 Gold/no-voxel preview fallback also had a centering error: it first
called `project()` with the fitted scale and then translated the finished mesh
again by a scale-dependent amount. The second transform could push tall, short,
or unusually proportioned models outside the portrait. v3.1.6 solves the foot
origin from the measured projected silhouette and draws the mesh without that
second translation.
## v3.1.7 — separate intrinsic yaw for Gold/projected rendering

The v3.1.6 diagnosis conflated the travel bearing with the imported mesh's forward axis. Naruto and BelleStarmon are actually authored facing `-Z`; the Voxel3D selector therefore needs their historical `modelYawOffset = pi` to present the front of the model at viewer yaw zero.

Gold does not use `voxelModelMatrix()` for its normal overworld player. `Gen2Bridge` calls `Renderer:draw()`, whose `project()` path deliberately has its own rotation convention. v3.1.7 adds `projectYawOffset` to `Renderer` and applies it in both `project()` and the projected selector fallback. Naruto and BelleStarmon set both offsets to pi, fixing viewer orientation and Gold travel-facing at the same time. FACE FLIP remains an extra saved user override.

