#!/usr/bin/env python3
from __future__ import annotations
import argparse, math, pathlib, xml.etree.ElementTree as ET
from PIL import Image
NS={'c':'http://www.collada.org/2005/11/COLLADASchema'}

def ident(): return [1.,0,0,0, 0,1.,0,0, 0,0,1.,0, 0,0,0,1.]
def mul(a,b):
    o=[0.]*16
    for r in range(4):
        for c in range(4): o[r*4+c]=sum(a[r*4+k]*b[k*4+c] for k in range(4))
    return o

def trans(x,y,z): m=ident(); m[3]=x; m[7]=y; m[11]=z; return m
def inv_rigid(m):
    rt=[m[0],m[4],m[8],m[1],m[5],m[9],m[2],m[6],m[10]]; tx,ty,tz=m[3],m[7],m[11]
    return [rt[0],rt[1],rt[2],-(rt[0]*tx+rt[1]*ty+rt[2]*tz),rt[3],rt[4],rt[5],-(rt[3]*tx+rt[4]*ty+rt[5]*tz),rt[6],rt[7],rt[8],-(rt[6]*tx+rt[7]*ty+rt[8]*tz),0,0,0,1]
def transform(m,p):
    x,y,z=p; return (m[0]*x+m[1]*y+m[2]*z+m[3],m[4]*x+m[5]*y+m[6]*z+m[7],m[8]*x+m[9]*y+m[10]*z+m[11])
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
def float_source(src):
    vals=[float(x) for x in (src.find('c:float_array',NS).text or '').split()]
    acc=src.find('c:technique_common/c:accessor',NS); st=int(acc.get('stride','1')) if acc is not None else 1
    return [tuple(vals[i:i+st]) for i in range(0,len(vals),st)]

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('dae',type=pathlib.Path); ap.add_argument('--diffuse',type=pathlib.Path,required=True); ap.add_argument('--out-lua',type=pathlib.Path,required=True); ap.add_argument('--out-atlas',type=pathlib.Path,required=True); a=ap.parse_args()
    root=ET.parse(a.dae).getroot(); mesh=root.find('.//c:library_geometries/c:geometry/c:mesh',NS)
    sources={s.get('id'):float_source(s) for s in mesh.findall('c:source',NS)}
    verts_el=mesh.find('c:vertices',NS); pos_id=uv_id=None
    for inp in verts_el.findall('c:input',NS):
        sem=inp.get('semantic'); rid=inp.get('source').lstrip('#')
        if sem=='POSITION': pos_id=rid
        elif sem=='TEXCOORD': uv_id=rid
    verts=[(p[0],p[1],p[2]) for p in sources[pos_id]]; uvs=sources[uv_id]
    tri=mesh.find('c:triangles',NS); ids=[int(x) for x in (tri.find('c:p',NS).text or '').split()]
    tris=[ids[i:i+3] for i in range(0,len(ids),3)]
    im=Image.open(a.diffuse).convert('RGBA').resize((1024,512),Image.Resampling.NEAREST); a.out_atlas.parent.mkdir(parents=True,exist_ok=True); im.save(a.out_atlas,optimize=True); AW,AH=im.size
    mins=[min(v[d] for v in verts) for d in range(3)]; maxs=[max(v[d] for v in verts) for d in range(3)]; width=maxs[0]-mins[0]; height=maxs[1]-mins[1]
    hip_y=mins[1]+height*.49; spine_y=mins[1]+height*.68; shoulder_y=mins[1]+height*.72; neck_y=mins[1]+height*.82; head_y=mins[1]+height*.89; knee_y=mins[1]+height*.22; ankle_y=mins[1]+height*.04; shoulder_x=width*.20; hip_x=width*.10
    upper=max(2.5,width*.14); fore=max(2.5,width*.13); thigh=max(3,hip_y-knee_y); shin=max(3,knee_y-ankle_y)
    names=['Root','Waist','Hips','Spine1','Neck','Head','LShoulder','LArm','LForeArm','LHand','RShoulder','RArm','RForeArm','RHand','LThigh','LLeg','LFoot','LToe','RThigh','RLeg','RFoot','RToe']
    parent=[0,1,2,2,4,5,4,7,8,9,4,11,12,13,3,15,16,17,3,19,20,21]
    locals=[ident(),trans(0,hip_y,0),ident(),trans(0,spine_y-hip_y,0),trans(0,neck_y-spine_y,0),trans(0,head_y-neck_y,0),trans(shoulder_x,shoulder_y-spine_y,0),ident(),trans(upper,0,0),trans(fore,0,0),trans(-shoulder_x,shoulder_y-spine_y,0),ident(),trans(-upper,0,0),trans(-fore,0,0),trans(hip_x,0,0),trans(0,-thigh,0),trans(0,-shin,0),trans(0,-1,width*.05),trans(-hip_x,0,0),trans(0,-thigh,0),trans(0,-shin,0),trans(0,-1,width*.05)]
    worlds=[]
    for i,m in enumerate(locals): worlds.append(mul(worlds[parent[i]-1],m) if parent[i]>0 else m)
    inv=[inv_rigid(m) for m in worlds]
    anim={n:i+1 for i,n in enumerate(names) if n!='Root'}
    pf=[];pc=[];ib=[];ix=[];iy=[];iz=[];iw=[]
    for p in verts:
        x,y,z=p; ax=abs(x)
        if y>=head_y-1.5: bi=6
        elif ax>shoulder_x*.75 and y>hip_y+4:
            left=x>0
            if ax>shoulder_x+upper*.65: bi=10 if left else 14
            elif ax>shoulder_x+upper*.25: bi=9 if left else 13
            else: bi=8 if left else 12
        elif y<hip_y:
            left=x>0
            if y>knee_y: bi=15 if left else 19
            elif y>ankle_y: bi=16 if left else 20
            elif z>2: bi=18 if left else 22
            else: bi=17 if left else 21
        elif y>neck_y-2: bi=5
        elif y>spine_y: bi=4
        else: bi=3
        pf.append(len(ib)+1); pc.append(1); lp=transform(inv[bi-1],p); ib.append(bi); ix.append(lp[0]);iy.append(lp[1]);iz.append(lp[2]);iw.append(1.0)
    cp=[];cu=[];cv=[];cent=[]
    for t in tris:
        pts=[]
        for vi in t:
            cp.append(vi+1); pts.append(verts[vi]); u,v=uvs[vi][:2]; u=u%1.0; v=v%1.0; cu.append((.5+u*(AW-1))/AW); cv.append((.5+v*(AH-1))/AH)
        cent.append(tuple(sum(p[d] for p in pts)/3 for d in range(3)))
    orders={}; yaws={'down':0,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}
    for name,yaw in yaws.items():
        c,s=math.cos(yaw),math.sin(yaw); ds=sorted((x*s+z*c,i+1) for i,(x,y,z) in enumerate(cent)); orders[name]=[i for _,i in ds]
    with a.out_lua.open('w') as out:
        out.write('-- GENERATED from Cloud DAE geometry with stable auto-rig\nreturn {\n'); out.write(f'  boneCount = {len(names)},\n  positionCount = {len(verts)},\n  cornerCount = {len(cp)},\n  triangleCount = {len(tris)},\n'); lua_strings('boneName',names,out);lua_array('boneParent',parent,out);lua_array('boneLocal',[v for m in locals for v in m],out);lua_array('posFirst',pf,out);lua_array('posCount',pc,out);lua_array('infBone',ib,out);lua_array('infX',ix,out);lua_array('infY',iy,out);lua_array('infZ',iz,out);lua_array('infW',iw,out);lua_array('cornerPos',cp,out);lua_array('cornerU',cu,out);lua_array('cornerV',cv,out);out.write('  order = {\n');
        for k in ('down','left','up','right'):
            out.write(f'    {k} = {{\n'); vals=orders[k]
            for i in range(0,len(vals),20): out.write('      '+', '.join(map(str,vals[i:i+20]))+',\n')
            out.write('    },\n')
        out.write('  },\n  animBone = {\n');
        for k,v in anim.items(): out.write(f'    {k} = {v},\n')
        out.write('  },\n'); lua_array('bounds',mins+maxs,out,6); out.write('}\n')
    print('Cloud auto',len(verts),'verts',len(tris),'tris bounds',mins,maxs)
if __name__=='__main__': main()
