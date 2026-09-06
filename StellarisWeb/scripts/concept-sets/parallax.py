"""PARALLAX reference-sampled obsidian and gravitational membranes, Blender 4.5.

Run: blender --background --factory-startup --python scripts/concept-sets/parallax.py
     -- [--only 04_kreuzer] [--render]

Rock colours are baked from selected mineral faces in the supplied
parallax_concept.png onto the original coarse fracture planes. Curved membrane
fibres and coplanar gravity ripples use small transparent baked textures.
The original rigid-node hierarchy and all animation accessors are preserved.
"""
import argparse
from array import array
import json
import math
from pathlib import Path
import random
import struct
import sys
import zlib
import tempfile

import bpy
import numpy as np
from mathutils import Vector
from mathutils import noise

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from concept_asset import ConceptAsset, asset_ids

OUT = ROOT / 'artifacts/model-remesh/parallax'
BEFORE = ROOT / 'artifacts/model-remesh/before/parallax'
PREVIEW_BLENDS = Path(tempfile.gettempdir())/'stellaris-remesh/parallax'
REFERENCE = ROOT / 'artifacts/concept-reference/RTS_Designs/01_Sets/Parallax/parallax_concept.png'
# Image coordinates of actual, broad mineral faces, avoiding the typography,
# mint membranes and the bright rose edge lights around them.
SAMPLE_TRIANGLES = [
    ((503, 213), (638, 163), (550, 229)),
    ((514, 626), (553, 661), (568, 739)),
    ((1242, 605), (1259, 656), (1300, 686)),
    ((182, 690), (210, 710), (227, 750)),
    ((1350, 174), (1378, 130), (1364, 220)),
]


def png(path, rgb, alpha=None):
    """Write standard 8-bit sRGB PNGs from linear-light baked material data."""
    rgb=np.clip(rgb,0,1)
    encoded=np.where(rgb<=.0031308,rgb*12.92,1.055*np.power(rgb,1/2.4)-.055)
    pixels=np.clip(np.rint(encoded*255),0,255).astype(np.uint8)
    if alpha is not None:pixels=np.concatenate((pixels,np.clip(np.rint(alpha[...,None]*255),0,255).astype(np.uint8)),axis=2)
    height,width,channels=pixels.shape
    def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    scan=b''.join(b'\0'+pixels[row].tobytes() for row in range(height))
    data=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6 if channels==4 else 2,0,0,0))+chunk(b'IDAT',zlib.compress(scan,9))+chunk(b'IEND',b'')
    path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)


def phase(seed):return int(round(((seed*.7)%math.tau)/math.tau*12))%12


def mineral_uv(seed,u,v):
    tile=(seed%5)*12+phase(seed);x=tile%8;y=tile//8
    return ((x*128+2+u*123)/1023,1-(y*128+2+v*123)/1023)


def bake_maps(pixels,image_size):
    """Five actual reference faces, with twelve low-frequency light phases."""
    output=OUT/'textures';output.mkdir(parents=True,exist_ok=True)
    width,height=image_size;source=np.asarray(pixels,dtype=np.float32).reshape(height,width,4)
    atlas=np.zeros((1024,1024,3),dtype=np.float32)
    y,x=np.mgrid[0:128,0:128];u=np.clip((x-2)/123,0,1);v=np.clip((y-2)/123,0,1)
    scale=np.maximum(u+v,1);u=u/scale;v=v/scale;w=1-u-v
    for face,triangle in enumerate(SAMPLE_TRIANGLES):
        sx=sum(point[0]*weight for point,weight in zip(triangle,(u,v,w)))
        sy=sum(point[1]*weight for point,weight in zip(triangle,(u,v,w)))
        rgb=source[np.clip(height-1-sy.astype(int),0,height-1),np.clip(sx.astype(int),0,width-1),:3]
        rgb=np.where(rgb<=.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)
        lum=rgb.mean(axis=2);rgb=rgb*np.minimum(1,.15/np.maximum(lum,1e-8))[...,None]
        rgb=np.clip(rgb*.88,.004,.22)
        for p in range(12):
            shade=.90+.12*np.maximum(0,np.sin((u*.75+v)*17+p*math.tau/12))
            tile=face*12+p;tx=tile%8*128;ty=tile//8*128
            atlas[ty:ty+128,tx:tx+128]=np.minimum(.22,rgb*shade[...,None])
    png(output/'reference-obsidian.png',atlas)
    # The same two 24-fibre families as the high-poly source, expressed in
    # the membrane's barycentric coordinates, with pixel-area antialiasing.
    n=1024;y,x=np.mgrid[0:n,0:n];u=x/(n-1);v=y/(n-1);w=1-u-v
    edge=np.minimum(np.minimum(u,v),w)
    background_alpha=.09*(.36+.64*np.exp(-np.maximum(edge,0)*16))
    coverage=np.zeros((n,n))
    for coord in [u,v]:
        nearest=np.rint(coord*26);distance=np.abs(coord-nearest/26)
        line=np.clip((.00030+.5/n-distance)*n,0,1)*((nearest>=1)&(nearest<=24))
        coverage=1-(1-coverage)*(1-line)
    fiber_alpha=.60*coverage;alpha=fiber_alpha+background_alpha*(1-fiber_alpha)
    base=(np.array((.04,.21,.14))*fiber_alpha[...,None]+np.array((.056,.50,.272))*(background_alpha*(1-fiber_alpha))[...,None])/alpha[...,None]
    emission=(np.array((.08,.61,.38))*.65*fiber_alpha[...,None]+np.array((.022,.25,.14))*.20*(background_alpha*(1-fiber_alpha))[...,None])/alpha[...,None]
    png(output/'gravity-membrane.png',base,alpha)
    png(output/'gravity-membrane-emission.png',emission)


