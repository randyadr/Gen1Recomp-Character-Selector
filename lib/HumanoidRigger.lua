-- Red 3D Player in-game humanoid rigger.
-- v3.0.30: first-class character-import rigging with improved automatic joint
-- placement and anatomical skin weighting.  Static OBJ/FBX/DAE package data is
-- converted into the runtime skinned-model format used by main.lua; imported
-- package code is never executed.

local M={}

local function clamp(v,a,b)
  v=tonumber(v) or 0
  if v<a then return a elseif v>b then return b end
  return v
end

local function copyPoint(p)
  return {tonumber(p and p[1]) or 0,tonumber(p and p[2]) or 0,tonumber(p and p[3]) or 0}
end

local function sortNumbers(t)
  table.sort(t,function(a,b) return a<b end)
  return t
end

local function quantile(t,q,default)
  if type(t)~="table" or #t==0 then return default or 0 end
  sortNumbers(t)
  q=clamp(q,0,1)
  local f=1+(#t-1)*q
  local i=math.floor(f)
  local r=f-i
  if i>=#t then return t[#t] end
  return t[i]*(1-r)+t[i+1]*r
end

local function boundsFor(def)
  local minX,minY,minZ=math.huge,math.huge,math.huge
  local maxX,maxY,maxZ=-math.huge,-math.huge,-math.huge
  for _,v in ipairs(def and def.corners or {}) do
    local x,y,z=tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0
    if x<minX then minX=x end; if x>maxX then maxX=x end
    if y<minY then minY=y end; if y>maxY then maxY=y end
    if z<minZ then minZ=z end; if z>maxZ then maxZ=z end
  end
  if minX==math.huge then return {-0.5,-0.5,-0.5,0.5,0.5,0.5} end
  return {minX,minY,minZ,maxX,maxY,maxZ}
end

local function sliceStats(def,targetY,window,cx,maxAbsX)
  local xs,zs={},{ }
  for _,v in ipairs(def and def.corners or {}) do
    local x,y,z=tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0
    if math.abs(y-targetY)<=window and (not maxAbsX or math.abs(x-cx)<=maxAbsX) then
      xs[#xs+1]=x; zs[#zs+1]=z
    end
  end
  if #xs<6 then return nil end
  return {
    xMid=quantile(xs,0.50,cx), zMid=quantile(zs,0.50,0),
    x10=quantile(xs,0.10,cx), x25=quantile(xs,0.25,cx),
    x75=quantile(xs,0.75,cx), x90=quantile(xs,0.90,cx),
  }
end

local JOINT_ORDER={
  "HIPS","SPINE","CHEST","NECK","HEAD",
  "L_SHOULDER","L_ELBOW","L_HAND",
  "R_SHOULDER","R_ELBOW","R_HAND",
  "L_HIP","L_KNEE","L_FOOT",
  "R_HIP","R_KNEE","R_FOOT",
}
M.JOINT_ORDER=JOINT_ORDER

local MIRROR={
  L_SHOULDER="R_SHOULDER",R_SHOULDER="L_SHOULDER",
  L_ELBOW="R_ELBOW",R_ELBOW="L_ELBOW",
  L_HAND="R_HAND",R_HAND="L_HAND",
  L_HIP="R_HIP",R_HIP="L_HIP",
  L_KNEE="R_KNEE",R_KNEE="L_KNEE",
  L_FOOT="R_FOOT",R_FOOT="L_FOOT",
}
M.MIRROR=MIRROR
M.WEIGHT_STYLES={"TIGHT","BALANCED","SOFT"}

function M.prettyJoint(name)
  local pretty={
    HIPS="Hips",SPINE="Spine",CHEST="Chest",NECK="Neck",HEAD="Head",
    L_SHOULDER="Left Shoulder",L_ELBOW="Left Elbow",L_HAND="Left Hand",
    R_SHOULDER="Right Shoulder",R_ELBOW="Right Elbow",R_HAND="Right Hand",
    L_HIP="Left Hip",L_KNEE="Left Knee",L_FOOT="Left Foot",
    R_HIP="Right Hip",R_KNEE="Right Knee",R_FOOT="Right Foot",
  }
  return pretty[name] or tostring(name or "Joint")
end

local function detectedExtremity(def,cx,side,minAbsX)
  local xs,ys,zs={},{},{}
  for _,v in ipairs(def and def.corners or {}) do
    local x,y,z=tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0
    local sx=(x-cx)*side
    if sx>=minAbsX then xs[#xs+1]=x; ys[#ys+1]=y; zs[#zs+1]=z end
  end
  if #xs<12 then return nil end
  -- Use the farthest 15% on the requested side as the hand cluster rather than
  -- trusting a single extremal vertex (weapons/hair often create outliers).
  local cutoff=side<0 and quantile(xs,0.15,cx) or quantile(xs,0.85,cx)
  local hx,hy,hz={},{},{}
  for _,v in ipairs(def.corners or {}) do
    local x,y,z=tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0
    if (side<0 and x<=cutoff) or (side>0 and x>=cutoff) then
      hx[#hx+1]=x; hy[#hy+1]=y; hz[#hz+1]=z
    end
  end
  return {quantile(hx,0.50,cx),quantile(hy,0.50,0),quantile(hz,0.50,0)}
end

function M.defaultConfig(def)
  local b=boundsFor(def)
  local minX,minY,minZ,maxX,maxY,maxZ=b[1],b[2],b[3],b[4],b[5],b[6]
  local w,h,d=maxX-minX,maxY-minY,maxZ-minZ
  if w<1e-6 then w=1 end; if h<1e-6 then h=1 end; if d<1e-6 then d=1 end
  local cx=(minX+maxX)*0.5
  local cz=(minZ+maxZ)*0.5
  local function y(frac) return minY+h*frac end

  -- Estimate the body centre from torso slices. This helps models whose bounding
  -- box is widened by hair, capes, weapons, or an asymmetric pose.
  local core=sliceStats(def,y(0.58),h*0.055,cx,w*0.24)
  if core then cx=core.xMid or cx; cz=core.zMid or cz end
  local chestSlice=sliceStats(def,y(0.69),h*0.05,cx,w*0.28)
  local hipSlice=sliceStats(def,y(0.44),h*0.05,cx,w*0.22)
  local chestZ=(chestSlice and chestSlice.zMid) or cz
  local hipZ=(hipSlice and hipSlice.zMid) or cz

  local shoulderX=w*0.235
  if chestSlice then
    local left=cx-(chestSlice.x25 or cx)
    local right=(chestSlice.x75 or cx)-cx
    local est=math.max(left,right)
    if est>w*0.12 and est<w*0.34 then shoulderX=est*1.08 end
  end
  shoulderX=clamp(shoulderX,w*0.16,w*0.30)
  local hipX=clamp(w*0.095,w*0.065,w*0.14)

  local lHand=detectedExtremity(def,cx,-1,w*0.30)
  local rHand=detectedExtremity(def,cx, 1,w*0.30)
  local defaultHandY=y(0.66)
  lHand=lHand or {cx-w*0.48,defaultHandY,chestZ}
  rHand=rHand or {cx+w*0.48,defaultHandY,chestZ}
  lHand[1]=clamp(lHand[1],minX,cx-w*0.30)
  rHand[1]=clamp(rHand[1],cx+w*0.30,maxX)
  -- Hands below the hips usually mean a non-rig-friendly pose or geometry
  -- outlier. Keep the initial markers in a usable A/T-pose range.
  lHand[2]=clamp(lHand[2],y(0.48),y(0.76))
  rHand[2]=clamp(rHand[2],y(0.48),y(0.76))

  local lShoulder={cx-shoulderX,y(0.72),chestZ}
  local rShoulder={cx+shoulderX,y(0.72),chestZ}
  local lElbow={lShoulder[1]+(lHand[1]-lShoulder[1])*0.52,lShoulder[2]+(lHand[2]-lShoulder[2])*0.52,(lShoulder[3]+lHand[3])*0.5}
  local rElbow={rShoulder[1]+(rHand[1]-rShoulder[1])*0.52,rShoulder[2]+(rHand[2]-rShoulder[2])*0.52,(rShoulder[3]+rHand[3])*0.5}

  -- Feet use lower-side clusters when possible, which is more reliable than a
  -- fixed X offset on models with wide stances.
  local function footFor(side)
    local xs,zs={},{}
    local cutY=y(0.13)
    for _,v in ipairs(def and def.corners or {}) do
      local x,yy,z=tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0
      if yy<=cutY and ((side<0 and x<cx) or (side>0 and x>=cx)) then xs[#xs+1]=x; zs[#zs+1]=z end
    end
    local fx=quantile(xs,0.50,cx+side*w*0.10)
    local fz=quantile(zs,0.55,cz+d*0.05)
    return {fx,y(0.055),fz}
  end
  local lf,rf=footFor(-1),footFor(1)
  local lhip={cx-hipX,y(0.44),hipZ}; local rhip={cx+hipX,y(0.44),hipZ}
  local lknee={lhip[1]+(lf[1]-lhip[1])*0.52,y(0.245),(lhip[3]+lf[3])*0.5}
  local rknee={rhip[1]+(rf[1]-rhip[1])*0.52,y(0.245),(rhip[3]+rf[3])*0.5}

  return {
    mirror=true,height=24,armRest=-90,softness=0.070,weightStyle="BALANCED",
    joints={
      HIPS={cx,y(0.455),hipZ}, SPINE={cx,y(0.565),(hipZ+chestZ)*0.52},
      CHEST={cx,y(0.685),chestZ}, NECK={cx,y(0.815),chestZ}, HEAD={cx,y(0.925),chestZ},
      L_SHOULDER=lShoulder,L_ELBOW=lElbow,L_HAND=lHand,
      R_SHOULDER=rShoulder,R_ELBOW=rElbow,R_HAND=rHand,
      L_HIP=lhip,L_KNEE=lknee,L_FOOT=lf,
      R_HIP=rhip,R_KNEE=rknee,R_FOOT=rf,
    },
    bounds=b,
  }
end

local function pointSegmentDistanceSq(px,py,pz,a,b)
  local ax,ay,az=a[1],a[2],a[3]
  local bx,by,bz=b[1],b[2],b[3]
  local dx,dy,dz=bx-ax,by-ay,bz-az
  local len=dx*dx+dy*dy+dz*dz
  local t=0
  if len>1e-10 then t=((px-ax)*dx+(py-ay)*dy+(pz-az)*dz)/len end
  if t<0 then t=0 elseif t>1 then t=1 end
  local qx,qy,qz=ax+dx*t,ay+dy*t,az+dz*t
  local ex,ey,ez=px-qx,py-qy,pz-qz
  return ex*ex+ey*ey+ez*ez,t
end

local function translate16(x,y,z)
  return {1,0,0,x, 0,1,0,y, 0,0,1,z, 0,0,0,1}
end

local function uvFor(def,index,settings)
  local src=def.corners[index]
  local u,v=tonumber(src[4]) or 0,tonumber(src[5]) or 0
  local variants=type(def.uvVariants)=="table" and def.uvVariants or nil
  local vi=math.floor(tonumber(settings and settings.uvVariant) or 1)
  if variants and variants[vi] and variants[vi].uvs and variants[vi].uvs[index] then
    local uv=variants[vi].uvs[index]
    u,v=tonumber(uv[1]) or u,tonumber(uv[2]) or v
  end
  if settings and settings.swapUV then u,v=v,u end
  if settings and settings.flipU then u=1-u end
  if settings and settings.flipV then v=1-v end
  return u,v
end

local function rigSkeleton(config)
  local J=config.joints
  local hips=copyPoint(J.HIPS)
  local spine=copyPoint(J.SPINE or {hips[1],hips[2]+((J.CHEST[2]-hips[2])*0.45),hips[3]})
  local chest=copyPoint(J.CHEST); local neck=copyPoint(J.NECK); local head=copyPoint(J.HEAD)
  local function toe(foot,side)
    return {foot[1]+side*0.002,foot[2]-0.005,foot[3]+0.075}
  end
  local bones={
    {name="Waist",parent=0,pos=hips,region="pelvis"},
    {name="Hips",parent=1,pos=hips,region="pelvis"},
    {name="Spine1",parent=2,pos=spine,region="torso"},
    {name="Spine2",parent=3,pos=chest,region="torso"},
    {name="Neck",parent=4,pos=neck,region="neck"},
    {name="Head",parent=5,pos=head,region="head"},
    {name="LeftArm",parent=4,pos=copyPoint(J.L_SHOULDER),region="larm"},
    {name="LeftForeArm",parent=7,pos=copyPoint(J.L_ELBOW),region="larm"},
    {name="LeftHand",parent=8,pos=copyPoint(J.L_HAND),region="larm"},
    {name="RightArm",parent=4,pos=copyPoint(J.R_SHOULDER),region="rarm"},
    {name="RightForeArm",parent=10,pos=copyPoint(J.R_ELBOW),region="rarm"},
    {name="RightHand",parent=11,pos=copyPoint(J.R_HAND),region="rarm"},
    {name="LeftUpLeg",parent=2,pos=copyPoint(J.L_HIP),region="lleg"},
    {name="LeftLeg",parent=13,pos=copyPoint(J.L_KNEE),region="lleg"},
    {name="LeftFoot",parent=14,pos=copyPoint(J.L_FOOT),region="lleg"},
    {name="LeftToeBase",parent=15,pos=toe(J.L_FOOT,-1),region="lleg"},
    {name="RightUpLeg",parent=2,pos=copyPoint(J.R_HIP),region="rleg"},
    {name="RightLeg",parent=17,pos=copyPoint(J.R_KNEE),region="rleg"},
    {name="RightFoot",parent=18,pos=copyPoint(J.R_FOOT),region="rleg"},
    {name="RightToeBase",parent=19,pos=toe(J.R_FOOT,1),region="rleg"},
  }
  return bones
end

local function smoothGate(a,b,v)
  if a==b then return v>=b and 1 or 0 end
  local t=(v-a)/(b-a)
  if t<=0 then return 0 elseif t>=1 then return 1 end
  return t*t*(3-2*t)
end

local function childForBone(bones,id)
  for j,b in ipairs(bones) do if b.parent==id then return b,j end end
  return nil,nil
end

local function anatomicalGate(px,py,pz,bone,id,config)
  local J=config.joints
  local cx=J.HIPS[1]
  local hipY=J.HIPS[2]
  local neckY=J.NECK[2]
  local shoulderSpan=math.max(math.abs(J.L_SHOULDER[1]-cx),math.abs(J.R_SHOULDER[1]-cx),0.08)
  local ax=math.abs(px-cx)
  local sideLeft=px<=cx
  local region=bone.region
  if region=="larm" or region=="rarm" then
    local correct=(region=="larm" and sideLeft) or (region=="rarm" and not sideLeft)
    local sideGate=correct and 1 or 0.001
    local outward=smoothGate(shoulderSpan*0.48,shoulderSpan*0.93,ax)
    local yLow=smoothGate(hipY-0.03,hipY+0.10,py)
    local yHigh=1-smoothGate(neckY+0.12,neckY+0.28,py)
    return sideGate*(0.02+0.98*outward)*yLow*yHigh
  elseif region=="lleg" or region=="rleg" then
    local correct=(region=="lleg" and sideLeft) or (region=="rleg" and not sideLeft)
    local sideGate=correct and 1 or 0.001
    local yGate=1-smoothGate(hipY+0.02,hipY+0.16,py)
    local centerPenalty=0.20+0.80*smoothGate(shoulderSpan*0.06,shoulderSpan*0.28,ax)
    return sideGate*yGate*centerPenalty
  elseif region=="pelvis" then
    local yGate=(1-smoothGate(hipY+0.10,hipY+0.26,py))*smoothGate(hipY-0.24,hipY-0.07,py)
    local sideGate=1-smoothGate(shoulderSpan*0.88,shoulderSpan*1.25,ax)
    return math.max(0.02,yGate*sideGate)
  elseif region=="torso" then
    local low=smoothGate(hipY-0.03,hipY+0.10,py)
    local high=1-smoothGate(neckY+0.03,neckY+0.16,py)
    local side=1-smoothGate(shoulderSpan*0.78,shoulderSpan*1.13,ax)
    return math.max(0.005,low*high*side)
  elseif region=="neck" then
    local yGate=smoothGate(J.CHEST[2]+0.02,neckY-0.03,py)*(1-smoothGate(J.HEAD[2],J.HEAD[2]+0.09,py))
    local side=1-smoothGate(shoulderSpan*0.38,shoulderSpan*0.78,ax)
    return math.max(0.003,yGate*side)
  elseif region=="head" then
    local yGate=smoothGate(neckY-0.01,J.HEAD[2]-0.02,py)
    local side=1-smoothGate(shoulderSpan*0.68,shoulderSpan*1.12,ax)
    return math.max(0.003,yGate*side)
  end
  return 1
end

local function weightStyleParams(config)
  local style=tostring(config.weightStyle or "BALANCED"):upper()
  local softness=clamp(config.softness or 0.070,0.015,0.25)
  if style=="TIGHT" then return softness*0.72,1.35
  elseif style=="SOFT" then return softness*1.35,0.96 end
  return softness,1.14
end

local function weightVertex(px,py,pz,bones,config)
  local sigma,power=weightStyleParams(config)
  local scored={}
  for id,bone in ipairs(bones) do
    -- Waist is a controller/root duplicate of Hips in this generated rig. Keep
    -- a tiny contribution available for compatibility but prefer Hips itself.
    local child=childForBone(bones,id)
    local d2
    if child then d2=pointSegmentDistanceSq(px,py,pz,bone.pos,child.pos)
    else
      local dx,dy,dz=px-bone.pos[1],py-bone.pos[2],pz-bone.pos[3]
      d2=dx*dx+dy*dy+dz*dz
    end
    local gate=anatomicalGate(px,py,pz,bone,id,config)
    local base=1/((d2+sigma*sigma)^power)
    if id==1 then base=base*0.08 end
    local w=base*gate
    if w>1e-10 then scored[#scored+1]={id=id,w=w} end
  end
  table.sort(scored,function(a,b) return a.w>b.w end)
  if #scored==0 then return {{id=2,w=1}} end
  -- Do not keep a fourth influence merely because four slots are available.
  -- Tiny cross-region weights are a common source of armpit/inner-thigh pulling.
  -- Prune anything below 0.5% of the strongest raw candidate, then normalize.
  local threshold=scored[1].w*0.005
  local chosen={}
  for i=1,#scored do
    if scored[i].w>=threshold then
      chosen[#chosen+1]=scored[i]
      if #chosen>=4 then break end
    end
  end
  if #chosen==0 then chosen[1]=scored[1] end
  local sum=0
  for i=1,#chosen do sum=sum+chosen[i].w end
  if sum<=1e-12 then return {{id=2,w=1}} end
  local out={}
  for i=1,#chosen do out[i]={id=chosen[i].id,w=chosen[i].w/sum} end
  return out
end

function M.buildData(def,config,textureSettings)
  if not def or type(def.corners)~="table" or #def.corners<3 then return nil,"model has no triangle mesh" end
  local defaults=M.defaultConfig(def)
  config=config or defaults
  config.joints=config.joints or defaults.joints
  if not config.joints.SPINE then config.joints.SPINE=copyPoint(defaults.joints.SPINE) end
  local bones=rigSkeleton(config)

  -- Deduplicate geometric positions before auto-weighting. Imported meshes often
  -- repeat the same control point for every triangle/UV seam; skinning those as
  -- separate positions wastes a large amount of CPU and memory. Corners keep
  -- their own UVs while sharing one weighted position whenever XYZ matches.
  local uniquePos,cornerToPos,posMap={},{},{}
  for i,v in ipairs(def.corners) do
    local x,y,z=tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0
    local key=string.format("%.7f|%.7f|%.7f",x,y,z)
    local pid=posMap[key]
    if not pid then
      pid=#uniquePos+1
      posMap[key]=pid
      uniquePos[pid]={x,y,z}
    end
    cornerToPos[i]=pid
  end

  local data={
    boneCount=#bones,
    positionCount=#uniquePos,
    cornerCount=#def.corners,
    triangleCount=math.floor(#def.corners/3),
    boneName={},boneParent={},boneLocal={},
    posFirst={},posCount={},infBone={},infX={},infY={},infZ={},infW={},
    cornerPos={},cornerU={},cornerV={},order={down={},up={},left={},right={},north={},south={}},
    animBone={},
  }

  for i,b in ipairs(bones) do
    data.boneName[i]=b.name
    data.boneParent[i]=b.parent
    local parentPos=(b.parent>0 and bones[b.parent].pos) or {0,0,0}
    local m=translate16(b.pos[1]-parentPos[1],b.pos[2]-parentPos[2],b.pos[3]-parentPos[3])
    for k=1,16 do data.boneLocal[#data.boneLocal+1]=m[k] end
  end
  data.animBone={
    Waist=1,Hips=2,Spine1=3,Spine2=4,Neck=5,Head=6,
    LArm=7,LForeArm=8,LHand=9,RArm=10,RForeArm=11,RHand=12,
    LThigh=13,LLeg=14,LFoot=15,LToe=16,RThigh=17,RLeg=18,RFoot=19,RToe=20,
  }

  local b=boundsFor(def)
  data.bounds={b[1],b[2],b[3],b[4],b[5],b[6]}
  local inf=0
  for i,v in ipairs(uniquePos) do
    local px,py,pz=v[1],v[2],v[3]
    local weights=weightVertex(px,py,pz,bones,config)
    data.posFirst[i]=inf+1
    data.posCount[i]=#weights
    for _,iw in ipairs(weights) do
      inf=inf+1
      local bp=bones[iw.id].pos
      data.infBone[inf]=iw.id
      data.infX[inf]=px-bp[1]; data.infY[inf]=py-bp[2]; data.infZ[inf]=pz-bp[3]
      data.infW[inf]=iw.w
    end
  end
  for i,_ in ipairs(def.corners) do
    data.cornerPos[i]=cornerToPos[i]
    local u,vv=uvFor(def,i,textureSettings)
    data.cornerU[i]=u; data.cornerV[i]=vv
  end

  for tri=1,data.triangleCount do
    data.order.down[tri]=tri; data.order.up[tri]=tri; data.order.left[tri]=tri
    data.order.right[tri]=tri; data.order.north[tri]=tri; data.order.south[tri]=tri
  end
  return data
end

function M.serializeJoints(config)
  local pieces={}
  for _,name in ipairs(JOINT_ORDER) do
    local p=config and config.joints and config.joints[name]
    if p then pieces[#pieces+1]=string.format("%s:%.6f,%.6f,%.6f",name,p[1] or 0,p[2] or 0,p[3] or 0) end
  end
  return table.concat(pieces,";")
end

function M.deserializeJoints(text,defaults)
  local out={}
  for k,v in pairs(defaults or {}) do out[k]=copyPoint(v) end
  if type(text)~="string" then return out end
  for name,x,y,z in text:gmatch("([A-Z_]+):([%+%-%.%deE]+),([%+%-%.%deE]+),([%+%-%.%deE]+)") do
    if out[name] then out[name]={tonumber(x) or out[name][1],tonumber(y) or out[name][2],tonumber(z) or out[name][3]} end
  end
  return out
end

function M.bounds(def) return boundsFor(def) end

return M
