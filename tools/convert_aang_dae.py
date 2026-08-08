#!/usr/bin/env python3
from __future__ import annotations
import argparse, math, pathlib, xml.etree.ElementTree as ET
from PIL import Image

NS={'c':'http://www.collada.org/2005/11/COLLADASchema'}
I=[1.,0,0,0, 0,1.,0,0, 0,0,1.,0, 0,0,0,1.]
# Z-up source -> runtime Y-up, and source -Y -> runtime +Z.
C=[1,0,0,0, 0,0,1,0, 0,-1,0,0, 0,0,0,1]
CINV=[1,0,0,0, 0,0,-1,0, 0,1,0,0, 0,0,0,1]

def mul(a,b):
    o=[0.]*16
    for r in range(4):
        for c in range(4): o[r*4+c]=sum(a[r*4+k]*b[k*4+c] for k in range(4))
    return o

def transform(m,p):
    x,y,z=p
    return (m[0]*x+m[1]*y+m[2]*z+m[3], m[4]*x+m[5]*y+m[6]*z+m[7], m[8]*x+m[9]*y+m[10]*z+m[11])

def inv_rigid(m):
    # Rigid matrices after scene conversion. (The armature's 9x parent scale is
    # baked into geometry/joint worlds before runtime locals are generated.)
    import numpy as np
    return np.linalg.inv(np.array(m,float).reshape(4,4)).reshape(-1).tolist()

def mrow(text): return [float(x) for x in (text or '').split()]
def runtime_matrix(m): return mul(mul(C,m),CINV)
def runtime_point(p): return transform(C,p)

def float_source(src):
    vals=[float(x) for x in (src.find('c:float_array',NS).text or '').split()]
    acc=src.find('c:technique_common/c:accessor',NS)
    stride=int(acc.get('stride','1')) if acc is not None else 1
    return vals,stride

def find_source(parent,ref):
    rid=ref.lstrip('#')
    el=parent.find(f"c:source[@id='{rid}']",NS)
    if el is None: raise KeyError(rid)
    return el

def lua_num(x):
    if isinstance(x,int): return str(x)
    if abs(x)<5e-10: x=0.
    return f'{x:.8g}'

def lua_array(name,vals,out,per=16):
    out.write(f'  {name} = {{\n')
    for i in range(0,len(vals),per): out.write('    '+', '.join(lua_num(v) for v in vals[i:i+per])+',\n')
    out.write('  },\n')

def lua_strings(name,vals,out,per=8):
    import json
    out.write(f'  {name} = {{\n')
    for i in range(0,len(vals),per): out.write('    '+', '.join(json.dumps(v) for v in vals[i:i+per])+',\n')
    out.write('  },\n')

