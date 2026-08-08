#!/usr/bin/env python3
from __future__ import annotations
import argparse, math, pathlib, xml.etree.ElementTree as ET
from PIL import Image


def ident(): return [1.,0,0,0, 0,1.,0,0, 0,0,1.,0, 0,0,0,1.]
def mul(a,b):
    o=[0.]*16
    for r in range(4):
        for c in range(4): o[r*4+c]=sum(a[r*4+k]*b[k*4+c] for k in range(4))
    return o

def trans(x,y,z):
    m=ident(); m[3]=x; m[7]=y; m[11]=z; return m

def inv_rigid(m):
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
    import json
    out.write(f'  {name} = {{\n')
    for i in range(0,len(vals),per): out.write('    '+', '.join(json.dumps(v) for v in vals[i:i+per])+',\n')
    out.write('  },\n')


def parse_obj(path):
    verts=[]; uvs=[]; groups={}; current_group=None; current_mat=None; faces=[]
    in_character=False
    for raw in path.read_text(errors='replace').splitlines():
        line=raw.strip()
        if not line or line.startswith('#'): continue
        if line.startswith('v '):
            p=line.split(); verts.append((float(p[1]),float(p[2]),float(p[3])))
        elif line.startswith('vt '):
            p=line.split(); uvs.append((float(p[1]),float(p[2])))
        elif line.startswith('g '):
            current_group=line.split(None,1)[1].strip(); groups.setdefault(current_group,set())
            if current_group=='Object001': in_character=True
        elif line.startswith('usemtl '): current_mat=line.split(None,1)[1].strip()
        elif line.startswith('f '):
            corners=[]
            for tok in line.split()[1:]:
                ps=tok.split('/'); vi=int(ps[0]); ti=int(ps[1]) if len(ps)>1 and ps[1] else 0
                if vi<0: vi=len(verts)+1+vi
                if ti<0: ti=len(uvs)+1+ti
                corners.append((vi,ti))
                if current_group: groups[current_group].add(vi)
            if in_character and current_group=='Object001':
                for i in range(1,len(corners)-1): faces.append((current_mat,[corners[0],corners[i],corners[i+1]]))
    return verts,uvs,groups,faces


def group_center(name, groups, verts):
    ids=groups.get(name) or []
    pts=[verts[i-1] for i in ids]
    if not pts: raise KeyError(name)
    return tuple(sum(p[d] for p in pts)/len(pts) for d in range(3))

def group_bounds(name, groups, verts):
    ids=groups.get(name) or []
    pts=[verts[i-1] for i in ids]
    return tuple(min(p[d] for p in pts) for d in range(3)), tuple(max(p[d] for p in pts) for d in range(3))


def build_atlas(texdir,outpath,pistol_texture=None):
    # Isolated regions with padding.  The final 516x516 region is reserved for
    # CJ's pistol texture so the weapon can live in the same runtime mesh/atlas.
    specs={
        'body_upper':('upper body.png',(2,2,514,514)),
        'head':('head.png',(518,2,774,258)),
        'legs':('legs.png',(778,2,1034,514)),
        'shoes':('shoes.png',(518,262,774,518)),
    }
    AW,AH=1560,520
    atlas=Image.new('RGBA',(AW,AH),(0,0,0,0)); rect={}
    for mat,(fn,box) in specs.items():
        src=Image.open(texdir/fn).convert('RGBA')
        w,h=box[2]-box[0],box[3]-box[1]
        im=src.resize((w,h),Image.Resampling.NEAREST)
        atlas.paste(im,(box[0],box[1]))
        rect[mat]=(box[0]/AW,box[1]/AH,w/AW,h/AH,w,h)
    if pistol_texture:
        box=(1042,2,1558,518); w,h=box[2]-box[0],box[3]-box[1]
        src=Image.open(pistol_texture).convert('RGBA').resize((w,h),Image.Resampling.LANCZOS)
        atlas.paste(src,(box[0],box[1]))
        rect['pistol']=(box[0]/AW,box[1]/AH,w/AW,h/AH,w,h)
    outpath.parent.mkdir(parents=True,exist_ok=True); atlas.save(outpath,optimize=True)
    return rect,(AW,AH)


