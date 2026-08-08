#!/usr/bin/env python3
from __future__ import annotations
import argparse, math, pathlib
from PIL import Image

def ident(): return [1.,0,0,0, 0,1.,0,0, 0,0,1.,0, 0,0,0,1.]
def trans(x,y,z):
    m=ident(); m[3]=x; m[7]=y; m[11]=z; return m

def inv_rigid(m):
    rt=[m[0],m[4],m[8], m[1],m[5],m[9], m[2],m[6],m[10]]
    tx,ty,tz=m[3],m[7],m[11]
    return [rt[0],rt[1],rt[2],-(rt[0]*tx+rt[1]*ty+rt[2]*tz),
            rt[3],rt[4],rt[5],-(rt[3]*tx+rt[4]*ty+rt[5]*tz),
            rt[6],rt[7],rt[8],-(rt[6]*tx+rt[7]*ty+rt[8]*tz),
            0,0,0,1]

def mul(a,b):
    o=[0.]*16
    for r in range(4):
        for c in range(4):
            o[r*4+c]=sum(a[r*4+k]*b[k*4+c] for k in range(4))
    return o

def transform(m,p):
    x,y,z=p
    return (m[0]*x+m[1]*y+m[2]*z+m[3],m[4]*x+m[5]*y+m[6]*z+m[7],m[8]*x+m[9]*y+m[10]*z+m[11])

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

def build_atlas(srcdir,outpath):
    specs={
        'face1.png':(0,0,256,256),
        'tex1.png':(256,0,512,256),
        'tex2.png':(512,0,768,256),
        'tex3.png':(0,256,512,768),
        'tex4.png':(512,256,1024,768),
    }
    atlas=Image.new('RGBA',(1024,768),(0,0,0,0)); rect={}
    for fn,box in specs.items():
        im=Image.open(srcdir/fn).convert('RGBA')
        w,h=box[2]-box[0],box[3]-box[1]
        if im.size!=(w,h): im=im.resize((w,h),Image.Resampling.NEAREST)
        atlas.paste(im,(box[0],box[1]))
        rect[fn]=(box[0]/1024,box[1]/768,w/1024,h/768,im.size[0],im.size[1])
    outpath.parent.mkdir(parents=True,exist_ok=True); atlas.save(outpath,optimize=True)
    return rect,(1024,768)