def build_atlas(src,out):
    im=Image.open(src).convert('RGBA')
    # Preserve source pixels; add 2px duplicated edge padding to avoid atlas bleed.
    w,h=im.size
    aw,ah=w+4,h+4
    atlas=Image.new('RGBA',(aw,ah),(0,0,0,0)); atlas.paste(im,(2,2))
    # duplicate edges
    atlas.paste(im.crop((0,0,w,1)).resize((w,2)),(2,0))
    atlas.paste(im.crop((0,h-1,w,h)).resize((w,2)),(2,h+2))
    atlas.paste(im.crop((0,0,1,h)).resize((2,h)),(0,2))
    atlas.paste(im.crop((w-1,0,w,h)).resize((2,h)),(w+2,2))
    out.parent.mkdir(parents=True,exist_ok=True); atlas.save(out,optimize=True)
    return w,h,aw,ah

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('dae',type=pathlib.Path); ap.add_argument('--texture',type=pathlib.Path,required=True); ap.add_argument('--out-lua',type=pathlib.Path,required=True); ap.add_argument('--out-atlas',type=pathlib.Path,required=True); args=ap.parse_args()
    root=ET.parse(args.dae).getroot(); tw,th,AW,AH=build_atlas(args.texture,args.out_atlas)
    ctrl=root.find('.//c:library_controllers/c:controller',NS); skin=ctrl.find('c:skin',NS)
    geom=root.find('.//c:library_geometries/c:geometry',NS); mesh=geom.find('c:mesh',NS)
    # positions
    verts=mesh.find('c:vertices',NS); posref=next(i.get('source') for i in verts.findall('c:input',NS) if i.get('semantic')=='POSITION')
    pv,pst=float_source(find_source(mesh,posref)); source_positions=[tuple(pv[i:i+3]) for i in range(0,len(pv),pst)]
    # scene joint worlds, including armature object scale; COLLADA matrices in this Blender file are already row-major.
    names=[]; parents=[]; source_world=[]; sid_to_idx={}
    def walk(n,pw,parent_idx):
        mel=n.find('c:matrix',NS); lm=mrow(mel.text) if mel is not None else I
        w=mul(pw,lm); this=parent_idx
        if n.get('type')=='JOINT':
            name=n.get('sid') or n.get('name'); idx=len(names); names.append(name); parents.append(parent_idx+1 if parent_idx>=0 else 0); source_world.append(w); sid_to_idx[name]=idx; this=idx
        for ch in n.findall('c:node',NS): walk(ch,w,this)
    vs=root.find('.//c:library_visual_scenes/c:visual_scene',NS)
    for n in vs.findall('c:node',NS): walk(n,I,-1)
    worlds=[runtime_matrix(w) for w in source_world]
    locals=[]
    for i,w in enumerate(worlds):
        pi=parents[i]-1
        locals.append(mul(inv_rigid(worlds[pi]),w) if pi>=0 else w)
    invworld=[inv_rigid(w) for w in worlds]
    # weights
    srcs={s.get('id'):s for s in skin.findall('c:source',NS)}
    ji={i.get('semantic'):i.get('source').lstrip('#') for i in skin.find('c:joints',NS).findall('c:input',NS)}
    joint_names=(srcs[ji['JOINT']].find('c:Name_array',NS).text or '').split()
    vw=skin.find('c:vertex_weights',NS); vi={i.get('semantic'):(i.get('source').lstrip('#'),int(i.get('offset','0'))) for i in vw.findall('c:input',NS)}
    step=1+max(v[1] for v in vi.values()); joff=vi['JOINT'][1]; wsrc,woff=vi['WEIGHT']; wvals,_=float_source(srcs[wsrc]); counts=[int(x) for x in (vw.find('c:vcount',NS).text or '').split()]; packed=[int(x) for x in (vw.find('c:v',NS).text or '').split()]
    bsm=skin.find('c:bind_shape_matrix',NS); bs=mrow(bsm.text) if bsm is not None else I
    pos_first=[];pos_count=[];inf_bone=[];inf_x=[];inf_y=[];inf_z=[];inf_w=[]; runtime_positions=[]; cur=0
    for idx,cnt in enumerate(counts):
        srcp=transform(bs,source_positions[idx]); p=runtime_point(srcp); runtime_positions.append(p)
        arr=[]
        for _ in range(cnt):
            j=packed[cur+joff]; wi=packed[cur+woff];cur+=step; wt=wvals[wi]
            if wt>1e-7: arr.append((j,wt))
        arr.sort(key=lambda q:q[1],reverse=True);arr=arr[:4]; sw=sum(w for _,w in arr) or 1
        pos_first.append(len(inf_bone)+1);pos_count.append(len(arr))
        for j,wt in arr:
            bi=sid_to_idx[joint_names[j]]; lp=transform(invworld[bi],p)
            inf_bone.append(bi+1);inf_x.append(lp[0]);inf_y.append(lp[1]);inf_z.append(lp[2]);inf_w.append(wt/sw)
    # UV/triangles
    cache={}
    def tuples(ref):
        rid=ref.lstrip('#')
        if rid not in cache:
            vals,st=float_source(find_source(mesh,ref));cache[rid]=[tuple(vals[i:i+st]) for i in range(0,len(vals),st)]
        return cache[rid]
    corner_pos=[];corner_u=[];corner_v=[];centers=[]
    for tri in mesh.findall('c:triangles',NS):
        ins=[(i.get('semantic'),i.get('source'),int(i.get('offset','0')),i.get('set')) for i in tri.findall('c:input',NS)]; st=1+max(i[2] for i in ins); data=[int(x) for x in (tri.find('c:p',NS).text or '').split()]; voff=next(i[2] for i in ins if i[0]=='VERTEX'); ti=next((i for i in ins if i[0]=='TEXCOORD'),None); tex=tuples(ti[1]) if ti else None
        for k in range(0,len(data),st*3):
            pts=[]
            for c in range(3):
                off=k+c*st; pi=data[off+voff]; corner_pos.append(pi+1); pts.append(runtime_positions[pi]); u,v=(tex[data[off+ti[2]]][:2] if ti else (0,0))
                # Aang's source UVs are already strictly inside 0..1. Clamp instead
                # of repeat-wrapping (which can turn an exact edge into the opposite
                # side of the sheet), then flip V for LÖVE's top-down image rows.
                u=max(0.0,min(1.0,float(u))); v=max(0.0,min(1.0,float(v)))
                v=1.0-v
                corner_u.append((2.5+u*(tw-1))/AW); corner_v.append((2.5+v*(th-1))/AH)
            centers.append(tuple(sum(p[d] for p in pts)/3 for d in range(3)))
    orders={}; yaws={'down':0.,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}
    for key,yaw in yaws.items():
        c,s=math.cos(yaw),math.sin(yaw); ds=[(x*s+z*c,i+1) for i,(x,y,z) in enumerate(centers)]; ds.sort(key=lambda q:q[0]);orders[key]=[i for _,i in ds]
    mins=[min(p[d] for p in runtime_positions) for d in range(3)];maxs=[max(p[d] for p in runtime_positions) for d in range(3)]
    alias={'Waist':'Pelvis','Hips':'Pelvis','Spine1':'Spine1','Spine2':'Spine2','Spine3':'Spine3','Neck':'Neck','Head':'Head','LShoulder':'L_Clavicle','LArm':'L_UpperArm','LForeArm':'L_Forearm','LHand':'L_Hand','RShoulder':'R_Clavicle','RArm':'R_UpperArm','RForeArm':'R_Forearm','RHand':'R_Hand','LThigh':'L_Thigh','LLeg':'L_Calf','LFoot':'L_Foot','LToe':'L_Toe','RThigh':'R_Thigh','RLeg':'R_Calf','RFoot':'R_Foot','RToe':'R_Toe'}
    anim={k:sid_to_idx[v]+1 for k,v in alias.items() if v in sid_to_idx}
    # validation
    avg=mx=0
    for i,p in enumerate(runtime_positions):
        out=[0,0,0]; first=pos_first[i]-1
        for j in range(first,first+pos_count[i]):
            bi=inf_bone[j]-1; tp=transform(worlds[bi],(inf_x[j],inf_y[j],inf_z[j]));w=inf_w[j];out[0]+=tp[0]*w;out[1]+=tp[1]*w;out[2]+=tp[2]*w
        e=math.dist(p,out);avg+=e;mx=max(mx,e)
    avg/=len(runtime_positions)
    args.out_lua.parent.mkdir(parents=True,exist_ok=True)
    with args.out_lua.open('w') as out:
        out.write('-- GENERATED from aang.dae with exact weighted bind reconstruction\nreturn {\n');out.write(f'  boneCount = {len(names)},\n  positionCount = {len(runtime_positions)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(centers)},\n');lua_strings('boneName',names,out);lua_array('boneParent',parents,out);lua_array('boneLocal',[v for m in locals for v in m],out);lua_array('posFirst',pos_first,out);lua_array('posCount',pos_count,out);lua_array('infBone',inf_bone,out);lua_array('infX',inf_x,out);lua_array('infY',inf_y,out);lua_array('infZ',inf_z,out);lua_array('infW',inf_w,out);lua_array('cornerPos',corner_pos,out);lua_array('cornerU',corner_u,out);lua_array('cornerV',corner_v,out);out.write('  order = {\n');
        for k in ('down','left','up','right'):
            out.write(f'    {k} = {{\n');vals=orders[k]
            for n in range(0,len(vals),20): out.write('      '+', '.join(map(str,vals[n:n+20]))+',\n')
            out.write('    },\n')
        out.write('  },\n  animBone = {\n')
        for k,v in anim.items(): out.write(f'    {k} = {v},\n')
        out.write('  },\n');lua_array('bounds',mins+maxs,out,6);out.write('}\n')
    print('Aang bones',len(names),'positions',len(runtime_positions),'tris',len(centers),'rest avg',avg,'max',mx,'bounds',mins,maxs,'anim',anim)

if __name__=='__main__': main()
