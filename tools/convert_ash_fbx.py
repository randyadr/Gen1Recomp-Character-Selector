#!/usr/bin/env python3
import argparse, struct, zlib, math, collections
from pathlib import Path
import numpy as np
from PIL import Image

FBX_TICKS=46186158000.0

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
    return s.split('\x00\x01')[0]

def child(n,name):
    for c in n.children:
        if c.name==name:return c
    return None

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
    for i in range(0,len(vals),per):out.write('    '+', '.join('"'+v.replace('"','\\"')+'"' for v in vals[i:i+per])+',\n')
    out.write('  },\n')

def main():
    ap=argparse.ArgumentParser();ap.add_argument('fbx',type=Path);ap.add_argument('--idle-fbx',type=Path,required=True);ap.add_argument('--textures',type=Path,required=True);ap.add_argument('--out-lua',type=Path,required=True);ap.add_argument('--out-atlas',type=Path,required=True);a=ap.parse_args()
    roots=load_fbx(a.fbx); R={r.name:r for r in roots}; objs=R['Objects'].children
    byid={n.props[0]:n for n in objs if n.props and isinstance(n.props[0],int)}
    par=collections.defaultdict(list); chi=collections.defaultdict(list)
    for c in R['Connections'].children:
        typ,src,dst,*rest=c.props; prop=rest[0] if rest else None; par[src].append((typ,dst,prop)); chi[dst].append((typ,src,prop))

    geoms=[n for n in objs if n.name=='Geometry' and len(n.props)>2 and n.props[2]=='Mesh']
    models=[n for n in objs if n.name=='Model']
    limbs=[n for n in models if len(n.props)>2 and n.props[2]=='LimbNode']
    clusters=[n for n in objs if n.name=='Deformer' and len(n.props)>2 and n.props[2]=='Cluster']

    # Cluster -> connected bone and geometry. Transform is already the mesh->bone bind map
    # (FBX uses row-vector matrices here). Normalize its cm output to model meters.
    cluster_info=[]; bone_world_candidates=collections.defaultdict(list)
    for cl in clusters:
        bones=[s for t,s,p in chi[cl.props[0]] if s in byid and byid[s].name=='Model' and len(byid[s].props)>2 and byid[s].props[2]=='LimbNode']
        geos=[d for t,d,p in par[cl.props[0]] if d in byid and byid[d].name=='Geometry']
        if not bones or not geos: continue
        C=np.array(child(cl,'Transform').props[0],float).reshape(4,4)
        Cn=C.copy(); Cn[:3,:3]/=100.0; Cn[3,:3]/=100.0
        W=np.linalg.inv(Cn)
        bone_world_candidates[bones[0]].append(W)
        inds=child(cl,'Indexes').props[0]; weights=child(cl,'Weights').props[0]
        cluster_info.append((cl,geos[0],bones[0],Cn,inds,weights))

    weighted_ids={b for _,_,b,_,_,_ in cluster_info}
    # Preserve FBX skeleton order but keep only deforming bones. Terminal no-weight bones do not affect the mesh.
    bones=[n for n in limbs if n.props[0] in weighted_ids]
    bindex={n.props[0]:i+1 for i,n in enumerate(bones)}
    names=[clean_name(n).replace('mixamorig:','') for n in bones]

    # Bind world/local from exact cluster matrices.
    world={bid:bone_world_candidates[bid][0] for bid in weighted_ids}
    parents=[]; locals_row=[]
    for b in bones:
        bid=b.props[0]; pids=[d for t,d,p in par[bid] if d in byid and byid[d].name=='Model' and d in weighted_ids]
        pid=pids[0] if pids else None
        parents.append(bindex[pid] if pid else 0)
        L=world[bid]@np.linalg.inv(world[pid]) if pid else world[bid]
        locals_row.append(L)

    # Exact per-control-point skinning using source cluster weights/local coordinates.
    clusters_by_geo=collections.defaultdict(list)
    for rec in cluster_info: clusters_by_geo[rec[1]].append(rec)
    pos_first=[];pos_count=[];inf_bone=[];inf_x=[];inf_y=[];inf_z=[];inf_w=[]
    geom_base={}; all_bind=[]
    for g in geoms:
        gid=g.props[0]; verts=np.array(child(g,'Vertices').props[0],float).reshape(-1,3); geom_base[gid]=len(all_bind)
        cpweights=[[] for _ in range(len(verts))]
        for cl,_,bid,Cn,inds,weights in clusters_by_geo[gid]:
            bi=bindex[bid]
            for vi,w in zip(inds,weights):
                if w>1e-7:
                    p=np.array([*verts[vi],1.0])@Cn
                    cpweights[vi].append((bi,float(w),p[:3]))
        for vi,pbind in enumerate(verts):
            infs=cpweights[vi]
            if not infs:
                # Extremely rare unweighted control point: attach to Hips/root in its local space.
                bi=1; C=np.linalg.inv(world[bones[0].props[0]])
                lp=np.array([*pbind,1.0])@C; infs=[(bi,1.0,lp[:3])]
            infs.sort(key=lambda q:q[1],reverse=True); infs=infs[:4]
            sw=sum(q[1] for q in infs) or 1.0
            pos_first.append(len(inf_bone)+1);pos_count.append(len(infs));all_bind.append(tuple(pbind))
            for bi,w,lp in infs:
                inf_bone.append(bi);inf_x.append(lp[0]);inf_y.append(lp[1]);inf_z.append(lp[2]);inf_w.append(w/sw)

    # Atlas layout matches mesh material image. All supplied images remain unscaled.
    image_files=['Ash_arms_hat_hair.png','trAsh_00_body_col.png','PokeTra_Ash_face.png']
    imgs={f:Image.open(a.textures/f).convert('RGBA') for f in image_files}
    AW=max(im.width for im in imgs.values()); y=0; slots={}
    for f in image_files:
        im=imgs[f]; slots[f]=(0,y,im.width,im.height); y+=im.height
    AH=y; atlas=Image.new('RGBA',(AW,AH),(0,0,0,0))
    for f,im in imgs.items(): atlas.paste(im,(slots[f][0],slots[f][1]))
    a.out_atlas.parent.mkdir(parents=True,exist_ok=True); atlas.save(a.out_atlas)

    # geometry -> material filename based on Geometry->Model->Material links
    mat_file={}
    for g in geoms:
        model_ids=[d for t,d,p in par[g.props[0]] if d in byid and byid[d].name=='Model']
        fn=None
        if model_ids:
            mats=[s for t,s,p in chi[model_ids[0]] if s in byid and byid[s].name=='Material']
            if mats: fn=clean_name(byid[mats[0]])
        if fn not in imgs: raise RuntimeError(f'no texture mapping for {clean_name(g)} -> {fn}')
        mat_file[g.props[0]]=fn

    corner_pos=[];corner_u=[];corner_v=[];tri_centers=[]
    for g in geoms:
        gid=g.props[0]; verts=np.array(child(g,'Vertices').props[0],float).reshape(-1,3); pvi=child(g,'PolygonVertexIndex').props[0]
        uvnode=child(g,'LayerElementUV'); uv=np.array(child(uvnode,'UV').props[0],float).reshape(-1,2); uvi=child(uvnode,'UVIndex').props[0]
        fn=mat_file[gid]; x0,y0,iwid,ihgt=slots[fn]
        poly=[]; puv=[]
        corner_i=0
        for raw in pvi:
            vi=(-raw-1) if raw<0 else raw; poly.append(vi); puv.append(uvi[corner_i]); corner_i+=1
            if raw<0:
                # Fan triangulate while retaining corner UVs.
                for k in range(1,len(poly)-1):
                    inds=[poly[0],poly[k],poly[k+1]]; uinds=[puv[0],puv[k],puv[k+1]]
                    pts=[]
                    for vv,uu in zip(inds,uinds):
                        corner_pos.append(geom_base[gid]+vv+1); pts.append(verts[vv])
                        U,V=map(float,uv[uu])
                        # The Ash export mixes three UV conventions:
                        # * arms/hat/hair and face use ordinary FBX bottom-left V
                        # * the body material is shifted down by exactly one UV tile (V in -1..0)
                        # * part of the face wraps U through the negative side (U in about -0.25..1)
                        # Clamp destroyed both cases in v2.8.43: body V collapsed to one row and
                        # negative face U collapsed to the texture edge. Preserve the authored wrap.
                        U=U%1.0
                        if fn=='trAsh_00_body_col.png':
                            imageV=-V
                        else:
                            imageV=1.0-V
                        imageV=max(0.0,min(1.0,imageV))
                        corner_u.append((x0+0.5+U*(iwid-1))/AW)
                        corner_v.append((y0+0.5+imageV*(ihgt-1))/AH)
                    q=np.mean(np.array(pts),axis=0);tri_centers.append(tuple(q))
                poly=[];puv=[]

    orders={}
    for key,yaw in {'down':0.,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}.items():
        c,s=math.cos(yaw),math.sin(yaw); ds=[(x*s+z*c,i+1) for i,(x,y,z) in enumerate(tri_centers)];ds.sort();orders[key]=[i for _,i in ds]

    # Embedded looping run: all curves have 44 synchronized 60-Hz keys. Bake the exact
    # local matrix deltas relative to the bind pose, including Hips vertical bounce but
    # removing FBX root X/Z locomotion because Gen1Recomp supplies world translation.
    curve_nodes=[n for n in objs if n.name=='AnimationCurveNode']; curves=[n for n in objs if n.name=='AnimationCurve']
    rot_curves={}; trans_curves={}; frame_times=None
    for b in bones:
        bid=b.props[0]
        for t,nid,prop in chi[bid]:
            if nid not in byid or byid[nid].name!='AnimationCurveNode': continue
            axes={}
            for tt,cid,axis in chi[nid]:
                if cid in byid and byid[cid].name=='AnimationCurve':
                    cu=byid[cid]; kt=child(cu,'KeyTime').props[0]; kv=child(cu,'KeyValueFloat').props[0]
                    axes[axis[-1]]=list(map(float,kv)); frame_times=frame_times or kt
            if prop=='Lcl Rotation':rot_curves[bid]=axes
            elif prop=='Lcl Translation':trans_curves[bid]=axes
    frame_count=len(frame_times or [])
    if frame_count<2: raise RuntimeError('embedded run animation not found')
    run=[]; idle=[]
    for bi,b in enumerate(bones):
        bid=b.props[0]; bind_row=locals_row[bi]; bind_col=bind_row.T; inv_bind_col=np.linalg.inv(bind_col); rc=rot_curves.get(bid,{})
        mats=[]
        for f in range(frame_count):
            x=rc.get('X',[0.0]*frame_count)[f] if rc else 0.0; yv=rc.get('Y',[0.0]*frame_count)[f] if rc else 0.0; z=rc.get('Z',[0.0]*frame_count)[f] if rc else 0.0
            # FBX local transform is Bind(Translation * PreRotation) * LclRotation.
            # The runtime also computes bindLocal * delta, so the correct delta is
            # simply the animated Euler rotation in column-vector form. The earlier
            # conjugated form rotated around the wrong basis and pulled limbs apart.
            delta=euler_row(x,yv,z).T
            if bi==0 and bid in trans_curves and 'Y' in trans_curves[bid]:
                delta=delta.copy(); delta[1,3]=(trans_curves[bid]['Y'][f]/100.0)-bind_row[3,1]
            mats.append(delta)
        for m in mats: run.extend(m.reshape(-1).tolist())
        # Average source Euler values gives a relaxed neutral stance from the same clip.
        ax=sum(rc.get('X',[0.0]))/frame_count if rc else 0.0; ay=sum(rc.get('Y',[0.0]))/frame_count if rc else 0.0; az=sum(rc.get('Z',[0.0]))/frame_count if rc else 0.0
        avg=euler_row(ax,ay,az).T
        if bi==0 and bid in trans_curves and 'Y' in trans_curves[bid]:
            avg=avg.copy(); avg[1,3]=(sum(trans_curves[bid]['Y'])/frame_count/100.0)-bind_row[3,1]
        idle.extend(avg.reshape(-1).tolist())

    # Import the user-supplied Standing Idle animation on the same Mixamo skeleton.
    # The idle FBX contains the same 65-bone hierarchy as Slow Run; only deforming bones
    # are emitted, matching the run/model bone order above. Root X/Z locomotion is removed
    # while the small authored Hips Y breathing motion is preserved.
    def extract_clip(path):
        roots2=load_fbx(path); R2={r.name:r for r in roots2}; objs2=R2['Objects'].children
        byid2={n.props[0]:n for n in objs2 if n.props and isinstance(n.props[0],int)}
        chi2=collections.defaultdict(list)
        for cc in R2['Connections'].children:
            typ,src,dst,*rest=cc.props; prop=rest[0] if rest else None
            chi2[dst].append((typ,src,prop))
        limb_by_name={clean_name(n).replace('mixamorig:',''):n for n in objs2 if n.name=='Model' and len(n.props)>2 and n.props[2]=='LimbNode'}
        rot2={}; trans2={}; times=None
        for name in names:
            bn=limb_by_name.get(name)
            if bn is None: continue
            bid2=bn.props[0]
            for typ,nid,prop in chi2[bid2]:
                if nid not in byid2 or byid2[nid].name!='AnimationCurveNode': continue
                axes={}; local_times=None
                for tt,cid,axis in chi2[nid]:
                    if cid in byid2 and byid2[cid].name=='AnimationCurve':
                        cu=byid2[cid]; kt=child(cu,'KeyTime').props[0]; kv=child(cu,'KeyValueFloat').props[0]
                        axes[axis[-1]]=(list(kt),list(map(float,kv))); local_times=kt
                if local_times and (times is None or len(local_times)>len(times)): times=list(local_times)
                if prop=='Lcl Rotation': rot2[name]=axes
                elif prop=='Lcl Translation': trans2[name]=axes
        count=len(times or [])
        if count<2: raise RuntimeError(f'animation clip not found in {path}')
        clip=[]
        target_times=np.asarray(times,dtype=float)
        def sampled(axes,key):
            rec=axes.get(key)
            if not rec: return np.zeros(count,dtype=float)
            kt,kv=rec
            if len(kv)==1: return np.full(count,float(kv[0]),dtype=float)
            return np.interp(target_times,np.asarray(kt,dtype=float),np.asarray(kv,dtype=float))
        for bi,name in enumerate(names):
            bind_row=locals_row[bi]; rc=rot2.get(name,{}); tc=trans2.get(name,{})
            xs=sampled(rc,'X'); ys=sampled(rc,'Y'); zs=sampled(rc,'Z'); tys=sampled(tc,'Y')
            for f in range(count):
                delta=euler_row(xs[f],ys[f],zs[f]).T
                if bi==0 and 'Y' in tc:
                    delta=delta.copy(); delta[1,3]=(tys[f]/100.0)-bind_row[3,1]
                clip.extend(delta.reshape(-1).tolist())
        return clip,count,(times[-1]-times[0])/FBX_TICKS

    idle_clip,idle_frame_count,idle_duration=extract_clip(a.idle_fbx)

    mins=[min(p[d] for p in all_bind) for d in range(3)]; maxs=[max(p[d] for p in all_bind) for d in range(3)]
    # Friendly runtime aliases expected by the rest of the mod.
    alias={
      'Hips':'Hips','Spine1':'Spine','Spine2':'Spine1','Spine3':'Spine2','Neck':'Neck','Head':'Head',
      'LShoulder':'LeftShoulder','LArm':'LeftArm','LForeArm':'LeftForeArm','LHand':'LeftHand',
      'RShoulder':'RightShoulder','RArm':'RightArm','RForeArm':'RightForeArm','RHand':'RightHand',
      'LThigh':'LeftUpLeg','LLeg':'LeftLeg','LFoot':'LeftFoot','LToe':'LeftToeBase',
      'RThigh':'RightUpLeg','RLeg':'RightLeg','RFoot':'RightFoot','RToe':'RightToeBase',
    }
    name_to_i={n:i+1 for i,n in enumerate(names)}
    anim={k:name_to_i[v] for k,v in alias.items() if v in name_to_i}

    a.out_lua.parent.mkdir(parents=True,exist_ok=True)
    with a.out_lua.open('w',encoding='utf-8',newline='\n') as out:
        out.write('-- GENERATED from supplied Ash Ketchum Slow Run.fbx + Standing Idle.fbx; exact FBX skin + embedded animations.\nreturn {\n')
        out.write(f'  boneCount = {len(bones)},\n  positionCount = {len(all_bind)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(tri_centers)},\n  runFrameCount = {frame_count},\n  runDuration = {(frame_times[-1]-frame_times[0])/FBX_TICKS:.9g},\n  idleFrameCount = {idle_frame_count},\n  idleDuration = {idle_duration:.9g},\n')
        lua_strings(out,'boneName',names); lua_array(out,'boneParent',parents,16); lua_array(out,'boneLocal',[x for L in locals_row for x in L.T.reshape(-1)],16)
        lua_array(out,'posFirst',pos_first,16);lua_array(out,'posCount',pos_count,16);lua_array(out,'infBone',inf_bone,16);lua_array(out,'infX',inf_x);lua_array(out,'infY',inf_y);lua_array(out,'infZ',inf_z);lua_array(out,'infW',inf_w)
        lua_array(out,'cornerPos',corner_pos,16);lua_array(out,'cornerU',corner_u);lua_array(out,'cornerV',corner_v)
        lua_array(out,'runDelta',run,16);lua_array(out,'runIdleDelta',idle,16);lua_array(out,'idleDelta',idle_clip,16)
        out.write('  order = {\n')
        for k in ('down','left','up','right'):
            out.write(f'    {k} = {{\n');v=orders[k]
            for i in range(0,len(v),20): out.write('      '+', '.join(map(str,v[i:i+20]))+',\n')
            out.write('    },\n')
        out.write('  },\n  animBone = {\n')
        for k,v in anim.items():out.write(f'    {k} = {v},\n')
        out.write('  },\n');lua_array(out,'bounds',mins+maxs,6);out.write('}\n')
    print('Ash conversion complete')
    print('bones',len(bones),'positions',len(all_bind),'influences',len(inf_bone),'triangles',len(tri_centers),'run frames',frame_count,'duration',(frame_times[-1]-frame_times[0])/FBX_TICKS,'idle frames',idle_frame_count,'idle duration',idle_duration)
    print('bounds',mins,maxs,'atlas',AW,AH)

if __name__=='__main__':main()
