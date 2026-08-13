-- Red 3D Player accessory ZIP importer / renderer.
-- Static accessory meshes only: OBJ (+ MTL), FBX first mesh, and Collada DAE.
-- ZIP contents are parsed as data; no code from an accessory package is executed.

local M={}

local MAX_ZIP_BYTES=192*1024*1024
local MAX_MODEL_BYTES=96*1024*1024
local MAX_TEXTURE_BYTES=64*1024*1024
local MAX_TEXTURE_OPTIONS=16
local MAX_TEXTURE_OPTION_TOTAL_BYTES=96*1024*1024
local MAX_TRIANGLES=120000
local MAX_FILES=1024

local function clamp(v,a,b)
  v=tonumber(v) or 0
  if v<a then return a elseif v>b then return b end
  return v
end

local function basename(p)
  p=tostring(p or ""):gsub("\\","/")
  return p:match("([^/]+)$") or p
end

local function dirname(p)
  p=tostring(p or ""):gsub("\\","/")
  return p:match("^(.*)/[^/]*$") or ""
end

local function stripExt(p)
  local b=basename(p)
  return (b:gsub("%.[^%.]+$",""))
end

local function ext(p)
  local e=tostring(p or ""):lower():match("%.([%w]+)$")
  return e or ""
end

local function safeToken(v,fallback)
  local s=tostring(v or fallback or "Accessory")
  s=s:gsub("[%c]"," "):gsub("^%s+",""):gsub("%s+$","")
  if s=="" then s=tostring(fallback or "Accessory") end
  return s
end

local function safeId(v)
  local s=safeToken(v,"ACCESSORY"):upper():gsub("[^A-Z0-9_]+","_")
  s=s:gsub("^_+",""):gsub("_+$","")
  if s=="" then s="ACCESSORY" end
  return s
end

local function rollingHash(s)
  local h=7
  for i=1,#s do h=(h*131+s:byte(i))%2147483647 end
  return h
end

