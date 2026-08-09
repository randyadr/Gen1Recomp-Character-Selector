#!/usr/bin/env python3
from __future__ import annotations
import argparse, math, pathlib, json
import numpy as np
from PIL import Image


def ident(): return [1.,0,0,0, 0,1.,0,0, 0,0,1.,0, 0,0,0,1.]
def mul(a,b):
    o=[0.]*16
    for r in range(4):
        for c in range(4):
            o[r*4+c]=sum(a[r*4+k]*b[k*4+c] for k in range(4))
    return o

def trans(x,y,z):
    m=ident(); m[3]=x; m[7]=y; m[11]=z; return m

def inv_rigid(m):
    # rotations are identity in this generated bind skeleton, but keep generic rigid inverse.
    rt=[m[0],m[4],m[8], m[1],m[5],m[9], m[2],m[6],m[10]]
    tx,ty,tz=m[3],m[7],m[11]
    return [rt[0],rt[1],rt[2],-(rt[0]*tx+rt[1]*ty+rt[2]*tz),
            rt[3],rt[4],rt[5],-(rt[3]*tx+rt[4]*ty+rt[5]*tz),
            rt[6],rt[7],rt[8],-(rt[6]*tx+rt[7]*ty+rt[8]*tz),
            0,0,0,1]

def transform(m,p):
    x,y,z=p
    return (m[0]*x+m[1]*y+m[2]*z+m[3],m[4]*x+m[5]*y+m[6]*z+m[7],m[8]*x+m[9]*y+m[10]*z+m[11])

def lua_num(x):
    if isinstance(x,int): return str(x)
    if abs(x)<5e-10: x=0.
    return f'{x:.8g}'

def lua_array(name, vals, out, per=16):
    out.write(f'  {name} = {{\n')
    for i in range(0,len(vals),per): out.write('    '+', '.join(lua_num(v) for v in vals[i:i+per])+',\n')
    out.write('  },\n')

def lua_strings(name, vals, out, per=8):
    out.write(f'  {name} = {{\n')
    for i in range(0,len(vals),per): out.write('    '+', '.join(json.dumps(v) for v in vals[i:i+per])+',\n')
    out.write('  },\n')


def parse_obj(path):
    verts=[]; uvs=[]; faces=[]; current_mat=None
    for raw in path.read_text(errors='replace').splitlines():
        line=raw.strip()
        if not line or line.startswith('#'): continue
        if line.startswith('v '):
            p=line.split(); verts.append((float(p[1]),float(p[2]),float(p[3])))
        elif line.startswith('vt '):
            p=line.split(); uvs.append((float(p[1]),float(p[2])))
        elif line.startswith('usemtl '): current_mat=line.split(None,1)[1].strip()
        elif line.startswith('f '):
            cs=[]
            for tok in line.split()[1:]:
                ps=tok.split('/'); vi=int(ps[0]); ti=int(ps[1]) if len(ps)>1 and ps[1] else 0
                if vi<0: vi=len(verts)+1+vi
                if ti<0: ti=len(uvs)+1+ti
                cs.append((vi,ti))
            for i in range(1,len(cs)-1): faces.append((current_mat,[cs[0],cs[i],cs[i+1]]))
    return verts,uvs,faces


def bleed_alpha(im, radius=8):
    arr=np.array(im, dtype=np.uint8)
    rgb=arr[:,:,:3].copy()
    alpha=arr[:,:,3].copy()
    h,w=alpha.shape
    for _ in range(max(1,radius)):
        mask=(alpha==0)
        if not mask.any():
            break
        filled=(alpha>0)
        newmask=np.zeros_like(mask)
        newrgb=rgb.copy()
        # 4-neighbor pull from nearest already-opaque texels. This removes the
        # black fringe from transparent padding when the atlas is minified.
        for dy,dx in ((-1,0),(1,0),(0,-1),(0,1)):
            src_fill=np.zeros_like(filled)
            src_rgb=np.zeros_like(rgb)
            if dy==-1:
                src_fill[1:,:]=filled[:-1,:]; src_rgb[1:,:,:]=rgb[:-1,:,:]
            elif dy==1:
                src_fill[:-1,:]=filled[1:,:]; src_rgb[:-1,:,:]=rgb[1:,:,:]
            elif dx==-1:
                src_fill[:,1:]=filled[:,:-1]; src_rgb[:,1:,:]=rgb[:,:-1,:]
            elif dx==1:
                src_fill[:,:-1]=filled[:,1:]; src_rgb[:,:-1,:]=rgb[:,1:,:]
            take=mask & src_fill & (~newmask)
            newrgb[take]=src_rgb[take]
            newmask[take]=True
        if not newmask.any():
            break
        rgb[newmask]=newrgb[newmask]
        # Keep these pixels transparent in the saved PNG; only their hidden RGB matters.
        alpha[newmask]=0
    out=np.dstack([rgb, arr[:,:,3]])
    return Image.fromarray(out, 'RGBA')

