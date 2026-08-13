-- Red 3D Player donor-rig cloner.
-- v3.0.60: bind an unrigged OBJ/FBX/DAE mesh to an existing character's
-- skeleton by transferring nearby donor vertex weights in bind-pose space.
-- The donor skeleton and embedded animation clips are reused verbatim, so the
-- imported mesh remains compatible with the donor's gameplay/selector poses.

local M={}

local function clamp(v,a,b)
  v=tonumber(v) or 0
  if v<a then return a elseif v>b then return b end
  return v
end

local function copyArray(t)
  local o={}
  for i=1,#(t or {}) do o[i]=t[i] end
  return o
end

local function copyMap(t)
  local o={}
  for k,v in pairs(t or {}) do o[k]=v end
  return o
end

local function copy16(flat,base)
  return {
    flat[base],flat[base+1],flat[base+2],flat[base+3],
    flat[base+4],flat[base+5],flat[base+6],flat[base+7],
    flat[base+8],flat[base+9],flat[base+10],flat[base+11],
    flat[base+12],flat[base+13],flat[base+14],flat[base+15],
  }
end

local function mul16(a,b,o)
  o=o or {}
  for r=0,3 do
    local r4=r*4
    for c=1,4 do
      o[r4+c]=a[r4+1]*b[c]+a[r4+2]*b[4+c]+a[r4+3]*b[8+c]+a[r4+4]*b[12+c]
    end
  end
  return o
end

local function transformPoint(m,x,y,z)
  return m[1]*x+m[2]*y+m[3]*z+m[4],
         m[5]*x+m[6]*y+m[7]*z+m[8],
         m[9]*x+m[10]*y+m[11]*z+m[12]
end

local function inversePoint(m,x,y,z)
  -- Invert the affine 3x3 + translation portion. This supports ordinary bone
  -- rotation/translation as well as the occasional bind-scale from an FBX.
  local a,b,c=m[1],m[2],m[3]
  local d,e,f=m[5],m[6],m[7]
  local g,h,i=m[9],m[10],m[11]
  local det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
  if math.abs(det)<1e-12 then
    -- Generated donor rigs are normally orthonormal. Fall back to transpose so
    -- one malformed helper bone cannot make the whole import fail.
    local px,py,pz=x-m[4],y-m[8],z-m[12]
    return a*px+d*py+g*pz,b*px+e*py+h*pz,c*px+f*py+i*pz
  end
  local inv=1/det
  local A=(e*i-f*h)*inv
  local B=(c*h-b*i)*inv
  local C=(b*f-c*e)*inv
  local D=(f*g-d*i)*inv
  local E=(a*i-c*g)*inv
  local F=(c*d-a*f)*inv
  local G=(d*h-e*g)*inv
  local H=(b*g-a*h)*inv
  local I=(a*e-b*d)*inv
  local px,py,pz=x-m[4],y-m[8],z-m[12]
  return A*px+B*py+C*pz,D*px+E*py+F*pz,G*px+H*py+I*pz
end

local function bindWorldFor(data)
  local out={}
  for bone=1,tonumber(data and data.boneCount) or 0 do
    local localM=copy16(data.boneLocal,(bone-1)*16+1)
    local parent=tonumber(data.boneParent[bone]) or 0
    if parent>0 then out[bone]=mul16(out[parent],localM,{}) else out[bone]=localM end
  end
  return out
end

local function donorBindPositions(data,bindWorld)
  local out={}
  for p=1,tonumber(data.positionCount) or 0 do
    local first=tonumber(data.posFirst[p]) or 1
    local count=tonumber(data.posCount[p]) or 0
    local x,y,z=0,0,0
    local total=0
    for j=first,first+count-1 do
      local bone=tonumber(data.infBone[j]) or 1
      local w=tonumber(data.infW[j]) or 0
      local tx,ty,tz=transformPoint(bindWorld[bone],tonumber(data.infX[j]) or 0,tonumber(data.infY[j]) or 0,tonumber(data.infZ[j]) or 0)
      x=x+tx*w; y=y+ty*w; z=z+tz*w; total=total+w
    end
    if total>1e-9 and math.abs(total-1)>1e-6 then x=x/total; y=y/total; z=z/total end
    out[p]={x,y,z}
  end
  return out
