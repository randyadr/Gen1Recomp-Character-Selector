-- 3D Character Selector for Gen1Recomp (Mod API 2)
--
-- v1.2 keeps the ordinary Player:draw() + Dramatic Shape voxel bridge and upgrades the
-- bridge into Dramatic Shape's voxel render pass.  Dramatic Shape normally
-- turns overworld actors into leaning sprite cards, so replacing Player:draw
-- alone cannot affect that mode.  The bridge below replaces only the player
-- card with this mod's real skinned mesh while leaving movement/collision,
-- NPCs, figures, water, lighting, camera and world geometry owned by the two
-- original projects.

local function loadLuaData(mod, rel)
  local source = mod:read(rel)
  if not source then
    mod.log:error("missing %s -- reinstall the complete Red 3D Player mod", rel)
    return nil
  end
  local chunk, err = load(source, "@" .. tostring(mod.path or mod.id) .. "/" .. rel)
  if not chunk then
    mod.log:error("%s did not compile: %s -- rebuild with tools/convert_red_dae.py", rel, tostring(err))
    return nil
  end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then
    mod.log:error("%s did not return model data: %s", rel, tostring(data))
    return nil
  end
  return data
end

local function copy16(flat, base)
  return {
    flat[base],flat[base+1],flat[base+2],flat[base+3],
    flat[base+4],flat[base+5],flat[base+6],flat[base+7],
    flat[base+8],flat[base+9],flat[base+10],flat[base+11],
    flat[base+12],flat[base+13],flat[base+14],flat[base+15],
  }
end

local function mul16(a,b,o)
  for r=0,3 do
    local r4=r*4
    for c=1,4 do
      o[r4+c] = a[r4+1]*b[c] + a[r4+2]*b[4+c]
                + a[r4+3]*b[8+c] + a[r4+4]*b[12+c]
    end
  end
  return o
end

local function transformPoint(m,x,y,z)
  return m[1]*x+m[2]*y+m[3]*z+m[4],
         m[5]*x+m[6]*y+m[7]*z+m[8],
         m[9]*x+m[10]*y+m[11]*z+m[12]
end

local function rotX(a)
  local c,s=math.cos(a),math.sin(a)
  return {1,0,0,0, 0,c,-s,0, 0,s,c,0, 0,0,0,1}
end

local function rotY(a)
  local c,s=math.cos(a),math.sin(a)
  return {c,0,s,0, 0,1,0,0, -s,0,c,0, 0,0,0,1}
end

local function rotZ(a)
  local c,s=math.cos(a),math.sin(a)
  return {c,-s,0,0, s,c,0,0, 0,0,1,0, 0,0,0,1}
end

local function rotAxis(x,y,z,a)
  local n=math.sqrt(x*x+y*y+z*z)
  if n<1e-9 then return {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1} end
  x,y,z=x/n,y/n,z/n
  local c,s=math.cos(a),math.sin(a); local k=1-c
  return {
    c+x*x*k, x*y*k-z*s, x*z*k+y*s, 0,
    y*x*k+z*s, c+y*y*k, y*z*k-x*s, 0,
    z*x*k-y*s, z*y*k+x*s, c+z*z*k, 0,
    0,0,0,1
  }
end

local function translate16(x,y,z)
  return {1,0,0,x, 0,1,0,y, 0,0,1,z, 0,0,0,1}
end

local function compose(a,b)
  local out={}
  return mul16(a,b,out)
end

local function compose3(a,b,c)
  return compose(compose(a,b),c)
end

local Renderer = {}
Renderer.__index = Renderer

local CONFIG = {
  height = 27,          -- body height in Dramatic Shape / overworld world pixels
  depthSlope = 0.12,    -- only used by the ordinary 2D projected fallback
  armRestDeg = 78,      -- supplied asset is a T-pose; rest both arms downward
  modelYawOffset = 0,   -- source Red faces +Z, which is map SOUTH in Dramatic Shape

  -- One complete cycle contains a left and right step.  At the normal
  -- overworld speed this lands in a relaxed/light-jog cadence rather than a
  -- sprint, while still scaling automatically with actual player speed.
  worldPixelsPerCycle = 30.0,
  groundClearance = 0.04,

  hipBobUnits = 0.62,
  hipTwistDeg = 1.15,
  shoulderTwistDeg = 2.55,
  jogLeanDeg = 2.5,
  headCounterDeg = 1.20,
  headBobUnits = 0.20,
  headNodDeg = 1.8,
  headYawDeg = 0.7,
  headRollDeg = 0.5,
  bagSwingDeg = 3.45,
  fingerCurlDeg = 7.5,
  thumbCurlDeg = 4.6,
  fingerMotionDeg = 7.0,
  thumbMotionDeg = 2.8,

  -- Ledge-hop animation. The world renderer already supplies the actual
  -- vertical arc; these values only pose the body during takeoff/air/landing.
  jumpCrouchUnits = 2.1,
  jumpLeanDeg = 4.2,
  jumpArmDeg = 16.0,
  manualJumpFrames = 30,
  manualJumpHeight = 8.0,
  cjShootFrames = 12,
  cjShootCooldown = 5,
  cjShootRangeCells = 13,
  cjAimCursorRadius = 86,
  cjAimCursorRadiusADS = 28,
  cjAimDeadzone = 0.18,
  cjADSZoom = 1.0, -- ADS now owns a real placed over-shoulder camera/FOV.
  cjADSDeadzone = 0.12,
  cjAimCameraBoom = 42,
  cjAimCameraShoulder = 6.0,
  cjAimCameraLift = 4.5,
  cjAimCameraFovDeg = 60,
  cjAimCameraBlendFrames = 5,
  -- Match Dramatic Shape's native free-camera stick rates/response closely.
  cjLookYawSpeed = 3.5,
  cjLookPitchSpeed = 2.4,
  cjLookPitchUp = -0.42,
  cjLookPitchDown = 0.58,
  cjDebrisCount = 75,
  cjDebrisLife = 1.55,
  cjDebrisGravity3D = 48,
  cjDebrisBounce = 0.38,
  cjDebrisGroundFriction = 0.72,
  cjDebrisBurstSpeed = 32,
  cjDebrisBurstUp = 25,
  cjHipSpreadDeg = 0.45,
  cjADSSpreadDeg = 0.0,
  cjAimAssistDeg = 3.25,
  cjAimAssistRange = 13.0,
  cjAimAssistStrength = 0.34,
  cjWorldImplodeTime = 0.045,
  cjDebrisImplodeStrength = 170,
  cjDebrisBurstMultiplier = 1.18,
  cjWorldDestroy = true,

  -- Motion controller smoothing.  These are rates, not fixed animation FPS,
  -- so they behave consistently on high-refresh displays.
  speedResponse = 10.0,
  startBlendRate = 10.0,
  stopBlendRate = 6.8,
  seamGrace = 0.12,

  -- BelleStarmon analog locomotion. A light analog tilt stays on the supplied
  -- catwalk clip; the upper half of the stick travel crossfades into Fast Run.
  belleWalkCyclePixels = 72.0,
  belleRunCyclePixels = 31.0,
  belleRunBlendStart = 0.55,
  belleRunBlendFull = 0.92,
  belleRunBlendRate = 7.5,
}

function Renderer.new(mod,data,characterDef)
  characterDef=characterDef or {}
  local self=setmetatable({
    mod=mod,data=data,failed=false,voxelFailed=false,
    characterId=characterDef.id or "RED",
    characterLabel=characterDef.label or characterDef.id or "RED",
    atlasPath=characterDef.atlas or "assets/red_atlas.png",
    atlasFrames=characterDef.atlasFrames or nil,
    dynamicAtlasMode=characterDef.dynamicAtlas or nil,
    modelYawOffset=characterDef.modelYawOffset or CONFIG.modelYawOffset,
    renderHeight=characterDef.height or CONFIG.height,
    animationProfile=characterDef.profile or "RED",
    armRestDeg=characterDef.armRestDeg or CONFIG.armRestDeg,
    motionDistance=0,motionX=nil,motionY=nil,lastAnimClock=nil,
    motionSampleTime=nil,voxelFrameSerial=0,voxelFrameClock=nil,
    voxelFrameWalking=false,voxelFrameKey=nil,voxelFrameBlend=0,
    voxelGaitDistance=0,voxelLastTime=nil,voxelLastMovingTime=nil,
    voxelLastSpeed=60,voxelSmoothSpeed=0,voxelMoveBlend=0,
    voxelWasMoving=false,motionMeasuredSpeed=nil,
    beelCloth=nil,beelClothSpeed=0,beelClothLastTime=nil,
    ashIdleTime=0,ashIdleLastTime=nil,
    beelIdleTime=0,beelIdleLastTime=nil,
    aangIdleTime=0,aangIdleLastTime=nil,
    cjIdleTime=0,cjIdleLastTime=nil,
    yamiIdleTime=0,yamiIdleLastTime=nil,
    belleRunBlend=0,belleGaitPhase=0,
    postSkinZUp=characterDef.postSkinZUp==true,
  },Renderer)
  -- model.lua only exposes a small animation-bone subset.  Extend it at
  -- runtime from the generated bone names so wrists/fingers can animate too.
  data.animBone=data.animBone or {}
  data.runtimeProfile=self.animationProfile
  data.runtimeCharacterId=self.characterId
  data.runtimeArmRest=self.armRestDeg
  if self.characterId=="BELLESTARMON" then data.runtimeBelleRunBlend=0 end
  for i,name in ipairs(data.boneName or {}) do
    if data.animBone[name]==nil then data.animBone[name]=i end
  end
  self.bindLocal={}; self.world={}; self.localWork={}
  for i=1,data.boneCount do
    self.bindLocal[i]=copy16(data.boneLocal,(i-1)*16+1)
    self.world[i]={}; self.localWork[i]={}
  end
  self.sx={}; self.sy={}; self.sz={}; self.screenX={}; self.screenY={}

  -- Lossless render-vertex compaction. Generated models often contain one
  -- corner vertex for every triangle corner even when many corners reference
  -- the exact same skinned position and UV. Updating those duplicates every
  -- frame is especially expensive on large imports (Yami was 147k corners).
  -- Build one render vertex for each unique position+UV tuple and use indexed
  -- triangle maps. Geometry, UVs and triangle order remain unchanged.
  self.vertexRows={}; self.voxelRows={}; self.vertexPos={};
  self.cornerVertex={}; self.baseMap={}; self.maps={}
  local compactLookup={}
  for i=1,data.cornerCount do
    local pos=data.cornerPos[i]
    local u,v=data.cornerU[i],data.cornerV[i]
    local byPos=compactLookup[pos]
    if not byPos then byPos={}; compactLookup[pos]=byPos end
    local byU=byPos[u]
    if not byU then byU={}; byPos[u]=byU end
    local vi=byU[v]
    if not vi then
      vi=#self.vertexRows+1
      byU[v]=vi
      self.vertexPos[vi]=pos
      self.vertexRows[vi]={0,0,u,v,1,1,1,1}
      self.voxelRows[vi]={0,0,0,u,v,1.0}
    end
    self.cornerVertex[i]=vi
    self.baseMap[i]=vi
  end
  self.renderVertexCount=#self.vertexRows
  for facing,order in pairs(data.order) do
    local map={}
    local n=0
    for i=1,#order do
      local b=(order[i]-1)*3
      n=n+1; map[n]=self.cornerVertex[b+1]
      n=n+1; map[n]=self.cornerVertex[b+2]
      n=n+1; map[n]=self.cornerVertex[b+3]
    end
    self.maps[facing]=map
  end
  local b=data.bounds
  self.minX,self.minY,self.minZ=b[1],b[2],b[3]
  self.maxX,self.maxY,self.maxZ=b[4],b[5],b[6]
  self.centerX=(self.minX+self.maxX)*0.5
  self.centerZ=(self.minZ+self.maxZ)*0.5
  self.scale=self.renderHeight/(self.maxY-self.minY)
  self.skinKey=nil
  self.voxelUploadedKey=nil
  return self
end

local function runtimeClock()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

function Renderer:atlasFramePath()
  if type(self.atlasFrames)~="table" or #self.atlasFrames==0 then
    return self.atlasPath
  end
  if self.dynamicAtlasMode=="blink" then
    local phase=runtimeClock()%4.2
    if (phase>=3.62 and phase<3.69) or (phase>=3.78 and phase<3.84) then
      return self.atlasFrames[2] or self.atlasFrames[1]
    end
  end
  return self.atlasFrames[1]
end

function Renderer:loadAtlasImage(path)
  self.imageCache=self.imageCache or {}
  if self.imageCache[path] then return self.imageCache[path] end
  if not (love and love.graphics and love.graphics.newImage) then return nil end

  local bytes=self.mod:read(path)
  if not bytes then
    self.mod.log:error("%s is missing for character %s -- reinstall the complete mod", tostring(path), tostring(self.characterLabel))
    return nil
  end
  local ok,img=pcall(function()
    if love.filesystem and love.filesystem.newFileData then
      local fd=love.filesystem.newFileData(bytes,self.characterId .. "_" .. path:gsub("[^%w]+","_") .. ".png")
      return love.graphics.newImage(fd)
    end
    return love.graphics.newImage((self.mod.path or "") .. "/" .. path)
  end)
  if not ok or not img then
    self.mod.log:error("could not create %s 3D texture atlas %s: %s",tostring(self.characterLabel),tostring(path),tostring(img))
    return nil
  end
  if img.setFilter then img:setFilter("linear","linear") end
  if img.setWrap then img:setWrap("clamp","clamp") end
  self.imageCache[path]=img
  return img
end

function Renderer:ensureImage()
  if self.failed then return false end
  local path=self:atlasFramePath()
  if self.image and self.currentAtlasPath==path then return true end
  local img=self:loadAtlasImage(path)
  if not img then
    self.failed=true
    return false
  end
  self.image=img
  self.currentAtlasPath=path
  if self.mesh and self.mesh.setTexture then self.mesh:setTexture(img) end
  return true
end

function Renderer:ensureGraphics()
  if self.mesh then return self:ensureImage() end
  if not self:ensureImage() then return false end
  if not (love and love.graphics and love.graphics.newMesh) then return false end

  local okMesh,mesh=pcall(love.graphics.newMesh,self.vertexRows,"triangles","dynamic")
  if not okMesh or not mesh then
    self.mod.log:error("could not create 3D character projected mesh: %s",tostring(mesh))
    self.failed=true
    return false
  end
  mesh:setTexture(self.image)
  self.mesh=mesh
  self.lastFacing=nil
  return true
end

function Renderer:ensureVoxelGraphics(Voxel3D)
  if self.voxelFailed or self.failed then return false end
  if not self:ensureImage() then return false end
  if not (love and love.graphics and love.graphics.newMesh) then return false end
  if type(Voxel3D)~="table" or type(Voxel3D.FORMAT)~="table" then return false end

  -- Dramatic Shape's mesh format is part of its shader contract.  Recreate
  -- the mesh if a hot reload swaps the FORMAT table out under us.
  if self.voxelMesh and self.voxelFormat==Voxel3D.FORMAT then return true end
  if self.voxelMesh and self.voxelMesh.release then pcall(self.voxelMesh.release,self.voxelMesh) end

  local okMesh,mesh=pcall(love.graphics.newMesh,Voxel3D.FORMAT,self.voxelRows,"triangles","dynamic")
  if not okMesh or not mesh then
    self.mod.log:error("could not create Dramatic Shape character mesh: %s",tostring(mesh))
    self.voxelFailed=true
    return false
  end
  self.voxelMesh=mesh
  self.voxelFormat=Voxel3D.FORMAT
  -- Preserve the original triangle sequence while drawing the compacted
  -- vertex buffer. Dramatic Shape still receives exactly the same triangles.
  if mesh.setVertexMap then pcall(mesh.setVertexMap,mesh,self.baseMap) end
  self.voxelUploadedKey=nil
  return true
end

local function wrap01(x)
  return x - math.floor(x)
end

local function catmull(p0,p1,p2,p3,t)
  local t2=t*t
  local t3=t2*t
  return 0.5*((2*p1) + (-p0+p2)*t
    + (2*p0-5*p1+4*p2-p3)*t2
    + (-p0+3*p1-3*p2+p3)*t3)
end

local function sampleCycle(values, phase)
  local n=#values
  local u=wrap01(phase)*n
  local i=math.floor(u)
  local t=u-i
  local function at(k)
    return values[((k % n)+n)%n + 1]
  end
  return catmull(at(i-1),at(i),at(i+1),at(i+2),t)
end

local function approachExp(current,target,rate,dt)
  if not dt or dt <= 0 then return target end
  local a=1-math.exp(-rate*dt)
  return current+(target-current)*a
end

-- Twelve evenly spaced key poses around one complete stride.  These are deliberately
-- not mirror-image sine waves: the contact, loading, passing, toe-off and swing
-- phases have different knee/ankle behavior, which is what keeps the walk from
-- reading like a robot pendulum.
local GAIT = {
  -- Twelve simulation-tuned poses across one complete stride.  The extra
  -- poses give contact, loading, mid-stance, heel-rise, toe-off, early swing,
  -- mid-swing, late swing and pre-contact their own timing instead of forcing
  -- several biomechanically different moments into the same key.
  thigh = {-18,-13, -5,  4, 12, 18, 20, 15,  6, -5,-14,-19 },
  knee  = { 12, 20, 15, 11, 15, 30, 56, 82, 72, 46, 25, 15 },
  foot  = {  1, -1, -3, -5, -8,-11, -8,  7,  6,  4,  2,  1 },

  -- Relaxed light-jog arm pump.  The shoulder leads, then the elbow and wrist
  -- follow through.  The amplitude is intentionally restrained so the hands
  -- stay near the torso instead of rising into a marching/Frankenstein pose.
  arm   = {-20,-17,-12, -6,  1,  9, 16, 17, 12,  5, -5,-14 },
  elbow = { 66, 65, 63, 61, 59, 58, 59, 61, 64, 67, 69, 68 },
  wristPitch = { 3, 3, 2, 1,-1,-2,-3,-2,-1, 1, 2, 3 },
  wristRoll  = {-2,-2,-1,-1, 1, 2, 2, 1, 1,-1,-2,-2 },
  wristYaw   = { 1, 1, 1, 0,-1,-1,-1,-1, 0, 1, 1, 1 },

  grip = { .14,.17,.22,.29,.37,.43,.39,.32,.25,.19,.15,.13 },
  toe  = { 0,0,0,1,4,8,10,6,2,1,0,0 },

  -- Head stays comparatively stable but breathes with the body's vertical
  -- rhythm.  Small nod/turn/roll curves stop it from feeling glued in place.
  headBob  = {-.03,-.08,-.10,-.05, .02, .07, .10, .05,-.02,-.07,-.08,-.04},
  headNod  = { .5, .3,  .0,-.3,-.6,-.8,-.6,-.2, .2, .5, .6, .5},
  headTurn = { .1, .2,  .3,.25, .1,  0,-.1,-.2,-.3,-.25,-.1,  0},
  headRoll = { .1, .2, .25, .1,-.1,-.2,-.25,-.1, .1, .2,.25, .1},

  bob   = { .06,-.08,-.18,-.12, .00, .11, .16, .08,-.04,-.14,-.12,-.02},
  twist = { 0,.22,.42,.50,.40,.18,0,-.22,-.42,-.50,-.40,-.18},
}

local JUMP = {
  -- 11 non-looping poses.  The launch is quick, the tuck peaks just after
  -- takeoff, and the legs extend before contact so landing does not look like
  -- the character simply drops out of a crouch.
  crouch = {0.00,0.55,1.00,0.52,0.16,0.05,0.04,0.12,0.34,0.62,0.00},
  lean   = {0.00,0.22,0.48,0.68,0.78,0.70,0.54,0.38,0.22,0.08,0.00},

  -- Slightly asymmetric legs make the jump feel athletic instead of like a
  -- perfectly mirrored squat.  Both feet still extend before landing.
  lThigh = {-3,-8,-18,-27,-31,-27,-20,-13,-7,-3,0},
  rThigh = { 3, 6, 14, 22, 26, 21, 13,  5,-4,-3,0},
  lKnee  = {14,22,38,58,66,58,43,30,23,17,12},
  rKnee  = {13,20,36,62,78,70,50,32,24,17,12},
  lFoot  = { 0,-1,-3,-4,-2, 0, 2, 4, 3, 1,0},
  rFoot  = { 0,-2,-4,-5,-3, 0, 3, 5, 3, 1,0},
  lToe   = { 0, 1, 3, 5, 4, 2, 1, 0, 0, 0,0},
  rToe   = { 0, 2, 4, 6, 5, 2, 1, 0, 0, 0,0},

  -- Arms swing slightly backward on compression, then come forward/out for
  -- balance and settle before the feet touch down.  Keep them below shoulder
  -- height so the jump never turns into the old Frankenstein-arm silhouette.
  lArm   = {-3,-8,-13,-15,-10,-2, 7,11, 8, 3,0},
  rArm   = { 3, 7, 11, 13,  8, 1,-6,-9,-7,-3,0},
  lElbow = {28,34,42,50,56,54,48,42,35,28,18},
  rElbow = {27,33,41,49,54,52,46,40,34,27,18},
  wrist  = { 0, 1, 3, 4, 5, 3, 1,-1,-2,-1,0},
  headNod= { 0,-.5,-1.2,-1.8,-1.5,-.8,0,.6,1.0,.5,0},
}

