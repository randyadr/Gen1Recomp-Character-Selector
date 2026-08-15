from __future__ import annotations
import base64, json, math, os, re, shutil, zipfile, zlib
from pathlib import Path

ROOT=Path(os.environ.get('STORE_ROOT','.'))
OUT=Path(os.environ.get('STORE_OUT','store_build'))
RAW_BASE=os.environ.get('STORE_RAW_BASE','https://raw.githubusercontent.com/randyadr/Gen1Recomp-Character-Selector/character-store/store')

CHARS=[
 dict(id='RED',name='Red',category='Pokemon Trainers',section='POKEMON',bundled=True),
 dict(id='ASH',name='Ash Ketchum',category='Pokemon Trainers',section='POKEMON',addon='red3d_char_ash',data='data/ash_model.lua',atlases=['assets/ash_atlas.png'],fields=dict(height=19.5,profile='ASH',armRestDeg=0,modelYawOffset=0)),
 dict(id='SABRINA',name='Sabrina',category='Pokemon Trainers',section='POKEMON',addon='red3d_char_sabrina',data='data/sabrina_outfit1_model.lua',atlases=['assets/sabrina_outfit1_neutral.png','assets/sabrina_outfit1_half.png','assets/sabrina_outfit1_blink.png','assets/sabrina_outfit1_smile.png','assets/sabrina_outfit2_original.png'],fields=dict(height=25.0,profile='WOW_FBX',armRestDeg=0,modelYawOffset=0,dynamicAtlas='hilda_face'),variants=[dict(label='OUTFIT 1',data='data/sabrina_outfit1_model.lua',atlas='assets/sabrina_outfit1_neutral.png',atlasFrames=['assets/sabrina_outfit1_neutral.png','assets/sabrina_outfit1_half.png','assets/sabrina_outfit1_blink.png','assets/sabrina_outfit1_smile.png'],dynamicAtlas='hilda_face',profile='WOW_FBX',height=25.0,modelYawOffset=0,projectYawOffset=0,sourceYaw180=False,postSkinZUp=False),dict(label='OUTFIT 2',data='data/sabrina_outfit2_model.lua',atlas='assets/sabrina_outfit2_original.png',profile='WOW_FBX',height=25.0,modelYawOffset=0,projectYawOffset=0,sourceYaw180=False,postSkinZUp=False)]),
 dict(id='HILDA',name='Hilda',category='Pokemon Trainers',section='POKEMON',addon='red3d_char_hilda',data='data/hilda_model.lua',atlases=['assets/hilda_atlas_neutral.png','assets/hilda_atlas_half.png','assets/hilda_atlas_blink.png','assets/hilda_atlas_smile.png'],fields=dict(height=20.0,profile='WOW_FBX',armRestDeg=0,modelYawOffset=0,dynamicAtlas='hilda_face')),
 dict(id='CYNTHIA',name='Cynthia',category='Pokemon Trainers',section='POKEMON',addon='red3d_char_cynthia',data='data/cynthia_model.lua',atlases=['assets/cynthia_atlas.png'],fields=dict(height=21.5,profile='WOW_FBX',armRestDeg=0,modelYawOffset=0)),
 dict(id='AANG',name='Aang',category='Anime',section='ANIME',addon='red3d_char_aang',data='data/aang_model.lua',atlases=['assets/aang_atlas.png'],fields=dict(height=18.5,profile='AANG_MIXAMO',armRestDeg=0,modelYawOffset=0)),
 dict(id='BELLESTARMON',name='BelleStarmon',category='Anime',section='ANIME',addon='red3d_char_bellestarmon',data='data/bellestarmon_model.lua',atlases=['assets/bellestarmon_atlas.png'],extra=['data/bellestarmon_selector_idle.lua'],fields=dict(height=27,profile='AANG_MIXAMO',armRestDeg=0,modelYawOffset=0,projectYawOffset=0,sourceYaw180=True,behaviorId='BELLESTARMON')),
 dict(id='NARUTO',name='Naruto',category='Anime',section='ANIME',addon='red3d_char_naruto',data='data/naruto_model.lua',atlases=['assets/naruto_atlas_open.png','assets/naruto_atlas_close00.png'],fields=dict(height=20.5,profile='NARUTO_MIXAMO',armRestDeg=0,modelYawOffset=0,projectYawOffset=0,sourceYaw180=True,dynamicAtlas='blink')),
 dict(id='ZORO',name='Roronoa Zoro',category='Anime',section='ANIME',addon='red3d_char_zoro',data='data/zoro_model.lua',atlases=['assets/zoro_atlas.png'],fields=dict(height=26,profile='AANG_MIXAMO',armRestDeg=0,modelYawOffset=0,postSkinZUp=True)),
 dict(id='NAMI',name='Nami',category='Anime',section='ANIME',addon='red3d_char_nami',data='data/nami_v1_model.lua',atlases=['assets/nami_v1_atlas.png','assets/nami_v2_atlas.png','assets/nami_bikini_atlas.png'],fields=dict(height=22.0,profile='WOW_FBX',armRestDeg=0,modelYawOffset=0,floatOffset=-0.46,behaviorId='NAMI'),variants=[dict(label='NAMI V1',data='data/nami_v1_model.lua',atlas='assets/nami_v1_atlas.png',profile='WOW_FBX',height=22.0,modelYawOffset=0,projectYawOffset=0,sourceYaw180=False,postSkinZUp=False,behaviorId='NAMI',floatOffset=-0.46),dict(label='NAMI V2',data='data/nami_v2_model.lua',atlas='assets/nami_v2_atlas.png',profile='WOW_FBX',height=22.0,modelYawOffset=0,projectYawOffset=0,sourceYaw180=False,postSkinZUp=False,behaviorId='NAMI',floatOffset=-0.46),dict(label='NAMI BIKINI',data='data/nami_bikini_model.lua',atlas='assets/nami_bikini_atlas.png',profile='WOW_FBX',height=22.0,modelYawOffset=0,projectYawOffset=0,sourceYaw180=False,postSkinZUp=False,behaviorId='NAMI',floatOffset=-0.46)]),
 dict(id='YAMI',name='Yami',category='Anime',section='ANIME',addon='red3d_char_yami',data='data/yami_model.lua',atlases=['assets/yami_atlas.png'],fields=dict(height=24.5,profile='YAMI_FBX',armRestDeg=0,modelYawOffset=0,postSkinZUp=True)),
 dict(id='YUGI',name='Yugi Muto',category='Anime',section='ANIME',addon='red3d_char_yugi',data='data/yugi_model.lua',atlases=['assets/yugi_atlas.png'],fields=dict(height=25,profile='YUGI',armRestDeg=62)),
 dict(id='CLOUD',name='Cloud',category='Random',section='MISC',addon='red3d_char_cloud',data='data/cloud_model.lua',atlases=['assets/cloud_atlas.png'],fields=dict(height=20,profile='CLOUD',armRestDeg=0)),
 dict(id='SHREK',name='Shrek',category='Random',section='MISC',addon='red3d_char_shrek',data='data/shrek_model.lua',atlases=['assets/shrek_atlas.png'],fields=dict(height=29,profile='AANG_MIXAMO',armRestDeg=0,modelYawOffset=0)),
 dict(id='DEXTERS_MOM',name="Dexter's Mom",category='Random',section='MISC',addon='red3d_char_dexters_mom',data='data/dexters_mom_model.lua',atlases=['assets/dexters_mom_atlas.png'],fields=dict(height=23.0,profile='WOW_FBX',armRestDeg=0,modelYawOffset=0,projectYawOffset=0,sourceYaw180=False,postSkinZUp=False,behaviorId='DEXTERS_MOM')),
 dict(id='MARIO',name='Mario (SM64 / SA64)',category='Random',section='MISC',addon='red3d_char_mario',data='data/mario_sm64_model.lua',atlases=['assets/mario_sm64_atlas.png','assets/mario_sm64_atlas_half.png','assets/mario_sm64_atlas_closed.png'],fields=dict(height=19.5,profile='MARIO_SM64',armRestDeg=0,modelYawOffset=0,behaviorId='MARIO',dynamicAtlas='marioBlink')),
 dict(id='SONIC_SA1',name='Sonic (Adventure 1)',category='Random',section='MISC',addon='red3d_char_sonic_sa1',data='data/sonic_sa1_model.lua',atlases=['assets/sonic_sa1_atlas.png'],fields=dict(height=18.5,profile='SA1_SONIC',armRestDeg=0,modelYawOffset=0,behaviorId='SONIC_SA1')),
 dict(id='SONIC',name='Sonic the Hedgehog',category='Random',section='MISC',addon='red3d_char_sonic',data='data/sonic_model.lua',atlases=['assets/sonic_atlas.png','assets/sonic_classic_atlas.png'],fields=dict(height=18.5,profile='WOW_FBX',armRestDeg=0,modelYawOffset=0),variants=[dict(label='MODERN SONIC',data='data/sonic_model.lua',atlas='assets/sonic_atlas.png',profile='WOW_FBX',height=18.5,modelYawOffset=0,projectYawOffset=0,sourceYaw180=False,postSkinZUp=False),dict(label='CLASSIC FIGHTERS',data='data/sonic_classic_model.lua',atlas='assets/sonic_classic_atlas.png',profile='WOW_FBX',height=18.5,modelYawOffset=0,projectYawOffset=0,sourceYaw180=False,postSkinZUp=False)]),
 dict(id='TITAN',name='OceanGate Titan',category='Random',section='MISC',addon='red3d_char_titan',data='data/titan_model.lua',atlases=['assets/titan_atlas.png'],fields=dict(height=10.5,profile='STATIC',armRestDeg=0,modelYawOffset=0,floatOffset=4.0)),
 dict(id='UGANDAN_KNUCKLES',name='Ugandan Knuckles',category='Random',section='MISC',addon='red3d_char_ugandan_knuckles',data='data/ugandan_knuckles_model.lua',atlases=['assets/ugandan_knuckles_atlas.png'],fields=dict(height=18.0,profile='AANG_MIXAMO',armRestDeg=0,modelYawOffset=0)),
]