def parse_pistol_dae(path):
    ns={'c':'http://www.collada.org/2005/11/COLLADASchema'}
    root=ET.parse(path).getroot(); mesh=root.find('.//c:library_geometries/c:geometry/c:mesh',ns)
    vertices=mesh.find('c:vertices',ns)
    pref=vertices.find("c:input[@semantic='POSITION']",ns).get('source').lstrip('#')
    def source_tuples(ref):
        rid=ref.lstrip('#'); src=mesh.find(f"c:source[@id='{rid}']",ns)
        arr=[float(x) for x in (src.find('c:float_array',ns).text or '').split()]
        acc=src.find('c:technique_common/c:accessor',ns); st=int(acc.get('stride','1'))
        return [tuple(arr[i:i+st]) for i in range(0,len(arr),st)]
    pts=source_tuples('#'+pref)
    tri=mesh.find('c:triangles',ns); inputs=[]
    for inp in tri.findall('c:input',ns):
        inputs.append((inp.get('semantic'),inp.get('source'),int(inp.get('offset','0'))))
    step=1+max(x[2] for x in inputs); packed=[int(x) for x in (tri.find('c:p',ns).text or '').split()]
    voff=next(x[2] for x in inputs if x[0]=='VERTEX')
    texin=next(x for x in inputs if x[0]=='TEXCOORD'); uv=source_tuples(texin[1])
    corners=[]
    for k in range(0,len(packed),step*3):
        tri_c=[]
        for c in range(3):
            off=k+c*step; tri_c.append((packed[off+voff],packed[off+texin[2]]))
        corners.append(tri_c)
    return pts,uv,corners


