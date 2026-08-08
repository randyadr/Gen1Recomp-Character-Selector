#!/usr/bin/env python3
from __future__ import annotations
import argparse, math, pathlib, re
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

def rotx(a):
    c,s=math.cos(a),math.sin(a); return [1,0,0,0, 0,c,-s,0, 0,s,c,0, 0,0,0,1]
def roty(a):
    c,s=math.cos(a),math.sin(a); return [c,0,s,0, 0,1,0,0, -s,0,c,0, 0,0,0,1]
def rotz(a):
    c,s=math.cos(a),math.sin(a); return [c,-s,0,0, s,c,0,0, 0,0,1,0, 0,0,0,1]
def euler(rx,ry,rz):
    # Source/Valve SMD convention; bind pose in this asset is zero-rotation,
    # but keep complete support for future animation/rest revisions.
    return mul(mul(rotz(rz), roty(ry)), rotx(rx))
def local_matrix(pos,rot): return mul(trans(*pos), euler(*rot))
def transform(m,p):
    x,y,z=p
    return (m[0]*x+m[1]*y+m[2]*z+m[3], m[4]*x+m[5]*y+m[6]*z+m[7], m[8]*x+m[9]*y+m[10]*z+m[11])
def inv_rigid(m):
    # inverse of rigid rotation+translation matrix
    r=[m[0],m[1],m[2], m[4],m[5],m[6], m[8],m[9],m[10]]
    rt=[r[0],r[3],r[6], r[1],r[4],r[7], r[2],r[5],r[8]]
    tx,ty,tz=m[3],m[7],m[11]
    return [rt[0],rt[1],rt[2],-(rt[0]*tx+rt[1]*ty+rt[2]*tz),
            rt[3],rt[4],rt[5],-(rt[3]*tx+rt[4]*ty+rt[5]*tz),
            rt[6],rt[7],rt[8],-(rt[6]*tx+rt[7]*ty+rt[8]*tz),
            0,0,0,1]

# Source Naruto SMD is Z-up and faces -Y. Runtime convention is Y-up, +Z forward.
C=[1,0,0,0, 0,0,1,0, 0,-1,0,0, 0,0,0,1]
CINV=[1,0,0,0, 0,0,-1,0, 0,1,0,0, 0,0,0,1]
def to_runtime_matrix(m): return mul(mul(C,m),CINV)
def to_runtime_point(p): return transform(C,p)

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

def build_atlas(texdir,outpath):
    AW,AH=2048,1024
    specs={
        'body':('body.png',(0,0,1024,1024)),
        'head':('head.png',(1024,0,1536,512)),
        'eye':('eye.png',(1536,0,2048,512)),
    }
    atlas=Image.new('RGBA',(AW,AH),(0,0,0,0)); rect={}
    for key,(fn,box) in specs.items():
        im=Image.open(texdir/fn).convert('RGBA')
        w,h=box[2]-box[0],box[3]-box[1]
        if im.size!=(w,h): im=im.resize((w,h),Image.Resampling.LANCZOS)
        atlas.paste(im,(box[0],box[1]))
        rect[key]=(box[0]/AW,box[1]/AH,w/AW,h/AH,w,h)
    outpath.parent.mkdir(parents=True,exist_ok=True); atlas.save(outpath,optimize=True)
    return rect,(AW,AH)