def lua_literal(v):
    if v is None:return 'nil'
    if v is True:return 'true'
    if v is False:return 'false'
    if isinstance(v,(int,float)):return repr(v).lower()
    if isinstance(v,str):return json.dumps(v)
    if isinstance(v,list):return '{'+','.join(lua_literal(x) for x in v)+'}'
    if isinstance(v,dict):return '{'+','.join(f'{k}={lua_literal(val)}' for k,val in v.items())+'}'
    raise TypeError(type(v))

def addon_main(c):
    d=dict(id=c['id'],behaviorId=c.get('fields',{}).get('behaviorId',c['id']),label=c['name'],section=c['section']);d.update(c.get('fields',{}));d['data']=c['data'];d['atlas']=c['atlases'][0]
    if len(c['atlases'])>1 and not c.get('variants'):d['atlasFrames']=c['atlases']
    if c.get('variants'):d['variants']=c['variants']
    extra='local selectorIdle=loadData("data/bellestarmon_selector_idle.lua")\n' if c['id']=='BELLESTARMON' else 'local selectorIdle=nil\n'
    return f'''local mod=...\nlocal function loadData(path)\n local src,err=mod:read(path); if type(src)~="string" then error("missing "..path..": "..tostring(err)) end\n local fn,e=load(src,"@"..path); if not fn then error(e) end\n local ok,data=pcall(fn); if not ok then error(data) end; return data\nend\nlocal META={lua_literal(d)}\nlocal ATLAS_PATHS={lua_literal(c['atlases'])}\nlocal imageMap={{}}\nfor _,path in ipairs(ATLAS_PATHS) do imageMap[path]=mod.assets:image(path) end\nlocal function hydrate(def)\n local out={{}}; for k,v in pairs(def or {{}}) do out[k]=v end\n if out.data then out._runtimeData=loadData(out.data) end\n out.atlasImages=imageMap; return out\nend\nlocal def=hydrate(META)\nif type(META.variants)=="table" then def.variants={{}}; for i,v in ipairs(META.variants) do def.variants[i]=hydrate(v) end end\n{extra}mod.exports.character={{id={lua_literal(c['id'])},def=def,selectorIdle=selectorIdle}}\n'''

