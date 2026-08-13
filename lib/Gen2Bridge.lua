-- Gen2Bridge -- Generation 2 (Gold) support for the 3D Character Selector.
--
-- Gen1Recomp runs TWO different game objects.  A Red/Blue/Yellow boot builds
-- src/core/Game.lua and an overworld whose player is src/world/Player.lua; a
-- Gold boot builds src/core/Game2.lua and a world whose player is
-- src/world/gen2/Player.lua.  The mod platform itself is shared -- Gold raises
-- input.pointer, render.hud, render.zones, movement.speed and
-- ui.start_menu.items under the same names, with the same payloads, at the same
-- point in the frame -- so the selector screen, the touch layer, the options and
-- the saved per-character settings all carry over untouched.
--
-- Four things do NOT carry over, and they are the whole of this file:
--
--   1. Player:draw's contract.  Gen 1 is draw(camX, camY) in world pixels
--      inside an already-scaled transform.  Gen 2 is draw(ox, oy, scale) where
--      ox/oy are SCREEN pixels the callee is expected to translate by before
--      applying its own scale (src/world/gen2/World.lua:drawPeople).
--   2. Player:pose().  Gen 2 has no such method; the same six values live in
--      loose fields (moving / stepFlip / jumping / spriteYOffset / walkPhase).
--   3. The overworld handle.  Gen 1 exposes Game.overworld; Gold keeps its
--      world on the Game2 INSTANCE as `world`, reachable through the state
--      stack.
--   4. The true-colour opt-out.  PaletteFX is not in Gold's render path, so
--      markTrueColor silently no-ops there.  Gold's equivalent is a
--      render.zones entry with `colors = false`, which matters only in CLASSIC
--      colour mode -- in normal Gold colour the palettes are applied per
--      sprite and nothing would have re-shaded the mesh anyway.
--
-- Everything else -- collision, movement, the camera, NPCs, warps, the world
-- itself -- stays owned by the engine, exactly as it does under Gen 1.

local Gen2Bridge = {}

local GEN2_VERSIONS = { gold = true, silver = true, crystal = true }

-- Gold-only.  Called before anything is patched, so a Red/Blue/Yellow boot
-- pays nothing for this file being present.
function Gen2Bridge.isActive()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not ok or type(GameVersion) ~= "table" then return false end
  if type(GameVersion.generation) == "function" then
    local okGen, gen = pcall(GameVersion.generation)
    if okGen and tonumber(gen) == 2 then return true end
  end
  if type(GameVersion.isGold) == "function" then
    local okGold, gold = pcall(GameVersion.isGold)
    if okGold and gold then return true end
  end
  if type(GameVersion.get) == "function" then
    local okId, id = pcall(GameVersion.get)
    if okId and GEN2_VERSIONS[tostring(id)] then return true end
  end
  return false
end

-- The live Game2 instance.  Gold does not publish a module-level handle the
-- way Gen 1's Game.overworld does, so walk the state stack and take the game
-- reference a stacked screen is holding.  Falls back to the module table for
-- the wheel patch, which only needs the class.
local function liveGame()
  local ok, StateStack = pcall(require, "src.core.StateStack")
  if not ok or type(StateStack) ~= "table" or type(StateStack.top) ~= "function" then
    return nil
  end
  local okTop, top = pcall(StateStack.top, StateStack)
  if not okTop or type(top) ~= "table" then return nil end
  local game = top.game or top.g
  if type(game) == "table" then return game end
  return nil
end

-- Gold's world.
--
-- The FIRST source is the official seam: under a Gen 2 boot the loader's
-- require shim answers `src.core.Game` with the Gen2Compat facade, whose
-- `.overworld` is documented as the Gen 1 spelling of Game2.world and is
-- resolved at CALL time off the live game (src/mods/Gen2Compat.lua:buildGame).
-- That is the supported way to ask, so ask it first.
--
-- The shim only swaps the module in for code it recognises as the mod's own,
-- so the state-stack walk stays as the fallback: on a Gen 1 boot, or anywhere
-- the facade is not served, `require` hands back the real Gen 1 module whose
-- `.overworld` is simply nil, and the walk answers instead.
function Gen2Bridge.world()
  local okGame, Game = pcall(require, "src.core.Game")
  if okGame and type(Game) == "table" then
    local okOw, ow = pcall(function() return Game.overworld end)
    if okOw and type(ow) == "table" then return ow end
  end
  local game = liveGame()
  if type(game) ~= "table" then return nil end
  local w = game.world or game.overworld
  if type(w) == "table" then return w end
  return nil
