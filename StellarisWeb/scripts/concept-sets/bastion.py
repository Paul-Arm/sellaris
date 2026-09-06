"""BASTION concept refit and authored runtime retopology, Blender 4.5.

blender --background --python scripts/concept-sets/bastion.py -- --render

The source is the supplied bastion_concept.png: broad navy armor modules, slate
caps, inset magenta engine cells, and squat stepped artillery. No mechanical
tile, grunge, vent, or generic science-fiction texture is used. Details are real
geometry fitted to each original module. Animation-bearing GLB nodes are kept.

The default command remeshes the immutable accepted concept snapshot in
artifacts/model-remesh/before/bastion. It recovers dense armor solids from their
six external face planes and removes proven enclosed interior faces, retaining
all authored material assignments and node/animation data. --dry-run writes GLB
previews to C:/Temp without changing the public models. The original refit
functions below document the first concept construction, but are not rerun by
the retopology path.
"""
import argparse
import bmesh
import bpy
import json
import math
from pathlib import Path
import sys
from mathutils import Vector, Matrix

ROOT = Path.cwd()
sys.path.insert(0, str(ROOT / 'scripts'))
from concept_asset import ConceptAsset

OUT = ROOT / 'artifacts/concept-refit/bastion'
OUT.mkdir(parents=True, exist_ok=True)


def box(name, center, size, axes, material, materials, bevel=0.0):
    center = Vector(center)
    axes = [Vector(v) for v in axes]
    mesh = bpy.data.meshes.new(name)
    corners = [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),
               (-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]
    vertices = [center + sum((axes[i]*size[i]*c[i]*0.5 for i in range(3)), Vector()) for c in corners]
    mesh.from_pydata(vertices, [], [(0,3,2,1),(4,5,6,7),(0,1,5,4),
                                   (1,2,6,5),(2,3,7,6),(3,0,4,7)])
    mesh.update()
    for m in materials:
        mesh.materials.append(m)
    for polygon in mesh.polygons:
        polygon.material_index = material
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if bevel > 0:
        mod = obj.modifiers.new('Concept chamfer', 'BEVEL')
        mod.width = bevel
        mod.segments = 1
        mod.use_clamp_overlap = True
        mod.harden_normals = True
        weighted = obj.modifiers.new('Broad armor normals', 'WEIGHTED_NORMAL')
        weighted.keep_sharp = True
        weighted.weight = 40
    return obj