def parse_smd(path):
    lines=path.read_text(errors='replace').splitlines(); i=0
    nodes={}; bind={}; tris=[]
    while i<len(lines):
        line=lines[i].strip(); i+=1
        if line=='nodes':
            while i<len(lines) and lines[i].strip()!='end':
                m=re.match(r'\s*(\d+)\s+"(.*)"\s+(-?\d+)\s*$',lines[i]); i+=1
                if m: nodes[int(m.group(1))]=(m.group(2),int(m.group(3)))
            i+=1
        elif line=='skeleton':
            curtime=None
            while i<len(lines) and lines[i].strip()!='end':
                s=lines[i].strip(); i+=1
                if s.startswith('time '): curtime=int(s.split()[1]); continue
                if curtime!=0: continue
                p=s.split()
                if len(p)>=7:
                    bid=int(p[0]); bind[bid]=((float(p[1]),float(p[2]),float(p[3])),(float(p[4]),float(p[5]),float(p[6])))
            i+=1
        elif line=='triangles':
            while i<len(lines) and lines[i].strip()!='end':
                material=lines[i].strip(); i+=1
                verts=[]
                for _ in range(3):
                    p=lines[i].split(); i+=1
                    root=int(p[0]); pos=tuple(map(float,p[1:4])); norm=tuple(map(float,p[4:7])); uv=tuple(map(float,p[7:9])); nlinks=int(p[9]) if len(p)>9 else 0
                    links=[]; at=10
                    for j in range(nlinks):
                        links.append((int(p[at]),float(p[at+1]))); at+=2
                    if not links: links=[(root,1.0)]
                    verts.append((pos,norm,uv,links))
                tris.append((material,verts))
            i+=1
    return nodes,bind,tris

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('smd',type=pathlib.Path); ap.add_argument('--textures',type=pathlib.Path,required=True); ap.add_argument('--out-lua',type=pathlib.Path,required=True); ap.add_argument('--out-atlas',type=pathlib.Path,required=True); args=ap.parse_args()
    nodes,bind,tris=parse_smd(args.smd); rects,(AW,AH)=build_atlas(args.textures,args.out_atlas)
    ids=sorted(nodes); id_to_idx={bid:i for i,bid in enumerate(ids)}
    names=[nodes[i][0] for i in ids]; parents=[]; source_worlds=[]
    source_locals=[]
    for bid in ids:
        name,parent_id=nodes[bid]; pos,rot=bind.get(bid,((0,0,0),(0,0,0))); lm=local_matrix(pos,rot); source_locals.append(lm)
        if parent_id>=0 and parent_id in id_to_idx:
            pi=id_to_idx[parent_id]; source_worlds.append(mul(source_worlds[pi],lm))
        else:
            source_worlds.append(lm)
    worlds=[to_runtime_matrix(m) for m in source_worlds]
    locals=[]
    for idx,bid in enumerate(ids):
        parent_id=nodes[bid][1]
        if parent_id>=0 and parent_id in id_to_idx:
            pi=id_to_idx[parent_id]; parents.append(pi+1); locals.append(mul(inv_rigid(worlds[pi]),worlds[idx]))
        else:
            parents.append(0); locals.append(worlds[idx])
    invworld=[inv_rigid(m) for m in worlds]
    pos_first=[];pos_count=[];inf_bone=[];inf_x=[];inf_y=[];inf_z=[];inf_w=[]
    corner_pos=[];corner_u=[];corner_v=[];tri_centers=[];original_positions=[]
    def matkey(mat):
        s=mat.lower()
        if 'eye' in s: return 'eye'
        if 'head' in s: return 'head'
        return 'body'
    for material,verts in tris:
        key=matkey(material); u0,v0,uw,vh,dw,dh=rects[key]
        tri_pts=[]
        for pos,norm,uv,links in verts:
            pos=to_runtime_point(pos)
            pi=len(pos_first); original_positions.append(pos); tri_pts.append(pos)
            links=sorted(links,key=lambda x:x[1],reverse=True)[:4]; sw=sum(w for _,w in links) or 1
            pos_first.append(len(inf_bone)+1); pos_count.append(len(links))
            for bid,w in links:
                bi=id_to_idx[bid]; lp=transform(invworld[bi],pos)
                inf_bone.append(bi+1); inf_x.append(lp[0]); inf_y.append(lp[1]); inf_z.append(lp[2]); inf_w.append(w/sw)
            corner_pos.append(pi+1)
            u,v=uv
            # Valve/SMD texture V runs opposite to LÖVE/Image atlas row order.
            # Wrap U normally, but wrap+flip V so the source's top of texture
            # maps to the atlas top. This is especially important for Yugi's
            # face sheet: unflipped V sampled the closed-eye lower half.
            u=u-math.floor(u)
            v=(-v) % 1.0
            corner_u.append(u0+(0.5+u*(dw-1))/AW)
            corner_v.append(v0+(0.5+v*(dh-1))/AH)
        tri_centers.append(tuple(sum(p[d] for p in tri_pts)/3 for d in range(3)))
    # validate exact rest reconstruction
    maxerr=0; avg=0
    for pi,pos in enumerate(original_positions):
        out=[0,0,0]; first=pos_first[pi]-1
        for j in range(first,first+pos_count[pi]):
            bi=inf_bone[j]-1; tp=transform(worlds[bi],(inf_x[j],inf_y[j],inf_z[j])); w=inf_w[j]
            for d in range(3): out[d]+=tp[d]*w
        e=math.dist(pos,out); avg+=e; maxerr=max(maxerr,e)
    avg/=max(1,len(original_positions))
    yaws={'down':0.,'left':-math.pi/2,'up':math.pi,'right':math.pi/2}; orders={}
    for name,yaw in yaws.items():
        c,s=math.cos(yaw),math.sin(yaw); depths=[]
        for ti,(x,y,z) in enumerate(tri_centers): depths.append((x*s+z*c,ti+1))
        depths.sort(key=lambda q:q[0]); orders[name]=[ti for _,ti in depths]
    mins=[min(p[d] for p in original_positions) for d in range(3)]; maxs=[max(p[d] for p in original_positions) for d in range(3)]
    alias={
        'Hips':'Bip01 Pelvis','Spine1':'Bip01 Spine','Spine2':'Bip01 Spine1','Spine3':'Bip01 Spine2',
        'Neck':'Bip01 Neck','Head':'Bip01 Head',
        'LShoulder':'Bip01 L Arm','LArm':'Bip01 L Arm1','LForeArm':'Bip01 L Arm2','LHand':'Bip01 L Hand',
        'LFingerA1':'L thumb','LFingerA2':'L thumb2','LFingerB1':'L pointer','LFingerB2':'L pointer2','LFingerB3':'L pointer3',
        'LFingerC1':'L middle','LFingerC2':'L middle2','LFingerC3':'L middle3','LFingerD1':'L ring','LFingerD2':'L ring2','LFingerD3':'L ring3',
        'LFingerE1':'L pinky','LFingerE2':'L pinky2','LFingerE3':'L pinky3',
        'RShoulder':'Bip01 R Arm','RArm':'Bip01 R Arm1','RForeArm':'Bip01 R Arm2','RHand':'Bip01 R Hand',
        'RFingerA1':'R thumb','RFingerA2':'R thumb2','RFingerB1':'R pointer','RFingerB2':'R pointer2','RFingerB3':'R pointer3',
        'RFingerC1':'R middle','RFingerC2':'R middle2','RFingerC3':'R middle3','RFingerD1':'R ring','RFingerD2':'R ring2','RFingerD3':'R ring3',
        'RFingerE1':'R pinky','RFingerE2':'R pinky2','RFingerE3':'R pinky3',
        'LThigh':'Bip01 L Leg','LLeg':'Bip01 L Leg1','LFoot':'Bip01 L Foot','LToe':'Bip01 L Toe1',
        'RThigh':'Bip01 R Leg','RLeg':'Bip01 R Leg1','RFoot':'Bip01 R Foot','RToe':'Bip01 R Toe1',
    }
    anim={k:names.index(v)+1 for k,v in alias.items() if v in names}
    args.out_lua.parent.mkdir(parents=True,exist_ok=True)
    with args.out_lua.open('w') as out:
        out.write('-- GENERATED from Naruto.smd -- exact SMD bind/weights/UVs, converted to runtime Y-up/+Z-forward\nreturn {\n')
        out.write(f'  boneCount = {len(ids)},\n  positionCount = {len(pos_first)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(tris)},\n')
        lua_strings('boneName',names,out); lua_array('boneParent',parents,out); lua_array('boneLocal',[v for m in locals for v in m],out); lua_array('posFirst',pos_first,out); lua_array('posCount',pos_count,out); lua_array('infBone',inf_bone,out); lua_array('infX',inf_x,out); lua_array('infY',inf_y,out); lua_array('infZ',inf_z,out); lua_array('infW',inf_w,out); lua_array('cornerPos',corner_pos,out); lua_array('cornerU',corner_u,out); lua_array('cornerV',corner_v,out)
        out.write('  order = {\n')
        for k in ('down','left','up','right'):
            out.write(f'    {k} = {{\n'); vals=orders[k]
            for q in range(0,len(vals),20): out.write('      '+', '.join(map(str,vals[q:q+20]))+',\n')
            out.write('    },\n')
        out.write('  },\n  animBone = {\n')
        for n,i in anim.items(): out.write(f'    {n} = {i},\n')
        out.write('  },\n'); lua_array('bounds',mins+maxs,out,6); out.write('}\n')
    print('bones',len(ids),'positions',len(pos_first),'tris',len(tris),'bounds',mins,maxs,'rest avg err',avg,'max',maxerr,'anim',anim)
if __name__=='__main__': main()