end

function Gen2Bridge.player()
  local w = Gen2Bridge.world()
  return w and w.player or nil
end

-- Surf, bike and the fishing pose all replace the walking sheet with a
-- purpose-drawn card the 3D mesh has no equivalent for, so the stock sprite is
-- left alone for those -- the same rule the Gen 1 path applies through
-- playerUsesSpecialCard().  Gold keeps the mount state on the WORLD
-- (World.playerState, read through FieldMoves) rather than on the player, so
-- this cannot be a field test on the player object.
local FieldMoves = nil
local function specialCard(player)
  if player and player.fishing then return true end
  local w = Gen2Bridge.world()
  if type(w) ~= "table" then return false end
  if w.fishing then return true end
  if FieldMoves == nil then
    local ok, mod = pcall(require, "src.world.gen2.FieldMoves")
    FieldMoves = (ok and type(mod) == "table") and mod or false
  end
  if not FieldMoves then return false end
  local state = w.playerState
  if state == nil then return false end
  local okSurf, surfing = pcall(FieldMoves.isSurfing, state)
  if okSurf and surfing then return true end
  local okBike, biking = pcall(FieldMoves.isBiking, state)
  if okBike and biking then return true end
  return false
end

-- Gen 1's Player:pose() in six values, rebuilt from what Gold's player
-- actually carries.
--
--   px/py     -- world pixels, already interpolated by Player:update, with
--                OBJECT_SPRITE_Y_OFFSET folded in the way Gen 2's own draw does
--   facing    -- same four names as Gen 1
--   phase     -- Player:walkPhase(), same 0/1 leg frame
--   flip      -- Gen 2 alternates cycles with a per-step boolean (stepFlip)
--                instead of Gen 1's animClock division; same meaning
--   hopping   -- the ledge jump; Gen 2 sets `jumping` for the two-cell move
local function gen2Pose(player)
  local px = tonumber(player.px) or 0
  local py = (tonumber(player.py) or 0) + (tonumber(player.spriteYOffset) or 0)
  local facing = player.facing or "down"
  local phase = 0
  if type(player.walkPhase) == "function" then
    local ok, p = pcall(player.walkPhase, player)
    if ok then phase = tonumber(p) or 0 end
  end
  return px, py, facing, phase, player.stepFlip and true or false,
         player.jumping and true or false
end

