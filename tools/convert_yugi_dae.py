#!/usr/bin/env python3
from __future__ import annotations
import argparse, math, pathlib, xml.etree.ElementTree as ET
from dataclasses import dataclass
from PIL import Image
NS={'c':'http://www.collada.org/2005/11/COLLADASchema'}
def ident(): return [1.,0,0,0, 0,1.,0,0, 0,0,1.,0, 0,0,0,1.]
def mul(a,b):
 o=[0.]*16
 for r in range(4):
  for c in range(4): o[r*4+c]=sum(a[r*4+k]*b[k*4+c] for k in range(4))
 return o
def trans(x,y,z): m=ident();m[3]=x;m[7]=y;m[11]=z;return m
def scale(x,y,z): m=ident();m[0]=x;m[5]=y;m[10]=z;return m
def rot_axis(x,y,z,deg):
 n=math.sqrt(x*x+y*y+z*z)
 if n<1e-12:return ident()
 x,y,z=x/n,y/n,z/n;a=math.radians(deg);c=math.cos(a);s=math.sin(a);C=1-c
 return [x*x*C+c,x*y*C-z*s,x*z*C+y*s,0,y*x*C+z*s,y*y*C+c,y*z*C-x*s,0,z*x*C-y*s,z*y*C+x*s,z*z*C+c,0,0,0,0,1]
def transform_point(m,p):
 x,y,z=p;return (m[0]*x+m[1]*y+m[2]*z+m[3],m[4]*x+m[5]*y+m[6]*z+m[7],m[8]*x+m[9]*y+m[10]*z+m[11])
def node_local(node):
 m=ident()
 for ch in list(node):
  tag=ch.tag.split('}')[-1]
  if tag not in ('translate','rotate','scale','matrix'):continue
  v=[float(x) for x in (ch.text or '').split()]
  if tag=='translate':t=trans(*v[:3])
  elif tag=='rotate':t=rot_axis(*v[:4])
  elif tag=='scale':t=scale(*v[:3])
  else:t=[v[c*4+r] for r in range(4) for c in range(4)]
  m=mul(m,t)
 return m
def float_source(src):
 arr=src.find('c:float_array',NS); vals=[float(x) for x in (arr.text or '').split()]; acc=src.find('c:technique_common/c:accessor',NS); st=int(acc.get('stride','1')); return vals,st
def find_source(parent,ref):
 rid=ref[1:] if ref.startswith('#') else ref; el=parent.find(f"c:source[@id='{rid}']",NS)
 if el is None: raise ValueError('missing '+rid)
 return el
def lua_num(x):
 if isinstance(x,int):return str(x)
 if abs(x)<5e-10:x=0.
 return f'{x:.7g}'
def lua_array(name,vals,out,per=16):
 out.write(f'  {name} = {{\n')
 for i in range(0,len(vals),per):out.write('    '+', '.join(lua_num(v) for v in vals[i:i+per])+',\n')
 out.write('  },\n')
def lua_strings(name,vals,out,per=8):
 import json;out.write(f'  {name} = {{\n')
 for i in range(0,len(vals),per):out.write('    '+', '.join(json.dumps(v) for v in vals[i:i+per])+',\n')
 out.write('  },\n')
@dataclass
class Bone:sid:str;name:str;parent:int;local:list;world:list
def collect_bones(root):
 vs=root.find('.//c:library_visual_scenes/c:visual_scene',NS);bones=[];sid_to_idx={}
 def walk(node,pw,pb):
  local=node_local(node);world=mul(pw,local);this=pb
  sid=node.get('sid')
  if node.get('type')=='JOINT' and sid:
   idx=len(bones);sid_to_idx[sid]=idx;bones.append(Bone(sid,node.get('name') or sid,pb,local,world));this=idx
  for ch in node.findall('c:node',NS):walk(ch,world,this)
 for n in vs.findall('c:node',NS):walk(n,ident(),-1)
 return bones,sid_to_idx
def build_atlas(texdir,outpath):
 AW,AH=512,256
 spec={'body':('Ch_MutoYugi01_body_tex.png',(0,0,256,256)), 'face':('Ch_MutoYugi01_face_tex.png',(256,0,384,256))}
 atlas=Image.new('RGBA',(AW,AH),(0,0,0,0));rects={}
 for key,(fn,box) in spec.items():
  im=Image.open(texdir/fn).convert('RGBA'); w,h=box[2]-box[0],box[3]-box[1]; im=im.resize((w,h),Image.Resampling.LANCZOS); atlas.paste(im,(box[0],box[1]));rects[key]=(box[0]/AW,box[1]/AH,w/AW,h/AH)
 outpath.parent.mkdir(parents=True,exist_ok=True);atlas.save(outpath,optimize=True);return rects,(AW,AH)
