#!/usr/bin/env python3
from __future__ import annotations
import argparse, math, collections, importlib.util
from pathlib import Path
import numpy as np
from PIL import Image

_THIS=Path(__file__).resolve().parent
_spec=importlib.util.spec_from_file_location('_ash_base', _THIS/'convert_ash_fbx.py')
_base=importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_base)
load_fbx=_base.load_fbx; clean_name=_base.clean_name; child=_base.child
lua_array=_base.lua_array; lua_strings=_base.lua_strings; euler_row=_base.euler_row
FBX_TICKS=_base.FBX_TICKS

def conn_maps(R):
    objs=R['Objects'].children
    byid={n.props[0]:n for n in objs if n.props and isinstance(n.props[0],int)}
    par=collections.defaultdict(list); chi=collections.defaultdict(list)
    for c in R['Connections'].children:
        typ,src,dst,*rest=c.props; prop=rest[0] if rest else None
        par[src].append((typ,dst,prop)); chi[dst].append((typ,src,prop))
    return objs,byid,par,chi

def stable_wrap(v):
    v=float(v)
    # Preserve deliberate negative-tile wrapping while keeping exact seams stable.
    if 0.0 <= v <= 1.0: return v
    frac=v-math.floor(v)
    if frac<1e-6: frac=0.0
    elif frac>1.0-1e-6: frac=1.0
    return max(0.0,min(1.0,frac))

