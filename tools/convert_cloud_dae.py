#!/usr/bin/env python3
from __future__ import annotations
import argparse, math, pathlib, xml.etree.ElementTree as ET
from PIL import Image

NS={'c':'http://www.collada.org/2005/11/COLLADASchema'}

def ident(): return [1.,0,0,0, 0,1.,0,0, 0,0,1.,0, 0,0,0,1.]
def mul(a,b):
    o=[0.]*16
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
    if n<1e-12: return ident()
    x,y,z=x/n,y/n,z/n
    a=math.radians(deg); c=math.cos(a); s=math.sin(a); C=1-c
    return [
        x*x*C+c, x*y*C-z*s, x*z*C+y*s, 0,
        y*x*C+z*s, y*y*C+c, y*z*C-x*s, 0,
        z*x*C-y*s, z*y*C+x*s, z*z*C+c, 0,
        0,0,0,1,
    ]

def transform(m,p):
    x,y,z=p
    return (m[0]*x+m[1]*y+m[2]*z+m[3],
            m[4]*x+m[5]*y+m[6]*z+m[7],
            m[8]*x+m[9]*y+m[10]*z+m[11])

def inv_rigid(m):
    rt=[m[0],m[4],m[8], m[1],m[5],m[9], m[2],m[6],m[10]]
    tx,ty,tz=m[3],m[7],m[11]
    return [rt[0],rt[1],rt[2],-(rt[0]*tx+rt[1]*ty+rt[2]*tz),
            rt[3],rt[4],rt[5],-(rt[3]*tx+rt[4]*ty+rt[5]*tz),
            rt[6],rt[7],rt[8],-(rt[6]*tx+rt[7]*ty+rt[8]*tz),
            0,0,0,1]

def node_local(node):
    m=ident()
    for ch in list(node):
        tag=ch.tag.split('}')[-1]
        if tag not in ('translate','rotate','scale','matrix'): continue
        v=[float(x) for x in (ch.text or '').split()]
        if tag=='translate': t=trans(*v[:3])
        elif tag=='rotate': t=rot_axis(*v[:4])
        elif tag=='scale': t=scale(*v[:3])
        else:
            # COLLADA matrix serialized column-major.
            t=[v[c*4+r] for r in range(4) for c in range(4)]
        m=mul(m,t)
    return m

def float_source(src):
    arr=src.find('c:float_array',NS)
    vals=[float(x) for x in (arr.text or '').split()]
    acc=src.find('c:technique_common/c:accessor',NS)
    stride=int(acc.get('stride','1')) if acc is not None else 1
    return vals,stride

def find_source(parent, ref):
    rid=ref[1:] if ref.startswith('#') else ref
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

def collect_bones(root):
    vs=root.find('.//c:library_visual_scenes/c:visual_scene',NS)
    bones=[]; id_to_idx={}; name_to_idx={}
    def walk(node,parent_world,parent_idx):
        local=node_local(node); world=mul(parent_world,local)
        this_parent=parent_idx
        if node.get('type')=='JOINT':
            idx=len(bones)
            name=node.get('name') or node.get('sid') or node.get('id')
            bones.append((name,parent_idx,local,world))
            if node.get('id'): id_to_idx[node.get('id')]=idx
            if node.get('sid'): id_to_idx[node.get('sid')]=idx
            id_to_idx[name]=idx; name_to_idx[name]=idx
            this_parent=idx
        for ch in node.findall('c:node',NS):
            walk(ch,world,this_parent)
    for n in vs.findall('c:node',NS): walk(n,ident(),-1)
    return bones,id_to_idx,name_to_idx