def package_char(c):
    if c.get('bundled'):return None
    cid=c['id'].lower();d=OUT/'packages_src'/cid;shutil.rmtree(d,ignore_errors=True);d.mkdir(parents=True)
    manifest={'id':c['addon'],'name':f"3D Character: {c['name']}",'version':'1.0.0','api':2,'entry':'main.lua','profile':'content','category':'CONTENT','games':['gen1','gen2'],'game_version':'0.0.0-dev || >=0.1.36 <2.0.0','priority':110,'dependencies':['red_3d_player'],'permissions':[],'description':f"Remote character pack for {c['name']} used by the Gen1Recomp 3D Character Selector.",'github':'randyadr/Gen1Recomp-Character-Selector'}
    (d/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');(d/'main.lua').write_text(addon_main(c))
    files={c['data'],*c['atlases'],*c.get('extra',[])}
    for v in c.get('variants',[]):
        if v.get('data'):files.add(v['data'])
        if v.get('atlas'):files.add(v['atlas'])
        for p in v.get('atlasFrames',[]) or []:files.add(p)
    for rel in sorted(files):
        src=ROOT/rel;dst=d/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
    zp=OUT/'packages'/f'{cid}.zip';zp.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(zp,'w',zipfile.ZIP_DEFLATED,compresslevel=1) as z:
        for p in d.rglob('*'):
            if p.is_file():z.write(p,p.relative_to(d).as_posix())
    with zipfile.ZipFile(zp) as z:assert z.testzip() is None
    return zp

def parse_array(text,key,dtype=float):
    m=re.search(r'\n\s*'+re.escape(key)+r'\s*=\s*\{(.*?)\n\s*\},',text,re.S)
    if not m:return []
    return [dtype(float(x)) for x in re.findall(r'[-+]?(?:\d+\.\d*|\d*\.\d+|\d+)(?:[eE][-+]?\d+)?',m.group(1))]
def matmul(a,b):
    o=[0.0]*16
    for r in range(4):
        for c in range(4):o[r*4+c]=sum(a[r*4+k]*b[k*4+c] for k in range(4))
    return o
def xform(m,x,y,z):return(m[0]*x+m[1]*y+m[2]*z+m[3],m[4]*x+m[5]*y+m[6]*z+m[7],m[8]*x+m[9]*y+m[10]*z+m[11])
def make_thumb(c):
    from PIL import Image,ImageDraw
    model=ROOT/('data/model.lua' if c.get('bundled') else c['data']);atlas=ROOT/('assets/red_atlas.png' if c.get('bundled') else c['atlases'][0]);text=model.read_text(errors='ignore')
    bp=parse_array(text,'boneParent',int);bl=parse_array(text,'boneLocal');pf=parse_array(text,'posFirst',int);pc=parse_array(text,'posCount',int);ib=parse_array(text,'infBone',int);ix=parse_array(text,'infX');iy=parse_array(text,'infY');iz=parse_array(text,'infZ');iw=parse_array(text,'infW');cp=parse_array(text,'cornerPos',int);cu=parse_array(text,'cornerU');cv=parse_array(text,'cornerV')
    n=min(len(bp),len(bl)//16);world=[None]*(n+1)
    for b in range(1,n+1):
        lm=bl[(b-1)*16:b*16];par=bp[b-1] if b-1<len(bp) else 0;world[b]=matmul(world[par],lm) if par and world[par] else lm
    pts=[]
    for pi in range(len(pf)):
        x=y=z=tw=0.0
        for j in range(pf[pi]-1,pf[pi]-1+pc[pi]):
            if 0<=j<len(ib) and 0<ib[j]<=n and world[ib[j]]:
                q=xform(world[ib[j]],ix[j],iy[j],iz[j]);w=iw[j];x+=q[0]*w;y+=q[1]*w;z+=q[2]*w;tw+=w
        pts.append((x/tw,y/tw,z/tw) if tw>1e-8 else (x,y,z))
    xs=[p[0] for p in pts];ys=[p[1] for p in pts];zs=[p[2] for p in pts];use_z=(max(zs)-min(zs))>(max(ys)-min(ys))*1.25;ca,sa=math.cos(math.radians(-16)),math.sin(math.radians(-16));proj=[];depth=[]
    for x,y,z in pts:
        if use_z:y,z=z,y
        proj.append((x*ca-z*sa,y));depth.append(x*sa+z*ca)
    px=[p[0] for p in proj];py=[p[1] for p in proj];minx,maxx,miny,maxy=min(px),max(px),min(py),max(py);scale=min(104/max(maxx-minx,1e-6),112/max(maxy-miny,1e-6));cx=(minx+maxx)/2
    def screen(i):x,y=proj[i];return(64+(x-cx)*scale,122-(y-miny)*scale)
    tex=Image.open(atlas).convert('RGBA');tw,th=tex.size;canvas=Image.new('RGBA',(128,128),(15,22,34,255));draw=ImageDraw.Draw(canvas,'RGBA');tc=len(cp)//3;step=max(1,tc//7000);samples=[]
    for t in range(0,tc,step):
        inds=[cp[t*3+k]-1 for k in range(3)]
        if any(i<0 or i>=len(pts) for i in inds):continue
        u=sum(cu[t*3+k] if t*3+k<len(cu) else .5 for k in range(3))/3;v=sum(cv[t*3+k] if t*3+k<len(cv) else .5 for k in range(3))/3;col=tex.getpixel((max(0,min(tw-1,int(u*(tw-1)))),max(0,min(th-1,int(v*(th-1))))))
        if col[3]<24:continue
        sx=sum(screen(i)[0] for i in inds)/3;sy=sum(screen(i)[1] for i in inds)/3;samples.append((sum(depth[i] for i in inds)/3,sx,sy,col))
    samples.sort(key=lambda q:q[0])
    for _,sx,sy,col in samples:draw.ellipse((sx-1.1,sy-1.1,sx+1.1,sy+1.1),fill=col)
    draw.rounded_rectangle((1,1,126,126),radius=12,outline=(74,103,135,255),width=2);raw=canvas.tobytes();enc=base64.b64encode(zlib.compress(raw,9)).decode('ascii');p=OUT/'thumbnails'/f"{c['id'].lower()}.r3dthumb";p.parent.mkdir(parents=True,exist_ok=True);p.write_text(f'R3DTHUMB1\n128\n128\n{enc}\n');pp=OUT/'preview'/f"{c['id'].lower()}.png";pp.parent.mkdir(parents=True,exist_ok=True);canvas.save(pp);return p

def main():
    shutil.rmtree(OUT,ignore_errors=True);OUT.mkdir(parents=True);entries=[]
    for c in CHARS:
        make_thumb(c);zp=package_char(c);size=zp.stat().st_size if zp else 0;cid=c['id'].lower();entries.append({'id':c['id'],'name':c['name'],'category':c['category'],'version':'1.0.0','bundled':bool(c.get('bundled')),'addon_mod_id':c.get('addon'),'thumbnail_url':f'{RAW_BASE}/thumbnails/{cid}.r3dthumb','package_url':None if not zp else f'{RAW_BASE}/packages/{cid}.zip','package_size':size,'free':True})
    (OUT/'index.json').write_text(json.dumps({'schema_version':2,'store_name':'Gen1Recomp Character Store','generated_at':'2026-08-15','categories':['Pokemon Trainers','Anime','Random'],'characters':entries},indent=2)+'\n')
if __name__=='__main__':main()