def components(obj):
    """Weld split normal vertices solely for detecting original disconnected boxes."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    span = max(max(v.co[i] for v in bm.verts)-min(v.co[i] for v in bm.verts) for i in range(3))
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=max(span*1e-6, 1e-7))
    bm.normal_update()
    todo = set(bm.verts)
    result = []
    while todo:
        first = todo.pop()
        found, stack = {first}, [first]
        while stack:
            v = stack.pop()
            for edge in v.link_edges:
                other = edge.other_vert(v)
                if other in todo:
                    todo.remove(other)
                    found.add(other)
                    stack.append(other)
        faces = sorted({f for v in found for f in v.link_faces},key=lambda f:(f.material_index,*(round(x,6) for x in f.calc_center_median()),*(round(x,6) for x in f.normal)))
        area_by_material = {}
        for face in faces:
            area_by_material[face.material_index] = area_by_material.get(face.material_index, 0) + face.calc_area()
        dominant = max(area_by_material, key=area_by_material.get)
        result.append({
            'points': [v.co.copy() for v in sorted(found,key=lambda v:tuple(v.co))],
            'faces': [(f.normal.copy(), f.calc_center_median().copy(), f.calc_area(),
                       [v.co.copy() for v in f.verts]) for f in faces],
            'material': dominant,
        })
    bm.free()
    return sorted(result,key=lambda q:(q['material'],*(round(min(p[i] for p in q['points']),5) for i in range(3))))


def face_plane(component, upward=True):
    """Find a broad actual box face, rather than using an axis-aligned decal."""
    grouped = {}
    for normal, center, area, verts in component['faces']:
        if area <= 1e-10:
            continue
        key = tuple(round(x*200) for x in normal)
        group = grouped.setdefault(key, {'normal': normal, 'area': 0, 'points': []})
        group['area'] += area
        group['points'].extend(verts)
    eligible = [g for g in grouped.values() if not upward or g['normal'].y > .65]
    if not eligible:
        return None
    plane = max(eligible, key=lambda g: (round(g['area'],5),round(g['normal'].y,4),round(g['normal'].z,4),round(g['normal'].x,4)))
    n = plane['normal'].normalized()
    points = plane['points']
    # Longest edge of this planar face gives a stable box-aligned tangent.
    origin = sum(points, Vector()) / len(points)
    candidates = []
    for _, _, _, verts in component['faces']:
        for i, a in enumerate(verts):
            d = verts[(i+1)%len(verts)]-a
            if d.length > 1e-8 and abs(d.normalized().dot(n)) < .015:
                candidates.append(d)
    if not candidates:
        return None
    # Original box-face diagonals can be longer than edges. Restrict tangent to
    # edges shared with a non-coplanar face by preferring principal coordinates
    # for ship modules. The generic fallback also suits radial dock modules.
    direction = max(candidates, key=lambda d: d.length).normalized()
    if abs(n.y) > .995:
        xs = [p.x for p in points]; zs = [p.z for p in points]
        # For axis-aligned modules use exact x/z. Radial blocks stay face-aligned.
        edge_axes = [d.normalized() for d in candidates if abs(d.normalized().x) > .995 or abs(d.normalized().z) > .995]
        if edge_axes:
            direction = Vector((0,0,1)) if max(zs)-min(zs) > max(xs)-min(xs) else Vector((1,0,0))
    u = direction - n*direction.dot(n)
    u.normalize()
    v = n.cross(u).normalized()
    # Eliminate triangulation diagonals: choose the tangent with the smallest
    # rectangle area, recovering the oriented rectangle of the original face.
    orientations = [u]
    for d in candidates:
        d = d.normalized()
        if abs(d.dot(n)) < .01:
            orientations.append(d)
    best = None
    for ou in orientations:
        ov = n.cross(ou).normalized()
        pu = [p.dot(ou) for p in points]; pv = [p.dot(ov) for p in points]
        width, length = max(pu)-min(pu), max(pv)-min(pv)
        if width < 1e-6 or length < 1e-6:
            continue
        if best is None or width*length < best[0] - 1e-5:
            best = (width*length, ou, ov, width, length,
                    ou*((min(pu)+max(pu))/2)+ov*((min(pv)+max(pv))/2)+n*origin.dot(n))
    if best is None:
        return None
    _, u, v, width, length, center = best
    if width < length:
        u,v,width,length = v,-u,length,width
    return center, u, v, n, width, length


def palette(a):
    for i, m in enumerate(a.document['materials']):
        name = m.get('name', '').lower()
        if 'emission' in name or 'core' in name or m.get('emissiveFactor'):
            a.set_material(i, color=(.53,.006,.20), metal=.12, rough=.32,
                           emission=(1,.014,.48), strength=2.6, role='energy')
        elif 'structure' in name:
            a.set_material(i, color=(.014,.021,.034), metal=.4, rough=.57, role='structure')
        elif 'facet b' in name:
            a.set_material(i, color=(.17,.205,.27), metal=.42, rough=.43, role='hull', coat=.1)
        elif 'facet a' in name:
            a.set_material(i, color=(.058,.082,.132), metal=.46, rough=.47, role='hull', coat=.08)
        else:
            a.set_material(i, color=(.028,.043,.075), metal=.48, rough=.49, role='hull', coat=.08)
    return {
        'cap': a.add_material('BASTION | Concept slate armor', color=(.055,.079,.13), metal=.30, rough=.49, role='hull', coat=.08),
        'navy': a.add_material('BASTION | Concept navy armor', color=(.027,.043,.076), metal=.32, rough=.5, role='hull'),
        'silver': a.add_material('BASTION | Concept pale edge plate', color=(.15,.181,.232), metal=.34, rough=.48, role='hull'),
        'dark': a.add_material('BASTION | Concept inset structure', color=(.01,.015,.025), metal=.35, rough=.58, role='structure'),
        'rim': a.add_material('BASTION | Concept engine frame', color=(.054,.043,.076), metal=.45, rough=.44, role='structure'),
        'core': a.add_material('BASTION | Concept magenta cell', color=(.78,.035,.38), metal=.05, rough=.3,
                               emission=(1,.075,.64), strength=3.4, role='energy'),
    }


def armor_cap(a, component, mats, index, upward=True):
    plane = face_plane(component, upward)
    if not plane:
        return []
    c,u,v,n,w,h = plane
    if h / w < .08:
        return []
    thickness = min(w,h)*.10
    axes=(u,v,n)
    # One or two broad fitted slabs match the illustrated armor terraces. The
    # border is the original shaded shell: it is genuine relief, not a texture.
    count = 2 if w/h > 1.5 else 1
    output = []
    usable = w*.89
    gap = min(w,h)*.035
    length = (usable-gap*(count-1))/count
    for k in range(count):
        center = c + u*(-usable*.5+length*.5+k*(length+gap)) + n*thickness*.3
        material = mats['silver'] if index%7 == 3 else mats['cap'] if index%3 else mats['navy']
        output.append(box('Bastion broad stepped armor',center,(length,h*.86,thickness),axes,material,a.materials,thickness*.35))
        if w/h > 1.15 and index%3 == 0:
            # A short broad shoulder at the end supplies the characteristic
            # stepped silhouette, without adding grilles or noisy microdetail.
            shoulder = center-u*length*.27+n*thickness*.62
            output.append(box('Bastion armor shoulder',shoulder,(length*.37,h*.83,thickness*.56),axes,mats['navy'],a.materials,thickness*.22))
    return output


def light_frame(a, component, mats, simple=False):
    plane = face_plane(component, upward=False)
    if not plane:
        return []
    c,u,v,n,w,h=plane
    # Choose the outward side consistently (engines mostly face +Z). Recessed
    # side lights keep their native face; orientation is entirely mesh-derived.
    if n.z < -.8:
        opposite = {'faces': [f for f in component['faces'] if f[0].dot(-n)>.99]}
        other = face_plane(opposite, upward=False)
        if other:
            c,u,v,n,w,h=other
    if h/w < .025:
        return []
    border = h*.105
    depth = h*.15
    axes=(u,v,n)
    output=[box('Bastion engine socket',c+n*depth*.27,(w*1.065,h*1.07,depth*.52),axes,mats['dark'],a.materials,border*.3)]
    for sign in (-1,1):
        output.append(box('Bastion armored engine frame',c+v*sign*(h*.5-border*.26)+n*depth*.49,
                          (w*1.05,border*.83,depth*.74),axes,mats['rim'],a.materials,border*.24))
    segments = 1 if simple else min(5,max(1,round(w/h*.8)))
    usable=w-2.7*border
    gap=border*.6
    cell=(usable-(segments-1)*gap)/segments
    for k in range(segments):
        cc=c+u*(-usable*.5+cell*.5+k*(cell+gap))+n*depth*.56
        output.append(box('Bastion magenta inset light cell',cc,(cell,h*.63,depth*.10),axes,mats['core'],a.materials,0))
        if k < segments-1:
            output.append(box('Bastion aperture separator',cc+u*(cell*.5+gap*.5)+n*depth*.3,
                              (gap,h*.8,depth*.9),axes,mats['dark'],a.materials,gap*.18))
    return output


def turret_detail(a, obj, mats):
    points=[v.co for v in obj.data.vertices]
    lo=Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    c=(lo+hi)*.5; s=hi-lo
    axes=(Vector((1,0,0)),Vector((0,0,1)),Vector((0,1,0)))
    # Original rail remains the animated barrel. Add its low armored mantlet
    # and black muzzle inset to the same mesh, preserving every recoil clip.
    return [
        box('Bastion artillery mantlet',c+Vector((0,s.y*.18,s.z*.18)),(s.x*1.7,s.z*.35,s.y*1.25),axes,mats['navy'],a.materials,s.x*.08),
        box('Bastion artillery roof',c+Vector((0,s.y*.88,s.z*.2)),(s.x*1.48,s.z*.30,s.y*.22),axes,mats['silver'],a.materials,s.x*.045),
        box('Bastion rail muzzle',Vector((c.x,c.y,lo.z-.004*s.z)),(s.x*.70,s.z*.012,s.y*.5),axes,mats['dark'],a.materials,0),
    ]


def refit(identifier):
    a=ConceptAsset('bastion',identifier)
    mats=palette(a)
    added=0; modules=0; lights=0; weapons=0
    node_names={n['mesh']:n.get('name','') for n in a.document['nodes'] if 'mesh' in n}
    dyson='dyson' in identifier
    for mesh_index,obj in list(a.mesh_objects.items()):
        name=node_names.get(mesh_index,'')
        if name.startswith('FX_'):
            continue
        detail=[]
        if name.startswith('weapon_'):
            detail.extend(turret_detail(a,obj,mats)); weapons+=1
        else:
            parts=components(obj)
            spans=[max(max(p[i] for p in q['points'])-min(p[i] for p in q['points']) for i in range(3)) for q in parts]
            largest=max(spans,default=1)
            for j,(part,span) in enumerate(zip(parts,spans)):
                material=a.document['materials'][part['material']]
                role=material.get('extras',{}).get('conceptRole')
                if role=='energy':
                    extra=light_frame(a,part,mats,simple=dyson)
                    detail.extend(extra); lights+=bool(extra)
                elif role=='hull' and span>largest*.055 and not dyson:
                    extra=armor_cap(a,part,mats,j,upward=not dyson)
                    detail.extend(extra); modules+=bool(extra)
        if detail:
            a.append_geometry(mesh_index,detail)
            added+=len(detail)
    a.document.setdefault('asset',{}).setdefault('extras',{}).update({
        'conceptReference':'RTS_Designs/01_Sets/Bastion/bastion_concept.png',
        'conceptFinish':'navy/slate fitted armor terraces; inset segmented magenta cells; no generic texture atlas',
        'conceptRefit':'bastion-v1',
    })
    a.write()
    if identifier in ('01_korvette','06_titan','04_zitadelle','04_mega_shipyard'):
        a.save_blend(OUT/f'{identifier}.blend')
    row={'id':identifier,'fitted_armor_modules':modules,'framed_light_apertures':lights,
         'animated_turrets_detailed':weapons,'added_detail_objects':added,
         'bytes':(ROOT/'public/models/bastion'/f'{identifier}.glb').stat().st_size}
    print(json.dumps(row),flush=True)
    return row


REMESH = ROOT/'artifacts/model-remesh/bastion'
BEFORE = ROOT/'artifacts/model-remesh/before/bastion'
TEMP = Path('C:/Users/paulp/AppData/Local/Temp/stellaris-remesh/bastion')


def fit_armor_box(part):
    """Recover one authored cuboid from its six retained primary face planes.

    Only dense, single-material disconnected solids qualify. The six broad
    surfaces, original orientation and outside extents define the replacement;
    fine secondary round-over loops become a single intentional chamfer.
    Unusual structures and all already efficient fitted details are retained.
    """
    faces=part
    if sum(len(f.verts)-2 for f in faces)<100 or len({f.material_index for f in faces})!=1:return None
    groups={}
    for face in faces:
        key=tuple(round(v,3) for v in face.normal)
        groups.setdefault(key,[]).append(face)
    ordered=sorted(groups.values(),key=lambda fs:-sum(f.calc_area() for f in fs))
    axis0=ordered[0][0].normal.copy().normalized()
    perpendicular=next((fs[0].normal.copy() for fs in ordered if abs(fs[0].normal.dot(axis0))<.002),None)
    if perpendicular is None:return None
    axis1=(perpendicular-axis0*perpendicular.dot(axis0)).normalized()
    axes=[axis0,axis1,axis0.cross(axis1).normalized()]
    points={v for f in faces for v in f.verts}
    projected=[tuple(v.co.dot(axis) for axis in axes) for v in points]
    lo=[min(p[j] for p in projected) for j in range(3)]
    hi=[max(p[j] for p in projected) for j in range(3)]
    size=[hi[j]-lo[j] for j in range(3)]
    if min(size)<1e-7:return None
    primary=[];insets=[]
    for j in range(3):
        for sign in [-1,1]:
            fs=[f for f in faces if f.normal.dot(axes[j])*sign>.99999]
            if not fs:return None
            # The recovered primary face must sit on the external box plane.
            edge=lo[j] if sign<0 else hi[j]
            if max(abs(v.co.dot(axes[j])-edge) for f in fs for v in f.verts)>max(size)*.00015:return None
            primary.extend(fs)
            for k in range(3):
                if k==j:continue
                values=[v.co.dot(axes[k]) for f in fs for v in f.verts]
                insets.extend([min(values)-lo[k],hi[k]-max(values)])
    if sum(f.calc_area() for f in primary)<sum(f.calc_area() for f in faces)*.50:return None
    insets=sorted(v for v in insets if v>min(size)*.001)
    if not insets:return None
    width=insets[len(insets)//2]
    if width>min(size)*.27:return None
    # Reject concave/compound surfaces instead of forcing them into a box.
    center=sum((axes[j]*(lo[j]+hi[j])*.5 for j in range(3)),Vector())
    for face in faces:
        if face.normal.dot(face.calc_center_median()-center)<-min(size)*.001:return None
    return center,size,axes,width,faces[0].material_index


def retained_faces(a,obj,indices):
    """Copy efficient details with their exact original corner normals."""
    if not indices:return None
    source=obj.data;source.calc_loop_triangles()
    verts=[];faces=[];normals=[];mats=[]
    for index in sorted(indices):
        face=source.polygons[index];start=len(verts)
        for loop_index in face.loop_indices:
            loop=source.loops[loop_index]
            verts.append(tuple(source.vertices[loop.vertex_index].co))
            normals.append(tuple(source.corner_normals[loop_index].vector))
        faces.append(tuple(range(start,len(verts))));mats.append(face.material_index)
    mesh=bpy.data.meshes.new(obj.name+' / unchanged efficient parts');mesh.from_pydata(verts,[],faces)
    for material in a.materials:mesh.materials.append(material)
    for face,material in zip(mesh.polygons,mats):face.material_index=material;face.use_smooth=True
    mesh.normals_split_custom_set(normals)
    result=bpy.data.objects.new(mesh.name,mesh);bpy.context.collection.objects.link(result)
    return result


def remesh(identifier):
    a=ConceptAsset('bastion',identifier,source=BEFORE/(identifier+'.glb'))
    rebuilt=retained=dense_unrecognized=hidden=0
    for index,obj in a.mesh_objects.items():
        if obj.name.startswith('FX_'):continue
        bm=bmesh.new();bm.from_mesh(obj.data)
        span=max(max(v.co[j] for v in bm.verts)-min(v.co[j] for v in bm.verts) for j in range(3))
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=max(span*2e-7,1e-7));bm.normal_update()
        remaining=set(bm.verts);keep=set(range(len(obj.data.polygons)));replacement=[]
        while remaining:
            seed=remaining.pop();seen={seed};stack=[seed]
            while stack:
                vertex=stack.pop()
                for edge in vertex.link_edges:
                    other=edge.other_vert(vertex)
                    if other not in seen:seen.add(other);remaining.discard(other);stack.append(other)
            part=sorted({face for vertex in seen for face in vertex.link_faces},key=lambda face:face.index)
            fit=fit_armor_box(part)
            if fit:
                center,size,axes,width,material=fit
                replacement.append(box(obj.name+' / recovered single chamfer',center,size,axes,material,a.materials,width))
                for face in part:keep.discard(face.index)
                rebuilt+=1
            else:
                retained+=1
                if len(part)>100:dense_unrecognized+=1
        bm.free()
        original=retained_faces(a,obj,keep)
        if original:replacement.append(original)
        replacement,removed=remove_internal_faces(a,replacement)
        hidden+=removed
        a.replace_mesh(index,replacement)
    return a,{'rebuilt_box_components':rebuilt,'unchanged_efficient_components':retained,'unrecognized_dense_components':dense_unrecognized,'proven_internal_triangles_removed':hidden}


def remove_internal_faces(a,objects):
    """Cull faces strictly inside another convex solid on this same rigid node.

    A face disappears only if every vertex is behind every supporting plane of
    an overlapping convex component. This is a geometric containment proof,
    not a camera-dependent visibility guess. Moving parts are never compared
    with another node, so all WIP animation poses remain valid.
    """
    solids=[];membership={};span=0
    for obj in objects:
        evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=evaluated.to_mesh()
        normals=[tuple(n.vector) for n in mesh.corner_normals];baked=mesh.copy();baked.normals_split_custom_set(normals);evaluated.to_mesh_clear()
        obj.modifiers.clear();obj.data=baked
        bm=bmesh.new();bm.from_mesh(baked)
        extent=max(max(v.co[j] for v in bm.verts)-min(v.co[j] for v in bm.verts) for j in range(3));span=max(span,extent)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=max(extent*2e-7,1e-7));bm.normal_update();remaining=set(bm.verts)
        while remaining:
            seed=remaining.pop();seen={seed};stack=[seed]
            while stack:
                vertex=stack.pop()
                for edge in vertex.link_edges:
                    other=edge.other_vert(vertex)
                    if other not in seen:seen.add(other);remaining.discard(other);stack.append(other)
            faces={f for v in seen for f in v.link_faces};points=[v.co.copy() for v in seen]
            planes={tuple(round(v,5) for v in (*f.normal,f.normal.dot(f.calc_center_median()))):(f.normal.copy(),f.normal.dot(f.calc_center_median())) for f in faces}
            planes=list(planes.values());tolerance=max(extent*1e-5,1e-7)
            convex=all(n.dot(p)<=d+tolerance for n,d in planes for p in points)
            solid={'lo':[min(p[j] for p in points) for j in range(3)],'hi':[max(p[j] for p in points) for j in range(3)],'planes':planes if convex else []}
            identity=len(solids);solids.append(solid)
            for face in faces:membership[(obj.name,face.index)]=identity
        bm.free()
    tolerance=max(span*2e-6,1e-7);removed=0;result=[]
    for obj in objects:
        keep=[]
        for face in obj.data.polygons:
            # Emissive inserts remain complete: the game animates their glow
            # and thin rear apertures can contribute light around a frame.
            if a.document['materials'][face.material_index].get('extras',{}).get('conceptRole') in {'energy','plume'}:
                keep.append(face.index);continue
            points=[obj.data.vertices[i].co for i in face.vertices]
            lo=[min(p[j] for p in points) for j in range(3)];hi=[max(p[j] for p in points) for j in range(3)]
            owner=membership.get((obj.name,face.index));inside=False
            for identity,solid in enumerate(solids):
                if identity==owner or not solid['planes']:continue
                if any(lo[j]<solid['lo'][j]+tolerance or hi[j]>solid['hi'][j]-tolerance for j in range(3)):continue
                if all(n.dot(p)<d-tolerance for n,d in solid['planes'] for p in points):inside=True;break
            if inside:removed+=len(face.vertices)-2
            else:keep.append(face.index)
        replacement=retained_faces(a,obj,keep)
        if replacement:result.append(replacement)
        bpy.data.objects.remove(obj,do_unlink=True)
    return result,removed


def preview(a,identifier,stage):
    """Render both immutable before and final meshes with the accepted camera."""
    TEMP.mkdir(parents=True,exist_ok=True);bpy.context.preferences.filepaths.save_version=0
    a.save_blend(TEMP/(stage+'-'+identifier+'.blend'))
    source=ROOT/'artifacts/concept-refit/bastion'/(identifier+'.blend')
    if source.exists():
        with bpy.data.libraries.load(str(source),link=False) as (available,loaded):
            loaded.objects=[name for name in available.objects if name.startswith(('Concept camera','Broad soft key','Soft neutral fill','Armor edge rim'))]
            loaded.worlds=[name for name in available.worlds if name.startswith('Bastion concept backdrop')]
        for obj in loaded.objects:
            if obj is not None:
                bpy.context.scene.collection.objects.link(obj)
                if obj.type=='CAMERA':bpy.context.scene.camera=obj
        if loaded.worlds:bpy.context.scene.world=loaded.worlds[0]
    if bpy.context.scene.camera is None:
        # Dyson had no accepted .blend preview. Fix one shared rig from the
        # immutable before bounds so both stages use identical world framing.
        assembly=bpy.data.collections.get('Concept assembly')
        points=[obj.matrix_world@Vector(v) for obj in assembly.objects for v in obj.bound_box]
        lo=Vector(tuple(min(p[i] for p in points) for i in range(3)));hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
        center=(lo+hi)*.5;span=max(hi-lo)
        config=TEMP/(identifier+'-camera.json')
        if config.exists():
            rig=json.loads(config.read_text());center=Vector(rig['center']);span=rig['span']
        else:config.write_text(json.dumps({'center':list(center),'span':span}))
        scene=bpy.context.scene;scene.world=bpy.data.worlds.new('Bastion concept backdrop');scene.world.use_nodes=True
        bg=scene.world.node_tree.nodes.get('Background');bg.inputs[0].default_value=(.022,.030,.047,1);bg.inputs[1].default_value=.28
        camera=bpy.data.objects.new('Concept camera',bpy.data.cameras.new('Concept camera'));scene.collection.objects.link(camera)
        camera.location=center+Vector((.90,.95,1.15))*span;forward=(center-camera.location).normalized();right=forward.cross(Vector((0,1,0))).normalized();up=right.cross(forward).normalized();camera.rotation_euler=Matrix((right,up,-forward)).transposed().to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=span*1.32;scene.camera=camera
        for name,position,power,size,color in [('Broad soft key',(-.7,1.7,.3),25,1.3,(.79,.88,1)),('Soft neutral fill',(1.4,.5,-.4),12,1,(.64,.71,1)),('Armor edge rim',(-.9,.4,-1.3),32,.7,(.91,.89,1))]:
            light=bpy.data.objects.new(name,bpy.data.lights.new(name,'AREA'));scene.collection.objects.link(light);light.location=center+Vector(position)*span;light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler();light.data.energy=span*span*power;light.data.shape='DISK';light.data.size=span*size;light.data.color=color
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True;scene.render.resolution_x=1200;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
    scene.use_nodes=True;tree=scene.node_tree;tree.nodes.clear();layers=tree.nodes.new('CompositorNodeRLayers');glow=tree.nodes.new('CompositorNodeGlare');glow.glare_type='FOG_GLOW';glow.quality='HIGH';glow.threshold=1.8;glow.size=7;glow.mix=-.85;output=tree.nodes.new('CompositorNodeComposite');tree.links.new(layers.outputs['Image'],glow.inputs['Image']);tree.links.new(glow.outputs['Image'],output.inputs[0])
    scene.render.image_settings.file_format='PNG';scene.render.filepath=str(REMESH/(stage+'-'+identifier+'.png'));bpy.ops.wm.save_as_mainfile(filepath=str(TEMP/(stage+'-'+identifier+'.blend')));bpy.ops.render.render(write_still=True)


def main():
    import shutil
    parser=argparse.ArgumentParser();parser.add_argument('--only');parser.add_argument('--render',action='store_true');parser.add_argument('--dry-run',action='store_true');args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    REMESH.mkdir(parents=True,exist_ok=True);TEMP.mkdir(parents=True,exist_ok=True)
    ids=[args.only] if args.only else sorted(p.stem for p in BEFORE.glob('*.glb'));rows=[]
    count=lambda d:sum(d['accessors'][p['indices']]['count']//3 for mesh in d['meshes'] for p in mesh['primitives'])
    for identifier in ids:
        if args.render and identifier in ['01_korvette','06_titan','03_dyson_swarm']:
            before=ConceptAsset('bastion',identifier,source=BEFORE/(identifier+'.glb'));preview(before,identifier,'before')
        a,row=remesh(identifier);row.update(model=identifier,before_triangles=count(a.document))
        if not args.dry_run:
            assert shutil.disk_usage(ROOT).free>20_000_000,'Insufficient staging space on workspace disk'
        a.write(TEMP/(identifier+'.glb') if args.dry_run else None)
        row.update(after_triangles=count(a.document),nodes_unchanged=a.document['nodes']==a.original_nodes,animation_json_unchanged=a.document.get('animations',[])==a.original_animations)
        rows.append(row);print(json.dumps(row),flush=True)
        if args.render and identifier in ['01_korvette','06_titan','03_dyson_swarm']:preview(a,identifier,'after')
    destination=REMESH/('dry-report.json' if args.dry_run else 'report.json')
    previous=json.loads(destination.read_text()) if args.only and destination.exists() else []
    merged={r['model']:r for r in previous+rows};destination.write_text(json.dumps(list(merged.values()),indent=2)+'\n')


if __name__=='__main__':main()
