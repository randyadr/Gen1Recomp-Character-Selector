#!/usr/bin/env python3
from __future__ import annotations
import argparse, math, collections, importlib.util
from pathlib import Path
import numpy as np
from PIL import Image

# Reuse the battle-tested binary FBX reader / Mixamo animation extraction from
# the fresh Beelstarmon importer. This script only changes mesh material/atlas handling.
_THIS = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('_mixamo_base', _THIS / 'convert_beelstarmon_mixamo.py')
_base = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_base)
load_fbx=_base.load_fbx; conn_maps=_base.conn_maps; clean_name=_base.clean_name; child=_base.child
extract_clip=_base.extract_clip; lua_array=_base.lua_array; lua_strings=_base.lua_strings
S=_base.S


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--base-fbx',type=Path,required=True)
    ap.add_argument('--idle-fbx',type=Path,required=True)
    ap.add_argument('--run-fbx',type=Path,required=True)
    ap.add_argument('--jump-fbx',type=Path,required=True)
    ap.add_argument('--body-texture',type=Path,required=True)
    ap.add_argument('--body-texture2',type=Path,required=True)
    ap.add_argument('--eye-texture',type=Path,required=True)
    ap.add_argument('--out-lua',type=Path,required=True)
    ap.add_argument('--out-atlas',type=Path,required=True)
    a=ap.parse_args()

    roots=load_fbx(a.base_fbx); R={r.name:r for r in roots}; objs,byid,par,chi=conn_maps(R)
    geoms=[n for n in objs if n.name=='Geometry' and len(n.props)>2 and n.props[2]=='Mesh']
    if len(geoms)!=1: raise RuntimeError(f'expected one Naruto mesh, found {len(geoms)}')
    g=geoms[0]
    models=[n for n in objs if n.name=='Model']
    limbs=[n for n in models if len(n.props)>2 and n.props[2]=='LimbNode']
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
        bid=b.props[0]
        pids=[d for t,d,p in par[bid] if d in byid and byid[d].name=='Model' and d in weighted_ids]
        pid=pids[0] if pids else None
        parents.append(bindex[pid] if pid else 0)
        L=world[bid]@np.linalg.inv(world[pid]) if pid else world[bid]
        locals_row.append(L)

    # Exact source skinning, using the authored Mixamo weights.
    verts_raw=np.array(child(g,'Vertices').props[0],float).reshape(-1,3)
    verts=np.column_stack((verts_raw[:,0],verts_raw[:,2],verts_raw[:,1]))
    cpweights=[[] for _ in range(len(verts))]
    for cl,_,bid,C,inds,weights in cluster_info:
        bi=bindex[bid]
        for vi,w in zip(inds,weights):
            if w>1e-7:
                p=np.array([*verts[vi],1.0])@C
                cpweights[vi].append((bi,float(w),p[:3]))
    left_leg_names={"LeftUpLeg","LeftLeg","LeftFoot","LeftToeBase"}
    right_leg_names={"RightUpLeg","RightLeg","RightFoot","RightToeBase"}
    left_leg_ids={bindex[b.props[0]] for b in bones if clean_name(b) in left_leg_names}
    right_leg_ids={bindex[b.props[0]] for b in bones if clean_name(b) in right_leg_names}

    pos_first=[];pos_count=[];inf_bone=[];inf_x=[];inf_y=[];inf_z=[];inf_w=[]
    for vi,pbind in enumerate(verts):
        src=cpweights[vi]
        if not src: src=[(1,1.0,(pbind[0],pbind[1],pbind[2]))]
        src.sort(key=lambda q:q[1],reverse=True); src=src[:4]
        sw=sum(q[1] for q in src) or 1.0
        pos_first.append(len(inf_bone)+1); pos_count.append(len(src))
        for bi,w,lp in src:
            inf_bone.append(int(bi)); inf_x.append(float(lp[0])); inf_y.append(float(lp[1])); inf_z.append(float(lp[2])); inf_w.append(float(w/sw))

    # The source mesh shares a few centre-seam positions between both legs.
    # Mixamo gives those positions weights from LEFT and RIGHT leg chains at
    # once, so when the run separates the legs the shared point becomes a long
    # stretched bridge.  Duplicate only those seam positions per triangle side
    # and strip the opposite-leg influences. Geometry stays in the same bind
    # location, but each leg can now deform independently.
    side_pos_cache={}
    def side_position(vi,side):
        key=(int(vi),side)
        hit=side_pos_cache.get(key)
        if hit is not None: return hit
        wanted=left_leg_ids if side=='L' else right_leg_ids
        opposite=right_leg_ids if side=='L' else left_leg_ids
        src=list(cpweights[vi])
        opp=sum(w for bi,w,lp in src if bi in opposite)
        own=sum(w for bi,w,lp in src if bi in wanted)
        # Ordinary vertices with no meaningful opposite-side contamination keep
        # their original runtime position and exact authored weights.
        if opp < 0.025 or own < 1e-6:
            side_pos_cache[key]=vi+1
            return vi+1
        use=[(bi,w,lp) for bi,w,lp in src if bi not in opposite]
        if not use:
            side_pos_cache[key]=vi+1
            return vi+1
        use.sort(key=lambda q:q[1],reverse=True); use=use[:4]
        sw=sum(q[1] for q in use) or 1.0
        pos_first.append(len(inf_bone)+1); pos_count.append(len(use))
        for bi,w,lp in use:
            inf_bone.append(int(bi)); inf_x.append(float(lp[0])); inf_y.append(float(lp[1])); inf_z.append(float(lp[2])); inf_w.append(float(w/sw))
        out_index=len(pos_first)
        side_pos_cache[key]=out_index
        return out_index

    # Naruto's supplied FBX has two body material slots plus the eye slot.
    # Rather than sharing one atlas region between the two body materials, bake
    # each source triangle into its own padded atlas cell. This preserves the
    # authored UV lookup exactly and prevents material/edge bleed in Gen1Recomp.
    # Naruto's original game asset uses separate body material textures.
    # Material 0 is the main suit; material 1 carries face/skin/accessory details.
    body0=Image.open(a.body_texture).convert('RGBA')
    body1=Image.open(a.body_texture2).convert('RGBA')
    eye=Image.open(a.eye_texture).convert('RGBA')

    uvnode=child(g,'LayerElementUV'); uv=np.array(child(uvnode,'UV').props[0],float).reshape(-1,2); uvi=child(uvnode,'UVIndex').props[0]
    matnode=child(g,'LayerElementMaterial'); mats=list(map(int,child(matnode,'Materials').props[0]))
    pvi=child(g,'PolygonVertexIndex').props[0]

    tri_records=[]; centers=[]; poly=[]; puv=[]; ci=0; pidx=0
    for raw in pvi:
        vi=(-raw-1) if raw<0 else raw; poly.append(vi); puv.append(uvi[ci]); ci+=1
        if raw<0:
            mat=mats[pidx] if pidx<len(mats) else 0; pidx+=1
            for k in range(1,len(poly)-1):
                inds=[poly[0],poly[k],poly[k+1]]
                uinds=[puv[0],puv[k],puv[k+1]]
                q=np.mean(verts[inds],axis=0)
                runtime_inds=[v+1 for v in inds]
                if q[1] < 0.95:
                    # +X is Naruto's left leg in this source rig. Pick the
                    # triangle's geometric side and duplicate any contaminated
                    # seam positions onto that leg's independent skin chain.
                    side='L' if q[0] >= 0.0 else 'R'
                    runtime_inds=[side_position(v,side) for v in inds]
                tri_records.append((mat,runtime_inds,uinds))
                centers.append(tuple(q))
            poly=[];puv=[]

    CELL=18
    cols=max(1,int(math.ceil(math.sqrt(len(tri_records)))))
    rows=int(math.ceil(len(tri_records)/cols))
    AW=cols*CELL; AH=rows*CELL
    atlas=np.zeros((AH,AW,4),dtype=np.uint8)
    atlas[:,:,:]=np.array([0,0,0,0],dtype=np.uint8)
    body0_np=np.asarray(body0,dtype=np.uint8)
    body1_np=np.asarray(body1,dtype=np.uint8)
    eye_np=np.asarray(eye,dtype=np.uint8)

    def bilinear(img,u,v):
        h,w=img.shape[:2]
        u=max(0.0,min(1.0,float(u))); v=max(0.0,min(1.0,float(v)))
        x=u*(w-1); y=v*(h-1)
        x0=int(math.floor(x)); y0=int(math.floor(y)); x1=min(w-1,x0+1); y1=min(h-1,y0+1)
        fx=x-x0; fy=y-y0
        a=img[y0,x0].astype(float)*(1-fx)+img[y0,x1].astype(float)*fx
        b=img[y1,x0].astype(float)*(1-fx)+img[y1,x1].astype(float)*fx
        return np.clip(a*(1-fy)+b*fy,0,255).astype(np.uint8)

    corner_pos=[];corner_u=[];corner_v=[]
    inner0=1.5; inner1=CELL-2.5; span=inner1-inner0
    for ti,(mat,inds,uinds) in enumerate(tri_records):
        col=ti%cols; row=ti//cols; ox=col*CELL; oy=row*CELL
        src=[]
        for uu in uinds:
            U,V=map(float,uv[uu])
            # FBX UVs are bottom-left; Pillow atlas pixels are top-left.
            src.append((U%1.0,max(0.0,min(1.0,1.0-V))))
        q=centers[ti]
        # The forehead plate is eight front-facing triangles using the metal
        # strip at U≈.499..997 / V≈.003..244. The FBX maps that strip mirrored.
        # Correct the UV lookup only for those triangles; do not flip the whole
        # face texture, which was the mistake in the previous passes.
        if mat==1 and q[1]>1.48 and q[2]<-0.03 and abs(q[0])<0.20:
            us=[u for u,v in src]; vs=[v for u,v in src]
            if min(us)>0.45 and max(vs)<0.28:
                u0,u1=0.49939900636672974,0.9972289800643921
                src=[(u0+u1-u,v) for u,v in src]
        img=eye_np if mat==2 else (body0_np if mat==0 else body1_np)
        # Fill the complete padded cell by clamping barycentrics to the source
        # triangle. Pixels outside the destination triangle become edge extrusion,
        # preventing filtering from pulling transparent/neighbor colors at seams.
        for yy in range(CELL):
            for xx in range(CELL):
                bx=(xx+0.5-inner0)/span; cy=(yy+0.5-inner0)/span
                bx=max(0.0,bx); cy=max(0.0,cy)
                if bx+cy>1.0:
                    s=bx+cy; bx/=s; cy/=s
                aa=max(0.0,1.0-bx-cy)
                su=aa*src[0][0]+bx*src[1][0]+cy*src[2][0]
                sv=aa*src[0][1]+bx*src[1][1]+cy*src[2][1]
                atlas[oy+yy,ox+xx]=bilinear(img,su,sv)
        # Canonical destination triangle corners. The mesh barycentrics then
        # reproduce the source texture interpolation inside this isolated cell.
        dst=[(inner0,inner0),(inner1,inner0),(inner0,inner1)]
        for vv,(dx,dy) in zip(inds,dst):
            corner_pos.append(vv)
            corner_u.append((ox+dx)/AW)
            corner_v.append((oy+dy)/AH)

    a.out_atlas.parent.mkdir(parents=True,exist_ok=True)
    Image.fromarray(atlas,'RGBA').save(a.out_atlas,optimize=True)

    orders={}
    for key,yaw in {'down':0.,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}.items():
        c,s=math.cos(yaw),math.sin(yaw); ds=[(x*s+z*c,i+1) for i,(x,y,z) in enumerate(centers)];ds.sort();orders[key]=[i for _,i in ds]

    idle,idle_n,idle_d=extract_clip(a.idle_fbx,names,locals_row,0,True)
    run,run_n,run_d=extract_clip(a.run_fbx,names,locals_row,0,True)
    jump,jump_n,jump_d=extract_clip(a.jump_fbx,names,locals_row,0,False)

    name_to_i={n:i+1 for i,n in enumerate(names)}
    alias={
      'Hips':'Hips','Spine1':'Spine','Spine2':'Spine1','Spine3':'Spine2','Neck':'Neck','Head':'Head',
      'LShoulder':'LeftShoulder','LArm':'LeftArm','LForeArm':'LeftForeArm','LHand':'LeftHand',
      'RShoulder':'RightShoulder','RArm':'RightArm','RForeArm':'RightForeArm','RHand':'RightHand',
      'LThigh':'LeftUpLeg','LLeg':'LeftLeg','LFoot':'LeftFoot','LToe':'LeftToeBase',
      'RThigh':'RightUpLeg','RLeg':'RightLeg','RFoot':'RightFoot','RToe':'RightToeBase',
    }
    anim={k:name_to_i[v] for k,v in alias.items() if v in name_to_i}
    mins=verts.min(axis=0).tolist(); maxs=verts.max(axis=0).tolist()

    a.out_lua.parent.mkdir(parents=True,exist_ok=True)
    with a.out_lua.open('w',encoding='utf-8',newline='\n') as out:
        out.write('-- GENERATED Naruto remake from supplied Mixamo FBXs; imported idle/run/jump clips.\nreturn {\n')
        out.write(f'  boneCount = {len(names)},\n  positionCount = {len(pos_first)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(centers)},\n')
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

    print('Naruto Mixamo conversion complete')
    print('bones',len(names),'positions',len(pos_first),'influences',len(inf_bone),'triangles',len(centers),'side duplicates',len(pos_first)-len(verts))
    print('idle',idle_n,idle_d,'run',run_n,run_d,'jump',jump_n,jump_d)
    print('bounds',mins,maxs,'atlas',AW,AH,'material counts',collections.Counter(mats))

if __name__=='__main__': main()