def bind_texture(asset,mat,path,emissive=False,alpha=False):
    texture=asset.embed_png_texture(path)
    asset.set_material_texture(mat,texture,base_color=not emissive,emissive=emissive)
    if alpha:
        material=asset.materials[mat];shader=material.node_tree.nodes.get('Principled BSDF')
        image=next(node for node in reversed(list(material.node_tree.nodes)) if node.type=='TEX_IMAGE')
        attr=material.node_tree.nodes.new('ShaderNodeVertexColor');attr.layer_name='ConceptColor'
        multiply=material.node_tree.nodes.new('ShaderNodeMath');multiply.operation='MULTIPLY'
        material.node_tree.links.new(image.outputs['Alpha'],multiply.inputs[0]);material.node_tree.links.new(attr.outputs['Alpha'],multiply.inputs[1])
        material.node_tree.links.new(multiply.outputs[0],shader.inputs['Alpha'])
        material.surface_render_method='DITHERED'
    return texture


def ripple_material(asset,mats,count,start,step,width,inner_rose):
    key=f'ripple-v2-{count}-{start:g}-{step:g}-{width:g}-{int(inner_rose)}'
    if key in mats:return mats[key]
    path=OUT/'textures'/(key+'.png');extent=start+(count-1)*step+width*2
    if not path.exists():
        n=512;y,x=np.mgrid[0:n,0:n];radius=np.hypot((x/(n-1)*2-1)*extent,(y/(n-1)*2-1)*extent)
        all_coverage=np.zeros((n,n));rose_coverage=np.zeros((n,n));pixel=2*extent/n
        for ring in range(count):
            coverage=np.clip((width+pixel*.5-np.abs(radius-(start+ring*step)))/pixel,0,1)
            all_coverage=np.maximum(all_coverage,coverage)
            if ring==0 and inner_rose:rose_coverage=coverage
        # Separate colour/emission values are baked for the optional rose rim.
        base=np.ones((n,n,3))*np.array((.04,.21,.14))
        emit=np.ones((n,n,3))*np.array((.08,.61,.38))*.325
        if inner_rose:
            mask=rose_coverage>0
            base[mask]=(.35,.04,.035);emit[mask]=(1,.33,.29)
        png(path,base,all_coverage*.73)
        if inner_rose:png(path.with_name(path.stem+'-emission.png'),emit)
    material=asset.add_material('PARALLAX | Baked gravity ripple '+key,color=(1,1,1,1),metal=0,rough=.5,
                               emission=(1,1,1) if inner_rose else (.08,.61,.38),strength=2 if inner_rose else .65,role='field')
    asset.document['materials'][material].update(alphaMode='BLEND',doubleSided=True)
    bind_texture(asset,material,path,alpha=True)
    if inner_rose:bind_texture(asset,material,path.with_name(path.stem+'-emission.png'),emissive=True)
    mats[key]=material;return material


