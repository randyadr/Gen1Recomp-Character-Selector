#!/usr/bin/env python3
"""Convert the supplied Red COLLADA skin to the compact Lua runtime format.

This converter is intentionally self-contained: ElementTree + Pillow only.
It preserves all source skin weights/joints and bakes each inverse-bind position
into bone-local coordinates, so the LÖVE runtime only needs current bone worlds.
"""
from __future__ import annotations
import argparse, math, os, pathlib, xml.etree.ElementTree as ET
from dataclasses import dataclass
from typing import Dict, List, Tuple
from PIL import Image

NS = {"c": "http://www.collada.org/2005/11/COLLADASchema"}

# ---------- matrix helpers (row-major, column-vector convention) ----------
def ident():
    return [1.0,0,0,0, 0,1.0,0,0, 0,0,1.0,0, 0,0,0,1.0]

def mul(a,b):
    o=[0.0]*16
    for r in range(4):
        for c in range(4):
            o[r*4+c]=sum(a[r*4+k]*b[k*4+c] for k in range(4))
    return o

def trans(x,y,z):
    m=ident(); m[3]=x; m[7]=y; m[11]=z; return m

def scale(x,y,z):
    m=ident(); m[0]=x; m[5]=y; m[10]=z; return m

def rot_axis(x,y,z,deg):
    n=math.sqrt(x*x+y*y+z*z)
    if n < 1e-12: return ident()
    x,y,z=x/n,y/n,z/n
    a=math.radians(deg); c=math.cos(a); s=math.sin(a); C=1-c
    return [
        x*x*C+c,   x*y*C-z*s, x*z*C+y*s, 0,
        y*x*C+z*s, y*y*C+c,   y*z*C-x*s, 0,
        z*x*C-y*s, z*y*C+x*s, z*z*C+c,   0,
        0,0,0,1,
    ]

def transform_point(m,p):
    x,y,z=p
    return (m[0]*x+m[1]*y+m[2]*z+m[3],
            m[4]*x+m[5]*y+m[6]*z+m[7],
            m[8]*x+m[9]*y+m[10]*z+m[11])

def node_local(node):
    m=ident()
    for ch in list(node):
        tag=ch.tag.split('}')[-1]
        if tag not in ("translate","rotate","scale","matrix"): continue
        v=[float(x) for x in (ch.text or '').split()]
        if tag=="translate": t=trans(*v[:3])
        elif tag=="rotate": t=rot_axis(*v[:4])
        elif tag=="scale": t=scale(*v[:3])
        else:
            # COLLADA matrices are serialized column-major.
            t=[v[c*4+r] for r in range(4) for c in range(4)]
        m=mul(m,t)
    return m

# ---------- parse helpers ----------
def float_source(src):
    arr=src.find('c:float_array',NS)
    vals=[float(x) for x in (arr.text or '').split()]
    acc=src.find('c:technique_common/c:accessor',NS)
    stride=int(acc.get('stride','1')) if acc is not None else 1
    return vals,stride

def find_source(parent, ref):
    rid=ref[1:] if ref.startswith('#') else ref
    el=parent.find(f"c:source[@id='{rid}']",NS)
    if el is None: raise ValueError(f"missing source {rid}")
    return el

def lua_num(x):
    if isinstance(x,int): return str(x)
    if abs(x) < 5e-10: x=0.0
    s=f"{x:.7g}"
    return s

def lua_array(name, vals, out, per=16):
    out.write(f"  {name} = {{\n")
    for i in range(0,len(vals),per):
        out.write("    "+", ".join(lua_num(v) for v in vals[i:i+per])+",\n")
    out.write("  },\n")

def lua_strings(name, vals, out, per=8):
    import json
    out.write(f"  {name} = {{\n")
    for i in range(0,len(vals),per):
        out.write("    "+", ".join(json.dumps(v) for v in vals[i:i+per])+",\n")
    out.write("  },\n")

@dataclass
class Bone:
    sid: str
    name: str
    parent: int
    local: List[float]
    world: List[float]


