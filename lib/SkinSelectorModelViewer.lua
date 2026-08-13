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
local FRAME_INTERVAL = 1 / 60

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
  elseif profile=="WOW_FBX" then
    d.runtimeWowIdlePhase=phase
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
    -- Blender-like inspection camera.  Yaw/pitch orbit the camera around the
    -- character, panX/panY move the orbit focus in the current camera plane,
    -- and zoom dollies the camera without touching the model transform.
    yaw=0,
    pitch=0,
    panX=0,
    panY=0,
    zoom=1.0,
    lastClock=nil,
    lastRenderClock=nil,
    animationTime=0,
    pendingAnimationDt=0,
    lastCharacter=nil,
    lastScale=nil,
    canvas=nil,
    canvasW=nil, canvasH=nil,
    dragging=false,
  },Viewer)
end

function Viewer:invalidate()
  self.lastRenderClock=nil
end

function Viewer:nudge(delta)
  self.yaw=(self.yaw+(tonumber(delta) or 0))%(math.pi*2)
  self.lastRenderClock=nil
end

function Viewer:orbitBy(dx,dy)
  dx=tonumber(dx) or 0
  dy=tonumber(dy) or 0
  self.yaw=(self.yaw+dx*0.012)%(math.pi*2)
  local p=(tonumber(self.pitch) or 0)-dy*0.012
  local limit=math.rad(85)
  if p>limit then p=limit elseif p<-limit then p=-limit end
  self.pitch=p
  self.lastRenderClock=nil
end

function Viewer:panBy(dx,dy)
  dx=tonumber(dx) or 0
  dy=tonumber(dy) or 0
  local z=tonumber(self.zoom) or 1.0
  if z<0.1 then z=0.1 end
  -- Store pan in preview-world units. Dividing by zoom keeps drag sensitivity
  -- useful while tightly zoomed in, like a conventional DCC viewport.
  local scale=0.042/z
  self.panX=(tonumber(self.panX) or 0)-dx*scale
  self.panY=(tonumber(self.panY) or 0)+dy*scale
  if self.panX>96 then self.panX=96 elseif self.panX<-96 then self.panX=-96 end
  if self.panY>96 then self.panY=96 elseif self.panY<-96 then self.panY=-96 end
  self.lastRenderClock=nil
end

function Viewer:zoomBy(delta)
  delta=tonumber(delta) or 0
  if delta==0 then return self.zoom or 1.0 end
  local z=tonumber(self.zoom) or 1.0
  -- Wide dolly range for close inspection, but still bounded so the camera
  -- cannot cross the focus point or disappear into floating point extremes.
  z=z*(1.12^delta)
  if z<0.22 then z=0.22 elseif z>6.00 then z=6.00 end
  self.zoom=z
  self.lastRenderClock=nil
  return z
end

function Viewer:resetView()
  self.yaw=0
  self.pitch=0
  self.panX=0
  self.panY=0
  self.zoom=1.0
  self.lastRenderClock=nil
end

function Viewer:resetZoom()
  self.zoom=1.0
  self.lastRenderClock=nil
end

