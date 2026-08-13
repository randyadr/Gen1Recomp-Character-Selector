-- 3D Character Selector for Gen1Recomp (Mod API 2)
--
-- v1.2 keeps the ordinary Player:draw() + Dramatic Shape voxel bridge and upgrades the
-- bridge into Dramatic Shape's voxel render pass.  Dramatic Shape normally
-- turns overworld actors into leaning sprite cards, so replacing Player:draw
-- alone cannot affect that mode.  The bridge below replaces only the player
-- card with this mod's real skinned mesh while leaving movement/collision,
-- NPCs, figures, water, lighting, camera and world geometry owned by the two
-- original projects.

local function loadLuaSourceData(mod, source, sourceName, sandboxed)
  if not source then return nil end
  sourceName=tostring(sourceName or "imported_skin")
  local chunk, err=nil,nil
  if sandboxed then
    -- Imported .red3dskin model chunks are expected to be pure `return { ... }`
    -- data. Compile them in an empty environment so a package cannot reach
    -- globals such as love/io/os/require while being validated. LuaJIT/Lua 5.1
    -- uses loadstring+setfenv; Lua 5.2+ uses load(..., mode, env).
    if type(loadstring)=="function" and type(setfenv)=="function" then
      chunk,err=loadstring(source,"@"..sourceName)
      if chunk then setfenv(chunk,{}) end
    else
      chunk,err=load(source,"@"..sourceName,"t",{})
    end
  else
    chunk,err=load(source,"@"..sourceName)
  end
  if not chunk then
    mod.log:error("%s did not compile: %s", sourceName, tostring(err))
    return nil
  end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then
    mod.log:error("%s did not return model data: %s", sourceName, tostring(data))
    return nil
  end
  return data
end

local function loadLuaData(mod, rel)
  local source = mod:read(rel)
  if not source then
    mod.log:error("missing %s -- reinstall the complete Red 3D Player mod", rel)
    return nil
  end
  return loadLuaSourceData(mod,source,tostring(mod.path or mod.id) .. "/" .. rel,false)
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


-- BelleStarmon secondary-motion anatomy cleanup.  The generated helper bones
-- intentionally reuse the source skin, but a few low-weight edge vertices can
-- spill outside the tissue region (most visibly the under-bust/upper abdomen).
-- Refine those helper influences once from the bind-pose vertex positions,
-- then renormalize the remaining skin weights so the bind shape is unchanged.
local function red3dSmoothGate(a,b,x)
  if x<=a then return 0 end
  if x>=b then return 1 end
  local t=(x-a)/(b-a)
  return t*t*(3-2*t)
end

local function red3dBreastAreaGate(data,behaviorId,x,y)
  if not data then return 1 end
  local minX,maxX,minY,maxY
  if behaviorId=="WOW" or data.runtimeProfile=="WOW_FBX" then
    minX,maxX,minY,maxY=-0.452770568,0.452770569,0.0,1.0
  else
    minX,maxX,minY,maxY=-0.580464948,0.580464959,-0.000399372,2.248856758
  end
  local nx=(x-minX)/math.max(1e-6,maxX-minX)
  local ny=1-((y-minY)/math.max(1e-6,maxY-minY))

  -- v3.0.52: one independently editable circle per breast.  Screen-left
  -- vertices use the left circle and screen-right vertices use the right circle.
  local left=nx<0.50
  local cx=tonumber(left and data.runtimeBelleBreastAreaLeftX or data.runtimeBelleBreastAreaRightX) or (left and 0.40 or 0.60)
  local cy=tonumber(left and data.runtimeBelleBreastAreaLeftY or data.runtimeBelleBreastAreaRightY) or 0.29
  local radius=tonumber(left and data.runtimeBelleBreastAreaLeftRadius or data.runtimeBelleBreastAreaRightRadius) or 0.13
  if radius<0.045 then radius=0.045 elseif radius>0.30 then radius=0.30 end

  -- Global upper/lower clamps keep the two circles from leaking onto the neck
  -- or abdomen.  ny grows downward on the editor preview.
  local upper=tonumber(data.runtimeBelleBreastAreaUpperLimit) or 0.16
  local lower=tonumber(data.runtimeBelleBreastAreaLowerLimit) or 0.44
  if upper<0.04 then upper=0.04 elseif upper>0.55 then upper=0.55 end
  if lower<upper+0.04 then lower=upper+0.04 elseif lower>0.72 then lower=0.72 end
  local feather=0.018
  local vertical=red3dSmoothGate(upper-feather,upper+feather,ny)*(1-red3dSmoothGate(lower-feather,lower+feather,ny))
  if vertical<=0 then return 0 end

  local dx,dy=nx-cx,ny-cy
  local dist=math.sqrt(dx*dx+dy*dy)
  local inner=radius*0.70
  local circle
  if dist<=inner then circle=1
  elseif dist>=radius then circle=0
  else circle=1-red3dSmoothGate(inner,radius,dist) end
  return circle*vertical
end

local function red3dBreastAreaSaveKey(id,field)
  local prefix=(id=="WOW") and "wow" or "belle"
  return prefix.."_breast_area_"..field.."_v3051"
end

local function refineBelleSecondaryWeights(data)
  if not data or data._red3dBelleAnatomyRefined then return end
  if not (data.boneName and data.boneLocal and data.boneParent and data.posFirst and data.posCount
      and data.infBone and data.infX and data.infY and data.infZ and data.infW) then return end

  local boneByName={}
  for i,name in ipairs(data.boneName) do boneByName[name]=i end
  local helperKind={}
  if boneByName.LBreast then helperKind[boneByName.LBreast]='breast' end
  if boneByName.RBreast then helperKind[boneByName.RBreast]='breast' end
  if not next(helperKind) then return end

  -- Build the unanimated bind hierarchy so each position can be classified in
  -- anatomical/model space rather than by screen-space guesses.
  local bindWorld={}
  for i=1,data.boneCount do
    local localM=copy16(data.boneLocal,(i-1)*16+1)
    local parent=data.boneParent[i]
    if parent and parent>0 then
      bindWorld[i]={}
      mul16(bindWorld[parent],localM,bindWorld[i])
    else
      bindWorld[i]=localM
    end
  end

  local breastMask=data.physicsBreastWeight

  for i=1,data.positionCount do
    local first=data.posFirst[i]
    local count=data.posCount[i]
    local x,y,z=0,0,0
    for j=first,first+count-1 do
      local tx,ty,tz=transformPoint(bindWorld[data.infBone[j]],data.infX[j],data.infY[j],data.infZ[j])
      local w=data.infW[j]
      x=x+tx*w; y=y+ty*w; z=z+tz*w
    end

    -- Breast: keep secondary motion tightly confined to the actual front
    -- breast mound. Fade out under the bust, upper chest, and especially the
    -- lateral side-chest/armpit area so the physics no longer tugs the side
    -- torso when Belle moves.
    local sideAbs=math.abs(x)
    local lowerGate=red3dSmoothGate(1.505,1.555,y)
    local upperGate=(1-red3dSmoothGate(1.690,1.735,y))
    local innerSideGate=red3dSmoothGate(0.030,0.060,sideAbs)
    local outerSideGate=(1-red3dSmoothGate(0.150,0.205,sideAbs))
    local sideGate=innerSideGate*outerSideGate
    local frontGate=1-red3dSmoothGate(-0.125,-0.055,z)
    local breastGate=lowerGate*upperGate*sideGate*(0.05+0.95*frontGate)

    if breastMask then breastMask[i]=(tonumber(breastMask[i]) or 0)*breastGate end

    -- Apply the same anatomical gate to the actual helper-bone skin weights,
    -- not just the post-skin surface layer.  Then renormalize every influence
    -- so zeroing an edge helper never changes the bind-pose vertex position.
    local sum=0
    for j=first,first+count-1 do
      local kind=helperKind[data.infBone[j]]
      local w=data.infW[j]
      if kind=='breast' then w=w*breastGate end
      data.infW[j]=w
      sum=sum+w
    end
    if sum>1e-9 and math.abs(sum-1)>1e-7 then
      local inv=1/sum
      for j=first,first+count-1 do data.infW[j]=data.infW[j]*inv end
    end
  end

  data._red3dBelleAnatomyRefined=true
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
    behaviorId=characterDef.behaviorId or characterDef.id or "RED",
    characterLabel=characterDef.label or characterDef.id or "RED",
    atlasPath=characterDef.atlas or "assets/red_atlas.png",
    atlasFrames=characterDef.atlasFrames or nil,
    atlasBytes=characterDef.atlasBytes or nil,
    dynamicAtlasMode=characterDef.dynamicAtlas or nil,
    modelYawOffset=characterDef.modelYawOffset or CONFIG.modelYawOffset,
    -- The projected Gen1/Gen2 renderer rotates in the opposite convention from
    -- Mat4/Voxel3D. Keep its import-facing correction separate so intrinsic
    -- model orientation can be correct in both paths without abusing FACE FLIP.
    projectYawOffset=tonumber(characterDef.projectYawOffset) or 0,
    -- v3.1.8: true source-basis repair. Some imported rigs were authored with
    -- their visible front 180 degrees opposite the runtime's canonical +Z
    -- forward direction. Correct their skinned geometry itself so every render
    -- path (Gold projection, Voxel3D, selector, battle, accessories) agrees.
    sourceYaw180=characterDef.sourceYaw180==true,
    renderHeight=characterDef.height or CONFIG.height,
    floatOffset=tonumber(characterDef.floatOffset) or 0,
    animationProfile=characterDef.profile or "RED",
    armRestDeg=characterDef.armRestDeg or CONFIG.armRestDeg,
    motionDistance=0,motionX=nil,motionY=nil,lastAnimClock=nil,
    motionSampleTime=nil,voxelFrameSerial=0,voxelFrameClock=nil,
    voxelFrameWalking=false,voxelFrameKey=nil,voxelFrameBlend=0,
    voxelGaitDistance=0,voxelLastTime=nil,voxelLastMovingTime=nil,
    voxelLastSpeed=60,voxelSmoothSpeed=0,voxelMoveBlend=0,
    voxelWasMoving=false,motionMeasuredSpeed=nil,motionMeasuredStable=false,
    motionSpeedSamples={},voxelStartupAge=0,
    beelCloth=nil,beelClothSpeed=0,beelClothLastTime=nil,
    ashIdleTime=0,ashIdleLastTime=nil,
    beelIdleTime=0,beelIdleLastTime=nil,
    aangIdleTime=0,aangIdleLastTime=nil,
    cjIdleTime=0,cjIdleLastTime=nil,
    yamiIdleTime=0,yamiIdleLastTime=nil,
    wowIdleTime=0,wowIdleLastTime=nil,wowRunBlend=0,
    belleRunBlend=0,belleGaitPhase=0,belleKeyboardWalk=false,belleCtrlWasDown=false,
    belleSoft=nil,belleSoftSpeed=0,
    postSkinZUp=characterDef.postSkinZUp==true,
  },Renderer)
  -- model.lua only exposes a small animation-bone subset.  Extend it at
  -- runtime from the generated bone names so wrists/fingers can animate too.
  data.animBone=data.animBone or {}
  data.runtimeProfile=self.animationProfile
  data.runtimeCharacterId=self.behaviorId
  data.runtimeSkinId=self.characterId
  data.runtimeArmRest=self.armRestDeg
  if self.behaviorId=="BELLESTARMON" then data.runtimeBelleRunBlend=0 end
  if data.runtimeProfile=="WOW_FBX" then data.runtimeWowRunBlend=0 end
  for i,name in ipairs(data.boneName or {}) do
    if data.animBone[name]==nil then data.animBone[name]=i end
  end
  if self.behaviorId=="BELLESTARMON" then
    refineBelleSecondaryWeights(data)
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
  -- Projected meshes use pre-sorted painter maps rather than a depth buffer.
  -- Rotating the source basis 180 degrees also reverses which precomputed map
  -- is correct for each view, so swap the opposing orders once at load time.
  if self.sourceYaw180 then
    self.maps.down,self.maps.up=self.maps.up,self.maps.down
    self.maps.left,self.maps.right=self.maps.right,self.maps.left
  end
  local b=data.bounds
  self.minX,self.minY,self.minZ=b[1],b[2],b[3]
  self.maxX,self.maxY,self.maxZ=b[4],b[5],b[6]
  self.centerX=(self.minX+self.maxX)*0.5
  self.centerZ=(self.minZ+self.maxZ)*0.5
  self.baseScale=self.renderHeight/(self.maxY-self.minY)
  self.userScale=1.0
  self.scale=self.baseScale
  self.skinKey=nil
  self.voxelUploadedKey=nil
  return self
end

-- v3.1.8 source-basis repair. Rotate around the model bounds centre rather
-- than the world origin so the character does not jump sideways when corrected.
-- This runs AFTER skinning/secondary physics, preserving all source-space masks
-- and animation math while presenting one canonical forward axis to renderers.
function Renderer:applySourceBasis(x,y,z)
  if self.sourceYaw180 then
    return 2*(self.centerX or 0)-x, y, 2*(self.centerZ or 0)-z
  end
  return x,y,z
end

-- FACE FLIP is a user override on top of the canonical source basis. v3.1.8
-- consumes it in both projected and Voxel3D paths so the checkbox means the
-- same thing everywhere.
function Renderer:setFaceFlip(on)
  self.faceFlipYaw=on and math.pi or 0
  self.skinKey=nil; self.voxelUploadedKey=nil; self.voxelFrameKey=nil
  return self.faceFlipYaw~=0
end

function Renderer:setUserScale(value)
  local v=tonumber(value) or 1.0
  if v<0.50 then v=0.50 elseif v>1.50 then v=1.50 end
  -- Quantize to 1% so save data and the selector percentage stay stable.
  v=math.floor(v*100+0.5)/100
  self.userScale=v
  self.scale=(self.baseScale or (self.renderHeight/(self.maxY-self.minY)))*v
  self.voxelUploadedKey=nil
  self.skinKey=nil
  self.voxelFrameKey=nil
  return v
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

  local bytes=(self.atlasBytes and self.atlasBytes[path]) or self.mod:read(path)
  if not bytes then
    self.mod.log:error("%s is missing for character %s -- reinstall/reimport the complete skin", tostring(path), tostring(self.characterLabel))
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

-- v3.1.15 VR body support. Dramatic/Dramaless Shape intentionally removes the
-- player's own sprite card when a VR eye is inside the player's head. A real
-- skinned body is useful there, but its head/hair must not be rendered around
-- the headset or the near plane becomes a wall of face polygons. Build one
-- alternate triangle map that removes geometry primarily weighted to Head and
-- every descendant of Head. The full mesh remains untouched for normal voxel,
-- third-person, tabletop/diorama VR, shadows, battles and the selector.
function Renderer:buildVRBodyMap()
  if self.vrBodyMap then return self.vrBodyMap end
  local d=self.data
  local head=d and d.animBone and d.animBone.Head or nil
  if not head or head<1 then
    self.vrBodyMap=self.baseMap
    self.vrBodyCulledTriangles=0
    return self.vrBodyMap
  end

  local hidden={[head]=true}
  -- Hair, face helpers and other head children vary by imported rig. Following
  -- the hierarchy rather than hard-coding names catches them all.
  for _=1,(d.boneCount or 0) do
    local changed=false
    for i=1,(d.boneCount or 0) do
      local parent=d.boneParent and d.boneParent[i]
      if parent and hidden[parent] and not hidden[i] then
        hidden[i]=true
        changed=true
      end
    end
    if not changed then break end
  end

  local headWeight={}
  for pos=1,(d.positionCount or 0) do
    local total=0
    local first=d.posFirst and d.posFirst[pos]
    local count=d.posCount and d.posCount[pos] or 0
    if first then
      for j=first,first+count-1 do
        if hidden[d.infBone[j]] then total=total+(tonumber(d.infW[j]) or 0) end
      end
    end
    headWeight[pos]=total
  end

  local out={}
  local base=self.baseMap or {}
  for i=1,#base-2,3 do
    local v1,v2,v3=base[i],base[i+1],base[i+2]
    local p1,p2,p3=self.vertexPos[v1],self.vertexPos[v2],self.vertexPos[v3]
    local h1=headWeight[p1] or 0
    local h2=headWeight[p2] or 0
    local h3=headWeight[p3] or 0
    local strong=(h1>=0.18 and 1 or 0)+(h2>=0.18 and 1 or 0)+(h3>=0.18 and 1 or 0)
    local avg=(h1+h2+h3)/3
    -- Two head-weighted corners is an unambiguous head/face/hair triangle.
    -- The average catches a fully blended neck-cap triangle without chewing a
    -- large hole out of the shoulders on rigs with broad neck weights.
    if strong<2 and avg<0.34 then
      out[#out+1]=v1; out[#out+1]=v2; out[#out+1]=v3
    end
  end
  if #out<3 then out=base end
  self.vrBodyMap=out
  self.vrBodyCulledTriangles=math.max(0,(#base-#out)/3)
  return out
end

function Renderer:ensureVRBodyGraphics(Voxel3D)
  if self.voxelFailed or self.failed then return false end
  if not self:ensureVoxelGraphics(Voxel3D) then return false end
  if self.vrBodyMesh and self.vrBodyFormat==Voxel3D.FORMAT then return true end
  if self.vrBodyMesh and self.vrBodyMesh.release then pcall(self.vrBodyMesh.release,self.vrBodyMesh) end
  local okMesh,mesh=pcall(love.graphics.newMesh,Voxel3D.FORMAT,self.voxelRows,"triangles","dynamic")
  if not okMesh or not mesh then
    self.mod.log:warn("could not create VR first-person character body mesh: %s",tostring(mesh))
    self.vrBodyMesh=nil
    return false
  end
  self.vrBodyMesh=mesh
  self.vrBodyFormat=Voxel3D.FORMAT
  local map=self:buildVRBodyMap()
  if mesh.setVertexMap and map then pcall(mesh.setVertexMap,mesh,map) end
  self.vrBodyUploadedKey=nil
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
    -- Selector/import clips may contain fewer animated bones than the runtime
    -- skeleton (Belle has neutral helper bones appended after the FBX rig).
    -- Never let a short clip abort the entire 3D preview.
    if type(x0)~="number" or type(x1)~="number" then return nil end
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

-- Rigid-transform interpolation used by Wow's supplied FBX clips. Ordinary
-- element-by-element 4x4 matrix lerping can temporarily introduce scale/shear
-- between authored rotation keys, which is especially visible in the fast run.
-- Convert the 3x3 rotation to quaternions, slerp it, then linearly interpolate
-- only the translation. This keeps every sampled pose orthonormal.
local function red3dQuatNormalize(x,y,z,w)
  local n=math.sqrt(x*x+y*y+z*z+w*w)
  if n<1e-12 then return 0,0,0,1 end
  return x/n,y/n,z/n,w/n
end

local function red3dQuatFrom16(m)
  local m00,m01,m02=m[1],m[2],m[3]
  local m10,m11,m12=m[5],m[6],m[7]
  local m20,m21,m22=m[9],m[10],m[11]
  local x,y,z,w
  local tr=m00+m11+m22
  if tr>0 then
    local s=math.sqrt(tr+1.0)*2
    w=0.25*s
    x=(m21-m12)/s
    y=(m02-m20)/s
    z=(m10-m01)/s
  elseif m00>m11 and m00>m22 then
    local s=math.sqrt(math.max(0,1.0+m00-m11-m22))*2
    if s<1e-12 then return 0,0,0,1 end
    w=(m21-m12)/s
    x=0.25*s
    y=(m01+m10)/s
    z=(m02+m20)/s
  elseif m11>m22 then
    local s=math.sqrt(math.max(0,1.0+m11-m00-m22))*2
    if s<1e-12 then return 0,0,0,1 end
    w=(m02-m20)/s
    x=(m01+m10)/s
    y=0.25*s
    z=(m12+m21)/s
  else
    local s=math.sqrt(math.max(0,1.0+m22-m00-m11))*2
    if s<1e-12 then return 0,0,0,1 end
    w=(m10-m01)/s
    x=(m02+m20)/s
    y=(m12+m21)/s
    z=0.25*s
  end
  return red3dQuatNormalize(x,y,z,w)
end

local function red3dQuatSlerp(ax,ay,az,aw,bx,by,bz,bw,t)
  local dot=ax*bx+ay*by+az*bz+aw*bw
  if dot<0 then
    dot=-dot; bx=-bx; by=-by; bz=-bz; bw=-bw
  end
  if dot>0.9995 then
    return red3dQuatNormalize(
      ax+(bx-ax)*t, ay+(by-ay)*t, az+(bz-az)*t, aw+(bw-aw)*t)
  end
  if dot>1 then dot=1 elseif dot<-1 then dot=-1 end
  local theta0=math.acos(dot)
  local st0=math.sin(theta0)
  if math.abs(st0)<1e-9 then return ax,ay,az,aw end
  local theta=theta0*t
  local s0=math.sin(theta0-theta)/st0
  local s1=math.sin(theta)/st0
  return red3dQuatNormalize(
    ax*s0+bx*s1, ay*s0+by*s1, az*s0+bz*s1, aw*s0+bw*s1)
end

local function red3dRigidBlend16(a,b,t)
  if not a then return b end
  if not b then return a end
  if t<=0 then return a end
  if t>=1 then return b end
  local ax,ay,az,aw=red3dQuatFrom16(a)
  local bx,by,bz,bw=red3dQuatFrom16(b)
  local x,y,z,w=red3dQuatSlerp(ax,ay,az,aw,bx,by,bz,bw,t)
  local xx,yy,zz=x*x,y*y,z*z
  local xy,xz,yz=x*y,x*z,y*z
  local wx,wy,wz=w*x,w*y,w*z
  return {
    1-2*(yy+zz), 2*(xy-wz),   2*(xz+wy),   a[4]+(b[4]-a[4])*t,
    2*(xy+wz),   1-2*(xx+zz), 2*(yz-wx),   a[8]+(b[8]-a[8])*t,
    2*(xz-wy),   2*(yz+wx),   1-2*(xx+yy), a[12]+(b[12]-a[12])*t,
    a[13]+(b[13]-a[13])*t, a[14]+(b[14]-a[14])*t,
    a[15]+(b[15]-a[15])*t, a[16]+(b[16]-a[16])*t
  }
end

local function sampleEmbeddedClipRigid(clip,n,bone,phase,closeUniqueLoop)
  if not clip or not n or n<2 then return nil end
  phase=wrap01(phase or 0)
  local f0,f1,a
  if closeUniqueLoop then
    -- Wow's Goofy Running source contains unique keys all the way through the
    -- final frame rather than a duplicate closing key. Treat the last -> first
    -- pair as a normal interpolation interval so the loop never snaps.
    local u=phase*n
    local base=math.floor(u)
    f0=base%n
    f1=(f0+1)%n
    a=u-base
  else
    -- Idle/Catwalk include a duplicate closing key, matching the regular
    -- embedded sampler's n-1 interval convention.
    local u=phase*(n-1)
    f0=math.floor(u)
    if f0>=n-1 then f0=n-2; u=n-1 end
    f1=f0+1
    a=u-f0
  end
  local b0=((bone-1)*n+f0)*16
  local b1=((bone-1)*n+f1)*16
  local m0,m1={},{}
  for k=1,16 do
    local x0=clip[b0+k]
    local x1=clip[b1+k]
    if type(x0)~="number" or type(x1)~="number" then return nil end
    m0[k]=x0; m1[k]=x1
  end
  return red3dRigidBlend16(m0,m1,a)
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

local function bellePhysicsStrength(data,key)
  local v=tonumber(data and data[key]) or 1.0
  if v<0 then v=0 elseif v>2 then v=2 end
  return v
end

-- Physics style changes the spring response curve while the independent
-- region and advanced controls below change how strongly that curve is driven.
local BELLE_PHYSICS_STYLES={
  SOFT={
    targetGain=0.90,
    breast={k=160,damping=20.0},
    thigh={k=140,damping=20.0},
  },
  NATURAL={
    targetGain=1.00,
    breast={k=520,damping=7.0},
    thigh={k=420,damping=8.0},
  },
  SPRINGY={
    targetGain=1.12,
    breast={k=590,damping=3.8},
    thigh={k=500,damping=4.4},
  },
  TIGHT={
    targetGain=0.76,
    breast={k=820,damping=24.0},
    thigh={k=720,damping=25.0},
  },
  HEAVY={
    targetGain=1.05,
    breast={k=225,damping=11.5},
    thigh={k=195,damping=12.5},
  },
  FLOATY={
    targetGain=0.98,
    breast={k=115,damping=5.2},
    thigh={k=105,damping=5.8},
  },
  JELLY={
    targetGain=1.24,
    breast={k=305,damping=2.6},
    thigh={k=270,damping=3.0},
  },
}

-- v3.0.21 doubles the v3.0.20 visible breast-physics strength again while preserving
-- the v3.0.18 responsive spring timing and the user's fixed motion/impact/idle
-- response preset. PHYSICS remains the only user-facing breast-physics control.
local BELLE_RECOMMENDED_PHYSICS={
  hz=120,
  motion=0.40,
  impact=1.05,
  idle=0.78,
  response=0.83,
  breastStrength=1.35,
  buttStrength=1.22,
  thighStrength=0.92,
  hairStrength=1.10,
  style={
    targetGain=1.04,
    breast={k=680,damping=7.4},
    butt={k=520,damping=8.8},
    thigh={k=500,damping=9.8},
    hair={k=210,damping=7.6},
  },
}

local function bellePhysicsStyle(data)
  local key=tostring(data and data.runtimeBellePhysicsStyle or 'NATURAL'):upper()
  return BELLE_PHYSICS_STYLES[key] or BELLE_PHYSICS_STYLES.NATURAL,key
end

local function bellePhysicsTuning(data,key,default,minValue,maxValue)
  local v=tonumber(data and data[key]) or default
  if v<minValue then v=minValue elseif v>maxValue then v=maxValue end
  return v
end

-- Dedicated runtime gate. The checkbox, preview, gameplay skeleton and
-- post-skin follow layer all read this same boolean, rather than inferring ON/OFF
-- from a saved key or from the numeric strength value.
local function belleBreastPhysicsEnabled(data)
  if not data then return false end
  local v=data.runtimeBellePhysicsEnabled
  if v==nil then
    return bellePhysicsStrength(data,'runtimeBelleBreastPhysics')>0
  end
  if v==false or v==0 or v=='0' or tostring(v):lower()=='false' then return false end
  return true
end

local function belleButtPhysicsEnabled(data)
  if not data then return false end
  local v=data.runtimeBelleButtocksEnabled
  if v==nil then
    return bellePhysicsStrength(data,'runtimeBelleButtocksPhysics')>0
  end
  if v==false or v==0 or v=='0' or tostring(v):lower()=='false' then return false end
  return true
end

local function belleThighPhysicsEnabled(data)
  if not data then return false end
  local v=data.runtimeBelleThighEnabled
  if v==nil then
    return bellePhysicsStrength(data,'runtimeBelleThighPhysics')>0
  end
  if v==false or v==0 or v=='0' or tostring(v):lower()=='false' then return false end
  return true
end

local function belleHairPhysicsEnabled(data)
  if not data then return false end
  local v=data.runtimeBelleHairEnabled
  if v==nil then
    return bellePhysicsStrength(data,'runtimeBelleHairPhysics')>0
  end
  if v==false or v==0 or v=='0' or tostring(v):lower()=='false' then return false end
  return true
end

local function bellePhysicsEnabled(data)
  return belleBreastPhysicsEnabled(data) or belleButtPhysicsEnabled(data) or belleThighPhysicsEnabled(data) or belleHairPhysicsEnabled(data)
end

local function bellePhysicsAxisMode(data)
  local mode=tostring(data and data.runtimeBellePhysicsAxes or 'FULL'):upper()
  if mode~='FULL' and mode~='VERTICAL' and mode~='DEPTH' and mode~='SIDE' then mode='FULL' end
  return mode
end

local function belleAxisTargets(data,x,y,z)
  local mode=bellePhysicsAxisMode(data)
  if mode=='VERTICAL' then return 0,y,0 end
  if mode=='DEPTH' then return 0,0,z end
  if mode=='SIDE' then return x,0,0 end
  return x,y,z
end

local function belleSecondaryDelta(data,bone,phase,motionBlend,jumpT)
  local A=data.animBone or {}
  -- v3.0.42: buttocks physics is post-skin only. Keeping the butt helper bones
  -- neutral prevents Belle from receiving the same butt motion twice.
  if bone==A.LThighSoft or bone==A.RThighSoft or bone==A.LButt or bone==A.RButt then
    return {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
  end
  local isSecondary=(bone==A.LBreast or bone==A.RBreast)
  if not isSecondary then return nil end
  -- Wow's source mesh uses corrected post-skin masks instead of helper-bone
  -- deformation for secondary motion, so keep the appended helpers neutral.
  if data.runtimeProfile=="WOW_FBX" then
    return {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
  end
  if not bellePhysicsEnabled(data) then
    return {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
  end
  local soft=data.runtimeBelleSoft
  if not soft then
    return {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
  end

  local node=nil
  local strength=1.0
  local translateGain=1.0
  local pitchGain=0.0
  local rollGain=0.0

  if bone==A.LBreast then
    if not belleBreastPhysicsEnabled(data) then
      return {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
    end
    node=soft.breastL
    strength=bellePhysicsStrength(data,'runtimeBelleBreastPhysics')
    translateGain=1.35; pitchGain=11.0; rollGain=-4.0
  elseif bone==A.RBreast then
    if not belleBreastPhysicsEnabled(data) then
      return {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
    end
    node=soft.breastR
    strength=bellePhysicsStrength(data,'runtimeBelleBreastPhysics')
    translateGain=1.35; pitchGain=11.0; rollGain=4.0
  else
    return nil
  end

  if not node or strength<=0 then
    return {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
  end

  -- These six helper bones have real skin weights in bellestarmon_model.lua.
  -- Drive them directly so the soft tissue is part of the skeletal deformation
  -- rather than merely receiving a tiny post-skin screen/world-space offset.
  -- A small rotational component makes the weighted region flex around its own
  -- anatomical pivot while the translation supplies the visible spring travel.
  local x=(tonumber(node.x) or 0)*strength
  local y=(tonumber(node.y) or 0)*strength
  local z=(tonumber(node.z) or 0)*strength
  local t=translate16(x*translateGain,y*translateGain,z*translateGain)
  local pitch=rotX(math.rad(y*pitchGain))
  local roll=rotZ(math.rad(x*rollGain))
  return compose3(t,pitch,roll)
end

local function belleLocomotionDelta(data,bone,phase,motionBlend)
  local secondary=belleSecondaryDelta(data,bone,phase,motionBlend,nil)
  if secondary then return secondary end
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
  local secondary=belleSecondaryDelta(data,bone,phase,motionBlend,t)
  if secondary then return secondary end
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

local function wowIdleDelta(data,bone)
  if data.idleDelta and data.idleFrameCount and data.idleFrameCount>1 then
    return sampleEmbeddedClipRigid(data.idleDelta,data.idleFrameCount,bone,data.runtimeWowIdlePhase or 0,false)
  end
  return nil
end

local function wowRootMotionFreeLoop(data,clip,n,bone,phase)
  -- v3.0.62: Mixamo's Catwalk and Goofy Run are authored as traveling clips.
  -- Their final key is the same cycle pose as frame zero, but Hips has moved
  -- forward by ~1.38 / ~1.41 model units. The player entity already supplies
  -- world translation, so keeping that FBX root travel made Wow slide forward
  -- through the cycle and then visibly reset at the seam. Sample the clips as
  -- ordinary duplicate-closing loops and subtract only the accumulated X/Z
  -- root drift. Vertical Hips motion is preserved for the authored body bob.
  local out=sampleEmbeddedClipRigid(clip,n,bone,phase,false)
  if not out then return nil end
  local A=data.animBone or {}
  if bone==A.Hips and type(clip)=="table" and tonumber(n) and n>1 then
    local p=wrap01(phase or 0)
    local last=(n-1)*16
    local sx=tonumber(clip[4]) or tonumber(out[4]) or 0
    local sz=tonumber(clip[12]) or tonumber(out[12]) or 0
    local ex=tonumber(clip[last+4]) or sx
    local ez=tonumber(clip[last+12]) or sz
    -- Remove the whole linear travel path, including its initial offset,
    -- while leaving small cyclic deviations around that path intact.
    out[4]=(tonumber(out[4]) or sx)-(sx+(ex-sx)*p)
    out[12]=(tonumber(out[12]) or sz)-(sz+(ez-sz)*p)
  end
  return out
end

local function wowLockJumpRoot(data,clip,bone,out)
  -- Jump clips are also traveling animations. Running Jump contains more than
  -- seven model units of forward Hips travel. Gameplay/player movement already
  -- moves Wow, so neutralize only the horizontal root channels while retaining
  -- the authored vertical jump/compression on Hips.
  if not out then return nil end
  local A=data.animBone or {}
  if bone==A.Hips and type(clip)=="table" then
    out[4]=0
    out[12]=0
  end
  return out
end

local function wowEmbeddedDelta(data,bone,phase,blend)
  -- Wow uses the user's native Mixamo skin and exact supplied clips. Rigid
  -- quaternion interpolation keeps joints orthonormal, while v3.0.62 removes
  -- the FBX's baked forward root travel so walk/run loops stay spatially fixed.
  local secondary=belleSecondaryDelta(data,bone,phase,blend,nil)
  if secondary then return secondary end
  local idle=wowIdleDelta(data,bone)
  local walk=wowRootMotionFreeLoop(data,data.walkDelta,data.walkFrameCount,bone,phase)
  local run=wowRootMotionFreeLoop(data,data.runDelta,data.runFrameCount,bone,phase)
  local rb=tonumber(data.runtimeWowRunBlend) or 0
  if rb<0 then rb=0 elseif rb>1 then rb=1 end
  rb=rb*rb*(3-2*rb)
  local locomotion=walk or run or idle
  if walk and run then locomotion=red3dRigidBlend16(walk,run,rb) end
  local move=tonumber(blend) or 0
  if move<0 then move=0 elseif move>1 then move=1 end
  move=move*move*(3-2*move)
  return red3dRigidBlend16(idle,locomotion,move)
end

local function wowJumpDelta(data,bone,t,phase,motionBlend)
  local secondary=belleSecondaryDelta(data,bone,phase,motionBlend,t)
  if secondary then return secondary end
  local tt=math.max(0,math.min(1,tonumber(t) or 0))
  local base=wowEmbeddedDelta(data,bone,phase,motionBlend)

  -- Do not cram the complete ~1.9-2.1 second source files into a ~0.5 second
  -- Gen1 hop. Use the useful middle 56% of the authored jump with a quintic
  -- time curve, then softly enter/leave it from the current locomotion pose.
  -- The manual cosmetic jump is also lengthened below to 48 frames for Wow.
  local eased=tt*tt*tt*(tt*(tt*6-15)+10)
  local sourceT=0.12 + 0.56*eased
  local stand=sampleEmbeddedClipRigid(data.jumpDelta,data.jumpFrameCount,bone,sourceT,false)
  local running=sampleEmbeddedClipRigid(data.runningJumpDelta,data.runningJumpFrameCount,bone,sourceT,false)
  stand=wowLockJumpRoot(data,data.jumpDelta,bone,stand)
  running=wowLockJumpRoot(data,data.runningJumpDelta,bone,running)

  -- Merely walking used to select Running Jump at full strength because the
  -- old blend used generic motionBlend. Only blend toward Running Jump when
  -- Wow is actually in her Goofy Run blend.
  local moving=math.max(0,math.min(1,tonumber(motionBlend) or 0))
  local runMix=math.max(0,math.min(1,tonumber(data.runtimeWowRunBlend) or 0))*moving
  runMix=runMix*runMix*(3-2*runMix)
  local jump=stand or running
  if stand and running then jump=red3dRigidBlend16(stand,running,runMix) end
  if not jump then return base end

  local function smooth(x)
    if x<=0 then return 0 elseif x>=1 then return 1 end
    return x*x*(3-2*x)
  end
  local w=math.min(smooth(tt/0.16),smooth((1-tt)/0.24))
  return red3dRigidBlend16(base,jump,w)
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

  -- v3.0.56: Wow ships three user-supplied static selector poses. The current
  -- pose is selected from Character Settings and only affects the Skin Selector
  -- preview; overworld idle/walk/run/jump continue to use their authored clips.
  if data.runtimeSkinSelectorPreview and data.runtimeCharacterId=="WOW" then
    local poseIndex=math.floor(tonumber(data.runtimeWowSelectorPose) or 1)
    if poseIndex<1 then poseIndex=1 elseif poseIndex>3 then poseIndex=3 end
    local clip=data["selectorPose"..tostring(poseIndex).."Delta"]
    if clip then
      local out={}; local base=(bone-1)*16
      for k=1,16 do out[k]=clip[base+k] end
      if type(out[1])=="number" then return out end
    end
  end

  -- v3.1.9: BelleStarmon no longer exposes or applies the old retargeted
  -- static selector poses. Its portrait always uses the dedicated selector-idle
  -- animation below, while Wow keeps its own three-pose selector feature.

  -- Legacy Skin Selector-only BelleStarmon animation fallback. The preview
  -- renderer sets this flag only around its own updateSkeleton() call.
  if data.runtimeSkinSelectorPreview and data.runtimeCharacterId=="BELLESTARMON"
      and data.selectorIdleDelta and (data.selectorIdleFrameCount or 0)>1 then
    local secondary=belleSecondaryDelta(data,bone,phase,blend,nil)
    if secondary then return secondary end
    local selectorPhase=tonumber(data.runtimeSelectorIdlePhase) or phase
    local selectorDelta=sampleEmbeddedClip(data.selectorIdleDelta,data.selectorIdleFrameCount,bone,selectorPhase)
    if selectorDelta then return selectorDelta end
  end

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
  elseif data.runtimeProfile=="WOW_FBX" and data.runDelta then
    return wowEmbeddedDelta(data,bone,phase,blend)
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
  -- v3.1.13: movement animation follows ACTUAL travel, not only the engine's
  -- four-way `moving` flag. The eight-way patch can be observed through
  -- different player/pose wrappers in Gen 1, Gen 2 and Dramatic Shape; some of
  -- those wrappers expose the changing world position before/without a reliable
  -- `moving` boolean. Treat the explicit diagonal marker, an outstanding target
  -- cell, and real render-space displacement as equivalent locomotion signals.
  local walking = (player.moving == true)
      or (player.red3dDiagonalMove == true)
      or (player.bumpFrames and player.bumpFrames > 0)
      or (player.stepLanded == true)

  if player.targetX~=nil and player.targetY~=nil then
    local cx=tonumber(player.cellX)
    local cy=tonumber(player.cellY)
    local tx=tonumber(player.targetX)
    local ty=tonumber(player.targetY)
    if cx and cy and tx and ty and (tx~=cx or ty~=cy) then walking=true end
  end

  local x=tonumber(px) or tonumber(player.px) or 0
  local y=tonumber(py) or tonumber(player.py) or 0

  if self.motionX==nil or self.motionY==nil then
    self.motionX,self.motionY=x,y
    self.motionSampleTime=now
  end

  local dx,dy=x-self.motionX,y-self.motionY
  local dist=math.sqrt(dx*dx+dy*dy)

  -- A warp/map swap is not a giant jog step. Rebase the sampler immediately
  -- and discard speed history so the first post-load movement cannot inherit a
  -- bogus cadence from coordinates/timestamps belonging to the previous map.
  if dist > 8 then
    self.motionX,self.motionY=x,y
    self.motionSampleTime=now
    self.motionSpeedSamples={}
    self.motionMeasuredSpeed=nil
    self.motionMeasuredStable=false
    dist=0
  elseif dist > 0.0001 then
    -- Real displacement is the final source of truth. This is what fixes
    -- diagonal gliding with an idle skeleton when the host's movement flag is
    -- stale or belongs to a different wrapper object.
    walking=true
  end

  if dist > 0.0001 then
    if now and self.motionSampleTime then
      local sampleDt=now-self.motionSampleTime
      -- v3.0.27: reject implausibly tiny startup/render-boundary samples. A
      -- single 240 Hz render slice used to turn a one-pixel position change
      -- into a near-240 px/s gait and could make animations boot very fast.
      if sampleDt >= (1/180) and sampleDt < 0.20 then
        local measured=dist/sampleDt
        if measured >= 8 and measured <= 240 then
          local samples=self.motionSpeedSamples or {}
          samples[#samples+1]=measured
          while #samples>5 do table.remove(samples,1) end
          self.motionSpeedSamples=samples

          -- Median-of-five is deliberately used instead of an EMA so one
          -- scheduling outlier cannot poison the startup cadence.
          local sorted={}
          for i=1,#samples do sorted[i]=samples[i] end
          table.sort(sorted)
          local n=#sorted
          local median
          if n%2==1 then median=sorted[(n+1)/2]
          else median=(sorted[n/2]+sorted[n/2+1])*0.5 end
          self.motionMeasuredSpeed=median
          self.motionMeasuredStable=(n>=3)
        end
      elseif sampleDt < 0 or sampleDt >= 0.20 then
        self.motionSpeedSamples={}
        self.motionMeasuredSpeed=nil
        self.motionMeasuredStable=false
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

function Renderer:updateBelleKeyboardWalkToggle()
  if self.behaviorId~="BELLESTARMON" then return end
  local down=false
  if love and love.keyboard and love.keyboard.isDown then
    down=love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
  end
  if down and not self.belleCtrlWasDown then
    self.belleKeyboardWalk=not self.belleKeyboardWalk
    if self.mod and self.mod.log and self.mod.log.info then
      self.mod.log:info("BelleStarmon keyboard locomotion: %s",self.belleKeyboardWalk and "WALK" or "RUN")
    end
  end
  self.belleCtrlWasDown=down
  self.data.runtimeBelleKeyboardWalk=self.belleKeyboardWalk==true
end

function Renderer:belleRunTarget(player,walking)
  if self.behaviorId~="BELLESTARMON" or not walking then return 0 end
  local x=tonumber(player and player.red3dMoveStickX) or 0
  local y=tonumber(player and player.red3dMoveStickY) or 0
  local mag=math.sqrt(x*x+y*y)
  if mag>1 then mag=1 end
  local analog=(player and player.red3dAnalogMoveActive==true and mag>0.08)
  if not analog then
    -- Ctrl is a true toggle for keyboard/digital movement: WALK when enabled,
    -- Fast Run when disabled. Analog-stick pressure always keeps its continuous
    -- idle -> walk -> run behavior regardless of the keyboard toggle.
    return self.belleKeyboardWalk and 0 or 1
  end
  local start=CONFIG.belleRunBlendStart or 0.55
  local full=CONFIG.belleRunBlendFull or 0.92
  if mag<=start then return 0 end
  if mag>=full then return 1 end
  return smooth01((mag-start)/(full-start))
end

local function belleSpringAxis(node,key,target,k,damping,dt)
  local vk=key.."v"
  local p=tonumber(node[key]) or 0
  local v=tonumber(node[vk]) or 0
  v=v+(target-p)*k*dt
  v=v*math.exp(-damping*dt)
  p=p+v*dt
  node[key]=p; node[vk]=v
end

local BELLE_PHYSICS_HZ_ALLOWED={60,90,120,144,240}

local function bellePhysicsHz(data)
  local requested=tonumber(data and data.runtimeBellePhysicsHz) or 120
  local best=120
  local bestDist=math.huge
  for _,hz in ipairs(BELLE_PHYSICS_HZ_ALLOWED) do
    local dist=math.abs(requested-hz)
    if dist<bestDist then best=hz; bestDist=dist end
  end
  return best
end

local function belleSpring3(node,tx,ty,tz,k,damping,dt,hz)
  -- v3.0.38 butter-smooth solver: keep the authored 120 Hz response profile,
  -- but internally oversample the numerical integration at no less than 240 Hz.
  -- The extra substeps are tiny (only two breast bodies) and make the spring
  -- much less sensitive to uneven phone frame times without changing the user's
  -- strength setting or coupling the left/right simulations.
  dt=tonumber(dt) or 0
  if dt<=0 then return end
  hz=tonumber(hz) or 120
  if hz<1 then hz=120 end
  local solverHz=math.max(240,hz)
  local steps=math.max(1,math.ceil(dt*solverHz))
  -- updateBelleBodyPhysics clamps dt to 50 ms, so 16 steps safely covers the
  -- worst case at 240 Hz while preventing a long hitch from causing a work spike.
  if steps>16 then steps=16 end
  local h=dt/steps
  for _=1,steps do
    belleSpringAxis(node,"x",tx,k,damping,h)
    belleSpringAxis(node,"y",ty,k,damping,h)
    belleSpringAxis(node,"z",tz,k,damping,h)
  end
end

local function belleSmoothExp(current,target,rate,dt)
  target=tonumber(target) or 0
  current=tonumber(current)
  if current==nil then return target end
  dt=tonumber(dt) or 0
  if dt<=0 then return current end
  rate=tonumber(rate) or 1
  if rate<0 then rate=0 end
  local a=1-math.exp(-rate*dt)
  return current+(target-current)*a
end

local function belleSmoothDrive(state,tx,ty,tz,dt)
  state=state or {}
  -- Target filtering removes one-frame gait/animation spikes before they reach
  -- the spring. Rates are intentionally fast enough to preserve bounce while
  -- rejecting the high-frequency twitch that is most visible on phones.
  state.x=belleSmoothExp(state.x,tx,28,dt)
  state.y=belleSmoothExp(state.y,ty,25,dt)
  state.z=belleSmoothExp(state.z,tz,26,dt)
  return state,state.x,state.y,state.z
end

local function belleSmoothRenderNode(out,sim,dt)
  out=out or {}
  sim=sim or {}
  -- A second, frame-rate-independent presentation filter hides residual solver
  -- quantization without feeding the filtered result back into the simulation.
  -- The actual spring stays lively underneath; only the rendered position is
  -- softened. Left and right still use completely separate states.
  out.x=belleSmoothExp(out.x,sim.x,36,dt)
  out.y=belleSmoothExp(out.y,sim.y,32,dt)
  out.z=belleSmoothExp(out.z,sim.z,34,dt)
  out.xv=tonumber(sim.xv) or 0
  out.yv=tonumber(sim.yv) or 0
  out.zv=tonumber(sim.zv) or 0
  return out
end

function Renderer:updateBelleBodyPhysics(player,walking,dt,preview)
  if self.behaviorId~="BELLESTARMON" and self.behaviorId~="WOW" then return end
  dt=tonumber(dt) or (1/60)
  if dt<0 then dt=0 elseif dt>0.05 then dt=0.05 end

  local S=self.belleSoft
  if not S then
    S={breastL={},breastR={},buttL={},buttR={},thighL={},thighR={},hairL={},hairR={},hairTailL={},hairTailR={}}
    self.belleSoft=S
  end
  S.breastL=S.breastL or {}
  S.breastR=S.breastR or {}
  S.buttL=S.buttL or {}
  S.buttR=S.buttR or {}
  S.thighL=S.thighL or {}
  S.thighR=S.thighR or {}
  S.hairL=S.hairL or {}
  S.hairR=S.hairR or {}
  S.hairTailL=S.hairTailL or {}
  S.hairTailR=S.hairTailR or {}

  -- v3.0.38 keeps the numerical spring and the displayed spring position in
  -- separate nodes. This is important: smoothing what is drawn must never feed
  -- back into velocity/integration, or the solver can fight its own filter and
  -- create the exact micro-twitch this update is meant to remove. Existing
  -- v3.0.37 enable-kick state is copied into the sim nodes on first use.
  if not S.simBreastL then
    S.simBreastL={x=tonumber(S.breastL.x) or 0,y=tonumber(S.breastL.y) or 0,z=tonumber(S.breastL.z) or 0,
      xv=tonumber(S.breastL.xv) or 0,yv=tonumber(S.breastL.yv) or 0,zv=tonumber(S.breastL.zv) or 0}
  end
  if not S.simBreastR then
    S.simBreastR={x=tonumber(S.breastR.x) or 0,y=tonumber(S.breastR.y) or 0,z=tonumber(S.breastR.z) or 0,
      xv=tonumber(S.breastR.xv) or 0,yv=tonumber(S.breastR.yv) or 0,zv=tonumber(S.breastR.zv) or 0}
  end
  if not S.simButtL then
    S.simButtL={x=tonumber(S.buttL.x) or 0,y=tonumber(S.buttL.y) or 0,z=tonumber(S.buttL.z) or 0,
      xv=tonumber(S.buttL.xv) or 0,yv=tonumber(S.buttL.yv) or 0,zv=tonumber(S.buttL.zv) or 0}
  end
  if not S.simButtR then
    S.simButtR={x=tonumber(S.buttR.x) or 0,y=tonumber(S.buttR.y) or 0,z=tonumber(S.buttR.z) or 0,
      xv=tonumber(S.buttR.xv) or 0,yv=tonumber(S.buttR.yv) or 0,zv=tonumber(S.buttR.zv) or 0}
  end
  if not S.simThighL then
    S.simThighL={x=tonumber(S.thighL.x) or 0,y=tonumber(S.thighL.y) or 0,z=tonumber(S.thighL.z) or 0,
      xv=tonumber(S.thighL.xv) or 0,yv=tonumber(S.thighL.yv) or 0,zv=tonumber(S.thighL.zv) or 0}
  end
  if not S.simThighR then
    S.simThighR={x=tonumber(S.thighR.x) or 0,y=tonumber(S.thighR.y) or 0,z=tonumber(S.thighR.z) or 0,
      xv=tonumber(S.thighR.xv) or 0,yv=tonumber(S.thighR.yv) or 0,zv=tonumber(S.thighR.zv) or 0}
  end
  if not S.simHairL then
    S.simHairL={x=tonumber(S.hairL.x) or 0,y=tonumber(S.hairL.y) or 0,z=tonumber(S.hairL.z) or 0,
      xv=tonumber(S.hairL.xv) or 0,yv=tonumber(S.hairL.yv) or 0,zv=tonumber(S.hairL.zv) or 0}
  end
  if not S.simHairR then
    S.simHairR={x=tonumber(S.hairR.x) or 0,y=tonumber(S.hairR.y) or 0,z=tonumber(S.hairR.z) or 0,
      xv=tonumber(S.hairR.xv) or 0,yv=tonumber(S.hairR.yv) or 0,zv=tonumber(S.hairR.zv) or 0}
  end
  if not S.simHairTailL then
    S.simHairTailL={x=tonumber(S.hairTailL.x) or 0,y=tonumber(S.hairTailL.y) or 0,z=tonumber(S.hairTailL.z) or 0,
      xv=tonumber(S.hairTailL.xv) or 0,yv=tonumber(S.hairTailL.yv) or 0,zv=tonumber(S.hairTailL.zv) or 0}
  end
  if not S.simHairTailR then
    S.simHairTailR={x=tonumber(S.hairTailR.x) or 0,y=tonumber(S.hairTailR.y) or 0,z=tonumber(S.hairTailR.z) or 0,
      xv=tonumber(S.hairTailR.xv) or 0,yv=tonumber(S.hairTailR.yv) or 0,zv=tonumber(S.hairTailR.zv) or 0}
  end

  -- OFF means fully neutral immediately. Do not keep integrating hidden spring
  -- velocity in the background; this also makes an ON click visibly start from
  -- a clean neutral state instead of inheriting stale momentum.
  if not bellePhysicsEnabled(self.data) then
    for _,node in ipairs({S.breastL,S.breastR,S.simBreastL,S.simBreastR,S.buttL,S.buttR,S.simButtL,S.simButtR,S.thighL,S.thighR,S.simThighL,S.simThighR,S.hairL,S.hairR,S.simHairL,S.simHairR,S.hairTailL,S.hairTailR,S.simHairTailL,S.simHairTailR}) do
      node.x,node.y,node.z=0,0,0
      node.xv,node.yv,node.zv=0,0,0
    end
    S.driveL=nil; S.driveR=nil; S.buttDriveL=nil; S.buttDriveR=nil; S.thighDriveL=nil; S.thighDriveR=nil; S.hairDriveL=nil; S.hairDriveR=nil; S.hairTailDriveL=nil; S.hairTailDriveR=nil
    self.belleSoftSpeed=nil
    self.belleSoftAccel=nil
    self.belleSoftWasJumping=nil
    self.bellePreviewKickWave=nil
    self.data.runtimeBelleSoft=S
    return
  end

  local rb,phase
  if self.behaviorId=="WOW" then
    rb=tonumber(self.wowRunBlend) or tonumber(self.data.runtimeWowRunBlend) or 0
    local cp=self:cyclePixels()
    if cp<1 then cp=1 end
    phase=((tonumber(self.voxelGaitDistance) or tonumber(self.motionDistance) or 0)/cp)%1
  else
    rb=tonumber(self.belleRunBlend) or tonumber(self.data.runtimeBelleRunBlend) or 0
    phase=tonumber(self.belleGaitPhase) or 0
  end
  if rb<0 then rb=0 elseif rb>1 then rb=1 end
  local move=tonumber(self.voxelMoveBlend) or (walking and 1 or 0)
  if move<0 then move=0 elseif move>1 then move=1 end

  if preview then
    -- A gentle continuous demo in the selector keeps enabled physics visible
    -- without needing to move the player in the world.
    phase=(runtimeClock()*0.72)%1
    move=0.58
    rb=0.28
  end

  local speed=tonumber(self.voxelSmoothSpeed) or tonumber(self.motionMeasuredSpeed) or 0
  if preview then speed=42 end
  local s=math.max(0,math.min(1.35,speed/78))
  local prev=tonumber(self.belleSoftSpeed) or s
  local rawAccel=(dt>0.0001) and ((s-prev)/dt) or 0
  self.belleSoftSpeed=s
  if rawAccel>6 then rawAccel=6 elseif rawAccel<-6 then rawAccel=-6 end
  -- Differentiating even a smoothed movement speed can amplify tiny frame-time
  -- noise. Low-pass the acceleration drive before it contributes to the chest
  -- target so irregular phone frames cannot show up as single-frame jerks.
  local accel=belleSmoothExp(self.belleSoftAccel,rawAccel,13,dt)
  self.belleSoftAccel=accel

  local energy=move*(0.50+0.50*rb)
  local gait=math.sin((phase+0.025)*math.pi*4.0)
  local follow=math.sin((phase+0.17)*math.pi*4.0)
  local step=math.sin(phase*math.pi*2.0)
  local physicsClock=runtimeClock()
  -- v3.0.37: each breast gets its own idle oscillator. These are deliberately
  -- different frequencies/phases so the two independent spring bodies never
  -- collapse into perfectly mirrored motion while standing still.
  local idleL=math.sin(physicsClock*math.pi*1.29+0.27)
  local idleR=math.sin(physicsClock*math.pi*1.43+1.61)

  local jt=nil
  if not preview and player then jt=jumpProgress(player) end
  local jumpPulse=0
  if preview then
    -- Periodic preview impulse demonstrates the recommended landing response
    -- without requiring the character to leave the selector screen.
    jumpPulse=math.sin(runtimeClock()*math.pi*0.92)*0.58
  elseif jt~=nil then
    jt=math.max(0,math.min(1,tonumber(jt) or 0))
    -- Strong takeoff/landing impulses feed an under-damped spring; the spring
    -- itself provides the delayed overshoot rather than a canned sine jiggle.
    jumpPulse=math.sin(jt*math.pi*2.0)*(1.0-jt*0.18)
  end

  -- The spring character stays fixed to the responsive preset. Only the
  -- PHYSICS checkbox is user-facing; legacy tuning values do not affect it.
  local style=BELLE_RECOMMENDED_PHYSICS.style
  local gain=style.targetGain
  local motionGain=bellePhysicsTuning(self.data,'runtimeBelleMotionPhysics',BELLE_RECOMMENDED_PHYSICS.motion,0,2)
  local impactGain=bellePhysicsTuning(self.data,'runtimeBelleImpactPhysics',BELLE_RECOMMENDED_PHYSICS.impact,0,2)
  local idleGain=bellePhysicsTuning(self.data,'runtimeBelleIdlePhysics',BELLE_RECOMMENDED_PHYSICS.idle,0,2)
  local response=bellePhysicsTuning(self.data,'runtimeBelleResponseSpeed',BELLE_RECOMMENDED_PHYSICS.response,0.5,2)
  local responseK=response*response
  local hz=BELLE_RECOMMENDED_PHYSICS.hz
  local function spring(node,tx,ty,tz,profile)
    -- Recommended mode is always FULL 3D.
    belleSpring3(node,tx,ty,tz,profile.k*responseK,profile.damping*response,dt,hz)
  end

  -- v3.0.37 independent breast bodies. Left and right are intentionally driven
  -- by different gait phases, different idle oscillators, alternating footfall
  -- impulses, and slightly different spring responses below. There is no
  -- left/right position or velocity coupling: the single user slider only
  -- scales the final visible amount, not the relationship between the bodies.
  local breastWaveL=math.sin((phase+0.018)*math.pi*4.0)
  local breastWaveR=math.sin((phase+0.148)*math.pi*4.0)
  local breastFollowL=math.sin((phase+0.105)*math.pi*4.0)
  local breastFollowR=math.sin((phase+0.255)*math.pi*4.0)
  local breastSideL=math.sin((phase+0.055)*math.pi*2.0)
  local breastSideR=math.sin((phase+0.365)*math.pi*2.0)

  -- Alternate impacts by stride side. Squaring the positive half-wave makes a
  -- short smooth impulse rather than a hard sign flip, so one breast can still
  -- be settling while the other receives the next step.
  local stride=math.sin((phase+0.02)*math.pi*2.0)
  local stepKickL=math.max(0,stride); stepKickL=stepKickL*stepKickL
  local stepKickR=math.max(0,-stride); stepKickR=stepKickR*stepKickR

  local jumpL=jumpPulse
  local jumpR=jumpPulse*0.91
  local chestYL=(0.009*idleL*idleGain + 0.196*breastWaveL*energy*motionGain + 0.028*stepKickL*energy*motionGain + 0.250*jumpL*impactGain - 0.016*accel*motionGain)*gain
  local chestYR=(0.009*idleR*idleGain + 0.190*breastWaveR*energy*motionGain + 0.030*stepKickR*energy*motionGain + 0.232*jumpR*impactGain - 0.014*accel*motionGain)*gain
  local chestZL=(0.005*idleL*idleGain + 0.088*breastFollowL*energy*motionGain + 0.010*stepKickL*energy*motionGain + 0.115*jumpL*impactGain + 0.006*accel*motionGain)*gain
  local chestZR=(0.005*idleR*idleGain + 0.083*breastFollowR*energy*motionGain + 0.012*stepKickR*energy*motionGain + 0.103*jumpR*impactGain + 0.005*accel*motionGain)*gain
  local chestXL=(0.0058*breastSideL*energy*motionGain)*gain
  local chestXR=(0.0055*breastSideR*energy*motionGain)*gain

  -- Clamp the drive target before it reaches the spring. This prevents a rare
  -- animation/acceleration spike from slamming the spring into its final safety
  -- bounds and producing a visible snap-back.
  local function clampTarget(v,limit)
    if v>limit then return limit elseif v<-limit then return -limit end
    return v
  end
  chestXL=clampTarget(chestXL,0.020); chestXR=clampTarget(chestXR,0.020)
  chestYL=clampTarget(chestYL,0.145); chestYR=clampTarget(chestYR,0.145)
  chestZL=clampTarget(chestZL,0.085); chestZR=clampTarget(chestZR,0.085)
  if self.data.runtimeBelleBreastIndependent==false then
    chestXR=-chestXL
    chestYR=chestYL
    chestZR=chestZL
  end

  -- Smooth each side's target independently before spring integration. This
  -- preserves the v3.0.37 left/right timing differences while removing tiny
  -- target discontinuities from animation sampling and uneven movement input.
  S.driveL,chestXL,chestYL,chestZL=belleSmoothDrive(S.driveL,chestXL,chestYL,chestZL,dt)
  S.driveR,chestXR,chestYR,chestZR=belleSmoothDrive(S.driveR,chestXR,chestYR,chestZR,dt)

  local buttWaveL=math.sin((phase+0.09)*math.pi*4.0)
  local buttWaveR=math.sin((phase+0.24)*math.pi*4.0)
  local buttFollowL=math.sin((phase+0.21)*math.pi*4.0)
  local buttFollowR=math.sin((phase+0.34)*math.pi*4.0)
  local buttSideL=math.sin((phase+0.16)*math.pi*2.0)
  local buttSideR=math.sin((phase+0.44)*math.pi*2.0)
  local hipDropL=math.max(0,-stride); hipDropL=hipDropL*hipDropL
  local hipDropR=math.max(0,stride); hipDropR=hipDropR*hipDropR
  local buttYL=(0.004*idleL*idleGain + 0.050*buttWaveL*energy*motionGain + 0.012*hipDropL*energy*motionGain + 0.060*jumpL*impactGain - 0.006*accel*motionGain)*gain
  local buttYR=(0.004*idleR*idleGain + 0.048*buttWaveR*energy*motionGain + 0.013*hipDropR*energy*motionGain + 0.056*jumpR*impactGain - 0.006*accel*motionGain)*gain
  local buttZL=(0.003*idleL*idleGain + 0.040*buttFollowL*energy*motionGain + 0.008*hipDropL*energy*motionGain + 0.048*jumpL*impactGain + 0.003*accel*motionGain)*gain
  local buttZR=(0.003*idleR*idleGain + 0.038*buttFollowR*energy*motionGain + 0.008*hipDropR*energy*motionGain + 0.044*jumpR*impactGain + 0.003*accel*motionGain)*gain
  local buttXL=(0.0040*buttSideL*energy*motionGain)*gain
  local buttXR=(0.0037*buttSideR*energy*motionGain)*gain
  buttXL=clampTarget(buttXL,0.016); buttXR=clampTarget(buttXR,0.016)
  buttYL=clampTarget(buttYL,0.080); buttYR=clampTarget(buttYR,0.080)
  buttZL=clampTarget(buttZL,0.060); buttZR=clampTarget(buttZR,0.060)
  if self.data.runtimeBelleButtIndependent==false then
    buttXR=-buttXL
    buttYR=buttYL
    buttZR=buttZL
  end
  S.buttDriveL,buttXL,buttYL,buttZL=belleSmoothDrive(S.buttDriveL,buttXL,buttYL,buttZL,dt)
  S.buttDriveR,buttXR,buttYR,buttZR=belleSmoothDrive(S.buttDriveR,buttXR,buttYR,buttZR,dt)

  local thighWaveL=math.sin((phase+0.04)*math.pi*4.0)
  local thighWaveR=math.sin((phase+0.29)*math.pi*4.0)
  local thighFollowL=math.sin((phase+0.12)*math.pi*4.0)
  local thighFollowR=math.sin((phase+0.37)*math.pi*4.0)
  local thighSideL=math.sin((phase+0.09)*math.pi*2.0)
  local thighSideR=math.sin((phase+0.41)*math.pi*2.0)
  local thighYL=(0.002*idleL*idleGain + 0.028*thighWaveL*energy*motionGain + 0.008*stepKickL*energy*motionGain + 0.040*jumpL*impactGain - 0.004*accel*motionGain)*gain
  local thighYR=(0.002*idleR*idleGain + 0.028*thighWaveR*energy*motionGain + 0.008*stepKickR*energy*motionGain + 0.038*jumpR*impactGain - 0.004*accel*motionGain)*gain
  local thighZL=(0.002*idleL*idleGain + 0.020*thighFollowL*energy*motionGain + 0.006*stepKickL*energy*motionGain + 0.028*jumpL*impactGain + 0.003*accel*motionGain)*gain
  local thighZR=(0.002*idleR*idleGain + 0.020*thighFollowR*energy*motionGain + 0.006*stepKickR*energy*motionGain + 0.027*jumpR*impactGain + 0.003*accel*motionGain)*gain
  local thighXL=(0.0034*thighSideL*energy*motionGain)*gain
  local thighXR=(0.0034*thighSideR*energy*motionGain)*gain
  thighXL=clampTarget(thighXL,0.015); thighXR=clampTarget(thighXR,0.015)
  thighYL=clampTarget(thighYL,0.060); thighYR=clampTarget(thighYR,0.060)
  thighZL=clampTarget(thighZL,0.045); thighZR=clampTarget(thighZR,0.045)
  if self.data.runtimeBelleThighIndependent==false then
    thighXR=-thighXL
    thighYR=thighYL
    thighZR=thighZL
  end
  S.thighDriveL,thighXL,thighYL,thighZL=belleSmoothDrive(S.thighDriveL,thighXL,thighYL,thighZL,dt)
  S.thighDriveR,thighXR,thighYR,thighZR=belleSmoothDrive(S.thighDriveR,thighXR,thighYR,thighZR,dt)

  local hairWaveL=math.sin((phase+0.20)*math.pi*2.0)
  local hairWaveR=math.sin((phase+0.33)*math.pi*2.0)
  local hairFollowL=math.sin((phase+0.10)*math.pi*2.0)
  local hairFollowR=math.sin((phase+0.26)*math.pi*2.0)
  local hairYL=(0.006*idleL*idleGain + 0.020*hairWaveL*energy*motionGain + 0.018*jumpL*impactGain - 0.005*accel*motionGain)*gain
  local hairYR=(0.006*idleR*idleGain + 0.020*hairWaveR*energy*motionGain + 0.017*jumpR*impactGain - 0.005*accel*motionGain)*gain
  local hairZL=(0.010*idleL*idleGain + 0.044*hairFollowL*energy*motionGain + 0.030*jumpL*impactGain + 0.008*accel*motionGain)*gain
  local hairZR=(0.010*idleR*idleGain + 0.044*hairFollowR*energy*motionGain + 0.028*jumpR*impactGain + 0.008*accel*motionGain)*gain
  local hairXL=(0.0030*hairWaveL*energy*motionGain)*gain
  local hairXR=(0.0030*hairWaveR*energy*motionGain)*gain
  hairXL=clampTarget(hairXL,0.016); hairXR=clampTarget(hairXR,0.016)
  hairYL=clampTarget(hairYL,0.045); hairYR=clampTarget(hairYR,0.045)
  hairZL=clampTarget(hairZL,0.090); hairZR=clampTarget(hairZR,0.090)
  S.hairDriveL,hairXL,hairYL,hairZL=belleSmoothDrive(S.hairDriveL,hairXL,hairYL,hairZL,dt)
  S.hairDriveR,hairXR,hairYR,hairZR=belleSmoothDrive(S.hairDriveR,hairXR,hairYR,hairZR,dt)

  -- v3.0.49: a second, deliberately slower spring drives only the lower/back
  -- hair, so the ends trail behind instead of the whole hair mass translating.
  local tailWaveL=math.sin((phase+0.38)*math.pi*2.0)
  local tailWaveR=math.sin((phase+0.52)*math.pi*2.0)
  local tailFollowL=math.sin((phase+0.31)*math.pi*2.0)
  local tailFollowR=math.sin((phase+0.47)*math.pi*2.0)
  local tailXL=(hairXL*1.15 + 0.0065*tailWaveL*energy*motionGain*gain)
  local tailXR=(hairXR*1.15 + 0.0065*tailWaveR*energy*motionGain*gain)
  local tailYL=(hairYL*1.10 + 0.018*tailWaveL*energy*motionGain*gain + 0.012*jumpL*impactGain*gain)
  local tailYR=(hairYR*1.10 + 0.018*tailWaveR*energy*motionGain*gain + 0.011*jumpR*impactGain*gain)
  local tailZL=(hairZL*1.20 + 0.072*tailFollowL*energy*motionGain*gain + 0.018*accel*motionGain*gain)
  local tailZR=(hairZR*1.20 + 0.072*tailFollowR*energy*motionGain*gain + 0.017*accel*motionGain*gain)
  tailXL=clampTarget(tailXL,0.030); tailXR=clampTarget(tailXR,0.030)
  tailYL=clampTarget(tailYL,0.080); tailYR=clampTarget(tailYR,0.080)
  tailZL=clampTarget(tailZL,0.155); tailZR=clampTarget(tailZR,0.155)
  S.hairTailDriveL,tailXL,tailYL,tailZL=belleSmoothDrive(S.hairTailDriveL,tailXL,tailYL,tailZL,dt)
  S.hairTailDriveR,tailXR,tailYR,tailZR=belleSmoothDrive(S.hairTailDriveR,tailXR,tailYR,tailZR,dt)

  -- Do not inject raw takeoff/landing velocity kicks. The spring follows the
  -- jump/landing target and supplies its own short overshoot, which is smoother
  -- and prevents the large snap/rebound spikes from v3.0.13/v3.0.14.
  self.belleSoftWasJumping=(jt~=nil)
  self.bellePreviewKickWave=nil

  -- Give each side its own response characteristics as well as its own target.
  -- Small differences are enough to produce natural independent settling
  -- without making one side obviously softer than the other.
  local breastProfileL={k=style.breast.k*0.94,damping=style.breast.damping*0.93}
  local breastProfileR=(self.data.runtimeBelleBreastIndependent==false) and breastProfileL or {k=style.breast.k*1.06,damping=style.breast.damping*1.07}
  if belleBreastPhysicsEnabled(self.data) then
    spring(S.simBreastL, chestXL, chestYL, chestZL, breastProfileL)
    spring(S.simBreastR, chestXR, chestYR, chestZR, breastProfileR)
  else
    for _,node in ipairs({S.breastL,S.breastR,S.simBreastL,S.simBreastR}) do
      node.x,node.y,node.z=0,0,0; node.xv,node.yv,node.zv=0,0,0
    end
  end

  local buttProfileL={k=style.butt.k*0.97,damping=style.butt.damping*0.95}
  local buttProfileR=(self.data.runtimeBelleButtIndependent==false) and buttProfileL or {k=style.butt.k*1.03,damping=style.butt.damping*1.05}
  if belleButtPhysicsEnabled(self.data) then
    spring(S.simButtL, buttXL, buttYL, buttZL, buttProfileL)
    spring(S.simButtR, buttXR, buttYR, buttZR, buttProfileR)
  else
    for _,node in ipairs({S.buttL,S.buttR,S.simButtL,S.simButtR}) do
      node.x,node.y,node.z=0,0,0; node.xv,node.yv,node.zv=0,0,0
    end
  end

  local thighProfileL={k=style.thigh.k*0.98,damping=style.thigh.damping*0.97}
  local thighProfileR=(self.data.runtimeBelleThighIndependent==false) and thighProfileL or {k=style.thigh.k*1.02,damping=style.thigh.damping*1.03}
  if belleThighPhysicsEnabled(self.data) then
    spring(S.simThighL, thighXL, thighYL, thighZL, thighProfileL)
    spring(S.simThighR, thighXR, thighYR, thighZR, thighProfileR)
  else
    for _,node in ipairs({S.thighL,S.thighR,S.simThighL,S.simThighR}) do
      node.x,node.y,node.z=0,0,0; node.xv,node.yv,node.zv=0,0,0
    end
  end

  local hairProfileL={k=style.hair.k*0.97,damping=style.hair.damping*0.96}
  local hairProfileR={k=style.hair.k*1.03,damping=style.hair.damping*1.04}
  local hairTailProfileL={k=style.hair.k*0.48,damping=style.hair.damping*0.72}
  local hairTailProfileR={k=style.hair.k*0.52,damping=style.hair.damping*0.76}
  if belleHairPhysicsEnabled(self.data) then
    spring(S.simHairL, hairXL, hairYL, hairZL, hairProfileL)
    spring(S.simHairR, hairXR, hairYR, hairZR, hairProfileR)
    spring(S.simHairTailL, tailXL, tailYL, tailZL, hairTailProfileL)
    spring(S.simHairTailR, tailXR, tailYR, tailZR, hairTailProfileR)
  else
    for _,node in ipairs({S.hairL,S.hairR,S.simHairL,S.simHairR,S.hairTailL,S.hairTailR,S.simHairTailL,S.simHairTailR}) do
      node.x,node.y,node.z=0,0,0; node.xv,node.yv,node.zv=0,0,0
    end
  end

  -- Tight position and velocity bounds are a second safety layer beneath the
  -- fixed preset. Even a hitch or extreme imported pose cannot turn the jiggle
  -- into wide, snapping motion.
  local function clampBreast(node)
    if node.x and node.x>0.025 then node.x=0.025 elseif node.x and node.x<-0.025 then node.x=-0.025 end
    if node.y and node.y>0.16 then node.y=0.16 elseif node.y and node.y<-0.16 then node.y=-0.16 end
    if node.z and node.z>0.095 then node.z=0.095 elseif node.z and node.z<-0.095 then node.z=-0.095 end
    if node.xv and node.xv>0.80 then node.xv=0.80 elseif node.xv and node.xv<-0.80 then node.xv=-0.80 end
    if node.yv and node.yv>2.0 then node.yv=2.0 elseif node.yv and node.yv<-2.0 then node.yv=-2.0 end
    if node.zv and node.zv>1.2 then node.zv=1.2 elseif node.zv and node.zv<-1.2 then node.zv=-1.2 end
  end
  clampBreast(S.simBreastL); clampBreast(S.simBreastR); clampBreast(S.simButtL); clampBreast(S.simButtR); clampBreast(S.simThighL); clampBreast(S.simThighR); clampBreast(S.simHairL); clampBreast(S.simHairR); clampBreast(S.simHairTailL); clampBreast(S.simHairTailR)

  -- Butter-smooth presentation layer. Rendering and helper-bone deformation use
  -- these filtered output nodes, while the independent sim nodes keep their own
  -- untouched velocity/position histories. Exponential smoothing makes the
  -- result consistent at 30/60/90/120/144 Hz instead of being frame dependent.
  S.breastL=belleSmoothRenderNode(S.breastL,S.simBreastL,dt)
  S.breastR=belleSmoothRenderNode(S.breastR,S.simBreastR,dt)
  S.buttL=belleSmoothRenderNode(S.buttL,S.simButtL,dt)
  S.buttR=belleSmoothRenderNode(S.buttR,S.simButtR,dt)
  S.thighL=belleSmoothRenderNode(S.thighL,S.simThighL,dt)
  S.thighR=belleSmoothRenderNode(S.thighR,S.simThighR,dt)
  S.hairL=belleSmoothRenderNode(S.hairL,S.simHairL,dt)
  S.hairR=belleSmoothRenderNode(S.hairR,S.simHairR,dt)
  S.hairTailL=belleSmoothRenderNode(S.hairTailL,S.simHairTailL,dt)
  S.hairTailR=belleSmoothRenderNode(S.hairTailR,S.simHairTailR,dt)
  if self.data.runtimeBelleBreastIndependent==false then
    S.breastR.x=-(tonumber(S.breastL.x) or 0)
    S.breastR.y=tonumber(S.breastL.y) or 0
    S.breastR.z=tonumber(S.breastL.z) or 0
    S.breastR.xv=-(tonumber(S.breastL.xv) or 0)
    S.breastR.yv=tonumber(S.breastL.yv) or 0
    S.breastR.zv=tonumber(S.breastL.zv) or 0
  end
  if self.data.runtimeBelleButtIndependent==false then
    S.buttR.x=-(tonumber(S.buttL.x) or 0)
    S.buttR.y=tonumber(S.buttL.y) or 0
    S.buttR.z=tonumber(S.buttL.z) or 0
    S.buttR.xv=-(tonumber(S.buttL.xv) or 0)
    S.buttR.yv=tonumber(S.buttL.yv) or 0
    S.buttR.zv=tonumber(S.buttL.zv) or 0
  end
  if self.data.runtimeBelleThighIndependent==false then
    S.thighR.x=-(tonumber(S.thighL.x) or 0)
    S.thighR.y=tonumber(S.thighL.y) or 0
    S.thighR.z=tonumber(S.thighL.z) or 0
    S.thighR.xv=-(tonumber(S.thighL.xv) or 0)
    S.thighR.yv=tonumber(S.thighL.yv) or 0
    S.thighR.zv=tonumber(S.thighL.zv) or 0
  end

  -- Clear v3.0.9 accumulator/target state if a save/session is upgraded in
  -- place. The classic-direct solver does not use either cache.
  self.bellePhysicsAccumulator=nil
  self.bellePhysicsTargets=nil
  self.data.runtimeBellePhysicsHz=hz
  self.data.runtimeBelleSoft=S
end

function Renderer:updateWowLocomotion(player,walking,dt)
  if not self.data or self.data.runtimeProfile~="WOW_FBX" then return end
  dt=tonumber(dt) or (1/60)
  local speed=tonumber(self.voxelSmoothSpeed) or tonumber(self.motionMeasuredSpeed) or tonumber(self.voxelLastSpeed) or 60
  local target=0
  if walking then
    target=(speed-42)/38
    if target<0 then target=0 elseif target>1 then target=1 end
  end
  self.wowRunBlend=approachExp(self.wowRunBlend or 0,target,7.0,dt)
  if self.wowRunBlend<0.0001 then self.wowRunBlend=0 elseif self.wowRunBlend>0.9999 then self.wowRunBlend=1 end
  self.data.runtimeWowRunBlend=self.wowRunBlend
  -- Keep Wow's optional post-skin soft-body system exclusive to Wow. Other
  -- characters can reuse the native FBX walk/run/jump profile without inheriting
  -- body-editor physics or its character-specific masks.
  if self.behaviorId=="WOW" then self:updateBelleBodyPhysics(player,walking,dt,false) end
end

function Renderer:updateBelleLocomotion(player,walking,dt)
  if self.data and self.data.runtimeProfile=="WOW_FBX" then return self:updateWowLocomotion(player,walking,dt) end
  if self.behaviorId~="BELLESTARMON" then return end
  self:updateBelleKeyboardWalkToggle()
  local target=self:belleRunTarget(player,walking)
  self.belleRunBlend=approachExp(self.belleRunBlend or 0,target,CONFIG.belleRunBlendRate or 7.5,dt or (1/60))
  if self.belleRunBlend<0.0001 then self.belleRunBlend=0 elseif self.belleRunBlend>0.9999 then self.belleRunBlend=1 end
  self.data.runtimeBelleRunBlend=self.belleRunBlend
  local x=tonumber(player and player.red3dMoveStickX) or 0
  local y=tonumber(player and player.red3dMoveStickY) or 0
  self.data.runtimeBelleAnalogMagnitude=math.min(1,math.sqrt(x*x+y*y))
  self:updateBelleBodyPhysics(player,walking,dt or (1/60),false)
end

function Renderer:cyclePixels()
  if self.behaviorId=="BELLESTARMON" then
    local rb=self.belleRunBlend or 0
    if rb<0 then rb=0 elseif rb>1 then rb=1 end
    return (CONFIG.belleWalkCyclePixels or 72.0) + ((CONFIG.belleRunCyclePixels or 31.0)-(CONFIG.belleWalkCyclePixels or 72.0))*rb
  end
  if self.data and self.data.runtimeProfile=="RED" then return 34.0 end
  if self.data and self.data.runtimeProfile=="ASH" then return 43.0 end
  if self.data and self.data.runtimeProfile=="WOW_FBX" then
    -- v3.0.47: keep Wow's supplied Catwalk/Goofy locomotion close to the
    -- authored clip timing. The old 58 -> 32 pixel cycle shrank too far at run
    -- speed, making the 0.633 s run clip loop in about 0.40 s. A nearly fixed
    -- 52 px stride matches both endpoints well: ~1.24 s at a 42 px/s walk and
    -- ~0.65 s at an 80 px/s run, without touching the high-rate soft physics.
    return 52.0
  end
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
    elseif self.data and self.data.runtimeProfile=="WOW_FBX" then
      self.wowIdleTime=(self.wowIdleTime or 0)+(1/60)
      local dur=tonumber(self.data.idleDuration) or 1
      if dur<=0 then dur=1 end
      self.data.runtimeWowIdlePhase=(self.wowIdleTime/dur)%1
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
    local phase=(self.behaviorId=="BELLESTARMON") and (self.belleGaitPhase or 0) or ((self.motionDistance/cyclePixels)%1)
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
  -- Animation/controller time is intentionally stricter than general render
  -- time. Hitches and focus/boot stalls must never advance a gait by 100 ms in
  -- one frame, which is perceived as a sudden fast-forward.
  if dt > 0.05 then dt=0.05 end
  self.voxelLastTime=now
  self.voxelStartupAge=math.min(10,(tonumber(self.voxelStartupAge) or 0)+dt)
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
  elseif self.data and self.data.runtimeProfile=="WOW_FBX" then
    self.wowIdleTime=(self.wowIdleTime or 0)+dt
    local dur=tonumber(self.data.idleDuration) or 1
    if dur<=0 then dur=1 end
    self.data.runtimeWowIdlePhase=(self.wowIdleTime/dur)%1
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
    -- Do not trust render-timed position speed immediately after boot. Wait
    -- for a short startup grace and at least three valid samples; until then
    -- the stock step cadence is the stable source of truth.
    if self.motionMeasuredStable and (self.voxelStartupAge or 0)>=0.12
        and measured and measured >= 8 and measured <= 240 then
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
    if self.behaviorId=="BELLESTARMON" then
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
    if self.behaviorId=="BELLESTARMON" then
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
  local gaitPhase=(self.behaviorId=="BELLESTARMON") and (self.belleGaitPhase or 0) or ((self.voxelGaitDistance/cyclePixels)%1)
  self.voxelFrameClock=gaitPhase*16
  self.voxelFrameKey=string.format("vf%d_%.3f",self.voxelFrameSerial,self.voxelFrameBlend)
end

function Renderer:animationState(player,px,py)
  local walking=self:motionSample(player,px,py,nil)
  -- BelleStarmon's spring state must advance even while standing. Previously
  -- the early idle return skipped the body solver completely in the ordinary
  -- non-voxel renderer, so her secondary bones could remain frozen at bind.
  if self.behaviorId=="BELLESTARMON" or (self.data and self.data.runtimeProfile=="WOW_FBX") then self:updateBelleLocomotion(player,walking,1/60) end
  if not walking then return false,0,"idle" end

  -- Non-voxel fallback remains deterministic and distance-locked.  The voxel
  -- pipeline uses beginVoxelFrame() above for sub-frame interpolation.
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
      elseif self.behaviorId=="BELLESTARMON" then
        delta=belleJumpDelta(d,i,jumpT,wrap01(phase/(math.pi*2)),motionBlend or 0)
      elseif d.runtimeProfile=="AANG_MIXAMO" then
        delta=aangJumpDelta(d,i,jumpT,wrap01(phase/(math.pi*2)),motionBlend or 0)
      elseif d.runtimeProfile=="CJ_FBX" then
        delta=cjJumpDelta(d,i,jumpT,wrap01(phase/(math.pi*2)),motionBlend or 0)
      elseif d.runtimeProfile=="YAMI_FBX" then
        delta=yamiJumpDelta(d,i,jumpT,wrap01(phase/(math.pi*2)),motionBlend or 0)
      elseif d.runtimeProfile=="WOW_FBX" then
        -- v3.0.56 uses the supplied in-place Jumping clip when standing and
        -- crossfades toward Running Jump as locomotion speed rises.
        delta=wowJumpDelta(d,i,jumpT,wrap01(phase/(math.pi*2)),motionBlend or 0)
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

    if self.behaviorId=="BELLESTARMON" or self.behaviorId=="WOW" then
      local soft=d.runtimeBelleSoft
      local side=(d.physicsSide and tonumber(d.physicsSide[i])) or ((x>=0) and 1 or -1)
      if soft and bellePhysicsEnabled(d) then
        if belleBreastPhysicsEnabled(d) then
          local bw=(d.physicsBreastWeight and tonumber(d.physicsBreastWeight[i])) or 0
          if bw>0.0001 then
            bw=bw*red3dBreastAreaGate(d,self.behaviorId,x,y)
          end
          if bw>0.0001 then
            local node=(side>=0) and soft.breastL or soft.breastR
            if node then
              local strength=bellePhysicsStrength(d,'runtimeBelleBreastPhysics')
              local surface=(self.behaviorId=="WOW") and 0.62 or 0.18
              x=x+(tonumber(node.x) or 0)*bw*strength*surface
              y=y+(tonumber(node.y) or 0)*bw*strength*surface
              z=z+(tonumber(node.z) or 0)*bw*strength*surface
            end
          end
        end
        -- v3.0.45: butt/thigh/hair physics is driven only by precomputed
        -- model-space masks. Toggling a region never calls a live mask/location
        -- helper from the renderer, preventing the v3.0.45 crash regression.
        if belleButtPhysicsEnabled(d) then
          local btw=(d.physicsButtWeight and tonumber(d.physicsButtWeight[i])) or 0
          local buttSide=(d.physicsButtSide and tonumber(d.physicsButtSide[i])) or side
          if btw>0.0001 then
            local node=(buttSide>=0) and soft.buttL or soft.buttR
            if node then
              local strength=bellePhysicsStrength(d,'runtimeBelleButtocksPhysics')
              local surface=(self.behaviorId=="WOW") and 0.58 or 0.42
              x=x+(tonumber(node.x) or 0)*btw*strength*surface
              y=y+(tonumber(node.y) or 0)*btw*strength*surface
              z=z+(tonumber(node.z) or 0)*btw*strength*surface
            end
          end
        end
        if belleThighPhysicsEnabled(d) then
          local tw=(d.physicsThighWeight and tonumber(d.physicsThighWeight[i])) or 0
          local thighSide=(d.physicsThighSide and tonumber(d.physicsThighSide[i])) or side
          if tw>0.0001 then
            local node=(thighSide>=0) and soft.thighL or soft.thighR
            if node then
              local strength=bellePhysicsStrength(d,'runtimeBelleThighPhysics')
              local surface=(self.behaviorId=="WOW") and 0.34 or 0.28
              x=x+(tonumber(node.x) or 0)*tw*strength*surface
              y=y+(tonumber(node.y) or 0)*tw*strength*surface
              z=z+(tonumber(node.z) or 0)*tw*strength*surface
            end
          end
        end
        if belleHairPhysicsEnabled(d) then
          local hw=(d.physicsHairWeight and tonumber(d.physicsHairWeight[i])) or 0
          local hairSide=(d.physicsHairSide and tonumber(d.physicsHairSide[i])) or side
          if hw>0.0001 then
            local node=(hairSide>=0) and soft.hairL or soft.hairR
            if node then
              local strength=bellePhysicsStrength(d,'runtimeBelleHairPhysics')
              local surface=(self.behaviorId=="WOW") and 0.42 or 0.32
              x=x+(tonumber(node.x) or 0)*hw*strength*surface
              y=y+(tonumber(node.y) or 0)*hw*strength*surface
              z=z+(tonumber(node.z) or 0)*hw*strength*surface

              -- Apply a separate delayed spring only to already-tagged lower/
              -- rear hair. Hair membership itself remains the stable precomputed
              -- physicsHairWeight array from v3.0.45.
              local tailNode=(hairSide>=0) and soft.hairTailL or soft.hairTailR
              if tailNode then
                local backBias=red3dSmoothGate(0.015,0.105,z)
                local lowerBias=1.0-red3dSmoothGate(1.34,1.70,y)
                local tailAmount=backBias*lowerBias
                if tailAmount>0.0001 then
                  local tailSurface=(self.behaviorId=="WOW") and 0.72 or 0.44
                  x=x+(tonumber(tailNode.x) or 0)*hw*strength*tailSurface*tailAmount
                  y=y+(tonumber(tailNode.y) or 0)*hw*strength*tailSurface*tailAmount
                  z=z+(tonumber(tailNode.z) or 0)*hw*strength*tailSurface*tailAmount
                end
              end
            end
          end
        end
      end
    end
    x,y,z=self:applySourceBasis(x,y,z)
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
  if not useVoxelFrame and self.data and self.data.runtimeProfile=="WOW_FBX" then
    local now=(love and love.timer and love.timer.getTime) and love.timer.getTime() or nil
    local dt=1/60
    if now and self.wowIdleLastTime then dt=now-self.wowIdleLastTime end
    if dt<0 then dt=0 elseif dt>0.10 then dt=0.10 end
    if now then self.wowIdleLastTime=now end
    self.wowIdleTime=(self.wowIdleTime or 0)+dt
    local dur=tonumber(self.data.idleDuration) or 1
    if dur<=0 then dur=1 end
    self.data.runtimeWowIdlePhase=(self.wowIdleTime/dur)%1
    key=key..string.format("_wowidle%.3f",self.data.runtimeWowIdlePhase)
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

local function nearestCardinalFacing(yaw)
  local twoPi=math.pi*2
  yaw=(tonumber(yaw) or 0)%twoPi
  if yaw<0 then yaw=yaw+twoPi end
  if yaw<math.pi/4 or yaw>=7*math.pi/4 then return "down" end
  if yaw<3*math.pi/4 then return "right" end
  if yaw<5*math.pi/4 then return "up" end
  return "left"
end

local function projectedTravelYaw(player,facing)
  local cardinal=YAW[facing] or 0
  if not player then return cardinal,facing or "down" end

  -- v3.1.12: use the actual step vector instead of the four-way sprite facing.
  -- Both generations expose targetX/targetY while a step is under way, and the
  -- directional-movement patch below may make BOTH axes non-zero.  That gives
  -- the renderer an exact diagonal heading while leaving the engine's cardinal
  -- `facing` field available for interactions, doors, ledges, scripts, etc.
  local dx,dy=0,0
  if player.moving and player.targetX~=nil and player.targetY~=nil then
    dx=(tonumber(player.targetX) or tonumber(player.cellX) or 0)
       -(tonumber(player.cellX) or 0)
    dy=(tonumber(player.targetY) or tonumber(player.cellY) or 0)
       -(tonumber(player.cellY) or 0)
  end

  local yaw=nil
  if dx~=0 or dy~=0 then
    yaw=atan2(dx,dy)
    player.red3dProjectedBodyYaw=yaw
  elseif player.spinning then
    -- Spinner/teleport animation owns the visible facing.
    yaw=cardinal
    player.red3dProjectedBodyYaw=yaw
  elseif (tonumber(player.turnTimer) or 0)>0 then
    -- A deliberate turn-in-place should still rotate the 3D body even though
    -- no translation happened.
    yaw=cardinal
    player.red3dProjectedBodyYaw=yaw
  else
    yaw=player.red3dProjectedBodyYaw
    if yaw==nil then
      yaw=cardinal
      player.red3dProjectedBodyYaw=yaw
    end
  end

  return yaw,nearestCardinalFacing(yaw)
end

function Renderer:project(px,py,camX,camY,facing,player)
  -- NOTE: this path rotates by -yaw (xr=c*x+s*z / zr=-s*x+c*z) while
  -- voxelModelMatrix/battleModelMatrix use Mat4.rotateY(+yaw).  The two spin
  -- OPPOSITE ways, so modelYawOffset remains voxel/model-space only. Characters
  -- whose imported forward axis also needs repair here use projectYawOffset;
  -- FACE FLIP stays a separate user-controlled extra 180-degree override.
  local travelYaw,sortFacing=projectedTravelYaw(player,facing)
  local yaw=travelYaw+(self.projectYawOffset or 0)+(self.faceFlipYaw or 0)
  local c,s=math.cos(yaw),math.sin(yaw)
  local footX=math.floor(px-camX)+8
  local footY=math.floor(py-camY)+12-(self.floatOffset or 0)
  local sc=self.scale
  for i=1,self.data.positionCount do
    local x,z=self.sx[i],self.sz[i]
    local xr=c*x+s*z
    local zr=-s*x+c*z
    self.screenX[i]=footX+xr*sc
    self.screenY[i]=footY-(self.sy[i]-self.minY)*sc+zr*sc*CONFIG.depthSlope
  end
  return sortFacing
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
  local sortFacing=self:project(px,visualPy,camX,camY,facing,player)
  self:updateMesh(sortFacing or facing)

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

-- v3.1.5 Skin Selector preview fallback.
--
-- SkinSelectorModelViewer renders the portrait through Dramatic Shape's
-- Voxel3D/Mat4, so on any host without that pipeline `renderer.voxelBridge` is
-- nil and the panel reads "3D PREVIEW UNAVAILABLE".  A Gold boot has no voxel
-- pipeline at all, so the preview was never available there.
--
-- This draws the same character with the mod's OWN projected mesh -- the exact
-- renderer the overworld player already uses -- into an off-screen canvas.  No
-- Voxel3D, no Mat4, no Dramatic Shape.  It deliberately mirrors the viewer's
-- per-frame sequence (preview physics, selector-pose flag, updateSkeleton,
-- skin) so BelleStarmon's physics controls stay live in the portrait.
function Renderer:previewCanvas(w,h,facing)
  if self.failed or not self:ensureGraphics() then return nil end
  if not (love and love.graphics and love.graphics.newCanvas) then return nil end
  w=math.max(64,math.floor(tonumber(w) or 320))
  h=math.max(64,math.floor(tonumber(h) or 400))

  local now=runtimeClock()
  local dt=(self._previewLast and (now-self._previewLast)) or (1/60)
  self._previewLast=now
  if dt<0 then dt=0 elseif dt>0.10 then dt=0.10 end

  -- Same order the voxel viewer uses (lib/SkinSelectorModelViewer.lua:282).
  if (self.behaviorId=="BELLESTARMON" or self.behaviorId=="WOW")
      and self.updateBelleBodyPhysics then
    self:updateBelleBodyPhysics(nil,false,dt,true)
  end
  local d=self.data
  if d and (self.behaviorId=="BELLESTARMON" or self.behaviorId=="WOW") then
    d.runtimeSkinSelectorPreview=true
  end
  if self.behaviorId=="BELLESTARMON" and d and d.selectorIdleDelta
      and (tonumber(d.selectorIdleFrameCount) or 0)>1 then
    local dur=tonumber(d.selectorIdleDuration) or 0.65
    if dur<=0 then dur=0.65 end
    self._previewIdle=((self._previewIdle or 0)+dt/dur)%1
    d.runtimeSelectorIdlePhase=self._previewIdle
  end
  local okSkel=pcall(self.updateSkeleton,self,{},false,0,0)
  if d then d.runtimeSkinSelectorPreview=nil; d.runtimeSelectorIdlePhase=nil end
  if not okSkel then return nil end
  if not pcall(self.skin,self) then return nil end
  -- the portrait is rebuilt every frame, so the cached world skin is stale
  self.skinKey=nil

  facing=facing or "down"

  -- Fit the projected silhouette to the canvas rather than assuming a scale.
  local yaw=(YAW[facing] or 0)+(self.projectYawOffset or 0)+(self.faceFlipYaw or 0)
  local c,s=math.cos(yaw),math.sin(yaw)
  local minX,maxX,minY,maxY=math.huge,-math.huge,math.huge,-math.huge
  for i=1,self.data.positionCount do
    local x,z=self.sx[i],self.sz[i]
    local xr=c*x+s*z
    local zr=-s*x+c*z
    local py=-(self.sy[i]-self.minY)+zr*CONFIG.depthSlope
    if xr<minX then minX=xr end
    if xr>maxX then maxX=xr end
    if py<minY then minY=py end
    if py>maxY then maxY=py end
  end
  if minX>maxX or minY>maxY then return nil end
  local spanX=math.max(0.001,maxX-minX)
  local spanY=math.max(0.001,maxY-minY)
  local fit=math.min(w*0.78/spanX,h*0.86/spanY)

  local okCanvas,canvas=pcall(love.graphics.newCanvas,w,h)
  if not okCanvas or not canvas then return nil end

  -- v3.1.6 preview centering fix. project() already multiplies model-space
  -- coordinates by self.scale and adds the player-foot origin. v3.1.5 then
  -- translated the completed mesh a second time, including a -12*fit term.
  -- Depending on the rig's fitted scale, that could move the whole character
  -- outside the selector canvas even though the preview technically rendered.
  -- Solve the foot origin once from the measured silhouette centre instead.
  local centerX=(minX+maxX)*0.5
  local centerY=(minY+maxY)*0.5
  local desiredFootX=w*0.5-centerX*fit
  local desiredFootY=h*0.5-centerY*fit
  local previewPx=desiredFootX-8
  local previewPy=desiredFootY-12+(self.floatOffset or 0)

  local saveScale=self.scale
  self.scale=fit
  local previewSort=self:project(previewPx,previewPy,0,0,facing,nil)
  self:updateMesh(previewSort or facing)
  self.scale=saveScale

  local ok=pcall(function()
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0,0,0,0)
    love.graphics.origin()
    love.graphics.setColor(1,1,1,1)
    love.graphics.setBlendMode("alpha")
    love.graphics.draw(self.mesh)
    love.graphics.pop()
  end)
  pcall(love.graphics.setCanvas)
  if not ok then return nil end
  return canvas
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

  local yaw=(liveYaw or YAW[p.facing] or 0)+(self.modelYawOffset or 0)+(self.faceFlipYaw or 0)
  local m=Mat4.translate(p.px+8,p.gh+(p.lift or 0)+manualJumpLift(player)+CONFIG.groundClearance+(self.floatOffset or 0),p.py+8)
  if yaw~=0 then m=Mat4.mul(m,Mat4.rotateY(yaw)) end
  m=Mat4.mul(m,Mat4.scale(self.scale,self.scale,self.scale))
  m=Mat4.mul(m,Mat4.translate(-self.centerX,-self.minY,-self.centerZ))
  return m
end

function Renderer:vrFirstPersonModelMatrix(player,p,Voxel3D,Mat4,FirstPerson)
  -- In headset first person the body follows the head bearing, matching the
  -- voxel mod's own FirstPerson.bodyBearing contract. Do not use the retained
  -- travel yaw here: standing still while physically turning your head should
  -- not leave your chest pointed in an unrelated direction.
  local yaw=(FirstPerson and tonumber(FirstPerson.yaw))
    or (player and tonumber(player.red3dFreeBodyYaw))
    or YAW[p.facing] or 0
  yaw=yaw+(self.modelYawOffset or 0)+(self.faceFlipYaw or 0)

  -- Keep the BODY at one world transform for both stereo eyes. Voxel3D.camera
  -- is a different eye record on the left and right pass; using camera.eye as
  -- a body translation would bake the headset IPD into the model position and
  -- make the two eyes disagree about where the torso is. The HMD can still
  -- lean/step naturally relative to this grounded body, while yaw follows the
  -- headset above.
  local x=p.px+8
  local z=p.py+8

  -- The VR rig defines 10 world px/metre and treats a 16 px person as ~1.6 m.
  -- The flat/third-person character heights are intentionally larger for screen
  -- readability, so normalize only the headset body to the VR world's life-size
  -- convention while retaining the user's per-character scale multiplier.
  local vrScale=self.scale
  local h=tonumber(self.renderHeight) or 16
  if h>0 then vrScale=vrScale*(16/h) end

  local m=Mat4.translate(x,p.gh+(p.lift or 0)+manualJumpLift(player)+CONFIG.groundClearance+(self.floatOffset or 0),z)
  if yaw~=0 then m=Mat4.mul(m,Mat4.rotateY(yaw)) end
  m=Mat4.mul(m,Mat4.scale(vrScale,vrScale,vrScale))
  m=Mat4.mul(m,Mat4.translate(-self.centerX,-self.minY,-self.centerZ))
  return m
end

function Renderer:updateVRBodyMesh(player,p,Voxel3D)
  if not self:ensureVRBodyGraphics(Voxel3D) then return false end
  local key=self:ensureSkinned(player,p and p.px,p and p.py,true)
  if key==self.vrBodyUploadedKey then return true end
  local rows=self.voxelRows
  for i=1,self.renderVertexCount do
    local pos=self.vertexPos[i]
    local row=rows[i]
    row[1]=self.sx[pos]; row[2]=self.sy[pos]; row[3]=self.sz[pos]
  end
  local ok,err=pcall(self.vrBodyMesh.setVertices,self.vrBodyMesh,rows)
  if not ok then
    self.mod.log:warn("VR first-person character body mesh update failed: %s",tostring(err))
    return false
  end
  self.vrBodyUploadedKey=key
  return true
end

function Renderer:drawVoxelVRBody(player,p,Voxel3D,Mat4,FirstPerson)
  -- The static OceanGate Titan is a vehicle-shaped prop, not a humanoid rig;
  -- putting its hull around a head-mounted camera would simply occlude the
  -- headset. It remains fully supported in diorama/tabletop and battle VR.
  if self.behaviorId=="TITAN" then return false end
  if self.voxelFailed or playerUsesSpecialCard(player) then return false end
  if not self:updateVRBodyMesh(player,p,Voxel3D) then return false end
  local model=self:vrFirstPersonModelMatrix(player,p,Voxel3D,Mat4,FirstPerson)
  -- This call happens after VoxelScene's normal drawCast has restored terrain
  -- rendering state, so explicitly switch to character state for the body and
  -- restore it afterward. Head accessories are intentionally omitted in first
  -- person; a hat/helmet attached at the culled head would sit inside the HMD.
  if Voxel3D.glass then pcall(Voxel3D.glass,false) end
  if Voxel3D.seams then pcall(Voxel3D.seams,false) end
  Voxel3D.draw(self.vrBodyMesh,self.image,model,nil,model)
  if Voxel3D.seams then pcall(Voxel3D.seams,true) end
  if Voxel3D.glass then pcall(Voxel3D.glass,true) end
  return true
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
  if type(self.red3dDrawAccessories)=="function" then
    pcall(self.red3dDrawAccessories,self,Voxel3D,model,nil,false)
  end
  return true
end

function Renderer:drawVoxelShadow(player,p,Voxel3D,Mat4,ShadowMap,FirstPerson)
  if self.voxelFailed or playerUsesSpecialCard(player) then return false end
  if not self:updateVoxelMesh(player,p,Voxel3D) then return false end
  local model=self:voxelModelMatrix(player,p,Mat4,FirstPerson)
  ShadowMap.draw(self.voxelMesh,self.image,model)
  if type(self.red3dDrawAccessories)=="function" then
    pcall(self.red3dDrawAccessories,self,Voxel3D,model,ShadowMap,false)
  end
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
  local yaw=atan2(ex-px,ez-pz)+(self.modelYawOffset or 0)+(self.faceFlipYaw or 0)
  local m=Mat4.translate(px,(groundY or 0)+CONFIG.groundClearance+(self.floatOffset or 0),pz)
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
  -- v3.1.16: NEVER V.require("VR") here. Some voxel forks install input/
  -- camera hooks as a side effect of loading their private VR module; eagerly
  -- requiring it from this companion mod can therefore steal/break the fork's
  -- own first/third-person camera hotkey even when no headset is active. Borrow
  -- only a VR table the voxel pipeline has already captured itself. Current
  -- Dramaless Shape captures VR in drawWorld/update; older/non-VR builds simply
  -- leave this nil and continue with the ordinary flat/third-person path.
  local VR=nil
  do
    local _,vr=findUpvalue(voxelDef.drawWorld,"VR")
    if type(vr)=="table" then VR=vr end
    if not VR and type(voxelDef.update)=="function" then
      local _,vr2=findUpvalue(voxelDef.update,"VR")
      if type(vr2)=="table" then VR=vr2 end
    end
    if not VR then
      local _,vr3=findUpvalue(render,"VR")
      if type(vr3)=="table" then VR=vr3 end
    end
  end
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
    VR=VR,
    disabled=false,
    loggedDrawError=false,
    loggedShadowError=false,
    loggedVRBodyError=false,
    -- Terrain meshes are texture-agnostic in Dramatic Shape; VoxelScene
    -- supplies TerrainAtlas.forMap(...) separately on each draw. Cache that
    -- exact live image so fractured geometry samples the same atlas as the
    -- intact environment instead of relying on Mesh:getTexture state.
    terrainAtlasByMesh=setmetatable({}, {__mode="k"}),
    terrainAtlasByMap={},
    -- v3.1.14: Dramatic Shape can omit the sun/shadow pass in third-person.
    -- That pass used to be our only stable call to beginVoxelFrame(), leaving
    -- the visible player mesh stuck on its last skinned pose whenever shadows
    -- were skipped. Track whether the shadow pass already prepared this frame
    -- so drawCast can provide a visible-pass fallback without double stepping.
    framePreparedByShadow=false,
    lastShadowFramePrepTime=nil,
    lastVisibleFramePrepTime=nil,
  }

  local function red3dFrameNow()
    if love and love.timer and love.timer.getTime then return love.timer.getTime() end
    return nil
  end

  local function red3dVRActive()
    if type(bridge.VR)~="table" or type(bridge.VR.active)~="function" then return false end
    local ok,on=pcall(bridge.VR.active)
    return ok and on==true
  end

  local function red3dVRFirstPersonBody()
    if not red3dVRActive() then return false end
    if type(FirstPerson)~="table" or type(FirstPerson.hidePlayer)~="function" then return false end
    local ok,hidden=pcall(FirstPerson.hidePlayer)
    return ok and hidden==true
  end

  local function red3dPrepareShadowFrame(player,p)
    if not (player and p) then return end
    local now=red3dFrameNow()
    -- Some pipeline revisions can touch the shadow path more than once during
    -- one render. Treat calls within 3 ms as the same rendered frame. Normal
    -- gameplay frames are much farther apart, while this prevents double gait
    -- advancement from duplicate shadow work.
    if now and bridge.lastShadowFramePrepTime
        and (now-bridge.lastShadowFramePrepTime)>=0
        and (now-bridge.lastShadowFramePrepTime)<0.003 then
      bridge.framePreparedByShadow=true
      return
    end
    renderer:beginVoxelFrame(player,p)
    bridge.framePreparedByShadow=true
    bridge.lastShadowFramePrepTime=now
  end

  local function red3dPrepareVisibleFrame(player,p)
    if not (player and p) then return end
    if bridge.framePreparedByShadow then
      -- Normal voxel mode consumes this marker after one visible pass. VR is
      -- different: VoxelScene draws the SAME prepared world once per eye, so
      -- both eyes must keep reusing the shadow-prepared skeleton or the second
      -- eye could advance a gait frame and stereo would disagree. The next VR
      -- frame's shadow pass simply overwrites the marker with a fresh pose.
      if not red3dVRActive() then bridge.framePreparedByShadow=false end
      bridge.lastVisibleFramePrepTime=red3dFrameNow()
      return
    end

    -- Third-person / shadowless path: make the visible cast responsible for
    -- advancing the same shared voxel animation controller. A tiny duplicate
    -- pass gate avoids double advancement if drawCast is invoked twice by a
    -- renderer variant in the same rendered frame.
    local now=red3dFrameNow()
    if now and bridge.lastVisibleFramePrepTime
        and (now-bridge.lastVisibleFramePrepTime)>=0
        and (now-bridge.lastVisibleFramePrepTime)<0.003 then
      return
    end
    renderer:beginVoxelFrame(player,p)
    bridge.lastVisibleFramePrepTime=now
  end

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
    -- v3.1.14: third-person can render the visible cast without invoking the
    -- sun/shadow pass first. Ensure the animation frame exists either way.
    if bridge.currentPose and bridge.currentPlayer then
      red3dPrepareVisibleFrame(bridge.currentPlayer,bridge.currentPose)
    end
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
    if ok and bridge.currentPlayer and bridge.currentPose and red3dVRFirstPersonBody() then
      -- First-person VR never calls drawEntity for the player: upstream hides
      -- the card before our ordinary replacement hook can see it. Draw the
      -- dedicated headless body explicitly after the rest of the cast instead.
      local okBody,shown=pcall(renderer.drawVoxelVRBody,renderer,bridge.currentPlayer,bridge.currentPose,Voxel3D,Mat4,FirstPerson)
      if not okBody and not bridge.loggedVRBodyError then
        bridge.loggedVRBodyError=true
        mod.log:error("VR first-person 3D body draw failed: %s",tostring(shown))
      end
    end
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
        if me and player then red3dPrepareShadowFrame(player,me) end
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
  mod.log:info("Dramatic Shape bridge installed: player sprite card -> real %d-triangle skinned mesh%s%s%s",
    renderer.data.triangleCount,
    bridge.shadowHook and " + volumetric sun shadow" or "",
    bridge.ghostSuppressed and " + stock ghost flicker suppression" or "",
    bridge.VR and " + VR stereo/headless first-person body" or "")
  return true
end

return function(mod)
  local CHARACTER_DEFS = {
    RED = { id="RED", label="Red", data="data/model.lua", atlas="assets/red_atlas.png", height=18.984375, profile="RED" },
    YUGI = { id="YUGI", label="Yugi Muto", data="data/yugi_model.lua", atlas="assets/yugi_atlas.png", height=25, profile="YUGI", armRestDeg=62 },
    -- v3.1.8: repair the actual skinned source basis once. Renderer yaw offsets
    -- stay zero so the selector, Gold projection and Voxel3D cannot double-flip.
    NARUTO = { id="NARUTO", label="Naruto", data="data/naruto_model.lua", atlas="assets/naruto_atlas_open.png", atlasFrames={"assets/naruto_atlas_open.png","assets/naruto_atlas_close00.png"}, dynamicAtlas="blink", height=20.5, profile="NARUTO_MIXAMO", armRestDeg=0, modelYawOffset=0, projectYawOffset=0, sourceYaw180=true },
    ZORO = { id="ZORO", label="Roronoa Zoro", data="data/zoro_model.lua", atlas="assets/zoro_atlas.png", height=26, profile="AANG_MIXAMO", armRestDeg=0, modelYawOffset=0, postSkinZUp=true },
    CLOUD = { id="CLOUD", label="Cloud", data="data/cloud_model.lua", atlas="assets/cloud_atlas.png", height=20, profile="CLOUD", armRestDeg=0 },
    AANG = { id="AANG", label="Aang", data="data/aang_model.lua", atlas="assets/aang_atlas.png", height=18.5, profile="AANG_MIXAMO", armRestDeg=0, modelYawOffset=0 },
    YAMI = { id="YAMI", label="Yami", data="data/yami_model.lua", atlas="assets/yami_atlas.png", height=24.5, profile="YAMI_FBX", armRestDeg=0, modelYawOffset=0, postSkinZUp=true },
    -- Same source-basis repair as Naruto. This is geometry-level, not another
    -- render-path yaw compensation.
    BELLESTARMON = { id="BELLESTARMON", label="BelleStarmon", data="data/bellestarmon_model.lua", atlas="assets/bellestarmon_atlas.png", height=27, profile="AANG_MIXAMO", armRestDeg=0, modelYawOffset=0, projectYawOffset=0, sourceYaw180=true },
    SHREK = { id="SHREK", label="Shrek", data="data/shrek_model.lua", atlas="assets/shrek_atlas.png", height=29, profile="AANG_MIXAMO", armRestDeg=0, modelYawOffset=0 },
    TITAN = { id="TITAN", label="OceanGate Titan", data="data/titan_model.lua", atlas="assets/titan_atlas.png", height=10.5, profile="STATIC", armRestDeg=0, modelYawOffset=0, floatOffset=4.0 },
    -- v3.1.10: user-supplied native Mixamo rig with dedicated Idle, Running,
    -- and Jump clips. The converted clips are in-place; entity movement stays
    -- owned by Gen1Recomp rather than the FBX root-motion track.
    UGANDAN_KNUCKLES = { id="UGANDAN_KNUCKLES", label="Ugandan Knuckles", data="data/ugandan_knuckles_model.lua", atlas="assets/ugandan_knuckles_atlas.png", height=18.0, profile="AANG_MIXAMO", armRestDeg=0, modelYawOffset=0 },
    -- v3.1.11: native 52-bone Sabrina rig using the supplied Idle, Catwalk
    -- Walking, Goofy Running and Jumping clips. WOW_FBX supplies authored
    -- walk/run blending and in-place root-motion handling without Wow-only UI.
    SABRINA = { id="SABRINA", label="Sabrina", data="data/sabrina_model.lua", atlas="assets/sabrina_atlas.png", height=25.0, profile="WOW_FBX", armRestDeg=0, modelYawOffset=0 },
    ASH = { id="ASH", label="Ash Ketchum", data="data/ash_model.lua", atlas="assets/ash_atlas.png", height=19.5, profile="ASH", armRestDeg=0, modelYawOffset=0 },
  }
  local CHARACTER_ORDER = { "AANG", "ASH", "BELLESTARMON", "CLOUD", "NARUTO", "RED", "ZORO", "SHREK", "TITAN", "UGANDAN_KNUCKLES", "SABRINA", "YAMI", "YUGI" }

  -- v3.0.12 portable skin packages.
  -- A .red3dskin is one binary file containing the generated model Lua source,
  -- one or more texture atlases, and the small renderer metadata needed to add
  -- the character back to the selector. Imports live in LÖVE's writable save
  -- directory because desktop file pickers are not exposed by Gen1Recomp.
  local RED3D_SKIN_MAGIC="RED3DSKIN1"
  local RED3D_SKIN_ROOT="red3d_skins"
  local RED3D_SKIN_IMPORT_DIR=RED3D_SKIN_ROOT.."/imports"
  local RED3D_SKIN_EXPORT_DIR=RED3D_SKIN_ROOT.."/exports"
  local IMPORTED_SKIN_FILES={}

  local function skinSafeToken(value,fallback)
    local s=tostring(value or fallback or "SKIN")
    s=s:gsub("[\r\n=]"," "):gsub("^%s+",""):gsub("%s+$","")
    if s=="" then s=tostring(fallback or "SKIN") end
    return s
  end

  local function skinSafeId(value)
    local s=skinSafeToken(value,"SKIN"):upper():gsub("[^A-Z0-9_]+","_")
    s=s:gsub("^_+",""):gsub("_+$","")
    if s=="" then s="SKIN" end
    return s
  end

  local function skinFsReady()
    local fs=love and love.filesystem
    if not fs then return false end
    if fs.createDirectory then
      pcall(fs.createDirectory,RED3D_SKIN_ROOT)
      pcall(fs.createDirectory,RED3D_SKIN_IMPORT_DIR)
      pcall(fs.createDirectory,RED3D_SKIN_EXPORT_DIR)
    end
    if fs.write then
      pcall(fs.write,RED3D_SKIN_IMPORT_DIR.."/README.txt",
        "Put .red3dskin files in this folder, then press IMPORT SKINS in the Red 3D Player Skin Selector.\n")
    end
    return true
  end

  local function skinNativeRoot()
    if love and love.filesystem and love.filesystem.getSaveDirectory then
      local ok,p=pcall(love.filesystem.getSaveDirectory)
      if ok and p then return tostring(p).."/"..RED3D_SKIN_ROOT end
    end
    return RED3D_SKIN_ROOT
  end

  local function parseSkinPackage(path)
    if not (love and love.filesystem and love.filesystem.read) then return nil,"filesystem unavailable" end
    local ok,bytes=pcall(love.filesystem.read,path)
    if not ok or type(bytes)~="string" then return nil,"could not read package" end
    if #bytes>268435456 then return nil,"package exceeds 256 MB safety limit" end
    if bytes:sub(1,#RED3D_SKIN_MAGIC)~=RED3D_SKIN_MAGIC then return nil,"not a RED3DSKIN1 package" end
    local headerEnd=bytes:find("\n\n",#RED3D_SKIN_MAGIC+1,true)
    if not headerEnd then return nil,"missing package header terminator" end
    local header=bytes:sub(#RED3D_SKIN_MAGIC+2,headerEnd-1)
    local fields={}
    for line in header:gmatch("[^\r\n]+") do
      local k,v=line:match("^([%w_]+)=(.*)$")
      if k then fields[k]=v end
    end
    local modelLen=tonumber(fields.modelLen) or 0
    local atlasCount=tonumber(fields.atlasCount) or 0
    if modelLen<16 or modelLen>67108864 or atlasCount<1 or atlasCount>8 then return nil,"invalid package lengths" end
    local cursor=headerEnd+2
    local modelBytes=bytes:sub(cursor,cursor+modelLen-1)
    if #modelBytes~=modelLen then return nil,"truncated model data" end
    cursor=cursor+modelLen
    local atlasFrames={}
    local atlasBytes={}
    for i=1,atlasCount do
      local len=tonumber(fields["atlas"..i.."Len"]) or 0
      if len<8 or len>67108864 then return nil,"invalid atlas data" end
      local blob=bytes:sub(cursor,cursor+len-1)
      if #blob~=len then return nil,"truncated atlas data" end
      cursor=cursor+len
      local virtual="@red3dskin/"..skinSafeId(fields.id).."/atlas"..i..".png"
      atlasFrames[#atlasFrames+1]=virtual
      atlasBytes[virtual]=blob
    end
    if cursor~=#bytes+1 then return nil,"package has undeclared trailing data" end
    local id=skinSafeId(fields.id)
    local def={
      id=id,
      behaviorId=skinSafeId(fields.behaviorId or fields.id),
      label=skinSafeToken(fields.label,id),
      data="@red3dskin/"..id.."/model.lua",
      atlas=atlasFrames[1],
      atlasFrames=(#atlasFrames>1) and atlasFrames or nil,
      atlasBytes=atlasBytes,
      dynamicAtlas=(fields.dynamicAtlas and fields.dynamicAtlas~="") and fields.dynamicAtlas or nil,
      height=tonumber(fields.height) or 24,
      profile=skinSafeToken(fields.profile,"AANG_MIXAMO"),
      armRestDeg=tonumber(fields.armRestDeg) or 0,
      modelYawOffset=tonumber(fields.modelYawOffset) or 0,
      projectYawOffset=tonumber(fields.projectYawOffset) or 0,
      sourceYaw180=(fields.sourceYaw180=="1" or fields.sourceYaw180=="true"),
      postSkinZUp=(fields.postSkinZUp=="1" or fields.postSkinZUp=="true"),
      _modelBytes=modelBytes,
      _packagePath=path,
      _imported=true,
    }
    return def
  end

  local function uniqueImportedId(preferred,path)
    local base=skinSafeId(preferred)
    local mapped=IMPORTED_SKIN_FILES[path]
    if mapped then return mapped end
    if not CHARACTER_DEFS[base] then return base end
    base="IMPORT_"..base
    local id=base
    local n=2
    while CHARACTER_DEFS[id] do
      id=base.."_"..n
      n=n+1
    end
    return id
  end

  local function addImportedDef(def,path)
    if not def then return nil end
    local id=uniqueImportedId(def.id,path)
    def.id=id
    if id:sub(1,7)=="IMPORT_" and not tostring(def.label):find("%(Imported%)",1,false) then
      def.label=tostring(def.label).." (Imported)"
    end
    -- Re-key virtual texture paths to the collision-safe runtime ID.
    local frames={}
    local bytes={}
    local sourceFrames=def.atlasFrames or {def.atlas}
    for i,old in ipairs(sourceFrames) do
      local key="@red3dskin/"..id.."/atlas"..i..".png"
      frames[#frames+1]=key
      bytes[key]=def.atlasBytes and def.atlasBytes[old] or nil
    end
    def.atlas=frames[1]
    def.atlasFrames=(#frames>1) and frames or nil
    def.atlasBytes=bytes
    def.data="@red3dskin/"..id.."/model.lua"
    CHARACTER_DEFS[id]=def
    local found=false
    for _,existing in ipairs(CHARACTER_ORDER) do if existing==id then found=true break end end
    if not found then CHARACTER_ORDER[#CHARACTER_ORDER+1]=id end
    IMPORTED_SKIN_FILES[path]=id
    return id
  end

  local function scanSkinPackagesIntoDefs()
    if not skinFsReady() then return 0,0 end
    local fs=love.filesystem
    if not fs.getDirectoryItems then return 0,0 end
    local ok,items=pcall(fs.getDirectoryItems,RED3D_SKIN_IMPORT_DIR)
    if not ok or type(items)~="table" then return 0,0 end
    table.sort(items)
    local added,failed=0,0
    for _,name in ipairs(items) do
      if tostring(name):lower():match("%.red3dskin$") then
        local p=RED3D_SKIN_IMPORT_DIR.."/"..name
        if not IMPORTED_SKIN_FILES[p] then
          local def,err=parseSkinPackage(p)
          if def then
            addImportedDef(def,p)
            added=added+1
          else
            failed=failed+1
            mod.log:error("skin import failed for %s: %s",tostring(p),tostring(err))
          end
        end
      end
    end
    return added,failed
  end

  scanSkinPackagesIntoDefs()

  -- Player-facing settings remain available in the mod manager, while the
  -- same character choice is also exposed as a proper pause/start-menu screen.
  if mod.options and mod.options.define then
    mod.options:define({
      { key = "character_3d", type = "choice", label = "CHARACTER", default = "RED",
        choices = { {"AANG","AANG"}, {"ASH KETCHUM","ASH"}, {"BELLESTARMON","BELLESTARMON"}, {"CLOUD","CLOUD"}, {"NARUTO","NARUTO"}, {"RED","RED"}, {"RORONOA ZORO","ZORO"}, {"SHREK","SHREK"}, {"OCEANGATE TITAN","TITAN"}, {"YAMI","YAMI"}, {"YUGI MUTO","YUGI"} } },
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
    -- v3.1.2: WOW was removed.  An existing save may still name it, and
    -- buildCharacterRenderer would return nil for a def that no longer exists,
    -- leaving no character at all -- so retire the id to the default here.
    local id=savedCharacter()
    if id=="WOW" then id=nil end
    return id or "RED"
  end

  -- v3.1.8 migration: earlier experimental facing fixes encouraged toggling
  -- FACE FLIP for these two characters. Clear that legacy override exactly once
  -- so the new source-basis correction starts from a deterministic front-facing
  -- default; subsequent user changes remain persistent.
  if mod.save and mod.save.get and mod.save.set
      and tonumber(mod.save:get("source_basis_v318_migrated"))~=1 then
    mod.save:set("face_flip_naruto",0)
    mod.save:set("face_flip_bellestarmon",0)
    mod.save:set("source_basis_v318_migrated",1)
  end

  local renderers={}
  local belleSelectorIdle=nil
  local function buildCharacterRenderer(id)
    local def=CHARACTER_DEFS[id]
    if not def then return nil end
    local data=nil
    if def._runtimeData then
      data=def._runtimeData
    elseif def._modelBytes then
      data=loadLuaSourceData(mod,def._modelBytes,def.data or ("imported/"..tostring(id).."/model.lua"),true)
    else
      data=loadLuaData(mod,def.data)
    end
    if data then
      if not (tonumber(data.boneCount) and tonumber(data.positionCount) and tonumber(data.cornerCount)
          and type(data.boneName)=="table" and type(data.boneLocal)=="table"
          and type(data.infBone)=="table" and type(data.infW)=="table"
          and type(data.cornerPos)=="table" and type(data.cornerU)=="table" and type(data.cornerV)=="table"
          and type(data.order)=="table" and type(data.bounds)=="table") then
        mod.log:error("character %s has incomplete generated model data",tostring(def.label))
        return nil
      end
      local ok,child=pcall(Renderer.new,mod,data,def)
      if ok and child then
        renderers[id]=child
        -- v3.1.4: restore this character's saved FACE FLIP.
        child:setFaceFlip(mod.save and mod.save.get
          and tonumber(mod.save:get("face_flip_"..string.lower(tostring(id)))) == 1)
        if child.behaviorId=="BELLESTARMON" and child.data then
          child.data.runtimeBellePhysicsEnabled=false
          child.data.runtimeBelleBreastPhysics=0
          child.data.runtimeBelleThighPhysics=0
          child.data.runtimeBellePhysicsHz=BELLE_RECOMMENDED_PHYSICS.hz
          child.data.runtimeBelleMotionPhysics=BELLE_RECOMMENDED_PHYSICS.motion
          child.data.runtimeBelleImpactPhysics=BELLE_RECOMMENDED_PHYSICS.impact
          child.data.runtimeBelleIdlePhysics=BELLE_RECOMMENDED_PHYSICS.idle
          child.data.runtimeBelleResponseSpeed=BELLE_RECOMMENDED_PHYSICS.response
          if belleSelectorIdle then
            child.data.selectorIdleDelta=belleSelectorIdle.delta
            child.data.selectorIdleFrameCount=tonumber(belleSelectorIdle.frameCount) or 0
            child.data.selectorIdleDuration=tonumber(belleSelectorIdle.duration) or 0.65
          end
        end
        mod.log:info("character %s loaded: %d bones, %d weighted points, %d triangles%s%s",
          def.label,data.boneCount,data.positionCount,data.triangleCount,def._imported and " [imported]" or "",
          child.sourceYaw180 and " [source yaw 180 corrected]" or "")
        return child
      end
      mod.log:error("character %s renderer failed: %s",tostring(def.label),tostring(child))
      return nil
    end
    mod.log:error("character %s could not be loaded",def.label)
    return nil
  end
  for _,id in ipairs(CHARACTER_ORDER) do buildCharacterRenderer(id) end
  if not renderers.RED then return end

  -- v3.0.5: the user-supplied Goofy Running FBX is converted at build time
  -- into compact local-space rotation deltas. It is intentionally attached as
  -- a separate selector-only clip so BelleStarmon's overworld idle/walk/run/jump
  -- animations remain completely unchanged.
  belleSelectorIdle=loadLuaData(mod,"data/bellestarmon_selector_idle.lua")
  if belleSelectorIdle then
    local attached=0
    for _,child in pairs(renderers) do
      if child and child.behaviorId=="BELLESTARMON" and child.data then
        local d=child.data
        d.selectorIdleDelta=belleSelectorIdle.delta
        d.selectorIdleFrameCount=tonumber(belleSelectorIdle.frameCount) or 0
        d.selectorIdleDuration=tonumber(belleSelectorIdle.duration) or 0.65
        attached=attached+1
      end
    end
    mod.log:info("BelleStarmon Skin Selector idle loaded: %d frames from %s (%d renderer%s)",
      tonumber(belleSelectorIdle.frameCount) or 0,tostring(belleSelectorIdle.source or "embedded clip"),
      attached,attached==1 and "" or "s")
  end

  local function characterScaleKey(id)
    return "character_scale_"..string.lower(tostring(id or "RED"))
  end

  local function savedCharacterScale(id)
    local value=nil
    if mod.save and mod.save.get then value=mod.save:get(characterScaleKey(id)) end
    value=tonumber(value) or 1.0
    if value<0.50 then value=0.50 elseif value>1.50 then value=1.50 end
    return value
  end

  local function applyCharacterScale(id,value,persist)
    local child=renderers[id]
    if not child then return nil end
    local v=child:setUserScale(value)
    if persist~=false and mod.save and mod.save.set then
      mod.save:set(characterScaleKey(id),v)
    end
    return v
  end

  -- Apply any scale values already visible in mod.save. save.loaded below repeats
  -- this after the real save bucket is restored on startup.
  for _,id in ipairs(CHARACTER_ORDER) do
    applyCharacterScale(id,savedCharacterScale(id),false)
  end

  BELLE_PHYSICS_FIELDS={
    breast={runtime="runtimeBelleBreastPhysics"},
    buttocks={runtime="runtimeBelleButtocksPhysics"},
    thighs={runtime="runtimeBelleThighPhysics"},
    hair={runtime="runtimeBelleHairPhysics"},
  }
  local BELLE_PHYSICS_ADVANCED_FIELDS={
    motion={key="belle_physics_motion",runtime="runtimeBelleMotionPhysics",default=BELLE_RECOMMENDED_PHYSICS.motion,min=0,max=2},
    impact={key="belle_physics_impact",runtime="runtimeBelleImpactPhysics",default=BELLE_RECOMMENDED_PHYSICS.impact,min=0,max=2},
    idle={key="belle_physics_idle",runtime="runtimeBelleIdlePhysics",default=BELLE_RECOMMENDED_PHYSICS.idle,min=0,max=2},
    response={key="belle_physics_response",runtime="runtimeBelleResponseSpeed",default=BELLE_RECOMMENDED_PHYSICS.response,min=0.5,max=2},
  }
  local BELLE_PHYSICS_STYLE_ORDER={"SOFT","NATURAL","SPRINGY","TIGHT","HEAVY","FLOATY","JELLY"}
  local BELLE_PHYSICS_STYLE_LABEL={
    SOFT="SOFT",NATURAL="NATURAL",SPRINGY="SPRINGY",TIGHT="TIGHT",
    HEAVY="HEAVY",FLOATY="FLOATY",JELLY="JELLY",
  }
  local BELLE_PHYSICS_AXIS_ORDER={"FULL","VERTICAL","DEPTH","SIDE"}
  local BELLE_PHYSICS_AXIS_LABEL={
    FULL="FULL 3D",VERTICAL="VERTICAL",DEPTH="FRONT / BACK",SIDE="SIDE / SIDE",
  }
  local BELLE_PHYSICS_HZ_ORDER={60,90,120,144,240}
  local BELLE_PHYSICS_HZ_LABEL={
    [60]="60 HZ",[90]="90 HZ",[120]="120 HZ",[144]="144 HZ",[240]="240 HZ",
  }

  local function resetBelleSpring(child)
    if not child or not child.data then return end
    child.belleSoft=nil
    child.belleSoftSpeed=nil
    child.bellePhysicsAccumulator=nil
    child.bellePhysicsTargets=nil
    child.belleSoftWasJumping=nil
    child.bellePreviewKickWave=nil
    child.data.runtimeBelleSoft=nil
    child.skinKey=nil; child.voxelUploadedKey=nil; child.voxelFrameKey=nil
  end

  BELLE_PHYSICS_TOGGLES={
    breast={runtime="runtimeBelleBreastPhysics",strength=BELLE_RECOMMENDED_PHYSICS.breastStrength},
    buttocks={runtime="runtimeBelleButtocksPhysics",strength=BELLE_RECOMMENDED_PHYSICS.buttStrength},
    thighs={runtime="runtimeBelleThighPhysics",strength=BELLE_RECOMMENDED_PHYSICS.thighStrength},
    hair={runtime="runtimeBelleHairPhysics",strength=BELLE_RECOMMENDED_PHYSICS.hairStrength},
  }

  function bellePhysicsEnabledSaveKey(kind,id)
    local prefix=((id or "BELLESTARMON")=="WOW") and "wow" or "belle"
    if kind=="buttocks" then return prefix.."_butt_physics_enabled_v3039" end
    if kind=="thighs" then return prefix.."_thigh_physics_enabled_v3044" end
    if kind=="hair" then return prefix.."_hair_physics_enabled_v3044" end
    return prefix..((id or "BELLESTARMON")=="WOW" and "_physics_enabled_v3032" or "_physics_enabled_v3016")
  end
  function bellePhysicsStrengthSaveKey(kind,id)
    local prefix=((id or "BELLESTARMON")=="WOW") and "wow" or "belle"
    if kind=="buttocks" then return prefix.."_butt_physics_strength_v3039" end
    if kind=="thighs" then return prefix.."_thigh_physics_strength_v3044" end
    if kind=="hair" then return prefix.."_hair_physics_strength_v3044" end
    return ((id or "BELLESTARMON")=="WOW") and "wow_physics_strength_v3032" or "belle_physics_strength_v3025"
  end

  function savedBellePhysicsEnabled(kind,id)
    local field=BELLE_PHYSICS_TOGGLES[kind]
    if not field then return false end
    local value=nil
    if mod.save and mod.save.get then value=mod.save:get(bellePhysicsEnabledSaveKey(kind,id)) end
    -- Fresh saves / saves with no explicit choice start with physics OFF.
    if value==nil then return false end
    if value==false or value==0 or value=="0" or tostring(value):lower()=="false" then return false end
    return true
  end

  function savedBelleStrengthScale(id,kind)
    local value=nil
    if mod.save and mod.save.get then value=mod.save:get(bellePhysicsStrengthSaveKey(kind or "breast",id)) end
    value=tonumber(value) or 1.0
    if value<0 then value=0 elseif value>1.5 then value=1.5 end
    return value
  end

  function currentBellePhysicsEnabled(kind,id)
    local child=renderers[id or "BELLESTARMON"]
    if child and child.data then
      if kind=="buttocks" and child.data.runtimeBelleButtocksEnabled~=nil then
        return belleButtPhysicsEnabled(child.data)
      elseif kind=="breast" and child.data.runtimeBellePhysicsEnabled~=nil then
        return belleBreastPhysicsEnabled(child.data)
      elseif kind=="thighs" and child.data.runtimeBelleThighEnabled~=nil then
        return belleThighPhysicsEnabled(child.data)
      elseif kind=="hair" and child.data.runtimeBelleHairEnabled~=nil then
        return belleHairPhysicsEnabled(child.data)
      end
    end
    return savedBellePhysicsEnabled(kind,id)
  end

  function applyBellePhysicsEnabled(kind,enabled,persist,id)
    local field=BELLE_PHYSICS_TOGGLES[kind]
    local child=renderers[id or "BELLESTARMON"]
    if not field or not child or not child.data then return nil end
    enabled=enabled==true or enabled==1 or enabled=='1' or tostring(enabled):lower()=='true'

    -- The checkbox is the single source of truth. Reapply the fixed preset on
    -- every ON transition so a stale/legacy runtime value cannot leave the box
    -- visually checked while the actual spring drive remains disabled.
    if kind=="breast" then child.data.runtimeBellePhysicsEnabled=enabled elseif kind=="buttocks" then child.data.runtimeBelleButtocksEnabled=enabled elseif kind=="thighs" then child.data.runtimeBelleThighEnabled=enabled else child.data.runtimeBelleHairEnabled=enabled end
    child.data.runtimeBellePhysicsStyle="RECOMMENDED"
    child.data.runtimeBellePhysicsAxes="FULL"
    child.data.runtimeBellePhysicsHz=BELLE_RECOMMENDED_PHYSICS.hz
    child.data.runtimeBelleMotionPhysics=BELLE_RECOMMENDED_PHYSICS.motion
    child.data.runtimeBelleImpactPhysics=BELLE_RECOMMENDED_PHYSICS.impact
    child.data.runtimeBelleIdlePhysics=BELLE_RECOMMENDED_PHYSICS.idle
    child.data.runtimeBelleResponseSpeed=BELLE_RECOMMENDED_PHYSICS.response
    child.data[field.runtime]=enabled and (field.strength*savedBelleStrengthScale(id,kind)) or 0

    resetBelleSpring(child)
    -- resetBelleSpring intentionally preserves configuration, but set the live
    -- gate/strength again defensively in case a future reset grows broader.
    if kind=="breast" then child.data.runtimeBellePhysicsEnabled=enabled elseif kind=="buttocks" then child.data.runtimeBelleButtocksEnabled=enabled elseif kind=="thighs" then child.data.runtimeBelleThighEnabled=enabled else child.data.runtimeBelleHairEnabled=enabled end
    child.data[field.runtime]=enabled and (field.strength*savedBelleStrengthScale(id,kind)) or 0
    if enabled then
      -- Give the selector immediate visual confirmation that PHYSICS turned on.
      -- The live spring takes over on the next preview/game update.
      child.belleSoft=child.belleSoft or {}
      if kind=="breast" then
        child.belleSoft.breastL={x=0,y=-0.012,z=0,yv=0.28}
        child.belleSoft.breastR={x=0,y=-0.010,z=0,yv=0.25}
      elseif kind=="buttocks" then
        child.belleSoft.buttL={x=0,y=-0.004,z=0.010,yv=0.20,zv=0.11}
        child.belleSoft.buttR={x=0,y=-0.004,z=0.010,yv=0.19,zv=0.10}
      elseif kind=="thighs" then
        child.belleSoft.thighL={x=0,y=-0.004,z=0.006,yv=0.12,zv=0.06}
        child.belleSoft.thighR={x=0,y=-0.004,z=0.006,yv=0.12,zv=0.06}
      elseif kind=="hair" then
        child.belleSoft.hairL={x=0,y=0.002,z=0.010,yv=0.08,zv=0.10}
        child.belleSoft.hairR={x=0,y=0.002,z=0.010,yv=0.08,zv=0.10}
      end
      child.data.runtimeBelleSoft=child.belleSoft
    end
    if kind=="breast" then child.data.runtimeBellePhysicsEnabled=enabled elseif kind=="buttocks" then child.data.runtimeBelleButtocksEnabled=enabled elseif kind=="thighs" then child.data.runtimeBelleThighEnabled=enabled else child.data.runtimeBelleHairEnabled=enabled end
    if persist~=false and mod.save and mod.save.set then mod.save:set(bellePhysicsEnabledSaveKey(kind,id),enabled and 1 or 0) end
    child.skinKey=nil; child.voxelUploadedKey=nil; child.voxelFrameKey=nil
    return enabled
  end

  local function applyBelleRecommendedProfile(id)
    local child=renderers[id or "BELLESTARMON"]
    if not child or not child.data then return end
    child.data.runtimeBellePhysicsStyle="RECOMMENDED"
    child.data.runtimeBellePhysicsAxes="FULL"
    child.data.runtimeBellePhysicsHz=BELLE_RECOMMENDED_PHYSICS.hz
    child.data.runtimeBelleMotionPhysics=BELLE_RECOMMENDED_PHYSICS.motion
    child.data.runtimeBelleImpactPhysics=BELLE_RECOMMENDED_PHYSICS.impact
    child.data.runtimeBelleIdlePhysics=BELLE_RECOMMENDED_PHYSICS.idle
    child.data.runtimeBelleResponseSpeed=BELLE_RECOMMENDED_PHYSICS.response
  end

  local function savedBellePhysicsStyle()
    local value=nil
    if mod.save and mod.save.get then value=mod.save:get("belle_physics_style") end
    value=tostring(value or "NATURAL"):upper()
    if not BELLE_PHYSICS_STYLE_LABEL[value] then value="NATURAL" end
    return value
  end

  local function applyBellePhysicsStyle(value,persist)
    local child=renderers.BELLESTARMON
    if not child or not child.data then return nil end
    local style=tostring(value or "NATURAL"):upper()
    if not BELLE_PHYSICS_STYLE_LABEL[style] then style="NATURAL" end
    child.data.runtimeBellePhysicsStyle=style
    -- A new response curve should not inherit velocity from the old one.
    resetBelleSpring(child)
    if persist~=false and mod.save and mod.save.set then mod.save:set("belle_physics_style",style) end
    return style
  end

  local function savedBellePhysicsAxes()
    local value=nil
    if mod.save and mod.save.get then value=mod.save:get("belle_physics_axes") end
    value=tostring(value or "FULL"):upper()
    if not BELLE_PHYSICS_AXIS_LABEL[value] then value="FULL" end
    return value
  end

  local function applyBellePhysicsAxes(value,persist)
    local child=renderers.BELLESTARMON
    if not child or not child.data then return nil end
    local mode=tostring(value or "FULL"):upper()
    if not BELLE_PHYSICS_AXIS_LABEL[mode] then mode="FULL" end
    child.data.runtimeBellePhysicsAxes=mode
    -- Clear disabled-axis momentum immediately when changing modes.
    resetBelleSpring(child)
    if persist~=false and mod.save and mod.save.set then mod.save:set("belle_physics_axes",mode) end
    return mode
  end

  local function savedBellePhysicsHz()
    local value=nil
    if mod.save and mod.save.get then value=tonumber(mod.save:get("belle_physics_hz")) end
    value=value or 120
    local best=120
    local bestDist=math.huge
    for _,hz in ipairs(BELLE_PHYSICS_HZ_ORDER) do
      local dist=math.abs(value-hz)
      if dist<bestDist then best=hz; bestDist=dist end
    end
    return best
  end

  local function applyBellePhysicsHz(value,persist)
    local child=renderers.BELLESTARMON
    if not child or not child.data then return nil end
    local requested=tonumber(value) or 120
    local best=120
    local bestDist=math.huge
    for _,hz in ipairs(BELLE_PHYSICS_HZ_ORDER) do
      local dist=math.abs(requested-hz)
      if dist<bestDist then best=hz; bestDist=dist end
    end
    child.data.runtimeBellePhysicsHz=best
    resetBelleSpring(child)
    child.data.runtimeBellePhysicsHz=best
    if persist~=false and mod.save and mod.save.set then mod.save:set("belle_physics_hz",best) end
    return best
  end

  local function savedBellePhysics(kind,id)
    local field=BELLE_PHYSICS_FIELDS[kind]
    if not field then return 1.0 end
    local value=nil
    if mod.save and mod.save.get then value=mod.save:get(bellePhysicsStrengthSaveKey(kind,id)) end
    value=tonumber(value) or 1.0
    if value<0 then value=0 elseif value>1.5 then value=1.5 end
    return value
  end

  function applyBellePhysics(kind,value,persist,id)
    local field=BELLE_PHYSICS_FIELDS[kind]
    local child=renderers[id or "BELLESTARMON"]
    if not field or not child or not child.data then return nil end
    local v=tonumber(value) or 1.0
    if v<0 then v=0 elseif v>1.5 then v=1.5 end
    if not currentBellePhysicsEnabled(kind,id) then
      child.data[field.runtime]=0
    elseif kind=="breast" then
      child.data[field.runtime]=BELLE_RECOMMENDED_PHYSICS.breastStrength*v
    elseif kind=="buttocks" then
      child.data[field.runtime]=BELLE_RECOMMENDED_PHYSICS.buttStrength*v
    elseif kind=="thighs" then
      child.data[field.runtime]=BELLE_RECOMMENDED_PHYSICS.thighStrength*v
    elseif kind=="hair" then
      child.data[field.runtime]=BELLE_RECOMMENDED_PHYSICS.hairStrength*v
    else
      child.data[field.runtime]=v
    end
    child.skinKey=nil; child.voxelUploadedKey=nil; child.voxelFrameKey=nil
    if persist~=false and mod.save and mod.save.set then mod.save:set(bellePhysicsStrengthSaveKey(kind,id),v) end
    return v
  end

  local function savedBelleAdvanced(kind)
    local field=BELLE_PHYSICS_ADVANCED_FIELDS[kind]
    if not field then return 1.0 end
    local value=nil
    if mod.save and mod.save.get then value=mod.save:get(field.key) end
    value=tonumber(value) or field.default
    if value<field.min then value=field.min elseif value>field.max then value=field.max end
    return value
  end

  local function applyBelleAdvanced(kind,value,persist,id)
    local field=BELLE_PHYSICS_ADVANCED_FIELDS[kind]
    local child=renderers[id or "BELLESTARMON"]
    if not field or not child or not child.data then return nil end
    local v=tonumber(value) or field.default
    if v<field.min then v=field.min elseif v>field.max then v=field.max end
    child.data[field.runtime]=v
    if kind=="response" then resetBelleSpring(child)
    else child.skinKey=nil; child.voxelUploadedKey=nil; child.voxelFrameKey=nil end
    if persist~=false and mod.save and mod.save.set then mod.save:set(field.key,v) end
    return v
  end

  local function applyBelleSavedProfile(id)
    local child=renderers[id or "BELLESTARMON"]
    if not child or (child.behaviorId~="BELLESTARMON" and child.behaviorId~="WOW") then return end
    -- Always restore the fixed preset first. Load the PHYSICS checkbox plus the
    -- single v3.0.25 breast-strength slider; legacy multi-slider/style/rate values
    -- remain ignored.
    applyBelleRecommendedProfile(id)
    applyBellePhysicsEnabled("breast",savedBellePhysicsEnabled("breast",id),false,id)
    applyBellePhysicsEnabled("buttocks",savedBellePhysicsEnabled("buttocks",id),false,id)
    applyBellePhysicsEnabled("thighs",savedBellePhysicsEnabled("thighs",id),false,id)
    applyBellePhysicsEnabled("hair",savedBellePhysicsEnabled("hair",id),false,id)
    local breastIndependent=nil
    local buttIndependent=nil
    local thighIndependent=nil
    if mod.save and mod.save.get then
      local prefix=(child.behaviorId=="WOW") and "wow" or "belle"
      breastIndependent=mod.save:get(prefix.."_breast_independent_v3040")
      buttIndependent=mod.save:get(prefix.."_butt_independent_v3040")
      thighIndependent=mod.save:get(prefix.."_thigh_independent_v3044")
    end
    child.data.runtimeBelleBreastIndependent=not (breastIndependent==false or breastIndependent==0 or breastIndependent=="0" or tostring(breastIndependent):lower()=="false")
    child.data.runtimeBelleButtIndependent=not (buttIndependent==false or buttIndependent==0 or buttIndependent=="0" or tostring(buttIndependent):lower()=="false")
    child.data.runtimeBelleThighIndependent=not (thighIndependent==false or thighIndependent==0 or thighIndependent=="0" or tostring(thighIndependent):lower()=="false")
    local areaLX,areaLY,areaLR,areaRX,areaRY,areaRR,areaUpper,areaLower=nil,nil,nil,nil,nil,nil,nil,nil
    if mod.save and mod.save.get then
      areaLX=tonumber(mod.save:get(red3dBreastAreaSaveKey(id,"left_x")))
      areaLY=tonumber(mod.save:get(red3dBreastAreaSaveKey(id,"left_y")))
      areaLR=tonumber(mod.save:get(red3dBreastAreaSaveKey(id,"left_radius")))
      areaRX=tonumber(mod.save:get(red3dBreastAreaSaveKey(id,"right_x")))
      areaRY=tonumber(mod.save:get(red3dBreastAreaSaveKey(id,"right_y")))
      areaRR=tonumber(mod.save:get(red3dBreastAreaSaveKey(id,"right_radius")))
      areaUpper=tonumber(mod.save:get(red3dBreastAreaSaveKey(id,"upper_limit")))
      areaLower=tonumber(mod.save:get(red3dBreastAreaSaveKey(id,"lower_limit")))
    end
    child.data.runtimeBelleBreastAreaLeftX=math.max(0.06,math.min(0.49,areaLX or 0.40))
    child.data.runtimeBelleBreastAreaLeftY=math.max(0.06,math.min(0.70,areaLY or 0.29))
    child.data.runtimeBelleBreastAreaLeftRadius=math.max(0.045,math.min(0.30,areaLR or 0.13))
    child.data.runtimeBelleBreastAreaRightX=math.max(0.51,math.min(0.94,areaRX or 0.60))
    child.data.runtimeBelleBreastAreaRightY=math.max(0.06,math.min(0.70,areaRY or 0.29))
    child.data.runtimeBelleBreastAreaRightRadius=math.max(0.045,math.min(0.30,areaRR or 0.13))
    child.data.runtimeBelleBreastAreaUpperLimit=math.max(0.04,math.min(0.55,areaUpper or 0.16))
    child.data.runtimeBelleBreastAreaLowerLimit=math.max(child.data.runtimeBelleBreastAreaUpperLimit+0.04,math.min(0.72,areaLower or 0.44))
  end

  for id,child in pairs(renderers) do
    if child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      applyBelleSavedProfile(id)
    end
  end

  local okPlayer,Player=pcall(require,"src.world.Player")
  local okGV,GameVersion=pcall(require,"src.core.GameVersion")
  if not okPlayer or not Player or not okGV or not GameVersion then
    mod.log:error("engine internals needed for Player:draw are unavailable -- this build of Gen1Recomp is not compatible")
    return
  end

  local renderer=ActiveRenderer.new(renderers,storedCharacter())

  -- BelleStarmon keyboard WALK mode is a real movement mode, not only an
  -- animation choice. Gen1Recomp expresses walking speed as frames per 16px
  -- step, so doubling the resolved frame count makes keyboard/digital walking
  -- exactly half the normal on-foot speed. Analog movement is intentionally
  -- left alone; stick magnitude continues to own its idle/walk/run blend.
  pcall(function()
    mod.hooks:wrap("movement.speed",function(next,frames,ctx)
      local resolved=next(frames,ctx)
      local active=renderer:getActive()
      if active and active.behaviorId=="BELLESTARMON" then
        -- Read Ctrl here so the speed change happens on the same step that the
        -- toggle is pressed instead of waiting for the next render update.
        active:updateBelleKeyboardWalkToggle()
        local player=ctx and ctx.player or nil
        local analog=player and player.red3dAnalogMoveActive==true
        local vehicle=ctx and (ctx.onBike or ctx.surfing)
        if active.belleKeyboardWalk==true and not analog and not vehicle then
          local base=tonumber(resolved) or tonumber(frames) or 16
          return math.max(1,base*2)
        end
      end
      return resolved
    end,math.huge)
  end)

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

  local function exportSkinPackage(id)
    local def=CHARACTER_DEFS[id]
    if not def then return false,"No highlighted skin." end
    if not skinFsReady() or not (love and love.filesystem and love.filesystem.write) then
      return false,"Writable skin folder is unavailable."
    end
    local modelBytes=def._modelBytes or mod:read(def.data)
    if type(modelBytes)~="string" then return false,"Model data could not be read." end
    local atlasPaths=def.atlasFrames or {def.atlas}
    local atlasBlobs={}
    for i,p in ipairs(atlasPaths) do
      local blob=(def.atlasBytes and def.atlasBytes[p]) or mod:read(p)
      if type(blob)~="string" then return false,"Texture atlas "..i.." could not be read." end
      atlasBlobs[#atlasBlobs+1]=blob
    end
    local lines={
      RED3D_SKIN_MAGIC,
      "id="..skinSafeId(def.id or id),
      "behaviorId="..skinSafeId(def.behaviorId or def.id or id),
      "label="..skinSafeToken(def.label or id,id),
      "profile="..skinSafeToken(def.profile or "AANG_MIXAMO","AANG_MIXAMO"),
      "height="..tostring(tonumber(def.height) or 24),
      "armRestDeg="..tostring(tonumber(def.armRestDeg) or 0),
      "modelYawOffset="..tostring(tonumber(def.modelYawOffset) or 0),
      "projectYawOffset="..tostring(tonumber(def.projectYawOffset) or 0),
      "sourceYaw180="..((def.sourceYaw180==true) and "1" or "0"),
      "postSkinZUp="..((def.postSkinZUp==true) and "1" or "0"),
      "dynamicAtlas="..skinSafeToken(def.dynamicAtlas or "",""),
      "modelLen="..tostring(#modelBytes),
      "atlasCount="..tostring(#atlasBlobs),
    }
    for i,blob in ipairs(atlasBlobs) do lines[#lines+1]="atlas"..i.."Len="..tostring(#blob) end
    local package=table.concat(lines,"\n").."\n\n"..modelBytes..table.concat(atlasBlobs)
    local base=skinSafeId(def.id or id):lower()
    local rel=RED3D_SKIN_EXPORT_DIR.."/"..base..".red3dskin"
    local ok,result,writeErr=pcall(love.filesystem.write,rel,package)
    if not ok or result==false then return false,"Export failed: "..tostring(writeErr or result) end
    local native=skinNativeRoot().."/exports/"..base..".red3dskin"
    mod.log:info("skin exported: %s",native)
    return true,native
  end

  local wireAccessoryRenderer

  local function importSkinPackages()
    local before={}
    for id,_ in pairs(renderers) do before[id]=true end
    local added,failed=scanSkinPackagesIntoDefs()
    local loaded=0
    for _,id in ipairs(CHARACTER_ORDER) do
      if not renderers[id] and CHARACTER_DEFS[id] and CHARACTER_DEFS[id]._imported then
        if buildCharacterRenderer(id) then
          applyCharacterScale(id,savedCharacterScale(id),false)
          local child=renderers[id]
          wireAccessoryRenderer(child)
          if child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
            applyBelleSavedProfile(id)
          end
          loaded=loaded+1
        end
      end
    end
    local native=skinNativeRoot().."/imports"
    mod.log:info("skin import scan: loaded=%d failed=%d folder=%s",loaded,failed,native)
    return loaded,failed,native
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
  local AccessoryImporter=loadLocalModule("lib/AccessoryImporter.lua")
  local HumanoidRigger=loadLocalModule("lib/HumanoidRigger.lua")
  local DonorRigCloner=loadLocalModule("lib/DonorRigCloner.lua")

  -- v3.0.17 static accessory library. ZIP packages are read as data only and
  -- may contain OBJ(+MTL), FBX, or Collada DAE plus image textures. Attachments are saved per
  -- character and follow a resolved body bone in both gameplay and the selector.
  local ACCESSORY_ROOT="red3d_accessories"
  local ACCESSORY_DEFS={}
  local ACCESSORY_ORDER={}
  local ACCESSORY_STATE={}
  local ACCESSORY_BONES={"HEAD","NECK","CHEST","HIPS","LEFT_HAND","RIGHT_HAND","LEFT_FOOT","RIGHT_FOOT"}

  -- v3.0.30 character imports are a first-class Skin Selector workflow rather
  -- than being hidden under Accessories. The parser is shared because it is the
  -- same safe OBJ/FBX/DAE ZIP reader, but these source meshes are used to create
  -- actual selectable characters, not body attachments.
  local CHARACTER_IMPORT_ROOT="red3d_characters"
  local CHARACTER_SOURCE_DEFS={}
  local CHARACTER_SOURCE_ORDER={}
  local DONOR_RIG_IDS={"BELLESTARMON"}
  local function donorRigLabel(id)
    local def=CHARACTER_DEFS[id]
    return tostring(def and def.label or id or "DONOR")
  end

  -- v3.0.29 experimental Mixamo-style local humanoid rigger. A static imported
  -- OBJ/FBX/DAE mesh can be given an estimated humanoid skeleton, adjusted joint
  -- by joint, auto-weighted, previewed with the generic locomotion controller,
  -- and saved as a selectable character. The original ZIP remains the source.
  local RIG_STATE={}
  local RIG_JOINT_INDEX={}
  if HumanoidRigger and type(HumanoidRigger.JOINT_ORDER)=="table" then
    for i,name in ipairs(HumanoidRigger.JOINT_ORDER) do RIG_JOINT_INDEX[name]=i end
  end

  local function rigSavePrefix(accessoryId)
    return "rig_"..skinSafeId(accessoryId or "MODEL"):sub(1,58).."_"
  end

  local function rigCharacterId(accessoryId)
    return "RIG_"..skinSafeId(accessoryId or "MODEL"):sub(1,52)
  end

  local function rigSaved(accessoryId,field)
    if mod.save and mod.save.get then return mod.save:get(rigSavePrefix(accessoryId)..field) end
    return nil
  end

  local function rigSavedBool(accessoryId,field,default)
    local v=rigSaved(accessoryId,field)
    if v==nil then return default==true end
    return v==true or v==1 or v=="1" or v=="true"
  end

  local function rigSourceDef(sourceId)
    return CHARACTER_SOURCE_DEFS[sourceId] or ACCESSORY_DEFS[sourceId]
  end

  local function rigState(accessoryId)
    local def=rigSourceDef(accessoryId)
    if not def or not HumanoidRigger then return nil end
    if RIG_STATE[accessoryId] then return RIG_STATE[accessoryId] end
    local defaults=HumanoidRigger.defaultConfig(def)
    local st={
      enabled=rigSavedBool(accessoryId,"enabled",false),
      mirror=rigSavedBool(accessoryId,"mirror",true),
      height=tonumber(rigSaved(accessoryId,"height")) or tonumber(defaults.height) or 24,
      armRest=tonumber(rigSaved(accessoryId,"armRest")) or tonumber(defaults.armRest) or -90,
      softness=tonumber(rigSaved(accessoryId,"softness")) or tonumber(defaults.softness) or 0.070,
      weightStyle=tostring(rigSaved(accessoryId,"weightStyle") or defaults.weightStyle or "BALANCED"):upper(),
      textureIndex=tonumber(rigSaved(accessoryId,"textureIndex")) or tonumber(def.defaultTextureIndex) or 1,
      uvVariant=tonumber(rigSaved(accessoryId,"uvVariant")) or 1,
      flipU=rigSavedBool(accessoryId,"flipU",false), flipV=rigSavedBool(accessoryId,"flipV",false),
      swapUV=rigSavedBool(accessoryId,"swapUV",false),
      donorId=tostring(rigSaved(accessoryId,"donorId") or "BELLESTARMON"),
      meshSwapYZ=rigSavedBool(accessoryId,"meshSwapYZ",false),
      meshFlipX=rigSavedBool(accessoryId,"meshFlipX",false),
      meshFlipY=rigSavedBool(accessoryId,"meshFlipY",false),
      meshFlipZ=rigSavedBool(accessoryId,"meshFlipZ",false),
      fitScale=tonumber(rigSaved(accessoryId,"fitScale")) or 1.0,
      fitX=tonumber(rigSaved(accessoryId,"fitX")) or 0,
      fitY=tonumber(rigSaved(accessoryId,"fitY")) or 0,
      fitZ=tonumber(rigSaved(accessoryId,"fitZ")) or 0,
      joints=HumanoidRigger.deserializeJoints(rigSaved(accessoryId,"joints"),defaults.joints),
      bounds=defaults.bounds,
    }
    RIG_STATE[accessoryId]=st
    return st
  end

  local function persistRigField(accessoryId,field,value)
    local st=rigState(accessoryId)
    if not st then return nil end
    st[field]=value
    if mod.save and mod.save.set then mod.save:set(rigSavePrefix(accessoryId)..field,value) end
    return value
  end

  local function persistRigJoints(accessoryId)
    local st=rigState(accessoryId)
    if st and HumanoidRigger and mod.save and mod.save.set then
      mod.save:set(rigSavePrefix(accessoryId).."joints",HumanoidRigger.serializeJoints(st))
    end
  end

  local function resetRigAutoSetup(accessoryId)
    local def=rigSourceDef(accessoryId)
    local st=rigState(accessoryId)
    if not def or not st or not HumanoidRigger then return end
    local defaults=HumanoidRigger.defaultConfig(def)
    st.joints=defaults.joints; st.bounds=defaults.bounds
    st.softness=defaults.softness or 0.070
    st.weightStyle=defaults.weightStyle or "BALANCED"
    persistRigJoints(accessoryId)
    persistRigField(accessoryId,"softness",st.softness)
    persistRigField(accessoryId,"weightStyle",st.weightStyle)
  end

  local function rigTextureSettings(st)
    return {
      textureIndex=st and st.textureIndex or 1, uvVariant=st and st.uvVariant or 1,
      flipU=st and st.flipU==true, flipV=st and st.flipV==true, swapUV=st and st.swapUV==true,
    }
  end

  local function rigAtlasFor(def,st,id)
    local options=type(def and def.textureOptions)=="table" and def.textureOptions or {}
    local index=math.floor(tonumber(st and st.textureIndex) or tonumber(def and def.defaultTextureIndex) or 1)
    if #options>0 then if index<1 then index=1 elseif index>#options then index=#options end end
    local option=options[index] or options[1]
    if not option or type(option.bytes)~="string" then return "assets/red_atlas.png",nil end
    local e=tostring(option.ext or "png"):lower()
    if e~="png" and e~="jpg" and e~="jpeg" and e~="bmp" and e~="tga" and e~="dds" then e="png" end
    local key="@red3drig/"..tostring(id).."/atlas."..e
    return key,{[key]=option.bytes}
  end

  local function donorCloneCharacterId(sourceId,donorId)
    return "CLONE_"..skinSafeId(donorId or "DONOR"):sub(1,18).."_"..skinSafeId(sourceId or "MODEL"):sub(1,38)
  end

  local function donorCloneSettings(st)
    return {
      textureIndex=st and st.textureIndex or 1, uvVariant=st and st.uvVariant or 1,
      flipU=st and st.flipU==true, flipV=st and st.flipV==true, swapUV=st and st.swapUV==true,
      swapYZ=st and st.meshSwapYZ==true, flipX=st and st.meshFlipX==true,
      flipY=st and st.meshFlipY==true, flipZ=st and st.meshFlipZ==true,
      fitScale=st and st.fitScale or 1.0, fitX=st and st.fitX or 0,
      fitY=st and st.fitY or 0, fitZ=st and st.fitZ or 0,
    }
  end

  local function buildDonorCharacterDef(sourceId)
    local source=rigSourceDef(sourceId)
    local st=rigState(sourceId)
    if not source or not st or not DonorRigCloner then return nil,"donor-rig cloner unavailable" end
    local donorId=tostring(st.donorId or "BELLESTARMON")
    local donorChild=renderers[donorId]
    local donorDef=CHARACTER_DEFS[donorId]
    if not donorChild or not donorChild.data or not donorDef then return nil,"donor character is not loaded: "..donorId end
    local data,err=DonorRigCloner.buildData(source,donorChild.data,donorCloneSettings(st))
    if not data then return nil,err end
    local id=donorCloneCharacterId(sourceId,donorId)
    local atlas,atlasBytes=rigAtlasFor(source,st,id)
    local stats=data._donorTransferStats
    return {
      id=id,behaviorId=donorId,label=tostring(source.label or "Imported").." ("..donorRigLabel(donorId).." Rig)",
      data="@red3dclone/"..id.."/runtime.lua",_runtimeData=data,_rigAccessoryId=sourceId,
      atlas=atlas,atlasBytes=atlasBytes,height=tonumber(donorDef.height) or 24,
      profile=donorDef.profile or ((donorId=="WOW") and "WOW_FBX" or "BELLESTARMON"),
      armRestDeg=tonumber(donorDef.armRestDeg) or 0,modelYawOffset=tonumber(donorDef.modelYawOffset) or 0,
      projectYawOffset=tonumber(donorDef.projectYawOffset) or 0,sourceYaw180=donorDef.sourceYaw180==true,postSkinZUp=donorDef.postSkinZUp==true,dynamicAtlas=donorDef.dynamicAtlas,
      _imported=true,_rigged=true,_donorClone=true,_donorId=donorId,_donorStats=stats,
    }
  end

  local function registerDonorCharacter(sourceId)
    local def,err=buildDonorCharacterDef(sourceId)
    if not def then return nil,err end
    local id=def.id
    -- If the same source was previously cloned from the other donor, remove the
    -- stale entry so changing RIG SOURCE produces one predictable test skin.
    for i=#CHARACTER_ORDER,1,-1 do
      local oldId=CHARACTER_ORDER[i]
      local old=CHARACTER_DEFS[oldId]
      if old and old._donorClone and old._rigAccessoryId==sourceId and oldId~=id then
        renderers[oldId]=nil; CHARACTER_DEFS[oldId]=nil; table.remove(CHARACTER_ORDER,i)
      end
    end
    CHARACTER_DEFS[id]=def
    local found=false; for _,existing in ipairs(CHARACTER_ORDER) do if existing==id then found=true break end end
    if not found then CHARACTER_ORDER[#CHARACTER_ORDER+1]=id end
    renderers[id]=nil
    local child=buildCharacterRenderer(id)
    if not child then return nil,"renderer build failed" end
    applyCharacterScale(id,savedCharacterScale(id),false)
    wireAccessoryRenderer(child)
    if child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW" then applyBelleSavedProfile(id) end
    persistRigField(sourceId,"donorId",def._donorId)
    persistRigField(sourceId,"cloneDonor",true)
    persistRigField(sourceId,"enabled",true)
    return id
  end

  local function buildRigCharacterDef(accessoryId)
    local def=rigSourceDef(accessoryId)
    local st=rigState(accessoryId)
    if not def or not st or not HumanoidRigger then return nil,"rigger unavailable" end
    local data,err=HumanoidRigger.buildData(def,st,rigTextureSettings(st))
    if not data then return nil,err end
    local id=rigCharacterId(accessoryId)
    local atlas,atlasBytes=rigAtlasFor(def,st,id)
    return {
      id=id,behaviorId=id,label=tostring(def.label or "Imported").." (Rigged)",
      data="@red3drig/"..id.."/runtime.lua",_runtimeData=data,_rigAccessoryId=accessoryId,
      atlas=atlas,atlasBytes=atlasBytes,height=math.max(12,math.min(40,tonumber(st.height) or 24)),
      profile="GENERIC",armRestDeg=math.max(-120,math.min(120,tonumber(st.armRest) or -90)),
      modelYawOffset=0,projectYawOffset=0,sourceYaw180=false,postSkinZUp=false,_imported=true,_rigged=true,
    }
  end

  local function registerRiggedCharacter(accessoryId)
    local def,err=buildRigCharacterDef(accessoryId)
    if not def then return nil,err end
    local id=def.id
    CHARACTER_DEFS[id]=def
    local found=false
    for _,existing in ipairs(CHARACTER_ORDER) do if existing==id then found=true break end end
    if not found then CHARACTER_ORDER[#CHARACTER_ORDER+1]=id end
    renderers[id]=nil
    local child=buildCharacterRenderer(id)
    if child then
      applyCharacterScale(id,savedCharacterScale(id),false)
      wireAccessoryRenderer(child)
      persistRigField(accessoryId,"cloneDonor",false)
      persistRigField(accessoryId,"enabled",true)
      return id
    end
    return nil,"renderer build failed"
  end

  local function clearRiggedCharacters()
    for i=#CHARACTER_ORDER,1,-1 do
      local id=CHARACTER_ORDER[i]
      if CHARACTER_DEFS[id] and CHARACTER_DEFS[id]._rigged then
        renderers[id]=nil
        CHARACTER_DEFS[id]=nil
        table.remove(CHARACTER_ORDER,i)
      end
    end
  end

  local function restoreRiggedCharacters()
    if not HumanoidRigger then return 0 end
    local n,seen=0,{}
    local function tryList(order)
      for _,sourceId in ipairs(order or {}) do
        if not seen[sourceId] then
          seen[sourceId]=true
          if rigSavedBool(sourceId,"enabled",false) then
            local useDonor=rigSavedBool(sourceId,"cloneDonor",false)
            local id
            if useDonor and DonorRigCloner then id=registerDonorCharacter(sourceId)
            else id=registerRiggedCharacter(sourceId) end
            if id then n=n+1 end
          end
        end
      end
    end
    tryList(CHARACTER_SOURCE_ORDER)
    -- Backward compatibility: v3.0.29 stored rig sources in the accessory ZIP
    -- folder. Saved rigs from that build still restore, but new rigging lives in
    -- the Character Import screen.
    tryList(ACCESSORY_ORDER)
    return n
  end

  local function accessorySavePrefix(characterId,accessoryId)
    local c=skinSafeId(characterId or "RED"):sub(1,24)
    local a=skinSafeId(accessoryId or "ACCESSORY"):sub(1,52)
    return "acc_"..c.."_"..a.."_"
  end

  local function accessoryState(characterId,accessoryId)
    characterId=characterId or "RED"
    local def=ACCESSORY_DEFS[accessoryId]
    if not def then return nil end
    ACCESSORY_STATE[characterId]=ACCESSORY_STATE[characterId] or {}
    local st=ACCESSORY_STATE[characterId][accessoryId]
    if st then return st end
    local prefix=accessorySavePrefix(characterId,accessoryId)
    local function saved(field)
      if mod.save and mod.save.get then return mod.save:get(prefix..field) end
      return nil
    end
    local function savedBool(field)
      local v=saved(field)
      return v==true or v==1 or v=="1" or v=="true"
    end
    st={
      enabled=savedBool("enabled"),
      bone=tostring(saved("bone") or def.defaultBone or "CHEST"),
      x=tonumber(saved("x")); y=tonumber(saved("y")); z=tonumber(saved("z"));
      scale=tonumber(saved("scale")); rx=tonumber(saved("rx")); ry=tonumber(saved("ry")); rz=tonumber(saved("rz"));
      textureIndex=tonumber(saved("textureIndex")),
      uvVariant=tonumber(saved("uvVariant")),
      flipU=savedBool("flipU"), flipV=savedBool("flipV"), swapUV=savedBool("swapUV"),
      repeatTexture=savedBool("repeatTexture"), nearestFilter=savedBool("nearestFilter"),
    }
    local savedAutoMaterial=saved("autoMaterialTextures")
    if savedAutoMaterial==nil then
      st.autoMaterialTextures=def.defaultAutoMaterialTextures==true
    else
      st.autoMaterialTextures=(savedAutoMaterial==true or savedAutoMaterial==1 or savedAutoMaterial=="1" or savedAutoMaterial=="true")
    end
    if st.x==nil then st.x=tonumber(def.defaultX) or 0 end
    if st.y==nil then st.y=tonumber(def.defaultY) or 0 end
    if st.z==nil then st.z=tonumber(def.defaultZ) or 0 end
    if st.scale==nil then st.scale=tonumber(def.defaultScale) or 0.16 end
    if st.rx==nil then st.rx=tonumber(def.defaultRX) or 0 end
    if st.ry==nil then st.ry=tonumber(def.defaultRY) or 0 end
    if st.rz==nil then st.rz=tonumber(def.defaultRZ) or 0 end
    local textureCount=type(def.textureOptions)=="table" and #def.textureOptions or 0
    if st.textureIndex==nil then st.textureIndex=tonumber(def.defaultTextureIndex) or 1 end
    st.textureIndex=math.floor(tonumber(st.textureIndex) or 1)
    if textureCount>0 then
      if st.textureIndex<1 then st.textureIndex=1 elseif st.textureIndex>textureCount then st.textureIndex=textureCount end
    else
      st.textureIndex=1
    end
    local uvCount=type(def.uvVariants)=="table" and #def.uvVariants or 0
    if st.uvVariant==nil then st.uvVariant=1 end
    st.uvVariant=math.floor(tonumber(st.uvVariant) or 1)
    if uvCount>0 then
      if st.uvVariant<1 then st.uvVariant=1 elseif st.uvVariant>uvCount then st.uvVariant=uvCount end
    else
      st.uvVariant=1
    end
    ACCESSORY_STATE[characterId][accessoryId]=st
    return st
  end

  local function persistAccessoryField(characterId,accessoryId,field,value)
    local st=accessoryState(characterId,accessoryId)
    if not st then return nil end
    st[field]=value
    if mod.save and mod.save.set then mod.save:set(accessorySavePrefix(characterId,accessoryId)..field,value) end
    local child=renderers[characterId]
    if child then child.voxelUploadedKey=nil; child.skinKey=nil; child.voxelFrameKey=nil end
    return value
  end

  local function resetAccessoryPlacement(characterId,accessoryId)
    local def=ACCESSORY_DEFS[accessoryId]
    local st=accessoryState(characterId,accessoryId)
    if not def or not st then return end
    local values={
      bone=def.defaultBone or "CHEST", x=tonumber(def.defaultX) or 0, y=tonumber(def.defaultY) or 0,
      z=tonumber(def.defaultZ) or 0, scale=tonumber(def.defaultScale) or 0.16,
      rx=tonumber(def.defaultRX) or 0, ry=tonumber(def.defaultRY) or 0, rz=tonumber(def.defaultRZ) or 0,
    }
    for k,v in pairs(values) do persistAccessoryField(characterId,accessoryId,k,v) end
  end

  local function resetAccessoryTextureFixes(characterId,accessoryId)
    local def=ACCESSORY_DEFS[accessoryId]
    local st=accessoryState(characterId,accessoryId)
    if not def or not st then return end
    local values={
      textureIndex=tonumber(def.defaultTextureIndex) or 1,
      uvVariant=1,
      autoMaterialTextures=def.defaultAutoMaterialTextures==true,
      flipU=false, flipV=false, swapUV=false, repeatTexture=false, nearestFilter=false,
    }
    for k,v in pairs(values) do persistAccessoryField(characterId,accessoryId,k,v) end
  end

  wireAccessoryRenderer=function(child)
    if not child then return end
    child.red3dDrawAccessories=function(r,Voxel3D,bodyModel,ShadowMap,preview)
      if not AccessoryImporter then return false end
      local any=false
      for _,accessoryId in ipairs(ACCESSORY_ORDER) do
        local def=ACCESSORY_DEFS[accessoryId]
        local st=def and accessoryState(r.characterId,accessoryId) or nil
        if st and st.enabled then
          local ok,drew=pcall(AccessoryImporter.draw,def,r,st,Voxel3D,bodyModel,ShadowMap)
          if ok and drew then any=true end
        end
      end
      return any
    end
  end

  local function scanAccessoryPackages()
    if not AccessoryImporter then return 0,1,"Accessory importer module is unavailable." end
    local old=ACCESSORY_DEFS
    local defs,failed,errors,folder=AccessoryImporter.scan(ACCESSORY_ROOT,mod.log)
    ACCESSORY_DEFS={}; ACCESSORY_ORDER={}
    for _,def in ipairs(defs or {}) do
      if def and def.id then
        -- Reuse already-created GPU resources when rescanning an unchanged ZIP.
        local prior=old and old[def.id]
        if prior and prior.runtimeParts and prior.corners and def.corners
            and #prior.corners==#def.corners and prior.materialCount==def.materialCount then
          -- Geometry allocation can be reused when the material split and
          -- vertex count still match, but images are intentionally rebuilt so
          -- rescanning the same ZIP can pick up replaced textures.
          def.runtimeParts=prior.runtimeParts
          def.runtimeMesh=prior.runtimeMesh; def.runtimeRows=prior.runtimeRows
          def.runtimeFormat=prior.runtimeFormat
        end
        ACCESSORY_DEFS[def.id]=def
        ACCESSORY_ORDER[#ACCESSORY_ORDER+1]=def.id
      end
    end
    table.sort(ACCESSORY_ORDER,function(a,b)
      local da,db=ACCESSORY_DEFS[a],ACCESSORY_DEFS[b]
      return tostring(da and da.label or a):lower()<tostring(db and db.label or b):lower()
    end)
    for _,child in pairs(renderers) do wireAccessoryRenderer(child) end
    local message
    if #ACCESSORY_ORDER>0 then
      message=string.format("Loaded %d accessory model%s from ZIPs. Folder: %s",#ACCESSORY_ORDER,(#ACCESSORY_ORDER==1) and "" or "s",tostring(folder))
    elseif (failed or 0)>0 then
      message="No accessories loaded; "..tostring(failed).." model/package error(s). Folder: "..tostring(folder)
      if errors and errors[1] then message=message.." First: "..tostring(errors[1]) end
    else
      message="No accessory ZIPs found. Put OBJ/FBX/DAE ZIPs in: "..tostring(folder)
    end
    return #ACCESSORY_ORDER,failed or 0,message,folder
  end

  local function scanCharacterPackages()
    if not AccessoryImporter then return 0,1,"Character model importer module is unavailable." end
    local old=CHARACTER_SOURCE_DEFS
    local defs,failed,errors,folder=AccessoryImporter.scan(CHARACTER_IMPORT_ROOT,mod.log)
    CHARACTER_SOURCE_DEFS={}; CHARACTER_SOURCE_ORDER={}
    for _,def in ipairs(defs or {}) do
      if def and def.id then
        local prior=old and old[def.id]
        if prior and prior.runtimeParts and prior.corners and def.corners
            and #prior.corners==#def.corners and prior.materialCount==def.materialCount then
          def.runtimeParts=prior.runtimeParts
          def.runtimeMesh=prior.runtimeMesh; def.runtimeRows=prior.runtimeRows
          def.runtimeFormat=prior.runtimeFormat
        end
        CHARACTER_SOURCE_DEFS[def.id]=def
        CHARACTER_SOURCE_ORDER[#CHARACTER_SOURCE_ORDER+1]=def.id
      end
    end
    table.sort(CHARACTER_SOURCE_ORDER,function(a,b)
      local da,db=CHARACTER_SOURCE_DEFS[a],CHARACTER_SOURCE_DEFS[b]
      return tostring(da and da.label or a):lower()<tostring(db and db.label or b):lower()
    end)
    local message
    if #CHARACTER_SOURCE_ORDER>0 then
      message=string.format("Loaded %d character source model%s. Choose a donor rig, then CLONE RIG + IMPORT. Folder: %s",
        #CHARACTER_SOURCE_ORDER,(#CHARACTER_SOURCE_ORDER==1) and "" or "s",tostring(folder))
    elseif (failed or 0)>0 then
      message="No character models loaded; "..tostring(failed).." model/package error(s). Folder: "..tostring(folder)
      if errors and errors[1] then message=message.." First: "..tostring(errors[1]) end
    else
      message="No character models found. Put OBJ/FBX/DAE files or ZIPs in: "..tostring(folder)
    end
    return #CHARACTER_SOURCE_ORDER,failed or 0,message,folder
  end

  -- Scan at startup so accessories and saved rigged characters are present in
  -- gameplay without opening the selector first. Character sources use their
  -- own import folder and are first-class selector content rather than
  -- accessory entries.
  scanAccessoryPackages()
  scanCharacterPackages()
  local restoredRigCount=restoreRiggedCharacters()
  if restoredRigCount>0 then mod.log:info("restored %d saved experimental rigged character(s)",restoredRigCount) end

  local function adjustCharacterScale(id,delta,viewer)
    local child=renderers[id]
    if not child then return nil end
    local value=applyCharacterScale(id,(child.userScale or 1.0)+(tonumber(delta) or 0),true)
    if viewer then
      if type(viewer.invalidate)=="function" then viewer:invalidate()
      else viewer.lastRenderClock=nil end
    end
    return value
  end

  local function toggleBellePhysics(kind,viewer,id)
    id=id or "BELLESTARMON"
    local enabled=not currentBellePhysicsEnabled(kind,id)
    applyBellePhysicsEnabled(kind,enabled,true,id)
    if viewer then
      if type(viewer.invalidate)=="function" then viewer:invalidate()
      else viewer.lastRenderClock=nil end
    end
    return enabled
  end

  local function adjustBellePhysics(kind,delta,viewer,id)
    local current=savedBellePhysics(kind,id)
    local value=applyBellePhysics(kind,current+(tonumber(delta) or 0),true,id)
    if viewer then
      if type(viewer.invalidate)=="function" then viewer:invalidate()
      else viewer.lastRenderClock=nil end
    end
    return value
  end

  local function adjustBellePhysicsStyle(direction,viewer)
    local current=savedBellePhysicsStyle()
    local index=2
    for i,key in ipairs(BELLE_PHYSICS_STYLE_ORDER) do
      if key==current then index=i break end
    end
    local step=(tonumber(direction) or 0)<0 and -1 or 1
    index=((index-1+step)%#BELLE_PHYSICS_STYLE_ORDER)+1
    local value=applyBellePhysicsStyle(BELLE_PHYSICS_STYLE_ORDER[index],true)
    if viewer then
      if type(viewer.invalidate)=="function" then viewer:invalidate()
      else viewer.lastRenderClock=nil end
    end
    return value
  end

  local function adjustBellePhysicsAxes(direction,viewer)
    local current=savedBellePhysicsAxes()
    local index=1
    for i,key in ipairs(BELLE_PHYSICS_AXIS_ORDER) do
      if key==current then index=i break end
    end
    local step=(tonumber(direction) or 0)<0 and -1 or 1
    index=((index-1+step)%#BELLE_PHYSICS_AXIS_ORDER)+1
    local value=applyBellePhysicsAxes(BELLE_PHYSICS_AXIS_ORDER[index],true)
    if viewer then
      if type(viewer.invalidate)=="function" then viewer:invalidate()
      else viewer.lastRenderClock=nil end
    end
    return value
  end

  local function adjustBellePhysicsHz(direction,viewer)
    local current=savedBellePhysicsHz()
    local index=3
    for i,hz in ipairs(BELLE_PHYSICS_HZ_ORDER) do
      if hz==current then index=i break end
    end
    local step=(tonumber(direction) or 0)<0 and -1 or 1
    index=((index-1+step)%#BELLE_PHYSICS_HZ_ORDER)+1
    local value=applyBellePhysicsHz(BELLE_PHYSICS_HZ_ORDER[index],true)
    if viewer then
      if type(viewer.invalidate)=="function" then viewer:invalidate()
      else viewer.lastRenderClock=nil end
    end
    return value
  end

  local function adjustBelleAdvanced(kind,delta,viewer)
    local current=savedBelleAdvanced(kind)
    local value=applyBelleAdvanced(kind,current+(tonumber(delta) or 0),true)
    if viewer then
      if type(viewer.invalidate)=="function" then viewer:invalidate()
      else viewer.lastRenderClock=nil end
    end
    return value
  end

  local SELECTOR_NAMES={
    AANG="Aang", ASH="Ash Ketchum", BELLESTARMON="BelleStarmon", CLOUD="Cloud",
    NARUTO="Naruto", RED="Red", ZORO="Roronoa Zoro", SHREK="Shrek", TITAN="OceanGate Titan", WOW="Wow",
    UGANDAN_KNUCKLES="Ugandan Knuckles", SABRINA="Sabrina", YAMI="Yami", YUGI="Yugi Muto",
  }

  -- v3.0.31: display names are separate from stable character IDs. Renaming a
  -- character never changes its renderer/save/accessory/rig identifiers, so a
  -- custom name cannot break animations, physics, attachments, or selection.
  local function characterNameKey(id)
    return "character_name_v3031_"..string.lower(skinSafeId(id or "RED"))
  end

  local function sanitizeCharacterDisplayName(value,fallback)
    local s=tostring(value or ""):gsub("[%c]"," "):gsub("^%s+",""):gsub("%s+$","")
    s=s:gsub("%s+"," ")
    if #s>32 then s=s:sub(1,32) end
    if s=="" then s=tostring(fallback or "Character") end
    return s
  end

  local function characterDefaultDisplayName(id)
    local def=CHARACTER_DEFS[id]
    return SELECTOR_NAMES[id] or (def and def.label) or tostring(id or "Character")
  end

  local function characterDisplayName(id)
    local fallback=characterDefaultDisplayName(id)
    local saved=nil
    if mod.save and mod.save.get then saved=mod.save:get(characterNameKey(id)) end
    if saved==nil or tostring(saved)=="" then return fallback end
    return sanitizeCharacterDisplayName(saved,fallback)
  end

  local function setCharacterDisplayName(id,value,persist)
    if not id or not CHARACTER_DEFS[id] then return nil end
    local name=sanitizeCharacterDisplayName(value,characterDefaultDisplayName(id))
    if persist~=false and mod.save and mod.save.set then mod.save:set(characterNameKey(id),name) end
    return name
  end

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
  local selectorCursors={}
  local setSelectorCursor

  -- v3.0.35 mobile build: keep the desktop selector intact on PC, but switch
  -- to larger touch targets and direct touch camera gestures on Android/iOS.
  -- Store helpers on the existing theme table so this already-large init
  -- function does not consume additional Lua local-variable slots.
  SELECTOR_THEME.hostIsPhone=function()
    if love and love.system and love.system.getOS then
      local ok,name=pcall(love.system.getOS)
      if ok and name then
        name=tostring(name)
        return name=="Android" or name=="iOS"
      end
    end
    return false
  end
  SELECTOR_THEME.mobileMode=function(menu)
    -- v3.0.42: desktop stays desktop even if a backend emits a touch-like event.
    -- Android/iOS continue to use the dedicated mobile layout.
    return SELECTOR_THEME.hostIsPhone()
  end
  SELECTOR_THEME.touchId=function(event)
    if type(event)~="table" then return "touch-primary" end
    local id=event.id
    if id==nil then id=event.pointerId end
    if id==nil then id=event.touchId end
    if id==nil then id=event.fingerId end
    if id==nil then id=event.button end
    if id==nil then id="primary" end
    return "touch-"..tostring(id)
  end

  -- Desktop focus/capture safety.  The selector owns a software cursor while the
  -- game window is focused, but it must never strand Windows in a hidden,
  -- grabbed, or relative mouse state when the player Alt-Tabs to another
  -- monitor.  Keep all LÖVE mouse calls soft-failing for older/mobile hosts.
  local function selectorWindowHasFocus()
    if love and love.window and love.window.hasFocus then
      local ok,focused=pcall(love.window.hasFocus)
      if ok then return focused==true end
    end
    return true
  end

  local function selectorReleaseMouseCapture()
    if not (love and love.mouse) then return end
    if love.mouse.setRelativeMode then pcall(love.mouse.setRelativeMode,false) end
    if love.mouse.setGrabbed then pcall(love.mouse.setGrabbed,false) end
  end

  local function selectorSetNativeCursorVisible(visible)
    if love and love.mouse and love.mouse.setVisible then
      pcall(love.mouse.setVisible,visible==true)
    end
  end

  local function selectorCancelMouseInteraction(menu)
    if not menu then return end
    menu._red3dControlDragging=nil
    menu._red3dRigJointDragging=nil
    menu._red3dModelDragging=false
    menu._red3dModelDragMode=nil
    menu._red3dModelDragButton=nil
    menu._red3dModelDragLastX=nil
    menu._red3dModelDragLastY=nil
    menu._red3dPolledMouseDown=false
    menu._red3dPollX=nil
    menu._red3dPollY=nil
    menu._red3dTouches={}
    menu._red3dTouchPinch=nil
    if menu._red3dViewer and type(menu._red3dViewer.setDragging)=="function" then
      menu._red3dViewer:setDragging(false)
    end
  end

  local function selectorApplyFocusMouseState(menu,focused)
    selectorCancelMouseInteraction(menu)
    selectorReleaseMouseCapture()
    setSelectorCursor("arrow")
    if focused then
      -- Inside the selector the mod-drawn pointer is the reliable visual cursor,
      -- so hide the native one only while this window actually owns focus.
      selectorSetNativeCursorVisible(false)
      if love and love.mouse and love.mouse.getPosition then
        local ok,mx,my=pcall(love.mouse.getPosition)
        if ok and mx and my and menu then
          menu._red3dMouseX,menu._red3dMouseY=mx,my
          menu._red3dPollX,menu._red3dPollY=mx,my
        end
      end
      if menu then
        -- Discard any synthetic A/B edge generated by the focus transition.
        menu._red3dSuppressNativeMenuFrames=math.max(
          tonumber(menu._red3dSuppressNativeMenuFrames) or 0,3)
      end
    else
      -- Critical Alt-Tab path: the OS cursor must be visible and completely
      -- uncaptured while another window/monitor owns focus.
      selectorSetNativeCursorVisible(true)
    end
  end

  setSelectorCursor=function(kind)
    if not (love and love.mouse) then return end
    -- Gen1Recomp may capture/hide the native OS cursor even when LÖVE reports
    -- it as visible. v3.0.5 therefore draws its own cursor in render.hud.
    if not (love.mouse.getSystemCursor and love.mouse.setCursor) then return end
    kind=kind or "arrow"
    if not selectorCursors[kind] then
      local ok,cursor=pcall(love.mouse.getSystemCursor,kind)
      if ok then selectorCursors[kind]=cursor end
    end
    if selectorCursors[kind] then pcall(love.mouse.setCursor,selectorCursors[kind]) end
  end
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

  local function rectContains(r,x,y)
    return r and x and y and x>=r.x and y>=r.y and x<=r.x+r.w and y<=r.y+r.h
  end

  local ACCESSORY_ACTION_FIELD={
    accessoryX="x",accessoryY="y",accessoryZ="z",accessoryScale="scale",
    accessoryRX="rx",accessoryRY="ry",accessoryRZ="rz",
  }

  local function prettyAccessoryBone(bone)
    return tostring(bone or "CHEST"):gsub("_"," ")
  end

  local function selectedAccessoryId(menu)
    if #ACCESSORY_ORDER==0 then return nil end
    local idx=math.floor(tonumber(menu and menu._red3dAccessoryIndex) or 1)
    if idx<1 then idx=1 elseif idx>#ACCESSORY_ORDER then idx=#ACCESSORY_ORDER end
    if menu then menu._red3dAccessoryIndex=idx end
    return ACCESSORY_ORDER[idx],idx
  end

  local function selectedCharacterSourceId(menu)
    if #CHARACTER_SOURCE_ORDER==0 then return nil end
    local idx=math.floor(tonumber(menu and menu._red3dCharacterSourceIndex) or 1)
    if idx<1 then idx=1 elseif idx>#CHARACTER_SOURCE_ORDER then idx=#CHARACTER_SOURCE_ORDER end
    if menu then menu._red3dCharacterSourceIndex=idx end
    return CHARACTER_SOURCE_ORDER[idx],idx
  end

  local function selectedRigSourceId(menu)
    local explicit=menu and menu._red3dRigSourceId or nil
    if explicit and rigSourceDef(explicit) then return explicit end
    if menu and menu._red3dCharacterImporter then
      return selectedCharacterSourceId(menu)
    end
    return selectedAccessoryId(menu)
  end

  local function accessoryControlDisplay(value,kind)
    value=tonumber(value) or 0
    if kind=="rotation" then return string.format("%+d°",math.floor(value+((value>=0) and 0.5 or -0.5))) end
    return string.format("%+d%%",math.floor(value*100+((value>=0) and 0.5 or -0.5)))
  end

  local function accessoryTextureLabel(def,st)
    local options=def and def.textureOptions or nil
    if type(options)~="table" or #options==0 then return "NONE / WHITE" end
    local index=math.floor(tonumber(st and st.textureIndex) or tonumber(def.defaultTextureIndex) or 1)
    if index<1 then index=1 elseif index>#options then index=#options end
    local label=tostring(options[index] and options[index].label or ("TEXTURE "..index))
    if #label>28 then label=label:sub(1,25).."..." end
    return string.format("%d/%d  %s",index,#options,label)
  end

  local function accessoryUVLabel(def,st)
    local variants=def and def.uvVariants or nil
    if type(variants)~="table" or #variants==0 then return "MODEL DEFAULT" end
    local index=math.floor(tonumber(st and st.uvVariant) or 1)
    if index<1 then index=1 elseif index>#variants then index=#variants end
    local label=tostring(variants[index] and variants[index].label or ("UV "..index))
    if #label>30 then label=label:sub(1,27).."..." end
    return label
  end

  local function currentRigJoint(menu)
    local order=HumanoidRigger and HumanoidRigger.JOINT_ORDER or {}
    if #order==0 then return nil,1 end
    local index=math.floor(tonumber(menu and menu._red3dRigJointIndex) or 1)
    if index<1 then index=1 elseif index>#order then index=#order end
    if menu then menu._red3dRigJointIndex=index end
    return order[index],index
  end

  local function rebuildRigPreview(menu,accessoryId)
    if not (menu and accessoryId) then return nil end
    local def,err
    if menu._red3dCharacterImporter and DonorRigCloner then def,err=buildDonorCharacterDef(accessoryId)
    elseif HumanoidRigger then def,err=buildRigCharacterDef(accessoryId)
    else err="rigger unavailable" end
    if not def then menu._red3dSkinFileStatus="Rig preview failed: "..tostring(err); return nil end
    local ok,child=pcall(Renderer.new,mod,def._runtimeData,def)
    if not ok or not child then
      menu._red3dSkinFileStatus="Rig preview renderer failed: "..tostring(child)
      return nil
    end
    child.userScale=1.0; child.scale=child.baseScale
    menu._red3dRigPreviewRenderer=child
    menu._red3dRigPreviewDirty=false
    if def._donorClone then
      local stats=def._donorStats
      menu._red3dSkinFileStatus=stats and string.format("Donor preview: %s rig • mean surface match %.4f",donorRigLabel(def._donorId),tonumber(stats.meanNearest) or 0)
        or ("Donor preview: "..donorRigLabel(def._donorId).." rig")
    else
      menu._red3dSkinFileStatus="Rig preview updated. Adjust joints, then UPDATE PREVIEW / AUTO WEIGHT again."
    end
    return child
  end

  local function selectorControlsFor(item,child,menu)
    local id=item and item.characterId or (child and child.characterId)
    if menu and menu._red3dRigEditor then
      local controls={
        {label="DONE",action="rigDone",button=true,buttonText="BACK TO CHARACTER IMPORT"},
      }
      local sourceId=selectedRigSourceId(menu)
      local def=sourceId and rigSourceDef(sourceId) or nil
      local st=def and rigState(sourceId) or nil
      if not def or not st or not HumanoidRigger then
        controls[#controls+1]={label="RIGGER",action="rigNone",button=true,buttonText="RIGGER UNAVAILABLE"}
        return controls
      end
      local jointName=currentRigJoint(menu)
      local jp=jointName and st.joints[jointName] or {0,0,0}
      local b=st.bounds or HumanoidRigger.bounds(def)
      local span=math.max((b[4]-b[1]),(b[5]-b[2]),(b[6]-b[3]),0.1)
      controls[#controls+1]={label="AUTO SETUP",action="rigAuto",button=true,buttonText="RE-DETECT HUMANOID JOINTS"}
      controls[#controls+1]={label="MIRROR L / R",action="rigMirror",toggle=true,checked=st.mirror==true}
      controls[#controls+1]={label="JOINT",action="rigJoint",choice=HumanoidRigger.prettyJoint(jointName)}
      controls[#controls+1]={label="JOINT X",action="rigJointX",value=jp[1],min=b[1]-span*0.15,max=b[4]+span*0.15,step=0.01,display=string.format("%.2f",jp[1] or 0)}
      controls[#controls+1]={label="JOINT Y",action="rigJointY",value=jp[2],min=b[2]-span*0.15,max=b[5]+span*0.15,step=0.01,display=string.format("%.2f",jp[2] or 0)}
      controls[#controls+1]={label="JOINT Z",action="rigJointZ",value=jp[3],min=b[3]-span*0.25,max=b[6]+span*0.25,step=0.01,display=string.format("%.2f",jp[3] or 0)}
      controls[#controls+1]={label="WEIGHT STYLE",action="rigWeightStyle",choice=tostring(st.weightStyle or "BALANCED")}
      controls[#controls+1]={label="WEIGHT BLEND",action="rigSoftness",value=st.softness,min=0.02,max=0.16,step=0.01,display=string.format("%.2f",st.softness or 0.070)}
      controls[#controls+1]={label="ARM REST",action="rigArmRest",value=st.armRest,min=-120,max=30,step=5,display=string.format("%d°",math.floor((st.armRest or -90)+0.5))}
      controls[#controls+1]={label="CHAR HEIGHT",action="rigHeight",value=st.height,min=12,max=40,step=1,display=string.format("%d",math.floor((st.height or 24)+0.5))}
      controls[#controls+1]={label="VIEW",action="rigFrontView",button=true,buttonText="FRONT VIEW / RESET CAMERA"}
      controls[#controls+1]={label="AUTO WEIGHT",action="rigPreview",button=true,buttonText="UPDATE ANIMATED PREVIEW"}
      controls[#controls+1]={label="SAVE",action="rigSave",button=true,buttonText="SAVE TO CHARACTER SELECTOR"}
      return controls
    end
    if menu and menu._red3dCharacterImporter then
      local controls={
        {label="DONE",action="characterImportDone",button=true,buttonText="BACK TO CHARACTER"},
        {label="IMPORT",action="characterImportScan",button=true,buttonText="SCAN OBJ / FBX / ZIP FOLDER"},
      }
      local sourceId=selectedCharacterSourceId(menu)
      local def=sourceId and CHARACTER_SOURCE_DEFS[sourceId] or nil
      if not def then
        controls[#controls+1]={label="MODEL",action="characterImportNone",button=true,buttonText="NO OBJ / FBX / DAE MODELS FOUND"}
        return controls
      end
      local st=rigState(sourceId)
      controls[#controls+1]={label="MODEL",action="characterImportSelect",choice=tostring(def.label or "Imported Model")}
      controls[#controls+1]={label="FORMAT",action="characterImportNone",choice=tostring(def.format or "MODEL")}
      controls[#controls+1]={label="TEXTURE IMAGE",action="rigTexture",choice=accessoryTextureLabel(def,st)}
      if type(def.uvVariants)=="table" and #def.uvVariants>1 then
        controls[#controls+1]={label="UV MAPPING",action="rigUVVariant",choice=accessoryUVLabel(def,st)}
      end
      controls[#controls+1]={label="FLIP TEXTURE U",action="rigFlipU",toggle=true,checked=st and st.flipU==true}
      controls[#controls+1]={label="FLIP TEXTURE V",action="rigFlipV",toggle=true,checked=st and st.flipV==true}
      controls[#controls+1]={label="SWAP U / V",action="rigSwapUV",toggle=true,checked=st and st.swapUV==true}
      controls[#controls+1]={label="DONOR RIG",action="characterDonorRig",choice=donorRigLabel(st and st.donorId or "BELLESTARMON")}
      controls[#controls+1]={label="SWAP MODEL Y / Z",action="cloneSwapYZ",toggle=true,checked=st and st.meshSwapYZ==true}
      controls[#controls+1]={label="FLIP MODEL X",action="cloneFlipX",toggle=true,checked=st and st.meshFlipX==true}
      controls[#controls+1]={label="FLIP MODEL Y",action="cloneFlipY",toggle=true,checked=st and st.meshFlipY==true}
      controls[#controls+1]={label="FLIP MODEL Z",action="cloneFlipZ",toggle=true,checked=st and st.meshFlipZ==true}
      controls[#controls+1]={label="FIT SCALE",action="cloneFitScale",value=st and st.fitScale or 1.0,min=0.50,max=1.50,step=0.01,display=string.format("%.2f",st and st.fitScale or 1.0)}
      controls[#controls+1]={label="FIT X",action="cloneFitX",value=st and st.fitX or 0,min=-0.25,max=0.25,step=0.01,display=string.format("%+.2f",st and st.fitX or 0)}
      controls[#controls+1]={label="FIT Y",action="cloneFitY",value=st and st.fitY or 0,min=-0.25,max=0.25,step=0.01,display=string.format("%+.2f",st and st.fitY or 0)}
      controls[#controls+1]={label="FIT Z",action="cloneFitZ",value=st and st.fitZ or 0,min=-0.25,max=0.25,step=0.01,display=string.format("%+.2f",st and st.fitZ or 0)}
      controls[#controls+1]={label="CLONE RIG",action="characterCloneRig",button=true,buttonText="CLONE RIG + IMPORT"}
      controls[#controls+1]={label="ADVANCED",action="characterRigOpen",button=true,buttonText="MANUAL HUMANOID RIGGER"}
      return controls
    end
    if menu and menu._red3dAccessoryEditor then
      local controls={
        {label="DONE",action="accessoryDone",button=true,buttonText="BACK TO CHARACTER"},
        {label="IMPORT",action="accessoryScan",button=true,buttonText="SCAN ACCESSORY ZIP FOLDER"},
      }
      local accessoryId=selectedAccessoryId(menu)
      local def=accessoryId and ACCESSORY_DEFS[accessoryId] or nil
      if not def then
        controls[#controls+1]={label="ACCESSORY",action="accessoryNone",button=true,buttonText="NO ACCESSORY ZIPS FOUND"}
        return controls
      end
      local st=accessoryState(id,accessoryId)
      controls[#controls+1]={label="ACCESSORY",action="accessorySelect",choice=def.label}
      controls[#controls+1]={label="ENABLED",action="accessoryEnabled",toggle=true,checked=st and st.enabled==true}
      controls[#controls+1]={label="ATTACH TO",action="accessoryBone",choice=prettyAccessoryBone(st and st.bone)}
      controls[#controls+1]={label="TEXTURE IMAGE",action="accessoryTexture",choice=accessoryTextureLabel(def,st)}
      if (tonumber(def.materialCount) or 1)>1 then
        controls[#controls+1]={label="AUTO MATERIAL TEXTURES",action="accessoryAutoMaterials",toggle=true,checked=st and st.autoMaterialTextures==true}
      end
      if type(def.uvVariants)=="table" and #def.uvVariants>1 then
        controls[#controls+1]={label="UV MAPPING",action="accessoryUVVariant",choice=accessoryUVLabel(def,st)}
      end
      controls[#controls+1]={label="FLIP TEXTURE U",action="accessoryFlipU",toggle=true,checked=st and st.flipU==true}
      controls[#controls+1]={label="FLIP TEXTURE V",action="accessoryFlipV",toggle=true,checked=st and st.flipV==true}
      controls[#controls+1]={label="SWAP U / V",action="accessorySwapUV",toggle=true,checked=st and st.swapUV==true}
      controls[#controls+1]={label="REPEAT TEXTURE",action="accessoryRepeatTexture",toggle=true,checked=st and st.repeatTexture==true}
      controls[#controls+1]={label="PIXEL FILTER",action="accessoryNearestFilter",toggle=true,checked=st and st.nearestFilter==true}
      controls[#controls+1]={label="RESET TEXTURE",action="accessoryTextureReset",button=true,buttonText="RESET TEXTURE FIXES"}
      controls[#controls+1]={label="POSITION X",action="accessoryX",value=st.x,min=-0.50,max=0.50,step=0.01,display=accessoryControlDisplay(st.x,"percent")}
      controls[#controls+1]={label="POSITION Y",action="accessoryY",value=st.y,min=-0.50,max=0.50,step=0.01,display=accessoryControlDisplay(st.y,"percent")}
      controls[#controls+1]={label="POSITION Z",action="accessoryZ",value=st.z,min=-0.50,max=0.50,step=0.01,display=accessoryControlDisplay(st.z,"percent")}
      controls[#controls+1]={label="SCALE",action="accessoryScale",value=st.scale,min=0.02,max=0.60,step=0.01,display=string.format("%d%%",math.floor((st.scale or 0)*100+0.5))}
      controls[#controls+1]={label="ROTATE X",action="accessoryRX",value=st.rx,min=-180,max=180,step=5,display=accessoryControlDisplay(st.rx,"rotation")}
      controls[#controls+1]={label="ROTATE Y",action="accessoryRY",value=st.ry,min=-180,max=180,step=5,display=accessoryControlDisplay(st.ry,"rotation")}
      controls[#controls+1]={label="ROTATE Z",action="accessoryRZ",value=st.rz,min=-180,max=180,step=5,display=accessoryControlDisplay(st.rz,"rotation")}
      controls[#controls+1]={label="RESET",action="accessoryReset",button=true,buttonText="RESET PLACEMENT"}
      return controls
    end

    local controls={}
    local mobileNormal=SELECTOR_THEME.mobileMode(menu)
    local specialPhysics=child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW")
    local physicsEnabled=specialPhysics and currentBellePhysicsEnabled("breast",id) or false
    local buttEnabled=specialPhysics and currentBellePhysicsEnabled("buttocks",id) or false

    -- v3.0.36 phone reachability: Belle/Wow put PHYSICS first on mobile so it
    -- remains visible even on very small landscape/internal render targets where
    -- only one settings row can fit. When enabled, BREAST PHYSICS is the second
    -- row so the title-bar paging arrows can reach it immediately.
    if mobileNormal and specialPhysics then
      controls[#controls+1]={label="PHYSICS",action="breastToggle",toggle=true,checked=physicsEnabled}
      if physicsEnabled then
        local breastScale=savedBelleStrengthScale(id,"breast")
        controls[#controls+1]={label="BREAST PHYSICS",action="breastStrength",value=breastScale,min=0,max=1.5,step=0.05,display=string.format("%d%%",math.floor(breastScale*100+0.5))}
        controls[#controls+1]={label="INDEPENDENT BREASTS",action="breastIndependentToggle",toggle=true,checked=(not child.data or child.data.runtimeBelleBreastIndependent~=false)}
      end
      controls[#controls+1]={label="BUTTOCKS",action="buttToggle",toggle=true,checked=buttEnabled}
      if buttEnabled then
        local buttScale=savedBelleStrengthScale(id,"buttocks")
        controls[#controls+1]={label="BUTTOCKS PHYSICS",action="buttStrength",value=buttScale,min=0,max=1.5,step=0.05,display=string.format("%d%%",math.floor(buttScale*100+0.5))}
        controls[#controls+1]={label="INDEPENDENT BUTTOCKS",action="buttIndependentToggle",toggle=true,checked=(not child.data or child.data.runtimeBelleButtIndependent~=false)}
      end
      local thighEnabled=specialPhysics and currentBellePhysicsEnabled("thighs",id) or false
      controls[#controls+1]={label="THIGHS",action="thighToggle",toggle=true,checked=thighEnabled}
      if thighEnabled then
        local thighScale=savedBelleStrengthScale(id,"thighs")
        controls[#controls+1]={label="THIGH PHYSICS",action="thighStrength",value=thighScale,min=0,max=1.5,step=0.05,display=string.format("%d%%",math.floor(thighScale*100+0.5))}
        controls[#controls+1]={label="INDEPENDENT THIGHS",action="thighIndependentToggle",toggle=true,checked=(not child.data or child.data.runtimeBelleThighIndependent~=false)}
      end
      local hairEnabled=specialPhysics and currentBellePhysicsEnabled("hair",id) or false
      controls[#controls+1]={label="HAIR",action="hairToggle",toggle=true,checked=hairEnabled}
      if hairEnabled then
        local hairScale=savedBelleStrengthScale(id,"hair")
        controls[#controls+1]={label="HAIR PHYSICS",action="hairStrength",value=hairScale,min=0,max=1.5,step=0.05,display=string.format("%d%%",math.floor(hairScale*100+0.5))}
      end
    end

    controls[#controls+1]={label="SIZE",action="size",value=(child and child.userScale) or 1.0,min=0.50,max=1.50,step=0.05}
    -- v3.1.4 FACE FLIP: turn a character 180 degrees in the ordinary
    -- (non-voxel) render path.  Source rigs disagree about which way is
    -- forward -- a Z-up export lands facing -Z after the postSkinZUp axis
    -- swap, and modelYawOffset cannot be reused here because this path
    -- rotates the opposite way to the voxel one.  Rather than guess per
    -- character, this is one saved switch per character.
    controls[#controls+1]={label="FACE FLIP",action="faceFlip",toggle=true,checked=(child and child.faceFlipYaw or 0)~=0}
    -- v3.1.9: BelleStarmon intentionally has no selector-pose control.
    -- Wow retains its authored three-pose selector option.
    if child and child.behaviorId=="WOW" and child.data and child.data.selectorPoseCount then
      local runtimeField="runtimeWowSelectorPose"
      local saveKey=(id=="WOW") and "wow_selector_pose_v3056" or ("clone_selector_pose_"..skinSafeId(id):sub(1,48).."_v3060")
      local pose=tonumber(child.data[runtimeField])
      if not pose and mod.save and mod.save.get then pose=tonumber(mod.save:get(saveKey)) end
      pose=math.floor(pose or 1)
      if pose<1 then pose=1 elseif pose>3 then pose=3 end
      child.data[runtimeField]=pose
      controls[#controls+1]={label="SELECTOR POSE",action="selectorPose",choice=string.format("POSE %d / 3",pose)}
    end
    local renameEditing=menu and menu._red3dRenameEditingId==id
    local renameText=renameEditing and tostring(menu._red3dRenameBuffer or characterDisplayName(id)) or characterDisplayName(id)
    controls[#controls+1]={label=renameEditing and "NAME • TYPE" or "NAME",action="renameCharacter",button=true,
      buttonText=renameEditing and (renameText.."_") or ("RENAME: "..renameText)}

    if (not mobileNormal) and specialPhysics then
      controls[#controls+1]={label="PHYSICS",action="breastToggle",toggle=true,checked=physicsEnabled}
      if physicsEnabled then
        local breastScale=savedBelleStrengthScale(id,"breast")
        controls[#controls+1]={label="BREAST PHYSICS",action="breastStrength",value=breastScale,min=0,max=1.5,step=0.05,display=string.format("%d%%",math.floor(breastScale*100+0.5))}
        controls[#controls+1]={label="INDEPENDENT BREASTS",action="breastIndependentToggle",toggle=true,checked=(not child.data or child.data.runtimeBelleBreastIndependent~=false)}
      end
      controls[#controls+1]={label="BUTTOCKS",action="buttToggle",toggle=true,checked=buttEnabled}
      if buttEnabled then
        local buttScale=savedBelleStrengthScale(id,"buttocks")
        controls[#controls+1]={label="BUTTOCKS PHYSICS",action="buttStrength",value=buttScale,min=0,max=1.5,step=0.05,display=string.format("%d%%",math.floor(buttScale*100+0.5))}
        controls[#controls+1]={label="INDEPENDENT BUTTOCKS",action="buttIndependentToggle",toggle=true,checked=(not child.data or child.data.runtimeBelleButtIndependent~=false)}
      end
      local thighEnabled=specialPhysics and currentBellePhysicsEnabled("thighs",id) or false
      controls[#controls+1]={label="THIGHS",action="thighToggle",toggle=true,checked=thighEnabled}
      if thighEnabled then
        local thighScale=savedBelleStrengthScale(id,"thighs")
        controls[#controls+1]={label="THIGH PHYSICS",action="thighStrength",value=thighScale,min=0,max=1.5,step=0.05,display=string.format("%d%%",math.floor(thighScale*100+0.5))}
        controls[#controls+1]={label="INDEPENDENT THIGHS",action="thighIndependentToggle",toggle=true,checked=(not child.data or child.data.runtimeBelleThighIndependent~=false)}
      end
      local hairEnabled=specialPhysics and currentBellePhysicsEnabled("hair",id) or false
      controls[#controls+1]={label="HAIR",action="hairToggle",toggle=true,checked=hairEnabled}
      if hairEnabled then
        local hairScale=savedBelleStrengthScale(id,"hair")
        controls[#controls+1]={label="HAIR PHYSICS",action="hairStrength",value=hairScale,min=0,max=1.5,step=0.05,display=string.format("%d%%",math.floor(hairScale*100+0.5))}
      end
    end
    local attached=0
    if id then
      for _,aid in ipairs(ACCESSORY_ORDER) do
        local st=accessoryState(id,aid)
        if st and st.enabled then attached=attached+1 end
      end
    end
    controls[#controls+1]={label="IMPORT CHARACTER",action="characterImportOpen",button=true,
      buttonText=(#CHARACTER_SOURCE_ORDER==0) and "IMPORT / RIG 3D CHARACTER" or string.format("RIG / IMPORT CHARACTER (%d MODEL%s)",#CHARACTER_SOURCE_ORDER,(#CHARACTER_SOURCE_ORDER==1) and "" or "S")}
    controls[#controls+1]={label="ACCESSORIES",action="accessoryOpen",button=true,
      buttonText=(#ACCESSORY_ORDER==0) and "IMPORT / ATTACH ACCESSORIES" or string.format("EDIT ACCESSORIES (%d ON)",attached)}
    return controls
  end

  local function invalidateSelectorViewer(viewer)
    if viewer then
      if type(viewer.invalidate)=="function" then viewer:invalidate() else viewer.lastRenderClock=nil end
    end
  end

  local function setRigJointCoord(accessoryId,jointName,axis,value)
    local st=rigState(accessoryId)
    if not st or not jointName or not st.joints[jointName] then return end
    axis=math.max(1,math.min(3,math.floor(tonumber(axis) or 1)))
    st.joints[jointName][axis]=value
    if st.mirror and HumanoidRigger and HumanoidRigger.MIRROR then
      local other=HumanoidRigger.MIRROR[jointName]
      if other and st.joints[other] then
        if axis==1 then
          local center=(st.joints.HIPS and st.joints.HIPS[1]) or 0
          st.joints[other][1]=center-(value-center)
        else
          st.joints[other][axis]=value
        end
      end
    end
    persistRigJoints(accessoryId)
  end

  local function copyAccessoryTextureToRig(characterId,accessoryId)
    local ast=accessoryState(characterId,accessoryId)
    local rst=rigState(accessoryId)
    if not ast or not rst then return end
    rst.textureIndex=ast.textureIndex or rst.textureIndex
    rst.uvVariant=ast.uvVariant or rst.uvVariant
    rst.flipU=ast.flipU==true; rst.flipV=ast.flipV==true; rst.swapUV=ast.swapUV==true
    persistRigField(accessoryId,"textureIndex",rst.textureIndex)
    persistRigField(accessoryId,"uvVariant",rst.uvVariant)
    persistRigField(accessoryId,"flipU",rst.flipU)
    persistRigField(accessoryId,"flipV",rst.flipV)
    persistRigField(accessoryId,"swapUV",rst.swapUV)
  end

  local function beginCharacterRename(id,menu)
    if not (menu and id and CHARACTER_DEFS[id]) then return end
    menu._red3dRenameEditingId=id
    menu._red3dRenameBuffer=characterDisplayName(id)
    menu._red3dRenameKeyDown={}
    if SELECTOR_THEME.mobileMode(menu) and love and love.keyboard and love.keyboard.setTextInput then
      pcall(love.keyboard.setTextInput,true)
    end
    menu._red3dSkinFileStatus="Rename: type a name • ENTER saves • BACKSPACE deletes • ESC cancels"
  end

  local function cancelCharacterRename(menu)
    if not menu then return end
    menu._red3dRenameEditingId=nil
    menu._red3dRenameBuffer=nil
    menu._red3dRenameKeyDown=nil
    if love and love.keyboard and love.keyboard.setTextInput then pcall(love.keyboard.setTextInput,false) end
    menu._red3dSkinFileStatus=nil
  end

  local function commitCharacterRename(menu)
    if not (menu and menu._red3dRenameEditingId) then return end
    local id=menu._red3dRenameEditingId
    local name=setCharacterDisplayName(id,menu._red3dRenameBuffer,true)
    menu._red3dRenameEditingId=nil
    menu._red3dRenameBuffer=nil
    menu._red3dRenameKeyDown=nil
    if love and love.keyboard and love.keyboard.setTextInput then pcall(love.keyboard.setTextInput,false) end
    menu._red3dSkinFileStatus="Character renamed to: "..tostring(name or characterDisplayName(id))
    if type(menu._red3dRebuildSkinItems)=="function" then menu:_red3dRebuildSkinItems(id) end
  end

  local RENAME_KEYS={
    {"a","a"},{"b","b"},{"c","c"},{"d","d"},{"e","e"},{"f","f"},{"g","g"},{"h","h"},{"i","i"},{"j","j"},{"k","k"},{"l","l"},{"m","m"},
    {"n","n"},{"o","o"},{"p","p"},{"q","q"},{"r","r"},{"s","s"},{"t","t"},{"u","u"},{"v","v"},{"w","w"},{"x","x"},{"y","y"},{"z","z"},
    {"0","0"},{"1","1"},{"2","2"},{"3","3"},{"4","4"},{"5","5"},{"6","6"},{"7","7"},{"8","8"},{"9","9"},
    {"space"," "},{"-","-"},{"'","'"},
  }

  local function processCharacterRenameInput(menu)
    if not (menu and menu._red3dRenameEditingId and love and love.keyboard and love.keyboard.isDown) then return false end
    local prev=menu._red3dRenameKeyDown or {}
    local now={}
    local function down(key)
      local ok,v=pcall(love.keyboard.isDown,key)
      now[key]=ok and v==true
      return now[key]
    end
    local shift=down("lshift") or down("rshift")
    if (down("return") or down("kpenter")) and not (prev["return"] or prev["kpenter"]) then
      menu._red3dRenameKeyDown=now
      commitCharacterRename(menu)
      return true
    end
    if down("escape") and not prev["escape"] then
      menu._red3dRenameKeyDown=now
      cancelCharacterRename(menu)
      return true
    end
    local buffer=tostring(menu._red3dRenameBuffer or "")
    if down("backspace") and not prev["backspace"] then
      buffer=buffer:sub(1,math.max(0,#buffer-1))
    end
    for _,pair in ipairs(RENAME_KEYS) do
      local key,ch=pair[1],pair[2]
      if down(key) and not prev[key] and #buffer<32 then
        if shift and ch:match("%a") then ch=ch:upper() end
        buffer=buffer..ch
      end
    end
    menu._red3dRenameBuffer=buffer
    menu._red3dRenameKeyDown=now
    return true
  end

  local function adjustSelectorControl(id,index,sign,viewer,menu)
    sign=(tonumber(sign) or 0)<0 and -1 or 1
    if not id then return end
    local child=renderers[id]
    local controls=selectorControlsFor({characterId=id},child,menu)
    local control=controls[index]
    if not control then return end
    local action=control.action

    if action=="size" then
      adjustCharacterScale(id,(control.step or 0.05)*sign,viewer)
      return
    elseif action=="faceFlip" and child then
      child:setFaceFlip(not ((child.faceFlipYaw or 0)~=0))
      if mod.save and mod.save.set then
        mod.save:set("face_flip_"..string.lower(tostring(id)),
                     ((child.faceFlipYaw or 0)~=0) and 1 or 0)
      end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="selectorPose" and child and child.behaviorId=="WOW" then
      local runtimeField="runtimeWowSelectorPose"
      local saveKey=(id=="WOW") and "wow_selector_pose_v3056" or ("clone_selector_pose_"..skinSafeId(id):sub(1,48).."_v3060")
      local pose=math.floor(tonumber(child.data[runtimeField]) or 1)
      pose=((pose-1+sign)%3)+1
      child.data[runtimeField]=pose
      if mod.save and mod.save.set then mod.save:set(saveKey,pose) end
      child.skinKey=nil; child.voxelUploadedKey=nil; child.voxelFrameKey=nil
      invalidateSelectorViewer(viewer)
      return
    elseif action=="renameCharacter" then
      if menu and menu._red3dRenameEditingId==id then commitCharacterRename(menu) else beginCharacterRename(id,menu) end
      return
    elseif action=="breastToggle" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      local enabled=toggleBellePhysics("breast",viewer,id)
      if menu and SELECTOR_THEME.mobileMode(menu) then
        -- On phone, jump straight to the newly revealed strength row. Turning
        -- physics back off returns focus to the always-visible PHYSICS row.
        menu._red3dControlIndex=enabled and 2 or 1
        menu._red3dSettingsFirstControl=enabled and 1 or 1
      end
      return
    elseif action=="breastStrength" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      adjustBellePhysics("breast",(control.step or 0.05)*sign,viewer,id)
      return
    elseif action=="buttToggle" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      local enabled=toggleBellePhysics("buttocks",viewer,id)
      if menu and SELECTOR_THEME.mobileMode(menu) then
        local controlsNow=selectorControlsFor({characterId=id},child,menu)
        local target=1
        for idx,c in ipairs(controlsNow) do if c.action==(enabled and "buttStrength" or "buttToggle") then target=idx break end end
        menu._red3dControlIndex=target; menu._red3dSettingsFirstControl=1
      end
      return
    elseif action=="buttStrength" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      adjustBellePhysics("buttocks",(control.step or 0.05)*sign,viewer,id)
      return
    elseif action=="thighToggle" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      local enabled=toggleBellePhysics("thighs",viewer,id)
      if menu and SELECTOR_THEME.mobileMode(menu) then
        local controlsNow=selectorControlsFor({characterId=id},child,menu)
        local target=1
        for idx,c in ipairs(controlsNow) do if c.action==(enabled and "thighStrength" or "thighToggle") then target=idx break end end
        menu._red3dControlIndex=target; menu._red3dSettingsFirstControl=1
      end
      return
    elseif action=="thighStrength" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      adjustBellePhysics("thighs",(control.step or 0.05)*sign,viewer,id)
      return
    elseif action=="hairToggle" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      local enabled=toggleBellePhysics("hair",viewer,id)
      if menu and SELECTOR_THEME.mobileMode(menu) then
        local controlsNow=selectorControlsFor({characterId=id},child,menu)
        local target=1
        for idx,c in ipairs(controlsNow) do if c.action==(enabled and "hairStrength" or "hairToggle") then target=idx break end end
        menu._red3dControlIndex=target; menu._red3dSettingsFirstControl=1
      end
      return
    elseif action=="hairStrength" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      adjustBellePhysics("hair",(control.step or 0.05)*sign,viewer,id)
      return
    elseif action=="breastAreaToggle" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      if menu._red3dBreastAreaEditorId==id then
        menu._red3dBreastAreaEditorId=nil
        menu._red3dBreastAreaDragging=nil
        menu._red3dBreastAreaActiveSide=nil
      else
        menu._red3dBreastAreaEditorId=id
        menu._red3dBreastAreaDragging=nil
        menu._red3dBreastAreaActiveSide="left"
        if viewer and type(viewer.resetView)=="function" then viewer:resetView() end
      end
      return
    elseif (action=="breastAreaLeftRadius" or action=="breastAreaRightRadius" or action=="breastAreaUpperLimit" or action=="breastAreaLowerLimit")
        and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      local step=(control.step or 0.01)*sign
      if action=="breastAreaLeftRadius" then
        local v=math.max(0.045,math.min(0.30,(tonumber(child.data.runtimeBelleBreastAreaLeftRadius) or 0.13)+step))
        child.data.runtimeBelleBreastAreaLeftRadius=v
        if mod.save and mod.save.set then mod.save:set(red3dBreastAreaSaveKey(id,"left_radius"),v) end
      elseif action=="breastAreaRightRadius" then
        local v=math.max(0.045,math.min(0.30,(tonumber(child.data.runtimeBelleBreastAreaRightRadius) or 0.13)+step))
        child.data.runtimeBelleBreastAreaRightRadius=v
        if mod.save and mod.save.set then mod.save:set(red3dBreastAreaSaveKey(id,"right_radius"),v) end
      elseif action=="breastAreaUpperLimit" then
        local lower=tonumber(child.data.runtimeBelleBreastAreaLowerLimit) or 0.44
        local v=math.max(0.04,math.min(lower-0.04,(tonumber(child.data.runtimeBelleBreastAreaUpperLimit) or 0.16)+step))
        child.data.runtimeBelleBreastAreaUpperLimit=v
        if mod.save and mod.save.set then mod.save:set(red3dBreastAreaSaveKey(id,"upper_limit"),v) end
      else
        local upper=tonumber(child.data.runtimeBelleBreastAreaUpperLimit) or 0.16
        local v=math.max(upper+0.04,math.min(0.72,(tonumber(child.data.runtimeBelleBreastAreaLowerLimit) or 0.44)+step))
        child.data.runtimeBelleBreastAreaLowerLimit=v
        if mod.save and mod.save.set then mod.save:set(red3dBreastAreaSaveKey(id,"lower_limit"),v) end
      end
      child.skinKey=nil; child.voxelUploadedKey=nil; child.voxelFrameKey=nil
      return
    elseif action=="breastAreaReset" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      child.data.runtimeBelleBreastAreaLeftX=0.40
      child.data.runtimeBelleBreastAreaLeftY=0.29
      child.data.runtimeBelleBreastAreaLeftRadius=0.13
      child.data.runtimeBelleBreastAreaRightX=0.60
      child.data.runtimeBelleBreastAreaRightY=0.29
      child.data.runtimeBelleBreastAreaRightRadius=0.13
      child.data.runtimeBelleBreastAreaUpperLimit=0.16
      child.data.runtimeBelleBreastAreaLowerLimit=0.44
      if mod.save and mod.save.set then
        mod.save:set(red3dBreastAreaSaveKey(id,"left_x"),0.40)
        mod.save:set(red3dBreastAreaSaveKey(id,"left_y"),0.29)
        mod.save:set(red3dBreastAreaSaveKey(id,"left_radius"),0.13)
        mod.save:set(red3dBreastAreaSaveKey(id,"right_x"),0.60)
        mod.save:set(red3dBreastAreaSaveKey(id,"right_y"),0.29)
        mod.save:set(red3dBreastAreaSaveKey(id,"right_radius"),0.13)
        mod.save:set(red3dBreastAreaSaveKey(id,"upper_limit"),0.16)
        mod.save:set(red3dBreastAreaSaveKey(id,"lower_limit"),0.44)
      end
      menu._red3dBreastAreaActiveSide="left"
      child.skinKey=nil; child.voxelUploadedKey=nil; child.voxelFrameKey=nil
      if viewer and type(viewer.resetView)=="function" then viewer:resetView() end
      return
    elseif action=="breastIndependentToggle" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      child.data.runtimeBelleBreastIndependent=(child.data.runtimeBelleBreastIndependent==false)
      if mod.save and mod.save.set then
        mod.save:set(((id=="WOW") and "wow" or "belle").."_breast_independent_v3040",child.data.runtimeBelleBreastIndependent and 1 or 0)
      end
      child.skinKey=nil; child.voxelUploadedKey=nil; child.voxelFrameKey=nil
      return
    elseif action=="buttIndependentToggle" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      child.data.runtimeBelleButtIndependent=(child.data.runtimeBelleButtIndependent==false)
      if mod.save and mod.save.set then
        mod.save:set(((id=="WOW") and "wow" or "belle").."_butt_independent_v3040",child.data.runtimeBelleButtIndependent and 1 or 0)
      end
      child.skinKey=nil; child.voxelUploadedKey=nil; child.voxelFrameKey=nil
      return
    elseif action=="characterImportOpen" then
      if menu then
        menu._red3dCharacterImporter=true
        menu._red3dAccessoryEditor=false
        menu._red3dRigEditor=false
        menu._red3dCharacterSourceIndex=math.max(1,tonumber(menu._red3dCharacterSourceIndex) or 1)
        menu._red3dControlIndex=1
        if #CHARACTER_SOURCE_ORDER==0 then
          local _,_,message=scanCharacterPackages()
          menu._red3dSkinFileStatus=message
        end
        local sourceId=selectedCharacterSourceId(menu)
        if sourceId then rebuildRigPreview(menu,sourceId) end
      end
      if viewer and type(viewer.resetView)=="function" then viewer:resetView() end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="characterImportDone" then
      if menu then
        menu._red3dCharacterImporter=false
        menu._red3dRigPreviewRenderer=nil
        menu._red3dRigSourceId=nil
        menu._red3dControlIndex=1
      end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="characterImportScan" then
      local _,_,message=scanCharacterPackages()
      if menu then
        menu._red3dSkinFileStatus=message
        if (tonumber(menu._red3dCharacterSourceIndex) or 1)>#CHARACTER_SOURCE_ORDER then menu._red3dCharacterSourceIndex=1 end
        local sourceId=selectedCharacterSourceId(menu)
        if sourceId then rebuildRigPreview(menu,sourceId) else menu._red3dRigPreviewRenderer=nil end
      end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="characterImportSelect" then
      if #CHARACTER_SOURCE_ORDER>0 and menu then
        local _,sourceIndex=selectedCharacterSourceId(menu)
        local nextIndex=(sourceIndex or 1)+sign
        if nextIndex<1 then nextIndex=#CHARACTER_SOURCE_ORDER elseif nextIndex>#CHARACTER_SOURCE_ORDER then nextIndex=1 end
        menu._red3dCharacterSourceIndex=nextIndex
        local sourceId=selectedCharacterSourceId(menu)
        menu._red3dRigSourceId=sourceId
        if sourceId then rebuildRigPreview(menu,sourceId) end
      end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="characterDonorRig" then
      local sourceId=selectedCharacterSourceId(menu)
      local st=sourceId and rigState(sourceId) or nil
      if st and #DONOR_RIG_IDS>0 then
        local current=1
        for i,v in ipairs(DONOR_RIG_IDS) do if v==st.donorId then current=i break end end
        current=current+sign; if current<1 then current=#DONOR_RIG_IDS elseif current>#DONOR_RIG_IDS then current=1 end
        persistRigField(sourceId,"donorId",DONOR_RIG_IDS[current])
        if menu and menu._red3dCharacterImporter then rebuildRigPreview(menu,sourceId) end
      end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="cloneSwapYZ" or action=="cloneFlipX" or action=="cloneFlipY" or action=="cloneFlipZ" then
      local sourceId=selectedCharacterSourceId(menu); local st=sourceId and rigState(sourceId) or nil
      if st then
        local field=(action=="cloneSwapYZ") and "meshSwapYZ" or ((action=="cloneFlipX") and "meshFlipX" or ((action=="cloneFlipY") and "meshFlipY" or "meshFlipZ"))
        persistRigField(sourceId,field,not st[field])
        if menu and menu._red3dCharacterImporter then rebuildRigPreview(menu,sourceId) end
      end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="cloneFitScale" or action=="cloneFitX" or action=="cloneFitY" or action=="cloneFitZ" then
      local sourceId=selectedCharacterSourceId(menu); local st=sourceId and rigState(sourceId) or nil
      if st then
        local field=(action=="cloneFitScale") and "fitScale" or ((action=="cloneFitX") and "fitX" or ((action=="cloneFitY") and "fitY" or "fitZ"))
        local value=(tonumber(st[field]) or tonumber(control.value) or ((field=="fitScale") and 1 or 0))+(tonumber(control.step) or 0.01)*sign
        if control.min~=nil then value=math.max(control.min,value) end
        if control.max~=nil then value=math.min(control.max,value) end
        persistRigField(sourceId,field,value)
        if menu and menu._red3dCharacterImporter then rebuildRigPreview(menu,sourceId) end
      end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="characterCloneRig" then
      local sourceId=selectedCharacterSourceId(menu)
      if sourceId then
        local cloneId,err=registerDonorCharacter(sourceId)
        if menu then
          if cloneId then
            local def=CHARACTER_DEFS[cloneId]
            local stats=def and def._donorStats
            local extra=""
            if stats then extra=string.format(" • mean surface match %.4f",tonumber(stats.meanNearest) or 0) end
            menu._red3dSkinFileStatus="Imported with "..donorRigLabel(def and def._donorId).." rig"..extra
            if type(menu._red3dRebuildSkinItems)=="function" then menu:_red3dRebuildSkinItems(cloneId) end
          else menu._red3dSkinFileStatus="Donor rig clone failed: "..tostring(err) end
        end
      end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="characterRigOpen" then
      local sourceId=selectedCharacterSourceId(menu)
      if menu and sourceId and HumanoidRigger then
        menu._red3dRigSourceId=sourceId
        menu._red3dCharacterImporter=false
        menu._red3dAccessoryEditor=false
        menu._red3dRigEditor=true
        menu._red3dRigReturnMode="characterImport"
        menu._red3dRigJointIndex=1
        menu._red3dControlIndex=1
        rebuildRigPreview(menu,sourceId)
      end
      if viewer and type(viewer.resetView)=="function" then viewer:resetView() end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="characterImportNone" then
      return
    elseif action=="rigTexture" or action=="rigUVVariant" or action=="rigFlipU" or action=="rigFlipV" or action=="rigSwapUV" then
      local sourceId=selectedCharacterSourceId(menu)
      local def=sourceId and rigSourceDef(sourceId) or nil
      local st=sourceId and rigState(sourceId) or nil
      if def and st then
        if action=="rigTexture" then
          local options=type(def.textureOptions)=="table" and def.textureOptions or {}
          if #options>0 then
            local current=math.floor(tonumber(st.textureIndex) or tonumber(def.defaultTextureIndex) or 1)+sign
            if current<1 then current=#options elseif current>#options then current=1 end
            persistRigField(sourceId,"textureIndex",current)
          end
        elseif action=="rigUVVariant" then
          local variants=type(def.uvVariants)=="table" and def.uvVariants or {}
          if #variants>0 then
            local current=math.floor(tonumber(st.uvVariant) or 1)+sign
            if current<1 then current=#variants elseif current>#variants then current=1 end
            persistRigField(sourceId,"uvVariant",current)
          end
        elseif action=="rigFlipU" then persistRigField(sourceId,"flipU",not st.flipU)
        elseif action=="rigFlipV" then persistRigField(sourceId,"flipV",not st.flipV)
        elseif action=="rigSwapUV" then persistRigField(sourceId,"swapUV",not st.swapUV) end
        rebuildRigPreview(menu,sourceId)
      end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="accessoryRigOpen" then
      -- Backward-compatible hidden path for v3.0.29 state. New rigs are opened
      -- from Character Import in the main selector, not from Accessories.
      local sourceId=selectedAccessoryId(menu)
      if menu and sourceId and HumanoidRigger then
        copyAccessoryTextureToRig(id,sourceId)
        menu._red3dRigSourceId=sourceId
        menu._red3dAccessoryEditor=false
        menu._red3dRigEditor=true
        menu._red3dRigReturnMode="accessory"
        menu._red3dRigJointIndex=1
        menu._red3dControlIndex=1
        rebuildRigPreview(menu,sourceId)
      end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="rigDone" then
      if menu then
        menu._red3dRigEditor=false
        if menu._red3dRigReturnMode=="accessory" then menu._red3dAccessoryEditor=true
        else menu._red3dCharacterImporter=true end
        menu._red3dRigReturnMode=nil
        menu._red3dRigPreviewRenderer=nil
        menu._red3dControlIndex=1
        local sourceId=selectedRigSourceId(menu)
        if menu._red3dCharacterImporter then
          sourceId=selectedCharacterSourceId(menu)
          if sourceId then rebuildRigPreview(menu,sourceId) end
        end
      end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="rigAuto" then
      local sourceId=selectedRigSourceId(menu)
      if sourceId then resetRigAutoSetup(sourceId); rebuildRigPreview(menu,sourceId) end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="rigMirror" then
      local sourceId=selectedRigSourceId(menu); local st=sourceId and rigState(sourceId)
      if st then persistRigField(sourceId,"mirror",not st.mirror) end
      return
    elseif action=="rigWeightStyle" then
      local sourceId=selectedRigSourceId(menu); local st=sourceId and rigState(sourceId)
      local styles=(HumanoidRigger and HumanoidRigger.WEIGHT_STYLES) or {"TIGHT","BALANCED","SOFT"}
      if st and #styles>0 then
        local current=1
        for i,v in ipairs(styles) do if tostring(v)==tostring(st.weightStyle) then current=i break end end
        current=current+sign
        if current<1 then current=#styles elseif current>#styles then current=1 end
        persistRigField(sourceId,"weightStyle",styles[current])
        if menu then menu._red3dRigPreviewDirty=true end
      end
      return
    elseif action=="rigFrontView" then
      if viewer and type(viewer.resetView)=="function" then viewer:resetView() end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="rigJoint" then
      local order=HumanoidRigger and HumanoidRigger.JOINT_ORDER or {}
      if menu and #order>0 then
        local current=math.floor(tonumber(menu._red3dRigJointIndex) or 1)+sign
        if current<1 then current=#order elseif current>#order then current=1 end
        menu._red3dRigJointIndex=current
      end
      return
    elseif action=="rigPreview" then
      local sourceId=selectedRigSourceId(menu)
      if sourceId then rebuildRigPreview(menu,sourceId) end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="rigSave" then
      local sourceId=selectedRigSourceId(menu)
      if sourceId then
        local rigId,err=registerRiggedCharacter(sourceId)
        if menu then
          if rigId then
            menu._red3dSkinFileStatus="Saved to Character Selector: "..tostring(CHARACTER_DEFS[rigId] and CHARACTER_DEFS[rigId].label or rigId)
            if type(menu._red3dRebuildSkinItems)=="function" then menu:_red3dRebuildSkinItems(rigId) end
          else
            menu._red3dSkinFileStatus="Rig save failed: "..tostring(err)
          end
        end
      end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="rigNone" then
      return
    elseif action=="rigJointX" or action=="rigJointY" or action=="rigJointZ" then
      local sourceId=selectedRigSourceId(menu); local st=sourceId and rigState(sourceId)
      local jointName=currentRigJoint(menu)
      if st and jointName then
        local axis=(action=="rigJointX") and 1 or ((action=="rigJointY") and 2 or 3)
        local value=(tonumber(st.joints[jointName][axis]) or 0)+(tonumber(control.step) or 0.01)*sign
        if control.min~=nil then value=math.max(control.min,value) end
        if control.max~=nil then value=math.min(control.max,value) end
        setRigJointCoord(sourceId,jointName,axis,value)
        if menu then menu._red3dRigPreviewDirty=true end
      end
      return
    elseif action=="rigSoftness" or action=="rigArmRest" or action=="rigHeight" then
      local sourceId=selectedRigSourceId(menu); local st=sourceId and rigState(sourceId)
      if st then
        local field=(action=="rigSoftness") and "softness" or ((action=="rigArmRest") and "armRest" or "height")
        local value=(tonumber(st[field]) or tonumber(control.value) or 0)+(tonumber(control.step) or 0.01)*sign
        if control.min~=nil then value=math.max(control.min,value) end
        if control.max~=nil then value=math.min(control.max,value) end
        persistRigField(sourceId,field,value)
        if menu then menu._red3dRigPreviewDirty=true end
      end
      return
    elseif action=="accessoryOpen" then
      if menu then
        menu._red3dAccessoryEditor=true
        menu._red3dAccessoryIndex=math.max(1,tonumber(menu._red3dAccessoryIndex) or 1)
        menu._red3dControlIndex=1
        if #ACCESSORY_ORDER==0 then
          local _,_,message=scanAccessoryPackages()
          menu._red3dSkinFileStatus=message
        end
      end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="accessoryDone" then
      if menu then menu._red3dAccessoryEditor=false; menu._red3dControlIndex=1 end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="accessoryScan" then
      local _,_,message=scanAccessoryPackages()
      if menu then
        menu._red3dSkinFileStatus=message
        if (tonumber(menu._red3dAccessoryIndex) or 1)>#ACCESSORY_ORDER then menu._red3dAccessoryIndex=1 end
      end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="accessoryNone" then
      return
    end

    local accessoryId,accessoryIndex=selectedAccessoryId(menu)
    local def=accessoryId and ACCESSORY_DEFS[accessoryId] or nil
    local st=def and accessoryState(id,accessoryId) or nil
    if action=="accessorySelect" and #ACCESSORY_ORDER>0 then
      local nextIndex=(accessoryIndex or 1)+sign
      if nextIndex<1 then nextIndex=#ACCESSORY_ORDER elseif nextIndex>#ACCESSORY_ORDER then nextIndex=1 end
      if menu then menu._red3dAccessoryIndex=nextIndex end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="accessoryEnabled" and st then
      persistAccessoryField(id,accessoryId,"enabled",not st.enabled)
      invalidateSelectorViewer(viewer)
      return
    elseif action=="accessoryBone" and st then
      local current=1
      for i,b in ipairs(ACCESSORY_BONES) do if b==st.bone then current=i break end end
      current=current+sign
      if current<1 then current=#ACCESSORY_BONES elseif current>#ACCESSORY_BONES then current=1 end
      persistAccessoryField(id,accessoryId,"bone",ACCESSORY_BONES[current])
      invalidateSelectorViewer(viewer)
      return
    elseif action=="accessoryTexture" and st and def then
      local options=type(def.textureOptions)=="table" and def.textureOptions or {}
      if #options>0 then
        local current=math.floor(tonumber(st.textureIndex) or tonumber(def.defaultTextureIndex) or 1)
        current=current+sign
        if current<1 then current=#options elseif current>#options then current=1 end
        persistAccessoryField(id,accessoryId,"textureIndex",current)
      end
      invalidateSelectorViewer(viewer)
      return
    elseif action=="accessoryAutoMaterials" and st then
      persistAccessoryField(id,accessoryId,"autoMaterialTextures",not st.autoMaterialTextures)
      invalidateSelectorViewer(viewer); return
    elseif action=="accessoryUVVariant" and st and def then
      local variants=type(def.uvVariants)=="table" and def.uvVariants or {}
      if #variants>0 then
        local current=math.floor(tonumber(st.uvVariant) or 1)+sign
        if current<1 then current=#variants elseif current>#variants then current=1 end
        persistAccessoryField(id,accessoryId,"uvVariant",current)
      end
      invalidateSelectorViewer(viewer); return
    elseif action=="accessoryFlipU" and st then
      persistAccessoryField(id,accessoryId,"flipU",not st.flipU); invalidateSelectorViewer(viewer); return
    elseif action=="accessoryFlipV" and st then
      persistAccessoryField(id,accessoryId,"flipV",not st.flipV); invalidateSelectorViewer(viewer); return
    elseif action=="accessorySwapUV" and st then
      persistAccessoryField(id,accessoryId,"swapUV",not st.swapUV); invalidateSelectorViewer(viewer); return
    elseif action=="accessoryRepeatTexture" and st then
      persistAccessoryField(id,accessoryId,"repeatTexture",not st.repeatTexture); invalidateSelectorViewer(viewer); return
    elseif action=="accessoryNearestFilter" and st then
      persistAccessoryField(id,accessoryId,"nearestFilter",not st.nearestFilter); invalidateSelectorViewer(viewer); return
    elseif action=="accessoryTextureReset" and st then
      resetAccessoryTextureFixes(id,accessoryId); invalidateSelectorViewer(viewer); return
    elseif action=="accessoryReset" and st then
      resetAccessoryPlacement(id,accessoryId)
      invalidateSelectorViewer(viewer)
      return
    end

    local field=ACCESSORY_ACTION_FIELD[action]
    if field and st then
      local value=(tonumber(control.value) or 0)+(tonumber(control.step) or 0.01)*sign
      if control.min~=nil then value=math.max(control.min,value) end
      if control.max~=nil then value=math.min(control.max,value) end
      local step=tonumber(control.step) or 0
      if step>0 then value=math.floor(value/step+0.5)*step end
      persistAccessoryField(id,accessoryId,field,value)
      invalidateSelectorViewer(viewer)
      return
    end
  end

  local function setSelectorControlFraction(id,index,frac,viewer,menu)
    if not id then return end
    frac=math.max(0,math.min(1,tonumber(frac) or 0))
    local child=renderers[id]
    local controls=selectorControlsFor({characterId=id},child,menu)
    local control=controls[index]
    if not control or control.min==nil or control.max==nil or control.toggle or control.button or control.choice then return end
    local value=control.min+(control.max-control.min)*frac
    local step=tonumber(control.step) or 0
    if step>0 then value=math.floor(value/step+0.5)*step end
    if control.action=="size" then
      applyCharacterScale(id,value,true)
    elseif control.action=="breastStrength" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      applyBellePhysics("breast",value,true,id)
    elseif (control.action=="breastAreaLeftRadius" or control.action=="breastAreaRightRadius" or control.action=="breastAreaUpperLimit" or control.action=="breastAreaLowerLimit")
        and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      if control.action=="breastAreaLeftRadius" then
        local v=math.max(0.045,math.min(0.30,tonumber(value) or 0.13))
        child.data.runtimeBelleBreastAreaLeftRadius=v
        if mod.save and mod.save.set then mod.save:set(red3dBreastAreaSaveKey(id,"left_radius"),v) end
      elseif control.action=="breastAreaRightRadius" then
        local v=math.max(0.045,math.min(0.30,tonumber(value) or 0.13))
        child.data.runtimeBelleBreastAreaRightRadius=v
        if mod.save and mod.save.set then mod.save:set(red3dBreastAreaSaveKey(id,"right_radius"),v) end
      elseif control.action=="breastAreaUpperLimit" then
        local lower=tonumber(child.data.runtimeBelleBreastAreaLowerLimit) or 0.44
        local v=math.max(0.04,math.min(lower-0.04,tonumber(value) or 0.16))
        child.data.runtimeBelleBreastAreaUpperLimit=v
        if mod.save and mod.save.set then mod.save:set(red3dBreastAreaSaveKey(id,"upper_limit"),v) end
      else
        local upper=tonumber(child.data.runtimeBelleBreastAreaUpperLimit) or 0.16
        local v=math.max(upper+0.04,math.min(0.72,tonumber(value) or 0.44))
        child.data.runtimeBelleBreastAreaLowerLimit=v
        if mod.save and mod.save.set then mod.save:set(red3dBreastAreaSaveKey(id,"lower_limit"),v) end
      end
      child.skinKey=nil; child.voxelUploadedKey=nil; child.voxelFrameKey=nil
    elseif control.action=="buttStrength" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      applyBellePhysics("buttocks",value,true,id)
    elseif control.action=="thighStrength" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      applyBellePhysics("thighs",value,true,id)
    elseif control.action=="hairStrength" and child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      applyBellePhysics("hair",value,true,id)
    elseif control.action=="rigJointX" or control.action=="rigJointY" or control.action=="rigJointZ" then
      local sourceId=selectedRigSourceId(menu)
      local jointName=currentRigJoint(menu)
      local axis=(control.action=="rigJointX") and 1 or ((control.action=="rigJointY") and 2 or 3)
      if sourceId and jointName then
        setRigJointCoord(sourceId,jointName,axis,value)
        if menu then menu._red3dRigPreviewDirty=true end
      end
    elseif control.action=="rigSoftness" or control.action=="rigArmRest" or control.action=="rigHeight" then
      local sourceId=selectedRigSourceId(menu)
      local field=(control.action=="rigSoftness") and "softness" or ((control.action=="rigArmRest") and "armRest" or "height")
      if sourceId then persistRigField(sourceId,field,value); if menu then menu._red3dRigPreviewDirty=true end end
    else
      local accessoryId=selectedAccessoryId(menu)
      local field=ACCESSORY_ACTION_FIELD[control.action]
      if accessoryId and field then persistAccessoryField(id,accessoryId,field,value) end
    end
    invalidateSelectorViewer(viewer)
  end

  local function drawPhysicsGearButton(r,hover,active)
    local g=love.graphics
    local bg=active and SELECTOR_THEME.selected or (hover and {0.12,0.22,0.34,1} or {0.055,0.085,0.13,0.72})
    roundedFill(r.x,r.y,r.w,r.h,math.max(5,r.h*0.24),bg)
    roundedLine(r.x,r.y,r.w,r.h,math.max(5,r.h*0.24),hover and SELECTOR_THEME.accent or SELECTOR_THEME.divider,1)
    local cx,cy=r.x+r.w*0.5,r.y+r.h*0.5
    local outer=math.min(r.w,r.h)*0.24
    local inner=outer*0.40
    setRGBA(hover and SELECTOR_THEME.text or SELECTOR_THEME.muted)
    g.setLineWidth(math.max(1.5,outer*0.20))
    g.circle("line",cx,cy,outer)
    g.circle("line",cx,cy,inner)
    for i=0,7 do
      local a=i*math.pi/4
      local x1,y1=cx+math.cos(a)*outer*1.05,cy+math.sin(a)*outer*1.05
      local x2,y2=cx+math.cos(a)*outer*1.42,cy+math.sin(a)*outer*1.42
      g.line(x1,y1,x2,y2)
    end
    g.setLineWidth(1)
  end

  local function drawControllerGlyph(kind,x,y,scale,font)
    local g=love.graphics
    local h=math.max(15,math.floor(17*scale))
    local w=h
    if kind=="DPAD" then
      setRGBA({0.08,0.13,0.20,1})
      g.rectangle("fill",x+h*0.34,y,h*0.32,h,3,3)
      g.rectangle("fill",x,y+h*0.34,h,h*0.32,3,3)
      setRGBA(SELECTOR_THEME.divider)
      g.rectangle("line",x+h*0.34,y,h*0.32,h,3,3)
      g.rectangle("line",x,y+h*0.34,h,h*0.32,3,3)
      return h
    elseif kind=="XY" then
      local r=h*0.42
      for i,label in ipairs({"X","Y"}) do
        local cx=x+r+(i-1)*(h*0.90)
        roundedFill(cx-r,y+h*0.08,r*2,r*2,r,{0.08,0.13,0.20,1})
        roundedLine(cx-r,y+h*0.08,r*2,r*2,r,SELECTOR_THEME.divider,1)
        drawSelectorText(label,font,cx-r,y+h*0.08+(r*2-(font and font:getHeight() or 10))*0.5,SELECTOR_THEME.text,"center",r*2)
      end
      return h*1.8
    else
      local capsule=(kind=="L3" or kind=="R3" or kind=="LB" or kind=="RB")
      w=capsule and h*1.55 or h
      roundedFill(x,y,w,h,h*0.48,{0.08,0.13,0.20,1})
      roundedLine(x,y,w,h,h*0.48,SELECTOR_THEME.divider,1)
      drawSelectorText(kind,font,x,y+(h-(font and font:getHeight() or 10))*0.5,SELECTOR_THEME.text,"center",w)
      return w
    end
  end

  local function drawControllerHints(font,x,y,width,scale,belle)
    local hints={{"DPAD","NAV/TURN"},{"L3","SETTING"},{"XY","ADJUST"},{"LB","EXPORT"},{"RB","IMPORT"},{"A","USE"},{"B","BACK"}}
    local gap=math.max(7,math.floor(9*scale))
    local textGap=math.max(3,math.floor(4*scale))
    local iconH=math.max(15,math.floor(17*scale))
    local widths={}
    local total=0
    for i,h in ipairs(hints) do
      local glyphW=(h[1]=="DPAD") and iconH or ((h[1]=="XY") and math.max(27,math.floor(31*scale)) or ((h[1]=="L3" or h[1]=="R3" or h[1]=="LB" or h[1]=="RB") and math.max(23,math.floor(26*scale)) or iconH))
      local tw=font and font:getWidth(h[2]) or #h[2]*6
      widths[i]=glyphW+textGap+tw
      total=total+widths[i]+(i>1 and gap or 0)
    end

    local lines={}
    if total<=width then
      lines[1]={1,#hints,total}
    else
      local split=math.ceil(#hints/2)
      local function lineWidth(a,b)
        local w=0
        for i=a,b do w=w+widths[i]+(i>a and gap or 0) end
        return w
      end
      lines[1]={1,split,lineWidth(1,split)}
      lines[2]={split+1,#hints,lineWidth(split+1,#hints)}
    end

    for li,line in ipairs(lines) do
      local sx=x+math.max(0,(width-line[3])*0.5)
      local ly=y+(li-1)*(iconH+math.max(3,math.floor(4*scale)))
      for i=line[1],line[2] do
        local h=hints[i]
        local gw=drawControllerGlyph(h[1],sx,ly,scale,font)
        drawSelectorText(h[2],font,sx+gw+textGap,ly+(iconH-(font and font:getHeight() or 10))*0.5,SELECTOR_THEME.muted)
        sx=sx+widths[i]+gap
      end
    end
    return #lines
  end

  local function drawMiniButton(text,font,r,hover,active)
    local bg=active and SELECTOR_THEME.selected or (hover and {0.12,0.22,0.34,1} or {0.075,0.115,0.175,1})
    roundedFill(r.x,r.y,r.w,r.h,math.max(5,r.h*0.22),bg)
    roundedLine(r.x,r.y,r.w,r.h,math.max(5,r.h*0.22),hover and SELECTOR_THEME.accent or SELECTOR_THEME.divider,1)
    drawSelectorText(text,font,r.x,r.y+(r.h-(font and font:getHeight() or 12))*0.5,
      hover and SELECTOR_THEME.text or SELECTOR_THEME.muted,"center",r.w)
  end

  local function drawSelectorCursor(x,y,scale,interactive,dragging)
    if not (love and love.graphics and x and y) then return end
    local g=love.graphics
    local s=math.max(0.85,math.min(1.8,tonumber(scale) or 1))
    local pts={
      x,y,
      x+2*s,y+22*s,
      x+7*s,y+17*s,
      x+12*s,y+28*s,
      x+17*s,y+25*s,
      x+12*s,y+15*s,
      x+20*s,y+14*s,
    }
    -- Thick black silhouette + bright face keeps the pointer readable over both
    -- the pale character texture and the dark selector panels.
    g.setLineWidth(math.max(2,2.5*s))
    g.setColor(0,0,0,0.96)
    g.polygon("fill",pts)
    g.polygon("line",pts)
    g.setLineWidth(math.max(1,1.1*s))
    if dragging then
      setRGBA(SELECTOR_THEME.accent)
    elseif interactive then
      g.setColor(1,1,1,1)
    else
      g.setColor(0.93,0.97,1,1)
    end
    g.polygon("line",pts)
    -- Small center dot makes precise slider placement easier.
    g.circle("fill",x+3*s,y+5*s,math.max(1.2,1.5*s))
    if dragging then
      g.setLineWidth(math.max(1.5,2*s))
      g.line(x-8*s,y+31*s,x+17*s,y+31*s)
      g.line(x-8*s,y+31*s,x-3*s,y+27*s)
      g.line(x-8*s,y+31*s,x-3*s,y+35*s)
      g.line(x+17*s,y+31*s,x+12*s,y+27*s)
      g.line(x+17*s,y+31*s,x+12*s,y+35*s)
      g.setLineWidth(1)
    end
  end

  local function drawStandaloneSkinSelector(menu,viewport)
    if not (love and love.graphics and menu and menu._red3dSkinSelector) then return end
    local g=love.graphics
    local vx,vy,vw,vh=viewportRect(viewport)
    if vw<360 or vh<260 then return end
    local mobile=SELECTOR_THEME.mobileMode(menu)

    local scale=math.max(mobile and 0.78 or 0.72,math.min(mobile and 1.42 or 1.55,math.min(vw/1280,vh/720)))
    local outer=mobile and math.max(7,math.floor(10*scale)) or math.max(14,math.floor(28*scale))
    local gap=mobile and math.max(7,math.floor(9*scale)) or math.max(10,math.floor(16*scale))
    local radius=mobile and math.max(9,math.floor(13*scale)) or math.max(10,math.floor(18*scale))
    local pad=mobile and math.max(9,math.floor(11*scale)) or math.max(12,math.floor(20*scale))
    local titleFont=selectorFont((mobile and 23 or 28)*scale)
    local subtitleFont=selectorFont((mobile and 12 or 14)*scale)
    local bodyFont=selectorFont((mobile and 17 or 18)*scale)
    local smallFont=selectorFont((mobile and 13 or 12)*scale)
    local badgeFont=selectorFont((mobile and 11 or 10)*scale)

    local maxW=math.min(vw-outer*2,1500*scale)
    local maxH=math.min(vh-outer*2,860*scale)
    local panelW=math.max(330,maxW)
    local panelH=math.max(250,maxH)
    local px=vx+(vw-panelW)*0.5
    local py=vy+(vh-panelH)*0.5

    local mouseX,mouseY=tonumber(menu._red3dMouseX),tonumber(menu._red3dMouseY)
    if (not mobile) and love.mouse and love.mouse.getPosition then
      local ok,mx,my=pcall(love.mouse.getPosition)
      if ok and mx and my and (not mouseX or not mouseY or not menu._red3dSawPointerHook) then
        mouseX,mouseY=mx,my
        menu._red3dMouseX,menu._red3dMouseY=mx,my
      end
    end

    local pushed=false
    if g.push then pushed=pcall(g.push,"all") end
    local oldShader=g.getShader and g.getShader() or nil
    pcall(g.setShader)
    pcall(g.setBlendMode,"alpha","alphamultiply")

    setRGBA(SELECTOR_THEME.backdrop)
    g.rectangle("fill",vx,vy,vw,vh)
    roundedFill(px+5*scale,py+7*scale,panelW,panelH,radius,SELECTOR_THEME.shadow)
    roundedFill(px,py,panelW,panelH,radius,SELECTOR_THEME.surface)
    roundedLine(px,py,panelW,panelH,radius,SELECTOR_THEME.divider,math.max(1,2*scale))

    local headerH=mobile and math.max(52,math.floor(58*scale)) or math.max(62,math.floor(76*scale))
    local footerH=mobile and math.max(82,math.floor(90*scale)) or math.max(88,math.floor(104*scale))
    drawSelectorText("SKIN SELECTOR",titleFont,px+pad,py+math.floor((mobile and 8 or 12)*scale),SELECTOR_THEME.text)
    local versionLabel="v3.1.21"
    local versionW=smallFont and smallFont:getWidth(versionLabel) or 0
    drawSelectorText(versionLabel,smallFont,px+panelW-pad-versionW,py+math.floor((mobile and 15 or 20)*scale),SELECTOR_THEME.muted)
    drawSelectorText(mobile and "Tap a skin • settings use ▲/▼ • drag preview • pinch to zoom"
      or "Click a skin to preview • adjust settings with the mouse or controller",subtitleFont,
      px+pad,py+math.floor((mobile and 35 or 47)*scale),SELECTOR_THEME.muted)
    setRGBA(SELECTOR_THEME.divider)
    g.rectangle("fill",px+pad,py+headerH-1,panelW-pad*2,1)

    local contentY=py+headerH+gap
    local contentH=panelH-headerH-footerH-gap*2
    local listW=mobile and math.max(176,math.min(panelW*0.30,330*scale))
      or math.max(210,math.min(panelW*0.35,420*scale))
    local previewX=px+pad+listW+gap
    local previewW=px+panelW-pad-previewX
    local listX=px+pad

    roundedFill(listX,contentY,listW,contentH,radius*0.75,SELECTOR_THEME.surfaceRaised)
    roundedFill(previewX,contentY,previewW,contentH,radius*0.75,SELECTOR_THEME.surfaceRaised)

    local hit={characterRows={},controls={},rigJoints={}}
    menu._red3dMouseUI=hit
    hit.list={x=listX,y=contentY,w=listW,h=contentH}

    local items=menu.items or {}
    local selected=math.max(1,math.min(#items,tonumber(menu.index) or 1))
    local listPad=math.max(10,math.floor(12*scale))
    local rowGap=math.max(4,math.floor(6*scale))
    local availableH=contentH-listPad*2
    local rowH=mobile and math.max(52,math.floor(58*scale)) or math.max(38,math.floor(48*scale))
    local visible=math.max(1,math.floor((availableH+rowGap)/(rowH+rowGap)))
    visible=math.min(visible,#items)
    local first=math.max(1,math.min(selected-math.floor(visible/2),#items-visible+1))
    local active=renderer.activeId or "RED"

    for slot=0,visible-1 do
      local i=first+slot
      local item=items[i]
      if item then
        local ry=contentY+listPad+slot*(rowH+rowGap)
        local rr={x=listX+listPad,y=ry,w=listW-listPad*2,h=rowH,index=i}
        hit.characterRows[#hit.characterRows+1]=rr
        local hover=rectContains(rr,mouseX,mouseY)
        local chosen=(i==selected)
        if chosen or hover then
          roundedFill(rr.x,rr.y,rr.w,rr.h,math.max(7,radius*0.48),chosen and SELECTOR_THEME.selected or {0.075,0.14,0.22,1})
        end
        if chosen then
          setRGBA(SELECTOR_THEME.accent)
          g.rectangle("fill",rr.x,ry+math.max(6,rowH*0.18),math.max(3,4*scale),rowH*0.64,3,3)
        end
        local label=item.fullLabel or item.label or item.previewLabel or ""
        drawSelectorText(label,bodyFont,rr.x+math.max(12,16*scale),
          ry+(rowH-(bodyFont and bodyFont:getHeight() or 18))*0.5,
          (chosen or hover) and SELECTOR_THEME.text or SELECTOR_THEME.muted)
        if item.characterId==active then
          local badge="ACTIVE"
          local bw=(badgeFont and badgeFont:getWidth(badge) or 38)+math.max(12,14*scale)
          local bh=math.max(20,math.floor(23*scale))
          local bx=rr.x+rr.w-bw-math.max(6,8*scale)
          local by=ry+(rowH-bh)*0.5
          roundedFill(bx,by,bw,bh,bh*0.45,SELECTOR_THEME.active)
          drawSelectorText(badge,badgeFont,bx,by+(bh-(badgeFont and badgeFont:getHeight() or 10))*0.5,
            {0.02,0.10,0.08,1},"center",bw)
        end
      end
    end

    local scrollBtn=mobile and math.max(34,math.floor(38*scale)) or math.max(20,math.floor(24*scale))
    if first>1 then
      hit.listUp={x=listX+listW-listPad-scrollBtn,y=contentY+4*scale,w=scrollBtn,h=scrollBtn}
      drawMiniButton("▲",badgeFont,hit.listUp,rectContains(hit.listUp,mouseX,mouseY),false)
    end
    if first+visible-1<#items then
      hit.listDown={x=listX+listW-listPad-scrollBtn,y=contentY+contentH-scrollBtn-4*scale,w=scrollBtn,h=scrollBtn}
      drawMiniButton("▼",badgeFont,hit.listDown,rectContains(hit.listDown,mouseX,mouseY),false)
    end

    local item=items[selected]
    local child=item and renderers[item.characterId] or nil
    if (menu._red3dRigEditor or menu._red3dCharacterImporter) and menu._red3dRigPreviewRenderer then
      child=menu._red3dRigPreviewRenderer
    end
    local viewer=menu._red3dViewer
    local bridge=renderer.voxelBridge
    local previewPad=math.max(12,math.floor(16*scale))
    local label=(item and item.fullLabel) or (child and child.characterLabel) or ""
    if menu._red3dRigEditor or menu._red3dCharacterImporter then
      local sourceId=(menu._red3dRigEditor and selectedRigSourceId(menu)) or selectedCharacterSourceId(menu)
      local sourceDef=sourceId and rigSourceDef(sourceId) or nil
      if sourceDef then label=tostring(sourceDef.label or "Imported Model").." • CHARACTER RIG" end
    end
    local countText=(#items>0) and string.format("%d / %d",selected,#items) or ""
    drawSelectorText(label,bodyFont,previewX+previewPad,contentY+math.max(8,10*scale),SELECTOR_THEME.text)
    local cw=smallFont and smallFont:getWidth(countText) or 0
    drawSelectorText(countText,smallFont,previewX+previewW-previewPad-cw,contentY+math.max(12,14*scale),SELECTOR_THEME.muted)

    local modelTop=contentY+math.max(44,math.floor(48*scale))
    local belleControls=(child and child.behaviorId=="BELLESTARMON")
    local detailsBottom=contentY+contentH-previewPad
    local modelX,modelY,modelW,modelH
    local settingsX,settingsY,settingsW,settingsH

    if previewW>=500*scale then
      settingsW=math.max(270*scale,math.min(350*scale,previewW*0.47))
      settingsX=previewX+previewW-previewPad-settingsW
      settingsY=modelTop
      settingsH=math.max(160,detailsBottom-modelTop)
      modelX=previewX+previewPad
      modelY=modelTop
      modelW=math.max(160,settingsX-gap-modelX)
      modelH=settingsH
    else
      local controlsH=math.max(120,math.floor(142*scale))
      local modelBottom=contentY+contentH-controlsH
      modelX=previewX+previewPad
      modelY=modelTop
      modelW=previewW-previewPad*2
      modelH=math.max(80,modelBottom-modelTop)
      settingsX=previewX+previewPad
      settingsY=modelBottom+math.max(8,math.floor(10*scale))
      settingsW=previewW-previewPad*2
      settingsH=math.max(90,detailsBottom-settingsY)
    end

    roundedFill(modelX,modelY,modelW,modelH,math.max(8,radius*0.55),{0.025,0.040,0.065,0.72})
    hit.model={x=modelX,y=modelY,w=modelW,h=modelH}
    local modelHover=rectContains(hit.model,mouseX,mouseY)
    if modelHover then roundedLine(modelX,modelY,modelW,modelH,math.max(8,radius*0.55),SELECTOR_THEME.accent,1) end

    local canvas=nil
    if viewer and child and bridge then
      local sceneW=math.max(640,math.min(1152,math.floor(modelW*1.55)))
      local sceneH=math.max(720,math.min(1280,math.floor(modelH*1.55)))
      local ok,result=pcall(viewer.render,viewer,child,bridge,sceneW,sceneH)
      if ok then canvas=result end
    end
    -- v3.1.5: no Dramatic Shape (always the case on Gold) means no voxel
    -- bridge, so fall back to the mod's own projected renderer.
    if not canvas and child and child.previewCanvas then
      local ok,result=pcall(child.previewCanvas,child,
        math.max(96,math.floor(modelW)),math.max(96,math.floor(modelH)),"down")
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
    local areaId=item and item.characterId or nil
    if child and areaId and menu._red3dBreastAreaEditorId==areaId
        and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
      local lx=math.max(0.06,math.min(0.49,tonumber(child.data.runtimeBelleBreastAreaLeftX) or 0.40))
      local ly=math.max(0.06,math.min(0.70,tonumber(child.data.runtimeBelleBreastAreaLeftY) or 0.29))
      local lr=math.max(0.045,math.min(0.30,tonumber(child.data.runtimeBelleBreastAreaLeftRadius) or 0.13))
      local rx=math.max(0.51,math.min(0.94,tonumber(child.data.runtimeBelleBreastAreaRightX) or 0.60))
      local ry=math.max(0.06,math.min(0.70,tonumber(child.data.runtimeBelleBreastAreaRightY) or 0.29))
      local rr=math.max(0.045,math.min(0.30,tonumber(child.data.runtimeBelleBreastAreaRightRadius) or 0.13))
      local upper=math.max(0.04,math.min(0.55,tonumber(child.data.runtimeBelleBreastAreaUpperLimit) or 0.16))
      local lower=math.max(upper+0.04,math.min(0.72,tonumber(child.data.runtimeBelleBreastAreaLowerLimit) or 0.44))
      local baseR=math.min(modelW,modelH)
      local lcx,lcy,lcr=modelX+modelW*lx,modelY+modelH*ly,baseR*lr
      local rcx,rcy,rcr=modelX+modelW*rx,modelY+modelH*ry,baseR*rr
      hit.breastAreaLeft={x=lcx-lcr,y=lcy-lcr,w=lcr*2,h=lcr*2,cx=lcx,cy=lcy,r=lcr,model=hit.model,id=areaId,side="left"}
      hit.breastAreaRight={x=rcx-rcr,y=rcy-rcr,w=rcr*2,h=rcr*2,cx=rcx,cy=rcy,r=rcr,model=hit.model,id=areaId,side="right"}
      local active=menu._red3dBreastAreaActiveSide or "left"
      local function drawAreaCircle(cx,cy,cr,isActive)
        g.setColor(0.10,0.82,1.0,isActive and 0.18 or 0.09); g.circle("fill",cx,cy,cr)
        g.setColor(isActive and 0.28 or 0.18,isActive and 1.0 or 0.86,1.0,isActive and 1.0 or 0.76)
        g.setLineWidth(math.max(isActive and 3 or 2,(isActive and 2.8 or 2.0)*scale)); g.circle("line",cx,cy,cr)
        g.line(cx-cr*0.18,cy,cx+cr*0.18,cy); g.line(cx,cy-cr*0.18,cx,cy+cr*0.18)
      end
      drawAreaCircle(lcx,lcy,lcr,active=="left")
      drawAreaCircle(rcx,rcy,rcr,active=="right")
      local upperY=modelY+modelH*upper
      local lowerY=modelY+modelH*lower
      g.setLineWidth(math.max(1.5,1.8*scale))
      g.setColor(1.0,0.78,0.20,0.92); g.line(modelX+6*scale,upperY,modelX+modelW-6*scale,upperY)
      g.setColor(1.0,0.42,0.24,0.92); g.line(modelX+6*scale,lowerY,modelX+modelW-6*scale,lowerY)
      g.setLineWidth(1)
      drawSelectorText("UPPER",badgeFont,modelX+8*scale,upperY-14*scale,{1.0,0.82,0.30,1})
      drawSelectorText("LOWER",badgeFont,modelX+8*scale,lowerY+2*scale,{1.0,0.50,0.30,1})
      drawSelectorText("BREAST AREA • DRAG EITHER CIRCLE • WHEEL RESIZES ACTIVE CIRCLE",badgeFont,
        modelX+8*scale,modelY+8*scale,{0.35,0.92,1.0,1})
    end
    if menu._red3dRigEditor and HumanoidRigger then
      local sourceId=selectedRigSourceId(menu)
      local st=sourceId and rigState(sourceId) or nil
      if st and st.joints then
        local b=st.bounds or {-0.5,-0.5,-0.5,0.5,0.5,0.5}
        local bw=math.max(1e-6,b[4]-b[1]); local bh=math.max(1e-6,b[5]-b[2])
        local insetX=modelW*0.12; local insetY=modelH*0.08
        local drawW=modelW-insetX*2; local drawH=modelH-insetY*2
        local function jp(name)
          local p=st.joints[name]; if not p then return nil,nil end
          return modelX+insetX+((p[1]-b[1])/bw)*drawW,
                 modelY+insetY+(1-(p[2]-b[2])/bh)*drawH
        end
        local links={
          {"HIPS","SPINE"},{"SPINE","CHEST"},{"CHEST","NECK"},{"NECK","HEAD"},
          {"CHEST","L_SHOULDER"},{"L_SHOULDER","L_ELBOW"},{"L_ELBOW","L_HAND"},
          {"CHEST","R_SHOULDER"},{"R_SHOULDER","R_ELBOW"},{"R_ELBOW","R_HAND"},
          {"HIPS","L_HIP"},{"L_HIP","L_KNEE"},{"L_KNEE","L_FOOT"},
          {"HIPS","R_HIP"},{"R_HIP","R_KNEE"},{"R_KNEE","R_FOOT"},
        }
        g.setLineWidth(math.max(1,1.4*scale)); g.setColor(0.30,0.86,1.0,0.72)
        for _,link in ipairs(links) do
          local ax,ay=jp(link[1]); local bx,by=jp(link[2])
          if ax and bx then g.line(ax,ay,bx,by) end
        end
        local selectedJoint=currentRigJoint(menu)
        for jointIndex,name in ipairs(HumanoidRigger.JOINT_ORDER or {}) do
          local x,y=jp(name)
          if x then
            local markerR=(name==selectedJoint) and math.max(5,6*scale) or math.max(3,4*scale)
            if name==selectedJoint then g.setColor(1.0,0.83,0.24,1.0) else g.setColor(0.35,0.92,1.0,0.95) end
            g.circle("fill",x,y,markerR)
            hit.rigJoints[#hit.rigJoints+1]={name=name,index=jointIndex,x=x-markerR*1.8,y=y-markerR*1.8,w=markerR*3.6,h=markerR*3.6,
              sourceId=sourceId,minX=b[1],minY=b[2],spanX=bw,spanY=bh,screenX=modelX+insetX,screenY=modelY+insetY,screenW=drawW,screenH=drawH}
          end
        end
        g.setLineWidth(1)
        drawSelectorText(menu._red3dRigPreviewDirty and "JOINTS CHANGED • PRESS UPDATE ANIMATED PREVIEW" or "FRONT VIEW: CLICK/DRAG JOINT DOTS • Z USES SLIDER",
          badgeFont,modelX+8*scale,modelY+8*scale,menu._red3dRigPreviewDirty and SELECTOR_THEME.accent or SELECTOR_THEME.muted)
      end
    end
    if mobile then
      -- Phone camera strip. One finger uses the selected mode; two fingers always
      -- pan with their midpoint while pinch distance controls zoom. Keeping
      -- explicit zoom/reset buttons also makes the selector usable on touch
      -- bridges that expose only one pointer at a time.
      local touchH=math.max(38,math.floor(44*scale))
      local touchGap=math.max(4,math.floor(5*scale))
      local touchY=modelY+modelH-touchH-math.max(6,math.floor(7*scale))
      local touchX=modelX+math.max(6,math.floor(7*scale))
      local touchW=modelW-math.max(12,math.floor(14*scale))
      local unit=(touchW-touchGap*4)/5
      local function touchButton(slot,label,key,active)
        local r={x=touchX+(slot-1)*(unit+touchGap),y=touchY,w=unit,h=touchH}
        hit[key]=r
        drawMiniButton(label,badgeFont,r,rectContains(r,mouseX,mouseY),active)
      end
      local cameraMode=menu._red3dTouchCameraMode or "orbit"
      local compactTouch=(unit<54*scale)
      touchButton(1,compactTouch and "ORB" or "ORBIT","touchOrbit",cameraMode=="orbit")
      touchButton(2,"PAN","touchPan",cameraMode=="pan")
      touchButton(3,compactTouch and "−" or "ZOOM −","touchZoomOut",false)
      touchButton(4,compactTouch and "+" or "ZOOM +","touchZoomIn",false)
      touchButton(5,compactTouch and "R" or "RESET","touchReset",false)
      drawSelectorText("1 FINGER "..string.upper(cameraMode).." • 2 FINGERS PAN + PINCH",badgeFont,
        modelX+8*scale,modelY+8*scale,SELECTOR_THEME.muted)
    elseif modelHover then
      drawSelectorText("LMB/MMB ORBIT  •  RMB/SHIFT+MMB PAN  •  WHEEL ZOOM  •  HOME RESET",badgeFont,modelX+8*scale,modelY+modelH-(badgeFont and badgeFont:getHeight() or 10)-8*scale,
        SELECTOR_THEME.muted)
    end

    local controls=selectorControlsFor(item,child,menu)
    local activeControl=tonumber(menu._red3dControlIndex) or 1
    if activeControl<1 then activeControl=1 elseif activeControl>#controls then activeControl=#controls end
    menu._red3dControlIndex=activeControl

    roundedFill(settingsX,settingsY,settingsW,settingsH,math.max(8,radius*0.55),{0.035,0.055,0.088,0.88})
    roundedLine(settingsX,settingsY,settingsW,settingsH,math.max(8,radius*0.55),SELECTOR_THEME.divider,1)
    hit.settings={x=settingsX,y=settingsY,w=settingsW,h=settingsH}
    local settingsPad=math.max(8,math.floor(10*scale))
    local settingsTitleH=math.max(24,math.floor(28*scale))
    local settingsTitle=(menu and menu._red3dRigEditor) and "HUMANOID RIGGER"
      or ((menu and menu._red3dCharacterImporter) and "CHARACTER IMPORTER"
      or ((menu and menu._red3dAccessoryEditor) and "ACCESSORY EDITOR" or "CHARACTER SETTINGS"))
    drawSelectorText(settingsTitle,smallFont,settingsX+settingsPad,settingsY+math.max(6,7*scale),SELECTOR_THEME.text)

    local rowAreaY=settingsY+settingsTitleH
    local rowAreaH=settingsH-settingsTitleH-settingsPad
    local rowGap2=math.max(2,math.floor(3*scale))
    local desiredRowH=mobile and math.max(54,math.floor(60*scale)) or math.max(42,math.floor(50*scale))
    local visibleControls=math.max(1,math.floor((rowAreaH+rowGap2)/(desiredRowH+rowGap2)))
    visibleControls=math.min(visibleControls,#controls)
    local firstControl=1
    if #controls>visibleControls then
      local maxFirst=math.max(1,#controls-visibleControls+1)
      firstControl=math.floor(tonumber(menu._red3dSettingsFirstControl) or 1)
      firstControl=math.max(1,math.min(firstControl,maxFirst))
      if not menu._red3dSettingsWheelBrowsing then
        if activeControl<firstControl then firstControl=activeControl end
        if activeControl>firstControl+visibleControls-1 then firstControl=activeControl-visibleControls+1 end
      end
      firstControl=math.max(1,math.min(firstControl,maxFirst))
      menu._red3dSettingsFirstControl=firstControl
    else
      menu._red3dSettingsFirstControl=1
    end
    hit.settingsFirstControl=firstControl
    hit.settingsVisibleControls=visibleControls
    hit.settingsMaxFirst=math.max(1,#controls-visibleControls+1)
    local actualRowH=math.min(desiredRowH,(rowAreaH-rowGap2*(visibleControls-1))/visibleControls)

    for slot=0,visibleControls-1 do
      local ci=firstControl+slot
      local control=controls[ci]
      local rowY=rowAreaY+slot*(actualRowH+rowGap2)
      local rr={x=settingsX+settingsPad,y=rowY,w=settingsW-settingsPad*2,h=actualRowH,index=ci}
      local hover=rectContains(rr,mouseX,mouseY)
      local selectedControl=(ci==activeControl)
      if selectedControl or hover then
        roundedFill(rr.x,rr.y,rr.w,rr.h,math.max(5,6*scale),selectedControl and {0.08,0.14,0.22,0.94} or {0.06,0.105,0.16,0.9})
      end

      local labelY=rr.y+math.max(3,4*scale)
      drawSelectorText(control.label,badgeFont,rr.x+math.max(5,6*scale),labelY,
        selectedControl and SELECTOR_THEME.text or SELECTOR_THEME.muted)

      if not control.toggle and not control.button then
        local valueText=control.choice or control.display or string.format("%d%%",math.floor((control.value or 0)*100+0.5))
        local valueW=smallFont and smallFont:getWidth(valueText) or 42
        drawSelectorText(valueText,smallFont,rr.x+rr.w-valueW-math.max(5,6*scale),
          rr.y+math.max(2,3*scale),SELECTOR_THEME.text)
      end

      local controlY=rr.y+math.max(16,math.floor(18*scale))
      local controlH=math.max(13,rr.h-(controlY-rr.y)-math.max(3,4*scale))
      local buttonW=mobile and math.max(34,math.floor(38*scale)) or math.max(22,math.floor(25*scale))
      local leftButton={x=rr.x+math.max(4,5*scale),y=controlY,w=buttonW,h=controlH}
      local rightButton={x=rr.x+rr.w-buttonW-math.max(4,5*scale),y=controlY,w=buttonW,h=controlH}
      local centerX=leftButton.x+leftButton.w+math.max(5,6*scale)
      local centerW=rightButton.x-math.max(5,6*scale)-centerX

      local hb={index=ci,row=rr}
      if control.button then
        local button={x=rr.x+math.max(5,6*scale),y=controlY,w=rr.w-math.max(10,12*scale),h=controlH}
        hb.button=button
        drawMiniButton(control.buttonText or control.label,badgeFont,button,rectContains(button,mouseX,mouseY),false)
      elseif control.toggle then
        local boxSize=mobile and math.max(27,math.floor(30*scale)) or math.max(18,math.floor(22*scale))
        local box={x=rr.x+rr.w-boxSize-math.max(7,8*scale),y=rr.y+(rr.h-boxSize)*0.5,w=boxSize,h=boxSize}
        hb.toggle=box
        local hover=rectContains(rr,mouseX,mouseY)
        roundedFill(box.x,box.y,box.w,box.h,math.max(4,box.h*0.18),control.checked and SELECTOR_THEME.selected or {0.055,0.09,0.14,1})
        roundedLine(box.x,box.y,box.w,box.h,math.max(4,box.h*0.18),hover and SELECTOR_THEME.accent or SELECTOR_THEME.divider,1)
        if control.checked then
          setRGBA(SELECTOR_THEME.text)
          g.setLineWidth(math.max(2,2*scale))
          g.line(box.x+box.w*0.22,box.y+box.h*0.54,box.x+box.w*0.43,box.y+box.h*0.74,box.x+box.w*0.80,box.y+box.h*0.28)
          g.setLineWidth(1)
        end
      elseif control.choice then
        hb.prev=leftButton; hb.next=rightButton
        drawMiniButton("‹",smallFont,leftButton,rectContains(leftButton,mouseX,mouseY),false)
        drawMiniButton("›",smallFont,rightButton,rectContains(rightButton,mouseX,mouseY),false)
        local choiceBox={x=centerX,y=controlY,w=centerW,h=controlH}
        roundedFill(choiceBox.x,choiceBox.y,choiceBox.w,choiceBox.h,math.max(5,choiceBox.h*0.25),{0.055,0.09,0.14,1})
        drawSelectorText(control.choice,badgeFont,choiceBox.x,
          choiceBox.y+(choiceBox.h-(badgeFont and badgeFont:getHeight() or 10))*0.5,SELECTOR_THEME.text,"center",choiceBox.w)
      else
        hb.minus=leftButton; hb.plus=rightButton
        drawMiniButton("−",smallFont,leftButton,rectContains(leftButton,mouseX,mouseY),false)
        drawMiniButton("+",smallFont,rightButton,rectContains(rightButton,mouseX,mouseY),false)
        local trackH=math.max(5,math.floor(6*scale))
        local track={x=centerX,y=controlY+(controlH-trackH)*0.5,w=centerW,h=trackH}
        hb.track={x=track.x-3*scale,y=controlY,w=track.w+6*scale,h=controlH,trackX=track.x,trackW=track.w}
        roundedFill(track.x,track.y,track.w,track.h,track.h*0.5,{0.12,0.18,0.26,1})
        local frac=((control.value or control.min)-control.min)/math.max(0.0001,control.max-control.min)
        frac=math.max(0,math.min(1,frac))
        roundedFill(track.x,track.y,math.max(track.h,track.w*frac),track.h,track.h*0.5,SELECTOR_THEME.accent)
        local knobX=track.x+track.w*frac
        setRGBA((selectedControl or rectContains(hb.track,mouseX,mouseY)) and SELECTOR_THEME.text or SELECTOR_THEME.muted)
        g.circle("fill",knobX,track.y+track.h*0.5,math.max(4,math.floor(5*scale)))
      end
      hit.controls[#hit.controls+1]=hb
    end

    local settingsScroll=mobile and math.max(32,math.floor(36*scale)) or math.max(18,math.floor(21*scale))
    if mobile then
      -- Phone paging lives in the SETTINGS title bar, not at the panel bottom.
      -- This keeps both arrows reachable even when Gen1Recomp exposes a tiny
      -- 480x320-ish internal viewport and the settings panel overlaps the footer.
      local arrowGap=math.max(3,math.floor(4*scale))
      local downX=settingsX+settingsW-settingsPad-settingsScroll
      local upX=downX-settingsScroll-arrowGap
      if firstControl>1 then
        hit.settingsUp={x=upX,y=settingsY+math.max(2,3*scale),w=settingsScroll,h=settingsScroll}
        drawMiniButton("▲",badgeFont,hit.settingsUp,rectContains(hit.settingsUp,mouseX,mouseY),false)
      end
      if firstControl+visibleControls-1<#controls then
        hit.settingsDown={x=downX,y=settingsY+math.max(2,3*scale),w=settingsScroll,h=settingsScroll}
        drawMiniButton("▼",badgeFont,hit.settingsDown,rectContains(hit.settingsDown,mouseX,mouseY),false)
      end
    else
      if firstControl>1 then
        hit.settingsUp={x=settingsX+settingsW-settingsPad-settingsScroll,y=settingsY+4*scale,w=settingsScroll,h=settingsScroll}
        drawMiniButton("▲",badgeFont,hit.settingsUp,rectContains(hit.settingsUp,mouseX,mouseY),false)
      end
      if firstControl+visibleControls-1<#controls then
        hit.settingsDown={x=settingsX+settingsW-settingsPad-settingsScroll,y=settingsY+settingsH-settingsScroll-4*scale,w=settingsScroll,h=settingsScroll}
        drawMiniButton("▼",badgeFont,hit.settingsDown,rectContains(hit.settingsDown,mouseX,mouseY),false)
      end
    end

    local footerY=py+panelH-footerH
    setRGBA(SELECTOR_THEME.divider)
    g.rectangle("fill",px+pad,footerY,panelW-pad*2,1)

    local buttonH=mobile and math.max(40,math.floor(44*scale)) or math.max(24,math.floor(29*scale))
    local backW=mobile and math.max(78,math.floor(92*scale)) or math.max(68,math.floor(82*scale))
    local applyW=mobile and math.max(128,math.floor(154*scale)) or math.max(112,math.floor(142*scale))
    local fileGap=math.max(5,math.floor(7*scale))
    local buttonY=footerY+footerH-buttonH-math.max(5,math.floor(6*scale))
    hit.back={x=px+pad,y=buttonY,w=backW,h=buttonH}
    hit.apply={x=px+panelW-pad-applyW,y=buttonY,w=applyW,h=buttonH}
    local fileStart=hit.back.x+hit.back.w+fileGap
    local fileEnd=hit.apply.x-fileGap
    local fileW=math.max(56,math.min(math.floor(104*scale),(fileEnd-fileStart-fileGap)*0.5))
    hit.export={x=fileStart,y=buttonY,w=fileW,h=buttonH}
    hit.import={x=fileStart+fileW+fileGap,y=buttonY,w=fileW,h=buttonH}
    drawMiniButton("BACK",smallFont,hit.back,rectContains(hit.back,mouseX,mouseY),false)
    drawMiniButton("EXPORT",smallFont,hit.export,rectContains(hit.export,mouseX,mouseY),false)
    drawMiniButton("IMPORT",smallFont,hit.import,rectContains(hit.import,mouseX,mouseY),false)
    local isActive=item and item.characterId==active
    local applyLabel=isActive and "CURRENT SKIN" or "USE THIS SKIN"
    drawMiniButton(applyLabel,smallFont,hit.apply,rectContains(hit.apply,mouseX,mouseY),not isActive)

    local controllerLines=mobile and 0 or drawControllerHints(badgeFont,px+pad,footerY+math.max(4,math.floor(6*scale)),panelW-pad*2,scale,belleControls)
    local hint=menu._red3dSkinFileStatus
    if not hint then
      if menu and menu._red3dRigEditor then
        hint="Rigger: align joints in Front View • choose Weight Style • Update Preview • Save to Character Selector"
      elseif menu and menu._red3dCharacterImporter then
        hint="Character Import: drop OBJ/FBX/DAE or ZIP • choose Bellestarmon donor rig • CLONE RIG + IMPORT"
      elseif menu and menu._red3dAccessoryEditor then
        hint=mobile and "Accessories: tap controls to place/rotate/scale • drag preview to inspect"
          or "Accessories: choose texture + UV fixes • tune X/Y/Z, scale and rotation • mouse wheel zooms preview"
      else
        hint=mobile and "Touch: tap settings • use ▲/▼ to page controls • drag preview • pinch zoom"
          or "Mouse: LMB/MMB orbit • RMB/Shift+MMB pan • wheel over model zooms • wheel over settings browses • Home resets view"
      end
    end
    local hintOffset=mobile and math.max(5,math.floor(7*scale))
      or ((controllerLines>1) and math.max(43,math.floor(48*scale)) or math.max(24,math.floor(28*scale)))
    drawSelectorText(hint,badgeFont,px+pad,footerY+hintOffset,SELECTOR_THEME.muted,
      "center",math.max(1,panelW-pad*2))

    -- Cursor feedback. The engine already exposes real mouse coordinates in the
    -- same window space as render.hud, so hit tests remain pixel-accurate.
    local interactive=rectContains(hit.back,mouseX,mouseY) or rectContains(hit.apply,mouseX,mouseY)
      or rectContains(hit.export,mouseX,mouseY) or rectContains(hit.import,mouseX,mouseY) or modelHover
      or rectContains(hit.listUp,mouseX,mouseY) or rectContains(hit.listDown,mouseX,mouseY)
      or rectContains(hit.settingsUp,mouseX,mouseY) or rectContains(hit.settingsDown,mouseX,mouseY)
      or rectContains(hit.touchOrbit,mouseX,mouseY) or rectContains(hit.touchPan,mouseX,mouseY)
      or rectContains(hit.touchZoomOut,mouseX,mouseY) or rectContains(hit.touchZoomIn,mouseX,mouseY)
      or rectContains(hit.touchReset,mouseX,mouseY)
    for _,r in ipairs(hit.characterRows) do if rectContains(r,mouseX,mouseY) then interactive=true break end end
    if not interactive then
      for _,j in ipairs(hit.rigJoints or {}) do
        if rectContains(j,mouseX,mouseY) then interactive=true break end
      end
    end
    if not interactive then
      for _,c in ipairs(hit.controls) do
        if rectContains(c.row,mouseX,mouseY) then interactive=true break end
      end
    end
    menu._red3dMouseHover=interactive
    if menu._red3dRigJointDragging then
      setSelectorCursor("sizeall")
    elseif menu._red3dModelDragging then
      setSelectorCursor("sizewe")
    elseif interactive then
      setSelectorCursor("hand")
    else
      setSelectorCursor("arrow")
    end

    -- Always render a mod-owned cursor last. This fixes hosts where mouse
    -- coordinates/clicks work but the captured native pointer never appears.
    if (not mobile) and mouseX and mouseY and mouseX>=vx and mouseY>=vy and mouseX<=vx+vw and mouseY<=vy+vh then
      drawSelectorCursor(mouseX,mouseY,scale,interactive,menu._red3dModelDragging==true)
    end

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
          local displayName=characterDisplayName(id)
          items[#items+1]={
            label=displayName,
            previewLabel=displayName,
            fullLabel=displayName,
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
      menu.footer="D-PAD TURN  A USE  B BACK"
      menu.index=activeIndex
      menu.scroll=math.max(0,activeIndex-(menu.rows or 8))
      menu._red3dSkinSelector=true
      menu._red3dTouchMode=SELECTOR_THEME.hostIsPhone()
      menu._red3dTouchCameraMode="orbit"
      menu._red3dTouches={}
      menu._red3dViewer=(SkinSelectorViewer and SkinSelectorViewer.new)
        and SkinSelectorViewer.new() or nil

      if love and love.mouse then
        if love.mouse.isVisible then
          local ok,visible=pcall(love.mouse.isVisible)
          if ok then menu._red3dMouseWasVisible=visible end
        end
        if love.mouse.isGrabbed then
          local ok,grabbed=pcall(love.mouse.isGrabbed)
          if ok then menu._red3dMouseWasGrabbed=grabbed end
        end
        if love.mouse.getRelativeMode then
          local ok,relative=pcall(love.mouse.getRelativeMode)
          if ok then menu._red3dMouseWasRelative=relative end
        end
        if love.mouse.getPosition then
          local ok,mx,my=pcall(love.mouse.getPosition)
          if ok then menu._red3dMouseX,menu._red3dMouseY=mx,my end
        end
      end
      menu._red3dWindowFocused=selectorWindowHasFocus()
      selectorApplyFocusMouseState(menu,menu._red3dWindowFocused)

      local baseClose=menu.close
      menu.close=function(self,...)
        selectorCancelMouseInteraction(self)
        setSelectorCursor("arrow")
        if love and love.mouse then
          if love.mouse.setVisible and self._red3dMouseWasVisible~=nil then
            pcall(love.mouse.setVisible,self._red3dMouseWasVisible)
          end
          if love.mouse.setRelativeMode and self._red3dMouseWasRelative~=nil then
            pcall(love.mouse.setRelativeMode,self._red3dMouseWasRelative)
          end
          if love.mouse.setGrabbed and self._red3dMouseWasGrabbed~=nil then
            pcall(love.mouse.setGrabbed,self._red3dMouseWasGrabbed)
          end
        end
        return baseClose(self,...)
      end

      local function highlightedId(self)
        local item=self.items and self.items[self.index or 1]
        return item and item.characterId or nil,item
      end

      local function chooseHighlighted(self)
        local id=highlightedId(self)
        if id then applyCharacter(id) end
        self:close()
      end

      local function rebuildSkinItems(self,keepId)
        keepId=keepId or highlightedId(self)
        local activeNow=renderer.activeId or "RED"
        local items={}
        local index=1
        for _,id in ipairs(CHARACTER_ORDER) do
          if renderers[id] and CHARACTER_DEFS[id] then
            local displayName=characterDisplayName(id)
            items[#items+1]={
              label=displayName,
              previewLabel=displayName,
              fullLabel=displayName,
              characterId=id,
              right=(id==activeNow) and "ACTIVE" or nil,
            }
            if id==keepId then index=#items end
          end
        end
        self.items=items
        self.index=math.max(1,math.min(#items,index))
        self.scroll=math.max(0,self.index-(self.rows or 8))
        self._red3dControlIndex=1
        self._red3dLastControlCharacter=nil
        if self._red3dViewer and type(self._red3dViewer.invalidate)=="function" then self._red3dViewer:invalidate() end
      end
      menu._red3dRebuildSkinItems=rebuildSkinItems

      local function setTrackFromMouse(self,controlHit,x)
        if not controlHit or not controlHit.track then return end
        local id=highlightedId(self)
        if not id then return end
        local track=controlHit.track
        local frac=(x-track.trackX)/math.max(1,track.trackW)
        setSelectorControlFraction(id,controlHit.index,frac,self._red3dViewer,self)
      end

      menu._red3dHandlePointer=function(self,event)
        if type(event)~="table" then return false end
        self._red3dSawPointerHook=true
        local phase=event.phase
        local x,y=tonumber(event.x),tonumber(event.y)
        if not x or not y then return true end
        self._red3dMouseX,self._red3dMouseY=x,y
        local hit=self._red3dMouseUI
        if not hit then return true end
        local isPhone=SELECTOR_THEME.hostIsPhone()
        if (not isPhone) and event.source=="touch" then
          event.source="mouse"
          if event.button==nil then event.button=1 end
        end
        local isTouch=(event.source=="touch" and isPhone)
        local touchId=nil
        if isTouch then
          self._red3dTouchMode=true
          self._red3dTouches=self._red3dTouches or {}
          touchId=SELECTOR_THEME.touchId(event)
          if phase=="pressed" then
            self._red3dTouches[touchId]={x=x,y=y,lastX=x,lastY=y,model=false}
          end
        end

        if self._red3dRenameEditingId then
          if phase=="pressed" and rectContains(hit.back,x,y) then cancelCharacterRename(self) end
          return true
        end

        -- v3.0.21: right-click is reserved for viewport panning and is never
        -- treated as Back/close. All mouse buttons are consumed by this modal.

        -- Pointer backends are not fully consistent about movement deltas.
        -- Always derive preview rotation from absolute cursor X when possible,
        -- then fall back to event.dx.  Also accept alternate move phase names
        -- used by some hosts/touch bridges.
        local isMovePhase=(phase=="moved" or phase=="move" or phase=="dragged")
        if isMovePhase then
          if isTouch then
            local touches=self._red3dTouches or {}
            local t=touches[touchId]
            if not t then
              t={x=x,y=y,lastX=x,lastY=y,model=rectContains(hit.model,x,y)}
              touches[touchId]=t
            end
            local oldX,oldY=tonumber(t.x) or x,tonumber(t.y) or y
            t.lastX,t.lastY=oldX,oldY
            t.x,t.y=x,y
            if t.model and self._red3dViewer then
              local modelTouches={}
              for _,candidate in pairs(touches) do
                if candidate and candidate.model then modelTouches[#modelTouches+1]=candidate end
              end
              if #modelTouches>=2 then
                local a,b=modelTouches[1],modelTouches[2]
                local dx=(b.x or 0)-(a.x or 0)
                local dy=(b.y or 0)-(a.y or 0)
                local dist=math.sqrt(dx*dx+dy*dy)
                local midX=((a.x or 0)+(b.x or 0))*0.5
                local midY=((a.y or 0)+(b.y or 0))*0.5
                local prev=self._red3dTouchPinch
                if prev and type(self._red3dViewer.zoomBy)=="function" then
                  local zoomDelta=(dist-(prev.dist or dist))/math.max(42,70)
                  if math.abs(zoomDelta)>0.002 then self._red3dViewer:zoomBy(zoomDelta) end
                end
                if prev and type(self._red3dViewer.panBy)=="function" then
                  self._red3dViewer:panBy(midX-(prev.midX or midX),midY-(prev.midY or midY))
                end
                self._red3dTouchPinch={dist=dist,midX=midX,midY=midY}
                self._red3dModelDragging=true
                self._red3dModelDragMode="touch-pinch"
                if type(self._red3dViewer.setDragging)=="function" then self._red3dViewer:setDragging(true) end
              else
                self._red3dTouchPinch=nil
                local moveX=x-oldX
                local moveY=y-oldY
                local mode=self._red3dTouchCameraMode or "orbit"
                if mode=="pan" and type(self._red3dViewer.panBy)=="function" then
                  self._red3dViewer:panBy(moveX,moveY)
                elseif type(self._red3dViewer.orbitBy)=="function" then
                  self._red3dViewer:orbitBy(moveX,moveY)
                end
                self._red3dModelDragging=true
                self._red3dModelDragMode=mode
                self._red3dModelDragLastX=x
                self._red3dModelDragLastY=y
                if type(self._red3dViewer.setDragging)=="function" then self._red3dViewer:setDragging(true) end
              end
              self._red3dSuppressNativeMenuFrames=math.max(tonumber(self._red3dSuppressNativeMenuFrames) or 0,2)
              return true
            end
          end
          if self._red3dBreastAreaDragging and hit.model then
            local id=self._red3dBreastAreaEditorId
            local child=id and renderers[id] or nil
            if child and child.data then
              local fx=(x-hit.model.x)/math.max(1,hit.model.w)
              local fy=(y-hit.model.y)/math.max(1,hit.model.h)
              local side=self._red3dBreastAreaDragging
              fy=math.max(0.06,math.min(0.70,fy))
              if side=="right" then
                fx=math.max(0.51,math.min(0.94,fx))
                child.data.runtimeBelleBreastAreaRightX=fx; child.data.runtimeBelleBreastAreaRightY=fy
                if mod.save and mod.save.set then
                  mod.save:set(red3dBreastAreaSaveKey(id,"right_x"),fx); mod.save:set(red3dBreastAreaSaveKey(id,"right_y"),fy)
                end
              else
                fx=math.max(0.06,math.min(0.49,fx))
                child.data.runtimeBelleBreastAreaLeftX=fx; child.data.runtimeBelleBreastAreaLeftY=fy
                if mod.save and mod.save.set then
                  mod.save:set(red3dBreastAreaSaveKey(id,"left_x"),fx); mod.save:set(red3dBreastAreaSaveKey(id,"left_y"),fy)
                end
              end
              child.skinKey=nil; child.voxelUploadedKey=nil; child.voxelFrameKey=nil
            end
          elseif self._red3dRigJointDragging then
            local d=self._red3dRigJointDragging
            local fx=(x-(d.screenX or 0))/math.max(1,d.screenW or 1)
            local fy=(y-(d.screenY or 0))/math.max(1,d.screenH or 1)
            fx=math.max(0,math.min(1,fx)); fy=math.max(0,math.min(1,fy))
            local mx=(d.minX or 0)+fx*(d.spanX or 1)
            local my=(d.minY or 0)+(1-fy)*(d.spanY or 1)
            if d.sourceId and d.name then
              setRigJointCoord(d.sourceId,d.name,1,mx)
              setRigJointCoord(d.sourceId,d.name,2,my)
              self._red3dRigPreviewDirty=true
              if self._red3dViewer and type(self._red3dViewer.invalidate)=="function" then self._red3dViewer:invalidate() end
            end
          elseif self._red3dControlDragging then
            setTrackFromMouse(self,self._red3dControlDragging,x)
          elseif self._red3dModelDragging and self._red3dViewer then
            local lastX=tonumber(self._red3dModelDragLastX)
            local dx=(lastX and (x-lastX)) or (tonumber(event.dx) or 0)
            -- If a host reports a stationary absolute coordinate but a useful
            -- relative delta, keep that as a compatibility fallback.
            if math.abs(dx)<0.0001 then dx=tonumber(event.dx) or 0 end
            local lastY=tonumber(self._red3dModelDragLastY)
            local dy=(lastY and (y-lastY)) or (tonumber(event.dy) or 0)
            if math.abs(dy)<0.0001 then dy=tonumber(event.dy) or 0 end
            local mode=self._red3dModelDragMode or "orbit"
            if mode=="pan" and type(self._red3dViewer.panBy)=="function" then
              self._red3dViewer:panBy(dx,dy)
            elseif type(self._red3dViewer.orbitBy)=="function" then
              self._red3dViewer:orbitBy(dx,dy)
            elseif math.abs(dx)>0.0001 then
              self._red3dViewer:nudge(dx*0.014)
            end
            self._red3dModelDragLastX=x
            self._red3dModelDragLastY=y
            self._red3dSuppressNativeMenuFrames=math.max(tonumber(self._red3dSuppressNativeMenuFrames) or 0,2)
          end
          return true
        elseif phase=="released" or phase=="cancelled" then
          if isTouch then
            local touches=self._red3dTouches or {}
            touches[touchId]=nil
            local remaining=nil
            local count=0
            for _,candidate in pairs(touches) do
              if candidate and candidate.model then count=count+1; remaining=candidate end
            end
            if phase=="cancelled" or count==0 then
              selectorCancelMouseInteraction(self)
            else
              self._red3dTouchPinch=nil
              self._red3dModelDragging=true
              self._red3dModelDragMode=self._red3dTouchCameraMode or "orbit"
              self._red3dModelDragLastX=remaining and remaining.x or nil
              self._red3dModelDragLastY=remaining and remaining.y or nil
              if self._red3dViewer and type(self._red3dViewer.setDragging)=="function" then
                self._red3dViewer:setDragging(true)
              end
            end
          else
            selectorCancelMouseInteraction(self)
          end
          -- Gen1Recomp emits pointer `cancelled` on focus/visibility loss. If
          -- that is why this pointer died, immediately give the OS its cursor
          -- back instead of waiting for another selector frame.
          if phase=="cancelled" then
            local focused=selectorWindowHasFocus()
            self._red3dWindowFocused=focused
            if not focused then selectorApplyFocusMouseState(self,false) end
          end
          -- Keep the hidden native ListMenu muted briefly through mouse-up too;
          -- some input backends publish their synthetic menu action on release.
          if event.source=="mouse" or event.source=="touch" then
            self._red3dSuppressNativeMenuFrames=math.max(tonumber(self._red3dSuppressNativeMenuFrames) or 0,2)
          end
          return true
        elseif phase~="pressed" then
          return true
        end

        -- Left, right, and middle mouse buttons are all owned by the selector.
        -- Right-click must never leak into the hidden native ListMenu as B/Back.
        local mouseButton=tonumber(event.button) or 1
        if event.source=="mouse" and mouseButton~=1 and mouseButton~=2 and mouseButton~=3 then return true end

        -- Gen1Recomp can mirror mouse buttons into native menu actions. Suppress
        -- that hidden ListMenu for every selector mouse press, not only left-click.
        if event.source=="mouse" or event.source=="touch" then
          self._red3dSuppressNativeMenuFrames=4
        end

        -- Non-left mouse buttons are viewport tools only. They never activate
        -- Back/Apply/settings hitboxes, so right-click cannot close the menu.
        if event.source=="mouse" and mouseButton~=1 then
          if rectContains(hit.model,x,y) then
            self._red3dModelDragging=true
            self._red3dModelDragButton=mouseButton
            local shift=false
            if love and love.keyboard and love.keyboard.isDown then
              local okShift,v=pcall(love.keyboard.isDown,"lshift","rshift")
              shift=okShift and v==true
            end
            self._red3dModelDragMode=(mouseButton==2 or (mouseButton==3 and shift)) and "pan" or "orbit"
            self._red3dModelDragLastX=x
            self._red3dModelDragLastY=y
            if self._red3dViewer and type(self._red3dViewer.setDragging)=="function" then
              self._red3dViewer:setDragging(true)
            end
          end
          return true
        end

        if rectContains(hit.back,x,y) then
          self:close()
          return true
        end
        if rectContains(hit.apply,x,y) then
          chooseHighlighted(self)
          return true
        end
        if rectContains(hit.export,x,y) then
          local id=highlightedId(self)
          local ok,message=exportSkinPackage(id)
          self._red3dSkinFileStatus=ok and ("Exported: "..tostring(message)) or tostring(message)
          return true
        end
        if rectContains(hit.import,x,y) then
          local keep=highlightedId(self)
          local loaded,failed,folder=importSkinPackages()
          rebuildSkinItems(self,keep)
          if loaded>0 then
            self._red3dSkinFileStatus="Imported "..loaded.." skin"..((loaded==1) and "" or "s")..". Folder: "..tostring(folder)
          elseif failed>0 then
            self._red3dSkinFileStatus="No skins loaded; "..failed.." package"..((failed==1) and "" or "s").." failed. Folder: "..tostring(folder)
          else
            self._red3dSkinFileStatus="No new .red3dskin files. Put packages in: "..tostring(folder)
          end
          return true
        end
        if rectContains(hit.listUp,x,y) then
          self.index=math.max(1,(tonumber(self.index) or 1)-1)
          self._red3dControlIndex=1
          return true
        end
        if rectContains(hit.listDown,x,y) then
          self.index=math.min(#(self.items or {}),(tonumber(self.index) or 1)+1)
          self._red3dControlIndex=1
          return true
        end
        if rectContains(hit.settingsUp,x,y) then
          self._red3dControlIndex=math.max(1,(tonumber(self._red3dControlIndex) or 1)-1)
          if SELECTOR_THEME.mobileMode(self) then self._red3dSettingsFirstControl=self._red3dControlIndex end
          return true
        end
        if rectContains(hit.settingsDown,x,y) then
          local id=highlightedId(self)
          local maxControls=#selectorControlsFor({characterId=id},renderers[id],self)
          self._red3dControlIndex=math.min(maxControls,(tonumber(self._red3dControlIndex) or 1)+1)
          if SELECTOR_THEME.mobileMode(self) then self._red3dSettingsFirstControl=self._red3dControlIndex end
          return true
        end
        if rectContains(hit.touchOrbit,x,y) then
          self._red3dTouchCameraMode="orbit"
          return true
        end
        if rectContains(hit.touchPan,x,y) then
          self._red3dTouchCameraMode="pan"
          return true
        end
        if rectContains(hit.touchZoomOut,x,y) then
          if self._red3dViewer and type(self._red3dViewer.zoomBy)=="function" then self._red3dViewer:zoomBy(-1) end
          return true
        end
        if rectContains(hit.touchZoomIn,x,y) then
          if self._red3dViewer and type(self._red3dViewer.zoomBy)=="function" then self._red3dViewer:zoomBy(1) end
          return true
        end
        if rectContains(hit.touchReset,x,y) then
          if self._red3dViewer and type(self._red3dViewer.resetView)=="function" then self._red3dViewer:resetView() end
          return true
        end

        if self._red3dRigEditor then
          for _,j in ipairs(hit.rigJoints or {}) do
            if rectContains(j,x,y) then
              self._red3dRigJointIndex=j.index or self._red3dRigJointIndex
              self._red3dRigJointDragging=j
              self._red3dControlIndex=4 -- JOINT row in the rigger control list.
              if self._red3dViewer and type(self._red3dViewer.resetView)=="function" then
                -- Marker overlay is a front-view editing plane. Snap to front
                -- when direct-manipulating a marker so the dot and mesh agree.
                self._red3dViewer:resetView()
              end
              return true
            end
          end
        end

        for _,r in ipairs(hit.characterRows or {}) do
          if rectContains(r,x,y) then
            if self.index~=r.index then
              self.index=r.index
              self.scroll=math.max(0,r.index-(self.rows or 8))
              self._red3dControlIndex=1
              self._red3dSettingsFirstControl=1
              self._red3dSettingsWheelBrowsing=false
              self._red3dBreastAreaEditorId=nil
              self._red3dLastControlCharacter=nil
              if self._red3dViewer and type(self._red3dViewer.invalidate)=="function" then self._red3dViewer:invalidate() end
            end
            return true
          end
        end

        for _,c in ipairs(hit.controls or {}) do
          if rectContains(c.row,x,y) then
            self._red3dSettingsWheelBrowsing=false
            self._red3dControlIndex=c.index
            local id=highlightedId(self)
            if c.button then
              adjustSelectorControl(id,c.index,1,self._red3dViewer,self)
            elseif c.toggle then
              adjustSelectorControl(id,c.index,1,self._red3dViewer,self)
            elseif rectContains(c.prev,x,y) or rectContains(c.minus,x,y) then
              adjustSelectorControl(id,c.index,-1,self._red3dViewer,self)
            elseif rectContains(c.next,x,y) or rectContains(c.plus,x,y) then
              adjustSelectorControl(id,c.index,1,self._red3dViewer,self)
            elseif rectContains(c.track,x,y) then
              self._red3dControlDragging=c
              setTrackFromMouse(self,c,x)
            end
            return true
          end
        end

        if rectContains(hit.model,x,y) and self._red3dBreastAreaEditorId then
          local id=self._red3dBreastAreaEditorId
          local child=id and renderers[id] or nil
          if child and child.data then
            local side=nil
            local function insideCircle(c)
              if not c then return false end
              local dx,dy=x-c.cx,y-c.cy
              return dx*dx+dy*dy<=c.r*c.r
            end
            if insideCircle(hit.breastAreaLeft) then side="left"
            elseif insideCircle(hit.breastAreaRight) then side="right"
            else side=(x<(hit.model.x+hit.model.w*0.5)) and "left" or "right" end
            self._red3dBreastAreaActiveSide=side
            local fx=(x-hit.model.x)/math.max(1,hit.model.w)
            local fy=math.max(0.06,math.min(0.70,(y-hit.model.y)/math.max(1,hit.model.h)))
            if side=="right" then
              fx=math.max(0.51,math.min(0.94,fx))
              child.data.runtimeBelleBreastAreaRightX=fx; child.data.runtimeBelleBreastAreaRightY=fy
              if mod.save and mod.save.set then
                mod.save:set(red3dBreastAreaSaveKey(id,"right_x"),fx); mod.save:set(red3dBreastAreaSaveKey(id,"right_y"),fy)
              end
            else
              fx=math.max(0.06,math.min(0.49,fx))
              child.data.runtimeBelleBreastAreaLeftX=fx; child.data.runtimeBelleBreastAreaLeftY=fy
              if mod.save and mod.save.set then
                mod.save:set(red3dBreastAreaSaveKey(id,"left_x"),fx); mod.save:set(red3dBreastAreaSaveKey(id,"left_y"),fy)
              end
            end
            child.skinKey=nil; child.voxelUploadedKey=nil; child.voxelFrameKey=nil
            self._red3dBreastAreaDragging=side
            return true
          end
        end
        if rectContains(hit.model,x,y) then
          self._red3dModelDragging=true
          self._red3dModelDragButton=(event.source=="mouse") and mouseButton or 1
          if isTouch then
            local t=self._red3dTouches and self._red3dTouches[touchId] or nil
            if t then t.model=true; t.x=x; t.y=y; t.lastX=x; t.lastY=y end
          end
          local shift=false
          if love and love.keyboard and love.keyboard.isDown then
            local okShift,v=pcall(love.keyboard.isDown,"lshift","rshift")
            shift=okShift and v==true
          end
          -- Blender-like viewport mapping, while preserving the existing easy
          -- left-drag orbit: LMB/MMB orbit; RMB or Shift+MMB pans.
          if isTouch then
            self._red3dModelDragMode=self._red3dTouchCameraMode or "orbit"
          elseif self._red3dModelDragButton==2 or (self._red3dModelDragButton==3 and shift) then
            self._red3dModelDragMode="pan"
          else
            self._red3dModelDragMode="orbit"
          end
          self._red3dModelDragLastX=x
          self._red3dModelDragLastY=y
          if self._red3dViewer and type(self._red3dViewer.setDragging)=="function" then
            self._red3dViewer:setDragging(true)
          end
          return true
        end
        return true
      end

      local baseUpdate=menu.update
      menu.update=function(self,dt)
        local input=self.game and self.game.input
        local viewer=self._red3dViewer

        -- Alt-Tab / multi-monitor safety. LÖVE keeps updating on desktop while
        -- unfocused, so detect both edges here even when no mouse button was
        -- down (and therefore Gen1Recomp had no pointer to cancel).
        local focused=selectorWindowHasFocus()
        if self._red3dWindowFocused==nil or focused~=self._red3dWindowFocused then
          self._red3dWindowFocused=focused
          selectorApplyFocusMouseState(self,focused)
          self._red3dScaleDecWasDown=false
          self._red3dScaleIncWasDown=false
          self._red3dSliderCycleWasDown=false
          self._red3dDirectSliderWasDown=false
          self._red3dExportWasDown=false
          self._red3dImportWasDown=false
          self._red3dResetViewWasDown=false
        end
        if not focused then
          -- Never poll buttons/coordinates while the pointer is on another
          -- monitor. This also prevents a button held in another app from being
          -- mistaken for a selector drag when focus comes back.
          return
        end

        -- A host may reapply cursor capture when focus is regained. The Skin
        -- Selector is a desktop pointer UI, so keep capture disabled while open.
        selectorReleaseMouseCapture()

        -- Text-entry mode owns keyboard input completely. This prevents the
        -- hidden ListMenu from interpreting Enter/Escape while a character name
        -- is being edited.
        if self._red3dRenameEditingId then
          processCharacterRenameInput(self)
          return
        end

        if viewer and input then
          if input:wasPressed("left") then viewer:nudge(-math.rad(18)) end
          if input:wasPressed("right") then viewer:nudge(math.rad(18)) end
        end

        local resetViewDown=false
        if love and love.keyboard and love.keyboard.isDown then
          resetViewDown=love.keyboard.isDown("home")
        end
        if resetViewDown and not self._red3dResetViewWasDown and viewer and type(viewer.resetView)=="function" then
          viewer:resetView()
        end
        self._red3dResetViewWasDown=resetViewDown

        -- Controls are edge-triggered. Every character exposes Size in the same
        -- right-side panel; Belle exposes PHYSICS, and shows the BREAST PHYSICS slider only while PHYSICS is checked. Tab/L3 cycles
        -- rows and X/Y or -/+ adjusts/toggles the selected control.
        local decDown=false
        local incDown=false
        local cycleDown=false
        local exportDown=false
        local importDown=false
        local directIndex=nil
        if love and love.keyboard and love.keyboard.isDown then
          decDown=love.keyboard.isDown("-") or love.keyboard.isDown("kp-") or love.keyboard.isDown("[")
          incDown=love.keyboard.isDown("=") or love.keyboard.isDown("kp+") or love.keyboard.isDown("]")
          cycleDown=love.keyboard.isDown("tab")
          if love.keyboard.isDown("1") then directIndex=1
          elseif love.keyboard.isDown("2") then directIndex=2
          elseif love.keyboard.isDown("3") then directIndex=3
          elseif love.keyboard.isDown("4") then directIndex=4
          elseif love.keyboard.isDown("5") then directIndex=5
          elseif love.keyboard.isDown("6") then directIndex=6
          elseif love.keyboard.isDown("7") then directIndex=7
          elseif love.keyboard.isDown("8") then directIndex=8
          elseif love.keyboard.isDown("9") then directIndex=9
          elseif love.keyboard.isDown("0") then directIndex=10 end
        end
        if love and love.joystick and love.joystick.getJoysticks then
          local sticks=love.joystick.getJoysticks() or {}
          for _,stick in ipairs(sticks) do
            if stick and stick.isGamepadDown then
              local okX,x=pcall(stick.isGamepadDown,stick,"x")
              local okY,y=pcall(stick.isGamepadDown,stick,"y")
              local okL3,l3=pcall(stick.isGamepadDown,stick,"leftstick")
              local okLB,lb=pcall(stick.isGamepadDown,stick,"leftshoulder")
              local okRB,rb=pcall(stick.isGamepadDown,stick,"rightshoulder")
              if okX and x then decDown=true end
              if okY and y then incDown=true end
              if okL3 and l3 then cycleDown=true end
              if okLB and lb then exportDown=true end
              if okRB and rb then importDown=true end
            end
          end
        end
        local id=highlightedId(self)
        if id~=self._red3dLastControlCharacter then
          self._red3dLastControlCharacter=id
          self._red3dControlIndex=1
        end
        if exportDown and not self._red3dExportWasDown then
          local ok,message=exportSkinPackage(id)
          self._red3dSkinFileStatus=ok and ("Exported: "..tostring(message)) or tostring(message)
        end
        self._red3dExportWasDown=exportDown
        if importDown and not self._red3dImportWasDown then
          local keep=id
          local loaded,failed,folder=importSkinPackages()
          rebuildSkinItems(self,keep)
          if loaded>0 then
            self._red3dSkinFileStatus="Imported "..loaded.." skin"..((loaded==1) and "" or "s")..". Folder: "..tostring(folder)
          elseif failed>0 then
            self._red3dSkinFileStatus="No skins loaded; "..failed.." package"..((failed==1) and "" or "s").." failed. Folder: "..tostring(folder)
          else
            self._red3dSkinFileStatus="No new .red3dskin files. Put packages in: "..tostring(folder)
          end
          id=highlightedId(self)
        end
        self._red3dImportWasDown=importDown
        local maxControls=#selectorControlsFor({characterId=id},renderers[id],self)
        if directIndex and renderers[id] and renderers[id].behaviorId=="BELLESTARMON" and directIndex<=maxControls and not self._red3dDirectSliderWasDown then
          self._red3dControlIndex=directIndex
        end
        self._red3dDirectSliderWasDown=(directIndex~=nil)
        if cycleDown and not self._red3dSliderCycleWasDown then
          self._red3dControlIndex=((tonumber(self._red3dControlIndex) or 1)%maxControls)+1
        end
        self._red3dSliderCycleWasDown=cycleDown
        local controlIndex=tonumber(self._red3dControlIndex) or 1
        if controlIndex>maxControls then controlIndex=1; self._red3dControlIndex=1 end
        if decDown and not self._red3dScaleDecWasDown then adjustSelectorControl(id,controlIndex,-1,viewer,self) end
        if incDown and not self._red3dScaleIncWasDown then adjustSelectorControl(id,controlIndex,1,viewer,self) end
        self._red3dScaleDecWasDown=decDown
        self._red3dScaleIncWasDown=incDown

        -- A rename can be entered by a controller/keyboard settings action in
        -- this same update. Do not pass that initiating button through to the
        -- hidden native ListMenu on the frame text entry begins.
        if self._red3dRenameEditingId then return end

        -- Compatibility fallback for pre-pointer-hook engine builds: poll a real
        -- desktop mouse click. Current Gen1Recomp uses input.pointer, so this path
        -- stays dormant there and cannot double-fire.
        if not SELECTOR_THEME.mobileMode(self) and not self._red3dSawPointerHook and love and love.mouse and love.mouse.getPosition and love.mouse.isDown then
          local button=nil
          if love.mouse.isDown(1) then button=1 elseif love.mouse.isDown(2) then button=2 elseif love.mouse.isDown(3) then button=3 end
          local down=(button~=nil)
          local mx,my=love.mouse.getPosition()
          local previousButton=self._red3dPolledMouseButton
          if down and not self._red3dPolledMouseDown then
            self:_red3dHandlePointer({phase="pressed",source="mouse",button=button,x=mx,y=my,dx=0,dy=0})
            self._red3dSawPointerHook=false
          elseif down and self._red3dPolledMouseDown and previousButton==button and (self._red3dControlDragging or self._red3dModelDragging) then
            self:_red3dHandlePointer({phase="moved",source="mouse",button=button,x=mx,y=my,dx=mx-(self._red3dPollX or mx),dy=my-(self._red3dPollY or my)})
            self._red3dSawPointerHook=false
          elseif (not down) and self._red3dPolledMouseDown then
            self:_red3dHandlePointer({phase="released",source="mouse",button=previousButton or 1,x=mx,y=my,dx=0,dy=0})
            self._red3dSawPointerHook=false
          elseif down and self._red3dPolledMouseDown and previousButton~=button then
            self:_red3dHandlePointer({phase="released",source="mouse",button=previousButton or 1,x=mx,y=my,dx=0,dy=0})
            self:_red3dHandlePointer({phase="pressed",source="mouse",button=button,x=mx,y=my,dx=0,dy=0})
            self._red3dSawPointerHook=false
          end
          self._red3dPolledMouseDown=down
          self._red3dPolledMouseButton=button
          self._red3dPollX,self._red3dPollY=mx,my
        end

        -- Drag safety net for current pointer-hook builds too. Some hosts emit
        -- button press/release through input.pointer but do not provide usable
        -- move deltas while a captured mouse button is held. Polling absolute
        -- position here makes model rotation and slider dragging independent of
        -- that backend detail. Because both paths update the same last-X state,
        -- a normal pointer-move event and this poll cannot rotate twice.
        if (not SELECTOR_THEME.mobileMode(self)) and love and love.mouse and love.mouse.getPosition and love.mouse.isDown
            and (self._red3dModelDragging or self._red3dControlDragging) then
          local heldButton=self._red3dControlDragging and 1 or (tonumber(self._red3dModelDragButton) or 1)
          local okHeld,held=pcall(love.mouse.isDown,heldButton)
          local okPos,mx,my=pcall(love.mouse.getPosition)
          if okHeld and held and okPos and mx and my then
            self._red3dMouseX,self._red3dMouseY=mx,my
            if self._red3dControlDragging then
              setTrackFromMouse(self,self._red3dControlDragging,mx)
            elseif self._red3dModelDragging and viewer then
              local lastX=tonumber(self._red3dModelDragLastX)
              local lastY=tonumber(self._red3dModelDragLastY)
              local dx=lastX and (mx-lastX) or 0
              local dy=lastY and (my-lastY) or 0
              if self._red3dModelDragMode=="pan" and type(viewer.panBy)=="function" then
                viewer:panBy(dx,dy)
              elseif type(viewer.orbitBy)=="function" then
                viewer:orbitBy(dx,dy)
              elseif math.abs(dx)>0.0001 then
                viewer:nudge(dx*0.014)
              end
              self._red3dModelDragLastX=mx
              self._red3dModelDragLastY=my
            end
          elseif okHeld and not held then
            selectorCancelMouseInteraction(self)
          end
        end

        -- A mouse/touch press can be mirrored by the engine into the hidden
        -- ListMenu's A/B input state.  Do not let that duplicate input reach the
        -- native menu; otherwise an ordinary left-click can invoke onChoose and
        -- close the selector.  Three frames covers either event/update ordering
        -- without affecting normal keyboard/controller navigation afterward.
        local suppressFrames=tonumber(self._red3dSuppressNativeMenuFrames) or 0
        local mouseButtonHeld=false
        if (not SELECTOR_THEME.mobileMode(self)) and love and love.mouse and love.mouse.isDown then
          local ok1,h1=pcall(love.mouse.isDown,1)
          local ok2,h2=pcall(love.mouse.isDown,2)
          local ok3,h3=pcall(love.mouse.isDown,3)
          mouseButtonHeld=(ok1 and h1==true) or (ok2 and h2==true) or (ok3 and h3==true)
        end
        if suppressFrames>0 or mouseButtonHeld then
          if suppressFrames>0 then self._red3dSuppressNativeMenuFrames=suppressFrames-1 end
          return
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

  -- Gen1Recomp 0.1.69+ exposes real mouse/touch events to mods through the
  -- input.pointer hook. v3.0.35 also treats touch as a first-class phone UI:
  -- tap controls, one-finger orbit/pan, and two-finger pan + pinch zoom.
  -- Consume them only while our selector is the active
  -- screen; gameplay and every other menu retain the engine's normal behavior.
  mod.hooks:wrap("input.pointer",function(next,game,event)
    local stack=game and game.stack
    local top=stack and type(stack.top)=="function" and stack:top() or nil
    if top and top._red3dSkinSelector and type(top._red3dHandlePointer)=="function" then
      local ok,consumed=pcall(top._red3dHandlePointer,top,event)
      if not ok then
        mod.log:error("Skin Selector pointer input failed: %s",tostring(consumed))
      elseif consumed then
        return true
      end
    end
    return next(game,event)
  end,math.huge)

  -- v3.1.0: the wheel decision is hoisted out of the Gen 1 install so the Gold
  -- boot can reuse the exact same logic.  Returns true when the event belonged
  -- to the Skin Selector and has been consumed; false means "not ours, run the
  -- engine's own wheel handler".
  renderer.red3dSelectorWheel=function(game,dx,dy)
    local stack=game and game.stack
    local top=stack and type(stack.top)=="function" and stack:top() or nil
    if not (top and top._red3dSkinSelector and top._red3dViewer
        and type(top._red3dViewer.zoomBy)=="function") then return false end
    local hit=top._red3dMouseUI
    local mx,my=tonumber(top._red3dMouseX),tonumber(top._red3dMouseY)
    if love and love.mouse and love.mouse.getPosition then
      local okPos,x,y=pcall(love.mouse.getPosition)
      if okPos and x and y then mx,my=x,y end
    end
    local wheel=tonumber(dy) or 0
    if not (hit and wheel~=0) then return false end
    if rectContains(hit.settings,mx,my) then
      local step=(wheel<0) and 1 or -1
      local maxFirst=math.max(1,tonumber(hit.settingsMaxFirst) or 1)
      local first=math.max(1,math.min(maxFirst,tonumber(top._red3dSettingsFirstControl) or tonumber(hit.settingsFirstControl) or 1))
      local nextFirst=math.max(1,math.min(maxFirst,first+step))
      top._red3dSettingsFirstControl=nextFirst
      top._red3dSettingsWheelBrowsing=true
      return true
    elseif rectContains(hit.model,mx,my) then
      if top._red3dBreastAreaEditorId then
        local id=top._red3dBreastAreaEditorId
        local child=id and renderers[id] or nil
        if child and child.data then
          local side=top._red3dBreastAreaActiveSide or ((mx<(hit.model.x+hit.model.w*0.5)) and "left" or "right")
          top._red3dBreastAreaActiveSide=side
          if side=="right" then
            local r=math.max(0.045,math.min(0.30,(tonumber(child.data.runtimeBelleBreastAreaRightRadius) or 0.13)+(wheel*0.010)))
            child.data.runtimeBelleBreastAreaRightRadius=r
            if mod.save and mod.save.set then mod.save:set(red3dBreastAreaSaveKey(id,"right_radius"),r) end
          else
            local r=math.max(0.045,math.min(0.30,(tonumber(child.data.runtimeBelleBreastAreaLeftRadius) or 0.13)+(wheel*0.010)))
            child.data.runtimeBelleBreastAreaLeftRadius=r
            if mod.save and mod.save.set then mod.save:set(red3dBreastAreaSaveKey(id,"left_radius"),r) end
          end
          child.skinKey=nil; child.voxelUploadedKey=nil; child.voxelFrameKey=nil
          return true
        end
      end
      top._red3dViewer:zoomBy(wheel)
      return true
    end
    return false
  end

  -- Gen1Recomp's desktop wheel goes directly through Game:wheelmoved (the
  -- public pointer hook does not carry wheel events).  With engine_internals
  -- permission, intercept that one method only while the cursor is over our 3D
  -- preview; everywhere else the original overworld/menu wheel behavior remains.
  do
    local okGame,Game=pcall(require,"src.core.Game")
    if okGame and type(Game)=="table" and type(Game.wheelmoved)=="function"
        and not Game._red3dSelectorWheelZoomInstalled then
      local originalWheel=Game.wheelmoved
      Game._red3dSelectorWheelZoomInstalled=true
      Game.wheelmoved=function(game,dx,dy)
        local okW,consumed=pcall(renderer.red3dSelectorWheel,game,dx,dy)
        if okW and consumed then return end
        return originalWheel(game,dx,dy)
      end
    end
  end

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
      -- Accessory placement is cached only for the current save. Clear the cache
      -- before reading the newly-restored modData bucket so attachments cannot
      -- bleed across save slots.
      ACCESSORY_STATE={}
      RIG_STATE={}
      clearRiggedCharacters()
      restoreRiggedCharacters()
      -- Per-character visual scales live in the same per-save modData bucket as
      -- the selected character. Missing keys from old saves cleanly mean 100%.
      for _,scaleId in ipairs(CHARACTER_ORDER) do
        applyCharacterScale(scaleId,savedCharacterScale(scaleId),false)
      end
      for belleId,belleChild in pairs(renderers) do
        if belleChild and (belleChild.behaviorId=="BELLESTARMON" or belleChild.behaviorId=="WOW") then
          applyBelleSavedProfile(belleId)
        end
      end
      local id=savedCharacter() or "RED"
      if id=="WOW" then id="RED" end
      if renderers[id] then
        renderer:setActive(id)
        local active=renderer:getActive()
        if active then
          active.skinKey=nil; active.voxelUploadedKey=nil; active.voxelFrameKey=nil
        end
        mod.log:info("3D character restored from save: %s", characterDisplayName(id))
      end
    end)

    mod.events:on("save.created",function()
      ACCESSORY_STATE={}
      RIG_STATE={}
      clearRiggedCharacters()
      -- New saves start from Red and every character starts at 100% visual scale.
      if mod.save and mod.save.set then mod.save:set("selected_character_3d","RED") end
      for _,scaleId in ipairs(CHARACTER_ORDER) do
        applyCharacterScale(scaleId,1.0,true)
      end
      for id,child in pairs(renderers) do
        if child and (child.behaviorId=="BELLESTARMON" or child.behaviorId=="WOW") then
          applyBelleRecommendedProfile(id)
          applyBellePhysicsEnabled("breast",false,true,id)
          applyBellePhysicsEnabled("buttocks",false,true,id)
          child.data.runtimeBelleBreastIndependent=true
          child.data.runtimeBelleButtIndependent=true
          if mod.save and mod.save.set then
            local prefix=(id=="WOW") and "wow" or "belle"
            mod.save:set(prefix.."_breast_independent_v3040",1)
            mod.save:set(prefix.."_butt_independent_v3040",1)
          end
          child.data.runtimeBelleThighPhysics=0
        end
      end
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

  -- v3.1.12 TRUE DIRECTIONAL MOVEMENT (Gen 1)
  --
  -- Gen1Recomp intentionally keeps the ROM's four-way tile movement.  The 3D
  -- characters benefit from a modern directional path, but replacing the cell
  -- system outright would bypass warps, encounters, scripts and NPC collision.
  -- Instead, add an engine-safe EIGHT-WAY step: a diagonal still lands on a real
  -- map cell and therefore runs the normal landing/event pipeline, while the
  -- renderer above rotates continuously to the actual travel vector.
  --
  -- Corner cutting is forbidden: both cardinal side cells AND the diagonal
  -- destination must be clear. Bikes/surf/fishing/forced/scripted movement stay
  -- vanilla so their special rules cannot be bypassed.
  do
    local okOW,OverworldState=pcall(require,"src.world.OverworldController")
    local okRuntime,Runtime=pcall(require,"src.mods.Runtime")
    local okGameMove,GameMove=pcall(require,"src.core.Game")

    local function signAxis(v,dead)
      v=tonumber(v) or 0
      dead=tonumber(dead) or 0.22
      if v>dead then return 1 end
      if v<-dead then return -1 end
      return 0
    end

    local function directionalIntent(input,player)
      local dx,dy=0,0
      local mx,my=tonumber(player and player.red3dMoveStickX) or 0,
                  tonumber(player and player.red3dMoveStickY) or 0
      if player and player.red3dAnalogMoveActive then
        dx=signAxis(mx,0.22)
        dy=signAxis(my,0.22)
      end
      -- Keyboard / d-pad can genuinely hold two directions at once even though
      -- the stock gamepad axis mapper reduces an analogue stick to one axis.
      if dx==0 and input then
        local l=input:isDown("left") and 1 or 0
        local r=input:isDown("right") and 1 or 0
        dx=r-l
      end
      if dy==0 and input then
        local u=input:isDown("up") and 1 or 0
        local d=input:isDown("down") and 1 or 0
        dy=d-u
      end
      if dx<-1 then dx=-1 elseif dx>1 then dx=1 end
      if dy<-1 then dy=-1 elseif dy>1 then dy=1 end
      return dx,dy,mx,my
    end

    local function componentFacing(player,dx,dy,mx,my)
      local h=dx<0 and "left" or (dx>0 and "right" or nil)
      local v=dy<0 and "up" or (dy>0 and "down" or nil)
      local old=player and player.facing
      if old==h or old==v then return old end
      if math.abs(mx)>math.abs(my)+0.05 then return h or v end
      return v or h or old or "down"
    end

    local function diagonalStart(top,player,dx,dy,mx,my)
      if not (okCollision and Collision and top and top.map and top.entities) then return false end
      if not player or player.moving or player.inputLocked then return false end
      if playerUsesSpecialCard(player) or player.spinning or player.fishing then return false end
      if okGameMove and GameMove and GameMove.save and GameMove.save.onBike then return false end
      if dx==0 or dy==0 then return false end

      local hdir=dx<0 and "left" or "right"
      local vdir=dy<0 and "up" or "down"
      local tx,ty=(player.cellX or 0)+dx,(player.cellY or 0)+dy
      local map=top.map
      if not map:inBounds(tx,ty) then return false end

      -- Both orthogonal legs must independently be legal. This preserves
      -- elevation-pair rules and blocks diagonal squeezing past an NPC/wall.
      local okH=Collision.canMove(map,top.entities,player,hdir)
      local okV=Collision.canMove(map,top.entities,player,vdir)
      if not okH or not okV then return false end
      if not map:isWalkableCell(tx,ty) then return false end
      if Collision.occupied(top.entities,tx,ty,player) then return false end

      local face=componentFacing(player,dx,dy,mx,my)
      player.facing=face
      player.turnArmed=false
      player.turnTimer=0
      player.bumpFrames=nil
      player.targetX,player.targetY=tx,ty
      player.moving=true
      player.progress=0
      player.red3dDiagonalMove=true
      local travelYaw=atan2(dx,dy)
      player.red3dProjectedBodyYaw=travelYaw
      player.red3dFreeBodyYaw=travelYaw

      -- A diagonal cell is sqrt(2) farther away. Scale the step duration after
      -- movement.speed so running/dash mods keep the same world-units/second.
      local frames=tonumber(player.stepFrames) or 16
      if okRuntime and Runtime and Runtime.wantsHook and Runtime.wantsHook("movement.speed") then
        local save=okGameMove and GameMove and GameMove.save or nil
        frames=Runtime.call("movement.speed",function(f) return f end,frames,{
          onBike=false,surfing=false,player=player,
          input=okGameMove and GameMove and GameMove.input or nil,save=save,
        })
      end
      frames=math.max(1,tonumber(frames) or 16)
      player.stepFramesCur=math.max(1,math.floor(frames*math.sqrt(2)+0.5))
      return true
    end

    if okOW and type(OverworldState)=="table" and type(OverworldState.handleInput)=="function"
        and not OverworldState.red3dDirectionalMovementInstalled then
      OverworldState.red3dDirectionalMovementInstalled=true
      local previousHandleInput=OverworldState.handleInput
      function OverworldState:handleInput(...)
        local input=okGameMove and GameMove and GameMove.input or nil
        local p=self.player
        -- Preserve the engine's mid-step button latch and all A/START actions.
        local latch=self.joyLatch
        local latchedAction=latch and ((latch.a and input and input:isDown("a"))
          or (latch.start and input and input:isDown("start")))
        if p and not p.moving and input and not latchedAction
            and not input:wasPressed("a") and not input:wasPressed("start") then
          local dx,dy,mx,my=directionalIntent(input,p)
          if dx~=0 and dy~=0 and diagonalStart(self,p,dx,dy,mx,my) then
            return "moved"
          end
        end
        return previousHandleInput(self,...)
      end
    end

    -- Gen 1's stock Player:update advances along Collision.DELTA[facing], which
    -- is necessarily cardinal. For ONLY our diagonal steps interpolate to the
    -- explicit target cell (the same target-vector strategy Gold already uses).
    if Player and type(Player.update)=="function" and not Player.red3dDirectionalUpdateInstalled then
      Player.red3dDirectionalUpdateInstalled=true
      local previousDirectionalUpdate=Player.update
      function Player:update(...)
        if not self.red3dDiagonalMove then return previousDirectionalUpdate(self,...) end

        self.stepLanded=false
        if self.hopFrames and self.hopFrames>0 then self.hopFrames=self.hopFrames-1 end
        if self.turnTimer and self.turnTimer>0 then self.turnTimer=self.turnTimer-1 end
        if self.spinFrames then
          self.spinFrames=self.spinFrames-1
          if self.spinFrames<=0 then
            self.spinFrames=nil; self.spinDrop=nil; self.spinRise=nil; self.spinning=false
          end
        end
        if not self.moving then
          self.red3dDiagonalMove=nil
          return false
        end

        local stepLen=self.stepFramesCur or self.stepFrames or 16
        self.progress=(self.progress or 0)+1
        self.animClock=(self.animClock or 0)+1
        local adv=math.floor(self.progress*16/stepLen)
        local dx=(self.targetX or self.cellX)-self.cellX
        local dy=(self.targetY or self.cellY)-self.cellY
        self.px=self.cellX*16+dx*adv
        self.py=self.cellY*16+dy*adv
        if self.progress>=stepLen then
          self.cellX,self.cellY=self.targetX,self.targetY
          self.targetX,self.targetY=nil,nil
          self.px,self.py=self.cellX*16,self.cellY*16
          self.moving=false
          self.stepFlip=not self.stepFlip
          self.stepLanded=true
          self.red3dDiagonalMove=nil
          return true
        end
        return false
      end
    end
  end

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

  -- v3.1.0 Generation 2 (Gold).  Gen1Recomp builds a DIFFERENT game object for a
  -- Gold boot -- src/core/Game2.lua, whose world's player is
  -- src/world/gen2/Player.lua, not the src.world.Player patched above.  The Gen 1
  -- patch is left in place regardless (the module still loads under Gold, it is
  -- simply never drawn), and the bridge below installs the same renderer over
  -- Gold's player using Gold's own draw contract.  Everything the mod platform
  -- owns -- the selector screen, touch input, options, saved per-character
  -- settings -- is shared between the two boots and needs no port at all.
  --
  -- The bridge no-ops on Red/Blue/Yellow, so this costs a Gen 1 boot one
  -- GameVersion check.
  do
    local gen2Src=mod:read("lib/Gen2Bridge.lua")
    if not gen2Src then
      mod.log:warn("lib/Gen2Bridge.lua is missing -- Gold boots will keep the stock player sprite")
    else
      local gen2Chunk,gen2Err=load(gen2Src,"@"..tostring(mod.path or mod.id).."/lib/Gen2Bridge.lua")
      if not gen2Chunk then
        mod.log:error("Gen 2 bridge compile failed: %s",tostring(gen2Err))
      else
        local okLoad,Gen2Bridge=pcall(gen2Chunk)
        if not okLoad or type(Gen2Bridge)~="table" then
          mod.log:error("Gen 2 bridge load failed: %s",tostring(Gen2Bridge))
        elseif Gen2Bridge.isActive() then
          local okInstall,installed,why=pcall(Gen2Bridge.install,{
            mod=mod,
            renderer=renderer,
            config=CONFIG,
            drawHopShadow=function(player,camX,camY)
              return drawHopShadow(player,camX,camY,GameVersion)
            end,
            selectorWheel=renderer.red3dSelectorWheel,
          })
          if not okInstall then
            mod.log:error("Gen 2 bridge install error: %s",tostring(installed))
          elseif not installed then
            mod.log:warn("Gen 2 bridge did not install: %s",tostring(why))
          end
        end
      end
    end
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
            local jumpFrames=CONFIG.manualJumpFrames
            if renderer and renderer.behaviorId=="BELLESTARMON" then
              jumpFrames=42
            elseif renderer and renderer.data and renderer.data.runtimeProfile=="WOW_FBX" then
              -- Native long-form FBX jump clips get a 0.8 s cosmetic window so
              -- takeoff/apex/landing do not look fast-forwarded.
              jumpFrames=48
            end
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

  -- v3.1.21 keeps the hard number-3 camera cycle + Android double-tap and adds Android voxel-world pinch zoom.
  --
  -- v3.1.18 wrapped Game:keypressed(), but Gen1Recomp deliberately lets the
  -- current top state inspect/consume a key before its built-in number-key
  -- display handling.  A state or another mod could therefore swallow "3"
  -- before this companion shortcut ever saw it.  It also consulted
  -- Pipelines.canToggle(), adding a second gate that could reject the camera
  -- change even though the live voxel renderer was healthy.
  --
  -- Install one layer earlier, on LOVE's physical key callback, and keep a
  -- physical-key edge poll in love.update as a fallback.  The shortcut only
  -- owns the key while the *actual overworld* is the top state; everywhere
  -- else the original LOVE/Game route receives 3 unchanged.  No canToggle()
  -- call is used.  The target is written straight to the live render-pipeline
  -- level and to the voxel renderer's captured VoxelState when available.
  do
    local okPipe,PipelinesHotkey=pcall(require,"src.render.Pipelines")
    if okPipe and PipelinesHotkey and type(PipelinesHotkey.setLevel)=="function"
        and love and type(love.keypressed)=="function"
        and not love.red3dNumber3CameraCycleInstalled then
      love.red3dNumber3CameraCycleInstalled=true

      local function activeOverworldGame()
        local candidates={}
        for _,name in ipairs({"src.core.Game","src.core.Game2"}) do
          local ok,g=pcall(require,name)
          if ok and type(g)=="table" then candidates[#candidates+1]=g end
        end
        for _,g in ipairs(candidates) do
          local top=nil
          if g.stack and type(g.stack.top)=="function" then
            local okTop,result=pcall(g.stack.top,g.stack)
            if okTop then top=result end
          end
          if g.overworld and top==g.overworld then return g end
        end
        return nil
      end

      local function classifyCameraLevels(id)
        local labels=PipelinesHotkey.levelLabels and PipelinesHotkey.levelLabels(id) or nil
        if type(labels)~="table" then return nil end
        local fp,tp,zoom=nil,nil,nil
        local ordinary={}
        for i,label in ipairs(labels) do
          local level=i-1
          local text=string.upper(tostring(label or ""))
          local compact=text:gsub("%s+","")
          if not fp and (text:find("1ST",1,true) or text:find("FIRST",1,true)) then fp=level end
          if not tp and (text:find("3RD",1,true) or text:find("THIRD",1,true)) then tp=level end
          if level>0 and not text:find("FULL",1,true) then
            ordinary[#ordinary+1]={level=level,text=text,compact=compact}
          end
          if not zoom and text:find("ZOOM",1,true) then zoom=level end
        end
        if not (fp and tp) then return nil end

        -- Current Dramatic/Dramaless Shape names the close orbit "75".
        if not zoom then
          for _,e in ipairs(ordinary) do
            if e.compact=="75" or e.compact=="75°" then zoom=e.level break end
          end
        end
        -- Fork fallback: the highest ordinary orbit rung immediately before
        -- the free-camera pair is the safest hand-off view.  FULL is skipped
        -- because selecting that preset also rewrites unrelated display rows.
        if not zoom then
          for _,e in ipairs(ordinary) do
            if e.level~=fp and e.level~=tp and (not zoom or e.level>zoom) then zoom=e.level end
          end
        end
        if not zoom then return nil end
        return zoom,fp,tp
      end

      local function resolveCameraPipeline()
        local tried={}
        local function tryId(id)
          if type(id)~="string" or tried[id] then return nil end
          tried[id]=true
          if type(PipelinesHotkey.get)=="function" and not PipelinesHotkey.get(id) then return nil end
          local zoom,fp,tp=classifyCameraLevels(id)
          if zoom and fp and tp then return id,zoom,fp,tp end
          return nil
        end

        -- Fast path for the public Dramatic/Dramaless id.
        local id,z,f,t=tryId("voxel")
        if id then return id,z,f,t end

        -- Fork-safe path: find whichever registered pipeline actually exposes
        -- both free-camera labels instead of assuming its id.
        if type(PipelinesHotkey.list)=="function" then
          local okList,list=pcall(PipelinesHotkey.list)
          if okList and type(list)=="table" then
            for _,entry in ipairs(list) do
              local eid=type(entry)=="table" and entry.id or nil
              local a,b,c,d=tryId(eid)
              if a then return a,b,c,d end
            end
          end
        end
        return nil
      end

      local function syncPrivateVoxelState(pipelineId,target)
        -- Keep the private camera state in lock-step immediately rather than
        -- waiting for the pipeline's next update tick.  This is a compatibility
        -- backup; the engine pipeline level remains the authoritative setting.
        local state=renderer and renderer.voxelBridge and renderer.voxelBridge.VoxelState or nil
        if type(state)=="table" and type(state.setLevel)=="function" then
          pcall(state.setLevel,target)
        end
        if type(PipelinesHotkey.get)=="function" and debug and debug.getupvalue then
          local def=PipelinesHotkey.get(pipelineId)
          local update=type(def)=="table" and def.update or nil
          if type(update)=="function" then
            local _,captured=findUpvalue(update,"Voxel")
            if type(captured)=="table" and type(captured.setLevel)=="function" then
              pcall(captured.setLevel,target)
            end
          end
        end
      end

      local function applyCameraLevel(game,pipelineId,target,reason)
        local actual=PipelinesHotkey.setLevel(pipelineId,target)
        if actual~=target then
          mod.log:warn("%s: pipeline refused target %s (got %s)",
            tostring(reason or "camera shortcut"),tostring(target),tostring(actual))
          return false
        end
        syncPrivateVoxelState(pipelineId,target)

        local opts=game.save and game.save.options or nil
        if opts and type(PipelinesHotkey.syncOptions)=="function" then
          pcall(PipelinesHotkey.syncOptions,opts)
          opts.tilt=0
        end
        local okTilt,Tilt=pcall(require,"src.render.Tilt")
        if okTilt and Tilt and type(Tilt.setLevel)=="function" then pcall(Tilt.setLevel,0) end
        if type(game.writeOptions)=="function" then pcall(game.writeOptions,game) end

        local label=(PipelinesHotkey.levelLabel and PipelinesHotkey.levelLabel(pipelineId,target)) or tostring(target)
        mod.log:info("%s -> %s [%s]",tostring(reason or "camera shortcut"),tostring(label),tostring(pipelineId))
        return true
      end

      local function activateNumber3()
        local game=activeOverworldGame()
        if not game then return false end

        local pipelineId,zoom,fp,tp=resolveCameraPipeline()
        if not (pipelineId and zoom and fp and tp) then
          mod.log:warn("3 camera cycle: no voxel pipeline with ZOOM/1ST/3RD levels was found")
          return false
        end

        local current=(PipelinesHotkey.level and PipelinesHotkey.level(pipelineId)) or 0
        local target
        if current==zoom then
          target=fp
        elseif current==fp then
          target=tp
        elseif current==tp then
          target=zoom
        else
          target=zoom
        end
        return applyCameraLevel(game,pipelineId,target,"3 hard camera cycle")
      end

      local function activateThirdPerson(reason)
        local game=activeOverworldGame()
        if not game then return false end
        local pipelineId,zoom,fp,tp=resolveCameraPipeline()
        if not (pipelineId and zoom and fp and tp) then
          mod.log:warn("Android double-tap: no voxel pipeline with ZOOM/1ST/3RD levels was found")
          return false
        end
        return applyCameraLevel(game,pipelineId,tp,reason or "Android double-tap 3RD")
      end

      local number3PhysicalLatched=false
      local innerLoveKeypressed=love.keypressed
      love.keypressed=function(key,scancode,isrepeat,...)
        local k=string.lower(tostring(key or ""))
        if k=="3" or k=="kp3" then
          -- Ignore OS key-repeat while the physical press is already owned.
          if number3PhysicalLatched and activeOverworldGame() then return end
          if activateNumber3() then
            number3PhysicalLatched=true
            return
          end
        end
        return innerLoveKeypressed(key,scancode,isrepeat,...)
      end

      -- Event-independent fallback: even if an outer callback swallows the
      -- keypressed event, the physical keyboard state still reaches here.
      -- This runs before the original love.update but does not alter the game
      -- simulation or input state itself.
      if type(love.update)=="function" and not love.red3dNumber3CameraPollInstalled then
        love.red3dNumber3CameraPollInstalled=true
        local innerLoveUpdate=love.update
        love.update=function(dt,...)
          local down=false
          if love.keyboard and type(love.keyboard.isDown)=="function" then
            local ok3,v3=pcall(love.keyboard.isDown,"3")
            local okKp,vKp=pcall(love.keyboard.isDown,"kp3")
            down=(ok3 and v3==true) or (okKp and vKp==true)
          end
          if down then
            if not number3PhysicalLatched then
              activateNumber3()
              number3PhysicalLatched=true
            end
          else
            number3PhysicalLatched=false
          end
          return innerLoveUpdate(dt,...)
        end
      end

      -- v3.1.21: Android double-tap + voxel-world pinch zoom. Two quick taps on empty
      -- overworld screen space jump directly to the voxel renderer's 3RD
      -- camera rung. Observe physical LOVE touch callbacks so the gesture is
      -- seen before a state/mod can consume it, but never claim/alter the
      -- underlying touch events. Touch-control hits and multi-touch gestures
      -- are excluded so D-pad/A/B taps and pinch/look gestures cannot switch
      -- the camera by accident.
      local isAndroid=false
      if love.system and type(love.system.getOS)=="function" then
        local okOS,osName=pcall(love.system.getOS)
        isAndroid=okOS and osName=="Android"
      end
      if isAndroid and type(love.touchpressed)=="function"
          and type(love.touchmoved)=="function" and type(love.touchreleased)=="function"
          and not love.red3dAndroidDoubleTapThirdInstalled then
        love.red3dAndroidDoubleTapThirdInstalled=true

        local TAP_MAX_TIME=0.30
        local DOUBLE_TAP_GAP=0.38
        local TAP_MOVE=40
        local DOUBLE_TAP_RADIUS=72
        local liveTouches={}
        local liveTouchCount=0
        local lastTap=nil
        liveTouches._pinch=nil
        liveTouches._pinchSurveyAccum=0

        local function touchNow()
          if love.timer and type(love.timer.getTime)=="function" then
            local okT,t=pcall(love.timer.getTime)
            if okT and type(t)=="number" then return t end
          end
          return os.clock()
        end

        local function touchHitsControl(x,y)
          local okTC,TouchControls=pcall(require,"src.core.TouchControls")
          if not okTC or not TouchControls or type(TouchControls.hitTest)~="function" then return false end
          local okHit,hit=pcall(TouchControls.hitTest,TouchControls,x,y)
          return okHit and hit~=nil and hit~=false
        end

        local function dist2(ax,ay,bx,by)
          local dx=(ax or 0)-(bx or 0)
          local dy=(ay or 0)-(by or 0)
          return dx*dx+dy*dy
        end

        liveTouches._bridgeCameraModules=function()
          local bridge=renderer and renderer.voxelBridge or nil
          return bridge and bridge.FirstPerson or nil, bridge and bridge.ThirdPerson or nil
        end

        -- Pinch semantics match the voxel renderer's own camera controls:
        -- fingers spreading means zoom IN, pinching together means zoom OUT.
        -- Orbit/tabletop views use Gen1Recomp's survey-zoom ladder; 3RD uses
        -- the voxel renderer's continuous boom-distance control when exposed.
        -- 1ST has no meaningful camera distance, so pinch is intentionally inert.
        liveTouches._pinchVoxelZoom=function(factor)
          if type(factor)~="number" or factor<=0 then return false end
          if math.abs(factor-1)<0.008 then return false end

          local game=activeOverworldGame()
          if not game then return false end
          local pipelineId,zoom,fp,tp=resolveCameraPipeline()
          if not (pipelineId and zoom and fp and tp) then return false end
          local current=(PipelinesHotkey.level and PipelinesHotkey.level(pipelineId)) or 0
          if current==fp then return false end

          if current==tp then
            local _,ThirdPerson=liveTouches._bridgeCameraModules()
            if type(ThirdPerson)=="table" and type(ThirdPerson.scaleZoom)=="function" then
              local okZoom,result=pcall(ThirdPerson.scaleZoom,1/factor)
              return okZoom and result~=false
            end
            -- Nearby voxel forks may expose only stepped boom zoom. Preserve
            -- the gesture there too, using the same log-distance accumulator.
            if type(ThirdPerson)=="table" and type(ThirdPerson.stepZoom)=="function" then
              liveTouches._pinchSurveyAccum=(liveTouches._pinchSurveyAccum or 0)+math.log(factor)/math.log(2)*2.2
              local moved=false
              while (liveTouches._pinchSurveyAccum or 0)>=1 do
                liveTouches._pinchSurveyAccum=liveTouches._pinchSurveyAccum-1
                pcall(ThirdPerson.stepZoom,-1) -- spread = camera in
                moved=true
              end
              while (liveTouches._pinchSurveyAccum or 0)<=-1 do
                liveTouches._pinchSurveyAccum=liveTouches._pinchSurveyAccum+1
                pcall(ThirdPerson.stepZoom,1) -- pinch = camera out
                moved=true
              end
              return moved
            end
            return false
          end

          if type(game.zoomStep)~="function" then return false end
          liveTouches._pinchSurveyAccum=(liveTouches._pinchSurveyAccum or 0)+math.log(factor)/math.log(2)*2.2
          local moved=false
          while (liveTouches._pinchSurveyAccum or 0)>=1 do
            liveTouches._pinchSurveyAccum=liveTouches._pinchSurveyAccum-1
            pcall(game.zoomStep,game,1) -- spread fingers = zoom in
            moved=true
          end
          while (liveTouches._pinchSurveyAccum or 0)<=-1 do
            liveTouches._pinchSurveyAccum=liveTouches._pinchSurveyAccum+1
            pcall(game.zoomStep,game,-1) -- pinch together = zoom out
            moved=true
          end
          return moved
        end

        liveTouches._cancelPinch=function(reseat)
          if not liveTouches._pinch then return end
          local old=liveTouches._pinch
          liveTouches._pinch=nil
          liveTouches._pinchSurveyAccum=0
          lastTap=nil
          for _,pid in ipairs({old.a,old.b}) do
            if liveTouches[pid] then liveTouches[pid].pinched=true end
          end
          if reseat then
            local FirstPerson=liveTouches._bridgeCameraModules()
            if type(FirstPerson)=="table" and type(FirstPerson.reseatLook)=="function" then
              for pid,t in pairs(liveTouches) do
                if pid~=reseat and type(t)=="table" and t.worldEligible then
                  pcall(FirstPerson.reseatLook,pid,t.lastX or t.x,t.lastY or t.y)
                  break
                end
              end
            end
          end
        end

        liveTouches._maybeStartPinch=function()
          if liveTouches._pinch or liveTouchCount~=2 then return end
          local ids={}
          for pid,t in pairs(liveTouches) do
            if type(t)=="table" and t.worldEligible and not t.control then ids[#ids+1]=pid end
          end
          if #ids~=2 then return end
          local a,b=liveTouches[ids[1]],liveTouches[ids[2]]
          local gap=math.sqrt(dist2(a.lastX or a.x,a.lastY or a.y,b.lastX or b.x,b.lastY or b.y))
          if gap<28 then return end
          liveTouches._pinch={a=ids[1],b=ids[2],gap=gap}
          liveTouches._pinchSurveyAccum=0
          a.pinched,b.pinched=true,true
          lastTap=nil
          local FirstPerson=liveTouches._bridgeCameraModules()
          if type(FirstPerson)=="table" and type(FirstPerson.dropLook)=="function" then
            pcall(FirstPerson.dropLook)
          end
        end

        local innerTouchPressed=love.touchpressed
        love.touchpressed=function(id,x,y,dx,dy,pressure,...)
          liveTouchCount=liveTouchCount+1
          local control=touchHitsControl(x,y)
          local worldEligible=activeOverworldGame()~=nil and not control
          -- `eligible` remains the single-finger double-tap qualification;
          -- `worldEligible` is intentionally true for both fingers so a real
          -- two-finger pinch can begin on empty voxel-world screen space.
          local eligible=liveTouchCount==1 and worldEligible
          liveTouches[id]={x=x,y=y,lastX=x,lastY=y,t=touchNow(),eligible=eligible,
            worldEligible=worldEligible,control=control,moved=false,pinched=false}
          if liveTouchCount>1 then lastTap=nil end
          if liveTouchCount>2 then
            liveTouches._cancelPinch(nil)
          else
            liveTouches._maybeStartPinch()
          end
          return innerTouchPressed(id,x,y,dx,dy,pressure,...)
        end

        local innerTouchMoved=love.touchmoved
        love.touchmoved=function(id,x,y,dx,dy,pressure,...)
          local tap=liveTouches[id]
          if tap then
            tap.lastX,tap.lastY=x,y
            if dist2(x,y,tap.x,tap.y)>TAP_MOVE*TAP_MOVE then tap.moved=true end
          end
          if liveTouches._pinch and (id==liveTouches._pinch.a or id==liveTouches._pinch.b) then
            local a,b=liveTouches[liveTouches._pinch.a],liveTouches[liveTouches._pinch.b]
            if a and b then
              local gap=math.sqrt(dist2(a.lastX or a.x,a.lastY or a.y,b.lastX or b.x,b.lastY or b.y))
              if gap>=28 and liveTouches._pinch.gap and liveTouches._pinch.gap>0 then
                local factor=gap/liveTouches._pinch.gap
                if math.abs(factor-1)>=0.008 then
                  liveTouches._pinchVoxelZoom(factor)
                  liveTouches._pinch.gap=gap
                end
              end
            end
            -- Claim pinch motion here so another voxel/touch wrapper cannot
            -- apply the same gesture a second time. Press/release still flow
            -- through, so the host never gets a stranded touch id.
            return
          end
          return innerTouchMoved(id,x,y,dx,dy,pressure,...)
        end

        local innerTouchReleased=love.touchreleased
        love.touchreleased=function(id,x,y,dx,dy,pressure,...)
          local tap=liveTouches[id]
          local wasPinch=liveTouches._pinch and (id==liveTouches._pinch.a or id==liveTouches._pinch.b)
          if wasPinch then
            -- Mark both touches before removal so neither half of a pinch can
            -- ever be mistaken for one half of the double-tap shortcut.
            if liveTouches[liveTouches._pinch.a] then liveTouches[liveTouches._pinch.a].pinched=true end
            if liveTouches[liveTouches._pinch.b] then liveTouches[liveTouches._pinch.b].pinched=true end
          end
          liveTouches[id]=nil
          liveTouchCount=math.max(0,liveTouchCount-1)
          if wasPinch then liveTouches._cancelPinch(id) end

          -- Always let the game's normal touch release complete. Pinch only
          -- claims MOVE events; releases must reach the host to clear ids.
          local result=innerTouchReleased(id,x,y,dx,dy,pressure,...)

          local now=touchNow()
          local qualifies=tap and tap.eligible and not tap.moved and not tap.pinched
            and liveTouchCount==0 and activeOverworldGame()~=nil
            and not touchHitsControl(x,y)
            and (now-(tap.t or now))<=TAP_MAX_TIME
          if qualifies then
            if lastTap and (now-lastTap.t)<=DOUBLE_TAP_GAP
                and dist2(x,y,lastTap.x,lastTap.y)<=DOUBLE_TAP_RADIUS*DOUBLE_TAP_RADIUS then
              activateThirdPerson("Android double-tap 3RD")
              lastTap=nil
            else
              lastTap={x=x,y=y,t=now}
            end
          elseif tap then
            lastTap=nil
          end
          return result
        end
      end
    elseif mod and mod.log then
      mod.log:warn("number-3 hard camera cycle unavailable: LOVE/pipeline API was not found")
    end
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