def main():
 ap=argparse.ArgumentParser();ap.add_argument('dae',type=pathlib.Path);ap.add_argument('--textures',type=pathlib.Path,required=True);ap.add_argument('--out-lua',type=pathlib.Path,required=True);ap.add_argument('--out-atlas',type=pathlib.Path,required=True);a=ap.parse_args()
 root=ET.parse(a.dae).getroot();bones,sid_to_idx=collect_bones(root);rects,(AW,AH)=build_atlas(a.textures,a.out_atlas)
 geoms={g.get('id'):g for g in root.findall('.//c:library_geometries/c:geometry',NS)};controllers=[]
 for c in root.findall('.//c:library_controllers/c:controller',NS):
  skin=c.find('c:skin',NS);controllers.append((c,skin,geoms[skin.get('source').lstrip('#')]))
 pos_first=[];pos_count=[];inf_bone=[];inf_x=[];inf_y=[];inf_z=[];inf_w=[];corner_pos=[];corner_u=[];corner_v=[];tri_centers=[];all_bind=[]
 matmap={'VisualMaterial0':'body','VisualMaterial10':'face'}
 for ctrl,skin,geom in controllers:
  mesh=geom.find('c:mesh',NS);verts=mesh.find('c:vertices',NS);pos_ref=next(i.get('source') for i in verts.findall('c:input',NS) if i.get('semantic')=='POSITION');ps=find_source(mesh,pos_ref);pv,pstride=float_source(ps);positions=[tuple(pv[i:i+3]) for i in range(0,len(pv),pstride)];base_pos=len(pos_first);all_bind.extend(positions)
  srcs={s.get('id'):s for s in skin.findall('c:source',NS)};j_inputs={i.get('semantic'):i.get('source').lstrip('#') for i in skin.find('c:joints',NS).findall('c:input',NS)};joint_names=(srcs[j_inputs['JOINT']].find('c:Name_array',NS).text or '').split();ib_vals,ib_stride=float_source(srcs[j_inputs['INV_BIND_MATRIX']]);invbind=[[ib_vals[i:i+16][c*4+r] for r in range(4) for c in range(4)] for i in range(0,len(ib_vals),ib_stride)];bind_shape=ident();bsm=skin.find('c:bind_shape_matrix',NS)
  if bsm is not None:
   vals=[float(x) for x in (bsm.text or '').split()]
   if len(vals)==16:bind_shape=vals
  vw=skin.find('c:vertex_weights',NS);vwi={i.get('semantic'):(i.get('source').lstrip('#'),int(i.get('offset','0'))) for i in vw.findall('c:input',NS)};stride=1+max(v[1] for v in vwi.values());jsrc,joff=vwi['JOINT'];wsrc,woff=vwi['WEIGHT'];weight_vals,_=float_source(srcs[wsrc]);counts=[int(x) for x in (vw.find('c:vcount',NS).text or '').split()];packed=[int(x) for x in (vw.find('c:v',NS).text or '').split()];cur=0
  for vi,cnt in enumerate(counts):
   influences=[]
   for _ in range(cnt):
    ji=packed[cur+joff];wi=packed[cur+woff];cur+=stride;w=weight_vals[wi]
    if w>1e-7:influences.append((ji,w))
   influences.sort(key=lambda q:q[1],reverse=True);influences=influences[:4];sw=sum(w for _,w in influences) or 1.;pos_first.append(len(inf_bone)+1);pos_count.append(len(influences));p=transform_point(bind_shape,positions[vi])
   for ji,w in influences:
    sid=joint_names[ji];bi=sid_to_idx[sid];lp=transform_point(invbind[ji],p);inf_bone.append(bi+1);inf_x.append(lp[0]);inf_y.append(lp[1]);inf_z.append(lp[2]);inf_w.append(w/sw)
  source_cache={}
  def source_tuples(ref):
   rid=ref.lstrip('#')
   if rid not in source_cache:
    vals,st=float_source(find_source(mesh,ref));source_cache[rid]=[tuple(vals[i:i+st]) for i in range(0,len(vals),st)]
   return source_cache[rid]
  # Some exporters (including this Yugi DAE) place NORMAL/TEXCOORD on the
  # <vertices> element rather than as direct <triangles> inputs.  Preserve
  # those vertex attributes instead of silently falling back to UV (0,0).
  vertex_inputs={i.get('semantic'):i.get('source') for i in verts.findall('c:input',NS)}
  vertex_tex_ref=vertex_inputs.get('TEXCOORD')
  vertex_texcoords=source_tuples(vertex_tex_ref) if vertex_tex_ref else None
  for tri in mesh.findall('c:triangles',NS):
   material=matmap.get(tri.get('material'), 'body'); inputs=[(i.get('semantic'),i.get('source'),int(i.get('offset','0')),i.get('set')) for i in tri.findall('c:input',NS)];step=1+max(x[2] for x in inputs);idx=[int(x) for x in (tri.find('c:p',NS).text or '').split()];voff=next(x[2] for x in inputs if x[0]=='VERTEX');texin=next((x for x in inputs if x[0]=='TEXCOORD' and x[3] in (None,'0')),None);texcoords=source_tuples(texin[1]) if texin else vertex_texcoords;u0,v0,uw,vh=rects[material];dw=uw*AW;dh=vh*AH
   for k in range(0,len(idx),step*3):
    tri_ps=[]
    for cidx in range(3):
     off=k+cidx*step;pi=idx[off+voff];corner_pos.append(base_pos+pi+1);tri_ps.append(positions[pi])
     if texin:
      ti=idx[off+texin[2]]
     else:
      ti=pi
     u,v=(texcoords[ti][:2] if texcoords else (0.,0.));u=u-math.floor(u);v=v-math.floor(v)
     # COLLADA/SMD UV V is already authored for the source images used by this
     # asset.  Keep V as-authored; LÖVE's mesh UV convention matches it here.
     corner_u.append(u0+(0.5+u*(dw-1))/AW);corner_v.append(v0+(0.5+v*(dh-1))/AH)
    tri_centers.append(tuple(sum(p[d] for p in tri_ps)/3 for d in range(3)))
 yaws={'down':0.,'left':-math.pi/2,'up':math.pi,'right':math.pi/2};orders={}
 for name,yaw in yaws.items():
  c,s=math.cos(yaw),math.sin(yaw);depths=[]
  for ti,(x,y,z) in enumerate(tri_centers):depths.append((x*s+z*c,ti+1))
  depths.sort(key=lambda q:q[0]);orders[name]=[ti for _,ti in depths]
 mins=[min(p[d] for p in all_bind) for d in range(3)];maxs=[max(p[d] for p in all_bind) for d in range(3)];names=[b.name for b in bones]
 alias={'Hips':'Hips','Spine1':'Spine','Spine2':'Spine1','Neck':'Neck','Head':'Head','LShoulder':'LeftShoulder','LArm':'LeftArm','LForeArm':'LeftForeArm','LHand':'LeftHand','LFingerB1':'LeftFinger','RShoulder':'RightShoulder','RArm':'RightArm','RForeArm':'RightForeArm','RHand':'RightHand','RFingerB1':'RightFinger','LThigh':'LeftUpLeg','LLeg':'LeftLeg','LFoot':'LeftFoot','LToe':'LeftToeBase','RThigh':'RightUpLeg','RLeg':'RightLeg','RFoot':'RightFoot','RToe':'RightToeBase'}
 anim={k:names.index(v)+1 for k,v in alias.items() if v in names}
 a.out_lua.parent.mkdir(parents=True,exist_ok=True)
 with a.out_lua.open('w',encoding='utf8') as out:
  out.write('-- GENERATED YUGI runtime data\nreturn {\n');out.write(f'  boneCount = {len(bones)},\n  positionCount = {len(pos_first)},\n  cornerCount = {len(corner_pos)},\n  triangleCount = {len(tri_centers)},\n');lua_strings('boneName',names,out);lua_array('boneParent',[b.parent+1 if b.parent>=0 else 0 for b in bones],out);lua_array('boneLocal',[v for b in bones for v in b.local],out);lua_array('posFirst',pos_first,out);lua_array('posCount',pos_count,out);lua_array('infBone',inf_bone,out);lua_array('infX',inf_x,out);lua_array('infY',inf_y,out);lua_array('infZ',inf_z,out);lua_array('infW',inf_w,out);lua_array('cornerPos',corner_pos,out);lua_array('cornerU',corner_u,out);lua_array('cornerV',corner_v,out);out.write('  order = {\n')
  for k in ('down','left','up','right'):
   out.write(f'    {k} = {{\n');vals=orders[k]
   for i in range(0,len(vals),20):out.write('      '+', '.join(map(str,vals[i:i+20]))+',\n')
   out.write('    },\n')
  out.write('  },\n  animBone = {\n')
  for n,i in anim.items():out.write(f'    {n} = {i},\n')
  out.write('  },\n');lua_array('bounds',mins+maxs,out,6);out.write('}\n')
 print('bones',len(bones),'positions',len(pos_first),'tris',len(tri_centers),'bounds',mins,maxs,'anim',anim)
if __name__=='__main__':main()