function Viewer:setDragging(active)
  self.dragging=(active==true)
  self.lastClock=nowClock()
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
  local previewScale=tonumber(r.userScale) or 1.0
  if previewScale<0.50 then previewScale=0.50 elseif previewScale>1.50 then previewScale=1.50 end
  if self.lastCharacter~=r.characterId then
    self.lastCharacter=r.characterId
    self.lastScale=previewScale
    self.yaw=0
    self.pitch=0
    self.panX=0
    self.panY=0
    self.lastClock=now
    self.lastRenderClock=nil
    self.animationTime=0
    self.pendingAnimationDt=0
    self.canvas=nil
    self.canvasW=nil; self.canvasH=nil
  elseif self.lastScale~=previewScale then
    self.lastScale=previewScale
    self.lastRenderClock=nil
  end

  local rawDt=0
  if self.lastClock then rawDt=now-self.lastClock end
  self.lastClock=now
  rawDt=math.max(0,math.min(tonumber(rawDt) or 0,0.05))
  self.animationTime=(tonumber(self.animationTime) or 0)+rawDt
  self.pendingAnimationDt=math.min(0.05,(tonumber(self.pendingAnimationDt) or 0)+rawDt)
  -- v3.0.15: no automatic showroom rotation. Angle changes only from explicit
  -- D-pad/keyboard nudges or mouse dragging.

  if self.canvas and self.canvasW==sceneW and self.canvasH==sceneH
      and self.lastRenderClock and (now-self.lastRenderClock)<FRAME_INTERVAL then
    return self.canvas
  end
  self.lastRenderClock=now
  local dt=tonumber(self.pendingAnimationDt) or 0
  self.pendingAnimationDt=0

  -- Use a local accumulated animation clock instead of absolute timer time so
  -- startup/focus clock discontinuities can never change preview playback rate.
  setIdlePhase(r,self.animationTime or 0)
  -- BelleStarmon previews the real high-rate direct-target spring solver while the user-supplied
  -- selector-only clip plays. The spring helpers remain independent of the
  -- authored skeleton motion, so all body-physics controls stay live.
  if (r.behaviorId=="BELLESTARMON" or r.behaviorId=="WOW") and r.updateBelleBodyPhysics then
    r:updateBelleBodyPhysics(nil,false,dt,true)
  end
  local d=r.data
  -- Selector-only pose clips are gated in boneDelta() by this short-lived
  -- preview flag. Wow uses its authored static poses; v3.0.59 retargets those
  -- same three poses onto BelleStarmon by matching skeleton bone names.
  if d and (r.behaviorId=="BELLESTARMON" or r.behaviorId=="WOW") then
    d.runtimeSkinSelectorPreview=true
  end
  if r.behaviorId=="BELLESTARMON" and d and d.selectorIdleDelta
      and (tonumber(d.selectorIdleFrameCount) or 0)>1 then
    local dur=tonumber(d.selectorIdleDuration) or 0.65
    if dur<=0 then dur=0.65 end
    d.runtimeSelectorIdlePhase=((self.animationTime or 0)/dur)%1
  end
  -- Fake standing player: normal characters use their authored idle; Belle
  -- and Wow receive their selector-only pose overrides above. Use pcall so
  -- the selector-only flag is cleared even if a host renderer throws here.
  local skeletonOK,skeletonErr=pcall(r.updateSkeleton,r,{},false,0,0)
  if d then d.runtimeSkinSelectorPreview=nil; d.runtimeSelectorIdlePhase=nil end
  if not skeletonOK then return nil end
  r:skin()
  if not uploadCurrentSkin(r,Voxel3D) then return nil end
  if not r:ensureImage() then return nil end

  local minX,minY,minZ,maxX,maxY,maxZ=currentBounds(r)
  if not minX then return nil end
  local h=math.max(0.001,maxY-minY)
  local cx=(minX+maxX)*0.5
  local cz=(minZ+maxZ)*0.5
  local targetH=32
  local baseScale=targetH/h
  local halfW=(maxX-minX)*0.5*baseScale
  local halfD=(maxZ-minZ)*0.5*baseScale
  local aspect=sceneW/math.max(1,sceneH)
  local tanHalf=math.tan(FOV*0.5)
  -- Frame the camera for the maximum 150% user scale once, then leave the
  -- camera fixed while the slider changes model scale. That makes the preview
  -- show the actual relative size change rather than silently zooming the
  -- camera to cancel it out.
  local maxPreviewScale=1.50
  local verticalDistance=(targetH*0.52*maxPreviewScale)/tanHalf
  local horizontalDistance=(halfW*maxPreviewScale)/math.max(0.05,tanHalf*aspect)
  local depthDistance=(halfD*maxPreviewScale)/tanHalf
  local distance=math.max(verticalDistance,horizontalDistance,depthDistance,8)*1.18
  local zoom=tonumber(self.zoom) or 1.0
  if zoom<0.22 then zoom=0.22 elseif zoom>6.00 then zoom=6.00 end
  distance=distance/zoom

  local scale=baseScale*previewScale
  -- Keep the model itself fixed. User inspection is now a true orbit camera, so
  -- attached accessories and animated bones do not receive artificial viewport
  -- rotation transforms. modelYawOffset is intrinsic import orientation only.
  local model=Mat4.rotateY((tonumber(r.modelYawOffset) or 0)+(tonumber(r.faceFlipYaw) or 0))
  model=Mat4.mul(model,Mat4.scale(scale,scale,scale))
  model=Mat4.mul(model,Mat4.translate(-cx,-minY,-cz))

  local yaw=tonumber(self.yaw) or 0
  local pitch=tonumber(self.pitch) or 0
  local cp,sp=math.cos(pitch),math.sin(pitch)
  local cy,sy=math.cos(yaw),math.sin(yaw)
  -- Camera basis for screen-plane panning. At yaw=0, right is +X and camera
  -- up is +Y. The focus offset rotates with the orbit, matching Blender-style
  -- viewport panning instead of becoming world-axis locked.
  local rightX,rightY,rightZ=cy,0,-sy
  local upX,upY,upZ=-sy*sp,cp,-cy*sp
  local panX=tonumber(self.panX) or 0
  local panY=tonumber(self.panY) or 0
  local focusX=rightX*panX+upX*panY
  local focusY=targetH*0.50+rightY*panX+upY*panY
  local focusZ=rightZ*panX+upZ*panY
  local eyeX=focusX+sy*cp*distance
  local eyeY=focusY+sp*distance
  local eyeZ=focusZ+cy*cp*distance

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
      eye={eyeX,eyeY,eyeZ},
      focus={focusX,focusY,focusZ},
      up={upX,upY,upZ},
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
      -- v3.0.17: imported accessories are transformed into the character's
      -- current bone space on CPU and drawn with the exact same body model
      -- matrix, so hats/necklaces/etc follow the selector animation too.
      if drew and type(r.red3dDrawAccessories)=="function" then
        pcall(r.red3dDrawAccessories,r,Voxel3D,model,nil,true)
      end
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