local function sampleJump(values,t)
  if t <= 0 then return values[1] end
  if t >= 1 then return values[#values] end
  local n=#values
  local u=t*(n-1)
  local i=math.floor(u)+1
  local f=u-math.floor(u)
  -- Smoothstep interpolation avoids visible corners between the ledge-hop poses.
  f=f*f*(3-2*f)
  return values[i] + (values[i+1]-values[i])*f
end

local function engineHopProgress(player)
  local frames=player and tonumber(player.hopFrames)
  if not frames or frames <= 0 then return nil end
  local total=tonumber(player.hopTotal) or 32
  if total <= 0 then total=32 end
  local t=1-frames/total
  if t < 0 then t=0 elseif t > 1 then t=1 end
  return t
end

local function manualJumpProgress(player)
  local frames=player and tonumber(player.red3dManualJumpFrames)
  if not frames or frames <= 0 then return nil end
  local total=tonumber(player.red3dManualJumpTotal) or CONFIG.manualJumpFrames
  if total <= 0 then total=CONFIG.manualJumpFrames end
  local t=1-frames/total
  if t < 0 then t=0 elseif t > 1 then t=1 end
  return t
end

local function jumpProgress(player)
  return engineHopProgress(player) or manualJumpProgress(player)
end

local function manualJumpLift(player)
  local t=manualJumpProgress(player)
  if not t then return 0 end
  -- A slightly softened sine arc: quick launch/landing, broad readable apex.
  local s=math.sin(math.pi*t)
  return CONFIG.manualJumpHeight * (s ^ 0.90)
end

local function shootProgress(player)
  local frames=player and tonumber(player.red3dShootFrames)
  if not frames or frames <= 0 then return nil end
  local total=tonumber(player.red3dShootTotal) or CONFIG.cjShootFrames
  if total <= 0 then total=CONFIG.cjShootFrames end
  local t=1-frames/total
  if t<0 then t=0 elseif t>1 then t=1 end
  return t
end

local function adsBoneDelta(data,bone,amount)
  if data.runtimeProfile~="CJ" or amount<=0 then return nil end
  local A=data.animBone
  local a=math.max(0,math.min(1,amount))
  if bone==A.Spine1 then
    return compose(rotX(math.rad(-3.0*a)),rotY(math.rad(-4.0*a)))
  elseif bone==A.RShoulder then
    return compose(rotY(math.rad(-2.0*a)),rotZ(math.rad(-1.5*a)))
  elseif bone==A.RArm then
    local rest=rotZ(math.rad(data.runtimeArmRest or 90))
    -- Proper third-person pistol extension: arm reaches forward from the
    -- shoulder while keeping a soft elbow instead of tucking into the torso.
    return compose(rest,compose(rotY(math.rad(-52*a)),rotX(math.rad(-4*a))))
  elseif bone==A.RForeArm then
    return rotY(math.rad(10*a))
  elseif bone==A.RHand then
    return compose3(rotX(math.rad(-6*a)),rotY(math.rad(4*a)),rotZ(math.rad(-17*a)))
  elseif bone==A.LArm then
    local rest=rotZ(math.rad(-(data.runtimeArmRest or 90)))
    return compose(rest,rotY(math.rad(-24*a)))
  elseif bone==A.LForeArm then
    return rotY(math.rad(-42*a))
  elseif bone==A.LHand then
    return compose3(rotX(math.rad(5*a)),rotY(math.rad(-4*a)),rotZ(math.rad(8*a)))
  elseif bone==A.Head then
    return compose(rotX(math.rad(-1.0*a)),rotY(math.rad(-3.0*a)))
  end
  return nil
end

local function shootBoneDelta(data,bone,t)
  if data.runtimeProfile~="CJ" then return nil end
  local A=data.animBone
  -- quick raise, sharp recoil around 35%, then settle while still aimed.
  local aim=math.min(1,t/0.24)
  aim=aim*aim*(3-2*aim)
  local recoil=math.exp(-((t-0.34)/0.11)^2)
  if bone==A.Spine1 then
    return compose(rotX(math.rad(-2.5*aim)),rotY(math.rad(-3.0*aim)))
  elseif bone==A.RShoulder then
    -- CJ's real GTA weights already carry shoulder deformation, so keep this
    -- joint quiet and aim mainly from the upper arm/elbow chain.
    return compose(rotY(math.rad(-1.5*aim)),rotZ(math.rad(-1.0*aim)))
  elseif bone==A.RArm then
    local rest=rotZ(math.rad(data.runtimeArmRest or 90))
    return compose(rest,compose(rotY(math.rad(-52*aim + 3.0*recoil)),rotX(math.rad(-4*aim))))
  elseif bone==A.RForeArm then
    return rotY(math.rad(10*aim + 5*recoil))
  elseif bone==A.RHand then
    return compose3(rotX(math.rad(-6*aim - 3.5*recoil)),rotY(math.rad(4*aim)),rotZ(math.rad(-17*aim)))
  elseif bone==A.LArm then
    local rest=rotZ(math.rad(-(data.runtimeArmRest or 90)))
    return compose(rest,rotY(math.rad(-7*aim)))
  elseif bone==A.LForeArm then
    return rotY(math.rad(-20*aim))
  elseif bone==A.Head then
    return rotY(math.rad(-2.5*aim))
  end
  return nil
end


local function sampleEmbeddedClip(clip,n,bone,phase)
  if not clip or not n or n<2 then return nil end
  phase=wrap01(phase or 0)
  -- Mixamo clips include a duplicate closing key. Sample n-1 intervals so
  -- wrapping from 1 -> 0 is seamless rather than pausing on the last frame.
  local u=phase*(n-1)
  local f0=math.floor(u)
  if f0>=n-1 then f0=n-2; u=n-1 end
  local f1=f0+1
  local a=u-f0
  local out={}
  local b0=((bone-1)*n+f0)*16
  local b1=((bone-1)*n+f1)*16
  for k=1,16 do
    local x0=clip[b0+k]
    local x1=clip[b1+k]
    out[k]=x0+(x1-x0)*a
  end
  return out
end

local function blend16(a,b,t)
  if not a then return b end
  if not b then return a end
  if t<=0 then return a end
  if t>=1 then return b end
  local out={}
  for k=1,16 do out[k]=a[k]+(b[k]-a[k])*t end
  return out
end

local function ashIdleDelta(data,bone)
  if data.idleDelta and data.idleFrameCount and data.idleFrameCount>1 then
    return sampleEmbeddedClip(data.idleDelta,data.idleFrameCount,bone,data.runtimeAshIdlePhase or 0)
  end
  local idle=data.runIdleDelta
  if not idle then return nil end
  local out={}; local base=(bone-1)*16
  for k=1,16 do out[k]=idle[base+k] end
  return out
end

local function ashEmbeddedDelta(data,bone,phase,blend)
  local run=sampleEmbeddedClip(data.runDelta,data.runFrameCount,bone,phase)
  local idle=ashIdleDelta(data,bone)
  if not run then return idle end
  blend=blend or 0
  if blend<0 then blend=0 elseif blend>1 then blend=1 end
  -- Smoothstep gives a soft idle -> run and run -> idle transition instead of
  -- linearly snapping the Mixamo limbs through the middle of the blend.
  blend=blend*blend*(3-2*blend)
  return blend16(idle,run,blend)
end

local function ashJumpDelta(data,bone,t,phase,motionBlend)
  local base=ashEmbeddedDelta(data,bone,phase,motionBlend or 0)
  if not base then return nil end
  local A=data.animBone or {}
  local e=math.sin(math.pi*math.max(0,math.min(1,t or 0)))
  e=e^0.78
  local add=nil
  -- Custom Ash jump pose layered over whichever idle/run pose was active at
  -- takeoff.  The envelope is zero at both ends, so takeoff and landing blend
  -- back into the imported clips without a visible pose pop.
  if bone==A.Spine1 then add=rotX(math.rad(-8.0*e))
  elseif bone==A.Spine2 then add=rotX(math.rad(-4.0*e))
  elseif bone==A.Spine3 then add=rotX(math.rad(-2.0*e))
  elseif bone==A.Neck then add=rotX(math.rad(3.0*e))
  elseif bone==A.Head then add=rotX(math.rad(2.5*e))
  elseif bone==A.LArm then add=compose3(rotX(math.rad(-7.0*e)),rotY(math.rad(-10.0*e)),rotZ(math.rad(-4.0*e)))
  elseif bone==A.RArm then add=compose3(rotX(math.rad(-7.0*e)),rotY(math.rad(10.0*e)),rotZ(math.rad(4.0*e)))
  elseif bone==A.LForeArm then add=rotZ(math.rad(22.0*e))
  elseif bone==A.RForeArm then add=rotZ(math.rad(-22.0*e))
  elseif bone==A.LThigh then add=rotX(math.rad(27.0*e))
  elseif bone==A.RThigh then add=rotX(math.rad(21.0*e))
  elseif bone==A.LLeg then add=rotX(math.rad(-46.0*e))
  elseif bone==A.RLeg then add=rotX(math.rad(-54.0*e))
  elseif bone==A.LFoot then add=rotX(math.rad(12.0*e))
  elseif bone==A.RFoot then add=rotX(math.rad(15.0*e))
  elseif bone==A.LToe then add=rotX(math.rad(5.0*e))
  elseif bone==A.RToe then add=rotX(math.rad(6.0*e))
  end
  if add then return compose(base,add) end
  return base
end

local function aangIdleDelta(data,bone)
  if data.idleDelta and data.idleFrameCount and data.idleFrameCount>1 then
    return sampleEmbeddedClip(data.idleDelta,data.idleFrameCount,bone,data.runtimeAangIdlePhase or 0)
  end
  return nil
end

local function aangEmbeddedDelta(data,bone,phase,blend)
  local idle=aangIdleDelta(data,bone)
  local run=sampleEmbeddedClip(data.runDelta,data.runFrameCount,bone,phase)
  if not run then return idle end
  blend=blend or 0
  if blend<0 then blend=0 elseif blend>1 then blend=1 end
  blend=blend*blend*(3-2*blend)
  return blend16(idle,run,blend)
end

local function aangJumpDelta(data,bone,t,phase,motionBlend)
  local move=motionBlend or 0
  if move<0 then move=0 elseif move>1 then move=1 end
  local base=aangEmbeddedDelta(data,bone,phase,move)
  local jump=sampleEmbeddedClip(data.jumpDelta,data.jumpFrameCount,bone,math.max(0,math.min(1,t or 0)))
  if not jump then return base end
  local A=data.animBone or {}
  local tt=math.max(0,math.min(1,t or 0))
  local function smooth(x) if x<=0 then return 0 elseif x>=1 then return 1 end return x*x*(3-2*x) end
  -- Keep some Running locomotion underneath the authored Jump clip so takeoff
  -- and landing connect to movement instead of snapping into a disconnected pose.
  local w=math.min(smooth(tt/0.10),smooth((1-tt)/0.18))
  local carry=0.0
  if bone==A.Hips then
    carry=0.56
  elseif bone==A.LThigh or bone==A.RThigh or bone==A.LLeg or bone==A.RLeg
      or bone==A.LFoot or bone==A.RFoot or bone==A.LToe or bone==A.RToe then
    carry=0.42
  elseif bone==A.Spine1 or bone==A.Spine2 or bone==A.Spine3 then
    carry=0.14
  elseif bone==A.LArm or bone==A.RArm or bone==A.LForeArm or bone==A.RForeArm
      or bone==A.LHand or bone==A.RHand then
    carry=0.08
  end
  return blend16(base,jump,w*(1.0-carry*move))
end

local function cjIdleDelta(data,bone)
  if data.idleDelta and data.idleFrameCount and data.idleFrameCount>1 then
    return sampleEmbeddedClip(data.idleDelta,data.idleFrameCount,bone,data.runtimeCJIdlePhase or 0)
  end
  return nil
end

local function cjEmbeddedDelta(data,bone,phase,blend)
  local idle=cjIdleDelta(data,bone)
  local run=sampleEmbeddedClip(data.runDelta,data.runFrameCount,bone,phase)
  if not run then return idle end
  blend=blend or 0
  if blend<0 then blend=0 elseif blend>1 then blend=1 end
  blend=blend*blend*(3-2*blend)
  return blend16(idle,run,blend)
end

local function cjJumpDelta(data,bone,t,phase,motionBlend)
  local move=motionBlend or 0
  if move<0 then move=0 elseif move>1 then move=1 end
  local base=cjEmbeddedDelta(data,bone,phase,move)
  local jump=sampleEmbeddedClip(data.jumpDelta,data.jumpFrameCount,bone,math.max(0,math.min(1,t or 0)))
  if not jump then return base end
  local A=data.animBone or {}
  local tt=math.max(0,math.min(1,t or 0))
  local function smooth(x) if x<=0 then return 0 elseif x>=1 then return 1 end return x*x*(3-2*x) end
  local w=math.min(smooth(tt/0.10),smooth((1-tt)/0.20))
  local carry=0.0
  if bone==A.Hips then
    carry=0.58
  elseif bone==A.LThigh or bone==A.RThigh or bone==A.LLeg or bone==A.RLeg
      or bone==A.LFoot or bone==A.RFoot or bone==A.LToe or bone==A.RToe then
    carry=0.44
  elseif bone==A.Spine1 or bone==A.Spine2 or bone==A.Spine3 then
    carry=0.14
  elseif bone==A.LArm or bone==A.RArm or bone==A.LForeArm or bone==A.RForeArm
      or bone==A.LHand or bone==A.RHand then
    carry=0.08
  end
  return blend16(base,jump,w*(1.0-carry*move))
end

local function yamiIdleDelta(data,bone)
  if data.idleDelta and data.idleFrameCount and data.idleFrameCount>1 then
    return sampleEmbeddedClip(data.idleDelta,data.idleFrameCount,bone,data.runtimeYamiIdlePhase or 0)
  end
  return nil
end

local function yamiEmbeddedDelta(data,bone,phase,blend)
  local idle=yamiIdleDelta(data,bone)
  local run=sampleEmbeddedClip(data.runDelta,data.runFrameCount,bone,phase)
  if not run then return idle end
  blend=blend or 0
  if blend<0 then blend=0 elseif blend>1 then blend=1 end
  blend=blend*blend*(3-2*blend)
  return blend16(idle,run,blend)
end

local function yamiJumpDelta(data,bone,t,phase,motionBlend)
  local move=motionBlend or 0
  if move<0 then move=0 elseif move>1 then move=1 end
  local base=yamiEmbeddedDelta(data,bone,phase,move)
  local jump=sampleEmbeddedClip(data.jumpDelta,data.jumpFrameCount,bone,math.max(0,math.min(1,t or 0)))
  if not jump then return base end
  local A=data.animBone or {}
  local tt=math.max(0,math.min(1,t or 0))
  local function smooth(x) if x<=0 then return 0 elseif x>=1 then return 1 end return x*x*(3-2*x) end
  local w=math.min(smooth(tt/0.10),smooth((1-tt)/0.20))
  local carry=0.0
  if bone==A.Hips then
    carry=0.58
  elseif bone==A.LThigh or bone==A.RThigh or bone==A.LLeg or bone==A.RLeg
      or bone==A.LFoot or bone==A.RFoot or bone==A.LToe or bone==A.RToe then
    carry=0.44
  elseif bone==A.Spine1 or bone==A.Spine2 or bone==A.Spine3 then
    carry=0.14
  elseif bone==A.LArm or bone==A.RArm or bone==A.LForeArm or bone==A.RForeArm
      or bone==A.LHand or bone==A.RHand then
    carry=0.08
  end
  return blend16(base,jump,w*(1.0-carry*move))
end

local function belleLocomotionDelta(data,bone,phase,motionBlend)
  local idle=aangIdleDelta(data,bone)
  local walk=nil
  if data.walkDelta and data.walkFrameCount and data.walkFrameCount>1 then
    walk=sampleEmbeddedClip(data.walkDelta,data.walkFrameCount,bone,phase)
  end
  local run=nil
  if data.runDelta and data.runFrameCount and data.runFrameCount>1 then
    run=sampleEmbeddedClip(data.runDelta,data.runFrameCount,bone,phase)
  end
  local locomotion=walk or run or idle
  if walk and run then
    local rb=tonumber(data.runtimeBelleRunBlend) or 0
    if rb<0 then rb=0 elseif rb>1 then rb=1 end
    rb=rb*rb*(3-2*rb)
    locomotion=blend16(walk,run,rb)
  end
  local move=motionBlend or 0
  if move<0 then move=0 elseif move>1 then move=1 end
  move=move*move*(3-2*move)
  return blend16(idle,locomotion,move)
end

local function belleJumpDelta(data,bone,t,phase,motionBlend)
  local move=motionBlend or 0
  if move<0 then move=0 elseif move>1 then move=1 end
  local base=belleLocomotionDelta(data,bone,phase,move)
  local tt=math.max(0,math.min(1,t or 0))
  -- BelleStarmon's supplied jump is almost 1.9 seconds long, while the game's
  -- hop window is much shorter. Sampling the whole source clip made the pose
  -- race through takeoff/descent and look jittery. Use a narrower authored
  -- section and a quintic ease so descent/landing progresses more smoothly.
  local eased=tt*tt*tt*(tt*(tt*6-15)+10)
  local sourceT=0.10 + 0.72*eased
  local jump=sampleEmbeddedClip(data.jumpDelta,data.jumpFrameCount,bone,sourceT)
  if not jump then return base end
  local A=data.animBone or {}
  local function smooth(x) if x<=0 then return 0 elseif x>=1 then return 1 end return x*x*(3-2*x) end
  local w=math.min(smooth(tt/0.14),smooth((1-tt)/0.26))
  local carry=0.0
  if bone==A.Hips then
    carry=0.58
  elseif bone==A.LThigh or bone==A.RThigh or bone==A.LLeg or bone==A.RLeg
      or bone==A.LFoot or bone==A.RFoot or bone==A.LToe or bone==A.RToe then
    carry=0.44
  elseif bone==A.Spine1 or bone==A.Spine2 or bone==A.Spine3 then
    carry=0.16
  elseif bone==A.LArm or bone==A.RArm or bone==A.LForeArm or bone==A.RForeArm
      or bone==A.LHand or bone==A.RHand then
    carry=0.10
  end
  return blend16(base,jump,w*(1.0-carry*move))
end

local function beelIdleDelta(data,bone)
  if data.idleDelta and data.idleFrameCount and data.idleFrameCount>1 then
    return sampleEmbeddedClip(data.idleDelta,data.idleFrameCount,bone,data.runtimeBeelIdlePhase or 0)
  end
  return nil
end

local function beelEmbeddedDelta(data,bone,phase,blend)
  local idle=beelIdleDelta(data,bone)
  local run=sampleEmbeddedClip(data.runDelta,data.runFrameCount,bone,phase)
  if not run then return idle end
  blend=blend or 0
  if blend<0 then blend=0 elseif blend>1 then blend=1 end
  blend=blend*blend*(3-2*blend)
  return blend16(idle,run,blend)
end

local function beelBreastDelta(data,bone,phase,motionBlend,jumpT)
  local A=data.animBone or {}
  if bone~=A.LBreast and bone~=A.RBreast then return nil end
  local side=(bone==A.LBreast) and -1 or 1
  local move=motionBlend or 0
  if move<0 then move=0 elseif move>1 then move=1 end
  local idlePhase=data.runtimeBeelIdlePhase or 0
  local idleWave=math.sin(idlePhase*math.pi*2)
  local runWave=math.sin((phase+0.06)*math.pi*4)
  local follow=math.sin((phase+0.17)*math.pi*4)
  -- x30 chest secondary motion. This is 1.5x the v2.8.50 x20 response.
  -- Idle remains restrained relative to running/jumping so the exaggerated effect
  -- is most visible during locomotion without destabilizing the standing pose.
  local y=0.021*idleWave*(1-move) + 0.300*runWave*move
  local z=0.015*idleWave*(1-move) + 0.132*follow*move
  local x=side*(0.018*follow*move)
  local pitch=13.2*runWave*move
  if jumpT then
    local t=math.max(0,math.min(1,jumpT))
    local pulse=math.sin(t*math.pi*3.0)*(1.0-t*0.30)
    y=y+0.384*pulse
    z=z+0.156*math.sin((t+0.08)*math.pi*3.0)*(1.0-t*0.25)
    x=x+side*0.024*pulse
    pitch=pitch+18.0*pulse
  end
  return compose(translate16(x,y,z),rotX(math.rad(pitch)))
end

local function narutoIdleDelta(data,bone)
  if data.idleDelta and data.idleFrameCount and data.idleFrameCount>1 then
    return sampleEmbeddedClip(data.idleDelta,data.idleFrameCount,bone,data.runtimeNarutoIdlePhase or 0)
  end
  return nil
end

local function narutoEmbeddedDelta(data,bone,phase,blend)
  local idle=narutoIdleDelta(data,bone)
  local run=sampleEmbeddedClip(data.runDelta,data.runFrameCount,bone,phase)
  if not run then return idle end
  blend=blend or 0
  if blend<0 then blend=0 elseif blend>1 then blend=1 end
  blend=blend*blend*(3-2*blend)
  return blend16(idle,run,blend)
end

local function narutoJumpDelta(data,bone,t,phase,motionBlend)
  local move=motionBlend or 0
  if move<0 then move=0 elseif move>1 then move=1 end
  local base=narutoEmbeddedDelta(data,bone,phase,move)
  local jump=sampleEmbeddedClip(data.jumpDelta,data.jumpFrameCount,bone,math.max(0,math.min(1,t or 0)))
  if not jump then return base end
  local A=data.animBone or {}
  local tt=math.max(0,math.min(1,t or 0))
  local function smooth(x) if x<=0 then return 0 elseif x>=1 then return 1 end return x*x*(3-2*x) end
  -- Blend the authored jump over the running gait instead of freezing the legs
  -- at takeoff. The hips/legs retain enough run locomotion to make the jump
  -- connect naturally to the supplied Run clip while the upper body follows
  -- the authored Jumping clip more strongly.
  local w=math.min(smooth(tt/0.10),smooth((1-tt)/0.20))
  local carry=0.0
  if bone==A.Hips then
    carry=0.58
  elseif bone==A.LThigh or bone==A.RThigh or bone==A.LLeg or bone==A.RLeg
      or bone==A.LFoot or bone==A.RFoot or bone==A.LToe or bone==A.RToe then
    carry=0.44
  elseif bone==A.Spine1 or bone==A.Spine2 or bone==A.Spine3 then
    carry=0.14
  elseif bone==A.LArm or bone==A.RArm or bone==A.LForeArm or bone==A.RForeArm
      or bone==A.LHand or bone==A.RHand then
    carry=0.08
  end
  return blend16(base,jump,w*(1.0-carry*move))
end

local function beelJumpDelta(data,bone,t,phase,motionBlend)
  local move=motionBlend or 0
  if move<0 then move=0 elseif move>1 then move=1 end
  local base=beelEmbeddedDelta(data,bone,phase,move)
  local jump=sampleEmbeddedClip(data.jumpDelta,data.jumpFrameCount,bone,math.max(0,math.min(1,t or 0)))
  local A=data.animBone or {}
  if bone==A.LBreast or bone==A.RBreast then
    return beelBreastDelta(data,bone,phase,move,t)
  end
  if not jump then return base end
  local tt=math.max(0,math.min(1,t or 0))
  local function smooth(x) if x<=0 then return 0 elseif x>=1 then return 1 end return x*x*(3-2*x) end
  local fadeIn=smooth(tt/0.10)
  local fadeOut=smooth((1-tt)/0.22)
  local w=math.min(fadeIn,fadeOut)

  -- Locomotion-aware jump blend.  While moving, keep the Fast Run phase alive
  -- underneath the authored jump instead of replacing it. Hips carry the most
  -- run motion, legs keep half, and the upper body takes most of the jump pose.
  local carry=0.0
  if bone==A.Hips then
    carry=0.65
  elseif bone==A.LThigh or bone==A.RThigh or bone==A.LLeg or bone==A.RLeg
      or bone==A.LFoot or bone==A.RFoot or bone==A.LToe or bone==A.RToe then
    carry=0.50
  elseif bone==A.Spine1 or bone==A.Spine2 or bone==A.Spine3 then
    carry=0.20
  elseif bone==A.LArm or bone==A.RArm or bone==A.LForeArm or bone==A.RForeArm
      or bone==A.LHand or bone==A.RHand then
    carry=0.15
  end
  local jumpWeight=w*(1.0-carry*move)
  return blend16(base,jump,jumpWeight)
end

local function jumpBoneDelta(data,bone,t)
  local A=data.animBone
  local crouch=sampleJump(JUMP.crouch,t)
  local lean=sampleJump(JUMP.lean,t)
  if data.runtimeProfile=="BEELSTARMON" then
    local A=data.animBone
    -- Beelstarmon's world-space jump already raises the character.  The stock
    -- jump pose also pushed Waist/Hips downward, which made this tall static-FBX
    -- conversion visibly sink into the floor.  Keep the root chain centered and
    -- put the jump compression into the limbs instead.
    if bone==A.Waist or bone==A.Hips then
      return nil
    elseif bone==A.Spine1 then
      return rotX(math.rad(CONFIG.jumpLeanDeg*lean*0.22))
    elseif bone==A.Spine2 then
      return rotX(math.rad(CONFIG.jumpLeanDeg*lean*0.10))
    elseif bone==A.Spine3 then
      return rotX(math.rad(CONFIG.jumpLeanDeg*lean*0.05))
    elseif bone==A.Neck then
      return rotX(math.rad(sampleJump(JUMP.headNod,t)*0.12))
    elseif bone==A.Head then
      return rotX(math.rad(sampleJump(JUMP.headNod,t)*0.20))
    elseif bone==A.LArm then
      return rotX(math.rad(sampleJump(JUMP.lArm,t)*0.34))
    elseif bone==A.RArm then
      return rotX(math.rad(-sampleJump(JUMP.rArm,t)*0.34))
    elseif bone==A.LForeArm then
      return rotX(math.rad(-sampleJump(JUMP.lElbow,t)*0.30))
    elseif bone==A.RForeArm then
      return rotX(math.rad(sampleJump(JUMP.rElbow,t)*0.30))
    elseif bone==A.LHand then
      local w=sampleJump(JUMP.wrist,t)
      return compose(rotX(math.rad(w*0.16)),rotZ(math.rad(-w*0.10)))
    elseif bone==A.RHand then
      local w=sampleJump(JUMP.wrist,t)
      return compose(rotX(math.rad(-w*0.16)),rotZ(math.rad(w*0.10)))
    elseif bone==A.LThigh then
      return rotX(math.rad(sampleJump(JUMP.lThigh,t)*0.42))
    elseif bone==A.RThigh then
      return rotX(math.rad(sampleJump(JUMP.rThigh,t)*0.42))
    elseif bone==A.LKnee then
      return rotX(math.rad(6.0 + sampleJump(JUMP.lKnee,t)*0.68))
    elseif bone==A.RKnee then
      return rotX(math.rad(6.0 + sampleJump(JUMP.rKnee,t)*0.68))
    elseif bone==A.LLeg then
      return rotX(math.rad(sampleJump(JUMP.lKnee,t)*0.10))
    elseif bone==A.RLeg then
      return rotX(math.rad(sampleJump(JUMP.rKnee,t)*0.10))
    elseif bone==A.LFoot then
      return rotX(math.rad(-4.0 + sampleJump(JUMP.lFoot,t)*0.54))
    elseif bone==A.RFoot then
      return rotX(math.rad(-4.0 + sampleJump(JUMP.rFoot,t)*0.54))
    elseif bone==A.LToe then
      return rotX(math.rad(2.0 + sampleJump(JUMP.lToe,t)*0.34))
    elseif bone==A.RToe then
      return rotX(math.rad(2.0 + sampleJump(JUMP.rToe,t)*0.34))
    elseif bone==A.LBreast or bone==A.RBreast then
      -- Strong secondary bounce on takeoff/landing: five times the baseline.
      local pulse=math.sin(t*math.pi*3.0)*(1.0-t*0.35)
      local side=(bone==A.LBreast) and -1 or 1
      return compose(translate16(side*0.004*pulse,0.062*pulse,0.024*pulse),rotX(math.rad(2.8*pulse)))
    elseif bone==A.HairRoot then
      -- Root hair follows the head quickly; the tip below lags much farther.
      local pulse=math.sin(t*math.pi*2.0)*(1.0-t*0.22)
      return compose(translate16(0,0,0.010*pulse),compose3(rotX(math.rad(-8.0*pulse)),rotY(math.rad(2.5*pulse)),rotZ(math.rad(3.5*pulse))))
    elseif bone==A.HairTip then
      local pulse=math.sin((t+0.10)*math.pi*2.0)*(1.0-t*0.16)
      return compose(translate16(0,0,0.028*pulse),compose3(rotX(math.rad(-18.0*pulse)),rotY(math.rad(5.0*pulse)),rotZ(math.rad(8.5*pulse))))
    elseif bone==A.CapeTop or bone==A.CapeMid or bone==A.CapeBottom or
        bone==A.CapeLTop or bone==A.CapeLMid or bone==A.CapeLTip or
        bone==A.CapeRTop or bone==A.CapeRMid or bone==A.CapeRTip then
      local C=data.runtimeCloth
      local node=nil
      if C then
        if bone==A.CapeTop then node=C.ct elseif bone==A.CapeMid then node=C.cm elseif bone==A.CapeBottom then node=C.cb
        elseif bone==A.CapeLTop then node=C.lt elseif bone==A.CapeLMid then node=C.lm elseif bone==A.CapeLTip then node=C.lb
        elseif bone==A.CapeRTop then node=C.rt elseif bone==A.CapeRMid then node=C.rm elseif bone==A.CapeRTip then node=C.rb end
      end
      local pulse=math.sin((t+0.08)*math.pi*2.0)*(1.0-t*0.16)
      local tip=(bone==A.CapeBottom or bone==A.CapeLTip or bone==A.CapeRTip)
      local mid=(bone==A.CapeMid or bone==A.CapeLMid or bone==A.CapeRMid)
      local kick=tip and -16.0*pulse or (mid and -10.0*pulse or -5.0*pulse)
      local py=(node and node.p or 0)+kick
      local yy=(node and node.y or 0)+(tip and 3.2*pulse or (mid and 1.8*pulse or 0.8*pulse))
      local tz=tip and 0.040*pulse or (mid and 0.022*pulse or 0.008*pulse)
      return compose(translate16(0,0,tz),compose(rotX(math.rad(py)),rotZ(math.rad(yy))))
    end
  end
  -- SHREK_RED jump uses the dedicated rig-axis branches below.
  if bone==A.Waist then
    return compose(translate16(0,-CONFIG.jumpCrouchUnits*crouch*0.45,0),
                   rotY(math.rad(CONFIG.jumpLeanDeg*lean*0.35)))
  elseif bone==A.Spine1 then
    if data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="AANG" or data.runtimeProfile=="CJ" or data.runtimeProfile=="SHREK_RED" then
      return rotX(math.rad(CONFIG.jumpLeanDeg*lean*0.65))
    end
    return rotY(math.rad(CONFIG.jumpLeanDeg*lean))
  elseif bone==A.Spine2 then
    return rotY(math.rad(CONFIG.jumpLeanDeg*lean*0.22))
  elseif bone==A.Neck then
    return rotX(math.rad(sampleJump(JUMP.headNod,t)*0.35))
  elseif bone==A.Head then
    return rotX(math.rad(sampleJump(JUMP.headNod,t)))
  elseif bone==A.Hips then
    return translate16(0,-CONFIG.jumpCrouchUnits*crouch,0)
  elseif bone==A.LArm then
    if data.runtimeProfile=="NARUTO" then
      local rest=rotAxis(0.11208,-0.11625,0.98688,math.rad(-70))
      local swing=rotAxis(-0.25845,0.95554,0.14191,math.rad(sampleJump(JUMP.lArm,t)*0.42))
      return compose(rest,swing)
    end
    if data.runtimeProfile=="YUGI" then
      return compose(rotX(math.rad(sampleJump(JUMP.lArm,t)*0.45)),rotZ(math.rad(-(data.runtimeArmRest or CONFIG.armRestDeg))))
    elseif data.runtimeProfile=="AANG" then
      local rest=rotZ(math.rad(data.runtimeArmRest or 70))
      return compose(rotY(math.rad(sampleJump(JUMP.lArm,t)*0.38)),rest)
    elseif data.runtimeProfile=="CJ" then
      local rest=rotZ(math.rad(-(data.runtimeArmRest or 90)))
      return compose(rest,rotY(math.rad(8 + sampleJump(JUMP.lArm,t)*0.18)))
    elseif data.runtimeProfile=="CLOUD" then
      return rotZ(math.rad(sampleJump(JUMP.lArm,t)*0.34))
    elseif data.runtimeProfile=="GENERIC" then
      local rest=rotZ(math.rad(-(data.runtimeArmRest or 0)))
      local swing=rotY(math.rad(sampleJump(JUMP.lArm,t)*0.42))
      return compose(rest,swing)
    elseif data.runtimeProfile=="SHREK_RED" then
      return compose(rotX(math.rad(sampleJump(JUMP.lArm,t)*0.30)), rotZ(math.rad(-42)))
    end
    return compose(rotZ(math.rad(-(data.runtimeArmRest or CONFIG.armRestDeg))),rotY(math.rad(sampleJump(JUMP.lArm,t))))
  elseif bone==A.RArm then
    if data.runtimeProfile=="NARUTO" then
      local rest=rotAxis(0.12191,-0.07037,-0.99004,math.rad(70))
      local swing=rotAxis(0.35474,-0.92851,0.10968,math.rad(sampleJump(JUMP.rArm,t)*0.42))
      return compose(rest,swing)
    end
    if data.runtimeProfile=="YUGI" then
      return compose(rotX(math.rad(-sampleJump(JUMP.rArm,t)*0.45)),rotZ(math.rad(data.runtimeArmRest or CONFIG.armRestDeg)))
    elseif data.runtimeProfile=="AANG" then
      local rest=rotZ(math.rad(-(data.runtimeArmRest or 70)))
      return compose(rotY(math.rad(sampleJump(JUMP.rArm,t)*0.38)),rest)
    elseif data.runtimeProfile=="CJ" then
      local rest=rotZ(math.rad(data.runtimeArmRest or 90))
      return compose(rest,compose(rotY(math.rad(28 + sampleJump(JUMP.rArm,t)*0.12)),rotX(math.rad(-2))))
    elseif data.runtimeProfile=="CLOUD" then
      return rotZ(math.rad(sampleJump(JUMP.rArm,t)*0.34))
    elseif data.runtimeProfile=="GENERIC" then
      local rest=rotZ(math.rad(data.runtimeArmRest or 0))
      local swing=rotY(math.rad(sampleJump(JUMP.rArm,t)*0.42))
      return compose(rest,swing)
    elseif data.runtimeProfile=="SHREK_RED" then
      return compose(rotX(math.rad(-sampleJump(JUMP.rArm,t)*0.30)), rotZ(math.rad(42)))
    end
    return compose(rotZ(math.rad(data.runtimeArmRest or CONFIG.armRestDeg)),rotY(math.rad(sampleJump(JUMP.rArm,t))))
  elseif bone==A.LForeArm then
    local a=sampleJump(JUMP.lElbow,t)
    if data.runtimeProfile=="NARUTO" then return rotAxis(-0.25845,0.95554,0.14191,math.rad(-a*0.55)) end
    if data.runtimeProfile=="AANG" then return rotZ(math.rad(a*0.48)) end
    if data.runtimeProfile=="CJ" then return rotY(math.rad(-10-a*0.18)) end
    if data.runtimeProfile=="CLOUD" then return rotZ(math.rad(-a*0.30)) end
    if data.runtimeProfile=="GENERIC" then return rotX(math.rad(-a*0.42)) end
    if data.runtimeProfile=="SHREK_RED" then return compose(rotX(math.rad(-a*0.32)), rotZ(math.rad(-14))) end
    return rotY(math.rad(data.runtimeProfile=="YUGI" and -a*0.52 or -a))
  elseif bone==A.RForeArm then
    local a=sampleJump(JUMP.rElbow,t)
    if data.runtimeProfile=="NARUTO" then return rotAxis(0.35474,-0.92851,0.10968,math.rad(-a*0.55)) end
    if data.runtimeProfile=="AANG" then return rotZ(math.rad(-a*0.48)) end
    if data.runtimeProfile=="CJ" then return rotY(math.rad(52+a*0.10)) end
    if data.runtimeProfile=="CLOUD" then return rotZ(math.rad(a*0.30)) end
    if data.runtimeProfile=="GENERIC" then return rotX(math.rad(-a*0.42)) end
    if data.runtimeProfile=="SHREK_RED" then return compose(rotX(math.rad(a*0.32)), rotZ(math.rad(14))) end
    return rotY(math.rad(data.runtimeProfile=="YUGI" and a*0.52 or -a))
  elseif bone==A.LHand then
    local w=sampleJump(JUMP.wrist,t)
    return compose(rotX(math.rad(w*0.45)),rotZ(math.rad(w)))
  elseif bone==A.RHand then
    local w=sampleJump(JUMP.wrist,t)
    return compose(rotX(math.rad(-w*0.45)),rotZ(math.rad(-w)))
  elseif bone==A.LThigh then
    local a=math.rad(sampleJump(JUMP.lThigh,t))
    if data.runtimeProfile=="NARUTO" then return rotAxis(-0.2949,0.1239,-0.9474,a) end
    if data.runtimeProfile=="AANG" then return rotY(-a) end
    if data.runtimeProfile=="CLOUD" then return rotZ(a) end
    if data.runtimeProfile=="CJ" then return rotX(a*0.08) end
    return (data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="SHREK_RED") and rotX(a) or rotY(a)
  elseif bone==A.RThigh then
    local a=math.rad(sampleJump(JUMP.rThigh,t))
    if data.runtimeProfile=="NARUTO" then return rotAxis(0.3321,-0.1095,-0.9369,a) end
    if data.runtimeProfile=="AANG" then return rotY(-a) end
    if data.runtimeProfile=="CLOUD" then return rotZ(a) end
    if data.runtimeProfile=="CJ" then return rotX(a*0.08) end
    return (data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="SHREK_RED") and rotX(a) or rotY(a)
  elseif bone==A.LLeg then
    local a=math.rad(sampleJump(JUMP.lKnee,t))
    if data.runtimeProfile=="NARUTO" then return rotAxis(-0.2949,0.1239,-0.9474,a) end
    if data.runtimeProfile=="AANG" then return rotY(-a) end
    if data.runtimeProfile=="CLOUD" then return rotZ(a) end
    if data.runtimeProfile=="CJ" then return rotX(a*0.11) end
    return (data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="SHREK_RED") and rotX(a) or rotY(a)
  elseif bone==A.RLeg then
    local a=math.rad(sampleJump(JUMP.rKnee,t))
    if data.runtimeProfile=="NARUTO" then return rotAxis(0.3321,-0.1095,-0.9369,a) end
    if data.runtimeProfile=="AANG" then return rotY(-a) end
    if data.runtimeProfile=="CLOUD" then return rotZ(a) end
    if data.runtimeProfile=="CJ" then return rotX(a*0.11) end
    return (data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="SHREK_RED") and rotX(a) or rotY(a)
  elseif bone==A.LFoot then
    local a=math.rad(sampleJump(JUMP.lFoot,t))
    if data.runtimeProfile=="NARUTO" then return rotAxis(-0.0475,0.3446,0.9376,a) end
    if data.runtimeProfile=="AANG" then return rotY(-a) end
    if data.runtimeProfile=="CLOUD" then return rotZ(a) end
    if data.runtimeProfile=="CJ" then return rotX(a*0.20) end
    return (data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="SHREK_RED") and rotX(a) or rotY(a)
  elseif bone==A.RFoot then
    local a=math.rad(sampleJump(JUMP.rFoot,t))
    if data.runtimeProfile=="NARUTO" then return rotAxis(0.0349,-0.4342,0.9002,a) end
    if data.runtimeProfile=="AANG" then return rotY(-a) end
    if data.runtimeProfile=="CLOUD" then return rotZ(a) end
    if data.runtimeProfile=="CJ" then return rotX(a*0.20) end
    return (data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="SHREK_RED") and rotX(a) or rotY(a)
  elseif bone==A.LToe then
    local a=math.rad(sampleJump(JUMP.lToe,t))
    if data.runtimeProfile=="NARUTO" then return rotAxis(-0.0475,0.3446,0.9376,a) end
    if data.runtimeProfile=="AANG" then return rotY(-a) end
    if data.runtimeProfile=="CLOUD" then return rotZ(a) end
    if data.runtimeProfile=="CJ" then return rotX(a*0.08) end
    return (data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="SHREK_RED") and rotX(a) or rotY(a)
  elseif bone==A.RToe then
    local a=math.rad(sampleJump(JUMP.rToe,t))
    if data.runtimeProfile=="NARUTO" then return rotAxis(0.0349,-0.4342,0.9002,a) end
    if data.runtimeProfile=="AANG" then return rotY(-a) end
    if data.runtimeProfile=="CLOUD" then return rotZ(a) end
    return (data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="SHREK_RED") and rotX(a) or rotY(a)
  end
  return nil
end

local function boneDelta(data, bone, phaseRadians, walkSin, walkCos, bounce, walking, motionBlend)
  local A=data.animBone
  local blend=motionBlend
  if blend==nil then blend=walking and 1 or 0 end
  if blend < 0 then blend=0 elseif blend > 1 then blend=1 end

  local phase=wrap01(phaseRadians/(math.pi*2))
  local opposite=wrap01(phase+0.5)

  if data.runtimeProfile=="ASH" and data.runDelta then
    return ashEmbeddedDelta(data,bone,phase,blend)
  elseif data.runtimeCharacterId=="BELLESTARMON" and data.walkDelta and data.runDelta then
    return belleLocomotionDelta(data,bone,phase,blend)
  elseif data.runtimeProfile=="AANG_MIXAMO" and data.runDelta then
    return aangEmbeddedDelta(data,bone,phase,blend)
  elseif data.runtimeProfile=="CJ_FBX" and data.runDelta then
    return cjEmbeddedDelta(data,bone,phase,blend)
  elseif data.runtimeProfile=="YAMI_FBX" and data.runDelta then
    return yamiEmbeddedDelta(data,bone,phase,blend)
  elseif data.runtimeProfile=="NARUTO_MIXAMO" and data.runDelta then
    return narutoEmbeddedDelta(data,bone,phase,blend)
  elseif data.runtimeProfile=="BEELSTARMON_MIXAMO" and data.runDelta then
    local breast=beelBreastDelta(data,bone,phase,blend,nil)
    if breast then return breast end
    return beelEmbeddedDelta(data,bone,phase,blend)
  end

  local lThigh=sampleCycle(GAIT.thigh,phase)
  local rThigh=sampleCycle(GAIT.thigh,opposite)

  -- Distal joints lag the joint above them by a few percent of a cycle.  This
  -- creates follow-through: hip -> knee -> ankle -> toe, instead of every leg
  -- joint hitting its key at exactly the same instant.
  local lKnee=sampleCycle(GAIT.knee,wrap01(phase-0.024))
  local rKnee=sampleCycle(GAIT.knee,wrap01(opposite-0.024))
  local lFoot=sampleCycle(GAIT.foot,wrap01(phase-0.042))
  local rFoot=sampleCycle(GAIT.foot,wrap01(opposite-0.042))

  -- The same principle is used for the upper body: the shoulder/upper arm
  -- leads, then the elbow, then the wrist follows through a little later.
  local lArm=sampleCycle(GAIT.arm,wrap01(phase+0.500))
  local rArm=sampleCycle(GAIT.arm,wrap01(opposite+0.500))
  -- A positive phase offset advances a cyclic curve.  Previous builds called
  -- that a lag, but it actually made the elbow/wrist arrive *before* the
  -- shoulder.  Use negative offsets so motion genuinely travels outward.
  local lElbow=sampleCycle(GAIT.elbow,wrap01(phase+0.465))
  local rElbow=sampleCycle(GAIT.elbow,wrap01(opposite+0.460))
  local lWristPitch=sampleCycle(GAIT.wristPitch,wrap01(phase+0.420))
  local rWristPitch=sampleCycle(GAIT.wristPitch,wrap01(opposite+0.412))
  local lWristRoll=sampleCycle(GAIT.wristRoll,wrap01(phase+0.395))
  local rWristRoll=sampleCycle(GAIT.wristRoll,wrap01(opposite+0.388))
  local lWristYaw=sampleCycle(GAIT.wristYaw,wrap01(phase+0.438))
  local rWristYaw=sampleCycle(GAIT.wristYaw,wrap01(opposite+0.432))

  -- Tiny phase offsets per digit make the grip feel organic.  Pinky/ring
  -- close a fraction earlier, index/thumb a fraction later; the right hand is
  -- also delayed one hundredth of a cycle so the hands are not exact mirrors.
  local lGripA=sampleCycle(GAIT.grip,wrap01(phase+0.130))
  local lGripB=sampleCycle(GAIT.grip,wrap01(phase+0.115))
  local lGripC=sampleCycle(GAIT.grip,wrap01(phase+0.105))
  local lGripD=sampleCycle(GAIT.grip,wrap01(phase+0.090))
  local lGripE=sampleCycle(GAIT.grip,wrap01(phase+0.080))
  local rGripA=sampleCycle(GAIT.grip,wrap01(opposite+0.140))
  local rGripB=sampleCycle(GAIT.grip,wrap01(opposite+0.125))
  local rGripC=sampleCycle(GAIT.grip,wrap01(opposite+0.115))
  local rGripD=sampleCycle(GAIT.grip,wrap01(opposite+0.100))
  local rGripE=sampleCycle(GAIT.grip,wrap01(opposite+0.090))

  local lToe=sampleCycle(GAIT.toe,wrap01(phase-0.055))
  local rToe=sampleCycle(GAIT.toe,wrap01(opposite-0.055))

  -- Character-specific gait amplitudes. Red is a light jog: quicker than a
  -- walk, but without the exaggerated sprint reach. Naruto keeps a quick leg
  -- cycle while his upper body is handled by the dedicated ninja-run branch.
  if data.runtimeProfile=="RED" then
    lThigh=lThigh*1.02
    rThigh=rThigh*1.02
    lKnee=12+(lKnee-12)*0.94
    rKnee=12+(rKnee-12)*0.94
    lFoot=lFoot*0.96
    rFoot=rFoot*0.96
    lToe=lToe*1.02
    rToe=rToe*1.02
    lArm=lArm*0.74
    rArm=rArm*0.74
    lElbow=56+(lElbow-56)*0.54
    rElbow=56+(rElbow-56)*0.54
    lWristPitch=lWristPitch*0.46
    rWristPitch=rWristPitch*0.46
  elseif data.runtimeProfile=="NARUTO" then
    lThigh=lThigh*1.10
    rThigh=rThigh*1.10
    lKnee=12+(lKnee-12)*0.92
    rKnee=12+(rKnee-12)*0.92
    lFoot=lFoot*1.02
    rFoot=rFoot*1.02
    lToe=lToe*0.92
    rToe=rToe*0.92
    lArm=lArm*0.12
    rArm=rArm*0.12
    lElbow=24+(lElbow-24)*0.16
    rElbow=24+(rElbow-24)*0.16
  end

  local bob=sampleCycle(GAIT.bob,phase)*CONFIG.hipBobUnits*blend
  local twist=sampleCycle(GAIT.twist,phase)*CONFIG.hipTwistDeg*blend
  local shoulderWave=sampleCycle(GAIT.twist,wrap01(phase+0.5))*blend
  local headBob=sampleCycle(GAIT.headBob,wrap01(phase-0.020))*CONFIG.headBobUnits*blend
  local headNod=sampleCycle(GAIT.headNod,wrap01(phase-0.010))*CONFIG.headNodDeg*blend
  local headTurn=sampleCycle(GAIT.headTurn,wrap01(phase-0.030))*CONFIG.headYawDeg*blend
  local headRoll=sampleCycle(GAIT.headRoll,wrap01(phase-0.020))*CONFIG.headRollDeg*blend

  if data.runtimeProfile=="RED" then
    -- Light-jog body rhythm: enough vertical compression and counter-rotation
    -- to read as jogging, but kept restrained so the feet stay grounded.
    bob=bob*0.64
    twist=twist*0.88
    shoulderWave=shoulderWave*0.86
    headBob=headBob*0.52
    headNod=headNod*0.64
    headRoll=headRoll*0.48
  elseif data.runtimeProfile=="NARUTO" then
    bob=bob*0.24
    twist=twist*0.34
    shoulderWave=shoulderWave*0.22
    headBob=headBob*0.18
    headNod=headNod*0.28
    headRoll=headRoll*0.16
  end

  -- Dedicated Red light-jog pass. Red's model has real shoulder, hand, head,
  -- and toe bones, so v2.8.31 exposes them in animBone and animates the full
  -- chain instead of driving only the middle of each limb.
  if data.runtimeProfile=="RED" then
    if bone==A.Waist then
      if blend<=0.0001 then return nil end
      return compose(translate16(0,bob*0.38,0),rotZ(math.rad(twist*0.08)))
    elseif bone==A.Hips then
      if blend<=0.0001 then return nil end
      return compose(translate16(0,bob*0.07,0),rotZ(math.rad(twist*0.24)))
    elseif bone==A.Spine1 then
      if blend<=0.0001 then return nil end
      return compose(rotY(math.rad(-3.2*blend)),rotZ(math.rad(-twist*0.18)))
    elseif bone==A.Spine2 then
      if blend<=0.0001 then return nil end
      return rotZ(math.rad(shoulderWave*0.70))
    elseif bone==A.Spine3 then
      if blend<=0.0001 then return nil end
      return rotZ(math.rad(shoulderWave*0.52))
    elseif bone==A.Neck then
      if blend<=0.0001 then return nil end
      return compose(translate16(0,headBob*0.20,0),rotX(math.rad(headNod*0.20)))
    elseif bone==A.Head then
      if blend<=0.0001 then return nil end
      return compose(translate16(0,headBob*0.42,0),compose3(rotX(math.rad(headNod*0.42)),rotY(math.rad(headTurn*0.28)),rotZ(math.rad(headRoll*0.25))))
    elseif bone==A.LShoulder then
      return compose(rotY(math.rad(-twist*0.10)),rotZ(math.rad(-1.0-shoulderWave*0.08)))
    elseif bone==A.RShoulder then
      return compose(rotY(math.rad(-twist*0.10)),rotZ(math.rad(1.0+shoulderWave*0.08)))
    elseif bone==A.LArm then
      local rest=rotZ(math.rad(-84))
      local swing=rotY(math.rad(lArm*blend*0.72))
      local settle=rotX(math.rad(-1.2-shoulderWave*0.06))
      return compose(rest,compose(swing,settle))
    elseif bone==A.RArm then
      local rest=rotZ(math.rad(84))
      local swing=rotY(math.rad(rArm*blend*0.72))
      local settle=rotX(math.rad(1.2+shoulderWave*0.06))
      return compose(rest,compose(swing,settle))
    elseif bone==A.LForeArm then
      local flex=28+(lElbow-56)*0.22
      local lag=2.4*math.sin((phase+0.06)*math.pi*2)*blend
      return compose(rotY(math.rad(-flex)),rotX(math.rad(lag)))
    elseif bone==A.RForeArm then
      local flex=28+(rElbow-56)*0.22
      local lag=-2.4*math.sin((opposite+0.06)*math.pi*2)*blend
      return compose(rotY(math.rad(-flex)),rotX(math.rad(lag)))
    elseif bone==A.LHand then
      return compose3(rotX(math.rad(lWristPitch*0.13*blend)),rotY(math.rad(lWristYaw*0.10*blend)),rotZ(math.rad(-1.2+lWristRoll*0.06*blend)))
    elseif bone==A.RHand then
      return compose3(rotX(math.rad(-rWristPitch*0.13*blend)),rotY(math.rad(-rWristYaw*0.10*blend)),rotZ(math.rad(1.2-rWristRoll*0.06*blend)))
    elseif bone==A.LThigh then
      return rotY(math.rad(lThigh*blend))
    elseif bone==A.RThigh then
      return rotY(math.rad(rThigh*blend))
    elseif bone==A.LLeg then
      return rotY(math.rad(lKnee*blend))
    elseif bone==A.RLeg then
      return rotY(math.rad(rKnee*blend))
    elseif bone==A.LFoot then
      return rotY(math.rad(lFoot*blend))
    elseif bone==A.RFoot then
      return rotY(math.rad(rFoot*blend))
    elseif bone==A.LToe then
      return rotY(math.rad(lToe*blend*0.70))
    elseif bone==A.RToe then
      return rotY(math.rad(rToe*blend*0.70))
    end
  end

  -- Dedicated Naruto ninja-run pass. Push the torso forward and hold the arms
  -- nearly straight and level behind the body in the recognisable anime pose.
  if data.runtimeProfile=="NARUTO" then
    local sway=math.sin(phase*math.pi*2)*blend
    if bone==A.Waist then
      if blend<=0.0001 then return nil end
      return compose(translate16(0,bob*0.02,0),rotZ(math.rad(twist*0.04)))
    elseif bone==A.Hips then
      if blend<=0.0001 then return nil end
      return compose(translate16(0,bob*0.02,0),rotZ(math.rad(twist*0.06)))
    elseif bone==A.Spine1 then
      if blend<=0.0001 then return nil end
      return rotX(math.rad(-17.5*blend))
    elseif bone==A.Spine2 then
      if blend<=0.0001 then return nil end
      return rotX(math.rad(-8.0*blend))
    elseif bone==A.Spine3 then
      if blend<=0.0001 then return nil end
      return rotX(math.rad(-3.5*blend))
    elseif bone==A.Neck then
      if blend<=0.0001 then return nil end
      return rotX(math.rad(10.0*blend+headNod*0.06))
    elseif bone==A.Head then
      if blend<=0.0001 then return nil end
      return compose3(rotX(math.rad(6.0*blend+headNod*0.08)),rotY(math.rad(headTurn*0.08)),rotZ(math.rad(headRoll*0.04)))
    elseif bone==A.LShoulder then
      -- Numerically solved against Naruto's actual SMD bind matrices so the
      -- whole chain stays OUTSIDE the torso, shoulder-height, and behind him.
      return compose3(rotX(math.rad(-91.5)),rotY(math.rad(43.0)),rotZ(math.rad(37.3)))
    elseif bone==A.LArm then
      return compose3(rotX(math.rad(-1.9+sway*0.22)),rotY(math.rad(-0.3)),rotZ(math.rad(7.8)))
    elseif bone==A.LForeArm then
      return compose3(rotX(math.rad(-12.3+sway*0.12)),rotY(math.rad(5.0)),rotZ(math.rad(-13.7)))
    elseif bone==A.LHand then
      return compose3(rotX(math.rad(-1.0+sway*0.08)),rotY(math.rad(0.0)),rotZ(math.rad(0.0)))
    elseif bone==A.RShoulder then
      return compose3(rotX(math.rad(87.4)),rotY(math.rad(-37.2)),rotZ(math.rad(34.5)))
    elseif bone==A.RArm then
      return compose3(rotX(math.rad(2.3-sway*0.22)),rotY(math.rad(0.2)),rotZ(math.rad(4.1)))
    elseif bone==A.RForeArm then
      return compose3(rotX(math.rad(12.0-sway*0.12)),rotY(math.rad(-2.3)),rotZ(math.rad(-11.6)))
    elseif bone==A.RHand then
      return compose3(rotX(math.rad(-1.0-sway*0.08)),rotY(math.rad(0.0)),rotZ(math.rad(0.0)))
    elseif bone==A.LThigh then
      return rotAxis(-0.2949,0.1239,-0.9474,math.rad(lThigh*blend*1.02))
    elseif bone==A.RThigh then
      return rotAxis(0.3321,-0.1095,-0.9369,math.rad(rThigh*blend*1.02))
    elseif bone==A.LLeg then
      return rotAxis(-0.2949,0.1239,-0.9474,math.rad(lKnee*blend*0.90))
    elseif bone==A.RLeg then
      return rotAxis(0.3321,-0.1095,-0.9369,math.rad(rKnee*blend*0.90))
    elseif bone==A.LFoot then
      return rotAxis(-0.0475,0.3446,0.9376,math.rad(lFoot*blend*0.90))
    elseif bone==A.RFoot then
      return rotAxis(0.0349,-0.4342,0.9002,math.rad(rFoot*blend*0.90))
    elseif bone==A.LToe then
      return rotAxis(-0.0475,0.3446,0.9376,math.rad(lToe*blend*0.68))
    elseif bone==A.RToe then
      return rotAxis(0.0349,-0.4342,0.9002,math.rad(rToe*blend*0.68))
    end
  end

  -- Beelstarmon uses a procedural world-aligned humanoid rig generated from
  -- the supplied static FBX.  It has dedicated chest secondary-motion bones;
  -- the requested exaggerated setting is five times the baseline jiggle amount.
  if data.runtimeProfile=="BEELSTARMON" then
    local breastWave=math.sin(phase*math.pi*4.0)*blend
    local breastWave2=math.sin((phase+0.08)*math.pi*4.0)*blend
    local breastY=0.050*breastWave       -- five-times secondary motion, now localized to the actual chest
    local breastZ=0.020*breastWave2
    local hair1=math.sin((phase+0.08)*math.pi*2.0)*blend
    local hair2=math.sin((phase+0.18)*math.pi*2.0)*blend
    local cloth1=math.sin((phase+0.10)*math.pi*2.0)*blend
    local cloth2=math.sin((phase+0.22)*math.pi*2.0)*blend
    local cloth3=math.sin((phase+0.34)*math.pi*2.0)*blend
    local strideDrag=math.max(0, -math.sin(phase*math.pi*2.0))*blend
    local swayDrag=math.sin((phase+0.25)*math.pi*2.0)*blend
    if bone==A.Waist then
      if blend<=0.0001 then return nil end
      return compose(translate16(0,bob*0.22,0),rotZ(math.rad(twist*0.10)))
    elseif bone==A.Hips then
      if blend<=0.0001 then return nil end
      return compose(translate16(0,bob*0.05,0),rotZ(math.rad(twist*0.26)))
    elseif bone==A.Spine1 then
      if blend<=0.0001 then return nil end
      return compose(rotX(math.rad(-CONFIG.jogLeanDeg*blend*0.42)),rotZ(math.rad(-twist*0.16)))
    elseif bone==A.Spine2 then
      if blend<=0.0001 then return nil end
      return rotZ(math.rad(shoulderWave*0.58))
    elseif bone==A.Spine3 then
      if blend<=0.0001 then return nil end
      return rotZ(math.rad(shoulderWave*0.42))
    elseif bone==A.Neck then
      if blend<=0.0001 then return nil end
      return compose(translate16(0,headBob*0.15,0),rotX(math.rad(headNod*0.17)))
    elseif bone==A.Head then
      if blend<=0.0001 then return nil end
      return compose(translate16(0,headBob*0.30,0),compose3(rotX(math.rad(headNod*0.28)),rotY(math.rad(headTurn*0.20)),rotZ(math.rad(headRoll*0.18))))
    elseif bone==A.LShoulder then
      return compose(rotY(math.rad(-twist*0.08)),rotZ(math.rad(-1.2-shoulderWave*0.08)))
    elseif bone==A.RShoulder then
      return compose(rotY(math.rad(-twist*0.08)),rotZ(math.rad(1.2+shoulderWave*0.08)))
    elseif bone==A.LArm then
      return compose(rotX(math.rad(lArm*blend*0.48)),rotZ(math.rad(-2.0)))
    elseif bone==A.RArm then
      return compose(rotX(math.rad(-rArm*blend*0.48)),rotZ(math.rad(2.0)))
    elseif bone==A.LForeArm then
      local e=20+(lElbow-20)*0.42
      local lag=2.2*math.sin((phase+0.08)*math.pi*2.0)*blend
      return compose(rotX(math.rad(-e*0.58)),rotZ(math.rad(lag)))
    elseif bone==A.RForeArm then
      local e=20+(rElbow-20)*0.42
      local lag=-2.2*math.sin((opposite+0.08)*math.pi*2.0)*blend
      return compose(rotX(math.rad(e*0.58)),rotZ(math.rad(lag)))
    elseif bone==A.LHand then
      return compose3(rotX(math.rad(lWristPitch*0.18*blend)),rotY(math.rad(lWristYaw*0.12*blend)),rotZ(math.rad(-1.2+lWristRoll*0.08*blend)))
    elseif bone==A.RHand then
      return compose3(rotX(math.rad(-rWristPitch*0.18*blend)),rotY(math.rad(-rWristYaw*0.12*blend)),rotZ(math.rad(1.2-rWristRoll*0.08*blend)))
    elseif bone==A.LThigh then
      -- Hip carries the stride; the appended knee joint below now creates the
      -- actual visible hinge instead of making the entire shin bend as one rod.
      return compose(rotX(math.rad(lThigh*blend*0.52)), rotZ(math.rad(0.45*math.sin(phase*math.pi*2.0)*blend)))
    elseif bone==A.RThigh then
      return compose(rotX(math.rad(rThigh*blend*0.52)), rotZ(math.rad(-0.45*math.sin(opposite*math.pi*2.0)*blend)))
    elseif bone==A.LKnee then
      local k=12+(lKnee-12)*0.72
      return compose(rotX(math.rad(k*blend*0.88)), rotZ(math.rad(0.30*math.sin((phase+0.08)*math.pi*2.0)*blend)))
    elseif bone==A.RKnee then
      local k=12+(rKnee-12)*0.72
      return compose(rotX(math.rad(k*blend*0.88)), rotZ(math.rad(-0.30*math.sin((opposite+0.08)*math.pi*2.0)*blend)))
    elseif bone==A.LLeg then
      local k=12+(lKnee-12)*0.72
      return rotX(math.rad(k*blend*0.12))
    elseif bone==A.RLeg then
      local k=12+(rKnee-12)*0.72
      return rotX(math.rad(k*blend*0.12))
    elseif bone==A.LFoot then
      return compose(rotX(math.rad(-5.0 + lFoot*blend*0.62)), rotZ(math.rad(-0.35*math.sin((phase+0.03)*math.pi*2.0)*blend)))
    elseif bone==A.RFoot then
      return compose(rotX(math.rad(-5.0 + rFoot*blend*0.62)), rotZ(math.rad(0.35*math.sin((opposite+0.03)*math.pi*2.0)*blend)))
    elseif bone==A.LToe then
      return rotX(math.rad(3.0 + lToe*blend*0.44))
    elseif bone==A.RToe then
      return rotX(math.rad(3.0 + rToe*blend*0.44))
    elseif bone==A.LBreast then
      return compose(translate16(-0.005*breastWave2,breastY,breastZ),rotX(math.rad(2.4*breastWave)))
    elseif bone==A.RBreast then
      return compose(translate16(0.005*breastWave2,breastY*0.96,breastZ*0.92),rotX(math.rad(2.3*breastWave2)))
    elseif bone==A.HairRoot then
      -- Two-stage procedural hair lag. The root follows the head softly while
      -- the long lower section has a delayed, wider swing.
      return compose(translate16(0,0,0.004*hair1),compose3(rotX(math.rad(4.0*hair1)),rotY(math.rad(2.0*hair2)),rotZ(math.rad(2.8*hair2))))
    elseif bone==A.HairTip then
      return compose(translate16(0,0,0.012*hair2),compose3(rotX(math.rad(11.5*hair2)),rotY(math.rad(3.6*hair1)),rotZ(math.rad(7.0*hair2))))
    elseif bone==A.CapeTop or bone==A.CapeMid or bone==A.CapeBottom or
        bone==A.CapeLTop or bone==A.CapeLMid or bone==A.CapeLTip or
        bone==A.CapeRTop or bone==A.CapeRMid or bone==A.CapeRTip then
      local C=data.runtimeCloth
      local node=nil
      if C then
        if bone==A.CapeTop then node=C.ct elseif bone==A.CapeMid then node=C.cm elseif bone==A.CapeBottom then node=C.cb
        elseif bone==A.CapeLTop then node=C.lt elseif bone==A.CapeLMid then node=C.lm elseif bone==A.CapeLTip then node=C.lb
        elseif bone==A.CapeRTop then node=C.rt elseif bone==A.CapeRMid then node=C.rm elseif bone==A.CapeRTip then node=C.rb end
      end
      if node then
        local depth=0.004
        if bone==A.CapeMid or bone==A.CapeLMid or bone==A.CapeRMid then depth=0.010
        elseif bone==A.CapeBottom or bone==A.CapeLTip or bone==A.CapeRTip then depth=0.018 end
        return compose(translate16(0,0,depth*math.sin(math.rad(node.p or 0))),compose(rotX(math.rad(node.p or 0)),rotZ(math.rad(node.y or 0))))
      end
      -- deterministic fallback for runtimes that skip the frame-state update
      if bone==A.CapeTop then return compose(rotX(math.rad(2.0+2.0*cloth1)),rotZ(math.rad(cloth1))) end
      if bone==A.CapeMid then return compose(rotX(math.rad(4.0+4.0*cloth2)),rotZ(math.rad(cloth2*1.5))) end
      if bone==A.CapeBottom then return compose(rotX(math.rad(7.0+7.0*cloth3)),rotZ(math.rad(cloth3*2.2))) end
      local side=(bone==A.CapeLTop or bone==A.CapeLMid or bone==A.CapeLTip) and 1 or -1
      local amp=(bone==A.CapeLTip or bone==A.CapeRTip) and 8 or ((bone==A.CapeLMid or bone==A.CapeRMid) and 5 or 3)
      return compose(rotX(math.rad(amp+cloth2*amp*0.65)),rotZ(math.rad(side*cloth3*amp*0.35)))
    end
  end

  -- Shrek's generated bind skeleton uses simple world-aligned joint axes.
  -- Reuse Red's gait timing, but map it onto Shrek's actual axes instead of
  -- blindly using Red's local-Y leg rotations (which twisted his knees sideways).
  if data.runtimeProfile=="SHREK_RED" then
    if bone==A.Waist then
      if blend<=0.0001 then return nil end
      return compose(translate16(0,bob*0.45,0),rotZ(math.rad(twist*0.08)))
    elseif bone==A.Hips then
      if blend<=0.0001 then return nil end
      return compose(translate16(0,bob*0.12,0),rotZ(math.rad(twist*0.24)))
    elseif bone==A.Spine1 then
      if blend<=0.0001 then return nil end
      return compose(rotX(math.rad(-CONFIG.jogLeanDeg*blend*0.55)),rotZ(math.rad(-twist*0.15)))
    elseif bone==A.Spine2 then
      if blend<=0.0001 then return nil end
      return rotZ(math.rad(shoulderWave*CONFIG.shoulderTwistDeg*0.10))
    elseif bone==A.Spine3 then
      if blend<=0.0001 then return nil end
      return rotZ(math.rad(shoulderWave*CONFIG.shoulderTwistDeg*0.08))
    elseif bone==A.Neck then
      if blend<=0.0001 then return nil end
      return compose(translate16(0,headBob*0.18,0),compose3(rotX(math.rad(headNod*0.24)),rotY(math.rad(headTurn*0.25)),rotZ(math.rad(-shoulderWave*CONFIG.headCounterDeg*0.22))))
    elseif bone==A.Head then
      if blend<=0.0001 then return nil end
      return compose(translate16(0,headBob*0.42,0),compose3(rotX(math.rad(headNod*0.45)),rotY(math.rad(headTurn*0.35)),rotZ(math.rad((-shoulderWave*CONFIG.headCounterDeg*0.40)+headRoll*0.28))))
    elseif bone==A.LShoulder or bone==A.RShoulder then
      if blend<=0.0001 then return nil end
      local sign=(bone==A.LShoulder) and -1 or 1
      return rotZ(math.rad(sign*(6.5 + shoulderWave*0.30)))
    elseif bone==A.LArm then
      -- Shrek's generated bind has the upper arms spread too far out for Red's
      -- straight application. First drop them inward around local Z, then add
      -- a gentler fore/aft X swing so the hands stay beside the body.
      return compose(rotX(math.rad(lArm*blend*0.42)), rotZ(math.rad(-42)))
    elseif bone==A.RArm then
      return compose(rotX(math.rad(-rArm*blend*0.42)), rotZ(math.rad(42)))
    elseif bone==A.LForeArm then
      local elbow=14+(lElbow-14)*blend
      return compose(rotX(math.rad(-elbow*0.34)), rotZ(math.rad(-14)))
    elseif bone==A.RForeArm then
      local elbow=14+(rElbow-14)*blend
      return compose(rotX(math.rad(elbow*0.34)), rotZ(math.rad(14)))
    elseif bone==A.LHand then
      return compose(rotX(math.rad(lWristPitch*0.14*blend)), rotZ(math.rad(-6)))
    elseif bone==A.RHand then
      return compose(rotX(math.rad(-rWristPitch*0.14*blend)), rotZ(math.rad(6)))
    elseif bone==A.LThigh then
      return rotX(math.rad(lThigh*blend*0.72))
    elseif bone==A.RThigh then
      return rotX(math.rad(rThigh*blend*0.72))
    elseif bone==A.LLeg then
      return rotX(math.rad(lKnee*blend*0.58))
    elseif bone==A.RLeg then
      return rotX(math.rad(rKnee*blend*0.58))
    elseif bone==A.LFoot then
      return rotX(math.rad(lFoot*blend*0.55))
    elseif bone==A.RFoot then
      return rotX(math.rad(rFoot*blend*0.55))
    elseif bone==A.LToe then
      return rotX(math.rad(lToe*blend*0.35))
    elseif bone==A.RToe then
      return rotX(math.rad(rToe*blend*0.35))
    end
  end

  if bone==A.Waist then
    if blend<=0.0001 then return nil end
    local waistBob=(data.runtimeProfile=="RED") and (bob*0.28) or (bob*0.65)
    return compose(translate16(0,waistBob,0),rotZ(math.rad(twist*0.10)))
  elseif bone==A.Spine1 then
    if blend<=0.0001 then return nil end
    local leanAmount = CONFIG.jogLeanDeg*blend*((data.runtimeProfile=="RED") and 0.58 or 1.0)
    local leanRot = (data.runtimeProfile=="YUGI" or data.runtimeProfile=="NARUTO" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="AANG" or data.runtimeProfile=="CJ")
      and rotX(math.rad(-leanAmount))
      or rotY(math.rad(-leanAmount))
    return compose(leanRot,rotZ(math.rad(-twist*0.22)))
  elseif bone==A.Spine2 then
    if blend<=0.0001 then return nil end
    return rotZ(math.rad(shoulderWave*CONFIG.shoulderTwistDeg*0.16))
  elseif bone==A.Spine3 then
    if blend<=0.0001 then return nil end
    return rotZ(math.rad(shoulderWave*CONFIG.shoulderTwistDeg*0.14))
  elseif bone==A.Neck then
    if blend<=0.0001 then return nil end
    local neckRot = compose3(
      rotX(math.rad(headNod*0.38)),
      rotY(math.rad(headTurn*0.45)),
      rotZ(math.rad((-shoulderWave*CONFIG.headCounterDeg*0.45) + headRoll*0.45))
    )
    return compose(translate16(0,headBob*0.32,0), neckRot)
  elseif bone==A.Head then
    if blend<=0.0001 then return nil end
    -- Small counter-motion plus a subtle bob/nod gives the head life while
    -- still keeping it comparatively stable like a real relaxed jog.
    local headRot = compose3(
      rotX(math.rad(headNod)),
      rotY(math.rad((-twist*0.18) + headTurn)),
      rotZ(math.rad((-shoulderWave*CONFIG.headCounterDeg) + headRoll))
    )
    return compose(translate16(0,headBob,0), headRot)
  elseif bone==A.Hips then
    if blend<=0.0001 then return nil end
    local hipsBob=(data.runtimeProfile=="RED") and (bob*0.05) or (bob*0.18)
    return compose(translate16(0,hipsBob,0),rotZ(math.rad(twist*0.38)))
  elseif bone==A.LShoulder then
    if blend<=0.0001 then return nil end
    if data.runtimeProfile=="NARUTO" or data.runtimeProfile=="CJ" then return nil end
    if data.runtimeProfile=="RED" then
      return compose(rotY(math.rad(-twist*0.10)), rotZ(math.rad(-1.8 - shoulderWave*0.10)))
    end
    return compose(
      rotY(math.rad(-twist*CONFIG.shoulderTwistDeg/CONFIG.hipTwistDeg*0.38)),
      rotZ(math.rad((-0.30*math.max(0,lArm/18)+0.12*math.max(0,-lArm/18))*blend))
    )
  elseif bone==A.RShoulder then
    if blend<=0.0001 then return nil end
    if data.runtimeProfile=="NARUTO" or data.runtimeProfile=="CJ" then return nil end
    if data.runtimeProfile=="RED" then
      return compose(rotY(math.rad(-twist*0.10)), rotZ(math.rad(1.8 + shoulderWave*0.10)))
    end
    return compose(
      rotY(math.rad(-twist*CONFIG.shoulderTwistDeg/CONFIG.hipTwistDeg*0.38)),
      rotZ(math.rad((0.30*math.max(0,rArm/18)-0.12*math.max(0,-rArm/18))*blend))
    )
  elseif bone==A.LArm then
    if data.runtimeProfile=="NARUTO" then
      local rest=rotAxis(0.11208,-0.11625,0.98688,math.rad(-70))
      local swing=rotAxis(-0.25845,0.95554,0.14191,math.rad(lArm*blend*0.48))
      return compose(rest,swing)
    end
    local rest=rotZ(math.rad(-(data.runtimeArmRest or CONFIG.armRestDeg)))
    if data.runtimeProfile=="AANG" then
      local aangRest=rotZ(math.rad(data.runtimeArmRest or 70))
      return compose(rotY(math.rad(lArm*blend*0.55)),aangRest)
    elseif data.runtimeProfile=="CJ" then
      local a=lArm
      if a < -10 then a=-10 elseif a > 12 then a=12 end
      return compose(rest,rotY(math.rad(6 + a*blend*0.16)))
    elseif data.runtimeProfile=="CLOUD" then
      return rotZ(math.rad(lArm*blend*0.34))
    elseif data.runtimeProfile=="GENERIC" then
      local rest=rotZ(math.rad(-(data.runtimeArmRest or 0)))
      local swing=rotY(math.rad(lArm*blend*0.50))
      return compose(rest,swing)
    elseif data.runtimeProfile=="YUGI" then
      -- Yugi's SMD arms exaggerate rearward motion. Bias the swing forward
      -- and cap the backswing so the hand stays beside/just behind the hip
      -- instead of being pulled unnaturally behind the torso.
      local a=lArm
      if a < -9 then a=-9 elseif a > 16 then a=16 end
      a=a+2.5
      return compose(rotX(math.rad(a*blend*0.34)),rest)
    elseif data.runtimeProfile=="RED" then
      -- Red's bind arms start close to a T-pose, so keep a proper arm-down
      -- rest orientation and layer the softer human walk swing on top of it.
      local rest=rotZ(math.rad(-88))
      return compose(rest, compose(rotY(math.rad(lArm*blend*0.34)), rotX(math.rad(-2.2))))
    end
    return compose(rest,rotY(math.rad(lArm*blend)))
  elseif bone==A.RArm then
    if data.runtimeProfile=="NARUTO" then
      local rest=rotAxis(0.12191,-0.07037,-0.99004,math.rad(70))
      local swing=rotAxis(0.35474,-0.92851,0.10968,math.rad(rArm*blend*0.48))
      return compose(rest,swing)
    end
    local rest=rotZ(math.rad(data.runtimeArmRest or CONFIG.armRestDeg))
    if data.runtimeProfile=="AANG" then
      local aangRest=rotZ(math.rad(-(data.runtimeArmRest or 70)))
      return compose(rotY(math.rad(rArm*blend*0.55)),aangRest)
    elseif data.runtimeProfile=="CJ" then
      local a=rArm
      if a < -8 then a=-8 elseif a > 10 then a=10 end
      return compose(rest,compose(rotY(math.rad(26 + a*blend*0.10)),rotX(math.rad(-2))))
    elseif data.runtimeProfile=="CLOUD" then
      return rotZ(math.rad(rArm*blend*0.34))
    elseif data.runtimeProfile=="GENERIC" then
      local rest=rotZ(math.rad(data.runtimeArmRest or 0))
      local swing=rotY(math.rad(rArm*blend*0.50))
      return compose(rest,swing)
    elseif data.runtimeProfile=="YUGI" then
      local a=rArm
      if a < -9 then a=-9 elseif a > 16 then a=16 end
      a=a+2.5
      return compose(rotX(math.rad(-a*blend*0.34)),rest)
    elseif data.runtimeProfile=="RED" then
      local rest=rotZ(math.rad(88))
      return compose(rest, compose(rotY(math.rad(rArm*blend*0.34)), rotX(math.rad(2.2))))
    end
    return compose(rest,rotY(math.rad(rArm*blend)))
  elseif bone==A.LForeArm then
    local idle=12
    local elbow=idle+(lElbow-idle)*blend
    if data.runtimeProfile=="NARUTO" then
      return rotAxis(-0.25845,0.95554,0.14191,math.rad(-elbow*0.62))
    end
    if data.runtimeProfile=="AANG" then return rotZ(math.rad(elbow*0.50)) end
    if data.runtimeProfile=="CJ" then return rotY(math.rad(-8 - elbow*0.16)) end
    if data.runtimeProfile=="CLOUD" then return rotZ(math.rad(-elbow*0.28)) end
    if data.runtimeProfile=="GENERIC" then
      return rotX(math.rad(-elbow*0.42))
    end
    if data.runtimeProfile=="YUGI" then
      -- SMD idle confirms the LEFT elbow flexes toward negative local Y.
      local yugiElbow=14+(elbow-12)*0.28
      return rotY(math.rad(-yugiElbow))
    end
    if data.runtimeProfile=="RED" then
      local lag=4.0*math.sin((phase+0.10)*math.pi*2)*blend
      return compose(rotY(math.rad(-(28 + elbow*0.24))), rotX(math.rad(lag)))
    end
    local pronate=1.25*math.sin((phase+0.47)*math.pi*2)*blend
    return compose(rotY(math.rad(-elbow)),rotX(math.rad(pronate)))
  elseif bone==A.RForeArm then
    local idle=12
    local elbow=idle+(rElbow-idle)*blend
    if data.runtimeProfile=="NARUTO" then
      return rotAxis(0.35474,-0.92851,0.10968,math.rad(-elbow*0.62))
    end
    if data.runtimeProfile=="AANG" then return rotZ(math.rad(-elbow*0.50)) end
    if data.runtimeProfile=="CJ" then return rotY(math.rad(50 + elbow*0.10)) end
    if data.runtimeProfile=="CLOUD" then return rotZ(math.rad(elbow*0.28)) end
    if data.runtimeProfile=="GENERIC" then
      return rotX(math.rad(-elbow*0.42))
    end
    if data.runtimeProfile=="YUGI" then
      -- Yugi's RIGHT forearm hinge is mirrored: positive local Y. Using the
      -- Red sign here was the source of the folded/twisted right arm.
      local yugiElbow=14+(elbow-12)*0.28
      return rotY(math.rad(yugiElbow))
    end
    if data.runtimeProfile=="RED" then
      local lag=-4.0*math.sin((opposite+0.10)*math.pi*2)*blend
      return compose(rotY(math.rad(-(28 + elbow*0.24))), rotX(math.rad(lag)))
    end
    local pronate=-1.25*math.sin((opposite+0.46)*math.pi*2)*blend
    return compose(rotY(math.rad(-elbow)),rotX(math.rad(pronate)))
  elseif bone==A.LHand then
    if data.runtimeProfile=="CJ" then
      return compose3(rotX(math.rad(4)),rotY(math.rad(2)),rotZ(math.rad(8)))
    end
    if data.runtimeProfile=="NARUTO" or data.runtimeProfile=="AANG" or data.runtimeProfile=="CLOUD" then return nil end
    if data.runtimeProfile=="GENERIC" then
      return compose3(rotX(math.rad(lWristPitch*0.35*blend)), rotY(math.rad(lWristYaw*0.25*blend)), rotZ(math.rad(lWristRoll*0.20*blend)))
    end
    if data.runtimeProfile=="YUGI" then
      return compose3(
        rotX(math.rad(lWristPitch*0.22*blend)),
        rotY(math.rad(lWristYaw*0.22*blend)),
        rotZ(math.rad(-3 + lWristRoll*0.18*blend))
      )
    end
    if data.runtimeProfile=="RED" then
      return compose3(rotX(math.rad(lWristPitch*0.18*blend)), rotY(math.rad(lWristYaw*0.16*blend)), rotZ(math.rad(-2.5 + lWristRoll*0.10*blend)))
    end
    -- Three-axis wrist follow-through plus a tiny natural inward rest angle.
    return compose3(
      rotX(math.rad(lWristPitch*0.78*blend)),
      rotY(math.rad(lWristYaw*blend)),
      rotZ(math.rad((lWristRoll*blend)-1.8))
    )
  elseif bone==A.RHand then
    if data.runtimeProfile=="CJ" then
      return compose3(rotX(math.rad(-8)),rotY(math.rad(8)),rotZ(math.rad(-24)))
    end
    if data.runtimeProfile=="NARUTO" or data.runtimeProfile=="AANG" or data.runtimeProfile=="CLOUD" then return nil end
    if data.runtimeProfile=="GENERIC" then
      return compose3(rotX(math.rad(-rWristPitch*0.35*blend)), rotY(math.rad(-rWristYaw*0.25*blend)), rotZ(math.rad(-rWristRoll*0.20*blend)))
    end
    if data.runtimeProfile=="YUGI" then
      return compose3(
        rotX(math.rad(-rWristPitch*0.22*blend)),
        rotY(math.rad(-rWristYaw*0.22*blend)),
        rotZ(math.rad(3 - rWristRoll*0.18*blend))
      )
    end
    if data.runtimeProfile=="RED" then
      return compose3(rotX(math.rad(-rWristPitch*0.18*blend)), rotY(math.rad(-rWristYaw*0.16*blend)), rotZ(math.rad(2.5 - rWristRoll*0.10*blend)))
    end
    return compose3(
      rotX(math.rad(-rWristPitch*0.78*blend)),
      rotY(math.rad(-rWristYaw*blend)),
      rotZ(math.rad((-rWristRoll*blend)+1.8))
    )

  -- The backpack lags the torso by a fraction of a step.  Very small motion
  -- here adds a lot of perceived softness because the bag is visually large.
  elseif bone==A.Bag1 then
    if blend<=0.0001 then return nil end
    local lag=sampleCycle(GAIT.arm,wrap01(phase+0.62))/38
    return rotY(math.rad(-lag*CONFIG.bagSwingDeg*blend))
  elseif bone==A.Bag2 then
    if blend<=0.0001 then return nil end
    local lag=sampleCycle(GAIT.arm,wrap01(phase+0.67))/38
    return rotY(math.rad(-lag*CONFIG.bagSwingDeg*0.55*blend))
  elseif bone==A.Bag3 then
    if blend<=0.0001 then return nil end
    local lag=sampleCycle(GAIT.arm,wrap01(phase+0.71))/38
    return rotY(math.rad(-lag*CONFIG.bagSwingDeg*0.30*blend))

  -- Naruto keeps the exact SMD hand/finger rest pose; its finger joint axes
  -- differ substantially from Red/Yugi and forcing Red's curl axes deforms them.
  elseif data.runtimeProfile=="NARUTO" and (
      bone==A.LFingerA1 or bone==A.LFingerA2 or bone==A.LFingerA3 or
      bone==A.LFingerB1 or bone==A.LFingerB2 or bone==A.LFingerB3 or
      bone==A.LFingerC1 or bone==A.LFingerC2 or bone==A.LFingerC3 or
      bone==A.LFingerD1 or bone==A.LFingerD2 or bone==A.LFingerD3 or
      bone==A.LFingerE1 or bone==A.LFingerE2 or bone==A.LFingerE3 or
      bone==A.RFingerA1 or bone==A.RFingerA2 or bone==A.RFingerA3 or
      bone==A.RFingerB1 or bone==A.RFingerB2 or bone==A.RFingerB3 or
      bone==A.RFingerC1 or bone==A.RFingerC2 or bone==A.RFingerC3 or
      bone==A.RFingerD1 or bone==A.RFingerD2 or bone==A.RFingerD3 or
      bone==A.RFingerE1 or bone==A.RFingerE2 or bone==A.RFingerE3) then
    return nil

  -- Hands use a loose runner's grip.  Each digit has its own resting curl,
  -- amplitude and phase so the hand reads as a soft organic shape rather than
  -- a paddle or five synchronized mechanical hinges.
  elseif bone==A.LFingerA1 then
    local curl=CONFIG.thumbCurlDeg + CONFIG.thumbMotionDeg*lGripA*blend
    local oppose=3.5 + 2.0*lGripA*blend
    return compose(rotY(math.rad(-oppose)),rotZ(math.rad(-curl)))
  elseif bone==A.LFingerA2 then
    return rotZ(math.rad(-(CONFIG.thumbCurlDeg*0.78 + CONFIG.thumbMotionDeg*0.58*lGripA*blend)))
  elseif bone==A.LFingerA3 then
    return rotZ(math.rad(-(CONFIG.thumbCurlDeg*0.50 + CONFIG.thumbMotionDeg*0.22*lGripA*blend)))
  elseif bone==A.LFingerB1 then
    return compose(rotY(math.rad(-1.5*(1-0.45*lGripB*blend))),rotZ(math.rad(-(10+4.6*lGripB*blend))))
  elseif bone==A.LFingerB2 then
    return rotZ(math.rad(-(7.8+3.6*lGripB*blend)))
  elseif bone==A.LFingerB3 then
    return rotZ(math.rad(-(5.0+2.3*lGripB*blend)))
  elseif bone==A.LFingerC1 then
    return compose(rotY(math.rad(-0.5*(1-0.45*lGripC*blend))),rotZ(math.rad(-(13+6.0*lGripC*blend))))
  elseif bone==A.LFingerC2 then
    return rotZ(math.rad(-(10.1+4.7*lGripC*blend)))
  elseif bone==A.LFingerC3 then
    return rotZ(math.rad(-(6.5+3.0*lGripC*blend)))
  elseif bone==A.LFingerD1 then
    return compose(rotY(math.rad(0.6*(1-0.45*lGripD*blend))),rotZ(math.rad(-(16+7.0*lGripD*blend))))
  elseif bone==A.LFingerD2 then
    return rotZ(math.rad(-(12.5+5.5*lGripD*blend)))
  elseif bone==A.LFingerD3 then
    return rotZ(math.rad(-(8.0+3.5*lGripD*blend)))
  elseif bone==A.LFingerE1 then
    return compose(rotY(math.rad(1.7*(1-0.45*lGripE*blend))),rotZ(math.rad(-(18.5+7.8*lGripE*blend))))
  elseif bone==A.LFingerE2 then
    return rotZ(math.rad(-(14.0+6.1*lGripE*blend)))
  elseif bone==A.LFingerE3 then
    return rotZ(math.rad(-(9.0+3.9*lGripE*blend)))

  elseif bone==A.RFingerA1 then
    local curl=CONFIG.thumbCurlDeg + CONFIG.thumbMotionDeg*rGripA*blend
    local oppose=3.5 + 2.0*rGripA*blend
    return compose(rotY(math.rad(oppose)),rotZ(math.rad(curl)))
  elseif bone==A.RFingerA2 then
    return rotZ(math.rad(CONFIG.thumbCurlDeg*0.78 + CONFIG.thumbMotionDeg*0.58*rGripA*blend))
  elseif bone==A.RFingerA3 then
    return rotZ(math.rad(CONFIG.thumbCurlDeg*0.50 + CONFIG.thumbMotionDeg*0.22*rGripA*blend))
  elseif bone==A.RFingerB1 then
    return compose(rotY(math.rad(1.5*(1-0.45*rGripB*blend))),rotZ(math.rad(10+4.6*rGripB*blend)))
  elseif bone==A.RFingerB2 then
    return rotZ(math.rad(7.8+3.6*rGripB*blend))
  elseif bone==A.RFingerB3 then
    return rotZ(math.rad(5.0+2.3*rGripB*blend))
  elseif bone==A.RFingerC1 then
    return compose(rotY(math.rad(0.5*(1-0.45*rGripC*blend))),rotZ(math.rad(13+6.0*rGripC*blend)))
  elseif bone==A.RFingerC2 then
    return rotZ(math.rad(10.1+4.7*rGripC*blend))
  elseif bone==A.RFingerC3 then
    return rotZ(math.rad(6.5+3.0*rGripC*blend))
  elseif bone==A.RFingerD1 then
    return compose(rotY(math.rad(-0.6*(1-0.45*rGripD*blend))),rotZ(math.rad(16+7.0*rGripD*blend)))
  elseif bone==A.RFingerD2 then
    return rotZ(math.rad(12.5+5.5*rGripD*blend))
  elseif bone==A.RFingerD3 then
    return rotZ(math.rad(8.0+3.5*rGripD*blend))
  elseif bone==A.RFingerE1 then
    return compose(rotY(math.rad(-1.7*(1-0.45*rGripE*blend))),rotZ(math.rad(18.5+7.8*rGripE*blend)))
  elseif bone==A.RFingerE2 then
    return rotZ(math.rad(14.0+6.1*rGripE*blend))
  elseif bone==A.RFingerE3 then
    return rotZ(math.rad(9.0+3.9*rGripE*blend))

  elseif bone==A.LThigh then
    local a=math.rad(lThigh*blend)
    if data.runtimeProfile=="NARUTO" then return rotAxis(-0.2949,0.1239,-0.9474,a) end
    if data.runtimeProfile=="AANG" then return rotY(-a) end
    if data.runtimeProfile=="CLOUD" then return rotZ(a) end
    return (data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="CJ") and rotX(a) or rotY(a)
  elseif bone==A.RThigh then
    local a=math.rad(rThigh*blend)
    if data.runtimeProfile=="NARUTO" then return rotAxis(0.3321,-0.1095,-0.9369,a) end
    if data.runtimeProfile=="AANG" then return rotY(-a) end
    if data.runtimeProfile=="CLOUD" then return rotZ(a) end
    return (data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="CJ") and rotX(a) or rotY(a)
  elseif bone==A.LLeg then
    local a=math.rad(lKnee*blend)
    if data.runtimeProfile=="NARUTO" then return rotAxis(-0.2949,0.1239,-0.9474,a) end
    if data.runtimeProfile=="AANG" then return rotY(-a) end
    if data.runtimeProfile=="CLOUD" then return rotZ(a) end
    return (data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="CJ") and rotX(a) or rotY(a)
  elseif bone==A.RLeg then
    local a=math.rad(rKnee*blend)
    if data.runtimeProfile=="NARUTO" then return rotAxis(0.3321,-0.1095,-0.9369,a) end
    if data.runtimeProfile=="AANG" then return rotY(-a) end
    if data.runtimeProfile=="CLOUD" then return rotZ(a) end
    return (data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="CJ") and rotX(a) or rotY(a)
  elseif bone==A.LFoot then
    local a=math.rad(lFoot*blend)
    if data.runtimeProfile=="NARUTO" then return rotAxis(-0.0475,0.3446,0.9376,a) end
    if data.runtimeProfile=="AANG" then return rotY(-a) end
    if data.runtimeProfile=="CLOUD" then return rotZ(a) end
    return (data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="CJ") and rotX(a) or rotY(a)
  elseif bone==A.RFoot then
    local a=math.rad(rFoot*blend)
    if data.runtimeProfile=="NARUTO" then return rotAxis(0.0349,-0.4342,0.9002,a) end
    if data.runtimeProfile=="AANG" then return rotY(-a) end
    if data.runtimeProfile=="CLOUD" then return rotZ(a) end
    return (data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="CJ") and rotX(a) or rotY(a)
  elseif bone==A.LToe then
    local a=math.rad(lToe*blend)
    if data.runtimeProfile=="NARUTO" then return rotAxis(-0.0475,0.3446,0.9376,a) end
    if data.runtimeProfile=="AANG" then return rotY(-a) end
    if data.runtimeProfile=="CLOUD" then return rotZ(a) end
    return (data.runtimeProfile=="YUGI" or data.runtimeProfile=="GENERIC" or data.runtimeProfile=="CJ") and rotX(a) or rotY(a)
  elseif bone==A.RToe then
    local a=math.rad(rToe*blend)
    if data.runtimeProfile=="NARUTO" then return rotAxis(0.0349,-0.4342,0.9002,a) end
    if data.runtimeProfile=="CJ" then return rotX(a*0.08) end
    return data.runtimeProfile=="YUGI" and rotX(a) or rotY(a)
  end
  return nil
end

local function clothSpringStep(node,targetPitch,targetYaw,k,damping,dt)
  node.p=node.p or 0; node.pv=node.pv or 0
  node.y=node.y or 0; node.yv=node.yv or 0
  node.pv=node.pv+(targetPitch-node.p)*k*dt
  node.yv=node.yv+(targetYaw-node.y)*k*dt
  local drag=math.exp(-damping*dt)
  node.pv=node.pv*drag; node.yv=node.yv*drag
  node.p=node.p+node.pv*dt; node.y=node.y+node.yv*dt
end

function Renderer:updateBeelCloth(dt,walking)
  if not self.data or self.data.runtimeProfile~="BEELSTARMON" then return end
  dt=tonumber(dt) or (1/60)
  if dt<0 then dt=0 elseif dt>0.05 then dt=0.05 end
  local C=self.beelCloth
  if not C then
    C={ct={},cm={},cb={},lt={},lm={},lb={},rt={},rm={},rb={}}
    self.beelCloth=C
  end
  local speed=tonumber(self.voxelSmoothSpeed) or tonumber(self.motionMeasuredSpeed) or 0
  if not walking then speed=speed*0.22 end
  local s=math.max(0,math.min(1.25,speed/78))
  local prev=self.beelClothSpeed or s
  local accel=(dt>0.0001) and ((s-prev)/dt) or 0
  self.beelClothSpeed=s
  if accel>7 then accel=7 elseif accel<-7 then accel=-7 end
  local cyclePixels=CONFIG.worldPixelsPerCycle
  local phase=((self.voxelGaitDistance or self.motionDistance or 0)/cyclePixels)%1
  local gait=math.sin(phase*math.pi*2)
  local pulse=math.sin((phase+0.16)*math.pi*2)
  local kick=accel*0.72

  -- Local-angle targets. Because the cape chains are hierarchical, modest
  -- per-joint angles accumulate into a broad cloth curve instead of rotating
  -- the entire garment as one rigid board.
  clothSpringStep(C.ct, 2.0*s + kick*0.15, 0.45*gait*s, 88,13.5,dt)
  clothSpringStep(C.cm, 3.8*s + kick*0.30 + C.ct.p*0.16, 0.85*gait*s + C.ct.y*0.18, 58,9.8,dt)
  clothSpringStep(C.cb, 6.5*s + kick*0.55 + C.cm.p*0.18, 1.55*pulse*s + C.cm.y*0.22, 36,6.8,dt)

  clothSpringStep(C.lt, 2.5*s + kick*0.18, 0.9*gait*s, 76,11.8,dt)
  clothSpringStep(C.lm, 4.8*s + kick*0.36 + C.lt.p*0.18, 1.8*gait*s + C.lt.y*0.22, 48,8.6,dt)
  clothSpringStep(C.lb, 8.2*s + kick*0.70 + C.lm.p*0.22, 3.8*pulse*s + C.lm.y*0.25, 28,5.9,dt)

  clothSpringStep(C.rt, 2.5*s + kick*0.18, -0.9*gait*s, 76,11.8,dt)
  clothSpringStep(C.rm, 4.8*s + kick*0.36 + C.rt.p*0.18, -1.8*gait*s + C.rt.y*0.22, 48,8.6,dt)
  clothSpringStep(C.rb, 8.2*s + kick*0.70 + C.rm.p*0.22, -3.8*pulse*s + C.rm.y*0.25, 28,5.9,dt)
end

function Renderer:motionSample(player,px,py,now)
  local walking = (player.moving == true)
      or (player.bumpFrames and player.bumpFrames > 0)
      or (player.stepLanded == true)

  local x=tonumber(px) or tonumber(player.px) or 0
  local y=tonumber(py) or tonumber(player.py) or 0

  if self.motionX==nil or self.motionY==nil then
    self.motionX,self.motionY=x,y
    self.motionSampleTime=now
  end

  local dx,dy=x-self.motionX,y-self.motionY
  local dist=math.sqrt(dx*dx+dy*dy)

  -- A warp/map swap is not a giant jog step.  Ignore discontinuities and
  -- keep the current gait phase when the player reappears at the destination.
  if dist > 8 then dist=0 end

  if dist > 0.0001 then
    if now and self.motionSampleTime then
      local sampleDt=now-self.motionSampleTime
      if sampleDt > 0.001 and sampleDt < 0.20 then
        local measured=dist/sampleDt
        if measured >= 8 and measured <= 240 then
          self.motionMeasuredSpeed=measured
        end
      end
    end
    self.motionX,self.motionY=x,y
    if walking then self.motionDistance=self.motionDistance+dist end
    self.motionSampleTime=now
  elseif walking and player.bumpFrames and player.bumpFrames > 0 then
    -- Wall-bonk keeps the stock walk clock moving despite zero translation.
    local ac=tonumber(player.animClock)
    if ac and self.lastAnimClock then
      local da=ac-self.lastAnimClock
      if da >= 0 and da <= 4 then
        self.motionDistance=self.motionDistance+da
      end
    end
  end

  self.lastAnimClock=tonumber(player.animClock) or self.lastAnimClock
  return walking,x,y
end

local function smooth01(x)
  if x<=0 then return 0 elseif x>=1 then return 1 end
  return x*x*(3-2*x)
end

function Renderer:belleRunTarget(player,walking)
  if self.characterId~="BELLESTARMON" or not walking then return 0 end
  local x=tonumber(player and player.red3dMoveStickX) or 0
  local y=tonumber(player and player.red3dMoveStickY) or 0
  local mag=math.sqrt(x*x+y*y)
  if mag>1 then mag=1 end
  local analog=(player and player.red3dAnalogMoveActive==true and mag>0.08)
  if not analog then
    -- Keyboard/D-pad movement has no analog magnitude, so it remains Fast Run.
    return 1
  end
  local start=CONFIG.belleRunBlendStart or 0.55
  local full=CONFIG.belleRunBlendFull or 0.92
  if mag<=start then return 0 end
  if mag>=full then return 1 end
  return smooth01((mag-start)/(full-start))
end

function Renderer:updateBelleLocomotion(player,walking,dt)
  if self.characterId~="BELLESTARMON" then return end
  local target=self:belleRunTarget(player,walking)
  self.belleRunBlend=approachExp(self.belleRunBlend or 0,target,CONFIG.belleRunBlendRate or 7.5,dt or (1/60))
  if self.belleRunBlend<0.0001 then self.belleRunBlend=0 elseif self.belleRunBlend>0.9999 then self.belleRunBlend=1 end
  self.data.runtimeBelleRunBlend=self.belleRunBlend
  local x=tonumber(player and player.red3dMoveStickX) or 0
  local y=tonumber(player and player.red3dMoveStickY) or 0
  self.data.runtimeBelleAnalogMagnitude=math.min(1,math.sqrt(x*x+y*y))
end

function Renderer:cyclePixels()
  if self.characterId=="BELLESTARMON" then
    local rb=self.belleRunBlend or 0
    if rb<0 then rb=0 elseif rb>1 then rb=1 end
    return (CONFIG.belleWalkCyclePixels or 72.0) + ((CONFIG.belleRunCyclePixels or 31.0)-(CONFIG.belleWalkCyclePixels or 72.0))*rb
  end
  if self.data and self.data.runtimeProfile=="RED" then return 34.0 end
  if self.data and self.data.runtimeProfile=="ASH" then return 43.0 end
  if self.data and self.data.runtimeProfile=="BEELSTARMON_MIXAMO" then return 31.0 end
  if self.data and self.data.runtimeProfile=="AANG_MIXAMO" then return 28.0 end
  if self.data and self.data.runtimeProfile=="NARUTO_MIXAMO" then return 22.0 end
  return CONFIG.worldPixelsPerCycle
end

function Renderer:beginVoxelFrame(player,p)
  if not player or not p then return end

  local now=nil
  if love and love.timer and love.timer.getTime then now=love.timer.getTime() end
  local rawWalking=self:motionSample(player,p.px,p.py,now)

  if not now then
    if self.data and self.data.runtimeProfile=="ASH" then
      self.ashIdleTime=(self.ashIdleTime or 0)+(1/60)
      local dur=tonumber(self.data.idleDuration) or 1
      if dur<=0 then dur=1 end
      self.data.runtimeAshIdlePhase=(self.ashIdleTime/dur)%1
    elseif self.data and self.data.runtimeProfile=="AANG_MIXAMO" then
      self.aangIdleTime=(self.aangIdleTime or 0)+(1/60)
      local dur=tonumber(self.data.idleDuration) or 1
      if dur<=0 then dur=1 end
      self.data.runtimeAangIdlePhase=(self.aangIdleTime/dur)%1
    elseif self.data and self.data.runtimeProfile=="CJ_FBX" then
      self.cjIdleTime=(self.cjIdleTime or 0)+(1/60)
      local dur=tonumber(self.data.idleDuration) or 1
      if dur<=0 then dur=1 end
      self.data.runtimeCJIdlePhase=(self.cjIdleTime/dur)%1
    elseif self.data and self.data.runtimeProfile=="YAMI_FBX" then
      self.yamiIdleTime=(self.yamiIdleTime or 0)+(1/60)
      local dur=tonumber(self.data.idleDuration) or 1
      if dur<=0 then dur=1 end
      self.data.runtimeYamiIdlePhase=(self.yamiIdleTime/dur)%1
    elseif self.data and self.data.runtimeProfile=="BEELSTARMON_MIXAMO" then
      self.beelIdleTime=(self.beelIdleTime or 0)+(1/60)
      local dur=tonumber(self.data.idleDuration) or 1
      if dur<=0 then dur=1 end
      self.data.runtimeBeelIdlePhase=(self.beelIdleTime/dur)%1
    elseif self.data and self.data.runtimeProfile=="NARUTO_MIXAMO" then
      self.narutoIdleTime=(self.narutoIdleTime or 0)+(1/60)
      local dur=tonumber(self.data.idleDuration) or 1
      if dur<=0 then dur=1 end
      self.data.runtimeNarutoIdlePhase=(self.narutoIdleTime/dur)%1
    end
    self:updateBelleLocomotion(player,rawWalking,1/60)
    local cyclePixels=self:cyclePixels()
    local phase=(self.characterId=="BELLESTARMON") and (self.belleGaitPhase or 0) or ((self.motionDistance/cyclePixels)%1)
    self.voxelFrameWalking=rawWalking
    self.voxelFrameBlend=rawWalking and 1 or 0
    self.voxelFrameClock=phase*16
    self:updateBeelCloth(1/60,rawWalking)
    self.voxelFrameSerial=self.voxelFrameSerial+1
    self.voxelFrameKey="vf_fallback"..tostring(self.voxelFrameSerial)
    return
  end

  if self.voxelLastTime==nil then
    self.voxelLastTime=now
    self.voxelGaitDistance=self.motionDistance
  end

  local dt=now-self.voxelLastTime
  if dt < 0 then dt=0 end
  if dt > 0.10 then dt=0.10 end
  self.voxelLastTime=now
  if self.data and self.data.runtimeProfile=="ASH" then
    self.ashIdleTime=(self.ashIdleTime or 0)+dt
    local dur=tonumber(self.data.idleDuration) or 1
    if dur<=0 then dur=1 end
    self.data.runtimeAshIdlePhase=(self.ashIdleTime/dur)%1
  elseif self.data and self.data.runtimeProfile=="AANG_MIXAMO" then
    self.aangIdleTime=(self.aangIdleTime or 0)+dt
    local dur=tonumber(self.data.idleDuration) or 1
    if dur<=0 then dur=1 end
    self.data.runtimeAangIdlePhase=(self.aangIdleTime/dur)%1
  elseif self.data and self.data.runtimeProfile=="CJ_FBX" then
    self.cjIdleTime=(self.cjIdleTime or 0)+dt
    local dur=tonumber(self.data.idleDuration) or 1
    if dur<=0 then dur=1 end
    self.data.runtimeCJIdlePhase=(self.cjIdleTime/dur)%1
  elseif self.data and self.data.runtimeProfile=="YAMI_FBX" then
    self.yamiIdleTime=(self.yamiIdleTime or 0)+dt
    local dur=tonumber(self.data.idleDuration) or 1
    if dur<=0 then dur=1 end
    self.data.runtimeYamiIdlePhase=(self.yamiIdleTime/dur)%1
  elseif self.data and self.data.runtimeProfile=="BEELSTARMON_MIXAMO" then
    self.beelIdleTime=(self.beelIdleTime or 0)+dt
    local dur=tonumber(self.data.idleDuration) or 1
    if dur<=0 then dur=1 end
    self.data.runtimeBeelIdlePhase=(self.beelIdleTime/dur)%1
  elseif self.data and self.data.runtimeProfile=="NARUTO_MIXAMO" then
    self.narutoIdleTime=(self.narutoIdleTime or 0)+dt
    local dur=tonumber(self.data.idleDuration) or 1
    if dur<=0 then dur=1 end
    self.data.runtimeNarutoIdlePhase=(self.narutoIdleTime/dur)%1
  end

  if rawWalking then self.voxelLastMovingTime=now end

  -- Preserve movement across the tiny flag seam between adjacent tile steps.
  local walking=rawWalking
  if not walking and self.voxelLastMovingTime
      and (now-self.voxelLastMovingTime) <= CONFIG.seamGrace then
    walking=true
  end

  self:updateBelleLocomotion(player,walking,dt)

  local targetSpeed=0
  if walking then
    local measured=tonumber(self.motionMeasuredSpeed)
    local stepLen=tonumber(player.stepFramesCur) or tonumber(player.stepFrames)
    local nominal=nil
    if stepLen and stepLen > 0 then nominal=16*60/stepLen end

    -- Prefer observed root speed when it is available; this keeps the jog in
    -- sync with Dramatic Shape free movement and other movement-speed mods.
    -- The normal Gen1 step-frame value remains the stable fallback.
    if measured and measured >= 8 and measured <= 240 then
      targetSpeed=measured
    elseif nominal then
      targetSpeed=nominal
    else
      targetSpeed=self.voxelLastSpeed or 60
    end
    if targetSpeed < 8 then targetSpeed=8 elseif targetSpeed > 240 then targetSpeed=240 end
    self.voxelLastSpeed=targetSpeed
  end

  -- Smooth speed and motion weight independently.  On a fresh start, seed
  -- cadence at the actual player speed while pose amplitude fades in from
  -- zero; this feels responsive without popping into a mid-run silhouette.
  if walking and not self.voxelWasMoving then
    self.voxelSmoothSpeed=targetSpeed
  else
    self.voxelSmoothSpeed=approachExp(
      self.voxelSmoothSpeed or 0,targetSpeed,CONFIG.speedResponse,dt)
  end
  local blendTarget=walking and 1 or 0
  local blendRate=walking and CONFIG.startBlendRate or CONFIG.stopBlendRate
  self.voxelMoveBlend=approachExp(
    self.voxelMoveBlend or 0,blendTarget,blendRate,dt)

  -- When starting from a true standstill, begin near a contact pose while the
  -- blend is still almost zero.  This avoids fading into an arbitrary mid-air
  -- pose left over from the previous jog.
  if walking and not self.voxelWasMoving and (self.voxelMoveBlend or 0) < 0.20 then
    if self.characterId=="BELLESTARMON" then
      self.belleGaitPhase=0
    else
      local cyclePixels=self:cyclePixels()
      local cycle=math.floor((self.voxelGaitDistance or 0)/cyclePixels)
      self.voxelGaitDistance=cycle*cyclePixels
    end
  end
  self.voxelWasMoving=walking

  if (self.voxelMoveBlend or 0) > 0.001 then
    local advance=(self.voxelSmoothSpeed or 0)*dt
    self.voxelGaitDistance=self.voxelGaitDistance + advance
    if self.characterId=="BELLESTARMON" then
      local cyclePixels=self:cyclePixels()
      if cyclePixels<1 then cyclePixels=1 end
      self.belleGaitPhase=((self.belleGaitPhase or 0) + advance/cyclePixels)%1
    end
  end

  self.voxelFrameWalking=(self.voxelMoveBlend or 0) > 0.001
  self.voxelFrameBlend=self.voxelMoveBlend or 0
  self:updateBeelCloth(dt,self.voxelFrameWalking)
  self.voxelFrameSerial=self.voxelFrameSerial+1
  local cyclePixels=self:cyclePixels()
  local gaitPhase=(self.characterId=="BELLESTARMON") and (self.belleGaitPhase or 0) or ((self.voxelGaitDistance/cyclePixels)%1)
  self.voxelFrameClock=gaitPhase*16
  self.voxelFrameKey=string.format("vf%d_%.3f",self.voxelFrameSerial,self.voxelFrameBlend)
end

function Renderer:animationState(player,px,py)
  local walking=self:motionSample(player,px,py,nil)
  if not walking then return false,0,"idle" end

  -- Non-voxel fallback remains deterministic and distance-locked.  The voxel
  -- pipeline uses beginVoxelFrame() above for sub-frame interpolation.
  if self.characterId=="BELLESTARMON" then self:updateBelleLocomotion(player,walking,1/60) end
  local cyclePixels=self:cyclePixels()
  local phase=(self.motionDistance/cyclePixels)%1
  local clock=phase*16
  return true,clock,string.format("move%.5f",phase)
end

function Renderer:updateSkeleton(player,walking,clock,motionBlend)
  local d=self.data
  local phase=(clock%16)/16*math.pi*2
  local walkSin=math.sin(phase)
  local walkCos=math.cos(phase)
  local bounce=0.5-0.5*math.cos(phase*2)
  local jumpT=jumpProgress(player)
  local shootT=shootProgress(player)
  if d.runtimeProfile=="BEELSTARMON" then d.runtimeCloth=self.beelCloth end

  for i=1,d.boneCount do
    local bind=self.bindLocal[i]
    local delta
    if shootT and d.runtimeProfile=="CJ" then
      delta=shootBoneDelta(d,i,shootT)
      if not delta then
        delta=adsBoneDelta(d,i,1.0)
      end
      if not delta then
        delta=boneDelta(d,i,phase,walkSin,walkCos,bounce,walking,math.min(motionBlend or 0,0.10))
      end
    elseif d.runtimeProfile=="CJ" and player and player.red3dADS then
      delta=adsBoneDelta(d,i,1.0)
      if not delta then
        delta=boneDelta(d,i,phase,walkSin,walkCos,bounce,walking,math.min(motionBlend or 0,0.08))
      end
    elseif jumpT then
      if d.runtimeProfile=="ASH" then
        delta=ashJumpDelta(d,i,jumpT,wrap01(phase/(math.pi*2)),motionBlend or 0)
      elseif self.characterId=="BELLESTARMON" then
        delta=belleJumpDelta(d,i,jumpT,wrap01(phase/(math.pi*2)),motionBlend or 0)
      elseif d.runtimeProfile=="AANG_MIXAMO" then
        delta=aangJumpDelta(d,i,jumpT,wrap01(phase/(math.pi*2)),motionBlend or 0)
      elseif d.runtimeProfile=="CJ_FBX" then
        delta=cjJumpDelta(d,i,jumpT,wrap01(phase/(math.pi*2)),motionBlend or 0)
      elseif d.runtimeProfile=="YAMI_FBX" then
        delta=yamiJumpDelta(d,i,jumpT,wrap01(phase/(math.pi*2)),motionBlend or 0)
      elseif d.runtimeProfile=="NARUTO_MIXAMO" then
        delta=narutoJumpDelta(d,i,jumpT,wrap01(phase/(math.pi*2)),motionBlend or 0)
      elseif d.runtimeProfile=="BEELSTARMON_MIXAMO" then
        delta=beelJumpDelta(d,i,jumpT,wrap01(phase/(math.pi*2)),motionBlend or 0)
      else
        delta=jumpBoneDelta(d,i,jumpT)
        -- Keep the refined relaxed hands/fingers and backpack alive during the
        -- hop when the dedicated jump pose does not override that bone.
        if not delta then
          delta=boneDelta(d,i,phase,walkSin,walkCos,bounce,walking,0.22)
        end
      end
    else
      delta=boneDelta(d,i,phase,walkSin,walkCos,bounce,walking,motionBlend)
    end

    -- Aang hard armature guard. The source skeleton uses mirrored local upper-arm
    -- axes, and host/build differences in the animation path can otherwise leave
    -- an older/generic Red-style delta active and throw both hands over his head.
    -- Override the final upper-arm/elbow deltas here, after every walk/jump path,
    -- so Aang always receives a known-good relaxed pose in overworld rendering.
    if d.runtimeProfile=="AANG" then
      local A=d.animBone
      if i==A.LArm then
        delta=rotZ(math.rad(d.runtimeArmRest or 70))
      elseif i==A.RArm then
        delta=rotZ(math.rad(-(d.runtimeArmRest or 70)))
      elseif i==A.LForeArm then
        delta=rotZ(math.rad(4))
      elseif i==A.RForeArm then
        delta=rotZ(math.rad(-4))
      end
    end

    local localM
    if delta then
      localM=self.localWork[i]
      mul16(bind,delta,localM)
    else
      localM=bind
    end
    local parent=d.boneParent[i]
    if parent and parent>0 then
      mul16(self.world[parent],localM,self.world[i])
    else
      local w=self.world[i]
      for k=1,16 do w[k]=localM[k] end
    end
  end
end

function Renderer:skin()
  local d=self.data
  -- Hot-loop localization matters on the large imported rigs. Avoid repeated
  -- table-field lookups and handle the common 1/2-influence vertices directly;
  -- Yami has more than 22k positions in those two fast paths alone.
  local posFirst,posCount=d.posFirst,d.posCount
  local infBone,infX,infY,infZ,infW=d.infBone,d.infX,d.infY,d.infZ,d.infW
  local world=self.world
  local sx,sy,sz=self.sx,self.sy,self.sz
  local zUp=self.postSkinZUp
  local tp=transformPoint
  for i=1,d.positionCount do
    local first=posFirst[i]
    local count=posCount[i]
    local x,y,z
    if count==1 then
      local j=first
      local tx,ty,tz=tp(world[infBone[j]],infX[j],infY[j],infZ[j])
      local w=infW[j]
      x,y,z=tx*w,ty*w,tz*w
    elseif count==2 then
      local j1,j2=first,first+1
      local tx1,ty1,tz1=tp(world[infBone[j1]],infX[j1],infY[j1],infZ[j1])
      local tx2,ty2,tz2=tp(world[infBone[j2]],infX[j2],infY[j2],infZ[j2])
      local w1,w2=infW[j1],infW[j2]
      x=tx1*w1+tx2*w2
      y=ty1*w1+ty2*w2
      z=tz1*w1+tz2*w2
    else
      x,y,z=0,0,0
      for j=first,first+count-1 do
        local tx,ty,tz=tp(world[infBone[j]],infX[j],infY[j],infZ[j])
        local w=infW[j]
        x=x+tx*w; y=y+ty*w; z=z+tz*w
      end
    end
    if zUp then
      -- Some imported GTA/FBX rigs are skinned in Z-up source space.
      x,y,z=x,z,-y
    end
    sx[i],sy[i],sz[i]=x,y,z
  end
end

function Renderer:ensureSkinned(player,px,py,useVoxelFrame)
  local walking,clock,key,motionBlend
  if useVoxelFrame and self.voxelFrameKey then
    walking=self.voxelFrameWalking
    clock=self.voxelFrameClock or 0
    key=self.voxelFrameKey
    motionBlend=self.voxelFrameBlend or (walking and 1 or 0)
  else
    walking,clock,key=self:animationState(player,px,py)
    motionBlend=walking and 1 or 0
  end
  local jumpT=jumpProgress(player)
  if jumpT then key=key..string.format("_hop%.4f",jumpT) end
  if not useVoxelFrame and self.data and self.data.runtimeProfile=="ASH" then
    local now=(love and love.timer and love.timer.getTime) and love.timer.getTime() or nil
    local dt=1/60
    if now and self.ashIdleLastTime then dt=now-self.ashIdleLastTime end
    if dt<0 then dt=0 elseif dt>0.10 then dt=0.10 end
    if now then self.ashIdleLastTime=now end
    self.ashIdleTime=(self.ashIdleTime or 0)+dt
    local dur=tonumber(self.data.idleDuration) or 1
    if dur<=0 then dur=1 end
    self.data.runtimeAshIdlePhase=(self.ashIdleTime/dur)%1
    key=key..string.format("_idle%.3f",self.data.runtimeAshIdlePhase)
  end
  if not useVoxelFrame and self.data and self.data.runtimeProfile=="AANG_MIXAMO" then
    local now=(love and love.timer and love.timer.getTime) and love.timer.getTime() or nil
    local dt=1/60
    if now and self.aangIdleLastTime then dt=now-self.aangIdleLastTime end
    if dt<0 then dt=0 elseif dt>0.10 then dt=0.10 end
    if now then self.aangIdleLastTime=now end
    self.aangIdleTime=(self.aangIdleTime or 0)+dt
    local dur=tonumber(self.data.idleDuration) or 1
    if dur<=0 then dur=1 end
    self.data.runtimeAangIdlePhase=(self.aangIdleTime/dur)%1
    key=key..string.format("_aangidle%.3f",self.data.runtimeAangIdlePhase)
  end
  if not useVoxelFrame and self.data and self.data.runtimeProfile=="CJ_FBX" then
    local now=(love and love.timer and love.timer.getTime) and love.timer.getTime() or nil
    local dt=1/60
    if now and self.cjIdleLastTime then dt=now-self.cjIdleLastTime end
    if dt<0 then dt=0 elseif dt>0.10 then dt=0.10 end
    if now then self.cjIdleLastTime=now end
    self.cjIdleTime=(self.cjIdleTime or 0)+dt
    local dur=tonumber(self.data.idleDuration) or 1
    if dur<=0 then dur=1 end
    self.data.runtimeCJIdlePhase=(self.cjIdleTime/dur)%1
    key=key..string.format("_cjidle%.3f",self.data.runtimeCJIdlePhase)
  end
  if not useVoxelFrame and self.data and self.data.runtimeProfile=="YAMI_FBX" then
    local now=(love and love.timer and love.timer.getTime) and love.timer.getTime() or nil
    local dt=1/60
    if now and self.yamiIdleLastTime then dt=now-self.yamiIdleLastTime end
    if dt<0 then dt=0 elseif dt>0.10 then dt=0.10 end
    if now then self.yamiIdleLastTime=now end
    self.yamiIdleTime=(self.yamiIdleTime or 0)+dt
    local dur=tonumber(self.data.idleDuration) or 1
    if dur<=0 then dur=1 end
    self.data.runtimeYamiIdlePhase=(self.yamiIdleTime/dur)%1
    key=key..string.format("_yamiidle%.3f",self.data.runtimeYamiIdlePhase)
  end
  if not useVoxelFrame and self.data and self.data.runtimeProfile=="NARUTO_MIXAMO" then
    local now=(love and love.timer and love.timer.getTime) and love.timer.getTime() or nil
    local dt=1/60
    if now and self.narutoIdleLastTime then dt=now-self.narutoIdleLastTime end
    if dt<0 then dt=0 elseif dt>0.10 then dt=0.10 end
    if now then self.narutoIdleLastTime=now end
    self.narutoIdleTime=(self.narutoIdleTime or 0)+dt
    local dur=tonumber(self.data.idleDuration) or 1
    if dur<=0 then dur=1 end
    self.data.runtimeNarutoIdlePhase=(self.narutoIdleTime/dur)%1
    key=key..string.format("_narutoidle%.3f",self.data.runtimeNarutoIdlePhase)
  end
  if not useVoxelFrame and self.data and self.data.runtimeProfile=="BEELSTARMON_MIXAMO" then
    local now=(love and love.timer and love.timer.getTime) and love.timer.getTime() or nil
    local dt=1/60
    if now and self.beelIdleLastTime then dt=now-self.beelIdleLastTime end
    if dt<0 then dt=0 elseif dt>0.10 then dt=0.10 end
    if now then self.beelIdleLastTime=now end
    self.beelIdleTime=(self.beelIdleTime or 0)+dt
    local dur=tonumber(self.data.idleDuration) or 1
    if dur<=0 then dur=1 end
    self.data.runtimeBeelIdlePhase=(self.beelIdleTime/dur)%1
    key=key..string.format("_beelidle%.3f",self.data.runtimeBeelIdlePhase)
  end
  if not useVoxelFrame and self.data and self.data.runtimeProfile=="BEELSTARMON" then
    local now=(love and love.timer and love.timer.getTime) and love.timer.getTime() or nil
    local dt=1/60
    if now and self.beelClothLastTime then dt=now-self.beelClothLastTime end
    if now then self.beelClothLastTime=now end
    self:updateBeelCloth(dt,walking)
  end
  if key==self.skinKey then return key end
  self:updateSkeleton(player,walking,clock,motionBlend)
  self:skin()
  self.skinKey=key
  return key
end

local YAW={down=0,left=-math.pi/2,up=math.pi,right=math.pi/2}

local function atan2(y,x)
  if math.atan2 then return math.atan2(y,x) end
  return math.atan(y,x)
end

function Renderer:project(px,py,camX,camY,facing)
  local yaw=YAW[facing] or 0
  local c,s=math.cos(yaw),math.sin(yaw)
  local footX=math.floor(px-camX)+8
  local footY=math.floor(py-camY)+12
  local sc=self.scale
  for i=1,self.data.positionCount do
    local x,z=self.sx[i],self.sz[i]
    local xr=c*x+s*z
    local zr=-s*x+c*z
    self.screenX[i]=footX+xr*sc
    self.screenY[i]=footY-(self.sy[i]-self.minY)*sc+zr*sc*CONFIG.depthSlope
  end
end

function Renderer:updateMesh(facing)
  local rows=self.vertexRows
  for i=1,self.renderVertexCount do
    local p=self.vertexPos[i]
    local row=rows[i]
    row[1]=self.screenX[p]
    row[2]=self.screenY[p]
  end
  self.mesh:setVertices(rows)
  if facing~=self.lastFacing then
    self.mesh:setVertexMap(self.maps[facing] or self.maps.down)
    self.lastFacing=facing
  end
end

function Renderer:draw(player,px,py,camX,camY,facing)
  if self.failed or not self:ensureGraphics() then return false end
  self:ensureSkinned(player,px,py)
  local visualPy=py-manualJumpLift(player)
  self:project(px,visualPy,camX,camY,facing)
  self:updateMesh(facing)

  -- Custom RGB textures should not be re-shaded as Game Boy background tiles.
  local okPF,PaletteFX=pcall(require,"src.render.PaletteFX")
  if okPF and PaletteFX and PaletteFX.markTrueColor then
    local x=math.floor(px-camX)+8-18
    local y=math.floor(py-camY)+12-CONFIG.height-5
    pcall(PaletteFX.markTrueColor,x,y,36,CONFIG.height+10)
  end

  love.graphics.push("all")
  love.graphics.setColor(1,1,1,1)
  love.graphics.setBlendMode("alpha")
  love.graphics.draw(self.mesh)
  love.graphics.pop()
  return true
end

local function playerUsesSpecialCard(player)
  return player and (player.fishing or player.surfing or player.onBike)
end

function Renderer:updateVoxelMesh(player,p,Voxel3D)
  if not self:ensureVoxelGraphics(Voxel3D) then return false end
  local key=self:ensureSkinned(player,p and p.px,p and p.py,true)
  if key==self.voxelUploadedKey then return true end

  local rows=self.voxelRows
  for i=1,self.renderVertexCount do
    local p=self.vertexPos[i]
    local row=rows[i]
    row[1]=self.sx[p]
    row[2]=self.sy[p]
    row[3]=self.sz[p]
  end
  local ok,err=pcall(self.voxelMesh.setVertices,self.voxelMesh,rows)
  if not ok then
    self.mod.log:error("Dramatic Shape Red mesh update failed: %s",tostring(err))
    self.voxelFailed=true
    return false
  end
  self.voxelUploadedKey=key
  return true
end

function Renderer:voxelModelMatrix(player,p,Mat4,FirstPerson)
  -- True 360-degree travel-facing for the real 3D body.
  --
  -- Do not depend on Dramatic Shape's bodyYaw here: that value intentionally
  -- returns to camera-forward while standing. Also do not depend solely on
  -- moveVector(), because older/newer Dramatic Shape builds can expose the
  -- private FirstPerson module differently through the bridge. Instead use
  -- the player's ACTUAL world-space displacement, which is the final truth
  -- after camera-relative input, collision sliding, keyboard, analog stick,
  -- touch input, etc.
  --
  -- A moving player updates the continuous yaw from delta-X/delta-Z. When the
  -- player stops, the last yaw is retained exactly, so orbiting the camera does
  -- not snap the body forward. Large discontinuities are treated as warps and
  -- do not make the model face along the teleport vector.
  local liveYaw=nil
  if player and p then
    local x=tonumber(p.px) or 0
    local z=tonumber(p.py) or 0
    local lx=player.red3dLastWorldX
    local lz=player.red3dLastWorldZ

    if lx~=nil and lz~=nil then
      local dx=x-lx
      local dz=z-lz
      local d2=dx*dx+dz*dz
      -- Tiny threshold rejects floating-point jitter. 64 px^2 rejects a
      -- one-cell/warp discontinuity while comfortably accepting free-walk
      -- subpixel motion at any angle.
      if d2>0.000001 and d2<64 then
        liveYaw=atan2(dx,dz)
        player.red3dFreeBodyYaw=liveYaw
      end
    end

    -- Only advance the sampled position when it really changed. drawVoxel and
    -- drawVoxelShadow can both ask for a model matrix in the same frame; this
    -- keeps the shadow pass from turning a valid movement delta into a zero one.
    if lx==nil or lz==nil or x~=lx or z~=lz then
      player.red3dLastWorldX=x
      player.red3dLastWorldZ=z
    end

    if liveYaw==nil then
      if player.red3dFreeBodyYaw==nil then
        player.red3dFreeBodyYaw=YAW[p.facing] or (FirstPerson and tonumber(FirstPerson.yaw)) or 0
      end
      liveYaw=player.red3dFreeBodyYaw
    end
  end

  -- CJ aiming remains an explicit body-facing override while ADS.
  if self.characterId=="CJ" and player and player.red3dADS and player.red3dAimBodyYaw~=nil then
    liveYaw=player.red3dAimBodyYaw
    player.red3dFreeBodyYaw=liveYaw
  end

  local yaw=(liveYaw or YAW[p.facing] or 0)+self.modelYawOffset
  local m=Mat4.translate(p.px+8,p.gh+(p.lift or 0)+manualJumpLift(player)+CONFIG.groundClearance,p.py+8)
  if yaw~=0 then m=Mat4.mul(m,Mat4.rotateY(yaw)) end
  m=Mat4.mul(m,Mat4.scale(self.scale,self.scale,self.scale))
  m=Mat4.mul(m,Mat4.translate(-self.centerX,-self.minY,-self.centerZ))
  return m
end

function Renderer:drawVoxel(player,p,Voxel3D,Mat4,FirstPerson)
  if self.voxelFailed or playerUsesSpecialCard(player) then return false end
  if not self:updateVoxelMesh(player,p,Voxel3D) then return false end
  local model=self:voxelModelMatrix(player,p,Mat4,FirstPerson)
  -- Custom character UVs are unrelated to Dramatic Shape's tileset atlas.
  -- Its glass mask intentionally paints matching atlas coordinates with warm
  -- window lamplight at night, which shows up as random yellow polygons on
  -- imported models. Force that tileset-only effect OFF at the actual custom
  -- mesh draw rather than trying to edit the character texture around it.
  if Voxel3D.glass then pcall(Voxel3D.glass,false) end
  -- Real geometry does not need the camera-ward depth pull used to make a
  -- leaning sprite card win against the wall it visually leans over.
  Voxel3D.draw(self.voxelMesh,self.image,model,nil,model)
  return true
end

function Renderer:drawVoxelShadow(player,p,Voxel3D,Mat4,ShadowMap,FirstPerson)
  if self.voxelFailed or playerUsesSpecialCard(player) then return false end
  if not self:updateVoxelMesh(player,p,Voxel3D) then return false end
  local model=self:voxelModelMatrix(player,p,Mat4,FirstPerson)
  ShadowMap.draw(self.voxelMesh,self.image,model)
  return true
end

-- Battle-intro pointing gesture.  The trainer appears only during Dramatic
-- Shape's intro stage, so animate quickly into a clear point and hold it until
-- the battle renderer swaps Red out for the player's Pokemon.
local function battlePointEase(t)
  if t<=0 then return 0 end
  if t>=1 then return 1 end
  return t*t*(3-2*t)
end

local function battlePointDelta(data,bone,amount)
  local A=data.animBone
  local a=battlePointEase(amount or 0)

  -- Keep the left arm relaxed while the right arm points toward the enemy.
  if bone==A.Spine2 then
    return rotZ(math.rad(-2.2*a))
  elseif bone==A.Spine3 then
    return compose(rotY(math.rad(4.0*a)),rotZ(math.rad(-2.8*a)))
  elseif bone==A.Neck then
    return rotY(math.rad(-2.2*a))
  elseif bone==A.Head then
    return compose(rotY(math.rad(-3.0*a)),rotZ(math.rad(1.2*a)))
  elseif bone==A.LArm then
    if data.runtimeProfile=="AANG" then
      -- Aang's upper-arm local Z axes are mirrored relative to Red's.  The
      -- generic battle pose used the Red sign here, which flips the relaxed
      -- arm upward over his head.  Keep the same Aang-specific arm drop used
      -- by normal movement and only add a very small battle settle.
      local rest=rotZ(math.rad(data.runtimeArmRest or 70))
      return compose(rotY(math.rad(-3*a)),rest)
    end
    return compose(rotZ(math.rad(-(data.runtimeArmRest or CONFIG.armRestDeg))),rotY(math.rad(-7*a)))
  elseif bone==A.LForeArm then
    if data.runtimeProfile=="AANG" then
      -- Aang's elbow hinge is local Z, not Red's local Y.
      return rotZ(math.rad(6 - 2*a))
    end
    return rotY(math.rad(-10))
  elseif bone==A.RShoulder then
    return compose(rotY(math.rad(-6.0*a)),rotZ(math.rad(2.0*a)))
  elseif bone==A.RArm then
    if data.runtimeProfile=="NARUTO" then
      local rest=rotAxis(0.12191,-0.07037,-0.99004,math.rad(70))
      local point=rotAxis(0.35474,-0.92851,0.10968,math.rad(-38*a))
      return compose(rest,point)
    elseif data.runtimeProfile=="AANG" then
      -- Start from Aang's correct arms-down bind adjustment, then lift the
      -- right arm toward a forward point.  Driving the lift around local Z
      -- avoids the inverted/over-head armature pose shown by the generic Red
      -- battle transform; local Y supplies only the forward reach.
      local rest=data.runtimeArmRest or 70
      local lift=-rest + 100*a
      return compose(rotY(math.rad(-52*a)),rotZ(math.rad(lift)))
    end
    -- Rest the T-pose arm downward, then drive it forward to roughly shoulder
    -- height.  The elbow finishes the line rather than locking instantly.
    return compose(rotZ(math.rad(data.runtimeArmRest or CONFIG.armRestDeg)),rotY(math.rad(-64*a)))
  elseif bone==A.RForeArm then
    local elbow=12 + (4-12)*a
    if data.runtimeProfile=="NARUTO" then
      return rotAxis(0.35474,-0.92851,0.10968,math.rad(-elbow*0.30))
    elseif data.runtimeProfile=="AANG" then
      -- Match Aang's mirrored local-Z elbow hinge and gradually straighten it
      -- as the pointing arm rises.
      return rotZ(math.rad(-(6 - 4*a)))
    end
    return compose(rotY(math.rad(-elbow)),rotX(math.rad(-2.5*a)))
  elseif bone==A.RHand then
    if data.runtimeProfile=="NARUTO" or data.runtimeProfile=="AANG" then return nil end
    return compose3(rotX(math.rad(-3*a)),rotY(math.rad(-5*a)),rotZ(math.rad(2*a)))

  -- Right index finger points.  Middle/ring/pinky fold into a loose fist and
  -- the thumb rests across them; this reads much better than a flat hand.
  elseif bone==A.RFingerA1 then
    return compose(rotY(math.rad(5*a)),rotZ(math.rad(10+8*a)))
  elseif bone==A.RFingerA2 then
    return rotZ(math.rad(7+7*a))
  elseif bone==A.RFingerA3 then
    return rotZ(math.rad(4+4*a))
  elseif bone==A.RFingerB1 then
    return rotZ(math.rad(8*(1-a)))
  elseif bone==A.RFingerB2 then
    return rotZ(math.rad(5*(1-a)))
  elseif bone==A.RFingerB3 then
    return rotZ(math.rad(3*(1-a)))
  elseif bone==A.RFingerC1 then
    return rotZ(math.rad(12+26*a))
  elseif bone==A.RFingerC2 then
    return rotZ(math.rad(9+30*a))
  elseif bone==A.RFingerC3 then
    return rotZ(math.rad(6+22*a))
  elseif bone==A.RFingerD1 then
    return rotZ(math.rad(15+30*a))
  elseif bone==A.RFingerD2 then
    return rotZ(math.rad(11+34*a))
  elseif bone==A.RFingerD3 then
    return rotZ(math.rad(7+24*a))
  elseif bone==A.RFingerE1 then
    return rotZ(math.rad(17+31*a))
  elseif bone==A.RFingerE2 then
    return rotZ(math.rad(13+35*a))
  elseif bone==A.RFingerE3 then
    return rotZ(math.rad(8+25*a))
  end
  return nil
end

function Renderer:updateBattleSkeleton(amount)
  local d=self.data
  for i=1,d.boneCount do
    local bind=self.bindLocal[i]
    local delta
    if d.runtimeProfile=="AANG_MIXAMO" then
      -- The replacement Aang ships with an authored Standing Idle. Keep that
      -- exact pose in the trainer battle intro instead of feeding the new
      -- Mixamo armature through the legacy Red/Aang pointing transforms.
      delta=aangIdleDelta(d,i)
    else
      delta=battlePointDelta(d,i,amount)
    end

    -- Keep Aang completely out of the generic trainer pointing arm chain.
    -- This deliberately favors a stable, natural arms-down stance over the
    -- pointing gesture until/if a bespoke Aang battle animation is authored.
    -- Applying this at the final battle skeleton stage makes the fix independent
    -- of hook order, intro timing, and any stale/generic pose calculation.
    if d.runtimeProfile=="AANG" then
      local A=d.animBone
      if i==A.LArm then
        delta=rotZ(math.rad(d.runtimeArmRest or 70))
      elseif i==A.RArm then
        delta=rotZ(math.rad(-(d.runtimeArmRest or 70)))
      elseif i==A.LForeArm then
        delta=rotZ(math.rad(4))
      elseif i==A.RForeArm then
        delta=rotZ(math.rad(-4))
      end
    end

    local localM
    if delta then
      localM=self.localWork[i]
      mul16(bind,delta,localM)
    else
      -- Preserve the normal relaxed arms-down idle for bones not explicitly
      -- animated by the point pose.
      local idle=boneDelta(d,i,0,0,1,0,false,0)
      if idle then
        localM=self.localWork[i]
        mul16(bind,idle,localM)
      else
        localM=bind
      end
    end
    local parent=d.boneParent[i]
    if parent and parent>0 then
      mul16(self.world[parent],localM,self.world[i])
    else
      local w=self.world[i]
      for k=1,16 do w[k]=localM[k] end
    end
  end
end

-- Dramatic Shape battle arenas normally render the player's trainer-back pic
-- as a flat BattleBillboard card.  This matrix places the same skinned Red
-- mesh on that player battle cell and turns him toward the enemy cell.
function Renderer:battleModelMatrix(arena,groundY,Mat4)
  if not (arena and arena.player) then return nil end
  local px,pz=arena.player[1],arena.player[2]
  local ex,ez=px,pz+1
  if arena.enemy then ex,ez=arena.enemy[1],arena.enemy[2] end
  local yaw=atan2(ex-px,ez-pz)+self.modelYawOffset
  local m=Mat4.translate(px,(groundY or 0)+CONFIG.groundClearance,pz)
  if yaw~=0 then m=Mat4.mul(m,Mat4.rotateY(yaw)) end
  m=Mat4.mul(m,Mat4.scale(self.scale,self.scale,self.scale))
  m=Mat4.mul(m,Mat4.translate(-self.centerX,-self.minY,-self.centerZ))
  return m
end

function Renderer:prepareBattleMesh(player,Voxel3D,pointAmount)
  if not self:ensureVoxelGraphics(Voxel3D) then return false end
  -- Battles use a stable trainer stance.  Clear any stale overworld motion
  -- cache and skin an idle pose so the model never freezes on a run/jump key.
  local oldMoving=player and player.moving
  local oldHop=player and player.hopFrames
  local oldManual=player and player.red3dManualJumpFrames
  if player then
    player.moving=false
    player.hopFrames=nil
    player.red3dManualJumpFrames=nil
  end
  self.skinKey=nil
  self.voxelFrameKey=nil
  self:updateBattleSkeleton(pointAmount or 0)
  self:skin()
  if player then
    player.moving=oldMoving
    player.hopFrames=oldHop
    player.red3dManualJumpFrames=oldManual
  end
  local rows=self.voxelRows
  for i=1,self.renderVertexCount do
    local pos=self.vertexPos[i]
    local row=rows[i]
    row[1]=self.sx[pos]
    row[2]=self.sy[pos]
    row[3]=self.sz[pos]
  end
  local ok,err=pcall(self.voxelMesh.setVertices,self.voxelMesh,rows)
  if not ok then
    self.mod.log:error("battle Red mesh update failed: %s",tostring(err))
    return false
  end
  self.voxelUploadedKey=nil
  return true
end

local ActiveRenderer = {}

function ActiveRenderer.new(renderers,activeId)
  local self={renderers=renderers,activeId=activeId}
  return setmetatable(self,{
    __index=function(t,k)
      local own=ActiveRenderer[k]
      if own then return own end
      local r=t.renderers[t.activeId]
      if not r then return nil end
      local v=r[k]
      if type(v)=="function" then
        return function(_,...) return v(r,...) end
      end
      return v
    end,
    __newindex=function(t,k,v)
      if k=="activeId" or k=="renderers" or k=="voxelBridgeInstalled" or k=="voxelBridge" or k=="voxelChunkMesher" then
        rawset(t,k,v)
        return
      end
      local r=t.renderers[rawget(t,"activeId")]
      if r then r[k]=v else rawset(t,k,v) end
    end,
  })
end

function ActiveRenderer:setActive(id)
  if not self.renderers[id] then return false end
  if self.activeId==id then return true end
  self.activeId=id
  local r=self.renderers[id]
  r.skinKey=nil
  r.voxelUploadedKey=nil
  r.voxelFrameKey=nil
  r.voxelFrameSerial=(r.voxelFrameSerial or 0)+1
  return true
end

function ActiveRenderer:getActive()
  return self.renderers[self.activeId]
end

local function drawHopShadow(player,camX,camY,GameVersion)
  if not player.shadowImg then return end
  local yellow=GameVersion.isYellow()
  local sx=math.floor(player.px-camX)
  local sy=math.floor(player.py-camY)-4+8+(yellow and 4 or 0)
  love.graphics.draw(player.shadowImg,sx,sy)
  love.graphics.draw(player.shadowImg,sx+16,sy,0,-1,1)
  if not yellow then
    love.graphics.draw(player.shadowImg,sx,sy+16,0,1,-1)
    love.graphics.draw(player.shadowImg,sx+16,sy+16,0,-1,-1)
  end
end

-- ---------- Dramatic Shape voxel bridge

local function findUpvalue(fn,wanted)
  if type(fn)~="function" or not (debug and debug.getupvalue) then return nil,nil end
  for i=1,100 do
    local name,value=debug.getupvalue(fn,i)
    if not name then break end
    if name==wanted then return i,value end
  end
  return nil,nil
end

local function setUpvalue(fn,index,value)
  if not (debug and debug.setupvalue) or not index then return false end
  return debug.setupvalue(fn,index,value)~=nil
end

local function playerPose(posed)
  for _,p in ipairs(posed or {}) do
    if p.isPlayer then return p end
  end
  return nil
end

local function installVoxelBridge(mod,renderer)
  if renderer.voxelBridgeInstalled then return true end
  if not (debug and debug.getupvalue and debug.setupvalue) then
    mod.log:warn("Dramatic Shape bridge unavailable: Lua debug upvalue API is disabled")
    return false
  end

  local okP,Pipelines=pcall(require,"src.render.Pipelines")
  if not okP or not Pipelines or not Pipelines.get then return false end
  local voxelDef=Pipelines.get("voxel")
  if type(voxelDef)~="table" or type(voxelDef.drawWorld)~="function" then
    -- Dramatic Shape is optional.  Its pipeline simply does not exist when
    -- the user has not installed/enabled it.
    return false
  end

  -- The registered drawWorld closure captures the private Dramatic Shape
  -- modules.  Pull those exact module tables out of the closure so this
  -- companion mod stays inside the currently installed version instead of
  -- bundling a stale copy of its renderer.
  local _,VoxelScene=findUpvalue(voxelDef.drawWorld,"VoxelScene")
  local _,Voxel3D=findUpvalue(voxelDef.drawWorld,"Voxel3D")
  local _,ChunkMesher=findUpvalue(voxelDef.drawWorld,"ChunkMesher")
  if type(VoxelScene)~="table" or type(VoxelScene.render)~="function"
      or type(Voxel3D)~="table" then
    mod.log:warn("Dramatic Shape voxel pipeline found, but its renderer layout is not compatible with 3D Character Selector v2.4.0")
    return false
  end
  if VoxelScene.red3dPlayerBridgeInstalled then
    renderer.voxelBridgeInstalled=true
    renderer.voxelBridge=VoxelScene.red3dPlayerBridge
    renderer.voxelChunkMesher=ChunkMesher
    return true
  end

  local render=VoxelScene.render
  local drawCastIndex,originalDrawCast=findUpvalue(render,"drawCast")
  local castShadowIndex,originalCastShadows=findUpvalue(render,"castShadows")
  local drawGhostIndex,originalDrawGhost=findUpvalue(render,"drawGhost")
  if not drawCastIndex or type(originalDrawCast)~="function" then
    mod.log:warn("Dramatic Shape drawCast hook point was not found; voxel player remains its stock sprite card")
    return false
  end

  local drawEntityIndex,originalDrawEntity=findUpvalue(originalDrawCast,"drawEntity")
  local _,Mat4=findUpvalue(originalDrawEntity,"Mat4")
  local FirstPerson=nil
  local _,billboardMatrix=findUpvalue(originalDrawEntity,"billboardMatrix")
  if type(billboardMatrix)=="function" then
    local _,fp=findUpvalue(billboardMatrix,"FirstPerson")
    FirstPerson=fp
  end
  local ThirdPerson=nil
  local VoxelState=nil
  if type(FirstPerson)=="table" then
    if type(FirstPerson.frame)=="function" then
      local _,tp=findUpvalue(FirstPerson.frame,"ThirdPerson")
      ThirdPerson=tp
    end
    if type(FirstPerson.engaged)=="function" then
      local _,vs=findUpvalue(FirstPerson.engaged,"Voxel")
      VoxelState=vs
    end
  end
  if type(Mat4)~="table" then
    -- Current Dramatic Shape's drawEntity calls billboardMatrix(), and that
    -- helper owns Mat4.  Walk that one extra closure rather than assuming
    -- drawEntity captures Mat4 directly.
    if type(billboardMatrix)=="function" then
      local _,m=findUpvalue(billboardMatrix,"Mat4")
      Mat4=m
    end
  end
  if type(Mat4)~="table" or not Mat4.translate or not Mat4.mul
      or not Mat4.scale or not Mat4.rotateY then
    -- render also references Mat4 while drawing neighbour meshes in current
    -- builds; keep this as a compatibility fallback for nearby revisions.
    local _,m=findUpvalue(render,"Mat4")
    Mat4=m
  end
  if not drawEntityIndex or type(originalDrawEntity)~="function" or type(Mat4)~="table" then
    mod.log:warn("Dramatic Shape character hook point was not found; voxel player remains its stock sprite card")
    return false
  end

  local bridge={
    currentPose=nil,
    currentPlayer=nil,
    renderer=renderer,
    VoxelScene=VoxelScene,
    Voxel3D=Voxel3D,
    Mat4=Mat4,
    FirstPerson=FirstPerson,
    ThirdPerson=ThirdPerson,
    VoxelState=VoxelState,
    disabled=false,
    loggedDrawError=false,
    loggedShadowError=false,
    -- Terrain meshes are texture-agnostic in Dramatic Shape; VoxelScene
    -- supplies TerrainAtlas.forMap(...) separately on each draw. Cache that
    -- exact live image so fractured geometry samples the same atlas as the
    -- intact environment instead of relying on Mesh:getTexture state.
    terrainAtlasByMesh=setmetatable({}, {__mode="k"}),
    terrainAtlasByMap={},
  }

  -- CJ ADS camera: use Dramatic Shape's placed-camera seam instead of
  -- fighting the ordinary map camera.  This leaves the user's VOXEL level
  -- untouched, but while L2/LT is held it smoothly blends to a collision-aware
  -- over-the-shoulder camera whose centre ray is the weapon's aim direction.
  if type(FirstPerson)=="table" and type(FirstPerson.frame)=="function"
      and not FirstPerson.red3dCJAimCameraInstalled then
    FirstPerson.red3dCJAimCameraInstalled=true
    local originalFPFrame=FirstPerson.frame
    local function mix3(a,b,t)
      return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t}
    end
    local function ease01(t)
      if t<=0 then return 0 elseif t>=1 then return 1 end
      return t*t*(3-2*t)
    end
    local function orbitRig(cx,cy,vh)
      local a=(VoxelState and VoxelState.angle) or math.rad(35)
      local focal=(VoxelState and VoxelState.FOCAL) or 1.0
      local dist=focal*vh
      return {
        eye={cx,dist*math.cos(a),cy+dist*math.sin(a)},
        focus={cx,0,cy},
        fov=2*math.atan(1/(2*focal)),
        up={0,math.sin(a),-math.cos(a)},
        curve=nil,
      }
    end
    FirstPerson.frame=function(me,cx,cy,vw,vh)
      local baseRig,baseCx,baseCy=originalFPFrame(me,cx,cy,vw,vh)
      local okG,Game=pcall(require,"src.core.Game")
      local ow=okG and Game and Game.stack and Game.stack:top() or nil
      if not (ow and ow.isOverworld) then ow=okG and Game and Game.overworld or nil end
      local player=ow and ow.player or nil
      local active=renderer:getActive()
      local b=player and tonumber(player.red3dAimCamBlend) or 0
      if not (player and me and active and active.characterId=="CJ" and b and b>0.001) then
        return baseRig,baseCx,baseCy
      end

      local yaw=tonumber(player.red3dAimYaw)
      if yaw==nil then yaw=YAW[player.facing] or 0 end
      local pitch=tonumber(player.red3dAimPitch) or 0.10
      local cp=math.cos(pitch)
      local lx,ly,lz=math.sin(yaw)*cp,-math.sin(pitch),math.cos(yaw)*cp
      local pivot={me.px+8,(me.gh or 0)+(me.lift or 0)+12,me.py+8}
      local orbit={pivot[1],pivot[2]+(CONFIG.cjAimCameraLift or 4.5),pivot[3]}
      local want=CONFIG.cjAimCameraBoom or 46
      local room=want
      if type(ThirdPerson)=="table" and type(ThirdPerson.reach)=="function" and ow then
        local okR,r=pcall(ThirdPerson.reach,ow,orbit,-lx,-ly,-lz,want)
        if okR and type(r)=="number" then room=math.max(10,math.min(want,r)) end
      end
      local flat=math.sqrt(lx*lx+lz*lz)
      local sx,sz=0,0
      if flat>1e-6 then
        local shoulder=(CONFIG.cjAimCameraShoulder or 6.0)*(room/want)
        sx,sz=-lz/flat*shoulder,lx/flat*shoulder
      end
      local targetEye={orbit[1]-lx*room+sx,orbit[2]-ly*room,orbit[3]-lz*room+sz}
      local focusDist=32
      local targetFocus={orbit[1]+lx*focusDist+sx,orbit[2]+ly*focusDist,orbit[3]+lz*focusDist+sz}
      local target={eye=targetEye,focus=targetFocus,
                    fov=math.rad(CONFIG.cjAimCameraFovDeg or 56),up={0,1,0},curve=0}

      local base=baseRig or orbitRig(cx,cy,vh)
      local e=ease01(math.max(0,math.min(1,b)))
      local up=mix3(base.up or {0,1,0},target.up,e)
      local ul=math.sqrt(up[1]*up[1]+up[2]*up[2]+up[3]*up[3])
      if ul>1e-6 then up={up[1]/ul,up[2]/ul,up[3]/ul} else up={0,1,0} end
      local rig={
        eye=mix3(base.eye,target.eye,e),
        focus=mix3(base.focus,target.focus,e),
        fov=(base.fov or target.fov)+(target.fov-(base.fov or target.fov))*e,
        up=up,
        curve=((base.curve or 0)*(1-e)),
      }
      Voxel3D.camera=rig
      player.red3dAimCameraRig=rig
      return rig,cx+(pivot[1]-cx)*e,cy+(pivot[3]-cy)*e
    end
  end

  -- Small real 3D cubes used for CJ world-destruction debris.  Four texture
  -- swatches keep the fragments looking like earthy/foliage voxel pieces.
  local debrisMesh=nil
  local debrisImage=nil
  local function ensureDebrisGraphics()
    if debrisMesh and debrisImage then return true end
    if not (love and love.graphics and love.image and Voxel3D and Voxel3D.FORMAT) then return false end
    local okImg,img=pcall(function()
      local id=love.image.newImageData(4,1)
      id:setPixel(0,0,0.24,0.34,0.17,1)
      id:setPixel(1,0,0.34,0.46,0.22,1)
      id:setPixel(2,0,0.40,0.32,0.20,1)
      id:setPixel(3,0,0.48,0.46,0.34,1)
      local im=love.graphics.newImage(id)
      im:setFilter("nearest","nearest")
      im:setWrap("clamp","clamp")
      return im
    end)
    if not okImg then return false end
    debrisImage=img
    -- Unit cube, centered at origin. Voxel3D's current vertex layout accepts
    -- x,y,z,u,v,light/ao exactly like the character mesh rows.
    local faces={
      {-0.5,-0.5, 0.5,  0.5,-0.5, 0.5,  0.5, 0.5, 0.5, -0.5, 0.5, 0.5},
      { 0.5,-0.5,-0.5, -0.5,-0.5,-0.5, -0.5, 0.5,-0.5,  0.5, 0.5,-0.5},
      {-0.5,-0.5,-0.5, -0.5,-0.5, 0.5, -0.5, 0.5, 0.5, -0.5, 0.5,-0.5},
      { 0.5,-0.5, 0.5,  0.5,-0.5,-0.5,  0.5, 0.5,-0.5,  0.5, 0.5, 0.5},
      {-0.5, 0.5, 0.5,  0.5, 0.5, 0.5,  0.5, 0.5,-0.5, -0.5, 0.5,-0.5},
      {-0.5,-0.5,-0.5,  0.5,-0.5,-0.5,  0.5,-0.5, 0.5, -0.5,-0.5, 0.5},
    }
    local rows={}
    local function add(x,y,z,u)
      rows[#rows+1]={x,y,z,u,0.5,1.0}
    end
    for _,f in ipairs(faces) do
      local p={}
      for i=1,12,3 do p[#p+1]={f[i],f[i+1],f[i+2]} end
      -- Use first palette pixel in the shared mesh; per-piece palette is
      -- expressed by a tiny U translation in the model-independent texture.
      local u=0.125
      add(p[1][1],p[1][2],p[1][3],u); add(p[2][1],p[2][2],p[2][3],u); add(p[3][1],p[3][2],p[3][3],u)
      add(p[1][1],p[1][2],p[1][3],u); add(p[3][1],p[3][2],p[3][3],u); add(p[4][1],p[4][2],p[4][3],u)
    end
    local okMesh,m=pcall(love.graphics.newMesh,Voxel3D.FORMAT,rows,"triangles","static")
    if not okMesh then debrisImage=nil; return false end
    debrisMesh=m
    return true
  end

  -- A cold fracture cache should never force the old flat-green placeholder.
  -- Build a tiny reusable cube whose six faces sample the exact tileset tile
  -- under the hit cell. This path is only a compatibility fallback; the
  -- preferred path below still fractures the live terrain triangles.
  local fallbackTileMeshByTexture=setmetatable({}, {__mode="k"})
  local function fallbackTileCube(map,cx,cy,texture)
    if not (map and texture and love and love.graphics and Voxel3D and Voxel3D.FORMAT) then return nil end
    local tile=0
    if type(map.cellTile)=="function" then
      local ok,t=pcall(map.cellTile,map,cx,cy)
      if ok and type(t)=="number" then tile=t end
    end
    local byTile=fallbackTileMeshByTexture[texture]
    if not byTile then byTile={};fallbackTileMeshByTexture[texture]=byTile end
    if byTile[tile] then return byTile[tile] end
    local ts=map.tileset or {}
    local perRow=ts.tilesPerRow or 16
    local aw=ts.imageWidth or (perRow*8)
    local ah=ts.imageHeight or 48
    if aw<=0 or ah<=0 then return nil end
    local ax=(tile%perRow)*8
    local ay=math.floor(tile/perRow)*8
    local inset=0.12
    local u0,u1=(ax+inset)/aw,(ax+8-inset)/aw
    local v0,v1=(ay+inset)/ah,(ay+8-inset)/ah
    local faces={
      {-0.5,-0.5, 0.5,  0.5,-0.5, 0.5,  0.5, 0.5, 0.5, -0.5, 0.5, 0.5},
      { 0.5,-0.5,-0.5, -0.5,-0.5,-0.5, -0.5, 0.5,-0.5,  0.5, 0.5,-0.5},
      {-0.5,-0.5,-0.5, -0.5,-0.5, 0.5, -0.5, 0.5, 0.5, -0.5, 0.5,-0.5},
      { 0.5,-0.5, 0.5,  0.5,-0.5,-0.5,  0.5, 0.5,-0.5,  0.5, 0.5, 0.5},
      {-0.5, 0.5, 0.5,  0.5, 0.5, 0.5,  0.5, 0.5,-0.5, -0.5, 0.5,-0.5},
      {-0.5,-0.5,-0.5,  0.5,-0.5,-0.5,  0.5,-0.5, 0.5, -0.5,-0.5, 0.5},
    }
    local uv={{u0,v1},{u1,v1},{u1,v0},{u0,v0}}
    local rows={}
    local function add(pt,t,shade) rows[#rows+1]={pt[1],pt[2],pt[3],t[1],t[2],shade} end
    for fi,f in ipairs(faces) do
      local q={}
      for i=1,12,3 do q[#q+1]={f[i],f[i+1],f[i+2]} end
      local shade=({0.84,0.72,0.68,0.90,1.0,0.55})[fi] or 0.85
      add(q[1],uv[1],shade);add(q[2],uv[2],shade);add(q[3],uv[3],shade)
      add(q[1],uv[1],shade);add(q[3],uv[3],shade);add(q[4],uv[4],shade)
    end
    local ok,m=pcall(love.graphics.newMesh,Voxel3D.FORMAT,rows,"triangles","static")
    if not ok or not m then return nil end
    if m.setTexture then pcall(m.setTexture,m,texture) end
    byTile[tile]=m
    return m
  end

  local function drawWorldDebris(player,terrainAtlas)
    if not (player and type(player.red3dDebris)=="table" and #player.red3dDebris>0) then return end
    local fallbackReady=false
    -- Fractured chunks have been recentered into rigid-piece local space, so
    -- the terrain wireframe's integer-grid assumption no longer applies.
    if Voxel3D.seams then Voxel3D.seams(false) end
    for _,d in ipairs(player.red3dDebris) do
      local lifeFrac=math.max(0,math.min(1,(d.life or 0)/(d.maxLife or 1)))
      local m=Mat4.translate(d.wx or 0,d.wy or 0,d.wz or 0)
      if Mat4.rotateX and d.rotX then m=Mat4.mul(m,Mat4.rotateX(d.rotX)) end
      if Mat4.rotateY and d.rotY then m=Mat4.mul(m,Mat4.rotateY(d.rotY)) end
      if Mat4.rotateZ and d.rotZ then m=Mat4.mul(m,Mat4.rotateZ(d.rotZ)) end
      if d.mesh then
        -- These are triangles cut directly out of Dramatic Shape's live
        -- terrain mesh. Their local geometry/UV/shade is unchanged; only a
        -- rigid chunk transform is animated here.  The environment therefore
        -- literally becomes the debris instead of blinking out underneath a
        -- separate particle effect.
        local shrink=1
        if lifeFrac<0.18 then shrink=math.max(0.05,lifeFrac/0.18) end
        if shrink~=1 then m=Mat4.mul(m,Mat4.scale(shrink,shrink,shrink)) end
        -- Always prefer the atlas currently used to draw this map. A terrain
        -- mesh can retain an old/no texture because Dramatic Shape supplies
        -- the atlas as a separate Voxel3D.draw argument every frame.
        local tex=(d.mapId and bridge.terrainAtlasByMap[d.mapId])
          or terrainAtlas or bridge.currentTerrainAtlas or d.texture
        if tex then Voxel3D.draw(d.mesh,tex,m,nil,m) end
      else
        local fadeShrink=0.58+0.42*math.min(1,lifeFrac*2.2)
        local s=(d.size or 1.5)*fadeShrink
        m=Mat4.mul(m,Mat4.scale(s,s,s))
        local tex=(d.mapId and bridge.terrainAtlasByMap[d.mapId])
          or terrainAtlas or bridge.currentTerrainAtlas or d.texture
        if d.fallbackMesh and tex then
          Voxel3D.draw(d.fallbackMesh,tex,m,nil,m)
        else
          if not fallbackReady then fallbackReady=ensureDebrisGraphics() end
          if fallbackReady then Voxel3D.draw(debrisMesh,debrisImage,m,nil,m) end
        end
      end
    end
    if Voxel3D.seams then Voxel3D.seams(true) end
  end

  -- Intercept only the drawEntity call whose arguments belong to the marked
  -- player pose.  Every NPC and every authored figure still uses Dramatic
  -- Shape's own card path untouched.
  local function hookedDrawEntity(sprite,px,py,facing,phase,flip,gh,colors,lift)
    local p=bridge.currentPose
    if not bridge.disabled and p and bridge.currentPlayer
        and sprite==p.sprite and px==p.px and py==p.py and gh==p.gh then
      local ok,shown=pcall(renderer.drawVoxel,renderer,bridge.currentPlayer,p,Voxel3D,Mat4,FirstPerson)
      if ok and shown then return true end
      if not ok then
        bridge.disabled=true
        renderer.voxelFailed=true
        if not bridge.loggedDrawError then
          bridge.loggedDrawError=true
          mod.log:error("Dramatic Shape 3D player draw failed: %s -- falling back to its stock player card",tostring(shown))
        end
      end
    end
    return originalDrawEntity(sprite,px,py,facing,phase,flip,gh,colors,lift)
  end
  if not setUpvalue(originalDrawCast,drawEntityIndex,hookedDrawEntity) then
    mod.log:warn("Dramatic Shape drawEntity upvalue could not be replaced")
    return false
  end

  local function hookedDrawCast(state,posed,atlasFor)
    local oldPose,oldPlayer=bridge.currentPose,bridge.currentPlayer
    bridge.currentPose=playerPose(posed)
    bridge.currentPlayer=state and state.player or nil
    local atlas=nil
    if type(atlasFor)=="function" and state and state.map then
      local okAtlas,a=pcall(atlasFor,state.map)
      if okAtlas and a then atlas=a end
    end
    if atlas and state and state.map then
      bridge.currentTerrainAtlas=atlas
      if state.map.id then bridge.terrainAtlasByMap[state.map.id]=atlas end
      if type(ChunkMesher)=="table" and type(ChunkMesher.pair)=="function" then
        local terrain=nil
        local okPair,t=pcall(ChunkMesher.pair,state.map,false)
        if okPair and t then terrain=t end
        if not terrain then
          okPair,t=pcall(ChunkMesher.pair,state.map,true)
          if okPair and t then terrain=t end
        end
        if terrain then bridge.terrainAtlasByMesh[terrain]=atlas end
      end
    end
    local ok,err=pcall(originalDrawCast,state,posed,atlasFor)
    if ok and bridge.currentPlayer then
      pcall(drawWorldDebris,bridge.currentPlayer,atlas or bridge.currentTerrainAtlas)
    end
    bridge.currentPose,bridge.currentPlayer=oldPose,oldPlayer
    if not ok then error(err,0) end
  end
  if not setUpvalue(render,drawCastIndex,hookedDrawCast) then
    -- Put drawEntity back if the outer hook cannot be installed.
    setUpvalue(originalDrawCast,drawEntityIndex,originalDrawEntity)
    mod.log:warn("Dramatic Shape drawCast upvalue could not be replaced")
    return false
  end

  -- Dramatic Shape normally draws the player's original sprite card again in
  -- an inverted-depth "ghost" pass whenever scenery occludes the player.  A
  -- real 3D mesh cannot safely use that exact pass (its own back faces would
  -- self-overlap), and leaving the stock card enabled makes Red visibly flash
  -- between the sprite and the model around walls/trees.  Suppress only that
  -- player ghost while the 3D bridge is healthy; NPC ghost behavior is kept.
  if drawGhostIndex and type(originalDrawGhost)=="function" then
    local function hookedDrawGhost(p)
      if not bridge.disabled and p and p.isPlayer then return end
      return originalDrawGhost(p)
    end
    if setUpvalue(render,drawGhostIndex,hookedDrawGhost) then
      bridge.ghostSuppressed=true
    end
  end

  -- Replace the stock upright *player card* in the sun pass with the same
  -- real mesh.  This makes Red cast a volumetric body shadow onto terrain,
  -- walls and roofs.  The visible draw hook above is useful without this,
  -- so a future Dramatic Shape shadow-layout change only loses this extra
  -- piece instead of disabling the model itself.
  if castShadowIndex and type(originalCastShadows)=="function" then
    local _,ShadowMap=findUpvalue(originalCastShadows,"ShadowMap")
    local _,SpriteBillboards=findUpvalue(originalCastShadows,"SpriteBillboards")
    if type(ShadowMap)=="table" and type(SpriteBillboards)=="table"
        and type(ShadowMap.finish)=="function" and type(ShadowMap.draw)=="function"
        and type(SpriteBillboards.shadowQuad)=="function" then
      local function hookedCastShadows(state,terrain,nbMesh,posed,cx,cy,vw,vh,
                                        atlasFor,water,nbWater,battleCards,battleToken)
        local me=playerPose(posed)
        local player=state and state.player or nil
        -- castShadows is invoked once at the start of every Dramatic Shape
        -- render frame, even when the shadow map itself is already current.
        -- Use it as a stable frame boundary so shadow/reflection/visible passes
        -- all share exactly the same skinned pose and cannot flicker apart.
        if me and player then renderer:beginVoxelFrame(player,me) end
        if bridge.disabled or not me or not player or playerUsesSpecialCard(player)
            or not renderer:ensureVoxelGraphics(Voxel3D) then
          return originalCastShadows(state,terrain,nbMesh,posed,cx,cy,vw,vh,
                                     atlasFor,water,nbWater,battleCards,battleToken)
        end

        local playerDef=me.sprite and me.sprite.def
        local oldQuad=SpriteBillboards.shadowQuad
        local oldFinish=ShadowMap.finish
        SpriteBillboards.shadowQuad=function(def,frame)
          if def==playerDef then return nil end
          return oldQuad(def,frame)
        end
        ShadowMap.finish=function(sig)
          local okShadow,shadowErr=pcall(function()
            if ShadowMap.sprites then ShadowMap.sprites(true) end
            renderer:drawVoxelShadow(player,me,Voxel3D,Mat4,ShadowMap,FirstPerson)
            if ShadowMap.sprites then ShadowMap.sprites(false) end
          end)
          if not okShadow and not bridge.loggedShadowError then
            bridge.loggedShadowError=true
            mod.log:error("3D character volumetric shadow failed: %s",tostring(shadowErr))
          end
          return oldFinish(sig)
        end

        local ok,err=pcall(originalCastShadows,state,terrain,nbMesh,posed,cx,cy,vw,vh,
                           atlasFor,water,nbWater,battleCards,battleToken)
        SpriteBillboards.shadowQuad=oldQuad
        ShadowMap.finish=oldFinish
        if not ok then error(err,0) end
      end
      if setUpvalue(render,castShadowIndex,hookedCastShadows) then
        if ShadowMap.invalidate then pcall(ShadowMap.invalidate) end
        bridge.shadowHook=true
      end
    end
  end

  -- Dramatic Shape's staged 3D battle has a separate renderer from the
  -- overworld voxel scene.  During the trainer-intro frames its player side is
  -- normally a flat back-picture card.  Wrap that battle render and replace
  -- only that trainer card (tex.trainer) with this real Red mesh; once the
  -- player's Pokemon appears, the normal Pokemon card path resumes untouched.
  do
    local _,V=findUpvalue(render,"V")
    if type(V)=="table" and type(V.require)=="function" then
      local okB,BattleScene=pcall(V.require,"BattleScene")
      local okS,ShadowMap=pcall(V.require,"ShadowMap")
      if okB and type(BattleScene)=="table" and type(BattleScene.render)=="function"
          and not BattleScene.red3dPlayerBattleInstalled then
        local originalBattleRender=BattleScene.render
        BattleScene.red3dPlayerBattleInstalled=true
        function BattleScene.render(state,arena,textures,token)
          local ptex=textures and textures.player
          local trainerCanvas=ptex and ptex.trainer and ptex.canvas or nil
          if bridge.disabled or not trainerCanvas or not arena or not arena.player then
            bridge.battlePointActive=false
            bridge.battlePointStart=nil
            return originalBattleRender(state,arena,textures,token)
          end

          local okGame,Game=pcall(require,"src.core.Game")
          local battlePlayer=okGame and Game and Game.overworld and Game.overworld.player or nil

          -- Start the pointing gesture once when the trainer card first appears.
          -- The battle token can change while Dramatic Shape animates the intro,
          -- so using it as the timer key used to reset the pose every frame and
          -- left the arm stuck at the starting position.
          local now=(love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
          if not bridge.battlePointActive then
            bridge.battlePointActive=true
            bridge.battlePointStart=now
          elseif not bridge.battlePointStart then
            bridge.battlePointStart=now
          end
          local pointAmount=(now-(bridge.battlePointStart or now))/0.38
          if pointAmount<0 then pointAmount=0 elseif pointAmount>1 then pointAmount=1 end

          if not battlePlayer or not renderer:prepareBattleMesh(battlePlayer,Voxel3D,pointAmount) then
            return originalBattleRender(state,arena,textures,token)
          end

          local host=arena.map or (state and state.map)
          local groundY=0
          if host and type(BattleScene.groundY)=="function" then
            local okG,g=pcall(BattleScene.groundY,host,arena)
            if okG and type(g)=="number" then groundY=g end
          end
          local battleModel=renderer:battleModelMatrix(arena,groundY,Mat4)
          if not battleModel then return originalBattleRender(state,arena,textures,token) end

          local oldVoxelDraw=Voxel3D.draw
          local oldShadowDraw=(okS and type(ShadowMap)=="table") and ShadowMap.draw or nil
          Voxel3D.draw=function(mesh,tex,model,pull,shadowModel,...)
            if tex==trainerCanvas then
              if Voxel3D.glass then pcall(Voxel3D.glass,false) end
              return oldVoxelDraw(renderer.voxelMesh,renderer.image,battleModel,nil,battleModel,...)
            end
            return oldVoxelDraw(mesh,tex,model,pull,shadowModel,...)
          end
          if oldShadowDraw then
            ShadowMap.draw=function(mesh,tex,model,...)
              if tex==trainerCanvas then
                return oldShadowDraw(renderer.voxelMesh,renderer.image,battleModel,...)
              end
              return oldShadowDraw(mesh,tex,model,...)
            end
          end

          local ok,result=pcall(originalBattleRender,state,arena,textures,token)
          Voxel3D.draw=oldVoxelDraw
          if oldShadowDraw then ShadowMap.draw=oldShadowDraw end
          if not ok then
            mod.log:error("Dramatic Shape battle 3D character replacement failed: %s",tostring(result))
            return nil
          end
          return result
        end
        bridge.battleHook=true
        mod.log:info("Dramatic Shape battle bridge installed: trainer back-card -> selected 3D character")
      end
    end
  end

  VoxelScene.red3dPlayerBridgeInstalled=true
  VoxelScene.red3dPlayerBridge=bridge
  renderer.voxelBridgeInstalled=true
  renderer.voxelBridge=bridge
  renderer.voxelChunkMesher=ChunkMesher
  mod.log:info("Dramatic Shape bridge installed: player sprite card -> real %d-triangle skinned mesh%s%s",
    renderer.data.triangleCount,
    bridge.shadowHook and " + volumetric sun shadow" or "",
    bridge.ghostSuppressed and " + stock ghost flicker suppression" or "")
  return true
end

return function(mod)
  local CHARACTER_DEFS = {
    RED = { id="RED", label="Red", data="data/model.lua", atlas="assets/red_atlas.png", height=18.984375, profile="RED" },
    YUGI = { id="YUGI", label="Yugi Muto", data="data/yugi_model.lua", atlas="assets/yugi_atlas.png", height=25, profile="YUGI", armRestDeg=62 },
    NARUTO = { id="NARUTO", label="Naruto", data="data/naruto_model.lua", atlas="assets/naruto_atlas_open.png", atlasFrames={"assets/naruto_atlas_open.png","assets/naruto_atlas_close00.png"}, dynamicAtlas="blink", height=20.5, profile="NARUTO_MIXAMO", armRestDeg=0, modelYawOffset=3.14159265 },
    ZORO = { id="ZORO", label="Roronoa Zoro", data="data/zoro_model.lua", atlas="assets/zoro_atlas.png", height=26, profile="AANG_MIXAMO", armRestDeg=0, modelYawOffset=0, postSkinZUp=true },
    CLOUD = { id="CLOUD", label="Cloud", data="data/cloud_model.lua", atlas="assets/cloud_atlas.png", height=20, profile="CLOUD", armRestDeg=0 },
    AANG = { id="AANG", label="Aang", data="data/aang_model.lua", atlas="assets/aang_atlas.png", height=18.5, profile="AANG_MIXAMO", armRestDeg=0, modelYawOffset=0 },
    CJ = { id="CJ", label="Carl Johnson (CJ)", data="data/cj_model.lua", atlas="assets/cj_atlas.png", height=27, profile="CJ_FBX", armRestDeg=0, modelYawOffset=0, postSkinZUp=true },
    YAMI = { id="YAMI", label="Yami", data="data/yami_model.lua", atlas="assets/yami_atlas.png", height=24.5, profile="YAMI_FBX", armRestDeg=0, modelYawOffset=0, postSkinZUp=true },
    BELLESTARMON = { id="BELLESTARMON", label="BelleStarmon", data="data/bellestarmon_model.lua", atlas="assets/bellestarmon_atlas.png", height=27, profile="AANG_MIXAMO", armRestDeg=0, modelYawOffset=3.14159265 },
    SHREK = { id="SHREK", label="Shrek", data="data/shrek_model.lua", atlas="assets/shrek_atlas.png", height=29, profile="AANG_MIXAMO", armRestDeg=0, modelYawOffset=0 },
        ASH = { id="ASH", label="Ash Ketchum", data="data/ash_model.lua", atlas="assets/ash_atlas.png", height=19.5, profile="ASH", armRestDeg=0, modelYawOffset=0 },
  }
  local CHARACTER_ORDER = { "RED", "YUGI", "YAMI", "BELLESTARMON", "NARUTO", "ZORO", "CLOUD", "AANG", "CJ", "SHREK", "ASH" }

  -- Player-facing settings remain available in the mod manager, while the
  -- same character choice is also exposed as a proper pause/start-menu screen.
  if mod.options and mod.options.define then
    mod.options:define({
      { key = "character_3d", type = "choice", label = "CHARACTER", default = "RED",
        choices = { {"RED","RED"}, {"YUGI MUTO","YUGI"}, {"YAMI","YAMI"}, {"BELLESTARMON","BELLESTARMON"}, {"NARUTO","NARUTO"}, {"RORONOA ZORO","ZORO"}, {"CLOUD","CLOUD"}, {"AANG","AANG"}, {"CARL JOHNSON (CJ)","CJ"}, {"SHREK","SHREK"}, {"ASH KETCHUM","ASH"} } },
      { key = "manual_jump", type = "toggle", label = "MANUAL JUMP", default = true },
    })
  end

  local function manualJumpEnabled()
    if not (mod.options and mod.options.get) then return true end
    return mod.options:get("manual_jump") ~= false
  end

  local function savedCharacter()
    -- mod entry code runs before the game save is necessarily restored.  Only
    -- read per-save state here; never fall back to an old global CHARACTER
    -- option, because that was the source of the "always boots as Aang" bug.
    local id=nil
    if mod.save and mod.save.get then
      id=mod.save:get("selected_character_3d")
    end
    if not CHARACTER_DEFS[id] then return nil end
    return id
  end

  local function storedCharacter()
    return savedCharacter() or "RED"
  end

  local renderers={}
  for _,id in ipairs(CHARACTER_ORDER) do
    local def=CHARACTER_DEFS[id]
    local data=loadLuaData(mod,def.data)
    if data then
      renderers[id]=Renderer.new(mod,data,def)
      mod.log:info("character %s loaded: %d bones, %d weighted points, %d triangles",
        def.label,data.boneCount,data.positionCount,data.triangleCount)
    else
      mod.log:error("character %s could not be loaded",def.label)
    end
  end
  if not renderers.RED then return end

  local okPlayer,Player=pcall(require,"src.world.Player")
  local okGV,GameVersion=pcall(require,"src.core.GameVersion")
  if not okPlayer or not Player or not okGV or not GameVersion then
    mod.log:error("engine internals needed for Player:draw are unavailable -- this build of Gen1Recomp is not compatible")
    return
  end

  local renderer=ActiveRenderer.new(renderers,storedCharacter())

  local function applyCharacter(id)
    if not renderers[id] then return false end
    renderer:setActive(id)
    if mod.save and mod.save.set then mod.save:set("selected_character_3d",id) end
    local active=renderer:getActive()
    if active then
      active.skinKey=nil; active.voxelUploadedKey=nil; active.voxelFrameKey=nil
    end
    mod.log:info("3D character selected: %s", CHARACTER_DEFS[id].label)
    return true
  end

  -- Proper pause/start-menu skin selector.  The public START-menu hook is the
  -- canonical path.  A small compatibility layer below also recognizes several
  -- paused-overlay hook/menu shapes used by host builds that expose a separate
  -- pause list, keeping the shortcut between MOD MENUS and MODS when possible.
  local CHARACTER_SCREEN = "RED3D_CHARACTER_SELECTOR"
  local SKIN_SELECTOR_LABEL = "Skin Selector"

  -- v2.8.68 ports the proven Stadium UI Model Viewer rendering architecture to
  -- the Skin Selector: render the highlighted character into a transparent
  -- off-screen Voxel3D scene, bypass PaletteFX for that true-color draw, then
  -- restore every graphics/voxel state immediately. Unlike the Pokedex viewer
  -- we own this screen, so no sprite-ID/draw interception is necessary.
  local function loadLocalModule(path)
    local src,err=mod:read(path)
    if not src then mod.log:error("Skin Selector viewer missing %s: %s",tostring(path),tostring(err)); return nil end
    local fn,e=load(src,"@"..tostring(mod.path or mod.id).."/"..path)
    if not fn then mod.log:error("Skin Selector viewer compile failed: %s",tostring(e)); return nil end
    local ok,result=pcall(fn)
    if not ok then mod.log:error("Skin Selector viewer load failed: %s",tostring(result)); return nil end
    return result
  end

  local SkinSelectorViewer=loadLocalModule("lib/SkinSelectorModelViewer.lua")

  local SELECTOR_NAMES={
    RED="RED", YUGI="YUGI", YAMI="YAMI", BELLESTARMON="BELLE",
    NARUTO="NARUTO", ZORO="ZORO", CLOUD="CLOUD", AANG="AANG",
    CJ="CJ", SHREK="SHREK", ASH="ASH",
  }

  local function viewportRect(viewport)
    if viewport and viewport.fullSafe then
      local safe=viewport.fullSafe
      return tonumber(safe.x) or 0,tonumber(safe.y) or 0,
        math.max(1,tonumber(safe.width) or 1),math.max(1,tonumber(safe.height) or 1)
    end
    if viewport and viewport.safe then
      local safe=viewport.safe
      return tonumber(safe.x) or 0,tonumber(safe.y) or 0,
        math.max(1,tonumber(safe.width or viewport.width) or 1),
        math.max(1,tonumber(safe.height or viewport.height) or 1)
    end
    if viewport and viewport.safeX then
      return tonumber(viewport.safeX) or 0,tonumber(viewport.safeY) or 0,
        math.max(1,tonumber(viewport.safeWidth or viewport.width) or 1),
        math.max(1,tonumber(viewport.safeHeight or viewport.height) or 1)
    end
    local g=love and love.graphics
    return 0,0,g and g.getWidth and g.getWidth() or 1280,
      g and g.getHeight and g.getHeight() or 720
  end

  -- v2.8.72 makes the Skin Selector's clean presentation self-contained.
  -- The game still owns the ListMenu state/input/callbacks; this mod only
  -- paints an independent high-resolution presenter after the native HUD.
  -- No Gen 1 Modern UI installation is required.
  local SELECTOR_THEME={
    backdrop={0.018,0.030,0.055,0.74},
    surface={0.045,0.067,0.105,0.985},
    surfaceRaised={0.072,0.105,0.160,0.985},
    selected={0.105,0.330,0.600,1.0},
    accent={0.40,0.80,1.00,1.0},
    text={0.965,0.985,1.0,1.0},
    muted={0.64,0.73,0.84,1.0},
    divider={0.20,0.30,0.43,1.0},
    active={0.25,0.83,0.61,1.0},
    shadow={0,0,0,0.28},
  }

  local selectorFonts={}
  local function selectorFont(px)
    px=math.max(10,math.floor((tonumber(px) or 16)+0.5))
    if selectorFonts[px] then return selectorFonts[px] end
    local g=love and love.graphics
    if not (g and g.newFont) then return g and g.getFont and g.getFont() or nil end
    local ok,font=pcall(g.newFont,px)
    if not ok or not font then return g.getFont and g.getFont() or nil end
    if font.setFilter then pcall(font.setFilter,font,"linear","linear",1) end
    selectorFonts[px]=font
    return font
  end

  local function setRGBA(c,a)
    if not (love and love.graphics) then return end
    love.graphics.setColor(c[1],c[2],c[3],a or c[4] or 1)
  end

  local function roundedFill(x,y,w,h,r,color)
    setRGBA(color)
    love.graphics.rectangle("fill",x,y,w,h,r,r)
  end

  local function roundedLine(x,y,w,h,r,color,width)
    local g=love.graphics
    setRGBA(color)
    g.setLineWidth(width or 1)
    g.rectangle("line",x,y,w,h,r,r)
    g.setLineWidth(1)
  end

  local function drawSelectorText(text,font,x,y,color,align,width)
    local g=love.graphics
    if font then g.setFont(font) end
    setRGBA(color)
    text=tostring(text or "")
    if width and align then g.printf(text,x,y,width,align) else g.print(text,x,y) end
  end

  local function drawStandaloneSkinSelector(menu,viewport)
    if not (love and love.graphics and menu and menu._red3dSkinSelector) then return end
    local g=love.graphics
    local vx,vy,vw,vh=viewportRect(viewport)
    if vw<360 or vh<260 then return end

    local scale=math.max(0.72,math.min(1.55,math.min(vw/1280,vh/720)))
    local outer=math.max(14,math.floor(28*scale))
    local gap=math.max(12,math.floor(18*scale))
    local radius=math.max(10,math.floor(18*scale))
    local pad=math.max(12,math.floor(20*scale))
    local titleFont=selectorFont(28*scale)
    local subtitleFont=selectorFont(14*scale)
    local bodyFont=selectorFont(18*scale)
    local smallFont=selectorFont(12*scale)
    local badgeFont=selectorFont(10*scale)

    -- Large centered modal that fully covers the underlying 160x144 menu.
    -- This keeps the clean presentation consistent whether or not another UI
    -- overhaul happens to be installed.
    local maxW=math.min(vw-outer*2,1500*scale)
    local maxH=math.min(vh-outer*2,860*scale)
    local panelW=math.max(330,maxW)
    local panelH=math.max(250,maxH)
    local px=vx+(vw-panelW)*0.5
    local py=vy+(vh-panelH)*0.5

    local pushed=false
    if g.push then pushed=pcall(g.push,"all") end
    local oldShader=g.getShader and g.getShader() or nil
    pcall(g.setShader)
    pcall(g.setBlendMode,"alpha","alphamultiply")

    -- Dim the game behind the selector without making it disappear completely.
    setRGBA(SELECTOR_THEME.backdrop)
    g.rectangle("fill",vx,vy,vw,vh)

    -- soft shadow + main card
    roundedFill(px+5*scale,py+7*scale,panelW,panelH,radius,SELECTOR_THEME.shadow)
    roundedFill(px,py,panelW,panelH,radius,SELECTOR_THEME.surface)
    roundedLine(px,py,panelW,panelH,radius,SELECTOR_THEME.divider,math.max(1,2*scale))

    local headerH=math.max(62,math.floor(76*scale))
    local footerH=math.max(42,math.floor(54*scale))
    drawSelectorText("SKIN SELECTOR",titleFont,px+pad,py+math.floor(12*scale),SELECTOR_THEME.text)
    drawSelectorText("Choose a character",subtitleFont,px+pad,py+math.floor(47*scale),SELECTOR_THEME.muted)
    setRGBA(SELECTOR_THEME.divider)
    g.rectangle("fill",px+pad,py+headerH-1,panelW-pad*2,1)

    local contentY=py+headerH+gap
    local contentH=panelH-headerH-footerH-gap*2
    local listW=math.max(210,math.min(panelW*0.38,450*scale))
    local previewX=px+pad+listW+gap
    local previewW=px+panelW-pad-previewX
    local listX=px+pad

    roundedFill(listX,contentY,listW,contentH,radius*0.75,SELECTOR_THEME.surfaceRaised)
    roundedFill(previewX,contentY,previewW,contentH,radius*0.75,SELECTOR_THEME.surfaceRaised)

    -- Character list. We derive its visual window from the live ListMenu index,
    -- while ListMenu itself continues to own scrolling/input and onChoose.
    local items=menu.items or {}
    local selected=math.max(1,math.min(#items,tonumber(menu.index) or 1))
    local listPad=math.max(10,math.floor(12*scale))
    local rowGap=math.max(4,math.floor(6*scale))
    local availableH=contentH-listPad*2
    local rowH=math.max(38,math.floor(48*scale))
    local visible=math.max(1,math.floor((availableH+rowGap)/(rowH+rowGap)))
    visible=math.min(visible,#items)
    local first=math.max(1,math.min(selected-math.floor(visible/2),#items-visible+1))
    local active=renderer.activeId or "RED"

    for slot=0,visible-1 do
      local i=first+slot
      local item=items[i]
      if item then
        local ry=contentY+listPad+slot*(rowH+rowGap)
        local chosen=(i==selected)
        if chosen then
          roundedFill(listX+listPad,ry,listW-listPad*2,rowH,math.max(7,radius*0.48),SELECTOR_THEME.selected)
          setRGBA(SELECTOR_THEME.accent)
          g.rectangle("fill",listX+listPad,ry+math.max(6,rowH*0.18),math.max(3,4*scale),rowH*0.64,3,3)
        end
        local label=item.fullLabel or item.label or item.previewLabel or ""
        drawSelectorText(label,bodyFont,listX+listPad+math.max(12,16*scale),
          ry+(rowH-(bodyFont and bodyFont:getHeight() or 18))*0.5,
          chosen and SELECTOR_THEME.text or SELECTOR_THEME.muted)
        if item.characterId==active then
          local badge="ACTIVE"
          local bw=(badgeFont and badgeFont:getWidth(badge) or 38)+math.max(12,14*scale)
          local bh=math.max(20,math.floor(23*scale))
          local bx=listX+listW-listPad-bw-math.max(4,6*scale)
          local by=ry+(rowH-bh)*0.5
          roundedFill(bx,by,bw,bh,bh*0.45,SELECTOR_THEME.active)
          drawSelectorText(badge,badgeFont,bx,by+(bh-(badgeFont and badgeFont:getHeight() or 10))*0.5,
            {0.02,0.10,0.08,1},"center",bw)
        end
      end
    end

    if first>1 then drawSelectorText("▲",smallFont,listX+listW-listPad*2,contentY+4*scale,SELECTOR_THEME.muted) end
    if first+visible-1<#items then
      drawSelectorText("▼",smallFont,listX+listW-listPad*2,contentY+contentH-(smallFont and smallFont:getHeight() or 12)-4*scale,SELECTOR_THEME.muted)
    end

    -- High-resolution 3D portrait.
    local item=items[selected]
    local child=item and renderers[item.characterId] or nil
    local viewer=menu._red3dViewer
    local bridge=renderer.voxelBridge
    local previewPad=math.max(12,math.floor(16*scale))
    local label=(item and item.fullLabel) or (child and child.characterLabel) or ""
    local countText=(#items>0) and string.format("%d / %d",selected,#items) or ""
    drawSelectorText(label,bodyFont,previewX+previewPad,contentY+math.max(8,10*scale),SELECTOR_THEME.text)
    local cw=smallFont and smallFont:getWidth(countText) or 0
    drawSelectorText(countText,smallFont,previewX+previewW-previewPad-cw,contentY+math.max(12,14*scale),SELECTOR_THEME.muted)

    local modelTop=contentY+math.max(44,math.floor(48*scale))
    local modelBottom=contentY+contentH-math.max(38,math.floor(42*scale))
    local modelX=previewX+previewPad
    local modelY=modelTop
    local modelW=previewW-previewPad*2
    local modelH=math.max(80,modelBottom-modelTop)
    roundedFill(modelX,modelY,modelW,modelH,math.max(8,radius*0.55),{0.025,0.040,0.065,0.72})

    local canvas=nil
    if viewer and child and bridge then
      -- Render above display resolution, then downsample once. The viewer clamps
      -- this to sane limits so large desktop windows stay sharp without an
      -- unbounded GPU allocation.
      local sceneW=math.max(640,math.min(1152,math.floor(modelW*1.55)))
      local sceneH=math.max(720,math.min(1280,math.floor(modelH*1.55)))
      local ok,result=pcall(viewer.render,viewer,child,bridge,sceneW,sceneH)
      if ok then canvas=result end
    end
    if canvas then
      local iw,ih=canvas:getDimensions()
      local drawScale=math.min(modelW/iw,modelH/ih)
      local dw,dh=iw*drawScale,ih*drawScale
      g.setColor(1,1,1,1)
      pcall(g.setBlendMode,"alpha","premultiplied")
      g.draw(canvas,modelX+(modelW-dw)*0.5,modelY+(modelH-dh)*0.5,0,drawScale,drawScale)
      pcall(g.setBlendMode,"alpha","alphamultiply")
    else
      drawSelectorText("3D PREVIEW UNAVAILABLE",smallFont,modelX,modelY+modelH*0.5,
        SELECTOR_THEME.muted,"center",modelW)
    end

    drawSelectorText("L / R   Rotate",smallFont,previewX+previewPad,
      contentY+contentH-math.max(26,31*scale),SELECTOR_THEME.muted)

    -- Footer hints stay readable on controller and keyboard without borrowing
    -- another UI mod's presenter or assets.
    local footerY=py+panelH-footerH
    setRGBA(SELECTOR_THEME.divider)
    g.rectangle("fill",px+pad,footerY,panelW-pad*2,1)
    drawSelectorText("↑↓  Browse",smallFont,px+pad,footerY+math.max(13,16*scale),SELECTOR_THEME.muted)
    local centerHint="A  Select"
    drawSelectorText(centerHint,smallFont,px,footerY+math.max(13,16*scale),SELECTOR_THEME.text,"center",panelW)
    local back="B  Back"
    local backW=smallFont and smallFont:getWidth(back) or 45
    drawSelectorText(back,smallFont,px+panelW-pad-backW,footerY+math.max(13,16*scale),SELECTOR_THEME.muted)

    if oldShader then pcall(g.setShader,oldShader) else pcall(g.setShader) end
    if pushed then pcall(g.pop) end
  end

  -- Keep a completely ordinary ListMenu underneath the presenter so the game
  -- remains the sole owner of cursor movement, callbacks, sounds, and stack state.
  -- v2.8.72's clean UI is a self-contained high-resolution render.hud overlay.
  mod.content.screens:register(CHARACTER_SCREEN,{
    new=function(game)
      local active=renderer.activeId or "RED"
      local items={}
      local activeIndex=1
      for _,id in ipairs(CHARACTER_ORDER) do
        if renderers[id] then
          items[#items+1]={
            label=SELECTOR_NAMES[id] or CHARACTER_DEFS[id].label,
            previewLabel=SELECTOR_NAMES[id] or CHARACTER_DEFS[id].label,
            fullLabel=CHARACTER_DEFS[id].label,
            characterId=id,
            right=(id==active) and "ACTIVE" or nil,
          }
          if id==active then activeIndex=#items end
        end
      end

      local menu=mod.ui.ListMenu.new(game,"SKIN SELECTOR",items,{
        pageJump=false,
        rows=8,
        onChoose=function(item,m)
          if item and item.characterId then applyCharacter(item.characterId) end
          m:close()
        end,
      })
      menu.game=menu.game or game
      menu.screenId=CHARACTER_SCREEN
      menu.title="SKIN SELECTOR"
      menu.footer="L/R  TURN    A  SELECT    B  BACK"
      menu.index=activeIndex
      menu.scroll=math.max(0,activeIndex-(menu.rows or 8))
      menu._red3dSkinSelector=true
      menu._red3dViewer=(SkinSelectorViewer and SkinSelectorViewer.new)
        and SkinSelectorViewer.new() or nil

      local baseUpdate=menu.update
      menu.update=function(self,dt)
        local input=self.game and self.game.input
        local viewer=self._red3dViewer
        if viewer and input then
          if input:wasPressed("left") then viewer:nudge(-math.rad(18)) end
          if input:wasPressed("right") then viewer:nudge(math.rad(18)) end
        end
        return baseUpdate(self,dt)
      end
      return menu
    end,
  })

  -- Draw after the native HUD. The large opaque modal covers the native
  -- 160x144 ListMenu visually, but that ListMenu continues handling input.
  -- This works identically with or without any external UI overhaul installed.
  mod.hooks:wrap("render.hud",function(next,game,viewport)
    local result=next(game,viewport)
    local stack=game and game.stack
    local top=stack and type(stack.top)=="function" and stack:top() or nil
    if top and top._red3dSkinSelector then
      local ok,err=pcall(drawStandaloneSkinSelector,top,viewport)
      if not ok then mod.log:error("Skin Selector HD preview failed: %s",tostring(err)) end
    end
    return result
  end,math.huge)

  local function openSkinSelector(game)
    if game then mod.ui.push(game, CHARACTER_SCREEN) end
  end

  local function normalizedMenuLabel(value)
    if value==nil then return "" end
    local s=tostring(value)
    s=s:gsub("^%s+",""):gsub("%s+$","")
    return string.upper(s)
  end

  local function menuItemLabel(item)
    if type(item)=="string" then return item end
    if type(item)~="table" then return nil end
    if type(item[1])=="string" then return item[1] end
    return item.label or item.text or item.name or item.title or item.caption
  end

  local function setMenuItemLabel(item,label)
    if type(item)~="table" then return false end
    if type(item[1])=="string" then item[1]=label; return true end
    if item.label~=nil then item.label=label; return true end
    if item.text~=nil then item.text=label; return true end
    if item.name~=nil then item.name=label; return true end
    if item.title~=nil then item.title=label; return true end
    if item.caption~=nil then item.caption=label; return true end
    item.label=label
    return true
  end

  local function looksLikeGame(value)
    return type(value)=="table" and
      (value.stack~=nil or value.save~=nil or value.overworld~=nil or value.data~=nil)
  end

  local function gameFromValues(values)
    if type(values)~="table" then return nil end
    local n=values.n or #values
    for i=1,n do
      if looksLikeGame(values[i]) then return values[i] end
    end
    return nil
  end

  local function makeSkinSelectorItem(sample,game)
    local function choose(...)
      local args={n=select("#",...),...}
      openSkinSelector(game or gameFromValues(args))
    end

    if type(sample)=="table" and type(sample[1])=="string" then
      local item={SKIN_SELECTOR_LABEL,choose}
      if sample.id~=nil then item.id="skin_selector" end
      if sample.key~=nil then item.key="skin_selector" end
      return item
    end

    local item={}
    local labelKey="label"
    if type(sample)=="table" then
      if sample.text~=nil then labelKey="text"
      elseif sample.name~=nil then labelKey="name"
      elseif sample.title~=nil then labelKey="title"
      elseif sample.caption~=nil then labelKey="caption"
      elseif sample.label~=nil then labelKey="label" end
    end
    item[labelKey]=SKIN_SELECTOR_LABEL

    local callbackKey="onSelect"
    if type(sample)=="table" then
      if sample.onSelect~=nil then callbackKey="onSelect"
      elseif sample.onChoose~=nil then callbackKey="onChoose"
      elseif sample.select~=nil then callbackKey="select"
      elseif sample.action~=nil then callbackKey="action"
      elseif sample.callback~=nil then callbackKey="callback"
      elseif sample.handler~=nil then callbackKey="handler"
      elseif sample.activate~=nil then callbackKey="activate" end
      if sample.id~=nil then item.id="skin_selector" end
      if sample.key~=nil then item.key="skin_selector" end
    end
    item[callbackKey]=choose

    -- Harmless aliases make the compatibility row usable by simple host menu
    -- tables that read a different conventional callback field.
    if callbackKey~="onSelect" then item.onSelect=choose end
    if callbackKey~="action" then item.action=choose end
    if callbackKey~="callback" then item.callback=choose end
    return item
  end

  local function insertSkinSelector(items,game)
    if type(items)~="table" then return false end

    local modsIndex=nil
    local modMenusIndex=nil
    for i,item in ipairs(items) do
      local label=normalizedMenuLabel(menuItemLabel(item))
      if label=="SKIN SELECTOR" or label=="CHARACTER SELECTOR" then
        if type(item)=="table" then setMenuItemLabel(item,SKIN_SELECTOR_LABEL) end
        return true
      elseif label=="MODS" then
        modsIndex=i
      elseif label=="MOD MENUS" or label=="MOD MENU" then
        modMenusIndex=i
      end
    end

    -- Prefer the slot immediately after MOD MENUS.  That matches the user's
    -- top-level pause layout and keeps Skin Selector out of the MOD MENUS
    -- submenu.  If MOD MENUS is absent, fall back to immediately before MODS.
    if modMenusIndex then
      table.insert(items,modMenusIndex+1,makeSkinSelectorItem(items[modMenusIndex],game))
      return true
    end
    if modsIndex then
      table.insert(items,modsIndex,makeSkinSelectorItem(items[modsIndex],game))
      return true
    end
    return false
  end

  -- MAIN START/PAUSE MENU ENTRY (official/documented path).
  --
  -- IMPORTANT: this wrapper must post-process the value returned by next().
  -- Other menu mods can replace the whole items table while building MOD MENUS
  -- / Cheat Menu / MODS.  v2.8.2 inserted before next(), so a later replacement
  -- could erase Skin Selector completely.  Running outermost and inserting into
  -- the final returned list makes the shortcut survive those menu builders.
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local hooked=next(game,items)
    if type(hooked)=="table" then
      items=hooked
    end
    insertSkinSelector(items,game)
    return items
  end, math.huge)

  -- Compatibility for host builds that expose a separate paused-overlay menu.
  -- These names are intentionally best-effort: unknown hook names are ignored.
  -- The adapter accepts common array/table item formats and can mutate either
  -- an incoming item list or a list returned by the wrapped host hook.
  local unpackArgs=table.unpack or unpack
  local function packArgs(...)
    return {n=select("#",...),...}
  end

  local function menuListScore(items)
    if type(items)~="table" then return -1 end
    local score=0
    local seen=0
    for i,item in ipairs(items) do
      if i>40 then break end
      seen=seen+1
      local label=normalizedMenuLabel(menuItemLabel(item))
      if label=="MODS" then score=score+20
      elseif label=="MOD MENUS" or label=="MOD MENU" then score=score+12
      elseif label=="QUIT" or label=="OPTION" or label=="SAVE" then score=score+2
      elseif label=="SKIN SELECTOR" or label=="CHARACTER SELECTOR" then score=score+10 end
    end
    if seen==0 then return -1 end
    return score
  end

  local function findMenuList(values)
    if type(values)~="table" then return nil end
    local best=nil
    local bestScore=0
    local function consider(candidate)
      local score=menuListScore(candidate)
      if score>bestScore then best=candidate; bestScore=score end
    end
    local n=values.n or #values
    for i=1,n do
      local value=values[i]
      consider(value)
      if type(value)=="table" then
        consider(value.items)
        consider(value.menuItems)
        consider(value.entries)
        consider(value.options)
        if type(value.menu)=="table" then
          consider(value.menu.items)
          consider(value.menu.entries)
        end
      end
    end
    return best
  end

  local function pausedOverlayCompatWrapper(next,...)
    local args=packArgs(...)
    local game=gameFromValues(args)
    local incoming=findMenuList(args)
    if incoming then insertSkinSelector(incoming,game) end

    local results=packArgs(next(unpackArgs(args,1,args.n)))
    local returned=findMenuList(results)
    if returned then insertSkinSelector(returned,game or gameFromValues(results)) end
    return unpackArgs(results,1,results.n)
  end

  local PAUSED_OVERLAY_HOOKS={
    "ui.pause_menu.items",
    "ui.paused_menu.items",
    "ui.pause_overlay.items",
    "ui.paused_overlay.items",
    "ui.overlay_pause.items",
    "ui.start_menu.paused_items",
    "ui.start_menu.overlay_items",
  }
  for _,hookName in ipairs(PAUSED_OVERLAY_HOOKS) do
    pcall(function()
      mod.hooks:wrap(hookName,pausedOverlayCompatWrapper,math.huge)
    end)
  end

  if mod.events and mod.events.on then
    -- The entry chunk can run before restoreSave. Re-apply the character only
    -- after the actual game save has loaded, when mod.save points at the
    -- restored save.modData bucket. This is what makes Skin Selector persist
    -- correctly across a full quit/relaunch.
    mod.events:on("save.loaded",function()
      local id=savedCharacter() or "RED"
      if renderers[id] then
        renderer:setActive(id)
        local active=renderer:getActive()
        if active then
          active.skinKey=nil; active.voxelUploadedKey=nil; active.voxelFrameKey=nil
        end
        mod.log:info("3D character restored from save: %s", CHARACTER_DEFS[id].label)
      end
    end)

    mod.events:on("save.created",function()
      -- New saves start from Red unless the player chooses another skin.
      if mod.save and mod.save.set then mod.save:set("selected_character_3d","RED") end
      renderer:setActive("RED")
    end)

    mod.events:on("mod.options_changed",function(payload)
      if payload and payload.mod==mod.id and payload.key=="character_3d"
          and renderers[payload.value] then
        renderer:setActive(payload.value)
        if mod.save and mod.save.set then mod.save:set("selected_character_3d",payload.value) end
      end
    end)
  end

  local okCollision,Collision=pcall(require,"src.world.Collision")
  local function tryOneCellBorderJump(top,player,dir)
    if not (okCollision and Collision and top and top.map and top.entities
        and type(top.scriptMove)=="function") then return false end
    local map=top.map
    local fx,fy=Collision.target(player.cellX,player.cellY,dir)
    if not map:inBounds(fx,fy) then return false end
    local lx,ly=Collision.target(fx,fy,dir)
    if not map:inBounds(lx,ly) then return false end

    -- Do not jump over NPCs/boulders.  The middle cell must be blocked by the
    -- map itself (solid border/fence or elevation pair), and the landing must
    -- be a normal empty walkable cell.  This deliberately supports exactly a
    -- one-cell-thick obstacle like the low brown borders in Dramatic Shape.
    if Collision.occupied(top.entities,fx,fy,player) then return false end
    local canFront=Collision.canMove(map,top.entities,player,dir)
    if canFront==true then return false end
    if not map:isWalkableCell(lx,ly) then return false end
    if Collision.occupied(top.entities,lx,ly,player) then return false end

    local okSound,Sound=pcall(require,"src.core.Sound")
    local okGame,GameCore=pcall(require,"src.core.Game")
    if okSound and Sound and okGame and GameCore and GameCore.data then
      pcall(Sound.play,GameCore.data,"Ledge")
    end
    player.hopFrames,player.hopTotal=32,32
    top:scriptMove(player,dir,2)
    return true
  end

  -- Ordinary/non-voxel mode: retain the v1.0 projected 3D replacement.
  if not Player.red3dPlayerInstalled then
    local previousDraw=Player.draw
    Player.red3dPlayerInstalled=true
    Player.red3dPlayerRenderer=renderer

    function Player:draw(camX,camY)
      if renderer.failed then return previousDraw(self,camX,camY) end
      if playerUsesSpecialCard(self) then
        return previousDraw(self,camX,camY)
      end

      local _,px,py,facing,phase,flip,hopping=self:pose()
      if hopping then drawHopShadow(self,camX,camY,GameVersion) end

      local ok,shown=pcall(renderer.draw,renderer,self,px,py,camX,camY,facing,phase,flip)
      if not ok then
        renderer.failed=true
        mod.log:error("3D player renderer disabled after draw error: %s -- stock sprite will resume next frame",tostring(shown))
        return
      end
      if not shown and renderer.failed then return end
    end
  else
    -- Hot reload / duplicate install: reuse the active renderer only for the
    -- ordinary path, but still allow this entry to try the voxel bridge.
    if Player.red3dPlayerRenderer then renderer=Player.red3dPlayerRenderer end
  end

  -- Manual jump: controller west-face button (SDL/LÖVE `x` = Xbox X /
  -- PlayStation Square).  When a real Gen1 ledge is directly in front, call
  -- the overworld's own checkLedgeHop() so landing validation, NPC collision,
  -- connected-map crossings, SFX and the two-cell movement all stay owned by
  -- the engine.  Everywhere else the button remains a visual jump in place.
  local okGame,Game=pcall(require,"src.core.Game")
  if okGame and Game then
    if not Player.red3dManualJumpUpdateInstalled then
      Player.red3dManualJumpUpdateInstalled=true
      local previousUpdate=Player.update
      function Player:update(...)
        if self.red3dManualJumpFrames and self.red3dManualJumpFrames > 0 then
          self.red3dManualJumpFrames=self.red3dManualJumpFrames-1
          if self.red3dManualJumpFrames <= 0 then
            self.red3dManualJumpFrames=nil
            self.red3dManualJumpTotal=nil
          end
        end
        if self.red3dShootFrames and self.red3dShootFrames > 0 then
          self.red3dShootFrames=self.red3dShootFrames-1
          if self.red3dShootFrames <= 0 then
            self.red3dShootFrames=nil
            self.red3dShootTotal=nil
          end
        end
        if self.red3dShootCooldown and self.red3dShootCooldown > 0 then
          self.red3dShootCooldown=self.red3dShootCooldown-1
          if self.red3dShootCooldown <= 0 then self.red3dShootCooldown=nil end
        end
        if self.red3dShotHudFrames and self.red3dShotHudFrames > 0 then
          self.red3dShotHudFrames=self.red3dShotHudFrames-1
        end
        if self.red3dShotHitFramesHud and self.red3dShotHitFramesHud > 0 then
          self.red3dShotHitFramesHud=self.red3dShotHitFramesHud-1
        end
        if type(self.red3dDebris)=="table" then
          local dt=1/60
          for i=#self.red3dDebris,1,-1 do
            local d=self.red3dDebris[i]
            d.life=(d.life or 0)-dt
            if d.life<=0 then
              if d.mesh and d.mesh.release then pcall(d.mesh.release,d.mesh) end
              table.remove(self.red3dDebris,i)
            else
              if d.phase=="hold" then
                -- For a couple of frames the debris grid occupies the exact
                -- old terrain volume while the voxel chunk refresh starts.
                d.phaseAge=(d.phaseAge or 0)+dt
                d.wx=d.homeX or d.wx; d.wy=d.homeY or d.wy; d.wz=d.homeZ or d.wz
              elseif d.phase=="implode" then
                d.phaseAge=(d.phaseAge or 0)+dt
                local tx,ty,tz=d.targetX or d.wx,d.targetY or d.wy,d.targetZ or d.wz
                local dx,dy,dz=tx-(d.wx or 0),ty-(d.wy or 0),tz-(d.wz or 0)
                local dist=math.sqrt(dx*dx+dy*dy+dz*dz)
                if dist>0.001 then
                  local pull=(CONFIG.cjDebrisImplodeStrength or 245)*(0.85+math.min(1,d.phaseAge/0.075)*0.90)
                  d.vx=(d.vx or 0)+dx/dist*pull*dt
                  d.vy=(d.vy or 0)+dy/dist*pull*dt
                  d.vz=(d.vz or 0)+dz/dist*pull*dt
                end
                d.vx=(d.vx or 0)*0.86; d.vy=(d.vy or 0)*0.86; d.vz=(d.vz or 0)*0.86
                d.wx=(d.wx or 0)+(d.vx or 0)*dt
                d.wy=(d.wy or 0)+(d.vy or 0)*dt
                d.wz=(d.wz or 0)+(d.vz or 0)*dt
                d.rotX=(d.rotX or 0)+(d.spinX or 0)*dt
                d.rotY=(d.rotY or 0)+(d.spinY or 0)*dt
                d.rotZ=(d.rotZ or 0)+(d.spinZ or 0)*dt
              else
                -- After the short implosion, the same pieces become independent
                -- rigid-body-ish chunks and blast outward from the destroyed voxel.
                d.vy=(d.vy or 0)-(CONFIG.cjDebrisGravity3D or 48)*dt
                d.wx=(d.wx or 0)+(d.vx or 0)*dt
                d.wy=(d.wy or 0)+(d.vy or 0)*dt
                d.wz=(d.wz or 0)+(d.vz or 0)*dt

                local ground=d.groundY or 0.45
                local half=d.halfY or ((d.size or 1.5)*0.5)
                if d.wy-half < ground then
                  d.wy=ground+half
                  if (d.vy or 0)<-1.5 then
                    d.vy=-(d.vy or 0)*(CONFIG.cjDebrisBounce or 0.38)
                    d.vx=(d.vx or 0)*(CONFIG.cjDebrisGroundFriction or 0.72)
                    d.vz=(d.vz or 0)*(CONFIG.cjDebrisGroundFriction or 0.72)
                    d.spinX=(d.spinX or 0)*0.78
                    d.spinY=(d.spinY or 0)*0.78
                    d.spinZ=(d.spinZ or 0)*0.78
                  else
                    d.vy=0
                    d.vx=(d.vx or 0)*0.90
                    d.vz=(d.vz or 0)*0.90
                  end
                end

                d.rotX=(d.rotX or 0)+(d.spinX or 0)*dt
                d.rotY=(d.rotY or 0)+(d.spinY or 0)*dt
                d.rotZ=(d.rotZ or 0)+(d.spinZ or 0)*dt
              end
            end
          end
          if #self.red3dDebris==0 then self.red3dDebris=nil end
        end
        if self.red3dWorldBreakFrames and self.red3dWorldBreakFrames>0 then self.red3dWorldBreakFrames=self.red3dWorldBreakFrames-1 end
        if self.red3dRecoilKick and self.red3dRecoilKick>0 then
          self.red3dRecoilKick=math.max(0,self.red3dRecoilKick-0.72)
        end
        -- Let Gen1Recomp resolve movement first, then impose the CJ aim-facing
        -- pose. That keeps movement direction independent while ADS, so CJ can
        -- actually strafe/backpedal instead of vanilla movement immediately
        -- overwriting the gun direction every frame.
        local result=previousUpdate(self,...)
        local top=Game and Game.stack and Game.stack:top() or nil
        local activeRenderer=renderer and renderer.getActive and renderer:getActive() or nil
        if top and activeRenderer and activeRenderer.characterId=="CJ" then
          -- v2.8.22: native terrain-mesh fracture/prewarm is deliberately disabled.
          -- Some LÖVE/Gen1Recomp builds crash inside Mesh vertex-map access when
          -- the pistol is fired. CJ shooting no longer touches that API at all.

          -- True third-person aim controller. Dramatic Shape's native shooter
          -- uses a squared stick curve and negative right-stick yaw; mirror
          -- that feel here instead of linearly rotating the aim vector.
          local dead=CONFIG.cjAimDeadzone or 0.18
          local function stickCurve(v)
            v=tonumber(v) or 0
            local a=math.abs(v)
            if a<=dead then return 0 end
            local n=(a-dead)/math.max(0.001,1-dead)
            n=n*n
            return v<0 and -n or n
          end
          local rx=stickCurve(self.red3dLookStickX)
          local ry=stickCurve(self.red3dLookStickY)
          local facingYaw=YAW[self.facing or "down"] or 0
          if self.red3dAimYaw==nil then self.red3dAimYaw=facingYaw end
          if self.red3dAimPitch==nil then self.red3dAimPitch=0.08 end
          local blend=tonumber(self.red3dAimCamBlend) or 0
          local blendStep=1/math.max(1,CONFIG.cjAimCameraBlendFrames or 7)

          if self.red3dADS then
            blend=math.min(1,blend+blendStep)
            -- Negative yaw sign matches Dramatic Shape's own right-stick
            -- camera convention: push right, orbit/aim right.
            self.red3dAimYaw=(self.red3dAimYaw-rx*(CONFIG.cjLookYawSpeed or 2.55)/60+math.pi)%(math.pi*2)-math.pi
            self.red3dAimPitch=self.red3dAimPitch+ry*(CONFIG.cjLookPitchSpeed or 1.65)/60
            local up=CONFIG.cjLookPitchUp or -0.42
            local down=CONFIG.cjLookPitchDown or 0.58
            if self.red3dAimPitch<up then self.red3dAimPitch=up
            elseif self.red3dAimPitch>down then self.red3dAimPitch=down end
            self.red3dAimBodyYaw=self.red3dAimYaw

            -- CJ stays oriented to the continuous weapon yaw while the game's
            -- four-direction facing remains the nearest cardinal for movement
            -- and collision semantics. This gives proper strafe/backpedal feel.
            local sx,sy=math.sin(self.red3dAimYaw),math.cos(self.red3dAimYaw)
            if math.abs(sx)>math.abs(sy) then self.facing=sx<0 and "left" or "right"
            else self.facing=sy<0 and "up" or "down" end
          else
            blend=math.max(0,blend-blendStep)
            self.red3dAimBodyYaw=nil
            -- Once the shoulder camera has mostly blended away, softly return
            -- the hidden aim state to current movement facing.
            if blend<0.10 then
              local diff=(facingYaw-self.red3dAimYaw+math.pi)%(math.pi*2)-math.pi
              self.red3dAimYaw=self.red3dAimYaw+diff*0.24
              self.red3dAimPitch=self.red3dAimPitch+(0.08-self.red3dAimPitch)*0.20
            end
          end
          self.red3dAimCamBlend=blend
          self.red3dAimX=math.sin(self.red3dAimYaw)
          self.red3dAimY=math.cos(self.red3dAimYaw)
          self.red3dAimMag=1

          -- Remove legacy map-camera zoom mutations from older hot-reloaded
          -- builds. The placed voxel camera above owns ADS now.
          if self.red3dADSCameraBase then
            local cam=top.camera or top.worldCamera or top.cam
            if cam then
              local base=self.red3dADSCameraBase
              if cam.targetZoom~=nil then cam.targetZoom=base end
              if cam.zoom~=nil then cam.zoom=base end
              if cam.scale~=nil then cam.scale=base end
            end
            self.red3dADSCameraBase=nil
          end
        else
          self.red3dAimCamBlend=math.max(0,(tonumber(self.red3dAimCamBlend) or 0)-1/math.max(1,CONFIG.cjAimCameraBlendFrames or 7))
          self.red3dAimBodyYaw=nil
        end
        return result
      end
    end

    local gunSource=nil
    local function playCJGunshot()
      -- Avoid invoking the MP3 decoder from the trigger path. A few runtime
      -- combinations have native decoder/source crashes that pcall cannot catch.
      -- Use a tiny generated mono crack instead; it is cached after first use.
      if not (love and love.audio and love.sound) then return end
      if not gunSource then
        local okBuild,src=pcall(function()
          local rate=22050
          local count=math.floor(rate*0.070)
          local sd=love.sound.newSoundData(count,rate,16,1)
          for i=0,count-1 do
            local t=i/math.max(1,count-1)
            local env=(1-t)*(1-t)*(1-t)
            local noise=(math.random()*2-1)*0.50
            local crack=math.sin(i*0.91)*0.22
            sd:setSample(i,math.max(-1,math.min(1,(noise+crack)*env)))
          end
          local s=love.audio.newSource(sd,"static")
          s:setVolume(0.82)
          return s
        end)
        if okBuild then gunSource=src end
      end
      if gunSource then
        pcall(gunSource.stop,gunSource)
        pcall(gunSource.setPitch,gunSource,0.99+math.random()*0.02)
        pcall(gunSource.play,gunSource)
      end
    end

    local function actorCell(e)
      if not e then return nil,nil end
      local x=tonumber(e.cellX or e.cx or e.tileX)
      local y=tonumber(e.cellY or e.cy or e.tileY)
      if x and y then return x,y end
      local px=tonumber(e.px or e.x)
      local py=tonumber(e.py or e.y)
      if px and py then return math.floor(px/16+0.5),math.floor(py/16+0.5) end
      return nil,nil
    end

    local function collectShootableActors(top,player)
      local out,seen={},{}
      local function scan(parent)
        if type(parent)~="table" then return end
        for k,v in pairs(parent) do
          if type(v)=="table" and v~=player and not seen[v] then
            local x,y=actorCell(v)
            if x and y then
              seen[v]=true
              out[#out+1]={entity=v,parent=parent,key=k,x=x,y=y}
            end
          end
        end
      end
      scan(top and top.entities)
      scan(top and top.npcs)
      scan(top and top.actors)
      scan(top and top.figures)
      scan(top and top.pokemon)
      scan(top and top.pokemons)
      scan(top and top.objects)
      scan(top and top.props)
      scan(top and top.decor)
      scan(top and top.decorations)
      return out
    end

    local function removeFromParent(parent,key)
      if type(parent)~="table" or key==nil then return end
      if type(key)=="number" then table.remove(parent,key) else parent[key]=nil end
    end

    local function destroyShotTarget(rec,player)
      if not rec or not rec.entity then return end
      local hit=rec.entity
      hit.red3dShotHitFrames=16
      hit.red3dShotHitDirection=player.red3dLastShotFacing or player.facing
      if hit.bumpFrames==nil or tonumber(hit.bumpFrames)==0 then hit.bumpFrames=12 end
      if hit.bumpDirection~=nil then hit.bumpDirection=player.red3dLastShotFacing or player.facing end
      if type(hit.onShot)=="function" then pcall(hit.onShot,hit,player) end
      if type(hit.onHit)=="function" then pcall(hit.onHit,hit,"red3d_pistol",player) end
      if type(hit.destroy)=="function" then pcall(hit.destroy,hit,player) end
      if type(hit.remove)=="function" then pcall(hit.remove,hit,player) end
      if type(hit.despawn)=="function" then pcall(hit.despawn,hit,player) end
      if type(hit.kill)=="function" then pcall(hit.kill,hit,player) end
      hit.visible=false; hit.hidden=true; hit.dead=true; hit.destroyed=true; hit.removeMe=true
      removeFromParent(rec.parent,rec.key)
    end

    local function cjAimVector(player)
      if player and player.red3dADS and player.red3dAimYaw~=nil then
        local yaw=tonumber(player.red3dAimYaw) or 0
        return math.sin(yaw),math.cos(yaw)
      end
      -- Hip fire follows CJ's body/facing instead of retaining an invisible
      -- camera heading from the last ADS session.
      local f=player and player.facing or "down"
      if f=="left" then return -1,0 elseif f=="right" then return 1,0 elseif f=="up" then return 0,-1 else return 0,1 end
    end

    local function cjAimFacing(player)
      local x,y=cjAimVector(player)
      if math.abs(x)>math.abs(y) then return x<0 and "left" or "right" end
      return y<0 and "up" or "down"
    end

    local function angleDiff(a,b)
      local d=(b-a+math.pi)%(math.pi*2)-math.pi
      return d
    end

    local function assistedAim(top,player,dx,dy,actors)
      if not (player and player.red3dADS) then return dx,dy,nil end
      local px=(player.cellX or 0)+0.5
      local py=(player.cellY or 0)+0.5
      local baseAim=atan2(dy,dx)
      local best,bestScore,bestAng,bestDa=nil,nil,nil,nil
      local maxAng=math.rad(CONFIG.cjAimAssistDeg or 3.25)
      for _,rec in ipairs(actors or {}) do
        local tx=(rec.x or 0)+0.5-px
        local ty=(rec.y or 0)+0.5-py
        local dist=math.sqrt(tx*tx+ty*ty)
        if dist>0.25 and dist<=(CONFIG.cjAimAssistRange or 13) then
          local ang=atan2(ty,tx)
          local da=math.abs(angleDiff(baseAim,ang))
          if da<=maxAng then
            local score=da*4+dist*0.012
            if not bestScore or score<bestScore then
              bestScore=score;best=rec;bestAng=ang;bestDa=da
            end
          end
        end
      end
      if best and bestAng then
        -- Magnetism only nudges toward a target that is already close to the
        -- crosshair. It never snaps or changes the reference angle while
        -- scanning other candidates.
        local closeness=1-math.min(1,(bestDa or 0)/math.max(maxAng,1e-5))
        local strength=(CONFIG.cjAimAssistStrength or 0.34)*closeness
        local turn=angleDiff(baseAim,bestAng)*strength
        local a=baseAim+turn
        return math.cos(a),math.sin(a),best
      end
      return dx,dy,nil
    end

    local function applySpread(dx,dy,ads)
      local deg=ads and (CONFIG.cjADSSpreadDeg or 0.10) or (CONFIG.cjHipSpreadDeg or 1.25)
      local jitter=(math.random()*2-1)*math.rad(deg)
      local a=atan2(dy,dx)+jitter
      return math.cos(a),math.sin(a)
    end

    local function findWalkableFloorBlock(map)
      if not (map and map.tileset and type(map.tileset.blocks)=="table" and type(map.walkable)=="table") then return nil end
      if map.red3dFloorBlock~=nil then return map.red3dFloorBlock end
      local best=nil
      for bi,block in ipairs(map.tileset.blocks) do
        if type(block)=="table" then
          local ids={block[5],block[7],block[13],block[15]}
          local ok=true
          for _,tid in ipairs(ids) do if tid==nil or not map.walkable[tid] then ok=false; break end end
          if ok then best=bi-1; break end
        end
      end
      map.red3dFloorBlock=best
      return best
    end

    -- Pre-index the live Dramatic Shape terrain mesh while CJ is active. The
    -- old fracture path discovered every triangle only after the trigger was
    -- pulled, which caused the visible delay before a block reacted. Cache the
    -- expensive world-position -> map-block lookup ahead of time instead.
    local fractureCache=setmetatable({}, {__mode="k"})

    local function currentTerrainMesh(top)
      local map=top and top.map
      local active=renderer:getActive()
      local cm=rawget(renderer,"voxelChunkMesher") or (active and active.voxelChunkMesher)
      if not (map and cm and type(cm.pair)=="function") then return nil,nil,nil end
      local function pair(border)
        local ok,a=pcall(cm.pair,map,border)
        if ok and a then return a end
        ok,a=pcall(cm.pair,cm,map,border)
        if ok then return a end
        return nil
      end
      return pair(false) or pair(true),cm,active
    end

    local function getFractureEntry(top)
      local map=top and top.map
      local terrain,cm,active=currentTerrainMesh(top)
      if not terrain or not terrain.getVertexCount or not terrain.getVertex then return nil end
      local entry=fractureCache[terrain]
      if entry then return entry end
      local count=terrain:getVertexCount()
      if not count or count<3 then return nil end
      local okVM,vm=pcall(terrain.getVertexMap,terrain)
      if not okVM or type(vm)~="table" or #vm<3 then vm=nil end
      -- Keep a full mutable index stream ready before the first shot. Fracture
      -- then only degenerates the selected triangle slots instead of building
      -- and allocating a brand-new map-sized list on the trigger frame.
      local sourceMap={}
      if vm then
        for i=1,#vm do sourceMap[i]=vm[i] end
      else
        for i=1,count do sourceMap[i]=i end
      end
      local activeMap={}
      for i=1,#sourceMap do activeMap[i]=sourceMap[i] end
      local bridge=rawget(renderer,"voxelBridge") or (active and active.voxelBridge)
      local tex=nil
      if bridge then
        tex=(bridge.terrainAtlasByMesh and bridge.terrainAtlasByMesh[terrain])
          or (map and map.id and bridge.terrainAtlasByMap and bridge.terrainAtlasByMap[map.id])
          or bridge.currentTerrainAtlas
      end
      if not tex and terrain.getTexture then
        local okT,v=pcall(terrain.getTexture,terrain)
        if okT then tex=v end
      end
      entry={
        terrain=terrain,cm=cm,active=active,count=count,
        originalMap=sourceMap,activeMap=activeMap,cursor=1,blocks={},ready=false,
        texture=tex,vertexCache={},
      }
      fractureCache[terrain]=entry
      return entry
    end

    local function entryIndex(entry,at)
      return entry.originalMap[at] or at
    end

    local function entryVertex(entry,i)
      local v=entry.vertexCache[i]
      if v then return v end
      local x,y,z,u,vv,shade
      -- Attribute reads make the terrain UV extraction explicit and avoid any
      -- ambiguity from custom Mesh:getVertex formats on older LÖVE builds.
      if entry.terrain.getVertexAttribute then
        local okP,px,py,pz=pcall(entry.terrain.getVertexAttribute,entry.terrain,i,1)
        local okT,tu,tv=pcall(entry.terrain.getVertexAttribute,entry.terrain,i,2)
        local okS,sh=pcall(entry.terrain.getVertexAttribute,entry.terrain,i,3)
        if okP and okT then x,y,z,u,vv,shade=px,py,pz,tu,tv,(okS and sh or 1) end
      end
      if x==nil then
        local ok
        ok,x,y,z,u,vv,shade=pcall(entry.terrain.getVertex,entry.terrain,i)
        if not ok then return nil end
      end
      v={x or 0,y or 0,z or 0,u or 0,vv or 0,shade or 1}
      entry.vertexCache[i]=v
      return v
    end

    local function indexFractureTerrain(top,budget)
      local entry=getFractureEntry(top)
      if not entry or entry.ready then return entry end
      local maxAt=#entry.originalMap-2
      local n=0
      budget=budget or 700
      while entry.cursor<=maxAt and n<budget do
        local at=entry.cursor
        local ia,ib,ic=entryIndex(entry,at),entryIndex(entry,at+1),entryIndex(entry,at+2)
        local a,b,c=entryVertex(entry,ia),entryVertex(entry,ib),entryVertex(entry,ic)
        if a and b and c then
          local mx=(a[1]+b[1]+c[1])/3
          local my=(a[2]+b[2]+c[2])/3
          local mz=(a[3]+b[3]+c[3])/3
          local maxY=math.max(a[2],b[2],c[2])
          -- Only index above-ground geometry. Floor remains static when a
          -- hedge/wall/building is fractured.
          if maxY>0.85 then
            local bx,by=math.floor(mx/32),math.floor(mz/32)
            local key=bx..":"..by
            local list=entry.blocks[key]
            if not list then list={};entry.blocks[key]=list end
            -- Store the index-map slot as well as the three vertex ids. This
            -- lets impact-time cutting touch only selected triangles.
            list[#list+1]=at;list[#list+1]=ia;list[#list+1]=ib;list[#list+1]=ic
          end
        end
        entry.cursor=at+3
        n=n+1
      end
      if entry.cursor>maxAt then entry.ready=true end
      if not entry.texture then
        if entry.terrain.getTexture then
          local okT,v=pcall(entry.terrain.getTexture,entry.terrain)
          if okT then entry.texture=v end
        end
        if not entry.texture then
          local b=rawget(renderer,"voxelBridge") or (entry.active and entry.active.voxelBridge)
          if b then entry.texture=b.currentTerrainAtlas end
        end
      end
      return entry
    end

    -- Called from Player:update in small chunks so by the time the user aims
    -- and fires, triangle classification is already done. This removes the
    -- expensive per-shot full terrain scan that caused the delayed fracture.
    rawset(renderer,"red3dPrewarmFracture",function(top,budget)
      return indexFractureTerrain(top,budget or 700)
    end)

    local function captureTerrainBlockDebris(player,top,cx,cy,shotDx,shotDy)
      local map=top and top.map
      local active=renderer:getActive()
      local bridge=rawget(renderer,"voxelBridge") or (active and active.voxelBridge)
      local V3=bridge and bridge.Voxel3D
      if not (player and map and V3 and love and love.graphics and V3.FORMAT) then return nil end

      local entry=getFractureEntry(top)
      if not entry or not entry.terrain or not entry.terrain.setVertexMap then return nil end
      local terrain=entry.terrain
      local bx,by=math.floor(cx/2),math.floor(cy/2)
      local key=bx..":"..by

      -- Never finish a whole route-sized index on the trigger frame. One
      -- bounded slice is enough to catch a nearly-warmed block; otherwise the
      -- textured fallback below reacts immediately instead of hitching.
      if not entry.ready and not entry.blocks[key] then
        indexFractureTerrain(top,2600)
      end
      local selected=entry.blocks[key]
      if type(selected)~="table" or #selected<4 then return nil end

      -- Impact-time work now touches only triangles in the hit block. The
      -- complete index stream was prepared by the pre-indexer already.
      local activeMap=entry.activeMap
      local groups={}
      local x0,z0=bx*32,by*32
      local selectedTriangles=0
      local selectedYSum,selectedYCount=0,0
      local changedSlots={}
      local function pieceKey(mx,my,mz)
        local gx=math.floor((mx-x0)/4.0)
        local gy=math.floor(math.max(0,my-0.75)/3.6)
        local gz=math.floor((mz-z0)/4.0)
        return gx..":"..gy..":"..gz
      end
      for n=1,#selected-3,4 do
        local at,ia,ib,ic=selected[n],selected[n+1],selected[n+2],selected[n+3]
        -- A previously destroyed block may still have a stale cached record;
        -- only process it if these slots still point at the original triangle.
        if activeMap[at]==ia and activeMap[at+1]==ib and activeMap[at+2]==ic then
          local a,b,c=entryVertex(entry,ia),entryVertex(entry,ib),entryVertex(entry,ic)
          if a and b and c then
            local mx=(a[1]+b[1]+c[1])/3
            local my=(a[2]+b[2]+c[2])/3
            local mz=(a[3]+b[3]+c[3])/3
            selectedTriangles=selectedTriangles+1
            selectedYSum=selectedYSum+my;selectedYCount=selectedYCount+1
            local pk=pieceKey(mx,my,mz)
            local g=groups[pk]
            if not g then g={rows={},sx=0,sy=0,sz=0,n=0};groups[pk]=g end
            for _,vv in ipairs({a,b,c}) do
              g.rows[#g.rows+1]={vv[1],vv[2],vv[3],vv[4],vv[5],vv[6]}
              g.sx=g.sx+vv[1];g.sy=g.sy+vv[2];g.sz=g.sz+vv[3];g.n=g.n+1
            end
            changedSlots[#changedSlots+1]={at,ia,ib,ic}
            -- Degenerate this triangle in place. All three indices reference
            -- the same original vertex, so it has zero area and disappears
            -- without reallocating/reordering the rest of the terrain mesh.
            activeMap[at]=ia;activeMap[at+1]=ia;activeMap[at+2]=ia
          end
        end
      end
      if selectedTriangles==0 then return nil end

      -- Capture the exact texture already attached to the source terrain mesh.
      -- This is more reliable than looking the atlas up again later and makes
      -- the fragments use the same texture object as the geometry they came from.
      local sourceTexture=nil
      if bridge then
        sourceTexture=(bridge.terrainAtlasByMesh and bridge.terrainAtlasByMesh[terrain])
          or (map.id and bridge.terrainAtlasByMap and bridge.terrainAtlasByMap[map.id])
          or bridge.currentTerrainAtlas
      end
      if not sourceTexture then sourceTexture=entry.texture end
      if not sourceTexture and terrain.getTexture then
        local okT,v=pcall(terrain.getTexture,terrain)
        if okT and v then sourceTexture=v end
      end
      entry.texture=sourceTexture

      -- Cut the source mesh immediately on the shot frame. Because activeMap
      -- is preallocated, this call does not build a second map-sized Lua table.
      local okSet=pcall(terrain.setVertexMap,terrain,activeMap)
      if not okSet then
        for _,s in ipairs(changedSlots) do
          local at,ia,ib,ic=s[1],s[2],s[3],s[4]
          activeMap[at]=ia;activeMap[at+1]=ib;activeMap[at+2]=ic
        end
        return nil
      end
      player.red3dDebris=player.red3dDebris or {}
      local groupId="mesh:"..key..":"..tostring(
        love and love.timer and love.timer.getTime and love.timer.getTime() or math.random())
      local targetX,targetZ=x0+16,z0+16
      local targetY=(selectedYCount>0 and selectedYSum/selectedYCount or 8)
      local baseLife=CONFIG.cjDebrisLife or 1.75
      local made=0

      for _,g in pairs(groups) do
        if g.n>=3 and #g.rows>=3 then
          local cx0,cy0,cz0=g.sx/g.n,g.sy/g.n,g.sz/g.n
          local localRows={}
          local halfY,rad=0,0
          for i,row in ipairs(g.rows) do
            local lx,ly,lz=row[1]-cx0,row[2]-cy0,row[3]-cz0
            localRows[i]={lx,ly,lz,row[4],row[5],row[6]}
            halfY=math.max(halfY,math.abs(ly))
            rad=math.max(rad,math.sqrt(lx*lx+ly*ly+lz*lz))
          end
          local okMesh,m=pcall(love.graphics.newMesh,V3.FORMAT,localRows,"triangles","static")
          if okMesh and m then
            if sourceTexture and m.setTexture then pcall(m.setTexture,m,sourceTexture) end
            made=made+1
            -- Start a fraction of a world pixel toward the implosion centre.
            -- This creates a visible crack on the very first rendered frame
            -- instead of leaving every chunk perfectly coincident with the
            -- original object until the next physics tick.
            local ddx,ddy,ddz=targetX-cx0,targetY-cy0,targetZ-cz0
            local dl=math.sqrt(ddx*ddx+ddy*ddy+ddz*ddz)
            local crack=0.32+math.random()*0.18
            local startX,startY,startZ=cx0,cy0,cz0
            if dl>0.001 then
              startX=cx0+ddx/dl*crack
              startY=cy0+ddy/dl*crack
              startZ=cz0+ddz/dl*crack
            end
            player.red3dDebris[#player.red3dDebris+1]={
              mesh=m,texture=sourceTexture,sourceTerrain=terrain,mapId=map.id,
              wx=startX,wy=startY,wz=startZ,homeX=cx0,homeY=cy0,homeZ=cz0,
              targetX=targetX,targetY=targetY,targetZ=targetZ,
              shotDx=tonumber(shotDx) or 0,shotDz=tonumber(shotDy) or 0,
              group=groupId,phase="implode",phaseAge=0,
              vx=0,vy=0,vz=0,
              rotX=0,rotY=0,rotZ=0,
              spinX=(math.random()*2-1)*2.2,
              spinY=(math.random()*2-1)*2.2,
              spinZ=(math.random()*2-1)*2.2,
              life=baseLife*(0.92+math.random()*0.20),maxLife=baseLife,
              groundY=0.15,halfY=math.max(0.35,halfY),radius=math.max(0.5,rad),
            }
          end
        end
      end

      if made==0 then
        -- Restore only the triangle slots touched by this fracture if GPU mesh
        -- creation failed.
        for _,s in ipairs(changedSlots) do
          local at,ia,ib,ic=s[1],s[2],s[3],s[4]
          activeMap[at]=ia;activeMap[at+1]=ib;activeMap[at+2]=ic
        end
        pcall(terrain.setVertexMap,terrain,activeMap)
        return nil
      end
      entry.blocks[key]=nil
      return groupId,made,selectedTriangles
    end

    local function spawnFallbackWorldDebris(player,top,cx,cy,shotDx,shotDy)
      if not (player and cx and cy) then return end
      player.red3dDebris=player.red3dDebris or {}
      local map=top and top.map or nil
      local active=renderer:getActive()
      local bridge=rawget(renderer,"voxelBridge") or (active and active.voxelBridge)
      local atlas=bridge and ((map and map.id and bridge.terrainAtlasByMap and bridge.terrainAtlasByMap[map.id])
        or bridge.currentTerrainAtlas) or nil
      local tileMesh=fallbackTileCube(map,cx,cy,atlas)

      -- Gen1 map blocks are 2x2 collision cells.  World destruction replaces
      -- the WHOLE block, so debris has to cover that same 32x32 footprint or
      -- the terrain appears to blink away around a tiny 16x16 effect.
      local bx,by=math.floor(cx/2),math.floor(cy/2)
      local blockX=bx*32
      local blockZ=by*32
      local tx=blockX+16
      local tz=blockZ+16
      local ty=10.5
      local group=bx..":"..by..":"..tostring(love and love.timer and love.timer.getTime and love.timer.getTime() or math.random())
      local baseLife=CONFIG.cjDebrisLife or 1.70

      -- Build a dense temporary voxel shell that visually occupies the same
      -- volume as the terrain block.  These pieces ARE the transition: the
      -- source terrain can be removed immediately underneath without a pop.
      local nx,nz,ny=5,5,3
      local sx,sz,sy=6.1,6.1,6.0
      for iy=0,ny-1 do
        for iz=0,nz-1 do
          for ix=0,nx-1 do
            local jitter=0.55
            local wx=blockX+(ix+0.5)*(32/nx)+(math.random()*2-1)*jitter
            local wz=blockZ+(iz+0.5)*(32/nz)+(math.random()*2-1)*jitter
            local wy=2.2+(iy+0.5)*6.3+(math.random()*2-1)*0.35
            local dx=tx-wx; local dy=ty-wy; local dz=tz-wz
            local dist=math.sqrt(dx*dx+dy*dy+dz*dz)
            local edge=math.min(ix,nx-1-ix,iz,nz-1-iz,iy,ny-1-iy)
            player.red3dDebris[#player.red3dDebris+1]={
              wx=wx,wy=wy,wz=wz,
              vx=(math.random()*2-1)*0.35,vy=(math.random()*2-1)*0.22,vz=(math.random()*2-1)*0.35,
              targetX=tx,targetY=ty,targetZ=tz,
              homeX=wx,homeY=wy,homeZ=wz,
              shotDx=tonumber(shotDx) or 0,shotDz=tonumber(shotDy) or 0,
              group=group,phase="implode",phaseAge=0,
              fallbackMesh=tileMesh,texture=atlas,mapId=map and map.id or nil,
              rotX=0,rotY=0,rotZ=0,
              spinX=(math.random()*2-1)*3,spinY=(math.random()*2-1)*3,spinZ=(math.random()*2-1)*3,
              size=(5.45+math.random()*0.85),
              palette=math.random(1,4),
              life=baseLife*(0.94+math.random()*0.22),maxLife=baseLife,
              groundY=0.45,
              edge=edge,
            }
          end
        end
      end
      return group
    end

    local function beginImplodeDebris(player,group)
      if not (player and type(player.red3dDebris)=="table") then return end
      for _,d in ipairs(player.red3dDebris) do
        if d.group==group and d.phase=="hold" then
          d.phase="implode"
          d.phaseAge=0
        end
      end
    end

    local function burstWorldDebris(player,group,shotDx,shotDy)
      if not (player and type(player.red3dDebris)=="table") then return end
      local sx=tonumber(shotDx) or 0
      local sz=tonumber(shotDy) or 0
      local sm=math.sqrt(sx*sx+sz*sz)
      if sm>0.001 then sx,sz=sx/sm,sz/sm else sx,sz=0,1 end
      for _,d in ipairs(player.red3dDebris) do
        if d.group==group and (d.phase=="implode" or d.phase=="hold") then
          d.phase="burst"
          d.phaseAge=0
          local ox=(d.wx or d.targetX or 0)-(d.targetX or 0)
          local oy=(d.wy or d.targetY or 0)-(d.targetY or 0)
          local oz=(d.wz or d.targetZ or 0)-(d.targetZ or 0)
          local len=math.sqrt(ox*ox+oy*oy+oz*oz)
          if len<0.08 then
            ox,oy,oz=(math.random()*2-1),math.random()*1.3,(math.random()*2-1)
            len=math.sqrt(ox*ox+oy*oy+oz*oz)
          end
          local rx,ry,rz=ox/len,oy/len,oz/len
          -- Strong radial blast plus bullet-direction bias.  Interior chunks
          -- are slightly faster so the block appears to tear itself apart.
          local burst=(CONFIG.cjDebrisBurstSpeed or 39)*(0.78+math.random()*0.92)
          local bulletPush=15+math.random()*20
          d.vx=rx*burst + sx*bulletPush + (math.random()*2-1)*7
          d.vy=math.abs(ry)*burst*0.68 + (CONFIG.cjDebrisBurstUp or 29)*(0.38+math.random()*0.95)
          d.vz=rz*burst + sz*bulletPush + (math.random()*2-1)*7
          d.spinX=(math.random()*2-1)*19
          d.spinY=(math.random()*2-1)*19
          d.spinZ=(math.random()*2-1)*19
        end
      end
    end

    local function destroyWorldCell(top,cx,cy)
      local map=top and top.map
      if not (CONFIG.cjWorldDestroy and map and map.inBounds and map:inBounds(cx,cy)) then return false end
      if map.isWarpTileCell and map:isWarpTileCell(cx,cy) then return false end
      if map.isDoorTileCell and map:isDoorTileCell(cx,cy) then return false end
      local bx,by=math.floor(cx/2),math.floor(cy/2)
      local floorBlock=findWalkableFloorBlock(map)
      if floorBlock==nil or type(map.setBlock)~="function" then return false end

      -- Change collision/map data immediately on the hit frame.  Then ask the
      -- voxel mesher for the narrowest available refresh path before falling
      -- back to its asynchronous map refresh.  This reduces the visible lag
      -- without invalidating the whole voxel pipeline or causing a 2D flash.
      map:setBlock(bx,by,floorBlock)
      map.red3dDestroyedBlocks=map.red3dDestroyedBlocks or {}
      map.red3dDestroyedBlocks[bx..":"..by]=true
      local active=renderer:getActive()
      local cm=rawget(renderer,"voxelChunkMesher") or (active and active.voxelChunkMesher)
      if cm then
        local refreshed=false
        local candidates={
          {"refreshCell",map.id,cx,cy}, {"refreshBlock",map.id,bx,by},
          {"markDirty",map.id,bx,by}, {"invalidateChunk",map.id,bx,by},
          {"rebuildChunk",map.id,bx,by},
        }
        for _,call in ipairs(candidates) do
          local fn=cm[call[1]]
          if type(fn)=="function" then
            -- Dramatic Shape's modules expose plain dot-functions. Call that
            -- convention first; only try method-style as a compatibility
            -- fallback for forks that wrap the module in an object.
            local ok=pcall(fn,call[2],call[3],call[4])
            if not ok then ok=pcall(fn,cm,call[2],call[3],call[4]) end
            if ok then refreshed=true; break end
          end
        end
        if not refreshed and type(cm.refresh)=="function" and map.id then
          local ok=pcall(cm.refresh,map.id)
          if not ok then pcall(cm.refresh,cm,map.id) end
        end
      end
      return true
    end

    if not Player.red3dDelayedWorldBreakInstalled then
      Player.red3dDelayedWorldBreakInstalled=true
      local previousBreakUpdate=Player.update
      function Player:update(...)
        local result=previousBreakUpdate(self,...)
        if type(self.red3dPendingWorldBreaks)=="table" then
          local dt=1/60
          for i=#self.red3dPendingWorldBreaks,1,-1 do
            local b=self.red3dPendingWorldBreaks[i]
            b.timer=(b.timer or 0)-dt
            if b.stage=="hold" and b.timer<=0 then
              beginImplodeDebris(self,b.group)
              b.stage="implode"
              b.timer=CONFIG.cjWorldImplodeTime or 0.10
            elseif b.stage=="implode" and b.timer<=0 then
              burstWorldDebris(self,b.group,b.dx,b.dy)
              table.remove(self.red3dPendingWorldBreaks,i)
            end
          end
          if #self.red3dPendingWorldBreaks==0 then self.red3dPendingWorldBreaks=nil end
        end
        return result
      end
    end

    local function fireCJShot(top,player)
      player.red3dShootTotal=CONFIG.cjShootFrames
      player.red3dShootFrames=CONFIG.cjShootFrames
      player.red3dShootCooldown=CONFIG.cjShootCooldown
      playCJGunshot()
      local aimFacing=cjAimFacing(player)
      player.red3dLastShotFacing=aimFacing
      player.red3dShotHudFrames=5
      local dx,dy=cjAimVector(player)
      local actors=collectShootableActors(top,player)
      dx,dy=assistedAim(top,player,dx,dy,actors)
      dx,dy=applySpread(dx,dy,player.red3dADS==true)
      player.red3dShotVecX,player.red3dShotVecY=dx,dy
      player.red3dRecoilKick=(player.red3dRecoilKick or 0)+(player.red3dADS and 1.15 or 2.8)
      local hit=nil
      local worldHit=nil
      if top and top.map then
        local px=(player.cellX or 0)+0.5
        local py=(player.cellY or 0)+0.5
        if player.red3dADS then
          -- Start the ray slightly from CJ's right-hand/shoulder side so the
          -- world hit test agrees with the offset third-person camera and gun.
          local handOffset=0.22
          px=px-dy*handOffset
          py=py+dx*handOffset
        end
        local maxDist=CONFIG.cjShootRangeCells or 13
        local visited={}
        local step=0.10
        for dist=0.35,maxDist,step do
          local rx=px+dx*dist
          local ry=py+dy*dist
          local cx=math.floor(rx)
          local cy=math.floor(ry)
          local key=cx..":"..cy
          if not visited[key] then
            visited[key]=true
            if not top.map:inBounds(cx,cy) then break end
            for _,rec in ipairs(actors) do
              if rec.x==cx and rec.y==cy then hit=rec; break end
            end
            if hit then break end
            if top.map.isWalkableCell and not top.map:isWalkableCell(cx,cy) then worldHit={cx=cx,cy=cy}; break end
          end
        end
      end
      if hit then
        player.red3dShotHitFramesHud=7
        destroyShotTarget(hit,player)
      elseif worldHit then
        -- STABILITY PATH: do not touch Dramatic Shape's live terrain Mesh,
        -- vertex maps, chunk refresh APIs, or map block tables from a gunshot.
        -- Those native mutation paths are the source of the CJ trigger crash on
        -- affected builds. Keep recoil/HUD/raycast feedback only.
        player.red3dShotHitFramesHud=5
        player.red3dWorldBreakFrames=6
      end
      local a=renderer:getActive()
      if a then a.skinKey=nil end
      return true
    end

    if not Game.red3dCJAimAxisInstalled then
      Game.red3dCJAimAxisInstalled=true
      local previousGamepadAxis=Game.gamepadaxis
      function Game:gamepadaxis(joystick,axis,value)
        local top=self.stack and self.stack:top() or nil
        local player=top and top.isOverworld and top.player or nil
        local activeRenderer=renderer:getActive()
        if player then
          if axis=="leftx" then player.red3dMoveStickX=value or 0
          elseif axis=="lefty" then player.red3dMoveStickY=value or 0 end
          if axis=="leftx" or axis=="lefty" then
            local mx=tonumber(player.red3dMoveStickX) or 0
            local my=tonumber(player.red3dMoveStickY) or 0
            local mag=math.sqrt(mx*mx+my*my)
            player.red3dAnalogMoveActive=mag>0.08
          end
        end
        if player and activeRenderer and activeRenderer.characterId=="CJ" then
          if axis=="rightx" then player.red3dLookStickX=value
          elseif axis=="righty" then player.red3dLookStickY=value
          elseif axis=="triggerleft" then
            local down=(value or 0)>0.45
            if down and not player.red3dADS then
              player.red3dAimYaw=YAW[player.facing or "down"] or 0
              player.red3dAimPitch=0.08
              player.red3dAimCamBlend=0
            end
            player.red3dADS=down
          end
        end
        return previousGamepadAxis(self,joystick,axis,value)
      end
    end

    if not Game.red3dCJADSReleaseInstalled then
      Game.red3dCJADSReleaseInstalled=true
      local previousGamepadReleased=Game.gamepadreleased
      function Game:gamepadreleased(joystick,button)
        local top=self.stack and self.stack:top() or nil
        local player=top and top.isOverworld and top.player or nil
        local activeRenderer=renderer:getActive()
        if player and activeRenderer and activeRenderer.characterId=="CJ" and button=="triggerleft" then
          player.red3dADS=false
        end
        if previousGamepadReleased then return previousGamepadReleased(self,joystick,button) end
      end
    end

    if not Game.red3dManualJumpInputInstalled then
      Game.red3dManualJumpInputInstalled=true
      local previousGamepadPressed=Game.gamepadpressed
      function Game:gamepadpressed(joystick,button)
        local top=self.stack and self.stack:top() or nil
        local player=top and top.isOverworld and top.player or nil
        local selectHeld=self.input and self.input.isDown and self.input:isDown("select")
        local activeRenderer=renderer:getActive()
        if button=="triggerleft" and player and activeRenderer and activeRenderer.characterId=="CJ" then
          if not player.red3dADS then
            player.red3dAimYaw=YAW[player.facing or "down"] or 0
            player.red3dAimPitch=0.08
            player.red3dAimCamBlend=0
          end
          player.red3dADS=true
        end
        if (button=="rightshoulder" or button=="y") and player and not selectHeld and activeRenderer and activeRenderer.characterId=="CJ"
            and not player.inputLocked and not player.fishing and not player.surfing and not player.onBike
            and not (player.hopFrames and player.hopFrames>0)
            and not (player.red3dShootCooldown and player.red3dShootCooldown>0) then
          local okShot,shotErr=pcall(fireCJShot,top,player)
          if not okShot then
            -- Never let a CJ shot-side Lua error terminate the game loop.
            player.red3dShootFrames=0
            player.red3dShootTotal=0
            player.red3dShootCooldown=math.max(6,tonumber(player.red3dShootCooldown) or 0)
            if mod and mod.log and mod.log.error then
              mod.log:error("CJ shot safely aborted: %s",tostring(shotErr))
            end
          end
          return
        end
        if button=="x" and manualJumpEnabled() and player and not selectHeld
            and not player.inputLocked and not player.fishing
            and not player.surfing and not player.onBike
            and not (player.hopFrames and player.hopFrames>0)
            and not (player.red3dManualJumpFrames and player.red3dManualJumpFrames>0) then

          -- First try the engine's real ledge crossing.  This is deliberately
          -- limited to tiles the game itself marks as jumpable: it cannot turn
          -- arbitrary walls, houses, NPCs, or solid scenery into shortcuts.
          local crossed=false
          if top and type(top.checkLedgeHop)=="function" then
            local ok,result=pcall(top.checkLedgeHop,top,player.facing)
            crossed=ok and result==true
            if not ok then
              mod.log:warn("manual ledge jump check failed: %s",tostring(result))
            end
          end

          if not crossed then
            -- Dramatic Shape also makes some ordinary solid map cells look
            -- like low fences/borders even though Gen 1 does not classify
            -- them as ledges.  Allow X/Square to clear one such blocked cell
            -- when the landing two cells ahead is empty and walkable.
            local okBorder,result=pcall(tryOneCellBorderJump,top,player,player.facing)
            crossed=okBorder and result==true
            if not okBorder then
              mod.log:warn("manual border jump check failed: %s",tostring(result))
            end
          end

          if crossed then
            -- Real ledge/border crossing owns the 32-frame hop and movement.
            -- Clear any stale cosmetic jump so both arcs cannot stack.
            player.red3dManualJumpFrames=nil
            player.red3dManualJumpTotal=nil
          else
            local jumpFrames=(renderer and renderer.characterId=="BELLESTARMON") and 42 or CONFIG.manualJumpFrames
            player.red3dManualJumpTotal=jumpFrames
            player.red3dManualJumpFrames=jumpFrames
          end

          -- Invalidate cached skin keys so takeoff appears immediately.
          renderer.skinKey=nil
          renderer.voxelUploadedKey=nil
          return
        end
        return previousGamepadPressed(self,joystick,button)
      end
    end
  else
    mod.log:warn("manual jump input unavailable: src.core.Game could not be loaded")
  end

  -- If the player disables MANUAL JUMP while a cosmetic jump is in flight,
  -- return immediately to normal rendering.  Real engine ledge hops are left
  -- alone because those are vanilla movement already in progress.
  if mod.events and mod.events.on then
    mod.events:on("mod.options_changed",function(payload)
      if payload and payload.mod==mod.id and payload.key=="manual_jump"
          and payload.value==false then
        local top=Game and Game.stack and Game.stack:top() or nil
        local player=top and top.isOverworld and top.player or nil
        if player then
          player.red3dManualJumpFrames=nil
          player.red3dManualJumpTotal=nil
          renderer.skinKey=nil
          renderer.voxelUploadedKey=nil
        end
      end
    end)
  end

  local function tryVoxelBridge()
    local ok,result=pcall(installVoxelBridge,mod,renderer)
    if not ok then
      mod.log:warn("Dramatic Shape bridge setup failed: %s",tostring(result))
      return false
    end
    return result
  end

  -- Immediate attempt covers hot reload after the content merge.  Normal
  -- startup installs after all mod content has merged, when Pipelines.get()
  -- can see Dramatic Shape's registered voxel pipeline.
  tryVoxelBridge()
  if mod.events and mod.events.on then
    mod.events:on("mods.loaded",function() tryVoxelBridge() end)
  end

  local active=renderer:getActive()
  if active and active.data then
    mod.log:info("3D Character Selector v2.8.70 active: %s (%d bones, %d weighted points, %d triangles)",
      tostring(active.characterLabel),active.data.boneCount,active.data.positionCount,active.data.triangleCount)
  end
  -- CJ-only third-person over-the-shoulder reticle and aim HUD.
  if mod.hooks and mod.hooks.wrap then
    mod.hooks:wrap("render.hud", function(next, game, viewport)
      next(game,viewport)
      local top=game and game.stack and game.stack:top() or nil
      local player=top and top.isOverworld and top.player or nil
      local activeRenderer=renderer:getActive()
      if not (player and activeRenderer and activeRenderer.characterId=="CJ" and love and love.graphics) then return end
      local w,h=love.graphics.getDimensions()
      local kick=tonumber(player.red3dRecoilKick) or 0
      local hitFlash=(player.red3dShotHitFramesHud or 0)>0
      local shotFlash=(player.red3dShotHudFrames or 0)>0
      -- The placed over-the-shoulder camera is itself shifted right, so its
      -- true aim ray is screen centre. Keeping the reticle there makes camera,
      -- pistol direction and raycast agree instead of requiring eye/hand
      -- compensation from the player.
      local cx=w*0.5
      local cy=h*0.49-kick*0.10
      local gap=(player.red3dADS and 2.5 or 5.0) + math.min(2.2,kick*0.14)
      local len=player.red3dADS and 6 or 8
      love.graphics.push("all")
      love.graphics.setLineWidth(player.red3dADS and 1.5 or 2)
      if hitFlash then love.graphics.setColor(1,0.25,0.20,1) else love.graphics.setColor(1,1,1,0.95) end
      love.graphics.line(cx-gap-len,cy,cx-gap,cy)
      love.graphics.line(cx+gap,cy,cx+gap+len,cy)
      love.graphics.line(cx,cy-gap-len,cx,cy-gap)
      love.graphics.line(cx,cy+gap,cx,cy+gap+len)
      if player.red3dADS then love.graphics.circle("line",cx,cy,2.5) end
      if shotFlash then
        love.graphics.setColor(1,0.9,0.45,0.65)
        love.graphics.circle("fill",cx,cy,player.red3dADS and 2 or 3)
      end
      love.graphics.pop()
    end)
  end

end
