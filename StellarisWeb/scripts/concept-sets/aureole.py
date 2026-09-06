"""AUREOLE concept refit in Blender 4.5: ivory shells, amber eyes, gold lips.

blender --background --factory-startup --python scripts/concept-sets/aureole.py -- --render
Original animation and attachment nodes are preserved by ConceptAsset. Geometry
is authored in glTF local coordinates (+Y up, -Z forward). No generic texture
atlas is used: the concept's shell breaks and lens recesses are actual geometry.
"""
from pathlib import Path
import argparse
import json
import math
import sys
import struct
import shutil
import bpy
import bmesh
from mathutils import Vector, Matrix

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
from concept_asset import ConceptAsset, asset_ids


class Shape:
    def __init__(self,name):
        self.name=name;self.vertices=[];self.faces=[];self.mats=[];self.colors=[]

    def add(self,vertices,faces,mats):
        start=len(self.vertices)
        self.vertices.extend(tuple(v) for v in vertices)
        self.colors.extend([(1,1,1,1)]*len(vertices))
        self.faces.extend(tuple(start+i for i in f) for f in faces)
        self.mats.extend([mats]*len(faces) if isinstance(mats,int) else mats)

    def band(self,center,rx,rz,width,depth,start,end,mat,*,steps=64,taper=False,inset=0,tilt=0,profile=None,profile_mats=None):
        """Cambered crescent section, unlike a rounded metal torus."""
        steps=min(steps,max(8,math.ceil(abs(end-start)/12)))
        profile=profile or [(1,-.18),(.60,.9),(-.55,.88),(-1,-.12),(-.75,-.62),(.75,-.62)]
        vertices=[];faces=[];mats=[];n=len(profile)
        rotation=Matrix.Rotation(tilt,3,'Z')
        for i in range(steps+1):
            u=i/steps; angle=math.radians(start+(end-start)*u)
            f=max(.008,math.sin(math.pi*u)**.65) if taper else 1
            # Width tapers globally at the fore tips, but panel joins are flush.
            out=Vector((math.sin(angle),0,-math.cos(angle)))
            base=Vector((rx*math.sin(angle),0,-rz*math.cos(angle)))-out*inset*f
            for q,h in profile:
                vertices.append(Vector(center)+rotation@(base+out*width*q*f+Vector((0,depth*h*f,0))))
        for i in range(steps):
            for k in range(n):
                faces.append((i*n+k,i*n+(k+1)%n,(i+1)*n+(k+1)%n,(i+1)*n+k))
                mats.append(profile_mats[k] if profile_mats else mat)
        faces.extend([tuple(reversed(range(n))),tuple(range(steps*n,(steps+1)*n))]);mats.extend([mat,mat])
        self.add(vertices,faces,mats)

    def shell_arc(self,center,rx,rz,width,depth,start,end,m,segments=3,steps=180):
        """One closed 13-point profile replaces four intersecting solid bands.

        All visible ivory, gold and amber borders retain the preceding authoring
        coordinates. Angular rows follow curvature and the exact old panel cuts;
        internal buried return faces and duplicate under-shells no longer exist.
        """
        depth*=.68
        profile=[(1.035,-.482),(1,.0),(.975,.28),(.72,.86),(.22,1.08),(-.55,.95),(-.92,.43),(-1.025,-.18),(-1.032,-.22),(-1.032,-.30),(-1.035,-.414),(-.88,-.896),(.40,-1.086)]
        strips=[m['satin'],m['satin'],m['white'],m['white'],m['white'],m['white'],m['gold'],m['gold'],m['energy'],m['gold'],m['dark'],m['dark'],m['dark']]
        verts=[];faces=[];mats=[];n=len(profile)
        intervals=[(math.floor(180*k/segments)/180,(math.floor(180*k/segments)+1)/180) for k in range(1,segments)]
        samples=max(12,math.ceil(abs(end-start)/10))
        us=sorted(set([i/samples for i in range(samples+1)]+[u for interval in intervals for u in interval]))
        for u in us:
            a=math.radians(start+(end-start)*u);f=max(.006,math.sin(math.pi*u)**.65)
            out=Vector((math.sin(a),0,-math.cos(a)))
            base=Vector(center)+Vector((rx*math.sin(a),0,-rz*math.cos(a)))
            for q,h in profile:verts.append(base+out*width*q*f+Vector((0,depth*h*f,0)))
        for i in range(len(us)-1):
            cut=any(lo<=(us[i]+us[i+1])*.5<=hi for lo,hi in intervals)
            for k in range(n):
                faces.append((i*n+k,i*n+(k+1)%n,(i+1)*n+(k+1)%n,(i+1)*n+k));mats.append(m['dark'] if cut and k<7 else strips[k])
        faces.extend([tuple(reversed(range(n))),tuple(range((len(us)-1)*n,len(us)*n))]);mats.extend([m['satin']]*2)
        self.add(verts,faces,mats)
        # Amber pin-lights live inside that continuous recess, not on the paint.
        for k in range(2,16):
            u=k/17;a=math.radians(start+(end-start)*u);f=math.sin(math.pi*u)**.65
            rad=Vector((math.sin(a),0,-math.cos(a)))
            p=Vector(center)+Vector((rx*math.sin(a),-depth*.32,-rz*math.cos(a)))-rad*width*.96*f
            self.ellipsoid(p,(width*.023,depth*.045,width*.023),m['energy'],segments=8,rings=4)

    def ellipsoid(self,center,size,mat,segments=32,rings=16,rotation=None):
        segments=min(segments,12);rings=min(rings,6)
        vertices=[];faces=[];rotation=rotation or Matrix.Identity(3)
        if segments<=8 and rings<=4:
            # Subpixel status lights require six extremal points, not UV spheres.
            v=[Vector(center)+rotation@Vector(p) for p in [(size[0],0,0),(-size[0],0,0),(0,size[1],0),(0,-size[1],0),(0,0,size[2]),(0,0,-size[2])]]
            self.add(v,[(2,0,4),(2,4,1),(2,1,5),(2,5,0),(3,4,0),(3,1,4),(3,5,1),(3,0,5)],mat)
            return
        vertices.append(Vector(center)+rotation@Vector((0,size[1],0)))
        for j in range(1,rings):
            phi=math.pi*j/rings
            for i in range(segments):
                a=2*math.pi*i/segments
                p=Vector((size[0]*math.sin(phi)*math.cos(a),size[1]*math.cos(phi),size[2]*math.sin(phi)*math.sin(a)))
                vertices.append(Vector(center)+rotation@p)
        south=len(vertices);vertices.append(Vector(center)+rotation@Vector((0,-size[1],0)))
        for i in range(segments):faces.append((0,1+(i+1)%segments,1+i))
        for j in range(rings-2):
            for i in range(segments):
                faces.append((1+j*segments+i,1+j*segments+(i+1)%segments,1+(j+1)*segments+(i+1)%segments,1+(j+1)*segments+i))
        for i in range(segments):faces.append((south,1+(rings-2)*segments+i,1+(rings-2)*segments+(i+1)%segments))
        self.add(vertices,faces,mat)

    def beam(self,a,b,r,mat,segments=10):
        segments=min(segments,6)
        a=Vector(a);b=Vector(b);direction=(b-a).normalized();side=direction.cross(Vector((0,1,0)))
        if side.length<1e-5:side=direction.cross(Vector((0,0,1)))
        side.normalize();up=direction.cross(side).normalized()
        vertices=[p+side*r*math.cos(i*2*math.pi/segments)+up*r*math.sin(i*2*math.pi/segments) for p in [a,b] for i in range(segments)]
        faces=[tuple(reversed(range(segments))),tuple(range(segments,2*segments))]
        faces += [(i,(i+1)%segments,(i+1)%segments+segments,i+segments) for i in range(segments)]
        self.add(vertices,faces,mat)

    def spindle(self,center,length,width,height,m,ceramic=True):
        """Pointed axial graphite chassis with ivory fore/aft petal fairings."""
        cx,cy,cz=center;rows=[0,2,6,12,20,34,48,62,76,84,90,94,96];around=12;verts=[];faces=[];mats=[]
        for j in rows:
            for i in range(around):
                a=i*2*math.pi/around
                fore=.17+.07*abs(math.cos(a));aft=.79-.045*abs(math.cos(a))
                u=(j/20)*fore if j<=20 else fore+(j-20)/56*(aft-fore) if j<=76 else aft+(j-76)/20*(1-aft)
                f=max(.007,math.sin(math.pi*u)**.72)
                verts.append((cx+math.cos(a)*width*f,cy+math.sin(a)*height*f,cz+(u-.5)*length))
        for row in range(len(rows)-1):
            j=rows[row]
            for i in range(around):
                a=(i+.5)*2*math.pi/around
                top=math.sin(a)
                # White ends meet the dark exposed axial service bed at shaped seams.
                white=ceramic and top>.08 and (j<20 or j>=76)
                face_mat=m['white'] if white else m['dark']
                if ceramic and -.15<top<.04:face_mat=m['gold']
                faces.append((row*around+i,row*around+(i+1)%around,(row+1)*around+(i+1)%around,(row+1)*around+i));mats.append(face_mat)
        self.add(verts,faces,mats)
        # Paired narrow sculpted plates expose the central dark spine.
        for sign in [-1,1]:
            for start,end in [(.19,.40),(.61,.77)]:
                p=(cx+sign*width*.70,cy+height*.28,cz+((start+end)*.5-.5)*length)
                self.ellipsoid(p,(width*.18,height*.30,length*(end-start)*.48),m['satin'],segments=12,rings=4)

    def eye(self,center,rx,rz,m,height=.015):
        # Recessed amber eye set into a double black/gold retaining ring.
        x,y,z=center
        small=self.name.startswith('AUREOLE fitted')
        self.ellipsoid((x,y-height*.72,z),(rx*1.32,height*.68,rz*1.13),m['dark'],8 if small else 12,3 if small else 6)
        self.band((x,y+height*.18,z),rx*1.07,rz*1.035,rx*.115,height*.24,0,360,m['gold'],steps=8 if small else 20,profile=[(1,0),(.5,1),(-1,0),(0,-1)])
        first=len(self.vertices)
        # Concentric dome topology spends vertices on the visible glass only.
        # The lower half was entirely enclosed by the retaining bezel.
        v=[(x,y+height*.79,z)];f=[];count=12 if small else 20
        radii=[.6,1] if small else [.28,.62,.86,1]
        for radius in radii:
            for k in range(count):
                angle=k*math.tau/count
                v.append((x+rx*radius*math.cos(angle),y+height*(.05+.74*math.sqrt(max(0,1-radius*radius))),z+rz*radius*math.sin(angle)))
        for k in range(count):f.append((0,1+(k+1)%count,1+k))
        for ring in range(len(radii)-1):
            for k in range(count):f.append((1+ring*count+k,1+ring*count+(k+1)%count,1+(ring+1)*count+(k+1)%count,1+(ring+1)*count+k))
        self.add(v,f,m['energy'])
        for i in range(first,len(self.vertices)):
            vx,vy,vz=self.vertices[i];u=(vx-x)/rx;v=(vz-z)/rz
            spine=math.exp(-((u-.055*math.sin(v*13))/.19)**2)
            flow=(.5+.5*math.sin(v*31+math.sin(u*18)*2))**9
            glow=min(1,.16+.75*spine+.16*flow)
            self.colors[i]=(glow,.57+.37*spine,.22+.43*spine,1)
        # The caustic is COLOR_0 on the single glass surface. An additional
        # highlight mesh would intersect the lens near the elliptical tips.

    def object(self,a,offset=(0,0,0),scale=1):
        mesh=bpy.data.meshes.new(self.name)
        mesh.from_pydata([Vector(v)*scale-Vector(offset) for v in self.vertices],[],self.faces)
        mesh.validate(clean_customdata=False);mesh.update()
        obj=bpy.data.objects.new(self.name,mesh);bpy.context.collection.objects.link(obj)
        for mat in a.materials:mesh.materials.append(mat)
        for p,mat in zip(mesh.polygons,self.mats):p.material_index=mat;p.use_smooth=True
        if any(c!=(1,1,1,1) for c in self.colors):
            layer=mesh.color_attributes.new(name='AureoleAmberRadiance',type='FLOAT_COLOR',domain='POINT')
            for i,c in enumerate(self.colors):layer.data[i].color=c
            mesh.color_attributes.active_color=layer
        mesh.set_sharp_from_angle(angle=math.radians(48))
        return obj


