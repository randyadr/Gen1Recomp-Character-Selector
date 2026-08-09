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

def stable_uv(v):
    v=float(v)
    if -1e-5 <= v <= 1.00001:
        return max(0.0,min(1.0,v))
    f=v-math.floor(v)
    if f<1e-5: f=0.0
    elif f>0.99999: f=1.0
    return max(0.0,min(1.0,f))

def extract_clip(path,names,nodes_by_name,bind_locals_row,preserve_vertical=False):
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
        tx=sample_axis(rec['T'],'X',base_t[0]); ty=sample_axis(rec['T'],'Y',base_t[1]); tz=sample_axis(rec['T'],'Z',base_t[2])
        B=bind_locals_row[bi]
        if name=='root ground':
            for f in range(count):
                # This GTA skeleton's root-ground channels are authored in a rotated
                # helper space and contain large locomotion translation/rotation. The
                # game owns world movement and jump lift, so keep this helper at its
                # bind transform and let the animated pelvis/spine/limbs supply the pose.
                out.extend(np.eye(4,dtype=float).reshape(-1).tolist())
        else:
            invB=np.linalg.inv(B)
            for f in range(count):
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
    ap.add_argument('--upper-texture',type=Path,required=True)
    ap.add_argument('--head-texture',type=Path,required=True)
    ap.add_argument('--shoes-texture',type=Path,required=True)
    ap.add_argument('--legs-texture',type=Path,required=True)
    ap.add_argument('--out-lua',type=Path,required=True)
    ap.add_argument('--out-atlas',type=Path,required=True)
    a=ap.parse_args()

    roots=load_fbx(a.base_fbx); R={r.name:r for r in roots}; objs,byid,par,chi=conn_maps(R)
    geoms=[n for n in objs if n.name=='Geometry' and len(n.props)>2 and n.props[2]=='Mesh']
    if len(geoms)!=1: raise RuntimeError(f'expected one CJ mesh geometry, got {len(geoms)}')
    g=geoms[0]; gid=g.props[0]
    limbs=[n for n in objs if n.name=='Model' and len(n.props)>2 and n.props[2]=='LimbNode']
    nodes_by_name={clean_name(n):n for n in limbs}
    names=[clean_name(n) for n in limbs]
    bindex={n.props[0]:i+1 for i,n in enumerate(limbs)}
    clusters=[n for n in objs if n.name=='Deformer' and len(n.props)>2 and n.props[2]=='Cluster']

    world={}; cluster_info=[]
    for cl in clusters:
        bones=[s for t,s,p in chi[cl.props[0]] if s in byid and byid[s].name=='Model' and len(byid[s].props)>2 and byid[s].props[2]=='LimbNode']
        if not bones: continue
        bid=bones[0]
        C=np.array(child(cl,'Transform').props[0],float).reshape(4,4)
        world[bid]=np.linalg.inv(C)
        inds=child(cl,'Indexes').props[0]; weights=child(cl,'Weights').props[0]
        cluster_info.append((bid,C,inds,weights))

    # The rig has one non-deforming helper (root hips). Infer any missing helper
    # world matrices from a known parent or child and the exact static FBX local.
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

    verts=np.array(child(g,'Vertices').props[0],float).reshape(-1,3)
    cpweights=[[] for _ in range(len(verts))]
    for bid,C,inds,weights in cluster_info:
        bi=bindex[bid]
        for vi,w in zip(inds,weights):
            if w>1e-7:
                lp=np.array([*verts[vi],1.0])@C
                cpweights[vi].append((bi,float(w),lp[:3]))
    pos_first=[];pos_count=[];inf_bone=[];inf_x=[];inf_y=[];inf_z=[];inf_w=[]
    root_index=bindex[nodes_by_name['root ground'].props[0]]
    root_inv=np.linalg.inv(world[nodes_by_name['root ground'].props[0]])
    for vi,pbind in enumerate(verts):
        infs=cpweights[vi]
        if not infs:
            lp=np.array([*pbind,1.0])@root_inv; infs=[(root_index,1.0,lp[:3])]
        infs.sort(key=lambda q:q[1],reverse=True); infs=infs[:4]
        sw=sum(q[1] for q in infs) or 1.0
        pos_first.append(len(inf_bone)+1);pos_count.append(len(infs))
        for bi,w,lp in infs:
            inf_bone.append(int(bi));inf_x.append(float(lp[0]));inf_y.append(float(lp[1]));inf_z.append(float(lp[2]));inf_w.append(float(w/sw))

    # Material order in the supplied FBX is: body upper, head, shoes, legs.
    textures=[np.asarray(Image.open(p).convert('RGBA'),dtype=np.uint8) for p in [a.upper_texture,a.head_texture,a.shoes_texture,a.legs_texture]]
    matnode=child(g,'LayerElementMaterial'); mats=list(map(int,child(matnode,'Materials').props[0]))
    uvnode=child(g,'LayerElementUV'); uv=np.array(child(uvnode,'UV').props[0],float).reshape(-1,2); uvi=child(uvnode,'UVIndex').props[0]
    pvi=child(g,'PolygonVertexIndex').props[0]
    tri=[]; centers=[]; poly=[]; puv=[]; ci=0; pidx=0
    for raw in pvi:
        vi=(-raw-1) if raw<0 else raw; poly.append(vi); puv.append(uvi[ci]); ci+=1
        if raw<0:
            mat=mats[pidx] if pidx<len(mats) else 0; pidx+=1
            for k in range(1,len(poly)-1):
                inds=[poly[0],poly[k],poly[k+1]]; uinds=[puv[0],puv[k],puv[k+1]]
                tri.append((mat,inds,uinds)); centers.append(tuple(np.mean(verts[inds],axis=0)))
            poly=[];puv=[]

    CELL=18; cols=max(1,int(math.ceil(math.sqrt(len(tri))))); rows=int(math.ceil(len(tri)/cols)); AW=cols*CELL;AH=rows*CELL
    atlas=np.zeros((AH,AW,4),dtype=np.uint8)
    def bilinear(img,u,v):
        h,w=img.shape[:2];u=max(0,min(1,float(u)));v=max(0,min(1,float(v)))
        x=u*(w-1);y=v*(h-1);x0=int(math.floor(x));y0=int(math.floor(y));x1=min(w-1,x0+1);y1=min(h-1,y0+1);fx=x-x0;fy=y-y0
        aa=img[y0,x0].astype(float)*(1-fx)+img[y0,x1].astype(float)*fx;bb=img[y1,x0].astype(float)*(1-fx)+img[y1,x1].astype(float)*fx
        return np.clip(aa*(1-fy)+bb*fy,0,255).astype(np.uint8)
    corner_pos=[];corner_u=[];corner_v=[]; inner0=1.5;inner1=CELL-2.5;span=inner1-inner0
    for ti,(mat,inds,uinds) in enumerate(tri):
        tex=textures[mat if 0<=mat<len(textures) else 0]; col=ti%cols;row=ti//cols;ox=col*CELL;oy=row*CELL
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
            corner_pos.append(vi+1);corner_u.append((ox+dx)/AW);corner_v.append((oy+dy)/AH)
    a.out_atlas.parent.mkdir(parents=True,exist_ok=True);Image.fromarray(atlas,'RGBA').save(a.out_atlas,optimize=True)

    # Source is Z-up. Runtime keeps the original skeleton/animation coordinate
    # system and converts skinned points to engine Y-up after skinning.
    centers_yup=[(x,z,-y) for x,y,z in centers]
    orders={}
    for key,yaw in {'down':0.,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}.items():
        c,s=math.cos(yaw),math.sin(yaw);ds=[(x*s+z*c,i+1) for i,(x,y,z) in enumerate(centers_yup)];ds.sort();orders[key]=[i for _,i in ds]

    idle,idle_n,idle_d=extract_clip(a.idle_fbx,names,nodes_by_name,bind_locals,True)
    run,run_n,run_d=extract_clip(a.run_fbx,names,nodes_by_name,bind_locals,True)
    jump,jump_n,jump_d=extract_clip(a.jump_fbx,names,nodes_by_name,bind_locals,True)

    ni={n:i+1 for i,n in enumerate(names)}
    alias={
      'Hips':'pelvis','Spine1':'spine lower','Spine2':'spine middle','Spine3':'spine upper','Neck':'head neck lower','Head':'head neck upper',
      'LShoulder':'arm left shoulder 1','LArm':'arm left shoulder 2','LForeArm':'arm left elbow','LHand':'arm left wrist',
      'RShoulder':'arm right shoulder 1','RArm':'arm right shoulder 2','RForeArm':'arm right elbow','RHand':'arm right wrist',
      'LThigh':'leg left thigh','LLeg':'leg left knee','LFoot':'leg left ankle','LToe':'leg left toes',
      'RThigh':'leg right thigh','RLeg':'leg right knee','RFoot':'leg right ankle','RToe':'leg right toes'}
    anim={k:ni[v] for k,v in alias.items() if v in ni}
    yup=np.column_stack((verts[:,0],verts[:,2],-verts[:,1]));mins=yup.min(axis=0).tolist();maxs=yup.max(axis=0).tolist()

    a.out_lua.parent.mkdir(parents=True,exist_ok=True)
    with a.out_lua.open('w',encoding='utf-8',newline='\n') as out:
        out.write('-- GENERATED fresh CJ replacement from supplied GTA SA FBXs; exact GTA skin + idle/run/jump.\nreturn {\n')
        out.write(f'  boneCount = {len(names)},\n  positionCount = {len(verts)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(tri)},\n')
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
    print('CJ FBX conversion complete')
    print('bones',len(names),'positions',len(verts),'influences',len(inf_bone),'triangles',len(tri),'materials',collections.Counter(mats))
    print('idle',idle_n,idle_d,'run',run_n,run_d,'jump',jump_n,jump_d,'bounds Y-up',mins,maxs,'atlas',AW,AH)

if __name__=='__main__': main()
