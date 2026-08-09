#!/usr/bin/env python3
from __future__ import annotations
import argparse, math, collections, importlib.util
from pathlib import Path
import numpy as np
from PIL import Image

_THIS=Path(__file__).resolve().parent
_spec=importlib.util.spec_from_file_location('_fbx_base', _THIS/'convert_ash_fbx.py')
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

def stable_uv(v: float) -> float:
    v=float(v)
    if -1e-5 <= v <= 1.00001:
        return max(0.0,min(1.0,v))
    f=v-math.floor(v)
    if f<1e-5: f=0.0
    elif f>0.99999: f=1.0
    return max(0.0,min(1.0,f))

def extract_clip(path,names,unit_scale):
    roots=load_fbx(path); R={r.name:r for r in roots}; objs,byid,par,chi=conn_maps(R)
    limb_by_name={clean_name(n).replace('mixamorig:',''):n for n in objs if n.name=='Model' and len(n.props)>2 and n.props[2]=='LimbNode'}
    rot={}; times=None
    for name in names:
        bn=limb_by_name.get(name)
        if bn is None: continue
        bid=bn.props[0]
        for typ,nid,prop in chi[bid]:
            if nid not in byid or byid[nid].name!='AnimationCurveNode' or prop!='Lcl Rotation': continue
            axes={}; local_times=None
            for tt,cid,axis in chi[nid]:
                if cid in byid and byid[cid].name=='AnimationCurve':
                    cu=byid[cid]; kt=list(child(cu,'KeyTime').props[0]); kv=list(map(float,child(cu,'KeyValueFloat').props[0]))
                    axes[axis[-1]]=(kt,kv); local_times=kt
            if local_times and (times is None or len(local_times)>len(times)): times=list(local_times)
            rot[name]=axes
    if not times or len(times)<2: raise RuntimeError(f'no usable animation in {path}')
    target=np.asarray(times,dtype=float); count=len(target)
    def sampled(axes,key):
        rec=axes.get(key)
        if not rec: return np.zeros(count,dtype=float)
        kt,kv=rec
        if len(kv)==1: return np.full(count,float(kv[0]),dtype=float)
        return np.interp(target,np.asarray(kt,dtype=float),np.asarray(kv,dtype=float))
    out=[]
    for name in names:
        rc=rot.get(name,{})
        xs=sampled(rc,'X'); ys=sampled(rc,'Y'); zs=sampled(rc,'Z')
        for f in range(count):
            # Gen1Recomp owns world movement and jump lift. Keep bind translations
            # untouched and apply only the authored Mixamo rotations.
            out.extend(euler_row(xs[f],ys[f],zs[f]).T.reshape(-1).tolist())
    duration=(target[-1]-target[0])/FBX_TICKS
    return out,count,duration

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--base-fbx',type=Path,required=True)
    ap.add_argument('--idle-fbx',type=Path,required=True)
    ap.add_argument('--run-fbx',type=Path,required=True)
    ap.add_argument('--jump-fbx',type=Path,required=True)
    ap.add_argument('--textures-dir',type=Path,required=True)
    ap.add_argument('--out-lua',type=Path,required=True)
    ap.add_argument('--out-atlas',type=Path,required=True)
    a=ap.parse_args()

    roots=load_fbx(a.base_fbx); R={r.name:r for r in roots}; objs,byid,par,chi=conn_maps(R)
    geoms=[n for n in objs if n.name=='Geometry' and len(n.props)>2 and n.props[2]=='Mesh']
    if not geoms: raise RuntimeError('no Zoro mesh geometry')
    limbs=[n for n in objs if n.name=='Model' and len(n.props)>2 and n.props[2]=='LimbNode']
    clusters=[n for n in objs if n.name=='Deformer' and len(n.props)>2 and n.props[2]=='Cluster']

    # Resolve Cluster -> Skin -> Geometry and normalize the 100x Mixamo bind scale.
    world_candidates=collections.defaultdict(list); by_geo=collections.defaultdict(list); scales=[]
    for cl in clusters:
        bone_ids=[s for t,s,p in chi[cl.props[0]] if s in byid and byid[s].name=='Model' and len(byid[s].props)>2 and byid[s].props[2]=='LimbNode']
        skin_ids=[d for t,d,p in par[cl.props[0]] if d in byid and byid[d].name=='Deformer' and len(byid[d].props)>2 and byid[d].props[2]=='Skin']
        geo_ids=[]
        for sid in skin_ids: geo_ids += [d for t,d,p in par[sid] if d in byid and byid[d].name=='Geometry']
        if not bone_ids or not geo_ids: continue
        Craw=np.array(child(cl,'Transform').props[0],float).reshape(4,4)
        scales.append(float(np.linalg.norm(Craw[0,:3])))
        unit=100.0 if float(np.linalg.norm(Craw[0,:3]))>10.0 else 1.0
        C=Craw.copy(); C[:3,:3]/=unit; C[3,:3]/=unit
        bid=bone_ids[0]; gid=geo_ids[0]
        world_candidates[bid].append(np.linalg.inv(C))
        inds=child(cl,'Indexes').props[0]; weights=child(cl,'Weights').props[0]
        by_geo[gid].append((bid,C,inds,weights))
    unit_scale=100.0 if (np.median(scales) if scales else 1.0)>10.0 else 1.0

    weighted_ids=set(world_candidates)
    bones=[n for n in limbs if n.props[0] in weighted_ids]
    bindex={n.props[0]:i+1 for i,n in enumerate(bones)}
    names=[clean_name(n).replace('mixamorig:','') for n in bones]
    world={bid:world_candidates[bid][0] for bid in weighted_ids}
    parents=[]; locals_row=[]
    for b in bones:
        bid=b.props[0]
        pids=[d for t,d,p in par[bid] if d in bindex]
        pid=pids[0] if pids else None
        parents.append(bindex[pid] if pid else 0)
        locals_row.append(world[bid]@np.linalg.inv(world[pid]) if pid else world[bid])

    geom_base={}; combined=[]
    pos_first=[];pos_count=[];inf_bone=[];inf_x=[];inf_y=[];inf_z=[];inf_w=[]
    root_id=bones[0].props[0]; root_inv=np.linalg.inv(world[root_id])
    for g in geoms:
        gid=g.props[0]; verts=np.array(child(g,'Vertices').props[0],float).reshape(-1,3); geom_base[gid]=len(combined)
        cpweights=[[] for _ in range(len(verts))]
        for bid,C,inds,weights in by_geo[gid]:
            if bid not in bindex: continue
            bi=bindex[bid]
            for vi,w in zip(inds,weights):
                if w>1e-7:
                    lp=np.array([*verts[vi],1.0])@C
                    cpweights[vi].append((bi,float(w),lp[:3]))
        for vi,pbind in enumerate(verts):
            infs=cpweights[vi]
            if not infs:
                lp=np.array([*pbind,1.0])@root_inv; infs=[(1,1.0,lp[:3])]
            infs.sort(key=lambda q:q[1],reverse=True); infs=infs[:4]
            sw=sum(q[1] for q in infs) or 1.0
            pos_first.append(len(inf_bone)+1);pos_count.append(len(infs));combined.append(tuple(pbind))
            for bi,w,lp in infs:
                inf_bone.append(int(bi));inf_x.append(float(lp[0]));inf_y.append(float(lp[1]));inf_z.append(float(lp[2]));inf_w.append(float(w/sw))

    tex_files=['face1.png','tex1.png','tex2.png','tex3.png','tex4.png']
    textures={f:np.asarray(Image.open(a.textures_dir/f).convert('RGBA'),dtype=np.uint8) for f in tex_files}

    # Bake each triangle into a padded cell. This preserves the PS2 UV/material
    # layout while eliminating atlas bleed in Dramatic Shape.
    tri_records=[]; centers=[]; material_counts=collections.Counter()
    for g in geoms:
        gid=g.props[0]; verts=np.array(child(g,'Vertices').props[0],float).reshape(-1,3)
        uvnode=child(g,'LayerElementUV'); uv=np.array(child(uvnode,'UV').props[0],float).reshape(-1,2); uvi=child(uvnode,'UVIndex').props[0]
        pvi=child(g,'PolygonVertexIndex').props[0]
        matnode=child(g,'LayerElementMaterial'); mats=list(map(int,child(matnode,'Materials').props[0])) if matnode else []
        model_ids=[d for t,d,p in par[gid] if d in byid and byid[d].name=='Model']
        model=byid[model_ids[0]] if model_ids else None
        mat_nodes=[byid[s] for t,s,p in chi[model.props[0]] if s in byid and byid[s].name=='Material'] if model else []
        mat_names=[clean_name(n) for n in mat_nodes]
        poly=[];puv=[];ci=0;pidx=0
        for raw in pvi:
            vi=(-raw-1) if raw<0 else raw;poly.append(vi);puv.append(uvi[ci]);ci+=1
            if raw<0:
                mi=mats[pidx] if pidx<len(mats) else 0;pidx+=1
                mat_name=mat_names[mi] if 0<=mi<len(mat_names) else (mat_names[0] if mat_names else 'tex3.png')
                tex_name=mat_name if mat_name in textures else 'tex3.png'; material_counts[tex_name]+=1
                for k in range(1,len(poly)-1):
                    inds=[poly[0],poly[k],poly[k+1]];uinds=[puv[0],puv[k],puv[k+1]]
                    tri_records.append((gid,inds,uinds,uv,tex_name));centers.append(tuple(np.mean(verts[inds],axis=0)))
                poly=[];puv=[]

    CELL=18;cols=max(1,int(math.ceil(math.sqrt(len(tri_records)))));rows=int(math.ceil(len(tri_records)/cols));AW=cols*CELL;AH=rows*CELL
    atlas=np.zeros((AH,AW,4),dtype=np.uint8)
    def bilinear(img,u,v):
        h,w=img.shape[:2];u=max(0,min(1,float(u)));v=max(0,min(1,float(v)))
        x=u*(w-1);y=v*(h-1);x0=int(math.floor(x));y0=int(math.floor(y));x1=min(w-1,x0+1);y1=min(h-1,y0+1);fx=x-x0;fy=y-y0
        aa=img[y0,x0].astype(float)*(1-fx)+img[y0,x1].astype(float)*fx;bb=img[y1,x0].astype(float)*(1-fx)+img[y1,x1].astype(float)*fx
        return np.clip(aa*(1-fy)+bb*fy,0,255).astype(np.uint8)
    corner_pos=[];corner_u=[];corner_v=[];inner0=1.5;inner1=CELL-2.5;span=inner1-inner0
    for ti,(gid,inds,uinds,uv,tex_name) in enumerate(tri_records):
        tex=textures[tex_name];col=ti%cols;row=ti//cols;ox=col*CELL;oy=row*CELL
        src=[]
        for ui in uinds:
            U,V=map(float,uv[ui]);src.append((stable_uv(U),max(0.0,min(1.0,1.0-stable_uv(V)))))
        for yy in range(CELL):
            for xx in range(CELL):
                bx=(xx+0.5-inner0)/span;cy=(yy+0.5-inner0)/span;bx=max(0,bx);cy=max(0,cy)
                if bx+cy>1: ss=bx+cy;bx/=ss;cy/=ss
                aa=max(0,1-bx-cy);su=aa*src[0][0]+bx*src[1][0]+cy*src[2][0];sv=aa*src[0][1]+bx*src[1][1]+cy*src[2][1]
                atlas[oy+yy,ox+xx]=bilinear(tex,su,sv)
        dst=[(inner0,inner0),(inner1,inner0),(inner0,inner1)]
        for vi,(dx,dy) in zip(inds,dst):
            corner_pos.append(geom_base[gid]+vi+1);corner_u.append((ox+dx)/AW);corner_v.append((oy+dy)/AH)
    a.out_atlas.parent.mkdir(parents=True,exist_ok=True);Image.fromarray(atlas,'RGBA').save(a.out_atlas,optimize=True)

    # Source mesh is Z-up; runtime converts skinned points to engine Y-up.
    centers_yup=[(x,z,-y) for x,y,z in centers]
    orders={}
    for key,yaw in {'down':0.,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}.items():
        c,s=math.cos(yaw),math.sin(yaw);ds=[(x*s+z*c,i+1) for i,(x,y,z) in enumerate(centers_yup)];ds.sort();orders[key]=[i for _,i in ds]

    idle,idle_n,idle_d=extract_clip(a.idle_fbx,names,unit_scale)
    run,run_n,run_d=extract_clip(a.run_fbx,names,unit_scale)
    jump,jump_n,jump_d=extract_clip(a.jump_fbx,names,unit_scale)

    ni={n:i+1 for i,n in enumerate(names)}
    alias={'Hips':'Hips','Spine1':'Spine','Spine2':'Spine1','Spine3':'Spine2','Neck':'Neck','Head':'Head','LShoulder':'LeftShoulder','LArm':'LeftArm','LForeArm':'LeftForeArm','LHand':'LeftHand','RShoulder':'RightShoulder','RArm':'RightArm','RForeArm':'RightForeArm','RHand':'RightHand','LThigh':'LeftUpLeg','LLeg':'LeftLeg','LFoot':'LeftFoot','LToe':'LeftToeBase','RThigh':'RightUpLeg','RLeg':'RightLeg','RFoot':'RightFoot','RToe':'RightToeBase'}
    anim={k:ni[v] for k,v in alias.items() if v in ni}
    bind=np.asarray(combined,float);yup=np.column_stack((bind[:,0],bind[:,2],-bind[:,1]));mins=yup.min(axis=0).tolist();maxs=yup.max(axis=0).tolist()

    a.out_lua.parent.mkdir(parents=True,exist_ok=True)
    with a.out_lua.open('w',encoding='utf-8',newline='\n') as out:
        out.write('-- GENERATED replacement Roronoa Zoro from Battle Stadium D.O.N. FBXs/textures.\nreturn {\n')
        out.write(f'  boneCount = {len(names)},\n  positionCount = {len(combined)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(tri_records)},\n')
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
    print('Zoro D.O.N. FBX conversion complete')
    print('geometries',len(geoms),'bones',len(names),'positions',len(combined),'influences',len(inf_bone),'triangles',len(tri_records),'unit_scale',unit_scale)
    print('idle',idle_n,idle_d,'run',run_n,run_d,'jump',jump_n,jump_d,'materials',dict(material_counts),'bounds Y-up',mins,maxs,'atlas',AW,AH)

if __name__=='__main__': main()