def ripple_sheet(shape,asset,mats,center,radius,count,start,step,tilt=.15,width=.01,inner_rose=False,flatten=1,x_tilt=0,alpha=1):
    material=ripple_material(asset,mats,count,start,step,width,inner_rose)
    extent=(start+(count-1)*step+width*2)*radius
    vertices=[center+Vector((x*extent,z*extent*tilt+x*extent*x_tilt,z*extent*flatten)) for x,z in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    shape.add(vertices,[(0,1,2),(0,2,3)],material,colors=[(1,1,1,alpha)]*4,uvs=[(0,0),(1,0),(1,1),(0,1)])


def read_reference():
    im = bpy.data.images.load(str(REFERENCE), check_existing=True)
    pixels = array('f', [0.0]) * len(im.pixels)
    im.pixels.foreach_get(pixels)
    return pixels, tuple(im.size)


def sample_mineral(pixels, image_size, face_id, u, v, w):
    tri = SAMPLE_TRIANGLES[face_id % len(SAMPLE_TRIANGLES)]
    x = sum(t[0] * f for t, f in zip(tri, (u, v, w)))
    y = sum(t[1] * f for t, f in zip(tri, (u, v, w)))
    width, height = image_size
    i = (max(0, min(height - 1, height - 1 - int(y))) * width + max(0, min(width - 1, int(x)))) * 4
    # The image is a lit concept painting. Limit the isolated painted highlights
    # to keep the surface dark under the game's own illumination, but retain
    # the actual colour and fine mineral striation from the painting.
    # Blender's PNG pixel buffer retains the encoded sRGB values here, while
    # glTF COLOR_0 and Blender colour attributes are linear-light values.
    rgb = [pixels[i+k]/12.92 if pixels[i+k] <= .04045 else ((pixels[i+k]+.055)/1.055)**2.4 for k in range(3)]
    lum = sum(rgb) / 3
    if lum > .15:
        rgb = [c * .15 / lum for c in rgb]
    return (*[max(.004, min(.22, c * .88)) for c in rgb], 1)


class RawAsset:
    def __init__(self, model_id):
        p = ROOT / 'artifacts/model-import/surface-originals/parallax' / (model_id + '.glb')
        d = p.read_bytes(); n = struct.unpack_from('<I', d, 12)[0]
        self.j = json.loads(d[20:20+n]); self.binary = d[28+n:]

    def accessor(self, index):
        a = self.j['accessors'][index]; b = self.j['bufferViews'][a['bufferView']]
        n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
        f = '<' + {5121: 'B', 5123: 'H', 5125: 'I', 5126: 'f'}[a['componentType']] * n
        stride = b.get('byteStride', struct.calcsize(f))
        offset = b.get('byteOffset', 0) + a.get('byteOffset', 0)
        return [struct.unpack_from(f, self.binary, offset + i * stride) for i in range(a['count'])]

    def triangles(self, mesh_id):
        result = []
        for p in self.j['meshes'][mesh_id]['primitives']:
            points = [Vector(q) for q in self.accessor(p['attributes']['POSITION'])]
            indices = [q[0] for q in self.accessor(p['indices'])]
            result += [(p.get('material', 0), [points[x] for x in indices[i:i+3]]) for i in range(0, len(indices), 3)]
        return result


class Shape:
    def __init__(self, name):
        self.name = name; self.vertices = []; self.faces = []; self.mats = []; self.colors = []; self.uvs=[]

    def add(self, vertices, faces, mat, colors=None,uvs=None):
        off = len(self.vertices)
        self.vertices += [tuple(v) for v in vertices]
        self.faces += [tuple(off+i for i in f) for f in faces]
        self.mats += [mat]*len(faces)
        self.colors += colors if colors is not None else [(1,1,1,1)]*len(vertices)
        self.uvs += uvs if uvs is not None else [(0,0)]*len(vertices)

    def tube(self, points, radius, mat, sides=3):
        if len(points) < 2: return
        points = list(map(Vector, points)); vertices = []
        for i,p in enumerate(points):
            axis = (points[min(i+1,len(points)-1)] - points[max(i-1,0)]).normalized()
            side = axis.cross(Vector((0,1,0)))
            if side.length < .01: side = axis.cross(Vector((1,0,0)))
            side.normalize(); up = axis.cross(side).normalized()
            vertices += [p+(side*math.cos(math.tau*j/sides)+up*math.sin(math.tau*j/sides))*radius for j in range(sides)]
        faces = [(i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j) for i in range(len(points)-1) for j in range(sides)]
        self.add(vertices, faces, mat)

    def sphere(self, center, radius, mat, segments=12, rings=6):
        center = Vector(center); verts = []
        for y in range(rings+1):
            a = math.pi*y/rings
            for x in range(segments):
                b = math.tau*x/segments
                verts.append(center+Vector((math.sin(a)*math.cos(b),math.cos(a),math.sin(a)*math.sin(b)))*radius)
        faces = []
        for y in range(rings):
            for x in range(segments):
                nx=(x+1)%segments
                if y>0: faces.append((y*segments+x,(y+1)*segments+x,y*segments+nx))
                if y<rings-1: faces.append((y*segments+nx,(y+1)*segments+x,(y+1)*segments+nx))
        self.add(verts,faces,mat)

    def object(self, asset):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.vertices, [], self.faces); mesh.update()
        for mat in asset.materials: mesh.materials.append(mat)
        for p,m in zip(mesh.polygons,self.mats): p.material_index=m; p.use_smooth=True
        layer=mesh.color_attributes.new(name='ConceptColor',type='FLOAT_COLOR',domain='POINT')
        for d,c in zip(layer.data,self.colors): d.color=c
        mesh.color_attributes.active_color=layer
        uv=mesh.uv_layers.new(name='BakedConceptUV')
        for loop in mesh.loops:uv.data[loop.index].uv=self.uvs[loop.vertex_index]
        obj=bpy.data.objects.new(self.name,mesh);bpy.context.collection.objects.link(obj)
        return obj