def build_atlas(srcdir,outpath):
    # Keep both original diffuse maps in one runtime atlas, but first bleed
    # color into transparent padding so filtered sampling does not darken the
    # sleeves/hands with black fringes at runtime.
    body=bleed_alpha(Image.open(srcdir/'ShrekBody_Col.png').convert('RGBA'), radius=10)
    head=bleed_alpha(Image.open(srcdir/'ShrekHead_Col.png').convert('RGBA'), radius=10)
    pad=12; W=max(body.width,head.width)+pad*2; H=body.height+head.height+pad*3
    atlas=Image.new('RGBA',(W,H),(0,0,0,0))
    body_xy=(pad,pad); head_xy=(pad,pad*2+body.height)
    atlas.paste(body,body_xy); atlas.paste(head,head_xy)
    outpath.parent.mkdir(parents=True,exist_ok=True); atlas.save(outpath,optimize=True)
    def rect(xy,im): return (xy[0]/W,xy[1]/H,im.width/W,im.height/H,im.width,im.height)
    return {'ShrekBody_Col':rect(body_xy,body),'ShrekHead_Col':rect(head_xy,head)},(W,H)


def dist_point_seg(p,a,b):
    ab=tuple(b[i]-a[i] for i in range(3)); ap=tuple(p[i]-a[i] for i in range(3))
    den=sum(x*x for x in ab)
    t=0 if den<1e-12 else max(0,min(1,sum(ap[i]*ab[i] for i in range(3))/den))
    q=tuple(a[i]+ab[i]*t for i in range(3))
    return math.dist(p,q),t


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('obj',type=pathlib.Path); ap.add_argument('--textures',type=pathlib.Path,required=True); ap.add_argument('--out-lua',type=pathlib.Path,required=True); ap.add_argument('--out-atlas',type=pathlib.Path,required=True); args=ap.parse_args()
    verts,uvs,faces=parse_obj(args.obj); rects,(AW,AH)=build_atlas(args.textures,args.out_atlas)
    visible=[(m,c) for m,c in faces if m in rects]
    ids=sorted(set(vi for _,cs in visible for vi,_ in cs)); remap={vi:i+1 for i,vi in enumerate(ids)}; actual=[verts[i-1] for i in ids]

    # Shrek Forever After's extracted OBJ is already in a relaxed arms-down-ish pose.
    # Build a compact humanoid bind skeleton around that pose instead of forcing a T-pose.
    P={
      'Root':(0.0,0.02,0.0),'Waist':(0.0,0.80,0.0),'Hips':(0.0,0.78,0.0),
      'Spine1':(0.0,1.02,0.0),'Spine2':(0.0,1.24,0.0),'Spine3':(0.0,1.43,0.0),'Neck':(0.0,1.58,0.0),'Head':(0.0,1.75,0.0),
      'LShoulder':(0.34,1.43,0.0),'LArm':(0.45,1.35,0.0),'LForeArm':(0.78,1.12,0.0),'LHand':(1.08,0.88,0.0),
      'RShoulder':(-0.34,1.43,0.0),'RArm':(-0.45,1.35,0.0),'RForeArm':(-0.78,1.12,0.0),'RHand':(-1.08,0.88,0.0),
      'LThigh':(0.19,0.76,0.0),'LLeg':(0.19,0.43,0.0),'LFoot':(0.19,0.13,0.0),'LToe':(0.19,0.05,0.17),
      'RThigh':(-0.19,0.76,0.0),'RLeg':(-0.19,0.43,0.0),'RFoot':(-0.19,0.13,0.0),'RToe':(-0.19,0.05,0.17),
    }
    names=['Root','Waist','Hips','Spine1','Spine2','Spine3','Neck','Head','LShoulder','LArm','LForeArm','LHand','RShoulder','RArm','RForeArm','RHand','LThigh','LLeg','LFoot','LToe','RThigh','RLeg','RFoot','RToe']
    parent={'Root':None,'Waist':'Root','Hips':'Waist','Spine1':'Hips','Spine2':'Spine1','Spine3':'Spine2','Neck':'Spine3','Head':'Neck',
      'LShoulder':'Spine3','LArm':'LShoulder','LForeArm':'LArm','LHand':'LForeArm','RShoulder':'Spine3','RArm':'RShoulder','RForeArm':'RArm','RHand':'RForeArm',
      'LThigh':'Hips','LLeg':'LThigh','LFoot':'LLeg','LToe':'LFoot','RThigh':'Hips','RLeg':'RThigh','RFoot':'RLeg','RToe':'RFoot'}
    idx={n:i for i,n in enumerate(names)}; parents=[]; locals=[]; worlds=[]
    for n in names:
        pn=parent[n]; parents.append(idx[pn]+1 if pn else 0)
        if pn:
            a,b=P[pn],P[n]; lm=trans(b[0]-a[0],b[1]-a[1],b[2]-a[2]); worlds.append(mul(worlds[idx[pn]],lm)); locals.append(lm)
        else:
            lm=trans(*P[n]); worlds.append(lm); locals.append(lm)
    inv=[inv_rigid(m) for m in worlds]

    arm_segments={'LArm':('LArm','LForeArm'),'LForeArm':('LForeArm','LHand'),'RArm':('RArm','RForeArm'),'RForeArm':('RForeArm','RHand')}
    leg_segments={'LThigh':('LThigh','LLeg'),'LLeg':('LLeg','LFoot'),'LFoot':('LFoot','LToe'),'RThigh':('RThigh','RLeg'),'RLeg':('RLeg','RFoot'),'RFoot':('RFoot','RToe')}
    pos_first=[]; pos_count=[]; inf_bone=[]; inf_x=[]; inf_y=[]; inf_z=[]; inf_w=[]

    for p in actual:
        x,y,z=p; ax=abs(x); candidates=[]
        # Rig the COMPLETE arm, including the inner sleeve/shoulder vertices.  The old
        # x>0.43 cutoff left much of each upper arm attached to the torso, so the hands
        # could move while the sleeves looked rigid.  Find the nearest segment of a
        # shoulder->upper-arm->forearm->hand polyline and smoothly blend the two joints
        # adjacent to that segment.
        side='L' if x>0 else 'R'
        arm_chain=[side+'Shoulder',side+'Arm',side+'ForeArm',side+'Hand']
        arm_hits=[]
        for si in range(len(arm_chain)-1):
            a_name,b_name=arm_chain[si],arm_chain[si+1]
            d,t=dist_point_seg(p,P[a_name],P[b_name])
            arm_hits.append((d,si,t))
        arm_hits.sort(key=lambda q:q[0])
        arm_d,arm_si,arm_t=arm_hits[0]
        # Spatial gate follows Shrek's actual diagonal arms while excluding most vest/torso
        # vertices near the centerline.  The distance gate also includes sleeve thickness
        # and the large hands from the source mesh.
        is_arm=(ax>0.26 and 0.62<y<1.58 and arm_d<0.34)
        if is_arm:
            a_name=arm_chain[arm_si]; b_name=arm_chain[arm_si+1]
            # Smoothstep keeps the deformation seam soft at shoulder/elbow/wrist.
            t=max(0.0,min(1.0,arm_t)); t=t*t*(3-2*t)
            wa=1.0-t; wb=t
            if wa<0.08: candidates=[(b_name,1.0)]
            elif wb<0.08: candidates=[(a_name,1.0)]
            else: candidates=[(a_name,wa),(b_name,wb)]
            # The outer palm/finger cluster should follow the hand rigidly.
            if ax>1.02 and y<1.04: candidates=[(side+'Hand',1.0)]
        elif y<0.82 and ax<0.58:
            side='L' if x>=0 else 'R'; opts=[side+'Thigh',side+'Leg',side+'Foot']; dd=[]
            for bn in opts:
                a,b=leg_segments[bn]; d,_=dist_point_seg(p,P[a],P[b]); dd.append((d,bn))
            dd.sort(); use=dd[:2]; ws=[1/(d+0.05) for d,_ in use]; s=sum(ws); candidates=[(bn,w/s) for w,(d,bn) in zip(ws,use)]
            if y<0.12: candidates=[(side+'Foot',0.70),(side+'Toe',0.30)]
        elif y>1.60:
            candidates=[('Head',1.0)]
        elif y>1.48:
            candidates=[('Neck',0.35),('Head',0.65)]
        elif y>1.30:
            candidates=[('Spine3',0.70),('Neck',0.30)]
        elif y>1.10:
            candidates=[('Spine2',0.75),('Spine3',0.25)]
        elif y>0.90:
            candidates=[('Spine1',0.75),('Spine2',0.25)]
        else:
            candidates=[('Hips',1.0)]
        pos_first.append(len(inf_bone)+1); pos_count.append(len(candidates))
        for bn,w in candidates:
            bi=idx[bn]; lp=transform(inv[bi],p)
            inf_bone.append(bi+1); inf_x.append(lp[0]); inf_y.append(lp[1]); inf_z.append(lp[2]); inf_w.append(w)

    corner_pos=[]; corner_u=[]; corner_v=[]; centers=[]
    for mat,cs in visible:
        u0,v0,uw,vh,dw,dh=rects[mat]; pts=[]
        for vi,ti in cs:
            corner_pos.append(remap[vi]); pts.append(verts[vi-1]); u,v=uvs[ti-1] if ti else (0,0)
            # This extracted OBJ stores diffuse V in the range -1..0.
            # The correct conversion is V = -v. Using (1 + v) vertically
            # flipped every material island, which mapped Shrek's clothes and
            # skin onto the wrong parts of the diffuse textures.
            u=max(0,min(1,u))
            v=max(0,min(1,-v))
            corner_u.append(u0+(0.5+u*(dw-1))/AW); corner_v.append(v0+(0.5+v*(dh-1))/AH)
        centers.append(tuple(sum(q[d] for q in pts)/3 for d in range(3)))

    yaws={'down':0.,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}; orders={}
    for k,yaw in yaws.items():
        c,s=math.cos(yaw),math.sin(yaw); ds=[(x*s+z*c,i+1) for i,(x,y,z) in enumerate(centers)]; ds.sort(key=lambda q:q[0]); orders[k]=[i for _,i in ds]
    mins=[min(p[d] for p in actual) for d in range(3)]; maxs=[max(p[d] for p in actual) for d in range(3)]
    anim={n:idx[n]+1 for n in names if n!='Root'}
    args.out_lua.parent.mkdir(parents=True,exist_ok=True)
    with args.out_lua.open('w') as out:
        out.write('-- GENERATED from Shrek Forever After shrek.obj with a procedural humanoid skin rig\nreturn {\n')
        out.write(f'  boneCount = {len(names)},\n  positionCount = {len(actual)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(centers)},\n')
        lua_strings('boneName',names,out); lua_array('boneParent',parents,out); lua_array('boneLocal',[v for m in locals for v in m],out)
        lua_array('posFirst',pos_first,out); lua_array('posCount',pos_count,out); lua_array('infBone',inf_bone,out); lua_array('infX',inf_x,out); lua_array('infY',inf_y,out); lua_array('infZ',inf_z,out); lua_array('infW',inf_w,out)
        lua_array('cornerPos',corner_pos,out); lua_array('cornerU',corner_u,out); lua_array('cornerV',corner_v,out)
        out.write('  order = {\n')
        for k in ('down','left','up','right'):
            out.write(f'    {k} = {{\n'); vals=orders[k]
            for i in range(0,len(vals),20): out.write('      '+', '.join(map(str,vals[i:i+20]))+',\n')
            out.write('    },\n')
        out.write('  },\n  animBone = {\n')
        for n,i in anim.items(): out.write(f'    {n} = {i},\n')
        out.write('  },\n'); lua_array('bounds',mins+maxs,out,6); out.write('}\n')
    print('Shrek bones',len(names),'positions',len(actual),'tris',len(centers),'bounds',mins,maxs)

if __name__=='__main__': main()