local function normalizeRel(path)
  path=tostring(path or ""):gsub("\\","/")
  path=path:gsub("^/+","")
  local out={}
  for part in path:gmatch("[^/]+") do
    if part==".." then
      if #out>0 then table.remove(out) end
    elseif part~="." and part~="" then
      out[#out+1]=part
    end
  end
  return table.concat(out,"/")
end

local function joinRel(a,b)
  b=normalizeRel(b)
  if b=="" then return normalizeRel(a) end
  if tostring(b):match("^[A-Za-z]:") then return normalizeRel(b:match("[^/\\]+$") or b) end
  a=normalizeRel(a)
  if a=="" then return b end
  return normalizeRel(a.."/"..b)
end

local function numList(text,maxCount)
  local out={}
  if type(text)~="string" then return out end
  for tok in text:gmatch("[^,%s]+") do
    local n=tonumber(tok)
    if n then
      out[#out+1]=n
      if maxCount and #out>=maxCount then break end
    end
  end
  return out
end

local function finalizeMesh(corners,label)
  if type(corners)~="table" or #corners<3 then return nil,"mesh has no triangles" end
  local triCount=math.floor(#corners/3)
  if triCount>MAX_TRIANGLES then return nil,"mesh exceeds "..MAX_TRIANGLES.." triangle safety limit" end

  local minX,minY,minZ=math.huge,math.huge,math.huge
  local maxX,maxY,maxZ=-math.huge,-math.huge,-math.huge
  for _,v in ipairs(corners) do
    local x,y,z=tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0
    if x<minX then minX=x end; if x>maxX then maxX=x end
    if y<minY then minY=y end; if y>maxY then maxY=y end
    if z<minZ then minZ=z end; if z>maxZ then maxZ=z end
  end
  local cx,cy,cz=(minX+maxX)*0.5,(minY+maxY)*0.5,(minZ+maxZ)*0.5
  local ex,ey,ez=maxX-minX,maxY-minY,maxZ-minZ
  local span=math.max(ex,ey,ez,1e-9)
  for _,v in ipairs(corners) do
    v[1]=((tonumber(v[1]) or 0)-cx)/span
    v[2]=((tonumber(v[2]) or 0)-cy)/span
    v[3]=((tonumber(v[3]) or 0)-cz)/span
    v[4]=tonumber(v[4]) or 0
    v[5]=tonumber(v[5]) or 0
  end
  return {
    label=safeToken(label,"Accessory"),
    corners=corners,
    triangleCount=triCount,
    normalizedBounds={-ex/(2*span),-ey/(2*span),-ez/(2*span),ex/(2*span),ey/(2*span),ez/(2*span)},
  }
end

local function parseObjIndex(tok,count)
  local n=tonumber(tok)
  if not n or n==0 then return nil end
  if n<0 then n=count+n+1 end
  if n<1 or n>count then return nil end
  return n
end

local function parseOBJ(text,label)
  if type(text)~="string" then return nil,"OBJ data unavailable" end
  local pos,uv={},{}
  local corners={}
  local mtllib=nil
  local firstMaterial=nil
  local currentMaterial=nil
  local materialNames={}
  local materialIndex={}

  local function materialSlot(name)
    name=safeToken(name,"Material")
    if not materialIndex[name] then
      materialNames[#materialNames+1]=name
      materialIndex[name]=#materialNames-1 -- FBX/OBJ runtime material slots are zero based.
    end
    return materialIndex[name]
  end

  for line in (text.."\n"):gmatch("([^\r\n]*)\r?\n") do
    local tag,rest=line:match("^%s*([^%s#]+)%s*(.-)%s*$")
    if tag=="v" then
      local a,b,c=rest:match("^([^%s]+)%s+([^%s]+)%s+([^%s]+)")
      local x,y,z=tonumber(a),tonumber(b),tonumber(c)
      if x and y and z then pos[#pos+1]={x,y,z} end
    elseif tag=="vt" then
      local a,b=rest:match("^([^%s]+)%s+([^%s]+)")
      local u,v=tonumber(a),tonumber(b)
      if u and v then uv[#uv+1]={u,1-v} end
    elseif tag=="mtllib" and not mtllib then
      mtllib=rest:match("^%s*(.-)%s*$")
    elseif tag=="usemtl" then
      currentMaterial=rest:match("^%s*(.-)%s*$")
      firstMaterial=firstMaterial or currentMaterial
      materialSlot(currentMaterial)
    elseif tag=="f" then
      local refs={}
      for part in rest:gmatch("%S+") do
        local a,b=part:match("^([^/]+)/?([^/]*)")
        local vi=parseObjIndex(a,#pos)
        local ti=(b and b~="") and parseObjIndex(b,#uv) or nil
        if vi then refs[#refs+1]={vi,ti} end
      end
      if #refs>=3 then
        local mat=materialSlot(currentMaterial or "Material")
        for k=2,#refs-1 do
          local ids={refs[1],refs[k],refs[k+1]}
          for _,r in ipairs(ids) do
            local pp=pos[r[1]]
            local t=r[2] and uv[r[2]] or nil
            corners[#corners+1]={pp[1],pp[2],pp[3],t and t[1] or 0,t and t[2] or 0,mat}
          end
          if #corners/3>MAX_TRIANGLES then return nil,"OBJ exceeds triangle safety limit" end
        end
      end
    end
  end
  local mesh,err=finalizeMesh(corners,label)
  if not mesh then return nil,err end
  mesh.mtllib=mtllib
  mesh.material=firstMaterial
  mesh.materialNames=materialNames
  mesh.materialCount=math.max(1,#materialNames)
  mesh.format="OBJ"
  return mesh
end

local function extractAsciiArray(text,name,startPos)
  startPos=startPos or 1
  local p=text:find(name.."%s*:%s*%*?%d*%s*{",startPos)
  if not p then return nil end
  local s,e=text:find("a%s*:%s*",p)
  if not s then return nil end
  local close=text:find("}",e+1,true)
  if not close then return nil end
  return numList(text:sub(e+1,close-1)),close+1
end

local function balancedBlock(text,startPos)
  local open=text:find("{",startPos,true)
  if not open then return nil,nil end
  local depth=0
  local quote=false
  local escape=false
  for i=open,#text do
    local ch=text:sub(i,i)
    if quote then
      if escape then escape=false
      elseif ch=="\\" then escape=true
      elseif ch=='"' then quote=false end
    else
      if ch=='"' then quote=true
      elseif ch=="{" then depth=depth+1
      elseif ch=="}" then
        depth=depth-1
        if depth==0 then return text:sub(open+1,i-1),i+1 end
      end
    end
  end
  return nil,nil
end

local function asciiQuotedValue(block,name)
  if type(block)~="string" then return nil end
  return block:match(name.."%s*:%s*\"([^\"]+)\"")
end

local function normalizedMapping(v)
  return tostring(v or "ByPolygonVertex"):lower():gsub("[^a-z]","")
end

local function normalizedReference(v)
  return tostring(v or "IndexToDirect"):lower():gsub("[^a-z]","")
end

local function materialForMeta(layer,meta)
  if not layer or type(layer.values)~="table" or #layer.values==0 then return 0 end
  local mapping=normalizedMapping(layer.mapping)
  local idx=1
  if mapping=="bypolygon" then idx=meta.poly
  elseif mapping=="bypolygonvertex" then idx=meta.pv
  elseif mapping=="byvertice" or mapping=="byvertex" or mapping=="bycontrolpoint" then idx=meta.cp
  elseif mapping=="allsame" then idx=1
  end
  local v=tonumber(layer.values[idx])
  if v==nil then v=tonumber(layer.values[1]) or 0 end
  if v<0 then v=0 end
  return math.floor(v)
end

local function uvForMeta(layer,meta,overrideMapping,overrideReference)
  if not layer or type(layer.uv)~="table" or #layer.uv<2 then return 0,0 end
  local mapping=normalizedMapping(overrideMapping or layer.mapping)
  local reference=normalizedReference(overrideReference or layer.reference)
  local mapIndex
  if mapping=="bypolygonvertex" then mapIndex=meta.pv
  elseif mapping=="byvertice" or mapping=="byvertex" or mapping=="bycontrolpoint" then mapIndex=meta.cp
  elseif mapping=="bypolygon" then mapIndex=meta.poly
  elseif mapping=="allsame" then mapIndex=1
  else mapIndex=meta.pv end
  local directIndex=mapIndex
  if reference:find("index",1,true) then
    local raw=layer.uvIndex and tonumber(layer.uvIndex[mapIndex]) or nil
    if raw~=nil then directIndex=math.floor(raw)+1 end
  end
  local j=(directIndex-1)*2+1
  local u=tonumber(layer.uv[j]) or 0
  local v=tonumber(layer.uv[j+1]) or 0
  return u,1-v
end

local function uvSignature(uvs)
  local h=17
  for i=1,math.min(#uvs,240) do
    local u=math.floor(((tonumber(uvs[i][1]) or 0)*8192)+0.5)
    local v=math.floor(((tonumber(uvs[i][2]) or 0)*8192)+0.5)
    h=(h*131+u*17+v*31)%2147483647
  end
  return tostring(#uvs)..":"..tostring(h)
end

local function buildFBXMesh(vertices,pvi,uvLayers,materialLayer,label)
  if type(vertices)~="table" or #vertices<3 or type(pvi)~="table" or #pvi<3 then
    return nil,"FBX mesh arrays are incomplete"
  end
  local pos={}
  for i=1,#vertices-2,3 do pos[#pos+1]={vertices[i],vertices[i+1],vertices[i+2]} end
  local corners={}
  local meta={}
  local poly={}
  local polygonVertexCursor=0
  local polygonIndex=0
  local function emitTri(a,b,c)
    for _,entry in ipairs({a,b,c}) do
      local pp=pos[entry.cp]
      local m={cp=entry.cp,pv=entry.pv,poly=polygonIndex}
      local mat=materialForMeta(materialLayer,m)
      corners[#corners+1]={pp[1],pp[2],pp[3],0,0,mat}
      meta[#meta+1]=m
    end
  end
  for _,raw in ipairs(pvi) do
    polygonVertexCursor=polygonVertexCursor+1
    local ending=raw<0
    local idx=(ending and (-raw-1) or raw)+1
    if idx>=1 and idx<=#pos then poly[#poly+1]={cp=idx,pv=polygonVertexCursor} end
    if ending then
      polygonIndex=polygonIndex+1
      if #poly>=3 then
        for k=2,#poly-1 do
          emitTri(poly[1],poly[k],poly[k+1])
          if #corners/3>MAX_TRIANGLES then return nil,"FBX exceeds triangle safety limit" end
        end
      end
      poly={}
    end
  end
  if #corners<3 then return nil,"FBX contains no usable triangles" end

  local variants={}
  local seen={}
  local function addVariant(labelText,layer,mapping,reference)
    if not layer or type(layer.uv)~="table" or #layer.uv<2 then return end
    local arr={}
    for i,m in ipairs(meta) do
      local u,v=uvForMeta(layer,m,mapping,reference)
      arr[i]={u,v}
    end
    local sig=uvSignature(arr)
    if seen[sig] then return end
    seen[sig]=true
    variants[#variants+1]={label=labelText,uvs=arr}
  end
  for li,layer in ipairs(uvLayers or {}) do
    addVariant(string.format("UV SET %d • AUTO",li),layer,nil,nil)
  end
  local first=(uvLayers or {})[1]
  if first then
    addVariant("UV1 • POLYGON INDEX",first,"ByPolygonVertex","IndexToDirect")
    addVariant("UV1 • POLYGON DIRECT",first,"ByPolygonVertex","Direct")
    addVariant("UV1 • CONTROL POINT INDEX",first,"ByVertice","IndexToDirect")
    addVariant("UV1 • CONTROL POINT DIRECT",first,"ByVertice","Direct")
  end
  if #variants==0 then variants[1]={label="NO UV DATA",uvs={}} end
  local primary=variants[1].uvs or {}
  for i,c in ipairs(corners) do
    local t=primary[i]
    c[4],c[5]=t and t[1] or 0,t and t[2] or 0
  end
  local mesh,err=finalizeMesh(corners,label)
  if not mesh then return nil,err end
  mesh.uvVariants=variants
  local maxMat=0
  for _,c in ipairs(corners) do maxMat=math.max(maxMat,math.floor(tonumber(c[6]) or 0)) end
  mesh.materialCount=maxMat+1
  mesh.format="FBX"
  return mesh
end

local function parseFBXAscii(text,label)
  local geomPos=nil
  local search=1
  while true do
    local p=text:find("Geometry%s*:%s*",search)
    if not p then break end
    local header=text:sub(p,math.min(#text,p+320))
    if header:find('"Mesh"',1,true) then geomPos=p break end
    search=p+8
  end
  geomPos=geomPos or text:find("Geometry%s*:%s*") or 1
  local geomBlock=balancedBlock(text,geomPos)
  geomBlock=geomBlock or text
  local vertices=extractAsciiArray(geomBlock,"Vertices")
  local pvi=extractAsciiArray(geomBlock,"PolygonVertexIndex")
  if not vertices or not pvi then return nil,"ASCII FBX geometry arrays not found" end

  local uvLayers={}
  local lp=1
  while true do
    local p=geomBlock:find("LayerElementUV%s*:%s*[%-%d]+%s*{",lp)
    if not p then break end
    local block,nextPos=balancedBlock(geomBlock,p)
    if not block then break end
    uvLayers[#uvLayers+1]={
      mapping=asciiQuotedValue(block,"MappingInformationType") or "ByPolygonVertex",
      reference=asciiQuotedValue(block,"ReferenceInformationType") or "IndexToDirect",
      uv=extractAsciiArray(block,"UV") or {},
      uvIndex=extractAsciiArray(block,"UVIndex") or {},
    }
    lp=nextPos or (p+1)
  end
  if #uvLayers==0 then
    uvLayers[1]={mapping="ByPolygonVertex",reference="IndexToDirect",uv=extractAsciiArray(geomBlock,"UV") or {},uvIndex=extractAsciiArray(geomBlock,"UVIndex") or {}}
  end

  local materialLayer=nil
  local mp=geomBlock:find("LayerElementMaterial%s*:%s*[%-%d]+%s*{")
  if mp then
    local block=balancedBlock(geomBlock,mp)
    if block then materialLayer={
      mapping=asciiQuotedValue(block,"MappingInformationType") or "ByPolygon",
      reference=asciiQuotedValue(block,"ReferenceInformationType") or "IndexToDirect",
      values=extractAsciiArray(block,"Materials") or {},
    } end
  end
  local mesh,err=buildFBXMesh(vertices,pvi,uvLayers,materialLayer,label)
  if not mesh then return nil,err end

  local geomId=tostring(text:match("Geometry%s*:%s*([%-%d]+)") or "")
  local materials={}
  for id,name in text:gmatch("Material%s*:%s*([%-%d]+)%s*,%s*\"([^\"]*)\"") do materials[tostring(id)]={name=name} end
  local textures={}
  local tp=1
  while true do
    local p,id,name=text:find("Texture%s*:%s*([%-%d]+)%s*,%s*\"([^\"]*)\"",tp)
    if not p then break end
    local block,nextPos=balancedBlock(text,p)
    local file=nil
    if block then
      file=block:match("RelativeFilename%s*:%s*\"([^\"]+)\"") or block:match("FileName%s*:%s*\"([^\"]+)\"")
    end
    textures[tostring(id)]={name=name,file=file}
    tp=nextPos or (p+1)
  end
  local connections={}
  for line in (text.."\n"):gmatch("([^\r\n]*)\r?\n") do
    local kind,src,dst,prop=line:match('C:%s*\"([^\"]+)\"%s*,%s*([%-%d]+)%s*,%s*([%-%d]+)%s*,?%s*\"?([^\"]*)')
    if kind and src and dst then connections[#connections+1]={kind=kind,src=tostring(src),dst=tostring(dst),prop=prop} end
  end
  local function resolveMaterialTextures()
    if geomId=="" then return end
    local modelId=nil
    for _,c in ipairs(connections) do
      if c.src==geomId then modelId=c.dst break elseif c.dst==geomId then modelId=c.src break end
    end
    if not modelId then return end
    local mids={}
    for _,c in ipairs(connections) do
      if c.dst==modelId and materials[c.src] then mids[#mids+1]=c.src
      elseif c.src==modelId and materials[c.dst] then mids[#mids+1]=c.dst end
    end
    local names,paths={},{ }
    for i,mid in ipairs(mids) do
      names[i]=materials[mid] and materials[mid].name or ("Material "..i)
      local best=nil
      for _,c in ipairs(connections) do
        local tid=nil
        if c.dst==mid and textures[c.src] then tid=c.src elseif c.src==mid and textures[c.dst] then tid=c.dst end
        if tid then
          local prop=tostring(c.prop or ""):lower()
          local candidate=textures[tid].file
          if candidate and (not best or prop:find("diffuse",1,true) or prop:find("basecolor",1,true)) then best=candidate end
        end
      end
      paths[i]=best
    end
    mesh.materialNames=names
    mesh.materialTextureNames=paths
    if #names>mesh.materialCount then mesh.materialCount=#names end
  end
  resolveMaterialTextures()
  return mesh
end

local function byteU32(s,p)
  local a,b,c,d=s:byte(p,p+3)
  if not d then return nil,p end
  return a+b*256+c*65536+d*16777216,p+4
end

local function byteI32(s,p)
  local v,np=byteU32(s,p); if not v then return nil,np end
  if v>=2147483648 then v=v-4294967296 end
  return v,np
end

local function byteU64(s,p)
  local lo,np=byteU32(s,p); if not lo then return nil,np end
  local hi,np2=byteU32(s,np); if not hi then return nil,np2 end
  return lo+hi*4294967296,np2
end

local function unpackNumber(fmt,data,pos)
  if not (love and love.data and love.data.unpack) then return nil,pos end
  local ok,a,nextPos=pcall(love.data.unpack,fmt,data,pos)
  if ok and type(a)=="number" then return a,tonumber(nextPos) or pos end
  return nil,pos
end

local function inflateArray(payload)
  if not (love and love.data and love.data.decompress) then return nil end
  local ok,out=pcall(love.data.decompress,"string","zlib",payload)
  if ok and type(out)=="string" then return out end
  return nil
end

local BINARY_ARRAY_NODE={Vertices=true,PolygonVertexIndex=true,UV=true,UVIndex=true,Materials=true}

local function readBinaryProperty(data,pos,nodeName)
  local typeByte=data:sub(pos,pos); pos=pos+1
  if typeByte=="Y" then local v; v,pos=unpackNumber("<i2",data,pos); return v,pos
  elseif typeByte=="C" then local v=data:byte(pos) or 0; return v~=0,pos+1
  elseif typeByte=="I" then local v; v,pos=byteI32(data,pos); return v,pos
  elseif typeByte=="F" then local v; v,pos=unpackNumber("<f",data,pos); return v,pos
  elseif typeByte=="D" then local v; v,pos=unpackNumber("<d",data,pos); return v,pos
  elseif typeByte=="L" then local v; v,pos=unpackNumber("<i8",data,pos); return v,pos
  elseif typeByte=="S" or typeByte=="R" then
    local len; len,pos=byteU32(data,pos); if not len then return nil,pos end
    local v=data:sub(pos,pos+len-1); return v,pos+len
  elseif typeByte=="f" or typeByte=="d" or typeByte=="l" or typeByte=="i" or typeByte=="b" then
    local length,encoding,compLen
    length,pos=byteU32(data,pos); encoding,pos=byteU32(data,pos); compLen,pos=byteU32(data,pos)
    if not length or not compLen then return nil,pos end
    local payload=data:sub(pos,pos+compLen-1); pos=pos+compLen
    if not BINARY_ARRAY_NODE[nodeName] then return nil,pos end
    if encoding==1 then payload=inflateArray(payload); if not payload then return nil,pos end end
    local vals={}; local pp=1; local fmt=nil
    if typeByte=="d" then fmt="<d" elseif typeByte=="f" then fmt="<f" elseif typeByte=="l" then fmt="<i8" end
    local maxN=math.min(length,MAX_TRIANGLES*18)
    for _=1,maxN do
      local v
      if typeByte=="i" then v,pp=byteI32(payload,pp)
      elseif typeByte=="b" then v=payload:byte(pp) or 0; pp=pp+1
      else v,pp=unpackNumber(fmt,payload,pp) end
      if v==nil then break end
      vals[#vals+1]=v
    end
    return vals,pos
  end
  return nil,pos
end

local function idKey(v)
  if v==nil then return nil end
  if type(v)=="number" then return string.format("%.0f",v) end
  return tostring(v)
end

local function parseFBXBinary(data,label)
  if data:sub(1,20)~="Kaydara FBX Binary  " then return nil,"not binary FBX" end
  local version=select(1,byteU32(data,24)) or 7400
  local wide=version>=7500
  local nullSize=wide and 25 or 13
  local scene={geometry=nil,materials={},textures={},connections={}}

  local function parseNode(pos,depth,ctx)
    if depth>72 or pos>#data then return #data+1 end
    local endOffset,numProps,propLen
    if wide then
      endOffset,pos=byteU64(data,pos); numProps,pos=byteU64(data,pos); propLen,pos=byteU64(data,pos)
    else
      endOffset,pos=byteU32(data,pos); numProps,pos=byteU32(data,pos); propLen,pos=byteU32(data,pos)
    end
    local nameLen=data:byte(pos) or 0; pos=pos+1
    if not endOffset or endOffset==0 then return pos end
    local name=data:sub(pos,pos+nameLen-1); pos=pos+nameLen
    local propertyStart=pos
    local props={}
    for i=1,(tonumber(numProps) or 0) do
      local v,np=readBinaryProperty(data,pos,name)
      props[i]=v
      if not np or np<=pos then break end
      pos=np
    end
    local declaredEnd=propertyStart+(tonumber(propLen) or 0)
    if declaredEnd>pos and declaredEnd<=#data+1 then pos=declaredEnd end

    local childCtx=ctx
    if name=="Geometry" and not scene.geometry then
      local isMesh=false
      for _,v in ipairs(props) do if type(v)=="string" and v:lower()=="mesh" then isMesh=true break end end
      if isMesh then
        scene.geometry={id=idKey(props[1]),uvLayers={},materialLayer=nil}
        childCtx={kind="geometry",obj=scene.geometry}
      end
    elseif name=="Material" then
      local id=idKey(props[1]); if id then scene.materials[id]={name=tostring(props[2] or "Material")} end
    elseif name=="Texture" then
      local id=idKey(props[1]); local obj={name=tostring(props[2] or "Texture")}; if id then scene.textures[id]=obj; childCtx={kind="texture",obj=obj} end
    elseif name=="C" and props[2]~=nil and props[3]~=nil then
      scene.connections[#scene.connections+1]={kind=tostring(props[1] or ""),src=idKey(props[2]),dst=idKey(props[3]),prop=tostring(props[4] or "")}
    elseif ctx and ctx.kind=="geometry" then
      if name=="Vertices" and type(props[1])=="table" then ctx.obj.vertices=props[1]
      elseif name=="PolygonVertexIndex" and type(props[1])=="table" then ctx.obj.pvi=props[1]
      elseif name=="LayerElementUV" then
        local layer={mapping="ByPolygonVertex",reference="IndexToDirect",uv={},uvIndex={}}
        ctx.obj.uvLayers[#ctx.obj.uvLayers+1]=layer; childCtx={kind="uv",obj=layer}
      elseif name=="LayerElementMaterial" then
        local layer={mapping="ByPolygon",reference="IndexToDirect",values={}}
        ctx.obj.materialLayer=layer; childCtx={kind="materialLayer",obj=layer}
      end
    elseif ctx and ctx.kind=="uv" then
      if name=="MappingInformationType" then ctx.obj.mapping=tostring(props[1] or ctx.obj.mapping)
      elseif name=="ReferenceInformationType" then ctx.obj.reference=tostring(props[1] or ctx.obj.reference)
      elseif name=="UV" and type(props[1])=="table" then ctx.obj.uv=props[1]
      elseif name=="UVIndex" and type(props[1])=="table" then ctx.obj.uvIndex=props[1] end
    elseif ctx and ctx.kind=="materialLayer" then
      if name=="MappingInformationType" then ctx.obj.mapping=tostring(props[1] or ctx.obj.mapping)
      elseif name=="ReferenceInformationType" then ctx.obj.reference=tostring(props[1] or ctx.obj.reference)
      elseif name=="Materials" and type(props[1])=="table" then ctx.obj.values=props[1] end
    elseif ctx and ctx.kind=="texture" then
      if name=="RelativeFilename" or name=="FileName" then
        if type(props[1])=="string" and props[1]~="" then ctx.obj.file=props[1] end
      end
    end

    local childEnd=math.min((tonumber(endOffset) and (tonumber(endOffset)+1)) or (#data+1),#data+1)
    while pos+nullSize<=childEnd and pos<=#data do
      local allZero=true
      for i=0,nullSize-1 do if (data:byte(pos+i) or 0)~=0 then allZero=false break end end
      if allZero then pos=pos+nullSize break end
      local np=parseNode(pos,depth+1,childCtx)
      if not np or np<=pos then break end
      pos=np
    end
    if childEnd>pos then pos=childEnd end
    return pos
  end

  local pos=28
  while pos+nullSize<=#data do
    local allZero=true
    for i=0,nullSize-1 do if (data:byte(pos+i) or 0)~=0 then allZero=false break end end
    if allZero then break end
    local np=parseNode(pos,0,nil)
    if not np or np<=pos then break end
    pos=np
  end
  local g=scene.geometry
  if not g or not g.vertices or not g.pvi then return nil,"binary FBX mesh arrays not found" end
  local mesh,err=buildFBXMesh(g.vertices,g.pvi,g.uvLayers or {},g.materialLayer,label)
  if not mesh then return nil,err end

  local modelId=nil
  if g.id then
    for _,c in ipairs(scene.connections) do
      if c.src==g.id then modelId=c.dst break elseif c.dst==g.id then modelId=c.src break end
    end
  end
  if modelId then
    local mids={}
    for _,c in ipairs(scene.connections) do
      if c.dst==modelId and scene.materials[c.src] then mids[#mids+1]=c.src
      elseif c.src==modelId and scene.materials[c.dst] then mids[#mids+1]=c.dst end
    end
    local names,paths={},{}
    for i,mid in ipairs(mids) do
      names[i]=scene.materials[mid] and scene.materials[mid].name or ("Material "..i)
      local best=nil; local bestScore=-1
      for _,c in ipairs(scene.connections) do
        local tid=nil
        if c.dst==mid and scene.textures[c.src] then tid=c.src elseif c.src==mid and scene.textures[c.dst] then tid=c.dst end
        if tid then
          local prop=tostring(c.prop or ""):lower()
          local score=(prop:find("diffuse",1,true) or prop:find("basecolor",1,true)) and 3 or 1
          if scene.textures[tid].file and score>bestScore then best=scene.textures[tid].file; bestScore=score end
        end
      end
      paths[i]=best
    end
    mesh.materialNames=names
    mesh.materialTextureNames=paths
    if #names>mesh.materialCount then mesh.materialCount=#names end
  end
  mesh.format="FBX"
  return mesh
end

local function parseFBX(data,label)
  if data:sub(1,20)=="Kaydara FBX Binary  " then return parseFBXBinary(data,label) end
  return parseFBXAscii(data,label)
end


-- Minimal, data-only Collada 1.4/1.5 static-mesh loader.  It intentionally
-- ignores skeleton/controller animation because accessories are rigidly parented
-- to the selected character bone by this mod.  Geometry supports the common
-- triangles/polylist/polygons forms, arbitrary input offsets, VERTEX indirection,
-- TEXCOORD sets, material symbols, and external diffuse image references.
local function xmlAttr(attrs,name)
  if type(attrs)~="string" then return nil end
  local escaped=tostring(name):gsub("([^%w])","%%%1")
  return attrs:match(escaped.."%s*=%s*\"([^\"]*)\"")
      or attrs:match(escaped.."%s*=%s*'([^']*)'")
end

local function xmlUnescape(s)
  s=tostring(s or "")
  s=s:gsub("&lt;","<"):gsub("&gt;",">"):gsub("&quot;",'"'):gsub("&apos;", "'"):gsub("&amp;","&")
  s=s:gsub("&#x([%da-fA-F]+);",function(h) return string.char(tonumber(h,16) or 63) end)
  s=s:gsub("&#(%d+);",function(d) return string.char(tonumber(d,10) or 63) end)
  return s
end

local function daeSourceValues(source,stride,index,componentCount)
  if not source or type(source.values)~="table" then return nil end
  stride=math.max(1,tonumber(stride) or tonumber(source.stride) or componentCount or 1)
  local first=(math.max(1,tonumber(index) or 1)-1)*stride+1
  local out={}
  for i=0,(componentCount or stride)-1 do out[i+1]=tonumber(source.values[first+i]) or 0 end
  return out
end

local function parseDAE(text,label)
  if type(text)~="string" then return nil,"DAE data unavailable" end
  if not text:find("<COLLADA",1,true) and not text:find("<collada",1,true) then
    return nil,"not a Collada document"
  end

  local upAxis=(text:match("<up_axis>%s*([^<]+)%s*</up_axis>") or "Y_UP"):upper():gsub("%s+","")
  local imagePathById={}
  for attrs,body in text:gmatch("<image([^>]*)>(.-)</image>") do
    local id=xmlAttr(attrs,"id") or xmlAttr(attrs,"name")
    local path=body:match("<init_from[^>]*>%s*(.-)%s*</init_from>")
    if id and path then imagePathById[id]=xmlUnescape(path) end
  end

  -- Material -> effect links.
  local materialEffect={}
  for attrs,body in text:gmatch("<material([^>]*)>(.-)</material>") do
    local id=xmlAttr(attrs,"id") or xmlAttr(attrs,"name")
    local instAttrs=body:match("<instance_effect([^>]*)/?>")
    local url=instAttrs and xmlAttr(instAttrs,"url")
    if id and url then materialEffect[id]=url:gsub("^#","") end
  end

  -- Effect -> diffuse/base-color image.  Resolve the standard sampler2D ->
  -- surface -> init_from chain, with fallbacks for simpler exporters.
  local effectImage={}
  for attrs,body in text:gmatch("<effect([^>]*)>(.-)</effect>") do
    local effectId=xmlAttr(attrs,"id") or xmlAttr(attrs,"name")
    if effectId then
      local surfaceToImage={}
      local samplerToSurface={}
      for npAttrs,npBody in body:gmatch("<newparam([^>]*)>(.-)</newparam>") do
        local sid=xmlAttr(npAttrs,"sid")
        if sid then
          local init=npBody:match("<surface[^>]*>.-<init_from[^>]*>%s*(.-)%s*</init_from>.-</surface>")
          if init then surfaceToImage[sid]=xmlUnescape(init) end
          local source=npBody:match("<sampler2D[^>]*>.-<source[^>]*>%s*(.-)%s*</source>.-</sampler2D>")
          if source then samplerToSurface[sid]=xmlUnescape(source) end
        end
      end
      local textureSid=nil
      local diffuse=body:match("<diffuse[^>]*>(.-)</diffuse>")
          or body:match("<base_color[^>]*>(.-)</base_color>")
          or body:match("<emission[^>]*>(.-)</emission>")
      if diffuse then
        local ta=diffuse:match("<texture([^>]*)/?>")
        if ta then textureSid=xmlAttr(ta,"texture") end
      end
      if not textureSid then
        local ta=body:match("<texture([^>]*)/?>")
        if ta then textureSid=xmlAttr(ta,"texture") end
      end
      local imageId=textureSid
      if samplerToSurface[imageId] then imageId=samplerToSurface[imageId] end
      if surfaceToImage[imageId] then imageId=surfaceToImage[imageId] end
      if imageId and imagePathById[imageId] then effectImage[effectId]=imagePathById[imageId]
      elseif imageId and (imageId:find("/",1,true) or imageId:find("\\",1,true) or imageId:find("%.[%w]+$")) then
        effectImage[effectId]=xmlUnescape(imageId)
      else
        -- Some exporters put an image id directly in a surface and omit a sampler.
        for _,candidate in pairs(surfaceToImage) do
          if imagePathById[candidate] then effectImage[effectId]=imagePathById[candidate]; break end
        end
      end
    end
  end

  -- Scene instance-material bindings map primitive symbols to actual material ids.
  local symbolMaterial={}
  for attrs in text:gmatch("<instance_material([^>]*)/?>") do
    local symbol=xmlAttr(attrs,"symbol")
    local target=xmlAttr(attrs,"target")
    if symbol and target then symbolMaterial[symbol]=target:gsub("^#","") end
  end

  local corners={}
  local materialNames={}
  local materialTextureNames={}
  local materialIndex={}
  local function materialSlot(symbol)
    symbol=safeToken(symbol or "Material","Material")
    if materialIndex[symbol]==nil then
      local slot=#materialNames
      materialIndex[symbol]=slot
      materialNames[slot+1]=symbol
      local matId=symbolMaterial[symbol] or symbol
      local effectId=materialEffect[matId]
      materialTextureNames[slot+1]=(effectId and effectImage[effectId]) or nil
    end
    return materialIndex[symbol]
  end

  local function convertUp(x,y,z)
    if upAxis=="Z_UP" then return x,z,-y end
    if upAxis=="X_UP" then return -y,x,z end
    return x,y,z
  end

  local geometryCount=0
  for geomAttrs,geomBody in text:gmatch("<geometry([^>]*)>(.-)</geometry>") do
    local meshBody=geomBody:match("<mesh[^>]*>(.-)</mesh>")
    if meshBody then
      geometryCount=geometryCount+1
      local sources={}
      for sAttrs,sBody in meshBody:gmatch("<source([^>]*)>(.-)</source>") do
        local sid=xmlAttr(sAttrs,"id")
        if sid then
          local floats=sBody:match("<float_array[^>]*>(.-)</float_array>")
          local stride=1
          local aAttrs=sBody:match("<accessor([^>]*)>") or sBody:match("<accessor([^>]*)/>")
          if aAttrs then stride=tonumber(xmlAttr(aAttrs,"stride")) or 1 end
          if floats then sources[sid]={values=numList(floats),stride=stride} end
        end
      end
      local verticesSources={}
      for vAttrs,vBody in meshBody:gmatch("<vertices([^>]*)>(.-)</vertices>") do
        local vid=xmlAttr(vAttrs,"id")
        if vid then
          for iAttrs in vBody:gmatch("<input([^>]*)/?>") do
            if tostring(xmlAttr(iAttrs,"semantic") or ""):upper()=="POSITION" then
              local src=xmlAttr(iAttrs,"source")
              if src then verticesSources[vid]=src:gsub("^#","") end
            end
          end
        end
      end

      local function parseInputs(block)
        local inputs={}; local maxOffset=0
        for attrs in block:gmatch("<input([^>]*)/?>") do
          local semantic=tostring(xmlAttr(attrs,"semantic") or ""):upper()
          local source=tostring(xmlAttr(attrs,"source") or ""):gsub("^#","")
          local offset=tonumber(xmlAttr(attrs,"offset")) or 0
          local set=tonumber(xmlAttr(attrs,"set")) or 0
          if semantic=="VERTEX" and verticesSources[source] then source=verticesSources[source]; semantic="POSITION" end
          inputs[#inputs+1]={semantic=semantic,source=source,offset=offset,set=set}
          if offset>maxOffset then maxOffset=offset end
        end
        return inputs,maxOffset+1
      end

      local function emitPrimitive(attrs,block,kind)
        local inputs,stride=parseInputs(block)
        if #inputs==0 then return true end
        local posInput=nil; local uvInput=nil
        for _,inp in ipairs(inputs) do
          if inp.semantic=="POSITION" and not posInput then posInput=inp end
          if inp.semantic=="TEXCOORD" and (not uvInput or inp.set<(uvInput.set or 999)) then uvInput=inp end
        end
        if not posInput or not sources[posInput.source] then return true end
        local mat=materialSlot(xmlAttr(attrs,"material") or "Material")
        local rawP={}
        for pBody in block:gmatch("<p[^>]*>(.-)</p>") do
          local nums=numList(pBody)
          for _,n in ipairs(nums) do rawP[#rawP+1]=math.floor(n) end
        end
        if #rawP==0 then return true end
        local refs={}
        local refCount=math.floor(#rawP/stride)
        for r=1,refCount do
          local base=(r-1)*stride
          local pi=rawP[base+posInput.offset+1]
          local ti=uvInput and rawP[base+uvInput.offset+1] or nil
          refs[r]={pi=pi and (pi+1) or nil,ti=ti and (ti+1) or nil}
        end
        local polys={}
        if kind=="triangles" then
          for i=1,#refs-2,3 do polys[#polys+1]={refs[i],refs[i+1],refs[i+2]} end
        elseif kind=="polylist" then
          local counts=numList(block:match("<vcount[^>]*>(.-)</vcount>") or "")
          local cursor=1
          for _,c in ipairs(counts) do
            c=math.max(0,math.floor(c))
            local poly={}
            for j=0,c-1 do if refs[cursor+j] then poly[#poly+1]=refs[cursor+j] end end
            if #poly>=3 then polys[#polys+1]=poly end
            cursor=cursor+c
          end
        else
          -- <polygons> gives one <p> per polygon, but the flattened fallback is
          -- still useful for exporters that only contain triangles here.
          if #refs>=3 then polys[1]=refs end
        end
        local psrc=sources[posInput.source]
        local usrc=uvInput and sources[uvInput.source] or nil
        for _,poly in ipairs(polys) do
          for k=2,#poly-1 do
            local tri={poly[1],poly[k],poly[k+1]}
            for _,ref in ipairs(tri) do
              local pp=ref.pi and daeSourceValues(psrc,psrc.stride,ref.pi,3) or nil
              if pp then
                local x,y,z=convertUp(pp[1],pp[2],pp[3])
                local u,v=0,0
                if usrc and ref.ti then
                  local uv=daeSourceValues(usrc,usrc.stride,ref.ti,2)
                  if uv then u=uv[1] or 0; v=1-(uv[2] or 0) end
                end
                corners[#corners+1]={x,y,z,u,v,mat}
                if #corners/3>MAX_TRIANGLES then return false,"DAE exceeds triangle safety limit" end
              end
            end
          end
        end
        return true
      end

      for attrs,body in meshBody:gmatch("<triangles([^>]*)>(.-)</triangles>") do
        local ok,err=emitPrimitive(attrs,body,"triangles"); if not ok then return nil,err end
      end
      for attrs,body in meshBody:gmatch("<polylist([^>]*)>(.-)</polylist>") do
        local ok,err=emitPrimitive(attrs,body,"polylist"); if not ok then return nil,err end
      end
      -- Handle <polygons> one polygon at a time so boundaries are preserved.
      for attrs,body in meshBody:gmatch("<polygons([^>]*)>(.-)</polygons>") do
        local inputsPrefix=""
        for inp in body:gmatch("<input[^>]*/?>") do inputsPrefix=inputsPrefix..inp end
        for pBody in body:gmatch("<p[^>]*>(.-)</p>") do
          local block=inputsPrefix.."<p>"..pBody.."</p>"
          local ok,err=emitPrimitive(attrs,block,"polygons"); if not ok then return nil,err end
        end
      end
    end
  end
  if geometryCount==0 then return nil,"DAE contains no mesh geometry" end
  local mesh,err=finalizeMesh(corners,label)
  if not mesh then return nil,err end
  mesh.format="DAE"
  mesh.materialNames=materialNames
  mesh.materialTextureNames=materialTextureNames
  mesh.materialCount=math.max(1,#materialNames)
  return mesh
end

local function parseMTL(text,material)
  if type(text)~="string" then return nil end
  local active=nil
  local first=nil
  for line in (text.."\n"):gmatch("([^\r\n]*)\r?\n") do
    local tag,rest=line:match("^%s*([^%s#]+)%s*(.-)%s*$")
    if tag=="newmtl" then active=rest
    elseif tag=="map_Kd" then
      local last=nil
      for tok in rest:gmatch("%S+") do last=tok end
      if last then
        first=first or last
        if material and active==material then return last end
      end
    end
  end
  return first
end

local function parseMTLAll(text)
  local out={}
  if type(text)~="string" then return out end
  local active=nil
  for line in (text.."\n"):gmatch("([^\r\n]*)\r?\n") do
    local tag,rest=line:match("^%s*([^%s#]+)%s*(.-)%s*$")
    if tag=="newmtl" then active=rest:match("^%s*(.-)%s*$")
    elseif tag=="map_Kd" and active then
      local last=nil
      for tok in rest:gmatch("%S+") do last=tok end
      if last then out[active]=last end
    end
  end
  return out
end

local function recursiveList(root,out,depth)
  out=out or {}; depth=depth or 0
  if depth>12 or #out>=MAX_FILES then return out end
  local fs=love and love.filesystem
  if not (fs and fs.getDirectoryItems and fs.getInfo) then return out end
  local ok,items=pcall(fs.getDirectoryItems,root)
  if not ok or type(items)~="table" then return out end
  table.sort(items)
  for _,name in ipairs(items) do
    if #out>=MAX_FILES then break end
    local p=(root=="" and name) or (root.."/"..name)
    local okInfo,info=pcall(fs.getInfo,p)
    if okInfo and info then
      if info.type=="directory" then recursiveList(p,out,depth+1)
      elseif info.type=="file" then out[#out+1]=p end
    end
  end
  return out
end

local IMAGE_EXT={png=true,jpg=true,jpeg=true,bmp=true,tga=true,dds=true}

-- Keep several plausible images from the accessory ZIP instead of permanently
-- guessing one at import time. FBX packages commonly include albedo, normal,
-- roughness, metallic, masks, and previews side-by-side; picking the first file
-- can therefore make an otherwise-correct mesh look wildly striped or tinted.
local function collectTextureOptions(modelPath,modelBytes,mesh,files,mountRoot)
  local fs=love.filesystem
  local candidates={}
  for _,p in ipairs(files) do
    if IMAGE_EXT[ext(p)] then candidates[#candidates+1]=p end
  end
  if #candidates==0 then return {},1,{} end

  local wanted=nil
  if mesh and mesh.format=="OBJ" and mesh.mtllib then
    local mtlPath=joinRel(dirname(modelPath),mesh.mtllib)
    local full=mountRoot.."/"..mtlPath
    local ok,mtl=pcall(fs.read,full)
    if ok and type(mtl)=="string" then
      wanted=parseMTL(mtl,mesh.material)
      local all=parseMTLAll(mtl)
      mesh.materialTextureNames=mesh.materialTextureNames or {}
      for i,name in ipairs(mesh.materialNames or {}) do
        if all[name] then mesh.materialTextureNames[i]=joinRel(dirname(mtlPath),all[name]) end
      end
    end
    if wanted then wanted=joinRel(dirname(mtlPath),wanted) end
  end

  local wantedNorm=wanted and normalizeRel(wanted):lower() or nil
  local wantedBase=wantedNorm and basename(wantedNorm) or nil
  local modelStem=basename(stripExt(modelPath)):lower()
  local modelText=type(modelBytes)=="string" and modelBytes or ""

  local function scorePath(full)
    local rel=full:sub(#mountRoot+2)
    local nrel=normalizeRel(rel):lower()
    local b=basename(nrel)
    local stem=stripExt(b):lower()
    local score=0
    if wantedNorm and nrel==wantedNorm then score=score+2000
    elseif wantedBase and b==wantedBase then score=score+1700 end
    local rawBase=basename(rel)
    if rawBase~="" and modelText:find(rawBase,1,true) then score=score+1200 end
    if stem==modelStem then score=score+650 end
    if stem:find(modelStem,1,true) or modelStem:find(stem,1,true) then score=score+180 end
    if b:find("albedo",1,true) or b:find("diffuse",1,true) or b:find("basecolor",1,true)
        or b:find("base_color",1,true) or b:find("colormap",1,true) or b:find("_color",1,true) then
      score=score+420
    end
    if b:find("normal",1,true) or b:find("_nrm",1,true) or b:find("rough",1,true)
        or b:find("metal",1,true) or b:find("spec",1,true) or b:find("occlusion",1,true)
        or b:find("_ao",1,true) or b:find("emiss",1,true) or b:find("mask",1,true) then
      score=score-500
    end
    return score,rel
  end

  table.sort(candidates,function(a,b)
    local sa,ra=scorePath(a); local sb,rb=scorePath(b)
    if sa~=sb then return sa>sb end
    return tostring(ra):lower()<tostring(rb):lower()
  end)

  local options={}
  local total=0
  local pathIndex={}
  for _,full in ipairs(candidates) do
    if #options>=MAX_TEXTURE_OPTIONS then break end
    local ok,bytes=pcall(fs.read,full)
    if ok and type(bytes)=="string" and #bytes<=MAX_TEXTURE_BYTES
        and total+#bytes<=MAX_TEXTURE_OPTION_TOTAL_BYTES then
      local rel=normalizeRel(full:sub(#mountRoot+2))
      options[#options+1]={label=basename(rel),path=rel,ext=ext(full),bytes=bytes}
      local idx=#options
      pathIndex[rel:lower()]=idx
      pathIndex[basename(rel):lower()]=pathIndex[basename(rel):lower()] or idx
      total=total+#bytes
    end
  end

  local materialTextureIndices={}
  local distinct={}
  for i,path in ipairs(mesh and mesh.materialTextureNames or {}) do
    if path then
      local n=normalizeRel(path):lower()
      local idx=pathIndex[n] or pathIndex[basename(n)]
      if idx then materialTextureIndices[i]=idx; distinct[idx]=true end
    end
  end
  local distinctCount=0; for _ in pairs(distinct) do distinctCount=distinctCount+1 end
  if mesh then
    mesh.materialTextureIndices=materialTextureIndices
    mesh.defaultAutoMaterialTextures=(tonumber(mesh.materialCount) or 1)>1 and (#options>1) and (distinctCount>1 or #options>1)
  end
  return options,1,materialTextureIndices
end

local function inferDefaults(label)
  local s=tostring(label or ""):lower()
  if s:find("hat",1,true) or s:find("cap",1,true) or s:find("crown",1,true)
      or s:find("helmet",1,true) or s:find("tiara",1,true) then
    return "HEAD",0,0.075,0,0.19,0,0,0
  elseif s:find("necklace",1,true) or s:find("chain",1,true) or s:find("choker",1,true)
      or s:find("collar",1,true) or s:find("pendant",1,true) then
    return "NECK",0,-0.015,0.025,0.13,0,0,0
  elseif s:find("glass",1,true) or s:find("goggle",1,true) or s:find("mask",1,true) then
    return "HEAD",0,0,0.045,0.13,0,0,0
  elseif s:find("ear",1,true) then
    return "HEAD",0,0,0,0.08,0,0,0
  elseif s:find("sword",1,true) or s:find("gun",1,true) or s:find("weapon",1,true) then
    return "RIGHT_HAND",0,0,0,0.20,0,0,0
  elseif s:find("bracelet",1,true) or s:find("watch",1,true) then
    return "LEFT_HAND",0,0,0,0.09,0,0,0
  end
  return "CHEST",0,0,0.03,0.16,0,0,0
end

function M.ensureFolders(root)
  root=normalizeRel(root or "red3d_accessories")
  local fs=love and love.filesystem
  if not fs then return false end
  if fs.createDirectory then
    pcall(fs.createDirectory,root)
    pcall(fs.createDirectory,root.."/imports")
  end
  if fs.write then
    local isCharacterRoot=root:lower():find("character",1,true)~=nil
    local message=isCharacterRoot
      and "Drop CHARACTER OBJ, FBX, or DAE files here (textures/MTL may sit beside them), or use ZIP packages. Open Skin Selector > Character Settings > Import Character > Scan.\n"
      or "Drop ACCESSORY model ZIPs here. Each ZIP may contain OBJ+MTL+textures, FBX+textures, or Collada DAE+textures. Open Skin Selector > Accessories > Scan Accessory ZIP Folder.\n"
    pcall(fs.write,root.."/imports/README.txt",message)
  end
  return true
end

function M.nativeImportFolder(root)
  root=normalizeRel(root or "red3d_accessories")
  if love and love.filesystem and love.filesystem.getSaveDirectory then
    local ok,p=pcall(love.filesystem.getSaveDirectory)
    if ok and p then return tostring(p).."/"..root.."/imports" end
  end
  return root.."/imports"
end

function M.scan(root,log)
  root=normalizeRel(root or "red3d_accessories")
  M.ensureFolders(root)
  local fs=love and love.filesystem
  if not (fs and fs.getDirectoryItems and fs.read and fs.newFileData and fs.mount and fs.unmount) then
    return {},0,{"LÖVE ZIP mounting is unavailable"},M.nativeImportFolder(root)
  end
  local okItems,items=pcall(fs.getDirectoryItems,root.."/imports")
  if not okItems or type(items)~="table" then return {},0,{"could not list accessory import folder"},M.nativeImportFolder(root) end
  table.sort(items)
  local defs={}; local failed=0; local errors={}

  for _,zipName in ipairs(items) do
    if tostring(zipName):lower():match("%.zip$") then
      local zipRel=root.."/imports/"..zipName
      local okZip,zipBytes=pcall(fs.read,zipRel)
      if not okZip or type(zipBytes)~="string" then
        failed=failed+1; errors[#errors+1]=zipName..": unreadable"
      elseif #zipBytes>MAX_ZIP_BYTES then
        failed=failed+1; errors[#errors+1]=zipName..": ZIP exceeds safety limit"
      else
        local okFD,fd=pcall(fs.newFileData,zipBytes,basename(zipName))
        if not okFD or not fd then
          failed=failed+1; errors[#errors+1]=zipName..": FileData creation failed"
        else
          local mount="__red3d_acc_"..tostring(rollingHash(zipName..#zipBytes))
          local okMount,mounted=pcall(fs.mount,fd,mount,true)
          if not okMount or mounted==false then
            failed=failed+1; errors[#errors+1]=zipName..": ZIP mount failed"
          else
            local files=recursiveList(mount,{})
            local models={}
            for _,full in ipairs(files) do
              local e=ext(full)
              if e=="obj" or e=="fbx" or e=="dae" then models[#models+1]=full end
            end
            table.sort(models,function(a,b)
              local ea,eb=ext(a),ext(b)
              local order={obj=1,fbx=2,dae=3}
              if ea~=eb then return (order[ea] or 9)<(order[eb] or 9) end
              return a<b
            end)
            if #models==0 then
              failed=failed+1; errors[#errors+1]=zipName..": no OBJ, FBX, or DAE found"
            else
              for _,full in ipairs(models) do
                local rel=full:sub(#mount+2)
                local okModel,modelBytes=pcall(fs.read,full)
                if not okModel or type(modelBytes)~="string" or #modelBytes>MAX_MODEL_BYTES then
                  failed=failed+1; errors[#errors+1]=zipName.." / "..rel..": model unreadable/too large"
                else
                  local label=stripExt(rel)
                  local mesh,err
                  local parseOk,a,b
                  local modelExt=ext(rel)
                  if modelExt=="obj" then parseOk,a,b=pcall(parseOBJ,modelBytes,label)
                  elseif modelExt=="dae" then parseOk,a,b=pcall(parseDAE,modelBytes,label)
                  else parseOk,a,b=pcall(parseFBX,modelBytes,label) end
                  if parseOk then mesh,err=a,b else mesh,err=nil,tostring(a) end
                  if mesh then
                    local textureOptions,defaultTextureIndex,materialTextureIndices={},1,{}
                    local texOk,ta,tb,tc=pcall(collectTextureOptions,rel,modelBytes,mesh,files,mount)
                    if texOk and type(ta)=="table" then
                      textureOptions=ta; defaultTextureIndex=tonumber(tb) or 1
                      if type(tc)=="table" then materialTextureIndices=tc end
                    end
                    local firstTexture=textureOptions[defaultTextureIndex] or textureOptions[1]
                    local bone,x,y,z,scale,rx,ry,rz=inferDefaults(label.." "..zipName)
                    local id="ACC_"..safeId(stripExt(zipName).."_"..stripExt(rel)).."_"..tostring(rollingHash(zipName.."|"..rel))
                    defs[#defs+1]={
                      id=id,label=safeToken(stripExt(rel),"Accessory"),zipName=zipName,modelPath=rel,
                      format=mesh.format,corners=mesh.corners,triangleCount=mesh.triangleCount,
                      normalizedBounds=mesh.normalizedBounds,uvVariants=mesh.uvVariants,materialCount=mesh.materialCount or 1,
                      materialNames=mesh.materialNames,materialTextureNames=mesh.materialTextureNames,
                      materialTextureIndices=materialTextureIndices,
                      defaultAutoMaterialTextures=mesh.defaultAutoMaterialTextures==true,
                      textureOptions=textureOptions,defaultTextureIndex=defaultTextureIndex,
                      -- Compatibility aliases for old code and already-created runtime state.
                      textureBytes=firstTexture and firstTexture.bytes or nil,
                      textureExt=firstTexture and firstTexture.ext or nil,
                      defaultBone=bone,defaultX=x,defaultY=y,defaultZ=z,defaultScale=scale,
                      defaultRX=rx,defaultRY=ry,defaultRZ=rz,
                    }
                  else
                    failed=failed+1; errors[#errors+1]=zipName.." / "..rel..": "..tostring(err)
                  end
                end
              end
            end
            pcall(fs.unmount,fd)
          end
        end
      end
    end
  end
  -- v3.0.60: character replacement testing can use loose OBJ/FBX/DAE files
  -- directly in the import folder. This avoids having to re-ZIP every small
  -- Blender edit. MTL files and textures beside the model are discovered by
  -- the same texture collector used for ZIP packages.
  local looseRoot=root.."/imports"
  local looseFiles=recursiveList(looseRoot,{})
  local looseModels={}
  for _,full in ipairs(looseFiles) do
    local e=ext(full)
    if e=="obj" or e=="fbx" or e=="dae" then looseModels[#looseModels+1]=full end
  end
  table.sort(looseModels)
  for _,full in ipairs(looseModels) do
    local rel=normalizeRel(full:sub(#looseRoot+2))
    local okModel,modelBytes=pcall(fs.read,full)
    if not okModel or type(modelBytes)~="string" or #modelBytes>MAX_MODEL_BYTES then
      failed=failed+1; errors[#errors+1]="loose / "..rel..": model unreadable/too large"
    else
      local label=stripExt(rel)
      local mesh,err
      local parseOk,a,b
      local modelExt=ext(rel)
      if modelExt=="obj" then parseOk,a,b=pcall(parseOBJ,modelBytes,label)
      elseif modelExt=="dae" then parseOk,a,b=pcall(parseDAE,modelBytes,label)
      else parseOk,a,b=pcall(parseFBX,modelBytes,label) end
      if parseOk then mesh,err=a,b else mesh,err=nil,tostring(a) end
      if mesh then
        local textureOptions,defaultTextureIndex,materialTextureIndices={},1,{}
        local texOk,ta,tb,tc=pcall(collectTextureOptions,rel,modelBytes,mesh,looseFiles,looseRoot)
        if texOk and type(ta)=="table" then
          textureOptions=ta; defaultTextureIndex=tonumber(tb) or 1
          if type(tc)=="table" then materialTextureIndices=tc end
        end
        local firstTexture=textureOptions[defaultTextureIndex] or textureOptions[1]
        local bone,x,y,z,scale,rx,ry,rz=inferDefaults(label)
        local id="ACC_"..safeId("LOOSE_"..stripExt(rel)).."_"..tostring(rollingHash("LOOSE|"..rel))
        defs[#defs+1]={
          id=id,label=safeToken(stripExt(rel),"Accessory"),zipName="(loose)",modelPath=rel,
          format=mesh.format,corners=mesh.corners,triangleCount=mesh.triangleCount,normalizedBounds=mesh.normalizedBounds,
          uvVariants=mesh.uvVariants,materialCount=mesh.materialCount or 1,materialNames=mesh.materialNames,
          materialTextureNames=mesh.materialTextureNames,materialTextureIndices=materialTextureIndices,
          defaultAutoMaterialTextures=mesh.defaultAutoMaterialTextures==true,textureOptions=textureOptions,
          defaultTextureIndex=defaultTextureIndex,textureBytes=firstTexture and firstTexture.bytes or nil,
          textureExt=firstTexture and firstTexture.ext or nil,defaultBone=bone,defaultX=x,defaultY=y,defaultZ=z,
          defaultScale=scale,defaultRX=rx,defaultRY=ry,defaultRZ=rz,
        }
      else
        failed=failed+1; errors[#errors+1]="loose / "..rel..": "..tostring(err)
      end
    end
  end

  if log and log.info then pcall(log.info,log,"accessory scan: %d loaded, %d failed",#defs,failed) end
  return defs,failed,errors,M.nativeImportFolder(root)
end

local function makeWhiteImage()
  if not (love and love.image and love.image.newImageData and love.graphics and love.graphics.newImage) then return nil end
  local ok,data=pcall(love.image.newImageData,2,2)
  if not ok or not data then return nil end
  for y=0,1 do for x=0,1 do pcall(data.setPixel,data,x,y,1,1,1,1) end end
  local okI,img=pcall(love.graphics.newImage,data)
  if okI then return img end
  return nil
end

local function ensureRuntimeImage(def,index,state)
  local options=def.textureOptions or {}
  local count=#options
  index=math.floor(tonumber(index) or tonumber(def.defaultTextureIndex) or 1)
  if count>0 then
    if index<1 then index=1 elseif index>count then index=count end
  else
    index=1
  end
  def.runtimeImages=def.runtimeImages or {}
  local image=def.runtimeImages[index]
  if not image then
    local option=options[index]
    local bytes=option and option.bytes or def.textureBytes
    local textureExt=option and option.ext or def.textureExt
    if bytes and love.filesystem and love.filesystem.newFileData then
      local name="accessory."..tostring(textureExt or "png")
      local okFD,fd=pcall(love.filesystem.newFileData,bytes,name)
      if okFD and fd then
        local okI,img=pcall(love.graphics.newImage,fd)
        if okI then image=img end
      end
    end
    image=image or makeWhiteImage()
    if not image then return nil end
    def.runtimeImages[index]=image
  end
  if image.setFilter then
    if state and state.nearestFilter then pcall(image.setFilter,image,"nearest","nearest")
    else pcall(image.setFilter,image,"linear","linear") end
  end
  if image.setWrap then
    local wrap=(state and state.repeatTexture) and "repeat" or "clamp"
    pcall(image.setWrap,image,wrap,wrap)
  end
  return image
end

function M.ensureRuntime(def,Voxel3D,state)
  if not def or not Voxel3D or type(Voxel3D.FORMAT)~="table" then return false,nil end
  if not (love and love.graphics and love.graphics.newMesh) then return false,nil end

  -- Build one dynamic mesh per material slot. Older accessories with no material
  -- data simply produce one part. Splitting here lets FBX/OBJ models retain their
  -- actual material-to-texture assignments instead of smearing one atlas over
  -- every polygon.
  if not def.runtimeParts or def.runtimeFormat~=Voxel3D.FORMAT then
    if type(def.runtimeParts)=="table" then
      for _,part in ipairs(def.runtimeParts) do
        if part.mesh and part.mesh.release then pcall(part.mesh.release,part.mesh) end
      end
    elseif def.runtimeMesh and def.runtimeMesh.release then
      pcall(def.runtimeMesh.release,def.runtimeMesh)
    end
    local grouped={}
    for i,v in ipairs(def.corners or {}) do
      local slot=math.floor(tonumber(v[6]) or 0)+1
      if slot<1 then slot=1 end
      grouped[slot]=grouped[slot] or {}
      grouped[slot][#grouped[slot]+1]=i
    end
    local maxSlot=math.max(1,tonumber(def.materialCount) or 1)
    for slot in pairs(grouped) do if slot>maxSlot then maxSlot=slot end end
    local parts={}
    for slot=1,maxSlot do
      local sourceIndices=grouped[slot]
      if sourceIndices and #sourceIndices>=3 then
        local rows={}
        for j,sourceIndex in ipairs(sourceIndices) do
          local v=def.corners[sourceIndex]
          rows[j]={v[1],v[2],v[3],v[4],v[5],1.0}
        end
        local okM,mesh=pcall(love.graphics.newMesh,Voxel3D.FORMAT,rows,"triangles","dynamic")
        if okM and mesh then
          parts[#parts+1]={materialIndex=slot,sourceIndices=sourceIndices,rows=rows,mesh=mesh}
        end
      end
    end
    if #parts==0 then return false,nil end
    def.runtimeParts=parts
    def.runtimeMesh=parts[1].mesh -- compatibility/diagnostics
    def.runtimeRows=parts[1].rows
    def.runtimeFormat=Voxel3D.FORMAT
  end

  local selectedIndex=math.floor(tonumber(state and state.textureIndex) or tonumber(def.defaultTextureIndex) or 1)
  local image=ensureRuntimeImage(def,selectedIndex,state)
  if not image then return false,nil end
  def.runtimeImage=image
  return true,image
end

local BONE_CANDIDATES={
  HEAD={"head","jkao","bip01head","headjoint","mixamorighead"},
  NECK={"neck","jkubi","bip01neck","mixamorigneck"},
  CHEST={"upperchest","chest","spine3","spine2","spine03","spine02","jsebo","mixamorigspine2","mixamorigspine1"},
  HIPS={"hips","pelvis","jkosi","bip01pelvis","mixamorighips"},
  LEFT_HAND={"lefthand","lhand","handl","jtel","bip01lhand","mixamoriglefthand"},
  RIGHT_HAND={"righthand","rhand","handr","jter","bip01rhand","mixamorigrighthand"},
  LEFT_FOOT={"leftfoot","lfoot","footl","jasicl","bip01lfoot","mixamorigleftfoot"},
  RIGHT_FOOT={"rightfoot","rfoot","footr","jasicr","bip01rfoot","mixamorigrightfoot"},
}

local function normBoneName(name)
  return tostring(name or ""):lower():gsub("mixamorig[:_]?","mixamorig"):gsub("[^a-z0-9]","")
end

function M.resolveBone(renderer,group)
  if not renderer or not renderer.data then return 1 end
  group=tostring(group or "CHEST"):upper()
  renderer._red3dAccessoryBoneCache=renderer._red3dAccessoryBoneCache or {}
  if renderer._red3dAccessoryBoneCache[group] then return renderer._red3dAccessoryBoneCache[group] end
  local names=renderer.data.boneName or {}
  local normalized={}
  for i,name in ipairs(names) do normalized[i]=normBoneName(name) end
  for _,want in ipairs(BONE_CANDIDATES[group] or {}) do
    local n=normBoneName(want)
    for i,name in ipairs(normalized) do if name==n then renderer._red3dAccessoryBoneCache[group]=i; return i end end
  end
  local needles={HEAD="head",NECK="neck",CHEST="spine",HIPS="hip",LEFT_HAND="hand",RIGHT_HAND="hand",LEFT_FOOT="foot",RIGHT_FOOT="foot"}
  local needle=needles[group]
  if needle then
    local wantsLeft=group:find("LEFT",1,true)~=nil
    local wantsRight=group:find("RIGHT",1,true)~=nil
    for i,name in ipairs(normalized) do
      if name:find(needle,1,true) then
        local left=name:find("left",1,true) or name:find("lhand",1,true) or name:find("lfoot",1,true)
        local right=name:find("right",1,true) or name:find("rhand",1,true) or name:find("rfoot",1,true)
        if (not wantsLeft and not wantsRight) or (wantsLeft and left) or (wantsRight and right) then
          renderer._red3dAccessoryBoneCache[group]=i; return i
        end
      end
    end
  end
  renderer._red3dAccessoryBoneCache[group]=1
  return 1
end

local function rotateXYZ(x,y,z,rx,ry,rz)
  local cx,sx=math.cos(rx),math.sin(rx)
  local cy,sy=math.cos(ry),math.sin(ry)
  local cz,sz=math.cos(rz),math.sin(rz)
  local y1,z1=y*cx-z*sx,y*sx+z*cx; y,z=y1,z1
  local x1,z2=x*cy+z*sy,-x*sy+z*cy; x,z=x1,z2
  local x2,y2=x*cz-y*sz,x*sz+y*cz
  return x2,y2,z
end

local function transformPoint(m,x,y,z)
  return m[1]*x+m[2]*y+m[3]*z+m[4],
         m[5]*x+m[6]*y+m[7]*z+m[8],
         m[9]*x+m[10]*y+m[11]*z+m[12]
end

function M.draw(def,renderer,state,Voxel3D,bodyModel,ShadowMap)
  if not (def and renderer and state and state.enabled and bodyModel) then return false end
  local ready,selectedImage=M.ensureRuntime(def,Voxel3D,state)
  if not ready or not selectedImage then return false end
  local bone=M.resolveBone(renderer,state.bone or def.defaultBone)
  -- Always use the CURRENT animated bone matrix. Placement/rotation values below
  -- are local to this bone, so once the user positions an accessory it remains
  -- rigidly glued to that exact spot throughout idle/walk/run/jump animations.
  local world=renderer.world and renderer.world[bone]
  if not world then return false end
  local bodyH=math.max(1e-6,(tonumber(renderer.maxY) or 1)-(tonumber(renderer.minY) or 0))
  local scaleValue=clamp(state.scale or def.defaultScale or 0.16,0.01,0.80)*bodyH
  local ox=clamp(state.x or 0,-0.75,0.75)*bodyH
  local oy=clamp(state.y or 0,-0.75,0.75)*bodyH
  local oz=clamp(state.z or 0,-0.75,0.75)*bodyH
  local rx=math.rad(clamp(state.rx or 0,-180,180))
  local ry=math.rad(clamp(state.ry or 0,-180,180))
  local rz=math.rad(clamp(state.rz or 0,-180,180))

  local uvVariants=type(def.uvVariants)=="table" and def.uvVariants or nil
  local uvIndex=math.floor(tonumber(state.uvVariant) or 1)
  if uvVariants and #uvVariants>0 then
    if uvIndex<1 then uvIndex=1 elseif uvIndex>#uvVariants then uvIndex=#uvVariants end
  else
    uvIndex=1
  end
  local uvData=uvVariants and uvVariants[uvIndex] and uvVariants[uvIndex].uvs or nil

  local any=false
  for _,part in ipairs(def.runtimeParts or {}) do
    local rows=part.rows
    for j,sourceIndex in ipairs(part.sourceIndices) do
      local src=def.corners[sourceIndex]
      local x,y,z=rotateXYZ(src[1]*scaleValue,src[2]*scaleValue,src[3]*scaleValue,rx,ry,rz)
      x,y,z=x+ox,y+oy,z+oz
      x,y,z=transformPoint(world,x,y,z)
      if renderer.postSkinZUp then x,y,z=x,z,-y end
      if type(renderer.applySourceBasis)=="function" then
        x,y,z=renderer:applySourceBasis(x,y,z)
      end
      local row=rows[j]
      row[1],row[2],row[3]=x,y,z
      local uv=uvData and uvData[sourceIndex] or nil
      local u,vv=uv and (tonumber(uv[1]) or 0) or (tonumber(src[4]) or 0),
                 uv and (tonumber(uv[2]) or 0) or (tonumber(src[5]) or 0)
      if state.swapUV then u,vv=vv,u end
      if state.flipU then u=1-u end
      if state.flipV then vv=1-vv end
      row[4],row[5]=u,vv
    end
    if pcall(part.mesh.setVertices,part.mesh,rows) then
      local image=selectedImage
      if state.autoMaterialTextures and type(def.materialTextureIndices)=="table" then
        local materialTextureIndex=def.materialTextureIndices[part.materialIndex]
        if materialTextureIndex then
          image=ensureRuntimeImage(def,materialTextureIndex,state) or image
        end
      end
      if ShadowMap then
        local drew=pcall(ShadowMap.draw,part.mesh,image,bodyModel)
        if drew then any=true end
      else
        if Voxel3D.glass then pcall(Voxel3D.glass,false) end
        local drew=pcall(Voxel3D.draw,part.mesh,image,bodyModel,nil,bodyModel)
        if drew then any=true end
      end
    end
  end
  return any
end

M.parseOBJ=parseOBJ
M.parseFBX=parseFBX
M.parseDAE=parseDAE
M.inferDefaults=inferDefaults
M.safeId=safeId

return M