def dist_point_seg(p,a,b):
    ab=tuple(b[i]-a[i] for i in range(3)); ap=tuple(p[i]-a[i] for i in range(3))
    den=sum(x*x for x in ab)
    t=0 if den<1e-12 else max(0,min(1,sum(ap[i]*ab[i] for i in range(3))/den))
    q=tuple(a[i]+ab[i]*t for i in range(3))
    return math.dist(p,q),t


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('obj',type=pathlib.Path); ap.add_argument('--textures',type=pathlib.Path,required=True); ap.add_argument('--fbx',type=pathlib.Path); ap.add_argument('--pistol-dae',type=pathlib.Path); ap.add_argument('--pistol-texture',type=pathlib.Path); ap.add_argument('--out-lua',type=pathlib.Path,required=True); ap.add_argument('--out-atlas',type=pathlib.Path,required=True); args=ap.parse_args()
    verts,uvs,groups,faces=parse_obj(args.obj)
    rects,(AW,AH)=build_atlas(args.textures,args.out_atlas,args.pistol_texture)

    # Real anatomical pivots derived from the GTA rig helper geometry in the OBJ.
    def bnd(n): return group_bounds(n,groups,verts)
    pelvis=group_center('pelvis',groups,verts)
    root=group_center('root_ground',groups,verts)
    waist=group_center('root_hips',groups,verts)
    spine1=group_center('spine_lower',groups,verts); spine2=group_center('spine_middle',groups,verts); spine3=group_center('spine_upper',groups,verts)
    neck=group_center('head_neck_lower',groups,verts); head=group_center('head_neck_upper',groups,verts)
    ls1=bnd('arm_left_shoulder_1')[0],bnd('arm_left_shoulder_1')[1]
    rs1=bnd('arm_right_shoulder_1')[0],bnd('arm_right_shoulder_1')[1]
    la2=bnd('arm_left_shoulder_2'); ra2=bnd('arm_right_shoulder_2')
    le=bnd('arm_left_elbow'); re=bnd('arm_right_elbow')
    lw=bnd('arm_left_wrist'); rw=bnd('arm_right_wrist')
    lt=bnd('leg_left_thigh'); rt=bnd('leg_right_thigh'); lk=bnd('leg_left_knee'); rk=bnd('leg_right_knee'); la=bnd('leg_left_ankle'); ra=bnd('leg_right_ankle'); lto=bnd('leg_left_toes'); rto=bnd('leg_right_toes')

    P={
      'Root':root,'Waist':waist,'Hips':pelvis,'Spine1':spine1,'Spine2':spine2,'Spine3':spine3,'Neck':neck,'Head':head,
      'LShoulder':(ls1[0][0], group_center('arm_left_shoulder_1',groups,verts)[1], 0.0),
      'LArm':(la2[0][0], group_center('arm_left_shoulder_2',groups,verts)[1], 0.0),
      'LForeArm':(le[0][0], group_center('arm_left_elbow',groups,verts)[1], group_center('arm_left_elbow',groups,verts)[2]),
      'LHand':(lw[0][0], group_center('arm_left_wrist',groups,verts)[1], group_center('arm_left_wrist',groups,verts)[2]),
      'RShoulder':(rs1[1][0], group_center('arm_right_shoulder_1',groups,verts)[1], 0.0),
      'RArm':(ra2[1][0], group_center('arm_right_shoulder_2',groups,verts)[1], 0.0),
      'RForeArm':(re[1][0], group_center('arm_right_elbow',groups,verts)[1], group_center('arm_right_elbow',groups,verts)[2]),
      'RHand':(rw[1][0], group_center('arm_right_wrist',groups,verts)[1], group_center('arm_right_wrist',groups,verts)[2]),
      'LThigh':(group_center('leg_left_thigh',groups,verts)[0], lt[1][1], group_center('leg_left_thigh',groups,verts)[2]),
      'LLeg':(group_center('leg_left_knee',groups,verts)[0], lk[1][1], group_center('leg_left_knee',groups,verts)[2]),
      'LFoot':(group_center('leg_left_ankle',groups,verts)[0], la[1][1], group_center('leg_left_ankle',groups,verts)[2]),
      'LToe':(group_center('leg_left_toes',groups,verts)[0], lto[1][1], group_center('leg_left_toes',groups,verts)[2]),
      'RThigh':(group_center('leg_right_thigh',groups,verts)[0], rt[1][1], group_center('leg_right_thigh',groups,verts)[2]),
      'RLeg':(group_center('leg_right_knee',groups,verts)[0], rk[1][1], group_center('leg_right_knee',groups,verts)[2]),
      'RFoot':(group_center('leg_right_ankle',groups,verts)[0], ra[1][1], group_center('leg_right_ankle',groups,verts)[2]),
      'RToe':(group_center('leg_right_toes',groups,verts)[0], rto[1][1], group_center('leg_right_toes',groups,verts)[2]),
    }
    names=['Root','Waist','Hips','Spine1','Spine2','Spine3','Neck','Head','LShoulder','LArm','LForeArm','LHand','RShoulder','RArm','RForeArm','RHand','LThigh','LLeg','LFoot','LToe','RThigh','RLeg','RFoot','RToe']
    parent_name={'Root':None,'Waist':'Root','Hips':'Waist','Spine1':'Hips','Spine2':'Spine1','Spine3':'Spine2','Neck':'Spine3','Head':'Neck',
      'LShoulder':'Spine3','LArm':'LShoulder','LForeArm':'LArm','LHand':'LForeArm','RShoulder':'Spine3','RArm':'RShoulder','RForeArm':'RArm','RHand':'RForeArm',
      'LThigh':'Hips','LLeg':'LThigh','LFoot':'LLeg','LToe':'LFoot','RThigh':'Hips','RLeg':'RThigh','RFoot':'RLeg','RToe':'RFoot'}
    idx={n:i for i,n in enumerate(names)}
    parents=[]; locals=[]; worlds=[]
    for n in names:
        pn=parent_name[n]; parents.append(idx[pn]+1 if pn else 0)
        if pn:
            a=P[pn]; b=P[n]; lm=trans(b[0]-a[0],b[1]-a[1],b[2]-a[2]); worlds.append(mul(worlds[idx[pn]],lm)); locals.append(lm)
        else:
            lm=trans(*P[n]); worlds.append(lm); locals.append(lm)
    invworld=[inv_rigid(m) for m in worlds]

    # actual mesh vertices only
    visible_faces=[(mat,cs) for mat,cs in faces if mat in rects]
    actual_ids=sorted(set(vi for _,cs in visible_faces for vi,_ in cs)); remap={vi:i+1 for i,vi in enumerate(actual_ids)}; actual=[verts[i-1] for i in actual_ids]
    segments={
      'LArm':('LArm','LForeArm'),'LForeArm':('LForeArm','LHand'), 'RArm':('RArm','RForeArm'),'RForeArm':('RForeArm','RHand'),
      'LThigh':('LThigh','LLeg'),'LLeg':('LLeg','LFoot'),'LFoot':('LFoot','LToe'), 'RThigh':('RThigh','RLeg'),'RLeg':('RLeg','RFoot'),'RFoot':('RFoot','RToe')
    }
    # Prefer the real GTA FBX skin weights when available. The OBJ helper groups
    # give us clean runtime pivots, while the FBX clusters give the actual per-vertex
    # deformation weights. This avoids the long rigid arm rods caused by the old
    # silhouette-based auto-weighting.
    fbx_weights_by_pos={}
    if args.fbx and args.fbx.exists():
        import re
        ft=args.fbx.read_text(errors='replace')
        vm=re.search(r'Vertices:\s*(.*?)\n\s*PolygonVertexIndex:',ft,re.S)
        if vm:
            nums=[float(x) for x in re.findall(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?',vm.group(1))]
            fpts=[]
            for q in range(0,len(nums)-2,3):
                # FBX -> OBJ/runtime: (x,z,-y)
                fpts.append((nums[q],nums[q+2],-nums[q+1]))
            ctrl={}
            cluster_re=re.compile(r'Deformer:\s*"SubDeformer::Cluster ([^"]+)",\s*"Cluster"\s*\{(.*?)(?=\n\s*Deformer:|\n\s*Model:|\n\s*Pose:|\Z)',re.S)
            def map_cluster(n):
                s=n.lower().strip()
                if s=='root ground': return 'Root'
                if s=='root hips': return 'Waist'
                if s=='pelvis': return 'Hips'
                if s=='spine lower': return 'Spine1'
                if s=='spine middle': return 'Spine2'
                if s=='spine upper': return 'Spine3'
                if s=='head neck lower': return 'Neck'
                if s.startswith('head '): return 'Head'
                if s=='arm left shoulder 1': return 'LShoulder'
                if s=='arm left shoulder 2': return 'LArm'
                if s=='arm left elbow': return 'LForeArm'
                if s.startswith('arm left wrist') or s.startswith('arm left finger'): return 'LHand'
                if s=='arm right shoulder 1': return 'RShoulder'
                if s=='arm right shoulder 2': return 'RArm'
                if s=='arm right elbow': return 'RForeArm'
                if s.startswith('arm right wrist') or s.startswith('arm right finger'): return 'RHand'
                if s=='leg left thigh': return 'LThigh'
                if s=='leg left knee': return 'LLeg'
                if s=='leg left ankle': return 'LFoot'
                if s.startswith('leg left toes'): return 'LToe'
                if s=='leg right thigh': return 'RThigh'
                if s=='leg right knee': return 'RLeg'
                if s=='leg right ankle': return 'RFoot'
                if s.startswith('leg right toes'): return 'RToe'
                return None
            for cm in cluster_re.finditer(ft):
                bn=map_cluster(cm.group(1)); block=cm.group(2)
                if not bn: continue
                im=re.search(r'Indexes:\s*(.*?)\n\s*Weights:',block,re.S)
                wm=re.search(r'Weights:\s*(.*?)\n\s*Transform:',block,re.S)
                if not im or not wm: continue
                ids=[int(x) for x in re.findall(r'-?\d+',im.group(1))]
                ws=[float(x) for x in re.findall(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?',wm.group(1))]
                for ci,w in zip(ids,ws):
                    ctrl.setdefault(ci,[]).append((bn,w))
            qmap={}
            for ci,fp in enumerate(fpts): qmap.setdefault(tuple(round(v,3) for v in fp),[]).append(ci)
            for p0 in actual:
                key=tuple(round(v,3) for v in p0); cands=qmap.get(key)
                if not cands:
                    # OBJ is rounded; try a coarser lookup before falling back.
                    key2=tuple(round(v,2) for v in p0)
                    cands=[ci for ci,fp in enumerate(fpts) if tuple(round(v,2) for v in fp)==key2][:2]
                if cands:
                    merged={}
                    for bn,w in ctrl.get(cands[0],[]): merged[bn]=merged.get(bn,0)+w
                    if merged:
                        arr=sorted(merged.items(),key=lambda q:q[1],reverse=True)[:4]
                        sw=sum(w for _,w in arr) or 1
                        fbx_weights_by_pos[key]=[(bn,w/sw) for bn,w in arr]

    pos_first=[];pos_count=[];inf_bone=[];inf_x=[];inf_y=[];inf_z=[];inf_w=[]
    for p in actual:
        x,y,z=p; candidates=[]
        fw=fbx_weights_by_pos.get(tuple(round(v,3) for v in p))
        if fw:
            candidates=fw
        elif y>61.0:
            candidates=[('Head',1.0)]
        elif y>56 and abs(x)>6:
            side='L' if x>0 else 'R'; segs=[side+'Arm',side+'ForeArm']
            dd=[]
            for bn in segs:
                a,b=segments[bn]; d,_=dist_point_seg(p,P[a],P[b]); dd.append((d,bn))
            dd.sort(); d1,b1=dd[0]; d2,b2=dd[1]; w1=1/(d1+0.8); w2=1/(d2+0.8); s=w1+w2; candidates=[(b1,w1/s),(b2,w2/s)]
        elif y<40.5 and abs(x)>1.0:
            side='L' if x>0 else 'R'; segs=[side+'Thigh',side+'Leg',side+'Foot']
            dd=[]
            for bn in segs:
                a,b=segments[bn]; d,_=dist_point_seg(p,P[a],P[b]); dd.append((d,bn))
            dd.sort(); use=dd[:2]; ws=[1/(d+0.7) for d,_ in use]; s=sum(ws); candidates=[(bn,w/s) for w,(d,bn) in zip(ws,use)]
        elif y>55.0: candidates=[('Spine3',0.65),('Neck',0.35)]
        elif y>50.0: candidates=[('Spine2',1.0)]
        elif y>43.0: candidates=[('Spine1',1.0)]
        else: candidates=[('Hips',1.0)]
        pos_first.append(len(inf_bone)+1); pos_count.append(len(candidates))
        for bn,w in candidates:
            bi=idx[bn]; lp=transform(invworld[bi],p)
            inf_bone.append(bi+1);inf_x.append(lp[0]);inf_y.append(lp[1]);inf_z.append(lp[2]);inf_w.append(w)

    corner_pos=[];corner_u=[];corner_v=[];centers=[]
    for mat,cs in visible_faces:
        u0,v0,uw,vh,dw,dh=rects[mat]; pts=[]
        for vi,ti in cs:
            corner_pos.append(remap[vi]); pts.append(verts[vi-1]); u,v=uvs[ti-1] if ti else (0,0)
            u=u-math.floor(u); v=(-v)%1.0
            corner_u.append(u0+(0.5+u*(dw-1))/AW); corner_v.append(v0+(0.5+v*(dh-1))/AH)
        centers.append(tuple(sum(p[d] for p in pts)/3 for d in range(3)))

    # Attach the supplied pistol directly to CJ's RHand bone.  Tune the local
    # remap for a proper in-hand carry pose: source +X becomes runtime +Z
    # (barrel forward), source +Z becomes runtime -X, and the grip is lifted
    # slightly into the palm so the weapon does not hang below the fingers.
    if args.pistol_dae and args.pistol_texture:
        gun_pts,gun_uv,gun_tris=parse_pistol_dae(args.pistol_dae)
        gun_rect=rects['pistol']; u0,v0,uw,vh,dw,dh=gun_rect
        gun_origin=(0.08421711,0.009684331,0.02159989)
        hand=P['RHand']; gun_scale=23.0
        gun_first=len(pos_first)+1
        rhand=idx['RHand']
        def gun_world(gp):
            rx=gp[0]-gun_origin[0]; ry=gp[1]-gun_origin[1]; rz=gp[2]-gun_origin[2]
            # source +X => runtime +Z, source +Z => runtime -X, source +Y => up
            return (hand[0]-rz*gun_scale+0.30,
                    hand[1]+ry*gun_scale+0.55,
                    hand[2]+rx*gun_scale+0.15)
        for gp in gun_pts:
            wp=gun_world(gp)
            pos_first.append(len(inf_bone)+1); pos_count.append(1)
            lp=transform(invworld[rhand],wp)
            inf_bone.append(rhand+1);inf_x.append(lp[0]);inf_y.append(lp[1]);inf_z.append(lp[2]);inf_w.append(1.0)
        for tri_c in gun_tris:
            tri_pts=[]
            for vi,ti in tri_c:
                wp=gun_world(gun_pts[vi]); tri_pts.append(wp)
                corner_pos.append(gun_first+vi)
                u,v=gun_uv[ti][:2]; u=u-math.floor(u); v=(-v)%1.0
                corner_u.append(u0+(0.5+u*(dw-1))/AW); corner_v.append(v0+(0.5+v*(dh-1))/AH)
            centers.append(tuple(sum(pp[d] for pp in tri_pts)/3 for d in range(3)))

    yaws={'down':0.,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}; orders={}
    for k,yaw in yaws.items():
        c,s=math.cos(yaw),math.sin(yaw); ds=[(x*s+z*c,i+1) for i,(x,y,z) in enumerate(centers)]; ds.sort(key=lambda q:q[0]); orders[k]=[i for _,i in ds]
    mins=[min(p[d] for p in actual) for d in range(3)]; maxs=[max(p[d] for p in actual) for d in range(3)]
    anim={n:idx[n]+1 for n in names if n!='Root'}

    args.out_lua.parent.mkdir(parents=True,exist_ok=True)
    with args.out_lua.open('w') as out:
        out.write('-- GENERATED from CarlJohnson-GTASA.obj + named GTA rig helper groups\nreturn {\n')
        out.write(f'  boneCount = {len(names)},\n  positionCount = {len(pos_first)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(centers)},\n')
        lua_strings('boneName',names,out);lua_array('boneParent',parents,out);lua_array('boneLocal',[v for m in locals for v in m],out)
        lua_array('posFirst',pos_first,out);lua_array('posCount',pos_count,out);lua_array('infBone',inf_bone,out);lua_array('infX',inf_x,out);lua_array('infY',inf_y,out);lua_array('infZ',inf_z,out);lua_array('infW',inf_w,out)
        lua_array('cornerPos',corner_pos,out);lua_array('cornerU',corner_u,out);lua_array('cornerV',corner_v,out)
        out.write('  order = {\n')
        for k in ('down','left','up','right'):
            out.write(f'    {k} = {{\n'); vals=orders[k]
            for i in range(0,len(vals),20): out.write('      '+', '.join(map(str,vals[i:i+20]))+',\n')
            out.write('    },\n')
        out.write('  },\n  animBone = {\n')
        for n,i in anim.items(): out.write(f'    {n} = {i},\n')
        out.write('  },\n');lua_array('bounds',mins+maxs,out,6);out.write('}\n')
    print('CJ bones',len(names),'positions',len(actual),'tris',len(centers),'bounds',mins,maxs,'fbx weighted',len(fbx_weights_by_pos))

if __name__=='__main__': main()