def finishes(a):
    for i,mat in enumerate(a.document['materials']):
        name=mat.get('name','').lower()
        if 'emission' in name or 'core' in name:
            a.set_material(i,color=(.38,.12,.006,1),metal=.15,rough=.24,emission=(1,.20,.004),strength=1.7,role='energy',coat=.2)
        elif 'structure' in name:
            a.set_material(i,color=(.026,.023,.018,1),metal=.73,rough=.36,emission=(0,0,0),strength=0,role='structure')
        elif 'facet a' in name:
            a.set_material(i,color=(.40,.20,.050,1),metal=.50,rough=.38,emission=(0,0,0),strength=0,role='hull')
        else:
            a.set_material(i,color=(.78,.745,.645,1),metal=.10,rough=.29,emission=(0,0,0),strength=0,role='hull',coat=.32)
    def add(name,**kwargs):return a.add_material('AUREOLE | Concept '+name,**kwargs)
    result=dict(
        white=add('warm ivory shell',color=(.81,.777,.692,1),metal=.08,rough=.28,role='hull',coat=.36),
        satin=add('recessed ivory return',color=(.46,.439,.369,1),metal=.19,rough=.34,role='hull',coat=.22),
        dark=add('exposed graphite bronze chassis',color=(.022,.019,.015,1),metal=.72,rough=.34,role='structure'),
        gold=add('narrow warm gold bezel',color=(.55,.287,.071,1),metal=.82,rough=.27,role='structure',coat=.22),
        energy=add('amber inner lens',color=(.43,.11,.002,1),metal=.05,rough=.24,emission=(1,.23,.004),strength=2.0,role='energy',conceptVertexEmission=True),
        hot=add('amber lens caustic',color=(.65,.28,.023,1),metal=0,rough=.25,emission=(1,.49,.042),strength=3.1,role='energy'),
        plume=add('short amber thrust',color=(.38,.105,.003,.65),metal=0,rough=.4,emission=(1,.23,.004),strength=2.8,role='plume'),
        crystal=add('captured honey crystal',color=(.19,.067,.006,1),metal=.12,rough=.22,emission=(1,.23,.007),strength=.42,role='energy',coat=.45),
    )
    # Cycles sees the same lens radiance field exported to COLOR_0 for Three.js.
    mat=a.materials[result['energy']];tree=mat.node_tree;shader=tree.nodes.get('Principled BSDF')
    attr=tree.nodes.new('ShaderNodeAttribute');attr.attribute_name='AureoleAmberRadiance'
    fallback=tree.nodes.new('ShaderNodeMixRGB');fallback.blend_type='MIX';fallback.inputs[1].default_value=(1,1,1,1)
    tree.links.new(attr.outputs['Alpha'],fallback.inputs[0]);tree.links.new(attr.outputs['Color'],fallback.inputs[2])
    multiply=tree.nodes.new('ShaderNodeMixRGB');multiply.blend_type='MULTIPLY';multiply.inputs[0].default_value=1;multiply.inputs[1].default_value=(1,.23,.004,1)
    tree.links.new(fallback.outputs[0],multiply.inputs[2]);tree.links.new(multiply.outputs[0],shader.inputs['Emission Color'])
    return result