-- CLASSIC-mode true-colour opt-out, the Gold analogue of
-- PaletteFX.markTrueColor.  A zone rect is 160x144 SCREEN space and
-- `colors = false` draws that rect with no palette shader at all
-- (src/core/Game2.lua:blitZones).  The rect is generous on purpose: it is a
-- shader exemption, not a clip, and the cost of it being a few pixels large is
-- nothing while the cost of it being a few pixels small is a half-recoloured
-- character.
local function installZoneOptOut(mod, renderer, config)
  if not (mod and mod.hooks and mod.hooks.wrap) then return end
  local height = (config and tonumber(config.height)) or 40
  pcall(function()
    mod.hooks:wrap("render.zones", function(next, game, zones)
      local result = next(game, zones)
      if renderer.failed then return result end
      if type(result) ~= "table" or result[1] == nil then return result end
      local w = Gen2Bridge.world()
      local player = w and w.player
      local cam = w and w.camera
      if not (player and cam) then return result end
      if specialCard(player) then return result end
      local px, py = gen2Pose(player)
      local x = math.floor(px - (tonumber(cam.x) or 0)) + 8 - 20
      local y = math.floor(py - (tonumber(cam.y) or 0)) + 12 - height - 8
      result[#result + 1] =
        { x = x, y = y, w = 40, h = height + 16, colors = false }
      return result
    end)
  end)
end

-- The Skin Selector's mouse-wheel zoom.  Gen 1 patches Game.wheelmoved; Gold's
-- wheel handler is the separate Game2:wheelmoved, so the selector screen needs
-- the same interception installed on that class too.  `handled` is the shared
-- decision function main.lua already uses for the Gen 1 patch: it returns true
-- when the wheel event belonged to the selector and has been consumed.
local function installWheel(handled)
  local ok, Game2 = pcall(require, "src.core.Game2")
  if not ok or type(Game2) ~= "table" then return false end
  if type(Game2.wheelmoved) ~= "function" then return false end
  if Game2._red3dSelectorWheelZoomInstalled then return true end
  local previousWheel = Game2.wheelmoved
  Game2._red3dSelectorWheelZoomInstalled = true
  Game2.wheelmoved = function(game, dx, dy)
    local okHandled, consumed = pcall(handled, game, dx, dy)
    if okHandled and consumed then return end
    return previousWheel(game, dx, dy)
  end
  return true
end

-- The cosmetic manual jump (controller west-face button).
--
-- Under Gen 1 the mod first asks the overworld for a REAL ledge crossing
-- (OverworldState:checkLedgeHop) and only falls back to a visual hop.  Gold's
-- ledge crossing is World:tryLedgeJump with a different signature and its own
-- two-cell STEP_LEDGE, and it is already reachable by simply walking into a
-- ledge -- so the Gen 2 path deliberately offers the COSMETIC jump only and
-- leaves every real map crossing to the engine.  Nothing here can move the
-- player through geometry.
local function installManualJump(mod, renderer, jumpFrames)
  local okPlayer, Player = pcall(require, "src.world.gen2.Player")
  if not okPlayer or type(Player) ~= "table" then return false end

  -- Tick the counters the renderer reads through manualJumpLift().
  if not Player.red3dManualJumpUpdateInstalled then
    Player.red3dManualJumpUpdateInstalled = true
    local previousUpdate = Player.update
    function Player:update(...)
      if self.red3dManualJumpFrames and self.red3dManualJumpFrames > 0 then
        self.red3dManualJumpFrames = self.red3dManualJumpFrames - 1
        if self.red3dManualJumpFrames <= 0 then
          self.red3dManualJumpFrames = nil
          self.red3dManualJumpTotal = nil
        end
      end
      return previousUpdate(self, ...)
    end
  end

  local okGame, Game2 = pcall(require, "src.core.Game2")
  if not okGame or type(Game2) ~= "table"
      or type(Game2.gamepadpressed) ~= "function" then
    return false
  end
  if Game2.red3dManualJumpInstalled then return true end
  Game2.red3dManualJumpInstalled = true

  local previousPressed = Game2.gamepadpressed
  function Game2:gamepadpressed(joystick, button)
    if button == "x" then
      local player = Gen2Bridge.player()
      -- Never on top of the engine's own two-cell ledge jump, and never on top
      -- of a cosmetic jump already playing.  `moving` is deliberately NOT a
      -- guard: a Gen 2 step holds it true for all 16 frames of the cell, so
      -- refusing on it would make the button feel dead while walking.  The lift
      -- is purely visual, exactly as it is under Gen 1.
      if player and not player.jumping
          and not specialCard(player)
          and not (player.red3dManualJumpFrames and player.red3dManualJumpFrames > 0) then
        local frames = tonumber(jumpFrames) or 30
        local active = renderer.getActive and renderer:getActive() or nil
        local behavior = active and active.behaviorId or renderer.behaviorId
        if behavior == "BELLESTARMON" then frames = 42
        elseif behavior == "WOW" then frames = 48 end
        player.red3dManualJumpTotal = frames
        player.red3dManualJumpFrames = frames
        renderer.skinKey = nil
        renderer.voxelUploadedKey = nil
        return
      end
    end
    return previousPressed(self, joystick, button)
  end

  if mod and mod.log then
    mod.log:info("3D Character Selector: Gen 2 cosmetic jump bound to the west-face button")
  end
  return true
end

-- v3.1.12: true directional / diagonal movement for Gold.
--
-- Gold already interpolates Player:update() toward targetX/targetY, so unlike
-- Gen 1 it needs no custom update loop.  We only teach World to accept a
-- diagonal held direction, validate BOTH side cells (no corner cutting), then
-- give the stock player a diagonal target.  All landing logic -- grass, warps,
-- encounters, step counters, scripts -- still sees a normal completed cell.
local function installDirectionalMovement(mod)
  local okWorld, World = pcall(require, "src.world.gen2.World")
  local okPlayer, Player = pcall(require, "src.world.gen2.Player")
  local okMap, Map = pcall(require, "src.world.gen2.Map")
  local okPerm, Permissions = pcall(require, "src.world.gen2.Permissions")
  local okRuntime, Runtime = pcall(require, "src.mods.Runtime")
  if not (okWorld and okPlayer and okMap and okPerm
      and type(World) == "table" and type(Player) == "table"
      and type(Map) == "table" and type(Permissions) == "table") then
    return false
  end

  local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    return math.atan(y, x)
  end

  local function signAxis(v, dead)
    v = tonumber(v) or 0
    dead = tonumber(dead) or 0.22
    if v > dead then return 1 end
    if v < -dead then return -1 end
    return 0
  end

  local function intent(input, p)
    local mx = tonumber(p and p.red3dMoveStickX) or 0
    local my = tonumber(p and p.red3dMoveStickY) or 0
    local dx, dy = 0, 0
    if p and p.red3dAnalogMoveActive then
      dx, dy = signAxis(mx, 0.22), signAxis(my, 0.22)
    end
    if dx == 0 and input then
      dx = (input:isDown("right") and 1 or 0)
         - (input:isDown("left") and 1 or 0)
    end
    if dy == 0 and input then
      dy = (input:isDown("down") and 1 or 0)
         - (input:isDown("up") and 1 or 0)
    end
    if dx < -1 then dx = -1 elseif dx > 1 then dx = 1 end
    if dy < -1 then dy = -1 elseif dy > 1 then dy = 1 end
    return dx, dy, mx, my
  end

  local function faceFor(p, dx, dy, mx, my)
    local h = dx < 0 and "left" or (dx > 0 and "right" or nil)
    local v = dy < 0 and "up" or (dy > 0 and "down" or nil)
    if p and (p.facing == h or p.facing == v) then return p.facing end
    if math.abs(mx) > math.abs(my) + 0.05 then return h or v end
    return v or h or (p and p.facing) or "down"
  end

  local DIAG = {
    up_left={-1,-1}, up_right={1,-1},
    down_left={-1,1}, down_right={1,1},
  }
  local function diagName(dx, dy)
    if dx < 0 and dy < 0 then return "up_left" end
    if dx > 0 and dy < 0 then return "up_right" end
    if dx < 0 and dy > 0 then return "down_left" end
    if dx > 0 and dy > 0 then return "down_right" end
    return nil
  end

  -- Input.lua intentionally collapses analogue movement to one dominant axis.
  -- Keep the raw left-stick pair on the live Gold player so two-axis intent is
  -- still available to this opt-in movement layer.
  local okGame2, Game2 = pcall(require, "src.core.Game2")
  if okGame2 and type(Game2) == "table" and type(Game2.gamepadaxis) == "function"
      and not Game2.red3dDirectionalAxisInstalled then
    Game2.red3dDirectionalAxisInstalled = true
    local previousAxis = Game2.gamepadaxis
    function Game2:gamepadaxis(joystick, axis, value)
      local p = self.world and self.world.player or Gen2Bridge.player()
      if p then
        if axis == "leftx" then p.red3dMoveStickX = value or 0
        elseif axis == "lefty" then p.red3dMoveStickY = value or 0 end
        if axis == "leftx" or axis == "lefty" then
          local x = tonumber(p.red3dMoveStickX) or 0
          local y = tonumber(p.red3dMoveStickY) or 0
          p.red3dAnalogMoveActive = math.sqrt(x*x + y*y) > 0.08
        end
      end
      return previousAxis(self, joystick, axis, value)
    end
  end

  if type(World.pollInput) == "function" and not World.red3dDirectionalPollInstalled then
    World.red3dDirectionalPollInstalled = true
    local previousPoll = World.pollInput
    function World:pollInput(input)
      local result = previousPoll(self, input)
      local p = self.player
      -- Special player cards and Cycling Road/forced movement keep the exact
      -- original one-axis rules.
      local downhill = type(self.downhill) == "function" and self:downhill()
      if p and not specialCard(p) and not downhill then
        local dx, dy, mx, my = intent(input, p)
        local name = diagName(dx, dy)
        if name then
          self.heldDir = name
          p.red3dDiagonalFace = faceFor(p, dx, dy, mx, my)
          p.red3dRequestedTravelYaw = atan2(dx, dy)
        else
          p.red3dDiagonalFace = nil
          p.red3dRequestedTravelYaw = nil
        end
      elseif p then
        p.red3dDiagonalFace = nil
        p.red3dRequestedTravelYaw = nil
      end
      return result
    end
  end

  if type(World.movePlayer) == "function" and not World.red3dDirectionalMoveInstalled then
    World.red3dDirectionalMoveInstalled = true
    local previousMove = World.movePlayer

    local function entityBlocks(world, p, x, y)
      -- npcAt accounts for Gold's BIG_OBJECT occupancy. Keep the generic scan
      -- too because followers/mod entities can live outside the NPC table.
      if type(world.npcAt) == "function" then
        local ok, npc = pcall(world.npcAt, world, x, y)
        if ok and npc then return true end
      end
      for _, e in ipairs(world.entities or {}) do
        if e ~= p and not e.passable then
          if e.cellX == x and e.cellY == y then return true end
          if e.moving and e.targetX == x and e.targetY == y then return true end
        end
      end
      return false
    end

    local function cardinalClear(world, p, map, dir)
      local d = Map.DELTA[dir]
      if not d then return false end
      local tx, ty = p.cellX + d[1], p.cellY + d[2]
      if not map:inBounds(tx, ty) or not map:isWalkable(tx, ty) then return false end
      if not Permissions.stepPermitted(
          function(x, y) return map:cellCollision(x, y) end,
          p.cellX, p.cellY, dir) then return false end
      if entityBlocks(world, p, tx, ty) then return false end
      return true
    end

    function World:movePlayer(dir)
      local dxy = DIAG[dir]
      if not dxy then return previousMove(self, dir) end
      local p, map = self.player, self.map
      if not (p and map) or p.moving or specialCard(p) then
        local fallback = p and p.red3dDiagonalFace or "down"
        return previousMove(self, fallback)
      end
      if type(self.downhill) == "function" and self:downhill() then
        return previousMove(self, p.red3dDiagonalFace or "down")
      end

      local dx, dy = dxy[1], dxy[2]
      local hdir = dx < 0 and "left" or "right"
      local vdir = dy < 0 and "up" or "down"
      local face = p.red3dDiagonalFace or vdir
      local tx, ty = p.cellX + dx, p.cellY + dy

      -- Never use a diagonal to cross a map connection. The stock edge path
      -- can then perform the correct cardinal connection/warp transition.
      if not map:inBounds(tx, ty) then return previousMove(self, face) end
      if not cardinalClear(self, p, map, hdir)
          or not cardinalClear(self, p, map, vdir)
          or not map:isWalkable(tx, ty)
          or entityBlocks(self, p, tx, ty) then
        return previousMove(self, face)
      end

      -- Door carpets/currents have directional semantics. Do not enter those
      -- diagonally; let the engine take a normal cardinal step instead.
      local coll = map:cellCollision(tx, ty)
      if (Permissions.carpetDirection and Permissions.carpetDirection(coll))
          or (Permissions.currentDirection and Permissions.currentDirection(coll))
          or (Permissions.doorForcedDirection and Permissions.doorForcedDirection(coll)) then
        return previousMove(self, face)
      end

      p.facing = face
      p.turnArmed = false
      p.turnTimer = 0
      p.targetX, p.targetY = tx, ty
      p.moving = true
      p.progress = 0
      p.red3dDiagonalMove = true
      local yaw = p.red3dRequestedTravelYaw or atan2(dx, dy)
      p.red3dProjectedBodyYaw = yaw
      p.red3dFreeBodyYaw = yaw

      -- On-foot Gold is 16 frames/cell. Run movement.speed first, then multiply
      -- by sqrt(2) so a diagonal does not move 41% faster in world space.
      local frames = tonumber(Player.STEP_FRAMES) or 16
      if okRuntime and Runtime and Runtime.wantsHook and Runtime.wantsHook("movement.speed") then
        local save = self.game and self.game.save
        frames = Runtime.call("movement.speed", function(f) return f end, frames, {
          onBike = false, surfing = false, downhill = false,
          playerState = self.playerState, player = p,
          input = self.game and self.game.input, save = save,
        })
      end
      frames = math.max(1, tonumber(frames) or 16)
      p.stepFrames = math.max(1, math.floor(frames * math.sqrt(2) + 0.5))
      self.turningDirection = face
      if type(self.playerStepGrass) == "function" then self:playerStepGrass() end
      return "moved"
    end
  end

  -- Clear the diagonal marker on landing. Gold's Player:update already commits
  -- the target correctly, so this wrapper is bookkeeping only.
  if type(Player.update) == "function" and not Player.red3dDirectionalClearInstalled then
    Player.red3dDirectionalClearInstalled = true
    local previousUpdate = Player.update
    function Player:update(...)
      local landed = previousUpdate(self, ...)
      if landed then self.red3dDiagonalMove = nil end
      return landed
    end
  end

  if mod and mod.log then
    mod.log:info("3D Character Selector: Gen 2 eight-way directional movement installed")
  end
  return true
end

-- Install the 3D mesh over Gold's player.
--
-- ctx = {
--   mod            -- the mod handle (log, hooks)
--   renderer       -- the shared ActiveRenderer, same instance the Gen 1 path uses
--   config         -- CONFIG, for the zone rect height and manualJumpFrames
--   drawHopShadow  -- optional; the Gen 1 ledge shadow helper
--   selectorWheel  -- optional; function(game, dx, dy) -> consumed
-- }
function Gen2Bridge.install(ctx)
  ctx = ctx or {}
  local mod = ctx.mod
  local renderer = ctx.renderer
  if not renderer then return false, "no renderer" end
  if not Gen2Bridge.isActive() then return false, "not a Gen 2 boot" end

  local ok, Player = pcall(require, "src.world.gen2.Player")
  if not ok or type(Player) ~= "table" or type(Player.draw) ~= "function" then
    if mod and mod.log then
      mod.log:error("Gen 2 player renderer unavailable -- this build of Gen1Recomp does not expose src.world.gen2.Player")
    end
    return false, "no gen2 player"
  end

  if not Player.red3dPlayerInstalled then
    local previousDraw = Player.draw
    Player.red3dPlayerInstalled = true
    Player.red3dPlayerRenderer = renderer

    -- Gold hands the callee SCREEN pixels plus the scale and expects it to set
    -- up its own transform.  Do exactly that, then hand the renderer a ZERO
    -- camera: inside the pushed transform the mesh's own world-pixel
    -- projection lands on the right screen pixels, at the right size, with no
    -- second scale factor threaded through the projector.
    function Player:draw(ox, oy, scale)
      if renderer.failed then return previousDraw(self, ox, oy, scale) end
      if specialCard(self) then return previousDraw(self, ox, oy, scale) end

      local s = tonumber(scale) or 1
      local px, py, facing, phase, flip, hopping = gen2Pose(self)

      local G = love.graphics
      G.push()
      G.translate(tonumber(ox) or 0, tonumber(oy) or 0)
      G.scale(s, s)

      if hopping and type(ctx.drawHopShadow) == "function" then
        pcall(ctx.drawHopShadow, self, 0, 0)
      end

      local okDraw, shown = pcall(renderer.draw, renderer, self, px, py, 0, 0,
                                  facing, phase, flip)
      G.pop()

      if not okDraw then
        renderer.failed = true
        if mod and mod.log then
          mod.log:error("3D player renderer disabled after Gen 2 draw error: %s -- stock sprite will resume next frame",
                        tostring(shown))
        end
        return previousDraw(self, ox, oy, scale)
      end
      if not shown then return previousDraw(self, ox, oy, scale) end
    end
  elseif Player.red3dPlayerRenderer then
    -- Hot reload / duplicate install: keep the renderer that is already live.
    renderer = Player.red3dPlayerRenderer
  end

  if type(ctx.selectorWheel) == "function" then
    installWheel(ctx.selectorWheel)
  end
  installZoneOptOut(mod, renderer, ctx.config)
  pcall(installDirectionalMovement, mod)
  pcall(installManualJump, mod, renderer,
        ctx.config and ctx.config.manualJumpFrames)

  if mod and mod.log then
    mod.log:info("3D Character Selector: Gen 2 (Gold) player bridge installed")
  end
  return true
end

return Gen2Bridge