def build_atlas(diffuse_path,outpath):
    im=Image.open(diffuse_path).convert('RGBA')
    # upscale modestly to keep crisp enough in-game
    atlas=im.resize((1024,512),Image.Resampling.NEAREST)
    outpath.parent.mkdir(parents=True,exist_ok=True)
    atlas.save(outpath,optimize=True)
    return (1024,512)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('dae',type=pathlib.Path)
    ap.add_argument('--diffuse',type=pathlib.Path,required=True)
    ap.add_argument('--out-lua',type=pathlib.Path,required=True)
    ap.add_argument('--out-atlas',type=pathlib.Path,required=True)
    args=ap.parse_args()

    root=ET.parse(args.dae).getroot()
    bones,id_to_idx,name_to_idx=collect_bones(root)
    AW,AH=build_atlas(args.diffuse,args.out_atlas)

    geoms={g.get('id'):g for g in root.findall('.//c:library_geometries/c:geometry',NS)}
    ctrl=root.find('.//c:library_controllers/c:controller',NS)
    skin=ctrl.find('c:skin',NS)
    gid=skin.get('source').lstrip('#')
    geom=geoms[gid]
    mesh=geom.find('c:mesh',NS)

    verts=mesh.find('c:vertices',NS)
    pos_ref=None
    for inp in verts.findall('c:input',NS):
        if inp.get('semantic')=='POSITION': pos_ref=inp.get('source')
    ps=find_source(mesh,pos_ref); pv,pstride=float_source(ps)
    positions=[tuple(pv[i:i+3]) for i in range(0,len(pv),pstride)]

    srcs={s.get('id'):s for s in skin.findall('c:source',NS)}
    j_inputs={i.get('semantic'):i.get('source').lstrip('#') for i in skin.find('c:joints',NS).findall('c:input',NS)}
    joint_names=(srcs[j_inputs['JOINT']].find('c:Name_array',NS).text or '').split()
    ib_vals,ib_stride=float_source(srcs[j_inputs['INV_BIND_MATRIX']])
    raw_invbind=[ib_vals[i:i+16] for i in range(0,len(ib_vals),ib_stride)]
    # Choose row-major vs column-major interpretation by reconstruction error.
    candidates=[]
    for mode in ('row','col'):
        invbind=[]
        for m in raw_invbind:
            if mode=='col': invbind.append([m[c*4+r] for r in range(4) for c in range(4)])
            else: invbind.append(m)
        candidates.append((mode,invbind))

    bind_shape=ident()
    bsm=skin.find('c:bind_shape_matrix',NS)
    if bsm is not None:
        vals=[float(x) for x in (bsm.text or '').split()]
        if len(vals)==16: bind_shape=[vals[c*4+r] for r in range(4) for c in range(4)]

    vw=skin.find('c:vertex_weights',NS)
    vw_inputs={i.get('semantic'):(i.get('source').lstrip('#'),int(i.get('offset','0'))) for i in vw.findall('c:input',NS)}
    step=1+max(v[1] for v in vw_inputs.values())
    _,joff=vw_inputs['JOINT']; wsrc,woff=vw_inputs['WEIGHT']
    weight_vals,_=float_source(srcs[wsrc])
    counts=[int(x) for x in (vw.find('c:vcount',NS).text or '').split()]
    packed=[int(x) for x in (vw.find('c:v',NS).text or '').split()]
    influences=[]
    cur=0
    for cnt in counts:
        arr=[]
        for _ in range(cnt):
            ji=packed[cur+joff]; wi=packed[cur+woff]; cur+=step
            w=weight_vals[wi]
            if w>1e-7: arr.append((ji,w))
        arr.sort(key=lambda q:q[1], reverse=True); arr=arr[:4]
        sw=sum(w for _,w in arr) or 1.0
        influences.append([(ji,w/sw) for ji,w in arr])

    # choose correct inverse-bind interpretation via rest-pose error.
    # Use the inverse-bind matrices themselves as the source of truth for the
    # bind-pose worlds; that avoids scene-export quirks like the top-level
    # 100x scale on this asset.
    best=None
    for mode,invbind in candidates:
        worlds=[]
        for m in invbind:
            worlds.append(inv_rigid(m))
        avg=maxerr=0.0
        sample=min(len(positions),500)
        for vi in range(sample):
            p=transform(bind_shape,positions[vi])
            out=[0,0,0]
            for ji,w in influences[vi]:
                bi=id_to_idx.get(joint_names[ji])
                if bi is None: continue
                tp=transform(worlds[ji], transform(invbind[ji], p))
                out[0]+=tp[0]*w; out[1]+=tp[1]*w; out[2]+=tp[2]*w
            e=math.dist(p,out); avg+=e; maxerr=max(maxerr,e)
        avg/=sample
        if best is None or avg<best[1]: best=(mode,avg,maxerr,invbind,worlds)
    mode,avg_err,max_err,invbind,source_worlds=best

    parents=[]; locals=[]; worlds=[]
    for idx,(name,parent,local,world) in enumerate(bones):
        parents.append(parent+1 if parent>=0 else 0)
        # bind world from inverse bind
        w=source_worlds[joint_names.index(name)] if name in joint_names else source_worlds[idx]
        worlds.append(w)
    for idx,w in enumerate(worlds):
        parent=bones[idx][1]
        if parent>=0: locals.append(mul(inv_rigid(worlds[parent]), w))
        else: locals.append(w)

    pos_first=[]; pos_count=[]; inf_bone=[]; inf_x=[]; inf_y=[]; inf_z=[]; inf_w=[]
    for vi,p0 in enumerate(positions):
        p=transform(bind_shape,p0)
        pos_first.append(len(inf_bone)+1)
        pos_count.append(len(influences[vi]))
        for ji,w in influences[vi]:
            bi=id_to_idx[joint_names[ji]]
            lp=transform(invbind[ji],p)
            inf_bone.append(bi+1); inf_x.append(lp[0]); inf_y.append(lp[1]); inf_z.append(lp[2]); inf_w.append(w)

    source_cache={}
    def tuples(ref):
        rid=ref.lstrip('#')
        if rid not in source_cache:
            vals,st=float_source(find_source(mesh,ref))
            source_cache[rid]=[tuple(vals[i:i+st]) for i in range(0,len(vals),st)]
        return source_cache[rid]
    corner_pos=[]; corner_u=[]; corner_v=[]; tri_centers=[]
    tri=mesh.find('c:triangles',NS)
    inputs=[]
    for inp in tri.findall('c:input',NS):
        inputs.append((inp.get('semantic'),inp.get('source'),int(inp.get('offset','0')),inp.get('set')))
    pstep=1+max(x[2] for x in inputs)
    idx=[int(x) for x in (tri.find('c:p',NS).text or '').split()]
    voff=next(x[2] for x in inputs if x[0]=='VERTEX')
    texin=next((x for x in inputs if x[0]=='TEXCOORD'),None)
    texcoords=tuples(texin[1]) if texin else None
    for k in range(0,len(idx),pstep*3):
        tri_ps=[]
        for c in range(3):
            off=k+c*pstep
            pi=idx[off+voff]
            corner_pos.append(pi+1)
            p=transform(bind_shape,positions[pi]); tri_ps.append(p)
            u,v=(texcoords[idx[off+texin[2]]][:2] if texin else (0.0,0.0))
            u=u-math.floor(u); v=v-math.floor(v)
            corner_u.append((0.5+u*(AW-1))/AW)
            corner_v.append((0.5+v*(AH-1))/AH)
        tri_centers.append(tuple(sum(p[d] for p in tri_ps)/3 for d in range(3)))

    yaws={'down':0.,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}; orders={}
    for name,yaw in yaws.items():
        c,s=math.cos(yaw),math.sin(yaw); ds=[]
        for ti,(x,y,z) in enumerate(tri_centers): ds.append((x*s+z*c, ti+1))
        ds.sort(key=lambda q:q[0]); orders[name]=[ti for _,ti in ds]

    mins=[min(transform(bind_shape,p)[d] for p in positions) for d in range(3)]
    maxs=[max(transform(bind_shape,p)[d] for p in positions) for d in range(3)]

    alias={
        'Waist':'n_hara', 'Hips':'j_kosi', 'Spine1':'j_sebo', 'Neck':'j_sebo', 'Head':'j_kao',
        'LShoulder':'j_sako_l','LArm':'j_ude_a_l','LForeArm':'j_ude_b_l','LHand':'j_te_l',
        'RShoulder':'j_sako_r','RArm':'j_ude_a_r','RForeArm':'j_ude_b_r','RHand':'j_te_r',
        'LThigh':'j_asi_a_l','LLeg':'j_asi_b_l','LFoot':'j_asi_c_l','LToe':'j_asi_c_l_end',
        'RThigh':'j_asi_a_r','RLeg':'j_asi_b_r','RFoot':'j_asi_c_r','RToe':'j_asi_c_r_end',
    }
    anim={k:name_to_idx[v]+1 for k,v in alias.items() if v in name_to_idx}

    args.out_lua.parent.mkdir(parents=True,exist_ok=True)
    with args.out_lua.open('w') as out:
        out.write('-- GENERATED from Wind-Up Cloud.dae\nreturn {\n')
        out.write(f'  boneCount = {len(bones)},\n  positionCount = {len(pos_first)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(tri_centers)},\n')
        lua_strings('boneName',[b[0] for b in bones],out); lua_array('boneParent',parents,out); lua_array('boneLocal',[v for m in locals for v in m],out)
        lua_array('posFirst',pos_first,out); lua_array('posCount',pos_count,out); lua_array('infBone',inf_bone,out); lua_array('infX',inf_x,out); lua_array('infY',inf_y,out); lua_array('infZ',inf_z,out); lua_array('infW',inf_w,out)
        lua_array('cornerPos',corner_pos,out); lua_array('cornerU',corner_u,out); lua_array('cornerV',corner_v,out)
        out.write('  order = {\n')
        for k in ('down','left','up','right'):
            out.write(f'    {k} = {{\n')
            vals=orders[k]
            for i in range(0,len(vals),20): out.write('      '+', '.join(map(str,vals[i:i+20]))+',\n')
            out.write('    },\n')
        out.write('  },\n  animBone = {\n')
        for k,v in anim.items(): out.write(f'    {k} = {v},\n')
        out.write('  },\n')
        lua_array('bounds',mins+maxs,out,6)
        out.write('}\n')
    print('Cloud bones',len(bones),'tris',len(tri_centers),'avg err',avg_err,'max',max_err,'invbind',mode,'anim',anim)

if __name__=='__main__':
    main()
