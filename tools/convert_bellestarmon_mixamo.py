#!/usr/bin/env python3
from __future__ import annotations
import argparse, struct, zlib, math, collections
from pathlib import Path
import numpy as np
from PIL import Image

FBX_TICKS=46186158000.0
S=np.array([[1,0,0,0],[0,0,1,0],[0,1,0,0],[0,0,0,1]],dtype=float)  # FBX Z-up -> runtime Y-up

class Node:
    __slots__=('name','props','children')
    def __init__(self,name,props,children): self.name=name; self.props=props; self.children=children

def _prop(data,off):
    t=chr(data[off]); off+=1
    if t=='Y': return struct.unpack_from('<h',data,off)[0],off+2
    if t=='C': return bool(data[off]),off+1
    if t=='I': return struct.unpack_from('<i',data,off)[0],off+4
    if t=='F': return struct.unpack_from('<f',data,off)[0],off+4
    if t=='D': return struct.unpack_from('<d',data,off)[0],off+8
    if t=='L': return struct.unpack_from('<q',data,off)[0],off+8
    if t in 'SR':
        n=struct.unpack_from('<I',data,off)[0]; off+=4; raw=data[off:off+n]; off+=n
        return (raw.decode('utf-8','replace') if t=='S' else raw),off
    if t in 'fdlib':
        n,enc,blen=struct.unpack_from('<III',data,off); off+=12; raw=data[off:off+blen]; off+=blen
        if enc==1: raw=zlib.decompress(raw)
        fm={'f':'f','d':'d','l':'q','i':'i','b':'b'}[t]
        return list(struct.unpack('<'+fm*n,raw)),off
    raise ValueError('unsupported FBX property '+t)

def _node(data,off,version):
    wide=version>=7500; hs=25 if wide else 13
    if wide: end,num,plen=struct.unpack_from('<QQQ',data,off); nl=data[off+24]
    else: end,num,plen=struct.unpack_from('<III',data,off); nl=data[off+12]
    if end==0: return None,off+hs
    off+=hs; name=data[off:off+nl].decode('utf-8','replace'); off+=nl; props=[]
    for _ in range(num): v,off=_prop(data,off); props.append(v)
    children=[]; null=25 if wide else 13
    while off < end-null:
        c,noff=_node(data,off,version)
        if c is None: off=noff; break
        children.append(c); off=noff
    return Node(name,props,children),end

def load_fbx(path):
    data=Path(path).read_bytes()
    if data[:21] != b'Kaydara FBX Binary  \x00': raise ValueError('expected binary FBX')
    version=struct.unpack_from('<I',data,23)[0]; off=27; roots=[]
    while off < len(data):
        n,noff=_node(data,off,version)
        if n is None: break
        roots.append(n); off=noff
    return roots

def clean_name(n):
    s=n.props[1] if len(n.props)>1 and isinstance(n.props[1],str) else n.name
    return s.split('\x00\x01')[0].replace('mixamorig:','')

def child(n,name):
    return next((c for c in n.children if c.name==name),None)

def rx_row(d):
    a=math.radians(d);c,s=math.cos(a),math.sin(a)
    return np.array([[1,0,0,0],[0,c,s,0],[0,-s,c,0],[0,0,0,1]],float)
def ry_row(d):
    a=math.radians(d);c,s=math.cos(a),math.sin(a)
    return np.array([[c,0,-s,0],[0,1,0,0],[s,0,c,0],[0,0,0,1]],float)
def rz_row(d):
    a=math.radians(d);c,s=math.cos(a),math.sin(a)
    return np.array([[c,s,0,0],[-s,c,0,0],[0,0,1,0],[0,0,0,1]],float)
def euler_row(x,y,z): return rx_row(x)@ry_row(y)@rz_row(z)

def lua_array(out,name,vals,per=12):
    out.write(f'  {name} = {{\n')
    for i in range(0,len(vals),per):
        seg=[]
        for v in vals[i:i+per]:
            if isinstance(v,(int,np.integer)): seg.append(str(int(v)))
            else:
                x=float(v)
                if abs(x)<5e-12:x=0.0
                seg.append(f'{x:.8g}')
        out.write('    '+', '.join(seg)+',\n')
    out.write('  },\n')

