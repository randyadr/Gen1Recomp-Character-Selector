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

def prop_vec(node,key,default=(0.0,0.0,0.0)):
    p70=child(node,'Properties70')
    if p70:
        for q in p70.children:
            if q.name=='P' and q.props and q.props[0]==key:
                return np.asarray(q.props[-3:],dtype=float)
    return np.asarray(default,dtype=float)

def translate_row(v):
    M=np.eye(4,dtype=float); M[3,:3]=v; return M

def static_local_row(node):
    return euler_row(*prop_vec(node,'Lcl Rotation')) @ translate_row(prop_vec(node,'Lcl Translation'))

def stable_uv(v: float) -> float:
    v=float(v)
    if -1e-5 <= v <= 1.00001:
        return max(0.0,min(1.0,v))
    f=v-math.floor(v)
    if f<1e-5: f=0.0
    elif f>0.99999: f=1.0
    return max(0.0,min(1.0,f))

def extract_clip(path,names,nodes_by_name,bind_locals_row):
    roots=load_fbx(path); R={r.name:r for r in roots}; objs,byid,par,chi=conn_maps(R)
    clip_nodes={clean_name(n):n for n in objs if n.name=='Model' and len(n.props)>2 and n.props[2]=='LimbNode'}
    curves={}; all_times=None
    for name in names:
        bn=clip_nodes.get(name)
        if bn is None: continue
        rec={'R':{},'T':{}}
        for typ,nid,prop in chi[bn.props[0]]:
            if nid not in byid or byid[nid].name!='AnimationCurveNode': continue
            dst='R' if prop=='Lcl Rotation' else ('T' if prop=='Lcl Translation' else None)
            if not dst: continue
            for tt,cid,axis in chi[nid]:
                if cid in byid and byid[cid].name=='AnimationCurve':
                    cu=byid[cid]; kt=list(child(cu,'KeyTime').props[0]); kv=list(map(float,child(cu,'KeyValueFloat').props[0]))
                    rec[dst][axis[-1]]=(kt,kv)
                    if all_times is None or len(kt)>len(all_times): all_times=kt
        curves[name]=rec
    if not all_times or len(all_times)<2: raise RuntimeError(f'no usable animation in {path}')
    target=np.asarray(all_times,dtype=float); count=len(target)
    def sample_axis(rec,key,default):
        q=rec.get(key)
        if not q: return np.full(count,float(default),dtype=float)
        kt,kv=q
        if len(kv)==1: return np.full(count,float(kv[0]),dtype=float)
        return np.interp(target,np.asarray(kt,dtype=float),np.asarray(kv,dtype=float))

    out=[]
    for bi,name in enumerate(names):
        source_node=nodes_by_name[name]
        base_r=prop_vec(source_node,'Lcl Rotation'); base_t=prop_vec(source_node,'Lcl Translation')
        rec=curves.get(name,{'R':{},'T':{}})
        xs=sample_axis(rec['R'],'X',base_r[0]); ys=sample_axis(rec['R'],'Y',base_r[1]); zs=sample_axis(rec['R'],'Z',base_r[2])
        B=bind_locals_row[bi]; invB=np.linalg.inv(B)
        for f in range(count):
            # The supplied clips put all locomotion translation on NULL. Gen1Recomp
            # owns world movement/jump height, so preserve each bone's bind translation
            # and use only the authored animation rotations. This keeps the pose while
            # preventing the mesh from walking hundreds of FBX units away from the player.
            A=euler_row(xs[f],ys[f],zs[f]) @ translate_row(base_t)
            D=A @ invB
            out.extend(D.T.reshape(-1).tolist())
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
    all_geoms=[n for n in objs if n.name=='Geometry' and len(n.props)>2 and n.props[2]=='Mesh']
    if not all_geoms: raise RuntimeError('no mesh geometry in Yami FBX')

    # Keep the normal body and facial mesh. The two chr0400_damage_* meshes are
    # alternate overlapping damage shells and would double-render the normal outfit.
    geoms=[]
    for g in all_geoms:
        gid=g.props[0]
        model_ids=[d for t,d,p in par[gid] if d in byid and byid[d].name=='Model']
        model_name=clean_name(byid[model_ids[0]]) if model_ids else ''
        if model_name in ('chr0400_form0','chr0400_facial1'):
            geoms.append(g)
    if len(geoms)!=2:
        raise RuntimeError(f'expected normal form0 + facial1 geometries, found {len(geoms)}')
    selected_gids={g.props[0] for g in geoms}

    limbs=[n for n in objs if n.name=='Model' and len(n.props)>2 and n.props[2]=='LimbNode']
    nodes_by_name={clean_name(n):n for n in limbs}; names=[clean_name(n) for n in limbs]
    bindex={n.props[0]:i+1 for i,n in enumerate(limbs)}
    clusters=[n for n in objs if n.name=='Deformer' and len(n.props)>2 and n.props[2]=='Cluster']

    # Resolve each cluster's geometry through Cluster -> Skin -> Geometry.
    world_candidates=collections.defaultdict(list); cluster_by_geo=collections.defaultdict(list)
    for cl in clusters:
        bone_ids=[s for t,s,p in chi[cl.props[0]] if s in byid and byid[s].name=='Model' and len(byid[s].props)>2 and byid[s].props[2]=='LimbNode']
        skin_ids=[d for t,d,p in par[cl.props[0]] if d in byid and byid[d].name=='Deformer' and len(byid[d].props)>2 and byid[d].props[2]=='Skin']
        geo_ids=[]
        for sid in skin_ids:
            geo_ids += [d for t,d,p in par[sid] if d in byid and byid[d].name=='Geometry']
        if not bone_ids or not geo_ids: continue
        bid=bone_ids[0]; gid=geo_ids[0]
        C=np.array(child(cl,'Transform').props[0],float).reshape(4,4)
        world_candidates[bid].append(np.linalg.inv(C))
        if gid in selected_gids:
            inds=child(cl,'Indexes').props[0]; weights=child(cl,'Weights').props[0]
            cluster_by_geo[gid].append((bid,C,inds,weights))

    world={bid:cands[0] for bid,cands in world_candidates.items()}
    # Infer non-deforming helper worlds from their exact static hierarchy.
    changed=True
    while changed:
        changed=False
        for n in limbs:
            nid=n.props[0]
            if nid in world: continue
            parent_ids=[d for t,d,p in par[nid] if d in bindex]
            if parent_ids and parent_ids[0] in world:
                world[nid]=static_local_row(n) @ world[parent_ids[0]]; changed=True; continue
            child_ids=[s for t,s,p in chi[nid] if s in bindex and s in world]
            if child_ids:
                cnode=byid[child_ids[0]]
                world[nid]=np.linalg.inv(static_local_row(cnode)) @ world[child_ids[0]]; changed=True
    missing=[clean_name(n) for n in limbs if n.props[0] not in world]
    if missing: raise RuntimeError(f'could not infer bind worlds for {missing}')

    parents=[]; bind_locals=[]
    for n in limbs:
        nid=n.props[0]; pids=[d for t,d,p in par[nid] if d in bindex]
        pid=pids[0] if pids else None
        parents.append(bindex[pid] if pid else 0)
        bind_locals.append(world[nid] @ np.linalg.inv(world[pid]) if pid else world[nid])

    # Build combined positions/influences across form0 + facial1.
    geom_base={}; combined_bind=[]
    pos_first=[];pos_count=[];inf_bone=[];inf_x=[];inf_y=[];inf_z=[];inf_w=[]
    fallback_name='WAIST' if 'WAIST' in nodes_by_name else names[0]
    fallback_id=nodes_by_name[fallback_name].props[0]; fallback_index=bindex[fallback_id]; fallback_inv=np.linalg.inv(world[fallback_id])
    for g in geoms:
        gid=g.props[0]; verts=np.array(child(g,'Vertices').props[0],float).reshape(-1,3)
        geom_base[gid]=len(combined_bind)
        cpweights=[[] for _ in range(len(verts))]
        for bid,C,inds,weights in cluster_by_geo[gid]:
            bi=bindex[bid]
            for vi,w in zip(inds,weights):
                if w>1e-7:
                    lp=np.array([*verts[vi],1.0])@C
                    cpweights[vi].append((bi,float(w),lp[:3]))
        for vi,pbind in enumerate(verts):
            infs=cpweights[vi]
            if not infs:
                lp=np.array([*pbind,1.0])@fallback_inv; infs=[(fallback_index,1.0,lp[:3])]
            infs.sort(key=lambda q:q[1],reverse=True); infs=infs[:4]
            sw=sum(q[1] for q in infs) or 1.0
            pos_first.append(len(inf_bone)+1); pos_count.append(len(infs)); combined_bind.append(tuple(pbind))
            for bi,w,lp in infs:
                inf_bone.append(int(bi));inf_x.append(float(lp[0]));inf_y.append(float(lp[1]));inf_z.append(float(lp[2]));inf_w.append(float(w/sw))

    # Material -> supplied diffuse/color map. Oral reuses skin; weapon glow reuses
    # weapon color because the engine has a single unlit diffuse atlas path here.
    tex_files={
      'MI_chr0400_skin':'T_Chr0400_skin_C.png',
      'MI_chr0400_cloth_02':'T_Chr0400_cloth_02_C.png',
      'MI_chr0400_weapon':'T_Chr0400_weapon_C.png',
      'MI_chr0400_cloth_01':'T_Chr0400_cloth_01_C.png',
      'MI_chr0400_eyeshadow':'T_Chr0400_eyeshadow_C.png',
      'MI_chr0400_lens':'T_Chr0400_lens_C.png',
      'MI_chr0400_hair':'T_Chr0400_hair_C.png',
      'MI_chr0400_eye':'T_Chr0400_eye_C.png',
      'MI_chr0400_weapon_glow':'T_Chr0400_weapon_C.png',
      'MI_chr0400_oral':'T_Chr0400_skin_C.png',
    }
    unique_files=[]
    for f in tex_files.values():
        if f not in unique_files: unique_files.append(f)
    images={f:Image.open(a.textures_dir/f).convert('RGBA') for f in unique_files}
    CELL=max(max(im.size) for im in images.values())
    cols=4; rows=int(math.ceil(len(unique_files)/cols)); AW=cols*CELL; AH=rows*CELL
    atlas=Image.new('RGBA',(AW,AH),(0,0,0,0)); slots={}
    for i,f in enumerate(unique_files):
        im=images[f]; x=(i%cols)*CELL; y=(i//cols)*CELL; atlas.paste(im,(x,y)); slots[f]=(x,y,im.width,im.height)
    a.out_atlas.parent.mkdir(parents=True,exist_ok=True); atlas.save(a.out_atlas,optimize=True)

    corner_pos=[];corner_u=[];corner_v=[];centers=[];material_counts=collections.Counter()
    for g in geoms:
        gid=g.props[0]; verts=np.array(child(g,'Vertices').props[0],float).reshape(-1,3); pvi=child(g,'PolygonVertexIndex').props[0]
        uvnode=child(g,'LayerElementUV'); uv=np.array(child(uvnode,'UV').props[0],float).reshape(-1,2); uvi=child(uvnode,'UVIndex').props[0]
        matnode=child(g,'LayerElementMaterial'); mats=list(map(int,child(matnode,'Materials').props[0]))
        model_ids=[d for t,d,p in par[gid] if d in byid and byid[d].name=='Model']; model=byid[model_ids[0]]
        mat_nodes=[byid[s] for t,s,p in chi[model.props[0]] if s in byid and byid[s].name=='Material']
        mat_names=[clean_name(n) for n in mat_nodes]
        poly=[];puv=[];ci=0;pidx=0
        for raw in pvi:
            vi=(-raw-1) if raw<0 else raw; poly.append(vi);puv.append(uvi[ci]);ci+=1
            if raw<0:
                mi=mats[pidx] if pidx<len(mats) else 0;pidx+=1
                mat_name=mat_names[mi] if 0<=mi<len(mat_names) else mat_names[0]
                tex_file=tex_files.get(mat_name,'T_Chr0400_skin_C.png'); x0,y0,iw,ih=slots[tex_file]
                material_counts[mat_name]+=1
                for k in range(1,len(poly)-1):
                    inds=[poly[0],poly[k],poly[k+1]];uinds=[puv[0],puv[k],puv[k+1]]
                    centers.append(tuple(np.mean(verts[inds],axis=0)))
                    for vi,ui in zip(inds,uinds):
                        U,V=map(float,uv[ui]); U=stable_uv(U); V=max(0.0,min(1.0,1.0-stable_uv(V)))
                        corner_pos.append(geom_base[gid]+vi+1)
                        corner_u.append((x0+0.5+U*(iw-1))/AW)
                        corner_v.append((y0+0.5+V*(ih-1))/AH)
                poly=[];puv=[]

    # Original rig is Z-up. Runtime skins in source space then converts each point
    # to engine Y-up via postSkinZUp=true.
    centers_yup=[(x,z,-y) for x,y,z in centers]
    orders={}
    for key,yaw in {'down':0.,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}.items():
        c,s=math.cos(yaw),math.sin(yaw); ds=[(x*s+z*c,i+1) for i,(x,y,z) in enumerate(centers_yup)]; ds.sort(); orders[key]=[i for _,i in ds]

    idle,idle_n,idle_d=extract_clip(a.idle_fbx,names,nodes_by_name,bind_locals)
    run,run_n,run_d=extract_clip(a.run_fbx,names,nodes_by_name,bind_locals)
    jump,jump_n,jump_d=extract_clip(a.jump_fbx,names,nodes_by_name,bind_locals)

    ni={n:i+1 for i,n in enumerate(names)}
    alias={
      'Hips':'WAIST','Spine1':'SPINE1','Spine2':'SPINE2','Spine3':'SPINE3','Neck':'NECK','Head':'HEAD',
      'LShoulder':'CLAVICLE_L','LArm':'SHOULDER_L','LForeArm':'ELBOW_L','LHand':'WRIST_L',
      'RShoulder':'CLAVICLE_R','RArm':'SHOULDER_R','RForeArm':'ELBOW_R','RHand':'WRIST_R',
      'LThigh':'THIGH_L','LLeg':'CLANK_L','LFoot':'CLANKROLL_L','LToe':'TOE1_L',
      'RThigh':'THIGH_R','RLeg':'CLANK_R','RFoot':'CLANKROLL_R','RToe':'TOE1_R'}
    anim={k:ni[v] for k,v in alias.items() if v in ni}
    bind=np.asarray(combined_bind,float); yup=np.column_stack((bind[:,0],bind[:,2],-bind[:,1])); mins=yup.min(axis=0).tolist();maxs=yup.max(axis=0).tolist()

    a.out_lua.parent.mkdir(parents=True,exist_ok=True)
    with a.out_lua.open('w',encoding='utf-8',newline='\n') as out:
        out.write('-- GENERATED Yami character from supplied FBXs/textures; normal form0 + facial1 meshes.\nreturn {\n')
        out.write(f'  boneCount = {len(names)},\n  positionCount = {len(combined_bind)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(centers)},\n')
        out.write(f'  idleFrameCount = {idle_n},\n  idleDuration = {idle_d:.9g},\n  runFrameCount = {run_n},\n  runDuration = {run_d:.9g},\n  jumpFrameCount = {jump_n},\n  jumpDuration = {jump_d:.9g},\n')
        lua_strings(out,'boneName',names);lua_array(out,'boneParent',parents,16);lua_array(out,'boneLocal',[x for L in bind_locals for x in L.T.reshape(-1)],16)
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
    print('Yami FBX conversion complete')
    print('bones',len(names),'positions',len(combined_bind),'influences',len(inf_bone),'triangles',len(centers))
    print('idle',idle_n,idle_d,'run',run_n,run_d,'jump',jump_n,jump_d)
    print('materials',dict(material_counts),'atlas',AW,AH,'bounds Y-up',mins,maxs)

if __name__=='__main__': main()