def parse_obj(path):
    verts=[]; uvs=[]; tris=[]; current='tex3.png'
    for raw in path.read_text(errors='replace').splitlines():
        line=raw.strip()
        if not line or line.startswith('#'): continue
        if line.startswith('v '):
            _,x,y,z=line.split()[:4]; verts.append((float(x),float(y),-float(z)))  # flip Z so forward is +Z
        elif line.startswith('vt '):
            p=line.split(); u=float(p[1]); v=float(p[2]); uvs.append((u,v))
        elif line.startswith('usemtl '):
            current=line.split(None,1)[1].strip()
        elif line.startswith('f '):
            items=line.split()[1:]
            corners=[]
            for tok in items:
                parts=tok.split('/')
                vi=int(parts[0]); ti=int(parts[1]) if len(parts)>1 and parts[1] else 0
                if vi<0: vi=len(verts)+1+vi
                if ti<0: ti=len(uvs)+1+ti
                corners.append((vi,ti))
            for i in range(1,len(corners)-1):
                tris.append((current,[corners[0], corners[i], corners[i+1]]))
    return verts,uvs,tris

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('obj',type=pathlib.Path)
    ap.add_argument('--texdir',type=pathlib.Path,required=True)
    ap.add_argument('--out-lua',type=pathlib.Path,required=True)
    ap.add_argument('--out-atlas',type=pathlib.Path,required=True)
    args=ap.parse_args()
    verts,uvs,tris=parse_obj(args.obj)
    rects,(AW,AH)=build_atlas(args.texdir,args.out_atlas)
    mins=[min(v[i] for v in verts) for i in range(3)]
    maxs=[max(v[i] for v in verts) for i in range(3)]
    width=maxs[0]-mins[0]; height=maxs[1]-mins[1]
    hip_y=mins[1]+height*0.60
    spine1_y=mins[1]+height*0.76
    shoulder_y=mins[1]+height*0.80
    neck_y=mins[1]+height*0.89
    head_y=mins[1]+height*0.94
    knee_y=mins[1]+height*0.26
    ankle_y=mins[1]+height*0.06
    shoulder_x=width*0.17
    hip_x=width*0.11
    # Zoro is a true horizontal T-pose. Derive the arm chain from the actual
    # side extent, not from vertical torso distances.
    arm_extent=max(abs(mins[0]),abs(maxs[0]))-shoulder_x
    upper_len=max(5.0,arm_extent*0.40)
    fore_len=max(5.0,arm_extent*0.35)
    hand_len=max(2.5,arm_extent-upper_len-fore_len)
    hand_y=shoulder_y
    thigh_len=max(4.0, hip_y-knee_y)
    shin_len=max(4.0, knee_y-ankle_y)
    toe_len=max(2.0, width*0.05)

    bone_names=['Root','Waist','Hips','Spine1','Neck','Head','LShoulder','LArm','LForeArm','LHand','RShoulder','RArm','RForeArm','RHand','LThigh','LLeg','LFoot','LToe','RThigh','RLeg','RFoot','RToe']
    parent=[0,1,2,2,4,5,4,7,8,9,4,11,12,13,3,15,16,17,3,19,20,21]  # 1-based parent bones, Root parent 0
    locals=[
        ident(),
        trans(0,hip_y,0),
        ident(),
        trans(0,spine1_y-hip_y,0),
        trans(0,neck_y-spine1_y,0),
        trans(0,head_y-neck_y,0),
        trans(shoulder_x, shoulder_y-spine1_y, 0),
        ident(),
        trans(upper_len,0,0),
        trans(fore_len,0,0),
        trans(-shoulder_x, shoulder_y-spine1_y, 0),
        ident(),
        trans(-upper_len,0,0),
        trans(-fore_len,0,0),
        trans(hip_x,0,0),
        trans(0,-thigh_len,0),
        trans(0,-shin_len,0),
        trans(0,-0.5,toe_len),
        trans(-hip_x,0,0),
        trans(0,-thigh_len,0),
        trans(0,-shin_len,0),
        trans(0,-0.5,toe_len),
    ]
    worlds=[]
    for i,m in enumerate(locals):
        pi=parent[i]-1
        if pi>=0: worlds.append(mul(worlds[pi],m))
        else: worlds.append(m)
    invworld=[inv_rigid(m) for m in worlds]

    anim={name:i+1 for i,name in enumerate(bone_names) if name in {'Waist','Hips','Spine1','Neck','Head','LShoulder','LArm','LForeArm','LHand','RShoulder','RArm','RForeArm','RHand','LThigh','LLeg','LFoot','LToe','RThigh','RLeg','RFoot','RToe'}}

    pos_first=[]; pos_count=[]; inf_bone=[]; inf_x=[]; inf_y=[]; inf_z=[]; inf_w=[]
    def add_influences(p, pairs):
        # pairs are (1-based bone id, weight). Exact bind reconstruction is
        # preserved because each local point is computed against that bone.
        sw=sum(w for _,w in pairs) or 1.0
        pos_first.append(len(inf_bone)+1); pos_count.append(len(pairs))
        for bi,w in pairs:
            lp=transform(invworld[bi-1],p)
            inf_bone.append(bi); inf_x.append(lp[0]); inf_y.append(lp[1]); inf_z.append(lp[2]); inf_w.append(w/sw)

    for p in verts:
        x,y,z=p; ax=abs(x)
        if y>=head_y-2:
            pairs=[(6,1.0)]
        elif ax>shoulder_x*0.72 and y>hip_y+4:
            left=x>0
            upper=8 if left else 12; fore=9 if left else 13; hand=10 if left else 14
            d=max(0.0,ax-shoulder_x)
            # Soft shoulder/elbow/wrist transitions prevent the rigid broken
            # seams the first auto-rig showed in-game.
            if d < 2.0:
                t=d/2.0; pairs=[(4,1.0-t),(upper,t)]
            elif d < upper_len-1.4:
                pairs=[(upper,1.0)]
            elif d < upper_len+1.4:
                t=(d-(upper_len-1.4))/2.8; pairs=[(upper,1.0-t),(fore,t)]
            elif d < upper_len+fore_len-1.2:
                pairs=[(fore,1.0)]
            elif d < upper_len+fore_len+1.2:
                t=(d-(upper_len+fore_len-1.2))/2.4; pairs=[(fore,1.0-t),(hand,t)]
            else:
                pairs=[(hand,1.0)]
        elif y<hip_y:
            left=x>0
            if y>knee_y: pairs=[(15 if left else 19,1.0)]
            elif y>ankle_y: pairs=[(16 if left else 20,1.0)]
            elif z>0.5: pairs=[(18 if left else 22,1.0)]
            else: pairs=[(17 if left else 21,1.0)]
        elif y>neck_y-3:
            pairs=[(5,1.0)]
        elif y>spine1_y:
            pairs=[(4,1.0)]
        else:
            pairs=[(3,1.0)]
        add_influences(p,pairs)

    corner_pos=[]; corner_u=[]; corner_v=[]; tri_centers=[]
    for mat,corners in tris:
        if mat not in rects: mat='tex3.png'
        u0,v0,uw,vh,dw,dh=rects[mat]
        tri=[]
        for vi,ti in corners:
            corner_pos.append(vi)
            p=verts[vi-1]; tri.append(p)
            u,v=uvs[ti-1] if ti>0 else (0.,0.)
            u=u-math.floor(u); v=v-math.floor(v)
            # OBJ V is bottom-up; flip into atlas row order
            v=1.0-v
            corner_u.append(u0+(0.5+u*(dw-1))/AW)
            corner_v.append(v0+(0.5+v*(dh-1))/AH)
        tri_centers.append(tuple(sum(p[d] for p in tri)/3 for d in range(3)))

    yaws={'down':0.,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}; orders={}
    for name,yaw in yaws.items():
        c,s=math.cos(yaw),math.sin(yaw); ds=[]
        for ti,(x,y,z) in enumerate(tri_centers): ds.append((x*s+z*c,ti+1))
        ds.sort(key=lambda q:q[0]); orders[name]=[ti for _,ti in ds]

    args.out_lua.parent.mkdir(parents=True,exist_ok=True)
    with args.out_lua.open('w') as out:
        out.write('-- GENERATED from Zoro.obj with simple auto-rig\nreturn {\n')
        out.write(f'  boneCount = {len(bone_names)},\n  positionCount = {len(verts)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(tri_centers)},\n')
        lua_strings('boneName',bone_names,out); lua_array('boneParent',parent,out)
        lua_array('boneLocal',[v for m in locals for v in m],out)
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
    print('Zoro bones',len(bone_names),'verts',len(verts),'tris',len(tris),'bounds',mins,maxs)

if __name__=='__main__':
    main()