def collect_bones(root):
    vs=root.find('.//c:library_visual_scenes/c:visual_scene',NS)
    bones=[]; sid_to_idx={}
    def walk(node, parent_world, parent_bone):
        local=node_local(node)
        sid=node.get('sid')
        # The skin's inverse-bind matrices are authored in model space before
        # the top scene conversion (-90° X). Keeping joint0 identity makes the
        # controller bind exact and leaves the runtime in Y-up model space.
        if sid=='joint0': local=ident()
        world=mul(parent_world,local)
        this_parent=parent_bone
        if node.get('type')=='JOINT' and sid:
            idx=len(bones); sid_to_idx[sid]=idx
            bones.append(Bone(sid,node.get('name') or sid,parent_bone,local,world))
            this_parent=idx
        for ch in node.findall('c:node',NS):
            walk(ch,world,this_parent)
    for n in vs.findall('c:node',NS): walk(n,ident(),-1)
    return bones,sid_to_idx


def build_atlas(texdir: pathlib.Path, outpath: pathlib.Path):
    # 1024² atlas. Source art is downscaled only to the level still far above
    # the in-game model's usual 30-40px height.
    spec={
      'eye': ('tr0022_00_eye_col.png',(0,0,512,512)),
      'body':('tr0022_00_body_col.png',(512,0,1024,512)),
      'skin':('tr0022_00_skin_col.png',(0,512,256,1024)),
      'hair':('tr0022_00_hair_col.png',(256,512,512,768)),
      'obj': ('tr0022_00_obj_col.png',(256,768,512,1024)),
    }
    atlas=Image.new('RGBA',(1024,1024),(0,0,0,0)); rects={}
    for key,(fn,box) in spec.items():
        im=Image.open(texdir/fn).convert('RGBA')
        w,h=box[2]-box[0],box[3]-box[1]
        im=im.resize((w,h),Image.Resampling.LANCZOS)
        atlas.paste(im,(box[0],box[1]))
        rects[key]=(box[0]/1024,box[1]/1024,w/1024,h/1024)
    outpath.parent.mkdir(parents=True,exist_ok=True)
    atlas.save(outpath,optimize=True)
    return rects


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('dae',type=pathlib.Path)
    ap.add_argument('--textures',type=pathlib.Path,required=True)
    ap.add_argument('--out-lua',type=pathlib.Path,required=True)
    ap.add_argument('--out-atlas',type=pathlib.Path,required=True)
    a=ap.parse_args()
    root=ET.parse(a.dae).getroot()
    bones,sid_to_idx=collect_bones(root)
    if len(bones)>255: raise ValueError('runtime currently stores bone ids as Lua integers; >255 not expected')
    atlas_rect=build_atlas(a.textures,a.out_atlas)

    geoms={g.get('id'):g for g in root.findall('.//c:library_geometries/c:geometry',NS)}
    controllers=[]
    for c in root.findall('.//c:library_controllers/c:controller',NS):
        skin=c.find('c:skin',NS)
        gid=skin.get('source').lstrip('#')
        controllers.append((c,skin,geoms[gid]))

    pos_first=[]; pos_count=[]; inf_bone=[]; inf_x=[]; inf_y=[]; inf_z=[]; inf_w=[]
    corner_pos=[]; corner_u=[]; corner_v=[]; tri_centers=[]
    all_bind=[]

    for ctrl,skin,geom in controllers:
        mesh=geom.find('c:mesh',NS)
        # POSITION source through <vertices>.
        verts=mesh.find('c:vertices',NS)
        pos_ref=None
        for inp in verts.findall('c:input',NS):
            if inp.get('semantic')=='POSITION': pos_ref=inp.get('source')
        ps=find_source(mesh,pos_ref); pv,pstride=float_source(ps)
        positions=[tuple(pv[i:i+3]) for i in range(0,len(pv),pstride)]
        base_pos=len(pos_first); all_bind.extend(positions)

        # Controller sources / joint lists / inverse bind matrices.
        srcs={s.get('id'):s for s in skin.findall('c:source',NS)}
        j_inputs={i.get('semantic'):i.get('source').lstrip('#') for i in skin.find('c:joints',NS).findall('c:input',NS)}
        joint_names=(srcs[j_inputs['JOINT']].find('c:Name_array',NS).text or '').split()
        ib_vals,ib_stride=float_source(srcs[j_inputs['INV_BIND_MATRIX']])
        invbind=[ib_vals[i:i+16] for i in range(0,len(ib_vals),ib_stride)]
        # Inverse-bind arrays here are already row-major for our convention.
        bind_shape=ident()
        bsm=skin.find('c:bind_shape_matrix',NS)
        if bsm is not None:
            vals=[float(x) for x in (bsm.text or '').split()]
            if len(vals)==16: bind_shape=vals

        vw=skin.find('c:vertex_weights',NS)
        vw_inputs={i.get('semantic'):(i.get('source').lstrip('#'),int(i.get('offset','0'))) for i in vw.findall('c:input',NS)}
        stride=1+max(v[1] for v in vw_inputs.values())
        jsrc,joff=vw_inputs['JOINT']; wsrc,woff=vw_inputs['WEIGHT']
        weight_vals,_=float_source(srcs[wsrc])
        counts=[int(x) for x in (vw.find('c:vcount',NS).text or '').split()]
        packed=[int(x) for x in (vw.find('c:v',NS).text or '').split()]
        cur=0
        if len(counts)!=len(positions): raise ValueError(f"weight/position mismatch {geom.get('id')}")
        for vi,cnt in enumerate(counts):
            influences=[]
            for _ in range(cnt):
                ji=packed[cur+joff]; wi=packed[cur+woff]; cur+=stride
                w=weight_vals[wi]
                if w>1e-7: influences.append((ji,w))
            influences.sort(key=lambda q:q[1],reverse=True)
            influences=influences[:4]
            sw=sum(w for _,w in influences) or 1.0
            pos_first.append(len(inf_bone)+1) # Lua 1-based
            pos_count.append(len(influences))
            p=transform_point(bind_shape,positions[vi])
            for ji,w in influences:
                sid=joint_names[ji]; bi=sid_to_idx[sid]
                lp=transform_point(invbind[ji],p)
                inf_bone.append(bi+1); inf_x.append(lp[0]); inf_y.append(lp[1]); inf_z.append(lp[2]); inf_w.append(w/sw)

        # Triangle corner streams. Material symbol maps directly to atlas key
        # in this asset (body/skin/eye/hair/obj).
        source_cache={}
        def source_tuples(ref):
            rid=ref.lstrip('#')
            if rid not in source_cache:
                vals,st=float_source(find_source(mesh,ref)); source_cache[rid]=[tuple(vals[i:i+st]) for i in range(0,len(vals),st)]
            return source_cache[rid]
        for tri in mesh.findall('c:triangles',NS):
            material=tri.get('material') or 'body'
            if material not in atlas_rect: raise ValueError(f'unknown material symbol {material}')
            inputs=[]
            for inp in tri.findall('c:input',NS):
                inputs.append((inp.get('semantic'),inp.get('source'),int(inp.get('offset','0')),inp.get('set')))
            step=1+max(x[2] for x in inputs)
            idx=[int(x) for x in (tri.find('c:p',NS).text or '').split()]
            voff=next(x[2] for x in inputs if x[0]=='VERTEX')
            texin=next((x for x in inputs if x[0]=='TEXCOORD' and (x[3] in (None,'0'))),None)
            texcoords=source_tuples(texin[1]) if texin else None
            u0,v0,uw,vh=atlas_rect[material]
            for k in range(0,len(idx),step*3):
                tri_ps=[]
                for cidx in range(3):
                    off=k+cidx*step
                    pi=idx[off+voff]
                    corner_pos.append(base_pos+pi+1)
                    tri_ps.append(positions[pi])
                    if texin:
                        uv=texcoords[idx[off+texin[2]]]
                        u=float(uv[0]); v=float(uv[1])
                    else: u=v=0.0
                    # Source textures use repeat wrapping.  The eye mesh in
                    # particular intentionally stores V in the 1.75..2.0 range
                    # to select a repeated section of its texture.  Atlas UVs
                    # cannot rely on texture repeat because repetition would
                    # wrap across the *whole atlas*, so fold source UVs into
                    # 0..1 before remapping them into their atlas rectangle.
                    u = u - math.floor(u)
                    v = v - math.floor(v)

                    # LOVE image UV has top-left origin; COLLADA UV has
                    # bottom-left.  Keep samples half a destination texel away
                    # from each sub-texture edge so linear filtering cannot
                    # bleed into adjacent atlas regions.
                    aw=1024.0; ah=1024.0
                    dest_w=uw*aw; dest_h=vh*ah
                    corner_u.append(u0 + (0.5 + u*(dest_w-1.0))/aw)
                    corner_v.append(v0 + (0.5 + (1.0-v)*(dest_h-1.0))/ah)
                tri_centers.append(tuple(sum(p[d] for p in tri_ps)/3.0 for d in range(3)))

    # Painter orders in bind pose for the four discrete Gen1 facings. Camera
    # looks from +Z. Sort far -> near after rotating model around Y.
    yaws={'down':0.0,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}
    orders={}
    for name,yaw in yaws.items():
        c,s=math.cos(yaw),math.sin(yaw)
        depths=[]
        for ti,(x,y,z) in enumerate(tri_centers):
            zp=x*s+z*c
            depths.append((zp,ti+1))
        # Smaller z is farther from +Z camera, draw it first.
        depths.sort(key=lambda q:q[0])
        orders[name]=[ti for _,ti in depths]

    mins=[min(p[d] for p in all_bind) for d in range(3)]
    maxs=[max(p[d] for p in all_bind) for d in range(3)]
    names=[b.name for b in bones]
    anim_names=['Waist','Spine1','LArm','RArm','LForeArm','RForeArm','Hips','LThigh','LLeg','LFoot','RThigh','RLeg','RFoot']
    anim={n:names.index(n)+1 for n in anim_names if n in names}

    a.out_lua.parent.mkdir(parents=True,exist_ok=True)
    with a.out_lua.open('w',encoding='utf-8',newline='\n') as out:
        out.write('-- GENERATED by tools/convert_red_dae.py -- do not hand-edit.\nreturn {\n')
        out.write(f"  boneCount = {len(bones)},\n  positionCount = {len(pos_first)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(tri_centers)},\n")
        lua_strings('boneName',names,out)
        lua_array('boneParent',[b.parent+1 if b.parent>=0 else 0 for b in bones],out)
        lua_array('boneLocal',[v for b in bones for v in b.local],out)
        lua_array('posFirst',pos_first,out); lua_array('posCount',pos_count,out)
        lua_array('infBone',inf_bone,out); lua_array('infX',inf_x,out); lua_array('infY',inf_y,out); lua_array('infZ',inf_z,out); lua_array('infW',inf_w,out)
        lua_array('cornerPos',corner_pos,out); lua_array('cornerU',corner_u,out); lua_array('cornerV',corner_v,out)
        out.write('  order = {\n')
        for k in ('down','left','up','right'):
            out.write(f'    {k} = {{\n')
            vals=orders[k]
            for i in range(0,len(vals),20): out.write('      '+', '.join(map(str,vals[i:i+20]))+',\n')
            out.write('    },\n')
        out.write('  },\n')
        out.write('  animBone = {\n')
        for n,i in anim.items(): out.write(f'    {n} = {i},\n')
        out.write('  },\n')
        lua_array('bounds',mins+maxs,out,6)
        out.write('}\n')
    print(f"bones={len(bones)} positions={len(pos_first)} influences={len(inf_bone)} triangles={len(tri_centers)} corners={len(corner_pos)}")
    print(f"bounds min={mins} max={maxs}")
    print(f"wrote {a.out_lua} and {a.out_atlas}")

if __name__=='__main__': main()