end

local function boundsFromPoints(points)
  local minX,minY,minZ=math.huge,math.huge,math.huge
  local maxX,maxY,maxZ=-math.huge,-math.huge,-math.huge
  for _,v in ipairs(points or {}) do
    local x,y,z=v[1],v[2],v[3]
    if x<minX then minX=x end; if x>maxX then maxX=x end
    if y<minY then minY=y end; if y>maxY then maxY=y end
    if z<minZ then minZ=z end; if z>maxZ then maxZ=z end
  end
  if minX==math.huge then return {-0.5,-0.5,-0.5,0.5,0.5,0.5} end
  return {minX,minY,minZ,maxX,maxY,maxZ}
end

local function donorFrame(data,positions)
  local b=(type(data.bounds)=="table" and #data.bounds>=6) and data.bounds or boundsFromPoints(positions)
  local minX,minY,minZ,maxX,maxY,maxZ=b[1],b[2],b[3],b[4],b[5],b[6]
  local span=math.max(maxX-minX,maxY-minY,maxZ-minZ,1e-8)
  return {cx=(minX+maxX)*0.5,cy=(minY+maxY)*0.5,cz=(minZ+maxZ)*0.5,span=span,bounds={minX,minY,minZ,maxX,maxY,maxZ}}
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

local function transformedNormalized(v,settings)
  local x,y,z=tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0
  -- Importer parsers already normalize source geometry to a centered unit-size
  -- frame. These switches are intentionally small and reversible, for exports
  -- whose handedness/up axis differs from the donor.
  if settings and settings.swapYZ then y,z=z,y end
  if settings and settings.flipX then x=-x end
  if settings and settings.flipY then y=-y end
  if settings and settings.flipZ then z=-z end
  local scale=clamp(settings and settings.fitScale or 1.0,0.50,1.50)
  local ox=tonumber(settings and settings.fitX) or 0
  local oy=tonumber(settings and settings.fitY) or 0
  local oz=tonumber(settings and settings.fitZ) or 0
  return x*scale+ox,y*scale+oy,z*scale+oz
end

local function gridKey(x,y,z,cell)
  return math.floor(x/cell).."|"..math.floor(y/cell).."|"..math.floor(z/cell)
end

local function pointKey(x,y,z)
  return string.format("%.7f|%.7f|%.7f",x,y,z)
end

local function buildGrid(points,cell)
  local grid,exact={},{}
  for i,p in ipairs(points) do
    local key=gridKey(p[1],p[2],p[3],cell)
    local bucket=grid[key]
    if not bucket then bucket={}; grid[key]=bucket end
    bucket[#bucket+1]=i
    local ekey=pointKey(p[1],p[2],p[3])
    if exact[ekey]==nil then exact[ekey]=i end
  end
  return grid,exact
end

local function nearestPositions(grid,points,x,y,z,cell,k)
  k=k or 4
  local cx,cy,cz=math.floor(x/cell),math.floor(y/cell),math.floor(z/cell)
  local candidates={}
  local seen={}
  -- Expand just far enough to find a useful local surface neighborhood. With
  -- donor meshes in the 10k-50k point range, radius 3 normally finds dozens.
  for radius=0,4 do
    for gx=cx-radius,cx+radius do
      for gy=cy-radius,cy+radius do
        for gz=cz-radius,cz+radius do
          if radius==0 or gx==cx-radius or gx==cx+radius or gy==cy-radius or gy==cy+radius or gz==cz-radius or gz==cz+radius then
            local bucket=grid[gx.."|"..gy.."|"..gz]
            if bucket then
              for _,idx in ipairs(bucket) do
                if not seen[idx] then
                  seen[idx]=true
                  local p=points[idx]
                  local dx,dy,dz=x-p[1],y-p[2],z-p[3]
                  candidates[#candidates+1]={idx=idx,d2=dx*dx+dy*dy+dz*dz}
                end
              end
            end
          end
        end
      end
    end
    if #candidates>=k*3 then break end
  end
  if #candidates==0 then
    -- Extremely unusual (huge added geometry outside the donor). Fall back to
    -- a coarse full scan so the import remains usable instead of failing.
    local stride=math.max(1,math.floor(#points/2500))
    for idx=1,#points,stride do
      local p=points[idx]
      local dx,dy,dz=x-p[1],y-p[2],z-p[3]
      candidates[#candidates+1]={idx=idx,d2=dx*dx+dy*dy+dz*dz}
    end
  end
  table.sort(candidates,function(a,b) return a.d2<b.d2 end)
  while #candidates>k do table.remove(candidates) end
  return candidates
end

local PHYSICS_FIELDS={
  "physicsBreastWeight","physicsThighWeight","physicsButtWeight","physicsHairWeight",
  "physicsSide","physicsThighSide","physicsButtSide","physicsHairSide",
}

local function blendedDonorWeights(data,near)
  local byBone={}
  local geoWeights={}
  local exact=(near[1] and near[1].d2 or 1)>1e-12 and false or true
  local geoSum=0
  for n,hit in ipairs(near) do
    local gw
    if exact then gw=(n==1) and 1 or 0 else gw=1/(hit.d2+1e-8) end
    geoWeights[n]=gw; geoSum=geoSum+gw
  end
  if geoSum<=1e-12 then geoSum=1 end
  for n,hit in ipairs(near) do
    local gw=geoWeights[n]/geoSum
    if gw>0 then
      local first=tonumber(data.posFirst[hit.idx]) or 1
      local count=tonumber(data.posCount[hit.idx]) or 0
      for j=first,first+count-1 do
        local bone=tonumber(data.infBone[j]) or 1
        local w=(tonumber(data.infW[j]) or 0)*gw
        byBone[bone]=(byBone[bone] or 0)+w
      end
    end
  end
  local list={}
  for bone,w in pairs(byBone) do if w>1e-8 then list[#list+1]={bone=bone,w=w} end end
  table.sort(list,function(a,b) return a.w>b.w end)
  while #list>4 do table.remove(list) end
  local sum=0; for _,v in ipairs(list) do sum=sum+v.w end
  if sum<=1e-10 then return {{bone=1,w=1}},geoWeights,geoSum end
  for _,v in ipairs(list) do v.w=v.w/sum end
  return list,geoWeights,geoSum
end

local function blendedPhysics(data,near,geoWeights,geoSum,field)
  local src=data[field]
  if type(src)~="table" then return nil end
  local value=0
  for n,hit in ipairs(near) do value=value+(tonumber(src[hit.idx]) or 0)*(geoWeights[n]/geoSum) end
  if field:find("Side",1,true) then
    if value>0.05 then return 1 elseif value<-0.05 then return -1 else return 0 end
  end
  return clamp(value,0,1)
end

local MESH_KEYS={
  positionCount=true,cornerCount=true,triangleCount=true,posFirst=true,posCount=true,
  infBone=true,infX=true,infY=true,infZ=true,infW=true,cornerPos=true,cornerU=true,
  cornerV=true,order=true,bounds=true,
  physicsBreastWeight=true,physicsThighWeight=true,physicsButtWeight=true,physicsHairWeight=true,
  physicsSide=true,physicsThighSide=true,physicsButtSide=true,physicsHairSide=true,
}

local function cloneDonorRigAndClips(dst,donor)
  -- Skeleton identity must be exact for donor behavior/animations.
  dst.boneCount=tonumber(donor.boneCount) or 0
  dst.boneName=copyArray(donor.boneName)
  dst.boneParent=copyArray(donor.boneParent)
  dst.boneLocal=copyArray(donor.boneLocal)
  dst.animBone=copyMap(donor.animBone)

  -- Copy animation metadata/clips without donor geometry. Keep references to the
  -- immutable numeric clip arrays; duplicating thousands of matrices would make
  -- each runtime import needlessly expensive.
  for k,v in pairs(donor) do
    if not MESH_KEYS[k] and k~="boneCount" and k~="boneName" and k~="boneParent" and k~="boneLocal" and k~="animBone"
        and tostring(k):sub(1,7)~="runtime" and tostring(k):sub(1,1)~="_" then
      local key=tostring(k)
      if key:match("Delta$") or key:match("FrameCount$") or key:match("Duration$") or key:match("Count$") then
        dst[k]=v
      end
    end
  end
end

function M.buildData(def,donorData,settings)
  if not def or type(def.corners)~="table" or #def.corners<3 then return nil,"imported model has no triangle mesh" end
  if not donorData or not tonumber(donorData.boneCount) or not donorData.boneLocal or not donorData.boneParent
      or not donorData.posFirst or not donorData.posCount or not donorData.infBone or not donorData.infW then
    return nil,"donor character has incomplete rig data"
  end

  local bindWorld=bindWorldFor(donorData)
  local donorPos=donorBindPositions(donorData,bindWorld)
  if #donorPos<3 then return nil,"donor has no weighted bind positions" end
  local frame=donorFrame(donorData,donorPos)
  local cell=math.max(frame.span*0.028,1e-5)
  local grid,exactMap=buildGrid(donorPos,cell)

  local uniquePos,cornerToPos,posMap={},{},{}
  for i,v in ipairs(def.corners) do
    local nx,ny,nz=transformedNormalized(v,settings)
    -- Def corners are already centered/unit-normalized by AccessoryImporter.
    -- Place them into the donor's bind frame so the cloned skeleton occupies
    -- the same body coordinates as the original character.
    local x=frame.cx+nx*frame.span
    local y=frame.cy+ny*frame.span
    local z=frame.cz+nz*frame.span
    local key=string.format("%.7f|%.7f|%.7f",x,y,z)
    local pid=posMap[key]
    if not pid then
      pid=#uniquePos+1; posMap[key]=pid; uniquePos[pid]={x,y,z,nx,ny,nz}
    end
    cornerToPos[i]=pid
  end

  local data={}
  cloneDonorRigAndClips(data,donorData)
  data.positionCount=#uniquePos
  data.cornerCount=#def.corners
  data.triangleCount=math.floor(#def.corners/3)
  data.posFirst={}; data.posCount={}; data.infBone={}; data.infX={}; data.infY={}; data.infZ={}; data.infW={}
  data.cornerPos={}; data.cornerU={}; data.cornerV={}
  data.order={down={},up={},left={},right={},north={},south={}}
  for _,field in ipairs(PHYSICS_FIELDS) do if type(donorData[field])=="table" then data[field]={} end end

  local inf=0
  local nearestDistanceSum=0
  local nearestDistanceMax=0
  for p,v in ipairs(uniquePos) do
    local x,y,z=v[1],v[2],v[3]
    local exact=exactMap[pointKey(x,y,z)]
    local near=exact and {{idx=exact,d2=0}} or nearestPositions(grid,donorPos,x,y,z,cell,4)
    local weights,geoWeights,geoSum=blendedDonorWeights(donorData,near)
    data.posFirst[p]=inf+1; data.posCount[p]=#weights
    for _,iw in ipairs(weights) do
      inf=inf+1
      local lx,ly,lz=inversePoint(bindWorld[iw.bone],x,y,z)
      data.infBone[inf]=iw.bone; data.infX[inf]=lx; data.infY[inf]=ly; data.infZ[inf]=lz; data.infW[inf]=iw.w
    end
    for _,field in ipairs(PHYSICS_FIELDS) do
      if data[field] then data[field][p]=blendedPhysics(donorData,near,geoWeights,geoSum,field) end
    end
    local dist=math.sqrt((near[1] and near[1].d2) or 0)
    nearestDistanceSum=nearestDistanceSum+dist
    if dist>nearestDistanceMax then nearestDistanceMax=dist end
  end

  for i=1,#def.corners do
    data.cornerPos[i]=cornerToPos[i]
    local u,v=uvFor(def,i,settings)
    data.cornerU[i]=u; data.cornerV[i]=v
  end
  for tri=1,data.triangleCount do
    data.order.down[tri]=tri; data.order.up[tri]=tri; data.order.left[tri]=tri
    data.order.right[tri]=tri; data.order.north[tri]=tri; data.order.south[tri]=tri
  end
  local pts={}
  for i,v in ipairs(uniquePos) do pts[i]={v[1],v[2],v[3]} end
  data.bounds=boundsFromPoints(pts)
  data._donorTransferStats={
    donorPositions=#donorPos,targetPositions=#uniquePos,
    meanNearest=(#uniquePos>0) and nearestDistanceSum/#uniquePos or 0,
    maxNearest=nearestDistanceMax,donorSpan=frame.span,
  }
  return data
end

return M
