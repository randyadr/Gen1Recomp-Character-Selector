-- Skin Selector live 3D portrait renderer.
--
-- Architecture intentionally mirrors the working Stadium UI Model Viewer:
-- render the selected model into a transparent off-screen Voxel3D scene,
-- never inherit PaletteFX into that scene, restore all graphics/Voxel3D state,
-- then let the owning Skin Selector draw the returned true-color canvas.
local Viewer = {}
Viewer.__index = Viewer

local DEFAULT_W = 768
local DEFAULT_H = 900
local FOV = math.rad(27)
local SPIN = math.rad(12)
local FRAME_INTERVAL = 1 / 30

local function safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok,a,b,c,d = pcall(fn, ...)
  if ok then return a,b,c,d end
  return nil
end

local function nowClock()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

local function saveLove()
  local g = love and love.graphics
  local s = {}
  if not g then return s end
  if g.getCanvas then local ok,v=pcall(g.getCanvas); if ok then s.canvas=v; s.canvasOK=true end end
  if g.getShader then local ok,v=pcall(g.getShader); if ok then s.shader=v; s.shaderOK=true end end
  if g.getColor then local ok,a,b,c,d=pcall(g.getColor); if ok then s.color={a,b,c,d}; s.colorOK=true end end
  if g.getBlendMode then local ok,a,b=pcall(g.getBlendMode); if ok then s.blend={a,b}; s.blendOK=true end end
  if g.getDepthMode then local ok,a,b=pcall(g.getDepthMode); if ok then s.depth={a,b}; s.depthOK=true end end
  if g.getMeshCullMode then local ok,v=pcall(g.getMeshCullMode); if ok then s.cull=v; s.cullOK=true end end
  if g.getScissor then
    local ok,a,b,c,d=pcall(g.getScissor)
    if ok then s.scissor={a,b,c,d}; s.scissorEnabled=(a~=nil); s.scissorOK=true end
  end
  return s
end

local function restoreLove(s)
  local g = love and love.graphics
  if not g then return end
  if s.canvasOK then if s.canvas then pcall(g.setCanvas,s.canvas) else pcall(g.setCanvas) end end
  if s.shaderOK then pcall(g.setShader,s.shader) end
  if s.depthOK then pcall(g.setDepthMode,s.depth[1],s.depth[2]) else pcall(g.setDepthMode) end
  if s.cullOK then pcall(g.setMeshCullMode,s.cull) end
  if s.blendOK then pcall(g.setBlendMode,s.blend[1],s.blend[2]) end
  if s.scissorOK then
    if s.scissorEnabled then pcall(g.setScissor,s.scissor[1],s.scissor[2],s.scissor[3],s.scissor[4])
    else pcall(g.setScissor) end
  end
  if s.colorOK then pcall(g.setColor,s.color[1],s.color[2],s.color[3],s.color[4]) end
end

local function saveVoxel(Voxel3D)
  return {
    camera=Voxel3D.camera,
    cull=Voxel3D.cull,
    keyColor=Voxel3D.keyColor,
    tint=Voxel3D.tint,
    fog=Voxel3D.fog,
    fireflyNight=Voxel3D.fireflyNight,
  }
end

local function restoreVoxel(Voxel3D,s)
  Voxel3D.camera=s.camera
  Voxel3D.cull=s.cull
  Voxel3D.keyColor=s.keyColor
  Voxel3D.tint=s.tint
  Voxel3D.fog=s.fog
  Voxel3D.fireflyNight=s.fireflyNight
end

local function setIdlePhase(r, now)
  local d=r and r.data
  if not d then return end
  local dur=tonumber(d.idleDuration) or 1
  if dur<=0 then dur=1 end
  local phase=(now/dur)%1
  local profile=d.runtimeProfile
  if profile=="ASH" then
    d.runtimeAshIdlePhase=phase
  elseif profile=="AANG_MIXAMO" then
    d.runtimeAangIdlePhase=phase
  elseif profile=="CJ_FBX" then
    d.runtimeCJIdlePhase=phase
  elseif profile=="YAMI_FBX" then
    d.runtimeYamiIdlePhase=phase
  elseif profile=="BEELSTARMON_MIXAMO" then
    d.runtimeBeelIdlePhase=phase
  elseif profile=="NARUTO_MIXAMO" then
    d.runtimeNarutoIdlePhase=phase
  end
end

local function uploadCurrentSkin(r,Voxel3D)
  if not r:ensureVoxelGraphics(Voxel3D) then return false end
  local rows=r.voxelRows
  for i=1,r.renderVertexCount do
    local p=r.vertexPos[i]
    local row=rows[i]
    row[1]=r.sx[p]
    row[2]=r.sy[p]
    row[3]=r.sz[p]
  end
  local ok=pcall(r.voxelMesh.setVertices,r.voxelMesh,rows)
  if not ok then return false end
  -- UI preview mutates the same optimized mesh used by the overworld. Force
  -- the next world frame to upload its own pose again after the menu closes.
  r.voxelUploadedKey=nil
  r.skinKey=nil
  return true
end

local function currentBounds(r)
  local minX,minY,minZ=math.huge,math.huge,math.huge
  local maxX,maxY,maxZ=-math.huge,-math.huge,-math.huge
  for i=1,r.data.positionCount do
    local x,y,z=r.sx[i],r.sy[i],r.sz[i]
    if x and y and z then
      if x<minX then minX=x end; if x>maxX then maxX=x end
      if y<minY then minY=y end; if y>maxY then maxY=y end
      if z<minZ then minZ=z end; if z>maxZ then maxZ=z end
    end
  end
  if minX==math.huge then return nil end
  return minX,minY,minZ,maxX,maxY,maxZ
