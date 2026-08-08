#!/usr/bin/env python3
from __future__ import annotations
import argparse, math, pathlib, xml.etree.ElementTree as ET
import numpy as np
from PIL import Image
NS={'c':'http://www.collada.org/2005/11/COLLADASchema'}

def ident(): return np.eye(4,dtype=float)
def mat_from_collada(text):
    vals=np.array([float(x) for x in (text or '').split()],dtype=float)
    if vals.size!=16: return ident()
    # FCollada here serializes row-major matrices.
    return vals.reshape(4,4)
def float_source(src):
    vals=[float(x) for x in (src.find('c:float_array',NS).text or '').split()]
    acc=src.find('c:technique_common/c:accessor',NS); st=int(acc.get('stride','1')) if acc is not None else 1
    return vals,st
def find_source(parent,ref):
    rid=ref.lstrip('#'); el=parent.find(f"c:source[@id='{rid}']",NS)
    if el is None: raise KeyError(rid)
    return el
def lua_num(x):
    if isinstance(x,int): return str(x)
    if abs(x)<5e-10: x=0.0
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
def tp(m,p):
    q=m@np.array([p[0],p[1],p[2],1.0]); return q[:3]

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('dae',type=pathlib.Path); ap.add_argument('--diffuse',type=pathlib.Path,required=True); ap.add_argument('--out-lua',type=pathlib.Path,required=True); ap.add_argument('--out-atlas',type=pathlib.Path,required=True); a=ap.parse_args()
    root=ET.parse(a.dae).getroot(); mesh=root.find('.//c:library_geometries/c:geometry/c:mesh',NS); skin=root.find('.//c:library_controllers/c:controller/c:skin',NS)
    # exact diffuse atlas: duplicated 2px edges, otherwise original pixels
    im=Image.open(a.diffuse).convert('RGBA'); tw,th=im.size; AW,AH=tw+4,th+4
    atlas=Image.new('RGBA',(AW,AH),(0,0,0,0)); atlas.paste(im,(2,2));
    atlas.paste(im.crop((0,0,tw,1)).resize((tw,2)),(2,0)); atlas.paste(im.crop((0,th-1,tw,th)).resize((tw,2)),(2,th+2)); atlas.paste(im.crop((0,0,1,th)).resize((2,th)),(0,2)); atlas.paste(im.crop((tw-1,0,tw,th)).resize((2,th)),(tw+2,2));
    a.out_atlas.parent.mkdir(parents=True,exist_ok=True); atlas.save(a.out_atlas,optimize=True)

    # geometry positions + UV from <vertices>
    verts_el=mesh.find('c:vertices',NS); posref=uvref=None
    for inp in verts_el.findall('c:input',NS):
        sem=inp.get('semantic'); ref=inp.get('source')
        if sem=='POSITION': posref=ref
        elif sem=='TEXCOORD': uvref=ref
    pv,pst=float_source(find_source(mesh,posref)); pos=[tuple(pv[i:i+3]) for i in range(0,len(pv),pst)]
    uvv,uvst=float_source(find_source(mesh,uvref)); uv=[tuple(uvv[i:i+2]) for i in range(0,len(uvv),uvst)]

    # hierarchy (names/parents only); exact rest worlds come from inverse bind matrices
    names=[]; parents=[]; name_to_idx={}
    vs=root.find('.//c:library_visual_scenes/c:visual_scene',NS)
    def walk(n,parent=-1):
        this=parent
        if n.get('type')=='JOINT':
            name=n.get('sid') or n.get('name') or n.get('id'); this=len(names); names.append(name); parents.append(parent+1 if parent>=0 else 0); name_to_idx[name]=this
        for ch in n.findall('c:node',NS): walk(ch,this)
    for n in vs.findall('c:node',NS): walk(n,-1)

    srcs={s.get('id'):s for s in skin.findall('c:source',NS)}
    jins={i.get('semantic'):i.get('source').lstrip('#') for i in skin.find('c:joints',NS).findall('c:input',NS)}
    joint_names=(srcs[jins['JOINT']].find('c:Name_array',NS).text or '').split()
    ibvals,ibst=float_source(srcs[jins['INV_BIND_MATRIX']]); invbind=[np.array(ibvals[i:i+16]).reshape(4,4) for i in range(0,len(ibvals),ibst)]
    bsm=skin.find('c:bind_shape_matrix',NS); bindshape=mat_from_collada(bsm.text) if bsm is not None else ident()
    # row-major inverse bind is correct for this asset; its inverses have plausible model-space joint origins.
    world_by_joint=[np.linalg.inv(m) for m in invbind]
    worlds=[None]*len(names)
    for jn,w in zip(joint_names,world_by_joint):
        if jn in name_to_idx: worlds[name_to_idx[jn]]=w
    # fill any unweighted helper bones from scene hierarchy if needed
    for i,w in enumerate(worlds):
        if w is None: worlds[i]=ident() if parents[i]==0 else worlds[parents[i]-1].copy()
    locals=[]
    for i,w in enumerate(worlds):
        pi=parents[i]-1; locals.append(np.linalg.inv(worlds[pi])@w if pi>=0 else w)

    vw=skin.find('c:vertex_weights',NS); ins={i.get('semantic'):(i.get('source').lstrip('#'),int(i.get('offset','0'))) for i in vw.findall('c:input',NS)}; step=1+max(v[1] for v in ins.values()); joff=ins['JOINT'][1]; wsrc,woff=ins['WEIGHT']; wvals,_=float_source(srcs[wsrc]); counts=[int(x) for x in (vw.find('c:vcount',NS).text or '').split()]; packed=[int(x) for x in (vw.find('c:v',NS).text or '').split()]
    pf=[];pc=[];ib=[];ix=[];iy=[];iz=[];iw=[]; cur=0; runtime=[]
    for vi,cnt in enumerate(counts):
        p=tp(bindshape,pos[vi]); runtime.append(tuple(p))
        arr=[]
        for _ in range(cnt):
            ji=packed[cur+joff]; wi=packed[cur+woff]; cur+=step; wt=wvals[wi]
            if wt>1e-7: arr.append((ji,wt))
        arr.sort(key=lambda q:q[1],reverse=True); arr=arr[:4]; sw=sum(w for _,w in arr) or 1.0
        pf.append(len(ib)+1);pc.append(len(arr))
        for ji,wt in arr:
            bi=name_to_idx[joint_names[ji]]; lp=tp(invbind[ji],p); ib.append(bi+1);ix.append(lp[0]);iy.append(lp[1]);iz.append(lp[2]);iw.append(wt/sw)

    # validate exact rest reconstruction
    avg=mx=0.0
    for vi,p in enumerate(runtime):
        out=np.zeros(3); first=pf[vi]-1
        for q in range(first,first+pc[vi]): out += tp(worlds[ib[q]-1],(ix[q],iy[q],iz[q]))*iw[q]
        e=float(np.linalg.norm(np.array(p)-out)); avg+=e; mx=max(mx,e)
    avg/=len(runtime)

    tri=mesh.find('c:triangles',NS); ids=[int(x) for x in (tri.find('c:p',NS).text or '').split()]
    corner_pos=[];cu=[];cv=[];cent=[]
    for k in range(0,len(ids),3):
        pts=[]
        for c in range(3):
            vi=ids[k+c]; corner_pos.append(vi+1); pts.append(runtime[vi]); u,v=uv[vi][:2]
            # This asset stores V around -2..-1 and expects repeating. Fold the source tile,
            # then flip into LÖVE's top-down image coordinates.
            u=u-math.floor(u); vv=(-v)%1.0
            cu.append((2.5+u*(tw-1))/AW); cv.append((2.5+vv*(th-1))/AH)
        cent.append(tuple(sum(p[d] for p in pts)/3 for d in range(3)))
    orders={}; yaws={'down':0.,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}
    for key,yaw in yaws.items():
        c,s=math.cos(yaw),math.sin(yaw); ds=sorted((x*s+z*c,i+1) for i,(x,y,z) in enumerate(cent)); orders[key]=[i for _,i in ds]
    mins=[min(p[d] for p in runtime) for d in range(3)]; maxs=[max(p[d] for p in runtime) for d in range(3)]
    alias={'Waist':'n_hara','Hips':'j_kosi','Spine1':'j_sebo','Neck':'j_sebo','Head':'j_kao','LShoulder':'j_sako_l','LArm':'j_ude_a_l','LForeArm':'j_ude_b_l','LHand':'j_te_l','RShoulder':'j_sako_r','RArm':'j_ude_a_r','RForeArm':'j_ude_b_r','RHand':'j_te_r','LThigh':'j_asi_a_l','LLeg':'j_asi_b_l','LFoot':'j_asi_c_l','LToe':'j_asi_c_l_end','RThigh':'j_asi_a_r','RLeg':'j_asi_b_r','RFoot':'j_asi_c_r','RToe':'j_asi_c_r_end'}
    anim={k:name_to_idx[v]+1 for k,v in alias.items() if v in name_to_idx}
    a.out_lua.parent.mkdir(parents=True,exist_ok=True)
    with a.out_lua.open('w') as out:
        out.write('-- GENERATED from Wind-Up Cloud.dae exact weighted rig + corrected repeated UVs\nreturn {\n'); out.write(f'  boneCount = {len(names)},\n  positionCount = {len(runtime)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(cent)},\n'); lua_strings('boneName',names,out);lua_array('boneParent',parents,out);lua_array('boneLocal',[x for m in locals for x in m.reshape(-1)],out);lua_array('posFirst',pf,out);lua_array('posCount',pc,out);lua_array('infBone',ib,out);lua_array('infX',ix,out);lua_array('infY',iy,out);lua_array('infZ',iz,out);lua_array('infW',iw,out);lua_array('cornerPos',corner_pos,out);lua_array('cornerU',cu,out);lua_array('cornerV',cv,out);out.write('  order = {\n');
        for key in ('down','left','up','right'):
            out.write(f'    {key} = {{\n'); vals=orders[key]
            for i in range(0,len(vals),20): out.write('      '+', '.join(map(str,vals[i:i+20]))+',\n')
            out.write('    },\n')
        out.write('  },\n  animBone = {\n');
        for k,v in anim.items(): out.write(f'    {k} = {v},\n')
        out.write('  },\n'); lua_array('bounds',mins+maxs,out,6); out.write('}\n')
    print('Cloud exact:',len(names),'bones',len(runtime),'positions',len(cent),'tris','rest avg',avg,'max',mx,'bounds',mins,maxs)
if __name__=='__main__': main()
