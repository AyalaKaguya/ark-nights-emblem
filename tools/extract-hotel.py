"""Read-only extraction of the PC client's 2026 ArkODC scene. Never writes to the client.

The LZ4AK byte rearrangement below is from isHarryh/Ark-Unpacker (BSD-3-Clause),
Copyright (c) 2022, Harry Huang. The source license is saved beside this script.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import copy
import hashlib
import sys
import numpy as np
from UnityPy.helpers.MeshHelper import MeshHandler
from PIL import Image

import lz4.block
import UnityPy
from UnityPy.enums.BundleFile import CompressionFlags
from UnityPy.helpers import CompressionHelper


def decompress_lz4ak(data, usize):
    d = bytearray(data)
    ip = op = 0
    while ip < len(d):
        lit, mat = d[ip] & 15, (d[ip] >> 4) & 15
        d[ip] = (lit << 4) | mat
        ip += 1
        if lit == 15:
            while ip < len(d):
                b = d[ip]; ip += 1; lit += b
                if b != 255: break
        ip += lit; op += lit
        if op >= usize: break
        off = (d[ip] << 8) | d[ip + 1]
        d[ip] = off & 255; d[ip + 1] = off >> 8; ip += 2
        if mat == 15:
            while ip < len(d):
                b = d[ip]; ip += 1; mat += b
                if b != 255: break
        op += mat + 4
    return lz4.block.decompress(bytes(d), usize)


CompressionHelper.DECOMPRESSION_MAP[CompressionFlags.LZHAM] = decompress_lz4ak
DEFAULT_CLIENT = Path(r"C:\Program Files\Hypergryph Launcher\games\Arknights\Arknights_Data\StreamingAssets\AB\Windows")
SCENE_SUB = "scenes/arkvent/ark_odc_act53side_main"


def jsonable(value):
    if value is None or isinstance(value, (str, int, float, bool)): return value
    if all(hasattr(value, k) for k in 'rgba'): return {k:float(getattr(value,k)) for k in 'rgba'}
    if isinstance(value, dict): return {str(k): jsonable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)): return [jsonable(v) for v in value]
    if hasattr(value, "m_PathID"): return {"pathId": value.m_PathID, "fileId": value.m_FileID}
    if hasattr(value, "__dict__"): return {k: jsonable(v) for k, v in vars(value).items() if not k.startswith("_") and k != "object_reader"}
    return str(value)


def vec(v, count=3):
    return [float(getattr(v, k)) for k in "xyzw"[:count]]


def object_id(obj):
    return f"{getattr(obj.assets_file, 'name', '')}:{obj.path_id}"


def export_scene(env, out, qa_out):
    objects = list(env.objects)
    scene_objects = [o for o in objects if "ark_odc_act53side_main" in o.assets_file.name and "scene_data" not in o.assets_file.name]
    # Scene serialized-file names may be CAB hashes, so select the scene via its abundant GameObjects.
    scene_file = next(o.assets_file for o in objects if o.type.name == "GameObject" and o.read().m_Name == "SceneRoot")
    scene_objects = list(scene_file.objects.values())
    gos = {o.path_id: o.read() for o in scene_objects if o.type.name == "GameObject"}
    trans = {o.path_id: o.read() for o in scene_objects if o.type.name == "Transform"}
    tf_by_go = {t.m_GameObject.m_PathID: tid for tid, t in trans.items()}
    filters = {o.read().m_GameObject.m_PathID: o.read() for o in scene_objects if o.type.name == "MeshFilter"}
    world_cache = {}
    def world(tid):
        if not tid or tid not in trans: return np.eye(4)
        if tid in world_cache: return world_cache[tid]
        t = trans[tid]; x,y,z,w = vec(t.m_LocalRotation,4); p=vec(t.m_LocalPosition); s=vec(t.m_LocalScale)
        m = np.array([[1-2*y*y-2*z*z,2*x*y-2*z*w,2*x*z+2*y*w,p[0]], [2*x*y+2*z*w,1-2*x*x-2*z*z,2*y*z-2*x*w,p[1]], [2*x*z-2*y*w,2*y*z+2*x*w,1-2*x*x-2*y*y,p[2]], [0,0,0,1]], dtype=np.float64)
        m[:3,:3] *= np.array(s)[None,:]
        result=world(t.m_Father.m_PathID)@m; world_cache[tid]=result; return result
    def hierarchy(gid):
        result=[];tid=tf_by_go.get(gid)
        while tid and tid in trans:
            t=trans[tid];go=gos.get(t.m_GameObject.m_PathID)
            if go: result.append(go.m_Name)
            tid=t.m_Father.m_PathID
        return list(reversed(result))
    def active(gid):
        tid=tf_by_go.get(gid)
        while tid and tid in trans:
            t=trans[tid];go=gos.get(t.m_GameObject.m_PathID)
            if go and not go.m_IsActive: return False
            tid=t.m_Father.m_PathID
        return True
    texture_dir=out/'textures';texture_dir.mkdir(exist_ok=True)
    textures={};materials={};mesh_cache={};chunks={};instances=[];failures=[]
    def texture(ptr):
        if not ptr or not ptr.m_PathID: return None
        try:
            obj=ptr.deref();tid=object_id(obj)
            if tid in textures: return textures[tid]['path']
            d=ptr.read();name=re.sub(r'[^\w.-]+','_',d.m_Name)
            filename=f'{name}_{d.object_reader.path_id}.png'
            d.image.save(texture_dir/filename)
            path=f'/maps/hotel/textures/{filename}'
            textures[tid]={'id':tid,'name':d.m_Name,'path':path,'width':d.m_Width,'height':d.m_Height,'format':int(d.m_TextureFormat)}
            return path
        except Exception as exc:
            failures.append({'kind':'texture','pathId':str(ptr.m_PathID),'error':str(exc)[:300]});return None
    def material(ptr):
        if not ptr or not ptr.m_PathID: return None
        try:
            obj=ptr.deref();mid=object_id(obj)
            if mid in materials: return mid
            d=ptr.read();saved=d.m_SavedProperties
            envs={};paths={}
            for key,e in saved.m_TexEnvs:
                path=texture(e.m_Texture)
                envs[key]={'path':path,'scale':vec(e.m_Scale,2),'offset':vec(e.m_Offset,2)}
                if path:paths[key]=path
            try:shader=d.m_Shader.read().m_Name
            except Exception:shader='unresolved'
            materials[mid]={'id':mid,'name':d.m_Name,'shader':shader,'textures':paths,'textureEnvs':envs,'floats':dict(saved.m_Floats),'colors':{k:jsonable(v) for k,v in saved.m_Colors},'renderQueue':d.m_CustomRenderQueue}
            return mid
        except Exception as exc:failures.append({'kind':'material','pathId':str(ptr.m_PathID),'error':str(exc)[:300]});return None
    def mesh_data(ptr):
        obj=ptr.deref();key=object_id(obj)
        if key not in mesh_cache:
            d=ptr.read();h=MeshHandler(d);h.process();mesh_cache[key]=(d,h,h.get_triangles())
        return key,mesh_cache[key]
    for o in scene_objects:
        if o.type.name!='MeshRenderer':continue
        r=o.read();gid=r.m_GameObject.m_PathID;go=gos[gid];mf=filters.get(gid)
        if not mf or not mf.m_Mesh.m_PathID:continue
        try:key,(d,h,tris)=mesh_data(mf.m_Mesh)
        except Exception as exc:failures.append({'kind':'mesh','name':go.m_Name,'error':str(exc)[:300]});continue
        sb=r.m_StaticBatchInfo;static=sb.subMeshCount>0;first=sb.firstSubMesh if static else 0
        matrix=np.eye(4) if static else world(tf_by_go.get(gid));vertices=np.asarray(h.m_Vertices,dtype=np.float64)
        normals=np.asarray(h.m_Normals,dtype=np.float64)[:,:3] if h.m_Normals else None
        uv=h.m_UV0 or [(0,0)]*len(vertices);uv2=h.m_UV1 or uv;colors=h.m_Colors
        lm=r.m_LightmapIndex if r.m_LightmapIndex<65534 else -1
        st=[1,1,0,0] if static else vec(r.m_LightmapTilingOffset,4)
        is_active=active(gid) and r.m_Enabled
        node_indices=[];node_min=np.array([np.inf]*3);node_max=-node_min
        for slot,mref in enumerate(r.m_Materials):
            sub=first+slot
            if sub>=len(tris):break
            mid=material(mref)
            if not mid:continue
            # Preserve the original names/hierarchy separately, merge draw chunks by material/lightmap.
            chunk_key=(mid,lm,is_active)
            chunk=chunks.setdefault(chunk_key,{'id':f'chunk-{len(chunks)}','name':f'{materials[mid]["name"]}-lm{lm}', 'materialId':mid,'lightmapIndex':lm,'active':is_active,'positions':[],'normals':[],'uv':[],'uv2':[],'colors':[],'indices':[]})
            remap={};start_index=len(chunk['indices'])
            for triangle in tris[sub]:
                for vi in triangle:
                    if vi not in remap:
                        pos=(matrix@np.array([*vertices[vi],1]))[:3];node_min=np.minimum(node_min,pos);node_max=np.maximum(node_max,pos)
                        n=matrix[:3,:3]@normals[vi] if normals is not None else np.array([0,1,0]);n/=np.linalg.norm(n) or 1
                        remap[vi]=len(chunk['positions'])//3
                        chunk['positions'].extend(np.round(pos,6).tolist());chunk['normals'].extend(np.round(n,6).tolist());chunk['uv'].extend([round(float(v),6) for v in uv[vi][:2]])
                        chunk['uv2'].extend([round(float(uv2[vi][0])*st[0]+st[2],6),round(float(uv2[vi][1])*st[1]+st[3],6)])
                        col=colors[vi] if colors else (1,1,1,1);chunk['colors'].extend([float(v) for v in col[:4]])
                    chunk['indices'].append(remap[vi])
            node_indices.append({'chunkId':chunk['id'],'indexStart':start_index,'indexCount':len(chunk['indices'])-start_index,'materialId':mid,'sourceSubmesh':sub})
        if node_indices:
            instances.append({'id':str(gid),'name':go.m_Name,'hierarchy':hierarchy(gid),'active':is_active,'sourceMeshId':key,'staticBatch':static,'matrix':world(tf_by_go.get(gid)).flatten(order='F').round(8).tolist(),'renderMatrix':matrix.flatten(order='F').round(8).tolist(),'ranges':node_indices,'bounds':{'min':node_min.round(6).tolist(),'max':node_max.round(6).tolist()},'lightmapIndex':lm,'lightmapScaleOffset':vec(r.m_LightmapTilingOffset,4)})
    navigation=[]
    for gid,mf in filters.items():
        if 'navmesh' not in gos[gid].m_Name.lower():continue
        try:
            key,(d,h,tris)=mesh_data(mf.m_Mesh);m=world(tf_by_go.get(gid));v=np.asarray(h.m_Vertices)
            pos=(np.column_stack((v,np.ones(len(v))))@m.T)[:,:3]
            navigation.append({'id':str(gid),'name':gos[gid].m_Name,'hierarchy':hierarchy(gid),'positions':pos.round(6).flatten().tolist(),'indices':[vi for sub in tris for tri in sub for vi in tri],'matrix':np.eye(4).flatten(order='F').tolist(),'sourceMesh':d.m_Name,'bounds':{'min':pos.min(axis=0).tolist(),'max':pos.max(axis=0).tolist()}})
        except Exception as exc:failures.append({'kind':'navigation','name':gos[gid].m_Name,'error':str(exc)[:300]})
    lightmaps=[]
    for o in scene_objects:
        if o.type.name=='LightmapSettings':
            for i,lmdata in enumerate(o.read().m_Lightmaps):
                rawpath=texture(lmdata.m_Lightmap);decoded=None
                if rawpath:
                    rgba=np.asarray(Image.open(texture_dir/Path(rawpath).name).convert('RGBA'),dtype=np.float64)/255
                    # Original PC lightmap RGBM: indirect L = RGB * (5*A)^2.2.
                    linear=rgba[:,:,:3]*(5*rgba[:,:,3:4])**2.2
                    encoded=np.clip(linear,0,1)**(1/2.2)
                    filename=f'lightmap-{i}-decoded.png';Image.fromarray((encoded*255).round().astype(np.uint8),'RGB').save(texture_dir/filename)
                    decoded=f'/maps/hotel/textures/{filename}'
                lightmaps.append({'index':i,'path':rawpath,'decodedPath':decoded,'shadowMask':texture(lmdata.m_ShadowMask),'encoding':'Raw Unity PC RGBM and gamma-encoded decoded RGB light multiplier (range 1)'})
    colliders=[];cameras=[];nodes=[];scene_settings={}
    for tid,t in trans.items():
        gid=t.m_GameObject.m_PathID;go=gos[gid]
        nodes.append({'id':str(gid),'name':go.m_Name,'parentId':str(trans[t.m_Father.m_PathID].m_GameObject.m_PathID) if t.m_Father.m_PathID in trans else None,'active':active(gid),'position':vec(t.m_LocalPosition),'rotation':vec(t.m_LocalRotation,4),'scale':vec(t.m_LocalScale),'matrix':world(tid).flatten(order='F').round(8).tolist()})
    for o in scene_objects:
        if o.type.name=='BoxCollider':
            d=o.read();gid=d.m_GameObject.m_PathID
            colliders.append({'id':str(o.path_id),'name':gos[gid].m_Name,'hierarchy':hierarchy(gid),'matrix':world(tf_by_go.get(gid)).flatten(order='F').round(8).tolist(),'center':vec(d.m_Center),'size':vec(d.m_Size),'isTrigger':d.m_IsTrigger,'enabled':d.m_Enabled})
        if o.type.name=='Camera':
            d=o.read();gid=d.m_GameObject.m_PathID
            cameras.append({'id':str(o.path_id),'name':gos[gid].m_Name,'hierarchy':hierarchy(gid),'matrix':world(tf_by_go.get(gid)).flatten(order='F').round(8).tolist(),'position':world(tf_by_go.get(gid))[:3,3].tolist(),'orthographic':d.orthographic,'orthographicSize':d.orthographic_size,'fov':d.field_of_view,'near':d.near_clip_plane,'far':d.far_clip_plane,'enabled':bool(d.m_Enabled),'purpose':'shadow camera; not the main player view'})
        if o.type.name=='MonoBehaviour' and o.path_id==12532:
            try:scene_settings=o.read_typetree()
            except Exception:pass
    spring=[i for i in instances if 'spring' in i['name'].lower()]
    sbounds={'min':np.min([i['bounds']['min'] for i in spring],axis=0).tolist(),'max':np.max([i['bounds']['max'] for i in spring],axis=0).tolist()} if spring else None
    for n in navigation:n['origin']=[0,0,0]
    suggested={'evidence':'Points are original Navmesh floor face centres; interaction meanings and encounter are prototype gameplay, region awaits visual verification.', 'bounds':{'min':[-2.5,-1.52,-3.5],'max':[47.5,2.38,28.5]},'cameraFocus':{'x':22,'y':0,'z':15},'partySpawns':[{'x':21.1667,'y':-.01,'z':23.1673},{'x':19.1667,'y':-.01,'z':23.8346},{'x':23.1667,'y':-.01,'z':23.1673}], 'encounterEnemies':[{'x':26.1667,'y':-.01,'z':16.8333},{'x':29.1667,'y':-.01,'z':15.5},{'x':29.1667,'y':-.01,'z':11.1667},{'x':29.8333,'y':-.01,'z':10.8333}], 'interactions':{'reception':{'x':26.1667,'y':-.01,'z':18.1667},'door':{'x':24.8333,'y':-.01,'z':16.8333},'supply':{'x':29.1667,'y':-.01,'z':19.8317}},'trigger':{'x':27,'z':16,'width':8,'depth':4}}
    doc={'version':1,'source':'local Arknights PC client; ark_odc_act53side_main', 'copyright':'Arknights assets belong to Hypergryph; code license does not grant asset rights.', 'coordinates':'Unity left-handed Y-up world metres. matrices are column-major, positions transformed to world. Static batch triangles use IDENTITY renderMatrix; do not apply source GO matrix again.', 'uvConvention':'Unity UVs bottom-left; PNG exports use UnityPy image orientation. Loader may need invertY=false.', 'meshes':list(chunks.values()),'instances':instances,'materials':list(materials.values()),'textures':list(textures.values()),'lightmaps':lightmaps,'navigation':navigation,'colliders':colliders,'cameras':cameras,'nodes':nodes,'sceneSettings':scene_settings,'regions':{'springExterior':sbounds},'suggestedPlay':suggested,'cameraEvidence':'Only SpineCam and ShadowCam are serialized. scene_data contains baked NavMeshData and occlusion data; no player camera config.', 'colliderEvidence':'All 19 BoxColliders are trigger-only DitherGroup occlusion volumes, not physical movement colliders. Use original Navmesh geometry.', 'failures':failures}
    (out/'scene.json').write_text(json.dumps(doc,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    export_runtime(doc,out)
    (qa_out/'extraction-report.json').write_text(json.dumps({'chunks':len(chunks),'instances':len(instances),'materials':len(materials),'textures':len(textures),'navigation':[{'name':n['name'],'vertices':len(n['positions'])//3,'triangles':len(n['indices'])//3,'bounds':n['bounds']} for n in navigation],'regions':doc['regions'],'failures':failures},ensure_ascii=False,indent=2),encoding='utf-8')
    (out/'play-suggestions.json').write_text(json.dumps(suggested,ensure_ascii=False,indent=2),encoding='utf8')
    export_interest(doc,out)
    print('EXPORTED',len(chunks),'chunks',len(instances),'instances',len(textures),'textures',len(failures),'issues',flush=True)
    print('SPRING BOUNDS',sbounds,flush=True)


def export_runtime(doc, out):
    """Compact production payload; keep the full JSON as independently readable evidence."""
    runtime={key:copy.deepcopy(value) for key,value in doc.items() if key not in {'meshes','nodes','sceneSettings'}}
    blob=bytearray();mesh_records=[]
    for mesh in doc['meshes']:
        record={key:value for key,value in mesh.items() if key not in {'positions','normals','uv','uv2','colors','indices'}}
        for key in ['positions','normals','uv','uv2','colors','indices']:
            while len(blob)%4:blob.append(0)
            kind='uint32' if key=='indices' else 'float32';dtype='<u4' if kind=='uint32' else '<f4'
            record[key]={'offset':len(blob),'length':len(mesh[key]),'kind':kind}
            blob.extend(np.asarray(mesh[key],dtype=dtype).tobytes())
        mesh_records.append(record)
    runtime['meshes']=mesh_records
    runtime['geometry']={'file':'/maps/hotel/geometry.bin','bytes':len(blob),'alignment':4,'endianness':'little'}
    runtime['runtimeFormat']='attribute metadata {offset byte,length element count,kind float32|uint32}; geometry.bin, all original world coordinates'
    (out/'geometry.bin').write_bytes(blob)
    (out/'scene-runtime.json').write_text(json.dumps(runtime,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    print('RUNTIME',len(blob),'geometry bytes',(out/'scene-runtime.json').stat().st_size,'JSON bytes',flush=True)


def export_interest(doc,out):
    """Only original object locations and material properties; no invented hotel geometry."""
    materials={m['id']:m for m in doc['materials']};meshes={m['id']:m for m in doc['meshes']}
    waters=[];entrances=[];buildings=[];signs=[]
    for inst in doc['instances']:
        if any('poolwater' in materials[r['materialId']]['name'] for r in inst['ranges']):waters.append({'id':inst['id'],'name':inst['name'],'bounds':inst['bounds'],'materialIds':list({r['materialId'] for r in inst['ranges']})})
        if 'entrance' in inst['name'].lower():entrances.append({'id':inst['id'],'name':inst['name'],'bounds':inst['bounds'],'hierarchy':inst['hierarchy']})
        if 'building' in inst['name'].lower() and inst['bounds']['max'][2]>15 and inst['bounds']['min'][2]<26 and inst['bounds']['max'][0]>5 and inst['bounds']['min'][0]<32:buildings.append({'id':inst['id'],'name':inst['name'],'bounds':inst['bounds'],'hierarchy':inst['hierarchy']})
        if 'billboard' not in inst['name'].lower():continue
        for r in inst['ranges']:
            if 'T_Arkodc_D2_' not in materials[r['materialId']]['textures'].get('_MainTex',''):continue
            m=meshes[r['chunkId']];ids=np.asarray(m['indices'][r['indexStart']:r['indexStart']+r['indexCount']]).reshape(-1,3);uv=np.asarray(m['uv']).reshape(-1,2)[ids];c=np.mod(uv.mean(1),1)
            mask=(c[:,0]>.65)&(c[:,0]<=1)&(c[:,1]>.005)&(c[:,1]<.25)
            if mask.any():
                v=np.asarray(m['positions']).reshape(-1,3)[ids[mask]].reshape(-1,3)
                signs.append({'id':inst['id'],'name':inst['name'],'originalBounds':inst['bounds'],'signGeometryBounds':{'min':v.min(0).tolist(),'max':v.max(0).tolist()},'candidateEvidence':'Billboard UV triangles overlap original atlas MOTEL rectangle and border; source object name is numeric.'})
    interest={'sourceScene':'ark_odc_act53side_main','coordinateSystem':'Unity left-handed Y-up metres; matrix column-major','waters':waters,'smokeEmitters':[{'name':n['name'],'position':n['matrix'][12:15],'matrix':n['matrix']} for n in doc['nodes'] if n['name'].startswith('mapeff_Arkodc_smoke')], 'waterMaterials':[m for m in doc['materials'] if 'poolwater' in m['name']],'entrances':entrances,'buildingCandidates':buildings,'motelSignRenderers':signs,'evidenceBoundary':'Numeric GO names do not explicitly label a hotel region. The atlas contains MOTEL signage. Confirm the candidate billboard in the rendered original scene before assigning the region label.'}
    (out/'interest-points.json').write_text(json.dumps(interest,ensure_ascii=False,indent=2),encoding='utf8')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--client", type=Path, default=DEFAULT_CLIENT)
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[1] / "public/maps/hotel")
    ap.add_argument("--qa-out", type=Path, default=Path(__file__).resolve().parents[1] / ".qa/extraction/hotel", help="Directory for extraction reports and inspection output")
    ap.add_argument("--inspect", action="store_true")
    ap.add_argument("--runtime-only", action="store_true", help="Build the compact payload from an existing scene.json without rereading the client")
    args = ap.parse_args()
    if args.runtime_only:
        args.out.mkdir(parents=True, exist_ok=True)
        export_runtime(json.loads((args.out/'scene.json').read_text(encoding='utf8')),args.out)
        return
    args.qa_out.mkdir(parents=True, exist_ok=True)
    if not args.inspect:
        args.out.mkdir(parents=True, exist_ok=True)
    bundles = [args.client / SCENE_SUB / "ark_odc_act53side_main.ab", args.client / SCENE_SUB / "scene_data.ab", args.client / SCENE_SUB / "ark_odc_act53side_main/lightingdata.ab", args.client / "arts/maps/map_arkodc/res.ab"]
    bundles.extend(path for path in (args.client/'arts/maps/map_arkodc').rglob('*.ab') if path not in bundles)
    default_resources=args.client.parents[2]/'Resources/unity default resources'
    if default_resources.exists(): bundles.append(default_resources)
    extra=args.client/'arts/maps/common/trap/trap_arkvent.ab'
    if extra.exists():bundles.append(extra)
    env = UnityPy.Environment()
    for path in bundles:
        print("LOAD", path.name, path.stat().st_size, flush=True)
        env.load_file(str(path))
    sources=[]
    for path in bundles:
        relative=str(path.relative_to(args.client)).replace('\\','/') if path.is_relative_to(args.client) else '../../Resources/unity default resources'
        sources.append({'relativePath':relative,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    manifest_out = args.qa_out if args.inspect else args.out
    (manifest_out/'source-manifest.json').write_text(json.dumps({'source':'Local installed Arknights PC game assets only; read-only extraction','sources':sources,'sourceAssetsUnmodified':True},indent=2),encoding='utf8')
    print("TYPES", Counter(o.type.name for o in env.objects), flush=True)
    if not args.inspect:
        export_scene(env,args.out,args.qa_out)
        return
    names = []
    cameras = []
    for obj in env.objects:
        if obj.type.name not in {"GameObject", "Mesh", "Material", "Camera", "MonoBehaviour", "NavMeshData", "BoxCollider", "MeshCollider"}: continue
        try:
            data = obj.read()
            name = getattr(data, "m_Name", "")
            if obj.type.name == "GameObject": names.append({"id": obj.path_id, "name": name})
            if obj.type.name == "Camera": cameras.append({"id": obj.path_id, "data": jsonable(data)})
            if name and re.search(r"hotel|spring|hots|resort|odc|area|zone|root|nav|camera|温泉|旅馆", name, re.I): print(obj.type.name, obj.path_id, name, flush=True)
        except Exception as exc: print("READFAIL", obj.type.name, obj.path_id, str(exc)[:160], flush=True)
    (args.qa_out / "inspection.json").write_text(json.dumps({"types": dict(Counter(o.type.name for o in env.objects)), "gameObjects": names, "cameras": cameras}, ensure_ascii=False, indent=2), encoding="utf-8")
    print("INSPECTION", len(names), "objects", len(cameras), "cameras", flush=True)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