def lua_strings(out,name,vals,per=6):
    out.write(f'  {name} = {{\n')
    for i in range(0,len(vals),per): out.write('    '+', '.join('"'+v.replace('"','\\"')+'"' for v in vals[i:i+per])+',\n')
    out.write('  },\n')

def conn_maps(R):
    objs=R['Objects'].children
    byid={n.props[0]:n for n in objs if n.props and isinstance(n.props[0],int)}
    par=collections.defaultdict(list); chi=collections.defaultdict(list)
    for c in R['Connections'].children:
        typ,src,dst,*rest=c.props; prop=rest[0] if rest else None
        par[src].append((typ,dst,prop)); chi[dst].append((typ,src,prop))
    return objs,byid,par,chi

def extract_clip(path,names,base_locals_row,extra_bone_count,preserve_vertical):
    roots=load_fbx(path); R={r.name:r for r in roots}; objs,byid,par,chi=conn_maps(R)
    limb_by_name={clean_name(n):n for n in objs if n.name=='Model' and len(n.props)>2 and n.props[2]=='LimbNode'}
    rot={}; trans={}; times=None
    for name in names:
        bn=limb_by_name.get(name)
        if bn is None: continue
        bid=bn.props[0]
        for typ,nid,prop in chi[bid]:
            if nid not in byid or byid[nid].name!='AnimationCurveNode': continue
            axes={}; local_times=None
            for tt,cid,axis in chi[nid]:
                if cid in byid and byid[cid].name=='AnimationCurve':
                    cu=byid[cid]; kt=child(cu,'KeyTime').props[0]; kv=child(cu,'KeyValueFloat').props[0]
                    axes[axis[-1]]=(list(kt),list(map(float,kv))); local_times=kt
            if local_times and (times is None or len(local_times)>len(times)): times=list(local_times)
            if prop=='Lcl Rotation': rot[name]=axes
            elif prop=='Lcl Translation': trans[name]=axes
    count=len(times or [])
    if count<2: raise RuntimeError(f'animation clip not found in {path}')
    target=np.asarray(times,dtype=float)
    def sampled(axes,key):
        rec=axes.get(key)
        if not rec: return np.zeros(count,dtype=float)
        kt,kv=rec
        if len(kv)==1:return np.full(count,float(kv[0]),dtype=float)
        return np.interp(target,np.asarray(kt,dtype=float),np.asarray(kv,dtype=float))
    clip=[]
    for bi,name in enumerate(names):
        rc=rot.get(name,{}); tc=trans.get(name,{})
        xs=sampled(rc,'X'); ys=sampled(rc,'Y'); zs=sampled(rc,'Z')
        tx=sampled(tc,'X'); ty=sampled(tc,'Y'); tz=sampled(tc,'Z')
        for f in range(count):
            raw=euler_row(xs[f],ys[f],zs[f])
            rt=S@raw@S
            delta=rt.T
            if bi==0 and preserve_vertical:
                # FBX Z is vertical; after axis conversion it is runtime Y.
                dy=(tz[f]/100.0)-base_locals_row[bi][3,1]
                # Clamp authored pelvis bob so world movement remains authoritative.
                dy=max(-0.10,min(0.10,dy))
                delta=delta.copy(); delta[1,3]=dy
            clip.extend(delta.reshape(-1).tolist())
    ident=np.eye(4).reshape(-1).tolist()
    for _ in range(extra_bone_count):
        # Data is bone-major, so append a complete identity clip for each appended secondary-motion bone.
        clip.extend(ident*count)
    return clip,count,(times[-1]-times[0])/FBX_TICKS

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--base-fbx',type=Path,required=True)
    ap.add_argument('--idle-fbx',type=Path,required=True)
    ap.add_argument('--walk-fbx',type=Path,required=True)
    ap.add_argument('--run-fbx',type=Path,required=True)
    ap.add_argument('--jump-fbx',type=Path,required=True)
    ap.add_argument('--texture',type=Path,required=True)
    ap.add_argument('--out-lua',type=Path,required=True)
    ap.add_argument('--out-atlas',type=Path,required=True)
    a=ap.parse_args()

    roots=load_fbx(a.base_fbx); R={r.name:r for r in roots}; objs,byid,par,chi=conn_maps(R)
    geoms=[n for n in objs if n.name=='Geometry' and len(n.props)>2 and n.props[2]=='Mesh']
    if len(geoms)!=1: raise RuntimeError(f'expected one BelleStarmon mesh, found {len(geoms)}')
    models=[n for n in objs if n.name=='Model']; limbs=[n for n in models if len(n.props)>2 and n.props[2]=='LimbNode']
    clusters=[n for n in objs if n.name=='Deformer' and len(n.props)>2 and n.props[2]=='Cluster']

    cluster_info=[]; world_candidates=collections.defaultdict(list)
    for cl in clusters:
        bones=[s for t,s,p in chi[cl.props[0]] if s in byid and byid[s].name=='Model' and len(byid[s].props)>2 and byid[s].props[2]=='LimbNode']
        geoid=[d for t,d,p in par[cl.props[0]] if d in byid and byid[d].name=='Geometry']
        if not bones or not geoid: continue
        C=np.array(child(cl,'Transform').props[0],float).reshape(4,4)
        C[:3,:3]/=100.0; C[3,:3]/=100.0
        C=S@C@S
        W=np.linalg.inv(C)
        world_candidates[bones[0]].append(W)
        inds=child(cl,'Indexes').props[0]; weights=child(cl,'Weights').props[0]
        cluster_info.append((cl,geoid[0],bones[0],C,inds,weights))

    weighted_ids={b for _,_,b,_,_,_ in cluster_info}
    bones=[n for n in limbs if n.props[0] in weighted_ids]
    bindex={n.props[0]:i+1 for i,n in enumerate(bones)}
    names=[clean_name(n) for n in bones]
    world={bid:world_candidates[bid][0] for bid in weighted_ids}
    parents=[]; locals_row=[]
    for b in bones:
        bid=b.props[0]; pids=[d for t,d,p in par[bid] if d in byid and byid[d].name=='Model' and d in weighted_ids]
        pid=pids[0] if pids else None
        parents.append(bindex[pid] if pid else 0)
        L=world[bid]@np.linalg.inv(world[pid]) if pid else world[bid]
        locals_row.append(L)

    # Append dedicated secondary-motion deform bones safely after the imported Mixamo skeleton.
    # They are never inserted into the source hierarchy, so every imported animation/skin index stays stable.
    name_to_i={n:i+1 for i,n in enumerate(names)}
    chest_parent_name='Spine2' if 'Spine2' in name_to_i else ('Spine1' if 'Spine1' in name_to_i else 'Spine')
    chest_parent_i=name_to_i[chest_parent_name]
    chest_parent_world=world[bones[chest_parent_i-1].props[0]]
    breast_world=[]
    for x in (0.15,-0.15):
        W=chest_parent_world.copy(); W[3,:3]=[x,1.62,-0.15]; breast_world.append(W)
    for nm,W in zip(('LBreast','RBreast'),breast_world):
        names.append(nm); parents.append(chest_parent_i); locals_row.append(W@np.linalg.inv(chest_parent_world))
    breast_indices={'LBreast':len(names)-1,'RBreast':len(names)}
    breast_inv={'LBreast':np.linalg.inv(breast_world[0]),'RBreast':np.linalg.inv(breast_world[1])}


    g=geoms[0]; gid=g.props[0]
    verts_raw=np.array(child(g,'Vertices').props[0],float).reshape(-1,3)
    verts=np.column_stack((verts_raw[:,0],verts_raw[:,2],verts_raw[:,1]))
    cpweights=[[] for _ in range(len(verts))]
    for cl,_,bid,C,inds,weights in cluster_info:
        bi=bindex[bid]
        for vi,w in zip(inds,weights):
            if w>1e-7:
                p=np.array([*verts[vi],1.0])@C
                cpweights[vi].append((bi,float(w),p[:3]))

    pos_first=[];pos_count=[];inf_bone=[];inf_x=[];inf_y=[];inf_z=[];inf_w=[]
    for vi,pbind in enumerate(verts):
        src=cpweights[vi]
        if not src:
            src=[(1,1.0,(pbind[0],pbind[1],pbind[2]))]
        # Localized high/front chest and rear pelvis weighting. Both are appended secondary-motion
        # layers over the original Mixamo skin; the rest of the source weighting remains untouched.
        x,y,z=map(float,pbind)
        chest=(1.47<y<1.79 and abs(x)<0.34 and z<-0.025)
        extra=None; bw=0.0
        if chest:
            nm='LBreast' if x>=0 else 'RBreast'; cx=0.15 if x>=0 else -0.15
            dx=(x-cx)/0.20; dy=(y-1.62)/0.17; dz=(z+0.15)/0.23
            gval=math.exp(-(dx*dx+dy*dy+dz*dz)*1.7)
            bw=max(0.0,min(0.88,gval*0.92))
            if bw>0.06:
                lp=np.array([x,y,z,1.0])@breast_inv[nm]
                extra=(breast_indices[nm],bw,lp[:3])
        src.sort(key=lambda q:q[1],reverse=True)
        use=[]
        scale=1.0-bw if extra else 1.0
        for bi,w,lp in src[:4]: use.append((bi,w*scale,lp))
        if extra: use.append(extra)
        use.sort(key=lambda q:q[1],reverse=True); use=use[:4]
        sw=sum(q[1] for q in use) or 1.0
        pos_first.append(len(inf_bone)+1); pos_count.append(len(use))
        for bi,w,lp in use:
            inf_bone.append(int(bi)); inf_x.append(float(lp[0])); inf_y.append(float(lp[1])); inf_z.append(float(lp[2])); inf_w.append(float(w/sw))

    uvnode=child(g,'LayerElementUV'); uv=np.array(child(uvnode,'UV').props[0],float).reshape(-1,2); uvi=child(uvnode,'UVIndex').props[0]
    pvi=child(g,'PolygonVertexIndex').props[0]
    corner_pos=[];corner_u=[];corner_v=[];centers=[];poly=[];puv=[];ci=0
    for raw in pvi:
        vi=(-raw-1) if raw<0 else raw; poly.append(vi); puv.append(uvi[ci]); ci+=1
        if raw<0:
            for k in range(1,len(poly)-1):
                inds=[poly[0],poly[k],poly[k+1]]; uinds=[puv[0],puv[k],puv[k+1]]; pts=[]
                for vv,uu in zip(inds,uinds):
                    corner_pos.append(vv+1); pts.append(verts[vv])
                    U,V=map(float,uv[uu]); U=U%1.0; V=max(0.0,min(1.0,1.0-V))
                    corner_u.append(U);corner_v.append(V)
                centers.append(tuple(np.mean(np.asarray(pts),axis=0)))
            poly=[];puv=[]

    orders={}
    for key,yaw in {'down':0.,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}.items():
        c,s=math.cos(yaw),math.sin(yaw); ds=[(x*s+z*c,i+1) for i,(x,y,z) in enumerate(centers)]; ds.sort(); orders[key]=[i for _,i in ds]

    a.out_atlas.parent.mkdir(parents=True,exist_ok=True); Image.open(a.texture).convert('RGBA').save(a.out_atlas,optimize=True)

    base_names=names[:-2]
    idle,idle_n,idle_d=extract_clip(a.idle_fbx,base_names,locals_row[:-2],2,True)
    walk,walk_n,walk_d=extract_clip(a.walk_fbx,base_names,locals_row[:-2],2,True)
    run,run_n,run_d=extract_clip(a.run_fbx,base_names,locals_row[:-2],2,True)
    jump,jump_n,jump_d=extract_clip(a.jump_fbx,base_names,locals_row[:-2],2,False)

    name_to_i={n:i+1 for i,n in enumerate(names)}
    alias={
      'Hips':'Hips','Spine1':'Spine','Spine2':'Spine1','Spine3':'Spine2','Neck':'Neck','Head':'Head',
      'LShoulder':'LeftShoulder','LArm':'LeftArm','LForeArm':'LeftForeArm','LHand':'LeftHand',
      'RShoulder':'RightShoulder','RArm':'RightArm','RForeArm':'RightForeArm','RHand':'RightHand',
      'LThigh':'LeftUpLeg','LLeg':'LeftLeg','LFoot':'LeftFoot','LToe':'LeftToeBase',
      'RThigh':'RightUpLeg','RLeg':'RightLeg','RFoot':'RightFoot','RToe':'RightToeBase',
      'LBreast':'LBreast','RBreast':'RBreast',
    }
    anim={k:name_to_i[v] for k,v in alias.items() if v in name_to_i}
    mins=verts.min(axis=0).tolist(); maxs=verts.max(axis=0).tolist()

    a.out_lua.parent.mkdir(parents=True,exist_ok=True)
    with a.out_lua.open('w',encoding='utf-8',newline='\n') as out:
        out.write('-- GENERATED BelleStarmon analog locomotion build: idle + catwalk walk + fast run + jump, with appended chest secondary-motion bones.\nreturn {\n')
        out.write(f'  boneCount = {len(names)},\n  positionCount = {len(verts)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(centers)},\n')
        out.write(f'  idleFrameCount = {idle_n},\n  idleDuration = {idle_d:.9g},\n  walkFrameCount = {walk_n},\n  walkDuration = {walk_d:.9g},\n  runFrameCount = {run_n},\n  runDuration = {run_d:.9g},\n  jumpFrameCount = {jump_n},\n  jumpDuration = {jump_d:.9g},\n')
        lua_strings(out,'boneName',names); lua_array(out,'boneParent',parents,16); lua_array(out,'boneLocal',[x for L in locals_row for x in L.T.reshape(-1)],16)
        lua_array(out,'posFirst',pos_first,16);lua_array(out,'posCount',pos_count,16);lua_array(out,'infBone',inf_bone,16);lua_array(out,'infX',inf_x);lua_array(out,'infY',inf_y);lua_array(out,'infZ',inf_z);lua_array(out,'infW',inf_w)
        lua_array(out,'cornerPos',corner_pos,16);lua_array(out,'cornerU',corner_u);lua_array(out,'cornerV',corner_v)
        lua_array(out,'idleDelta',idle,16);lua_array(out,'walkDelta',walk,16);lua_array(out,'runDelta',run,16);lua_array(out,'jumpDelta',jump,16)
        out.write('  order = {\n')
        for k in ('down','left','up','right'):
            out.write(f'    {k} = {{\n');v=orders[k]
            for i in range(0,len(v),20):out.write('      '+', '.join(map(str,v[i:i+20]))+',\n')
            out.write('    },\n')
        out.write('  },\n  animBone = {\n')
        for k,v in anim.items(): out.write(f'    {k} = {v},\n')
        out.write('  },\n'); lua_array(out,'bounds',mins+maxs,6); out.write('}\n')

    chest_positions=sum(1 for i,(f,c) in enumerate(zip(pos_first,pos_count)) if any(inf_bone[j] in breast_indices.values() for j in range(f-1,f-1+c)))
    print('Fresh BelleStarmon Mixamo conversion complete')
    print('bones',len(names),'positions',len(verts),'influences',len(inf_bone),'triangles',len(centers))
    print('idle',idle_n,idle_d,'walk',walk_n,walk_d,'run',run_n,run_d,'jump',jump_n,jump_d,'chest positions',chest_positions)
    print('bounds',mins,maxs)

if __name__=='__main__': main()