end

function Viewer.new()
  return setmetatable({
    angle=0,
    lastClock=nil,
    lastRenderClock=nil,
    lastCharacter=nil,
    canvas=nil,
    canvasW=nil, canvasH=nil,
  },Viewer)
end

function Viewer:nudge(delta)
  self.angle=(self.angle+(tonumber(delta) or 0))%(math.pi*2)
  self.lastRenderClock=nil
end

function Viewer:render(r,bridge,requestedW,requestedH)
  if not (r and bridge and type(bridge)=="table") then return nil end
  local Voxel3D=bridge.Voxel3D
  local Mat4=bridge.Mat4
  if type(Voxel3D)~="table" or type(Mat4)~="table" then return nil end
  if not (Mat4.translate and Mat4.rotateY and Mat4.scale and Mat4.mul) then return nil end
  if not (Voxel3D.beginScene and Voxel3D.endScene and Voxel3D.draw) then return nil end

  local sceneW=math.max(320,math.min(1152,math.floor(tonumber(requestedW) or DEFAULT_W)))
  local sceneH=math.max(400,math.min(1280,math.floor(tonumber(requestedH) or DEFAULT_H)))

  local now=nowClock()
  if self.lastCharacter~=r.characterId then
    self.lastCharacter=r.characterId
    self.angle=0
    self.lastClock=now
    self.lastRenderClock=nil
    self.canvas=nil
    self.canvasW=nil; self.canvasH=nil
  end

  local dt=0
  if self.lastClock then dt=now-self.lastClock end
  self.lastClock=now
  dt=math.max(0,math.min(tonumber(dt) or 0,0.1))
  self.angle=(self.angle+dt*SPIN)%(math.pi*2)

  if self.canvas and self.canvasW==sceneW and self.canvasH==sceneH
      and self.lastRenderClock and (now-self.lastRenderClock)<FRAME_INTERVAL then
    return self.canvas
  end
  self.lastRenderClock=now

  setIdlePhase(r,now)
  -- Fake standing player: embedded authored idle clips continue to animate,
  -- while procedural characters simply hold their normal standing pose.
  r:updateSkeleton({},false,0,0)
  r:skin()
  if not uploadCurrentSkin(r,Voxel3D) then return nil end
  if not r:ensureImage() then return nil end

  local minX,minY,minZ,maxX,maxY,maxZ=currentBounds(r)
  if not minX then return nil end
  local h=math.max(0.001,maxY-minY)
  local cx=(minX+maxX)*0.5
  local cz=(minZ+maxZ)*0.5
  local targetH=32
  local scale=targetH/h
  local halfW=(maxX-minX)*0.5*scale
  local halfD=(maxZ-minZ)*0.5*scale
  local aspect=sceneW/math.max(1,sceneH)
  local tanHalf=math.tan(FOV*0.5)
  -- Fit the full silhouette at the actual portrait aspect ratio. The old
  -- 128x128 preview then scaled into a 64x66 Game Boy box; this one is
  -- rendered natively at HUD resolution and keeps wide hair/weapons in frame.
  local verticalDistance=(targetH*0.52)/tanHalf
  local horizontalDistance=halfW/math.max(0.05,tanHalf*aspect)
  local depthDistance=halfD/tanHalf
  local distance=math.max(verticalDistance,horizontalDistance,depthDistance,8)*1.18

  local model=Mat4.rotateY((tonumber(r.modelYawOffset) or 0)+self.angle)
  model=Mat4.mul(model,Mat4.scale(scale,scale,scale))
  model=Mat4.mul(model,Mat4.translate(-cx,-minY,-cz))

  local ls=saveLove()
  local vs=saveVoxel(Voxel3D)
  local g=love.graphics
  local pushed=false
  if g.push then pushed=pcall(g.push,"all") end
  local output=nil
  local ok=pcall(function()
    -- Exact working Pokedex-viewer rule: never inherit the Game Boy palette
    -- shader into the off-screen true-color model render.
    if g.setShader then pcall(g.setShader) end
    if g.setColor then pcall(g.setColor,1,1,1,1) end

    Voxel3D.camera={
      eye={0,targetH*0.52,distance},
      focus={0,targetH*0.50,0},
      up={0,1,0},
      fov=FOV,
      curve=0,
    }
    Voxel3D.cull=nil
    Voxel3D.keyColor=nil
    Voxel3D.tint={1,1,1}
    Voxel3D.fog=nil
    Voxel3D.fireflyNight=0

    if safe(Voxel3D.beginScene,sceneW,sceneH,0,0,sceneW,sceneH,nil,"skin_selector_portrait_hd") then
      if Voxel3D.glass then pcall(Voxel3D.glass,false) end
      local drew=pcall(Voxel3D.draw,r.voxelMesh,r.image,model,nil,model)
      local canvas=safe(Voxel3D.endScene)
      if drew and canvas then output=canvas end
    end
  end)

  restoreVoxel(Voxel3D,vs)
  if pushed then pcall(g.pop) end
  restoreLove(ls)
  if not ok then return nil end
  if output then
    self.canvas=output
    self.canvasW=sceneW; self.canvasH=sceneH
    if type(output.setFilter)=="function" then pcall(output.setFilter,output,"linear","linear",1) end
  end
  return output or self.canvas
end

return Viewer