def node(a,name):return next((n for n in a.document['nodes'] if n.get('name')==name),None)
def bounds(obj):
    vs=[v.co for v in obj.data.vertices]
    lo=Vector(tuple(min(v[i] for v in vs) for i in range(3)));hi=Vector(tuple(max(v[i] for v in vs) for i in range(3)))
    return lo,hi


def control_meshes(a):
    """Recover the identical authored control surfaces beneath added bevels.

    These are the same asset/node-local components used by the current concept
    authoring script. We preserve their placement and material segmentation, then
    reproduce the current concept finish below. No old surface palette is used.
    """
    path=ROOT/'artifacts/model-import/surface-originals/aureole'/(a.asset_id+'.glb')
    raw=path.read_bytes();length=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+length]);binary=raw[28+length:]
    assert doc['nodes']==a.original_nodes
    saved_doc,saved_binary=a.document,a.binary
    a.document,a.binary=doc,binary
    try:
        for idx,source in enumerate(doc['meshes']):
            vertices=[];faces=[];mats=[]
            for primitive in source['primitives']:
                offset=len(vertices);positions=a.accessor(primitive['attributes']['POSITION']);vertices.extend(positions)
                indices=[v[0] for v in a.accessor(primitive['indices'])]
                faces.extend(tuple(offset+v for v in indices[i:i+3]) for i in range(0,len(indices),3))
                name=doc['materials'][primitive.get('material',0)]['name'];mat=next(j for j,m in enumerate(saved_doc['materials']) if m['name']==name)
                mats.extend([mat]*(len(indices)//3))
            mesh=bpy.data.meshes.new('AUREOLE original control surface')
            mesh.from_pydata(vertices,[],faces);mesh.validate();mesh.update()
            for mat in a.materials:mesh.materials.append(mat)
            for face,mat in zip(mesh.polygons,mats):face.material_index=mat;face.use_smooth=True
            a.mesh_objects[idx].data=mesh
    finally:a.document,a.binary=saved_doc,saved_binary


def retessellate_ellipsoids(a):
    """Analytic primitive retopology; arbitrary silhouettes are left untouched.

    Fit each closed single-material island to a quadric. A candidate must have
    spherical topology and match every original vertex to <0.15% normalized
    quadric error. This never collapses components or changes their centers.
    """
    import numpy as np
    replaced=0;sweeps=0
    for idx,obj in a.mesh_objects.items():
        bm=bmesh.new();bm.from_mesh(obj.data)
        lo,hi=bounds(obj);span=max(hi-lo)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=max(span*1e-7,1e-7));bm.normal_update()
        bm.verts.ensure_lookup_table();bm.faces.ensure_lookup_table();seen=set();result=Shape('AUREOLE analytic control topology')
        for seed in list(bm.verts):
            if seed in seen:continue
            stack=[seed];seen.add(seed);vs=[]
            while stack:
                v=stack.pop();vs.append(v)
                for e in v.link_edges:
                    other=e.other_vert(v)
                    if other not in seen:seen.add(other);stack.append(other)
            fs=set(f for v in vs for f in v.link_faces);es=set(e for v in vs for e in v.link_edges)
            # The control source stores ring cross-sections as six ordered
            # vertices per row. Verify that exact topology before resampling.
            # All retained profile vertices stay bit-for-bit in their old place.
            ordered=sorted(vs,key=lambda v:v.index)
            if len(vs)>=24 and len(vs)%6==0 and len({f.material_index for f in fs})==1:
                lookup={v:k for k,v in enumerate(ordered)};rows=len(vs)//6;structured=True;closed=False
                for face in fs:
                    rr={lookup[v]//6 for v in face.verts}
                    if len(rr)>2 or (len(rr)==2 and max(rr)-min(rr) not in {1,rows-1}):structured=False;break
                    if len(rr)==2 and max(rr)-min(rr)==rows-1:closed=True
                if structured:
                    profiles=[[ordered[6*r+k].co.copy() for k in range(6)] for r in range(rows)]
                    if closed:profiles.append(profiles[0])
                    length=max(max(v[i] for row in profiles for v in row)-min(v[i] for row in profiles for v in row) for i in range(3))
                    tolerance=length*(.035 if a.asset_id=='03_dyson_swarm' else .0065)
                    keep={0,len(profiles)-1}
                    # Preserve every world-space extremum, including tapered tips.
                    for axis in range(3):
                        keep.add(min(range(rows),key=lambda r:min(v[axis] for v in profiles[r])))
                        keep.add(max(range(rows),key=lambda r:max(v[axis] for v in profiles[r])))
                    def refine(lo,hi):
                        if hi-lo<2:return
                        maximum=-1;winner=lo
                        for r in range(lo+1,hi):
                            t=(r-lo)/(hi-lo)
                            error=max((profiles[r][k]-(profiles[lo][k]*(1-t)+profiles[hi][k]*t)).length for k in range(6))
                            if error>maximum:maximum=error;winner=r
                        if maximum>tolerance:keep.add(winner);refine(lo,winner);refine(winner,hi)
                    keys=sorted(keep)
                    for lo2,hi2 in zip(keys,keys[1:]):refine(lo2,hi2)
                    retained=sorted(keep)
                    if len(retained)<len(profiles):
                        vertices=[v for row in retained for v in profiles[row]];faces=[]
                        for row in range(len(retained)-1):
                            faces.extend((row*6+k,row*6+(k+1)%6,(row+1)*6+(k+1)%6,(row+1)*6+k) for k in range(6))
                        if not closed:faces.extend([tuple(reversed(range(6))),tuple(range((len(retained)-1)*6,len(retained)*6))])
                        result.add(vertices,faces,next(iter(fs)).material_index);sweeps+=1;continue
            fit=None
            if len(vs)>40 and len(vs)-len(es)+len(fs)==2 and len({f.material_index for f in fs})==1:
                xyz=np.array([tuple(v.co) for v in vs]);mean=xyz.mean(axis=0);scale=float(np.max(xyz.max(axis=0)-xyz.min(axis=0)))
                if scale>1e-7:
                    p=(xyz-mean)/scale;x,y,z=p.T
                    design=np.column_stack((x*x,y*y,z*z,2*x*y,2*x*z,2*y*z,x,y,z,np.ones(len(x))))
                    try:
                        _,_,vt=np.linalg.svd(design,full_matrices=False);q=vt[-1]
                        A=np.array([[q[0],q[3],q[4]],[q[3],q[1],q[5]],[q[4],q[5],q[2]]]);b=q[6:9];center=-.5*np.linalg.solve(A,b)
                        rhs=float(center@A@center-q[9]);ev,axes=np.linalg.eigh(A/rhs)
                        if np.all(ev>0):
                            radii=1/np.sqrt(ev);local=(p-center)@axes/radii;error=float(np.max(np.abs(np.sum(local*local,axis=1)-1)))
                            if error<.0015 and np.all(local.max(axis=0)>.94) and np.all(local.min(axis=0)<-.94):
                                # Eigenvector bases may be mirrored. Ellipsoids
                                # are symmetric, but face winding must stay right
                                # handed for the existing top/bottom shell finish.
                                if np.linalg.det(axes)<0:axes[:,0]*=-1
                                fit=(mean+center*scale,radii*scale,axes)
                    except (np.linalg.LinAlgError,ZeroDivisionError):pass
            if fit:
                center,radii,axes=fit;mat=next(iter(fs)).material_index
                # Keep full ellipsoidal collector eyes; they are tiny but do not
                # replace them by octahedral lamps intended for subpixel status.
                result.ellipsoid(center,radii,mat,segments=10 if a.asset_id=='03_dyson_swarm' else 12,rings=4 if a.asset_id=='03_dyson_swarm' else 6,rotation=Matrix(axes.tolist()))
                replaced+=1
            else:
                lookup={v:i for i,v in enumerate(vs)}
                result.add([v.co.copy() for v in vs],[tuple(lookup[v] for v in f.verts) for f in fs],[f.material_index for f in fs])
        bm.free()
        replacement=result.object(a);obj.data=replacement.data;bpy.data.objects.remove(replacement,do_unlink=True)
    a._aureole_sweeps=sweeps
    return replaced


def military(a,model_id,m):
    rank=int(model_id[:2])-1;hull=node(a,'Hull');idx=hull['mesh'];origin=Vector(hull.get('translation',[0,0,0]));lo,hi=bounds(a.mesh_objects[idx]);length=hi.z-lo.z
    cx=0;cz=(hi.z+lo.z)*.5+origin.z;half=(hi.x-lo.x)*.5
    s=Shape('AUREOLE sculpted ivory crescents and exposed axial chassis')
    rx=half/length*.89;rz=.452;width=.066 if rank<2 else .073
    cy=origin.y/length;center=(0,cy,cz/length)
    if rank<2:
        s.shell_arc(center,rx,rz,width,.034,27,333,m,segments=4)
    elif rank==2:
        for start,end in [(24,169),(191,336)]:s.shell_arc(center,rx,rz,width,.035,start,end,m,segments=2)
    elif rank==3:
        # Four outward-scrolled wings, the concept's double crescent silhouette.
        for sign in [-1,1]:
            x=sign*rx*.28
            start,end=(8,174) if sign>0 else (186,352)
            s.shell_arc((x,cy-.012,cz/length),rx*.67,rz,.081,.036,start,end,m,segments=3)
            start,end=(25,155) if sign>0 else (205,335)
            s.shell_arc((sign*rx*.055,cy+.005,cz/length+.02),rx*.43,rz*.67,.050,.029,start,end,m,segments=2)
    else:
        for start,end in [(27,171),(189,333)]:s.shell_arc(center,rx*.78,rz,width,.031,start,end,m,segments=3)
        for start,end in [(40,164),(196,320)]:s.shell_arc((0,cy-.032,cz/length+.045),rx,rz*.94,width*.82,.029,start,end,m,segments=3)
        if rank==5:
            for start,end in [(35,169),(191,325)]:s.shell_arc((0,cy+.080,cz/length-.02),rx*.44,rz*.79,width*.57,.025,start,end,m,segments=2)
    # The long slender hull remains separate from the crescent wings.
    s.spindle((0,cy+.008,cz/length-.055),.84,.065 if rank<3 else .074,.047,m)
    # Curved organic support arms tucked underneath the ivory shell.
    for sign in [-1,1]:
        for z in ([.12] if rank<2 else [-.10,.20]):
            p0=(sign*.052,cy-.012,z+cz/length);p1=(sign*rx*.83,cy-.030,z+cz/length+.018)
            s.beam(p0,p1,.017,m['dark']);s.beam((p0[0],p0[1]+.016,p0[2]),(p1[0],p1[1]+.016,p1[2]),.003,m['gold'])
    # Original animated energy node owns its lens, and our bezel meets that pivot.
    lens=node(a,'energy_1')
    if lens:
        lensidx=lens['mesh'];elo,ehi=bounds(a.mesh_objects[lensidx]);p=Vector(lens.get('translation',[0,0,0]));sz=(ehi-elo)*.5
        # A refitted chassis can sit above the source lens pivot. Translate the
        # glass/whole bezel in local mesh space, keeping that animated node exact.
        lift=max(0,(cy+.008+.047+.006)*length-p.y)
        es=Shape('AUREOLE animated recessed amber weapon eye')
        lens_scale=.60 if rank<2 else 1
        es.eye((0,lift,0),sz.x*1.10*lens_scale,sz.z*(1.55 if rank==2 else 1)*lens_scale,m,height=sz.y*.7)
        a.replace_mesh(lensidx,es.object(a))
        s.ellipsoid((p.x/length,(p.y+lift-sz.y*.77)/length,p.z/length),(sz.x/length*1.54*lens_scale,sz.y/length*.60,sz.z/length*(1.74 if rank==2 else 1.23)*lens_scale),m['dark'],36,14)
    if rank==4:
        for z in [-.30,.03,.29]:s.eye((0,cy+.054,z+cz/length),.037,.066,m,.016)
    if rank==5:
        s.eye((0,cy+.095,cz/length-.015),.037,.195,m,.028)
        for sign in [-1,1]:s.beam((sign*.028,cy+.081,cz/length-.15),(sign*.041,cy+.064,cz/length+.13),.004,m['gold'])
    # Tiny longitudinal marks on the exposed bed, never repeated over the paint.
    for k in range(7):
        z=-.25+k*.073
        for sign in [-1,1]:
            s.beam((sign*.050,cy+.029,z),(sign*.055,cy+.029,z+.023),.0021,m['gold'])
    a.replace_mesh(idx,s.object(a,origin,length))
    # Recessed aft ion port retains its existing energy animation.
    lens2=node(a,'energy_2')
    if lens2:
        lo2,hi2=bounds(a.mesh_objects[lens2['mesh']]);sz=(hi2-lo2)*.5
        e=Shape('AUREOLE stern amber eye')
        e.ellipsoid((0,0,0),(sz.x*1.32,sz.y*1.30,sz.z*.95),m['dark'],28,12)
        e.ellipsoid((0,0,sz.z*.75),(sz.x*.73,sz.y*.65,sz.z*.45),m['energy'],24,12)
        a.replace_mesh(lens2['mesh'],e.object(a))
    return {'authored':'sculpted ivory crescent shells, graphite axial bed, gold inner lips, recessed amber eyes','span':length}


def layered_originals(a,m):
    """Tailored dark under-shells and small gold returns on existing curved parts.

    Connected islands follow original curved panels and orbital geometry. Smooth
    upper shell stays ivory; underside components are duplicated slightly inward
    along normals to make a real dark seam behind the ceramic shell.
    """
    count=0
    for idx,obj in list(a.mesh_objects.items()):
        if not obj.data.vertices:continue
        source_name=next((n.get('name','') for n in a.document['nodes'] if n.get('mesh')==idx),'')
        if source_name.startswith('FX_') or source_name.startswith('energy_') or source_name=='Cargo_optional':continue
        bm=bmesh.new();bm.from_mesh(obj.data)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
        bm.normal_update();bm.verts.ensure_lookup_table();bm.faces.ensure_lookup_table()
        seen=set();islands=[]
        for v in bm.verts:
            if v in seen:continue
            stack=[v];seen.add(v);component=[]
            while stack:
                q=stack.pop();component.append(q)
                for edge in q.link_edges:
                    other=edge.other_vert(q)
                    if other not in seen:seen.add(other);stack.append(other)
            islands.append(component)
        extras=Shape('AUREOLE fitted shell undercuts and organic gold collars')
        for island in islands:
            faces=set(f for v in island for f in v.link_faces)
            hullfaces=[f for f in faces if a.document['materials'][f.material_index].get('extras',{}).get('conceptRole')=='hull']
            if len(hullfaces)<8:continue
            lo=Vector(tuple(min(v.co[i] for v in island) for i in range(3)));hi=Vector(tuple(max(v.co[i] for v in island) for i in range(3)));size=hi-lo;center=(hi+lo)*.5
            span=max(size)
            if span<.001:continue
            # Broad original curves become ceramic outer shells over a bronze
            # chassis. This geometry-linked division uses no tiled image map.
            for f in hullfaces:
                ny=f.normal.y
                if ny<-.14:f.material_index=m['dark']
                elif -.14<=ny<.02:f.material_index=m['gold']
                elif ny<.23:f.material_index=m['satin']
                else:f.material_index=m['white']
            # Sculpted spindle islands receive an inset amber/gold collar. The
            # major axis follows the original island instead of world axes.
            if size.y>span*.20 and min(size.x,size.z)<max(size.x,size.z)*.60 and len(hullfaces)>30:
                axis=2 if size.z>=size.x else 0
                p=center.copy();p.y=center.y+size.y*.51
                rx=min(size.x,size.z)*.115;rz=max(size.x,size.z)*.16
                if axis==2:extras.eye(p,rx,rz,m,max(size.y*.055,span*.006))
                else:
                    # Rotated eye: generate one then rotate only its new vertices.
                    start=len(extras.vertices);extras.eye((0,0,0),rx,rz,m,max(size.y*.055,span*.006))
                    rot=Matrix.Rotation(math.pi/2,3,'Y')
                    extras.vertices[start:]=[tuple(p+rot@Vector(v)) for v in extras.vertices[start:]]
                count+=1
        bm.to_mesh(obj.data);bm.free();obj.data.update()
        if extras.faces:a.append_geometry(idx,extras.object(a))
    return count


def civilian(a,model_id,m):
    if model_id=='07_arbeiter':
        hull=node(a,'Hull');idx=hull['mesh'];origin=Vector(hull.get('translation',[0,0,0]));lo,hi=bounds(a.mesh_objects[idx]);length=7.5
        s=Shape('AUREOLE ivory cargo cradle with amber inner track')
        s.shell_arc((0,0,0),.380,.44,.067,.055,60,300,m,segments=4)
        for sign in [-1,1]:
            s.beam((sign*.380*math.sin(math.pi/3),0,-.22),(sign*2.4357/length,0,-1.95/length),.029,m['dark'])
        s.spindle((0,.013,.35),.255,.097,.056,m)
        a.replace_mesh(idx,s.object(a,origin,length))
        for side,name in [(-1,'gripper_left'),(1,'gripper_right')]:
            n=node(a,name)
            if not n:continue
            old=a.mesh_objects[n['mesh']];lo,hi=bounds(old);center=(lo+hi)*.5;size=hi-lo
            g=Shape('AUREOLE articulated ivory gripper')
            g.ellipsoid((0,0,-size.z*.17),(size.x*.39,size.y*.54,size.z*.22),m['dark'],24,12)
            p=(side*-.20*size.x,.03*size.y,-size.z*.62)
            g.ellipsoid(p,(size.x*.32,size.y*.40,size.z*.43),m['white'],28,14)
            g.ellipsoid((p[0],size.y*.38,p[2]+size.z*.13),(size.x*.25,size.y*.08,size.z*.26),m['satin'],24,10)
            g.ellipsoid((p[0],0,-size.z*.93),(size.x*.35,size.y*.45,size.z*.15),m['dark'],24,12)
            g.ellipsoid((p[0],0,-size.z*1.05),(size.x*.19,size.y*.27,size.z*.045),m['energy'],20,10)
            g.band((0,size.y*.40,-size.z*.17),size.x*.16,size.z*.08,size.x*.035,size.y*.04,0,360,m['gold'],steps=12,profile=[(1,0),(.5,1),(-1,0),(0,-1)])
            a.replace_mesh(n['mesh'],g.object(a))
        n=node(a,'Cargo_optional')
        if n:
            old=a.mesh_objects[n['mesh']];lo,hi=bounds(old);size=(hi-lo)*.5
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1)
            obj=bpy.context.object;obj.name='AUREOLE captive amber cargo crystal'
            for v in obj.data.vertices:
                v.co.x*=size.x*.80;v.co.y*=size.y*.61;v.co.z*=size.z*1.07
                v.co*=1+.06*math.sin(v.co.x*8+v.co.z*5)
            for mat in a.materials:obj.data.materials.append(mat)
            for face in obj.data.polygons:face.material_index=m['crystal'];face.use_smooth=False
            wire=obj.copy();wire.data=obj.data.copy();wire.name='AUREOLE amber crystalline edges';bpy.context.collection.objects.link(wire)
            for face in wire.data.polygons:face.material_index=m['hot']
            mod=wire.modifiers.new('Fine crystalline seams','WIREFRAME');mod.thickness=max(size)*.004;mod.use_replace=True
            a.replace_mesh(n['mesh'],[obj,wire])
        return {'authored':'segmented ivory cargo cradle, articulated rounded grippers and faceted amber crystal'}
    # Research spindle is individually remodeled; moving oval sensor stays on
    # its original node so all scan animations remain valid.
    hull=node(a,'Hull');origin=Vector(hull.get('translation',[0,0,0]));lo,hi=bounds(a.mesh_objects[hull['mesh']]);length=hi.z-lo.z
    s=Shape('AUREOLE research axial ivory petals')
    s.spindle((0,origin.y/length,0),.99,.110,.066,m)
    s.eye((0,origin.y/length+.058,-.25),.037,.087,m,.015)
    a.replace_mesh(hull['mesh'],s.object(a,origin,length))
    sensor=node(a,'sensor_array')
    if sensor:
        ar=Shape('AUREOLE dark orbital instrument rim and amber focus')
        ar.band((0,0,0),2.145,4.10,.110,.065,0,360,m['dark'],steps=160)
        ar.band((0,0,0),2.245,4.20,.020,.025,0,360,m['white'],steps=160)
        ar.band((0,0,0),2.040,3.995,.015,.013,0,360,m['gold'],steps=160)
        ar.band((0,0,0),2.025,3.980,.009,.008,0,360,m['energy'],steps=160)
        rot=Matrix.Rotation(.78,3,'X');center=Vector((0,-.0665,.1604))
        ar.vertices=[tuple(center+rot@Vector(v)) for v in ar.vertices]
        p=(0,.0459,-.289)
        ar.ellipsoid(p,(.27,.35,.29),m['energy'],40,20)
        ar.band(p,.31,.33,.018,.012,0,360,m['gold'],steps=48)
        for j in range(32):
            t=j*math.pi/16;p=center+rot@Vector((2.045*math.sin(t),.042,-4.0*math.cos(t)))
            ar.ellipsoid(p,(.022,.022,.022),m['energy'],8,4)
        a.replace_mesh(sensor['mesh'],ar.object(a))
    return {'authored':'ivory research spindle, exposed instrument bed and bespoke dark gold orbital scanner'}


def fx(a,m):
    for n in a.document['nodes']:
        if not n.get('name','').startswith('FX_') or 'mesh' not in n:continue
        idx=n['mesh'];lo,hi=bounds(a.mesh_objects[idx]);r=max(hi-lo)*.5
        s=Shape('AUREOLE restrained amber marker lens')
        if n['name']=='FX_drive':
            s.ellipsoid((0,0,r*.45),(r*.36,r*.29,r*.84),m['plume'],8,4)
        else:s.ellipsoid((0,0,0),(r*.28,r*.35,r*.28),m['energy'],8,4)
        a.replace_mesh(idx,s.object(a))


def render_preview(a,model_id):
    folder=ROOT/'artifacts/model-remesh/aureole';folder.mkdir(parents=True,exist_ok=True)
    blend_folder=Path('C:/Users/paulp/AppData/Local/Temp/stellaris-remesh/aureole');blend_folder.mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    # Three.js treats absent COLOR_0 as white. Blender's Attribute node returns
    # black for an absent layer, so add the equivalent preview-only white layer
    # after GLB export. Painted lens fields remain untouched.
    for parts in a._parts.values():
        for part in parts:
            if not part.data.color_attributes.get('AureoleAmberRadiance'):
                layer=part.data.color_attributes.new(name='AureoleAmberRadiance',type='FLOAT_COLOR',domain='POINT')
                for color in layer.data:color.color=(1,1,1,1)
    a.save_blend(blend_folder/(model_id+'.blend'))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and not o.hide_render]
    orient=bpy.data.objects.new('AUREOLE preview orientation',None);bpy.context.collection.objects.link(orient)
    for obj in meshes:obj.parent=orient
    orient.rotation_euler.x=math.pi/2;bpy.context.view_layer.update()
    vs=[o.matrix_world@Vector(c) for o in meshes for c in o.bound_box];lo=Vector(tuple(min(v[i] for v in vs) for i in range(3)));hi=Vector(tuple(max(v[i] for v in vs) for i in range(3)))
    center=(lo+hi)*.5;span=max(hi-lo);scene=bpy.context.scene
    scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
    scene.render.resolution_x=1200;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new('Charcoal concept backdrop');scene.world.use_nodes=True
    bg=scene.world.node_tree.nodes.get('Background');bg.inputs['Color'].default_value=(.021,.020,.018,1);bg.inputs['Strength'].default_value=.38
    scene.view_settings.view_transform='AgX'
    for name,delta,power,color,size in [('Soft ivory key',(1,-1,2),1100,(1,.94,.82),1.6),('Narrow gold rim',(-1,1,1),1000,(1,.75,.44),1),('Soft neutral fill',(-1,-1,.4),500,(.78,.87,1),1.2)]:
        light=bpy.data.lights.new(name,'AREA');light.energy=power*span*span*.023;light.shape='DISK';light.size=span*size;light.color=color
        obj=bpy.data.objects.new(name,light);scene.collection.objects.link(obj);obj.location=center+Vector(delta)*span;obj.rotation_euler=(center-obj.location).to_track_quat('-Z','Y').to_euler()
    data=bpy.data.cameras.new('Concept inspection');obj=bpy.data.objects.new('Concept inspection',data);scene.collection.objects.link(obj);obj.location=center+Vector((.85,-1.3 if model_id=='08_forschung' else 1.3,1.28))*span
    obj.rotation_euler=(center-obj.location).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.ortho_scale=span*1.19;scene.camera=obj
    scene.use_nodes=True;tree=scene.node_tree;tree.nodes.clear();layers=tree.nodes.new('CompositorNodeRLayers');glare=tree.nodes.new('CompositorNodeGlare');glare.glare_type='FOG_GLOW';glare.threshold=1.7;glare.quality='HIGH';comp=tree.nodes.new('CompositorNodeComposite');tree.links.new(layers.outputs['Image'],glare.inputs['Image']);tree.links.new(glare.outputs['Image'],comp.inputs['Image'])
    reference=ROOT/'artifacts/concept-refit/aureole'/(model_id+'.blend')
    if reference.exists():
        # Import the previous accepted preview rig only. Its exact matrices,
        # focal scale, source powers and world are shared by the before/after.
        old_rig=[o for o in scene.objects if o.type in {'CAMERA','LIGHT'}]
        with bpy.data.libraries.load(str(reference),link=False) as (source,target):
            target.objects=[n for n in source.objects if n.startswith(('Concept inspection','Soft ivory key','Narrow gold rim','Soft neutral fill'))]
            target.worlds=[n for n in source.worlds if n.startswith('Charcoal concept backdrop')]
        for o in old_rig:bpy.data.objects.remove(o,do_unlink=True)
        for o in target.objects:
            if o is not None:
                scene.collection.objects.link(o)
                if o.type=='CAMERA':scene.camera=o
        if target.worlds:scene.world=target.worlds[0]
        original_png=reference.with_suffix('.png')
        if original_png.exists():shutil.copy2(original_png,folder/('before-'+model_id+'.png'))
    scene.render.image_settings.file_format='PNG';scene.render.filepath=str(folder/('after-'+model_id+'.png'));bpy.ops.wm.save_as_mainfile(filepath=str(blend_folder/(model_id+'.blend')));bpy.ops.render.render(write_still=True)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--only');parser.add_argument('--render',action='store_true');args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    folder=ROOT/'artifacts/model-remesh/aureole';folder.mkdir(parents=True,exist_ok=True);report=[]
    for model_id in asset_ids('aureole'):
        if args.only and model_id!=args.only:continue
        a=ConceptAsset('aureole',model_id);m=finishes(a)
        if model_id in ['01_korvette','02_fregatte','03_zerstoerer','04_kreuzer','05_schlachtschiff','06_titan']:entry=military(a,model_id,m)
        elif model_id in ['07_arbeiter','08_forschung']:entry=civilian(a,model_id,m)
        else:
            control_meshes(a);fitted=retessellate_ellipsoids(a)
            entry={'authored':'curved ivory shells with fitted dark undersides, gold returns and amber eyes','ellipsoid_control_surfaces':fitted,'collars':layered_originals(a,m)}
        fx(a,m);a.write()
        backup=(ROOT/'artifacts/model-remesh/before/aureole'/(model_id+'.glb')).read_bytes();before=json.loads(backup[20:20+struct.unpack_from('<I',backup,12)[0]])
        count=lambda d:sum(d['accessors'][p['indices']]['count']//3 for mesh in d['meshes'] for p in mesh['primitives'])
        entry.update(model=model_id,bytes=a.path.stat().st_size,before_triangles=count(before),after_triangles=count(a.document),nodes_unchanged=a.document['nodes']==before['nodes'],animations_unchanged=a.document.get('animations',[])==a.original_animations);report.append(entry)
        print(json.dumps(entry),flush=True)
        if args.render and model_id in ['01_korvette','04_kreuzer','06_titan','07_arbeiter','08_forschung','03_festung']:render_preview(a,model_id)
    report_path=folder/'report.json'
    previous=json.loads(report_path.read_text()) if args.only and report_path.exists() else []
    merged={r['model']:r for r in previous+report};report_path.write_text(json.dumps(list(merged.values()),indent=2)+'\n')


if __name__=='__main__':main()