def extract_clip(path,names,base_locals_row,unit_scale,preserve_vertical,looping):
    roots=load_fbx(path); R={r.name:r for r in roots}; objs,byid,par,chi=conn_maps(R)
    limb_by_name={clean_name(n).replace('mixamorig:',''):n for n in objs if n.name=='Model' and len(n.props)>2 and n.props[2]=='LimbNode'}
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
        if len(kv)==1: return np.full(count,float(kv[0]),dtype=float)
        return np.interp(target,np.asarray(kt,dtype=float),np.asarray(kv,dtype=float))
    clip=[]
    for bi,name in enumerate(names):
        rc=rot.get(name,{}); tc=trans.get(name,{})
        xs=sampled(rc,'X'); ys=sampled(rc,'Y'); zs=sampled(rc,'Z'); tys=sampled(tc,'Y')
        for f in range(count):
            delta=euler_row(xs[f],ys[f],zs[f]).T
            if bi==0 and preserve_vertical and 'Y' in tc:
                delta=delta.copy()
                dy=(tys[f]/unit_scale)-base_locals_row[bi][3,1]
                # World locomotion owns translation; keep only authored pelvis bob.
                delta[1,3]=max(-0.12,min(0.12,dy))
            clip.extend(delta.reshape(-1).tolist())
    dur=(times[-1]-times[0])/FBX_TICKS
    return clip,count,dur

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--base-fbx',type=Path,required=True)
    ap.add_argument('--idle-fbx',type=Path,required=True)
    ap.add_argument('--run-fbx',type=Path,required=True)
    ap.add_argument('--jump-fbx',type=Path,required=True)
    ap.add_argument('--texture',type=Path,required=True)
    ap.add_argument('--out-lua',type=Path,required=True)
    ap.add_argument('--out-atlas',type=Path,required=True)
    a=ap.parse_args()

    roots=load_fbx(a.base_fbx); R={r.name:r for r in roots}; objs,byid,par,chi=conn_maps(R)
    geoms=[n for n in objs if n.name=='Geometry' and len(n.props)>2 and n.props[2]=='Mesh']
    if not geoms: raise RuntimeError('no mesh geometry in Aang FBX')
    limbs=[n for n in objs if n.name=='Model' and len(n.props)>2 and n.props[2]=='LimbNode']
    clusters=[n for n in objs if n.name=='Deformer' and len(n.props)>2 and n.props[2]=='Cluster']

    # Aang's FBXs are authored directly in metre-scale transforms (cluster scale ~= 1),
    # unlike some Mixamo exports whose cluster matrices carry a 100x scale. Detect it.
    cluster_info=[]; world_candidates=collections.defaultdict(list); scales=[]
    for cl in clusters:
        bones=[s for t,s,p in chi[cl.props[0]] if s in byid and byid[s].name=='Model' and len(byid[s].props)>2 and byid[s].props[2]=='LimbNode']
        geos=[d for t,d,p in par[cl.props[0]] if d in byid and byid[d].name=='Geometry']
        if not bones or not geos: continue
        Craw=np.array(child(cl,'Transform').props[0],float).reshape(4,4)
        scales.append(float(np.linalg.norm(Craw[0,:3])))
        unit=100.0 if float(np.linalg.norm(Craw[0,:3]))>10.0 else 1.0
        C=Craw.copy(); C[:3,:3]/=unit; C[3,:3]/=unit
        W=np.linalg.inv(C)
        world_candidates[bones[0]].append(W)
        inds=child(cl,'Indexes').props[0]; weights=child(cl,'Weights').props[0]
        cluster_info.append((geos[0],bones[0],C,inds,weights))
    unit_scale=100.0 if (np.median(scales) if scales else 1.0)>10.0 else 1.0

    weighted_ids={b for _,b,_,_,_ in cluster_info}
    bones=[n for n in limbs if n.props[0] in weighted_ids]
    bindex={n.props[0]:i+1 for i,n in enumerate(bones)}
    names=[clean_name(n).replace('mixamorig:','') for n in bones]
    world={bid:world_candidates[bid][0] for bid in weighted_ids}
    parents=[]; locals_row=[]
    for b in bones:
        bid=b.props[0]
        pids=[d for t,d,p in par[bid] if d in byid and byid[d].name=='Model' and d in weighted_ids]
        pid=pids[0] if pids else None
        parents.append(bindex[pid] if pid else 0)
        L=world[bid]@np.linalg.inv(world[pid]) if pid else world[bid]
        locals_row.append(L)

    by_geo=collections.defaultdict(list)
    for rec in cluster_info: by_geo[rec[0]].append(rec)
    pos_first=[];pos_count=[];inf_bone=[];inf_x=[];inf_y=[];inf_z=[];inf_w=[]
    geom_base={}; all_bind=[]
    for g in geoms:
        gid=g.props[0]; verts=np.array(child(g,'Vertices').props[0],float).reshape(-1,3); geom_base[gid]=len(all_bind)
        cpweights=[[] for _ in range(len(verts))]
        for _,bid,C,inds,weights in by_geo[gid]:
            bi=bindex[bid]
            for vi,w in zip(inds,weights):
                if w>1e-7:
                    lp=np.array([*verts[vi],1.0])@C
                    cpweights[vi].append((bi,float(w),lp[:3]))
        for vi,pbind in enumerate(verts):
            infs=cpweights[vi]
            if not infs:
                # Attach rare unweighted points to the root using its bind inverse.
                bi=1; C=np.linalg.inv(world[bones[0].props[0]])
                lp=np.array([*pbind,1.0])@C; infs=[(bi,1.0,lp[:3])]
            infs.sort(key=lambda q:q[1],reverse=True); infs=infs[:4]
            sw=sum(q[1] for q in infs) or 1.0
            pos_first.append(len(inf_bone)+1); pos_count.append(len(infs)); all_bind.append(tuple(pbind))
            for bi,w,lp in infs:
                inf_bone.append(int(bi)); inf_x.append(float(lp[0])); inf_y.append(float(lp[1])); inf_z.append(float(lp[2])); inf_w.append(float(w/sw))

    # Bake every source triangle into an isolated padded atlas cell. This handles the
    # source's negative-V convention and wrapped head UVs without cross-triangle bleed.
    src_img=np.asarray(Image.open(a.texture).convert('RGBA'),dtype=np.uint8)
    tri_records=[]; centers=[]
    for g in geoms:
        gid=g.props[0]; verts=np.array(child(g,'Vertices').props[0],float).reshape(-1,3)
        uvnode=child(g,'LayerElementUV'); uv=np.array(child(uvnode,'UV').props[0],float).reshape(-1,2); uvi=child(uvnode,'UVIndex').props[0]
        pvi=child(g,'PolygonVertexIndex').props[0]
        poly=[]; puv=[]; ci=0
        for raw in pvi:
            vi=(-raw-1) if raw<0 else raw; poly.append(vi); puv.append(uvi[ci]); ci+=1
            if raw<0:
                for k in range(1,len(poly)-1):
                    inds=[poly[0],poly[k],poly[k+1]]; uinds=[puv[0],puv[k],puv[k+1]]
                    tri_records.append((gid,inds,uinds,uv))
                    centers.append(tuple(np.mean(verts[inds],axis=0)))
                poly=[]; puv=[]

    CELL=18; cols=max(1,int(math.ceil(math.sqrt(len(tri_records))))); rows=int(math.ceil(len(tri_records)/cols))
    AW=cols*CELL; AH=rows*CELL; atlas=np.zeros((AH,AW,4),dtype=np.uint8)
    def bilinear(img,u,v):
        h,w=img.shape[:2]; u=max(0,min(1,float(u)));v=max(0,min(1,float(v)))
        x=u*(w-1);y=v*(h-1);x0=int(math.floor(x));y0=int(math.floor(y));x1=min(w-1,x0+1);y1=min(h-1,y0+1)
        fx=x-x0;fy=y-y0
        aa=img[y0,x0].astype(float)*(1-fx)+img[y0,x1].astype(float)*fx
        bb=img[y1,x0].astype(float)*(1-fx)+img[y1,x1].astype(float)*fx
        return np.clip(aa*(1-fy)+bb*fy,0,255).astype(np.uint8)
    corner_pos=[];corner_u=[];corner_v=[];inner0=1.5;inner1=CELL-2.5;span=inner1-inner0
    for ti,(gid,inds,uinds,uv) in enumerate(tri_records):
        col=ti%cols;row=ti//cols;ox=col*CELL;oy=row*CELL
        src=[]
        for uu in uinds:
            U,V=map(float,uv[uu]); src.append((stable_wrap(U),max(0.0,min(1.0,-V))))
        for yy in range(CELL):
            for xx in range(CELL):
                bx=(xx+0.5-inner0)/span;cy=(yy+0.5-inner0)/span;bx=max(0,bx);cy=max(0,cy)
                if bx+cy>1:
                    ss=bx+cy;bx/=ss;cy/=ss
                aa=max(0,1-bx-cy);su=aa*src[0][0]+bx*src[1][0]+cy*src[2][0];sv=aa*src[0][1]+bx*src[1][1]+cy*src[2][1]
                atlas[oy+yy,ox+xx]=bilinear(src_img,su,sv)
        dst=[(inner0,inner0),(inner1,inner0),(inner0,inner1)]
        for vv,(dx,dy) in zip(inds,dst):
            corner_pos.append(geom_base[gid]+vv+1);corner_u.append((ox+dx)/AW);corner_v.append((oy+dy)/AH)
    a.out_atlas.parent.mkdir(parents=True,exist_ok=True);Image.fromarray(atlas,'RGBA').save(a.out_atlas,optimize=True)

    orders={}
    for key,yaw in {'down':0.,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}.items():
        c,s=math.cos(yaw),math.sin(yaw);ds=[(x*s+z*c,i+1) for i,(x,y,z) in enumerate(centers)];ds.sort();orders[key]=[i for _,i in ds]

    idle,idle_n,idle_d=extract_clip(a.idle_fbx,names,locals_row,unit_scale,True,True)
    run,run_n,run_d=extract_clip(a.run_fbx,names,locals_row,unit_scale,True,True)
    jump,jump_n,jump_d=extract_clip(a.jump_fbx,names,locals_row,unit_scale,True,False)

    name_to_i={n:i+1 for i,n in enumerate(names)}
    alias={'Hips':'Hips','Spine1':'Spine','Spine2':'Spine1','Spine3':'Spine2','Neck':'Neck','Head':'Head','LShoulder':'LeftShoulder','LArm':'LeftArm','LForeArm':'LeftForeArm','LHand':'LeftHand','RShoulder':'RightShoulder','RArm':'RightArm','RForeArm':'RightForeArm','RHand':'RightHand','LThigh':'LeftUpLeg','LLeg':'LeftLeg','LFoot':'LeftFoot','LToe':'LeftToeBase','RThigh':'RightUpLeg','RLeg':'RightLeg','RFoot':'RightFoot','RToe':'RightToeBase'}
    anim={k:name_to_i[v] for k,v in alias.items() if v in name_to_i}
    bind=np.asarray(all_bind,float);mins=bind.min(axis=0).tolist();maxs=bind.max(axis=0).tolist()

    a.out_lua.parent.mkdir(parents=True,exist_ok=True)
    with a.out_lua.open('w',encoding='utf-8',newline='\n') as out:
        out.write('-- GENERATED fresh Aang Title Screen remake from supplied Mixamo FBXs; exact source skin + idle/run/jump.\nreturn {\n')
        out.write(f'  boneCount = {len(names)},\n  positionCount = {len(all_bind)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(centers)},\n')
        out.write(f'  idleFrameCount = {idle_n},\n  idleDuration = {idle_d:.9g},\n  runFrameCount = {run_n},\n  runDuration = {run_d:.9g},\n  jumpFrameCount = {jump_n},\n  jumpDuration = {jump_d:.9g},\n')
        lua_strings(out,'boneName',names);lua_array(out,'boneParent',parents,16);lua_array(out,'boneLocal',[x for L in locals_row for x in L.T.reshape(-1)],16)
        lua_array(out,'posFirst',pos_first,16);lua_array(out,'posCount',pos_count,16);lua_array(out,'infBone',inf_bone,16);lua_array(out,'infX',inf_x);lua_array(out,'infY',inf_y);lua_array(out,'infZ',inf_z);lua_array(out,'infW',inf_w)
        lua_array(out,'cornerPos',corner_pos,16);lua_array(out,'cornerU',corner_u);lua_array(out,'cornerV',corner_v)
        lua_array(out,'idleDelta',idle,16);lua_array(out,'runDelta',run,16);lua_array(out,'jumpDelta',jump,16)
        out.write('  order = {\n')
        for k in ('down','left','up','right'):
            out.write(f'    {k} = {{\n');v=orders[k]
            for i in range(0,len(v),20):out.write('      '+', '.join(map(str,v[i:i+20]))+',\n')
            out.write('    },\n')
        out.write('  },\n  animBone = {\n')
        for k,v in anim.items():out.write(f'    {k} = {v},\n')
        out.write('  },\n');lua_array(out,'bounds',mins+maxs,6);out.write('}\n')
    print('Aang Mixamo conversion complete')
    print('geometries',len(geoms),'bones',len(names),'positions',len(all_bind),'influences',len(inf_bone),'triangles',len(centers),'unit_scale',unit_scale)
    print('idle',idle_n,idle_d,'run',run_n,run_d,'jump',jump_n,jump_d,'bounds',mins,maxs,'atlas',AW,AH)

if __name__=='__main__': main()