def components(triangles):
    lookup={}; coords=[]; faces=[]; mats=[]
    for mat, tri in triangles:
        face=[]
        for v in tri:
            k=tuple(round(float(x),5) for x in v)
            if k not in lookup: lookup[k]=len(coords);coords.append(v)
            face.append(lookup[k])
        faces.append(face);mats.append(mat)
    neighbours=[set() for p in coords]
    for f in faces:
        for i in f: neighbours[i].update(f)
    pending=set(range(len(coords))); groups=[]
    while pending:
        seed=pending.pop();group={seed};stack=[seed]
        while stack:
            for j in neighbours[stack.pop()]:
                if j in pending: pending.remove(j);group.add(j);stack.append(j)
        groups.append(group)
    result=[]
    for group in groups:
        selected=[(m,[coords[i] for i in f]) for f,m in zip(faces,mats) if f[0] in group]
        result.append((selected,[coords[i] for i in group]))
    return result


def mineral_face(shape, triangle, mat, seed, pixels, image_size, density, sample_coords=None):
    a,b,c=triangle; normal=(b-a).cross(c-a)
    if normal.length < 1e-8: return
    normal.normalize(); span=max((a-b).length,(b-c).length,(c-a).length)
    # Only the already-authored macro fracture plane remains geometric. The
    # mineral painting and its fine strata now live in a reference-baked atlas.
    density=1
    vertices=[]; colors=[]; uvs=[]; grid={}; rng=random.Random(seed)
    for i in range(density+1):
        for j in range(density+1-i):
            u=i/density; v=j/density; w=1-u-v
            if min(u,v,w)>.0001:
                u+=rng.uniform(-.22,.22)/density;v+=rng.uniform(-.22,.22)/density;w=1-u-v
            p=a*u+b*v+c*w
            interior=max(0,math.sin(math.pi*u)*math.sin(math.pi*v)*math.sin(math.pi*w))
            # Small conchoidal breaks within the large original sharp faces.
            stratum=math.sin((u*.75+v)*17+seed*.7)
            relief=interior*noise.noise(Vector((u*10,v*4,seed*.21)))*.0004
            p+=normal*span*relief
            grid[i,j]=len(vertices);vertices.append(p)
            su,sv,sw=(u,v,w) if sample_coords is None else tuple(sum(t[k]*f for t,f in zip(sample_coords,(u,v,w))) for k in range(3))
            uvs.append(mineral_uv(seed,su,sv));colors.append((1,1,1,1))
    faces=[]
    for i in range(density):
        for j in range(density-i):
            faces.append((grid[i,j],grid[i+1,j],grid[i,j+1]))
            if j<density-i-1:faces.append((grid[i+1,j],grid[i+1,j+1],grid[i,j+1]))
    shape.add(vertices,faces,mat,colors,uvs)


def rock_region(shape, triangles, points, mats, seed, pixels, image_size, density):
    if not points: return
    span=max(max(p[k] for p in points)-min(p[k] for p in points) for k in range(3))
    edges={}
    for j,(mat,triangle) in enumerate(triangles):
        # Split each primary crystalline face into a few sharp, irregular
        # conchoidal fracture planes. The painted mineral coordinates remain
        # continuous over these geometric fractures instead of tiling a crop.
        a,b,c=triangle;normal=(b-a).cross(c-a).normalized();scale=max((a-b).length,(b-c).length,(c-a).length)
        count=3 if density>=9 else 2;grid={};rng=random.Random(seed+j*19)
        for x in range(count+1):
            for y in range(count+1-x):
                u=x/count;v=y/count;w=1-u-v
                if min(u,v,w)>.001:u+=rng.uniform(-.16,.16)/count;v+=rng.uniform(-.16,.16)/count;w=1-u-v
                p=a*u+b*v+c*w
                p+=normal*scale*max(0,math.sin(math.pi*u)*math.sin(math.pi*v)*math.sin(math.pi*w))*rng.uniform(-.025,.018)
                grid[x,y]=(p,(u,v,w))
        for x in range(count):
            for y in range(count-x):
                child=[(grid[x,y],grid[x+1,y],grid[x,y+1])]
                if y<count-x-1:child.append((grid[x+1,y],grid[x+1,y+1],grid[x,y+1]))
                for face in child:mineral_face(shape,[q[0] for q in face],mats['rock'],seed+j,pixels,image_size,max(2,density//count),[q[1] for q in face])
        normal=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized()
        for u,v in [(0,1),(1,2),(2,0)]:
            pa,pb=triangle[u],triangle[v]
            key=tuple(sorted((tuple(round(x,5) for x in pa),tuple(round(x,5) for x in pb))))
            if key not in edges:edges[key]=[pa,pb,[]]
            edges[key][2].append(normal)
    # Only a few outward cutting edges carry rose light. No luminous wireframe.
    candidates=[]
    for pa,pb,norms in edges.values():
        if len(norms)<2 or abs(norms[0].dot(norms[-1]))>.985:continue
        length=(pa-pb).length
        outward=sum((n.dot(Vector((.48,.80,-.30))) for n in norms))/len(norms)
        candidates.append((length*(.7+outward*.35),pa,pb,norms))
    candidates.sort(key=lambda x:x[0],reverse=True)
    for k,(_,pa,pb,norms) in enumerate(candidates[:2]):
        n=sum(norms,Vector()).normalized(); offset=n*span*.0012
        shape.tube([pa+offset,pb+offset],span*(.00135 if k==0 else .0007),mats['rose'],4)


def patch_point(corners, u, v):
    a,b,c=corners;w=1-u-v;center=(a+b+c)/3
    point=a*u+b*v+c*w
    contraction=.62*(1-u**4-v**4-w**4)
    normal=(b-a).cross(c-a).normalized();span=max((a-b).length,(b-c).length,(c-a).length)
    return point+(center-point)*contraction+normal*span*.075*27*u*v*w


def field_region(shape, points, mats, seed, hole=False):
    if len(points)<3:return
    # Farthest endpoints and farthest distance to their axis identify the three
    # original anchors independently of model orientation and animation node.
    p0=points[0];a=max(points,key=lambda p:(p-p0).length_squared)
    b=max(points,key=lambda p:(p-a).length_squared)
    axis=b-a;c=max(points,key=lambda p:axis.cross(p-a).length_squared)
    if axis.cross(c-a).length<1e-7:return
    corners=(a,b,c);center=(a+b+c)/3;span=max((a-b).length,(a-c).length,(b-c).length)
    # Keep the exact original aperture contour on holed membranes. Other
    # concave patches need only twelve samples per side for their curvature.
    n=28 if hole else 12;verts=[];faces=[];colors=[];uvs=[];grid={}
    normal=(b-a).cross(c-a).normalized()
    for i in range(n+1):
        for j in range(n+1-i):
            u=i/n;v=j/n;w=1-u-v;p=patch_point(corners,u,v)
            grid[i,j]=len(verts);verts.append(p)
            edge=min(u,v,w);alpha=.36+.64*math.exp(-edge*16)
            colors.append((1,1,1,1));uvs.append((u,1-v))
    for i in range(n):
        for j in range(n-i):
            for tri in [(grid[i,j],grid[i+1,j],grid[i,j+1])]+([(grid[i+1,j],grid[i+1,j+1],grid[i,j+1])] if j<n-i-1 else []):
                mid=sum((verts[k] for k in tri),Vector())/3
                if not hole or (mid-center).length>span*.10:faces.append(tri)
    shape.add(verts,faces,mats['field'],colors,uvs)
    # Both original families of 24 delicate fibres are baked onto this exact
    # curved patch. Only the bright physical boundary curves need geometry.
    for edge in range(3):
        points=[]
        for j in range(17):
            t=j/16;uv=[(t,1-t),(0,t),(t,0)][edge]
            points.append(patch_point(corners,*uv)+normal*span*.001)
        shape.tube(points,span*.00050,mats['mint'])


def finishes(a):
    for i,m in enumerate(a.document['materials']):
        name=m['name'].lower()
        if 'emission' in name:
            a.set_material(i,color=(.014,.25,.15,1),metal=.05,rough=.25,emission=(.08,.82,.50),strength=1.5,role='energy')
        elif 'core' in name:
            a.set_material(i,color=(.3,.05,.05,1),metal=.05,rough=.25,emission=(1,.38,.35),strength=1.3,role='energy')
        elif 'structure' in name:
            a.set_material(i,color=(.08,.46,.30,.10),metal=0,rough=.32,emission=(.015,.25,.13),strength=.22,role='field')
            m['alphaMode']='BLEND';m['doubleSided']=True
        else:a.set_material(i,color=(1,1,1,1),metal=.30,rough=.32,emission=(0,0,0),strength=0,role='hull',coat=.38)
    mats={
        'rock':a.add_material('PARALLAX | Actual concept obsidian mineral',color=(1,1,1,1),metal=.72,rough=.51,role='hull',coat=.04,conceptReference='parallax_concept.png',conceptColorSource='Five sampled mineral face triangles baked to UV atlas'),
        'rose':a.add_material('PARALLAX | Rose cutting edge',color=(.35,.04,.035,1),metal=.1,rough=.28,emission=(1,.33,.29),strength=2.0,role='energy'),
        'mint':a.add_material('PARALLAX | Mint gravity anchor',color=(.035,.35,.22,1),metal=.05,rough=.28,emission=(.05,1,.62),strength=2.0,role='energy'),
        'fiber':a.add_material('PARALLAX | Fine curved field fibers',color=(.04,.21,.14,.48),metal=0,rough=.5,emission=(.08,.61,.38),strength=.65,role='field'),
        'field':a.add_material('PARALLAX | Concave transparent gravity membrane',color=(1,1,1,1),metal=0,rough=.38,emission=(1,1,1),strength=1,role='field'),
        'cargo':a.add_material('PARALLAX | Suspended mint crystal',color=(.06,.65,.40,.30),metal=.05,rough=.16,emission=(.035,.55,.30),strength=.48,role='field'),
        'void':a.add_material('PARALLAX | Dark gravitational lens',color=(.0015,.004,.005,1),metal=.35,rough=.23,role='hull'),
    }
    for key in ['field','fiber','cargo']:
        a.document['materials'][mats[key]].update(alphaMode='BLEND',doubleSided=True)
    # Blender's material graph must display the same baked reference colours
    # and transparency that GLTFLoader reads from COLOR_0 in the game.
    for i,mat in enumerate(a.materials):
        shader=mat.node_tree.nodes.get('Principled BSDF')
        attr=mat.node_tree.nodes.new('ShaderNodeVertexColor');attr.layer_name='ConceptColor'
        mix=mat.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
        mix.inputs[1].default_value=shader.inputs['Base Color'].default_value
        mat.node_tree.links.new(attr.outputs['Color'],mix.inputs[2]);mat.node_tree.links.new(mix.outputs['Color'],shader.inputs['Base Color'])
        if mat.get('conceptRole')=='field':
            alpha=mat.node_tree.nodes.new('ShaderNodeMath');alpha.operation='MULTIPLY';alpha.inputs[0].default_value=shader.inputs['Alpha'].default_value
            mat.node_tree.links.new(attr.outputs['Alpha'],alpha.inputs[1]);mat.node_tree.links.new(alpha.outputs[0],shader.inputs['Alpha'])
            mat.surface_render_method='DITHERED'
    bind_texture(a,mats['rock'],OUT/'textures/reference-obsidian.png')
    bind_texture(a,mats['field'],OUT/'textures/gravity-membrane.png',alpha=True)
    bind_texture(a,mats['field'],OUT/'textures/gravity-membrane-emission.png',emissive=True)
    return mats


def refit(a, model_id, pixels, image_size):
    raw=RawAsset(model_id);mats=finishes(a)
    total_faces=0;rocks=fields=0
    for idx,mesh in enumerate(raw.j['meshes']):
        triangles=raw.triangles(idx);shape=Shape('PARALLAX concept mineral / membranes / fibers')
        solid=[];membrane=[];retained=[]
        for mat,tri in triangles:
            name=raw.j['materials'][mat]['name'].lower()
            if any(word in name for word in ['hull','facet']):solid.append((mat,tri))
            elif 'structure' in name:membrane.append((mat,tri))
            else:retained.append((mat,tri))
        groups=components(solid)
        # Retain the approved coarse fracture count for every class. Surface
        # painting density now belongs to the atlas rather than the mesh.
        density=18 if model_id in ['01_korvette','02_fregatte','03_zerstoerer','04_kreuzer','05_schlachtschiff','06_titan','07_arbeiter','08_forschung'] else 9
        if model_id=='03_dyson_swarm':density=5
        for ci,(faces,points) in enumerate(groups):
            rock_region(shape,faces,points,mats,idx*107+ci*31,pixels,image_size,density);rocks+=1
        for fi,(faces,points) in enumerate(components(membrane)):
            field_region(shape,points,mats,idx*13+fi,hole=model_id in ['05_schlachtschiff','06_titan','04_zitadelle']);fields+=1
        if membrane:
            for faces,points in components(retained):
                if not points:continue
                lo=Vector(tuple(min(p[k] for p in points) for k in range(3)));hi=Vector(tuple(max(p[k] for p in points) for k in range(3)));dims=hi-lo;radius=max(dims)*.46
                # Dense old contour beams do not follow the newly curved
                # membranes. Rebuild only their compact spherical foci.
                if len(faces)<=16 and min(dims)>max(dims)*.45:
                    center=(lo+hi)/2;source_mat=faces[0][0]
                    is_rose='Core' in raw.j['materials'][source_mat]['name'];fm=mats['rose'] if is_rose else mats['mint']
                    dark_lens=not is_rose and model_id in ['03_zerstoerer','04_kreuzer','05_schlachtschiff']
                    shape.sphere(center,radius*(1.15 if dark_lens else .8),mats['void'] if dark_lens else fm)
                    ripple_sheet(shape,a,mats,center,radius,7,1.30,.28,.18)
        elif model_id=='08_forschung' and mesh['name']=='Sensor stone A':
            for faces,points in components(retained):
                if len(faces)<=32:
                    for mat,tri in faces:shape.add(tri,[(0,1,2)],mat)
            points=[p for _,tri in retained for p in tri]
            lo=Vector(tuple(min(p[k] for p in points) for k in range(3)));hi=Vector(tuple(max(p[k] for p in points) for k in range(3)));center=(lo+hi)/2;radius=max(hi-lo)*.43
            for j in range(11):
                r=radius*(.57+j*.052);tilt=-.45+j*.09
                # Each interference ellipse is planar even though their
                # planes differ. Keep its exact tilt and flattening; a shared
                # antialiased annulus has no visible low-poly curve corners.
                ripple_sheet(shape,a,mats,center,r,1,1,0,tilt,width=.002,flatten=.86,x_tilt=.12,alpha=radius*.0007/(r*.002))
        else:
            for mat,tri in retained:shape.add(tri,[(0,1,2)],mat)
        if model_id=='07_arbeiter' and mesh['name']=='Cargo_optional':
            points=[p for _,tri in triangles for p in tri]
            lo=Vector(tuple(min(p[k] for p in points) for k in range(3)));hi=Vector(tuple(max(p[k] for p in points) for k in range(3)));center=(lo+hi)/2;span=max(hi-lo)*.60
            shape=Shape('PARALLAX suspended transparent faceted cargo crystal')
            vertices=[]
            for y,r in [(-.68,.20),(-.36,.44),(.34,.41),(.70,.19)]:
                vertices += [center+Vector((math.cos(math.tau*k/6)*r,y,math.sin(math.tau*k/6)*r))*span for k in range(6)]
            faces=[tuple(reversed(range(6))),tuple(range(18,24))]
            faces += [(j*6+k,j*6+(k+1)%6,(j+1)*6+(k+1)%6,(j+1)*6+k) for j in range(3) for k in range(6)]
            shape.add(vertices,faces,mats['cargo'])
            for k in range(6):shape.tube([vertices[j*6+k] for j in range(4)],span*.0035,mats['mint'],3)
            shape.sphere(center,span*.12,mats['mint'],12,6)
        if model_id=='07_arbeiter' and mesh['name']=='Tractor filament':
            hull_node=next(n for n in a.document['nodes'] if n.get('mesh')==idx);offset=Vector(hull_node.get('translation',[0,0,0]))
            anchors=[Vector(n.get('translation',[0,0,0]))-offset for n in a.document['nodes'] if n.get('name','').startswith('gripper_')]
            if len(anchors)==3:
                field_region(shape,anchors,mats,17,hole=True);fields+=1
        if model_id=='08_forschung' and mesh['name']=='Energy focus.007':
            points=[p for _,tri in triangles for p in tri];lo=Vector(tuple(min(p[k] for p in points) for k in range(3)));hi=Vector(tuple(max(p[k] for p in points) for k in range(3)));center=(lo+hi)/2;radius=max(hi-lo)*.28
            shape=Shape('PARALLAX interferometer rose lens');shape.sphere(center,radius,mats['void'])
            ripple_sheet(shape,a,mats,center,radius,5,1.4,.22,.15,inner_rose=True)
        if mesh['name'].startswith('FX_'):
            points=[p for _,tri in triangles for p in tri];lo=Vector(tuple(min(p[k] for p in points) for k in range(3)));hi=Vector(tuple(max(p[k] for p in points) for k in range(3)));center=(lo+hi)/2;radius=max(hi-lo)*.23
            shape=Shape('PARALLAX gravitational focus pulse');shape.sphere(center,radius,mats['mint'],12,6)
        # The small corvette's central suspended focus is spherical in the
        # painting, with several fine gravity ripples instead of a white cube.
        if model_id=='01_korvette' and mesh['name']=='Energy focus':
            energy=next((i for i,m in enumerate(raw.j['materials']) if 'Emission' in m['name']),0)
            focus=[p for mat,tri in retained if mat==energy for p in tri]
            if focus:
                lo=Vector(tuple(min(p[k] for p in focus) for k in range(3)));hi=Vector(tuple(max(p[k] for p in focus) for k in range(3)));center=(lo+hi)/2;radius=max(hi-lo)*.48
                shape=Shape('PARALLAX suspended mint lens and gravity ripples')
                for mat,tri in retained:
                    if mat!=energy:shape.add(tri,[(0,1,2)],mat)
                shape.sphere(center,radius*.72,mats['mint'])
                ripple_sheet(shape,a,mats,center,radius,5,1,.15,.15,width=.011)
        if shape.faces:
            total_faces+=len(shape.faces);a.replace_mesh(idx,shape.object(a))
    # Stage the complete export first. A disk-full failure must never truncate
    # the currently valid runtime asset.
    staged=OUT/'staging'/(model_id+'.glb');a.write(staged);staged.replace(a.path)
    triangles=sum(a.document['accessors'][p['indices']]['count']//3 for m in a.document['meshes'] for p in m['primitives'])
    return dict(model=model_id,mineral_regions=rocks,curved_membranes=fields,triangles=triangles,clips=len(a.document.get('animations',[])),bytes=a.path.stat().st_size)


def render_preview(a, model_id):
    bpy.context.preferences.filepaths.save_version=0
    OUT.mkdir(parents=True,exist_ok=True);PREVIEW_BLENDS.mkdir(parents=True,exist_ok=True);a.save_blend(PREVIEW_BLENDS/(model_id+'.blend'))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and not o.hide_render]
    root=bpy.data.objects.new('PARALLAX Y-up preview orientation',None);bpy.context.collection.objects.link(root)
    for obj in meshes:obj.parent=root
    root.rotation_euler.x=math.pi/2;bpy.context.view_layer.update()
    corners=[obj.matrix_world@Vector(c) for obj in meshes for c in obj.bound_box]
    lo=Vector(tuple(min(v[k] for v in corners) for k in range(3)));hi=Vector(tuple(max(v[k] for v in corners) for k in range(3)));center=(lo+hi)/2;span=max(hi-lo)
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.cycles.transparent_max_bounces=64
    scene.render.resolution_x=1100;scene.render.resolution_y=950;scene.render.resolution_percentage=100
    if scene.world is None:scene.world=bpy.data.worlds.new('Charcoal concept space')
    scene.world.use_nodes=True;bg=scene.world.node_tree.nodes.get('Background');bg.inputs['Color'].default_value=(.016,.021,.025,1);bg.inputs['Strength'].default_value=.5
    scene.view_settings.view_transform='AgX'
    for name,delta,power,color,size in [('Mineral edge softbox',(-1,-1,2),1400,(.8,.91,1),1.5),('Neutral mineral rim',(1,1,.5),1100,(.80,.86,.94),1.0),('Mint field fill',(-1,1,.3),350,(.48,1,.81),.9)]:
        light=bpy.data.lights.new(name,'AREA');light.energy=power*span*span*.025;light.shape='DISK';light.size=span*size;light.color=color
        o=bpy.data.objects.new(name,light);scene.collection.objects.link(o);o.location=center+Vector(delta)*span;o.rotation_euler=(center-o.location).to_track_quat('-Z','Y').to_euler()
    cam=bpy.data.cameras.new('PARALLAX concept inspection');o=bpy.data.objects.new('PARALLAX concept inspection',cam);scene.collection.objects.link(o)
    o.location=center+Vector((.83,-1.35,1.55))*span;o.rotation_euler=(center-o.location).to_track_quat('-Z','Y').to_euler();cam.type='ORTHO';cam.ortho_scale=span*(1.38 if model_id=='07_arbeiter' else 1.12);scene.camera=o
    scene.use_nodes=True;tree=scene.node_tree;tree.nodes.clear();layers=tree.nodes.new('CompositorNodeRLayers');glow=tree.nodes.new('CompositorNodeGlare');glow.glare_type='FOG_GLOW';glow.quality='HIGH';glow.threshold=1.4;comp=tree.nodes.new('CompositorNodeComposite');tree.links.new(layers.outputs['Image'],glow.inputs['Image']);tree.links.new(glow.outputs['Image'],comp.inputs['Image'])
    scene.render.image_settings.file_format='PNG';scene.render.filepath=str(OUT/(model_id+'.png'));bpy.ops.wm.save_as_mainfile(filepath=str(PREVIEW_BLENDS/(model_id+'.blend')),compress=True);bpy.ops.render.render(write_still=True)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--only');parser.add_argument('--render',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    pixels,image_size=read_reference();bake_maps(pixels,image_size);report=[]
    for model_id in asset_ids('parallax'):
        if args.only and args.only!=model_id:continue
        a=ConceptAsset('parallax',model_id,source=BEFORE/(model_id+'.glb'));entry=refit(a,model_id,pixels,image_size);report.append(entry);print(json.dumps(entry),flush=True)
        if args.render and model_id in ['01_korvette','04_kreuzer','06_titan','07_arbeiter','08_forschung','03_festung','02_mining_ring','04_mega_shipyard']:render_preview(a,model_id)
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/('report-'+args.only+'.json' if args.only else 'report.json')).write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':main()
