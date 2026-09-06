"""NEXUS concept refit in Blender 4.5.

Run: blender --background --factory-startup --python scripts/concept-sets/nexus.py
     [-- --only 06_titan --render]

References: nexus_concept.png and the three adjacent design sheets. Authored
surfaces are blue cellular plasma, dark polished cages, and narrow knife edges;
there are deliberately no generic panel, vent, grunge, or tiled sci-fi textures.
Only mesh/material payloads change. concept_asset preserves animation/node data.
"""
import argparse
import json
import math
import struct
import sys
import zlib
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils import noise
from mathutils.bvhtree import BVHTree

ROOT = Path.cwd()
sys.path.insert(0, str(ROOT / 'scripts'))
from concept_asset import ConceptAsset

OUT = ROOT / 'artifacts/model-remesh/nexus'
OUT.mkdir(parents=True, exist_ok=True)
ATLAS = OUT / 'nexus-concept-clouds-32.png'
parser = argparse.ArgumentParser()
parser.add_argument('--only')
parser.add_argument('--render', action='store_true')
parser.add_argument('--no-render', action='store_true')
parser.add_argument('--before-render', action='store_true')
parser.add_argument('--rebake', action='store_true')
ARGS = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])


def welded_subset(obj, material_index):
    """Get connected material regions, joining coincident glTF split vertices."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    unwanted = [f for f in bm.faces if f.material_index != material_index]
    bmesh.ops.delete(bm, geom=unwanted, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    span = max(obj.dimensions) or 1
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=span * 1e-6)
    pending = set(bm.verts)
    regions = []
    while pending:
        seed = pending.pop()
        stack, region = [seed], [seed]
        while stack:
            v = stack.pop()
            for edge in v.link_edges:
                w = edge.other_vert(v)
                if w in pending:
                    pending.remove(w)
                    stack.append(w)
                    region.append(w)
        regions.append([v.co.copy() for v in region])
    bm.free()
    return regions


def bounds(points):
    low = Vector(tuple(min(p[k] for p in points) for k in range(3)))
    high = Vector(tuple(max(p[k] for p in points) for k in range(3)))
    return (low + high) * .5, high - low


def ensure_color(mesh):
    attr = mesh.color_attributes.get('ConceptColor')
    if not attr:
        attr = mesh.color_attributes.new(name='ConceptColor', type='FLOAT_COLOR', domain='POINT')
        for entry in attr.data:
            entry.color = (1, 1, 1, 1)
    mesh.color_attributes.active_color = attr
    return attr


REFERENCE_FIELD = None


def load_reference_field():
    """Extract only the blue plasma inside the concept's Titan globe.

    Metal/background pixels are rejected before filling a small color field.
    Triplanar sampling transfers its cloud drawing without projecting cages,
    text, silhouette or the sheet background onto the model.
    """
    import numpy as np
    global REFERENCE_FIELD
    path = ROOT / 'artifacts/concept-reference/RTS_Designs/01_Sets/Nexus/nexus_concept.png'
    image = bpy.data.images.load(str(path), check_existing=True)
    w, h = image.size
    pixels = np.asarray(image.pixels[:], dtype=np.float32).reshape((h, w, 4))[::-1]
    patch = pixels[594:638, 599:652, :3].copy()
    valid = ((patch[:,:,2] > patch[:,:,0]*2.1) &
             (patch[:,:,2] > patch[:,:,1]*1.18) &
             (patch[:,:,2] > .20))
    coords = np.argwhere(valid)
    # Fill tiny corner occlusions from adjacent real plasma; never sample metal.
    for y, x in np.argwhere(~valid):
        d = ((coords - np.array((y, x)))**2).sum(axis=1)
        yy, xx = coords[d.argmin()]
        patch[y, x] = patch[yy, xx]
    REFERENCE_FIELD = np.where(patch <= .04045, patch/12.92,
                               ((patch+.055)/1.055)**2.4)


def sample_reference(p, seed):
    field = REFERENCE_FIELD
    def sample(u, v):
        u = .5 + .47*math.sin(u*4.2 + seed*.21)
        v = .5 + .47*math.sin(v*3.7 - seed*.16)
        x, y = u*(field.shape[1]-1), v*(field.shape[0]-1)
        ix, iy = int(x), int(y)
        dx, dy = x-ix, y-iy
        return ((field[iy,ix]*(1-dx)+field[iy,ix+1]*dx)*(1-dy) +
                (field[iy+1,ix]*(1-dx)+field[iy+1,ix+1]*dx)*dy)
    weights = [abs(p[k])**6 + .01 for k in range(3)]
    a, b, c = sample(p.z,p.y), sample(p.x,p.z), sample(p.y,p.x)
    return (a*weights[0]+b*weights[1]+c*weights[2])/sum(weights)


def plasma_color(p, seed=0):
    """Concept-derived blue cloud drawing with sparse, broken fine tendrils."""
    p = p.normalized()
    shifted = p + Vector((1.37 + seed * .13, -3.15, 2.71))
    warp = noise.noise_vector(shifted * 2.1, noise_basis='PERLIN_ORIGINAL')
    q = (p + warp * .23).normalized()
    n = noise.fractal(shifted * 4.2, .7, 2.0, 4, noise_basis='PERLIN_ORIGINAL')
    finer = noise.noise(shifted * 13.0, noise_basis='PERLIN_ORIGINAL')
    fine = noise.noise(shifted * 32.0, noise_basis='PERLIN_ORIGINAL')
    cloud = max(0, min(1, .48 + n * .64 + finer * .16))
    # Broken noise ridges replace the old continuous Voronoi cell network.
    # Their brightness is deliberately subordinate to the source cloud drawing.
    ridge = noise.noise(q*8.7 + Vector((2.7,-1.3,4.1)), noise_basis='PERLIN_ORIGINAL')
    gate = max(0, min(1, (noise.noise(q*3.5 + Vector((5.3,1.1,-.8)),
                                       noise_basis='PERLIN_ORIGINAL')-.035)*3.0))
    filament = math.exp(-((ridge/.030)**2)) * gate
    branching = math.exp(-((fine/.022)**2)) * gate * .27
    hot = max(filament, branching) * .23
    reference = sample_reference(q, seed)
    illumination = .69 + .50*cloud
    rgb = (
        reference[0]*illumination*.35 + hot*.038,
        reference[1]**1.3*illumination*.55 + .001*cloud + hot*.19,
        reference[2]**1.2*illumination*.58 + .006*cloud + hot*.37,
    )
    return (*tuple(max(0, min(1, value)) for value in rgb), 1)


def bake_plasma_atlas():
    """Bake the approved field, unchanged, to 32 padded spherical UV charts."""
    import numpy as np
    if ATLAS.exists() and not ARGS.rebake:
        return
    width = height = 1024
    tile_w, tile_h, pad = 256, 128, 4
    pixels = np.empty((height,width,3),dtype=np.uint8)
    for seed in range(32):
        ox, oy = (seed%4)*tile_w, (seed//4)*tile_h
        for y in range(tile_h):
            v = max(0,min(1,1-(y-pad)/(tile_h-2*pad)))
            lat = math.pi*(v-.5)
            for x in range(tile_w):
                u = ((x-pad)/(tile_w-2*pad))%1
                phi = math.tau*(u-.5)
                p = Vector((math.cos(phi)*math.cos(lat),math.sin(phi)*math.cos(lat),math.sin(lat)))
                linear = plasma_color(p,seed)[:3]
                srgb = [c*12.92 if c<=.0031308 else 1.055*c**(1/2.4)-.055 for c in linear]
                pixels[oy+y,ox+x] = [round(max(0,min(1,c))*255) for c in srgb]
        print('NEXUS bake chart '+str(seed+1)+'/32',flush=True)
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    rows = b''.join(b'\0'+pixels[y].tobytes() for y in range(height))
    ATLAS.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,2,0,0,0))+
                      chunk(b'IDAT',zlib.compress(rows,9))+chunk(b'IEND',b''))


def plasma_sphere(asset, center, extents, index, segments=64, rings=32, orientation=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings,
                                      radius=1, location=(0, 0, 0))
    obj = bpy.context.object
    obj.name = 'NEXUS / cellular plasma shell'
    for material in asset.materials:
        obj.data.materials.append(material)
    radius = extents * .5
    color = ensure_color(obj.data)
    for vertex in obj.data.vertices:
        p = vertex.co.copy()
        color.data[vertex.index].color = (1,1,1,1)
        local = Vector(tuple(p[k] * radius[k] for k in range(3)))
        if orientation is not None and radius.x < min(radius.y,radius.z)*.5:
            # Put the latitude poles through the thin axis of a collector lens:
            # its visible outline then has 12 contour points instead of being
            # limited by the four depth rings on a major-axis meridian.
            local = Vector((p.z*radius.x,p.x*radius.y,p.y*radius.z))
        vertex.co = center + (orientation @ local if orientation else local)
    for face in obj.data.polygons:
        face.material_index = PLASMA_INDEX
        face.use_smooth = True
    cell = index % 32
    for datum in obj.data.uv_layers.active.data:
        u,v = datum.uv
        datum.uv = (((cell%4)*256+4+u*248)/1024,
                    1-((cell//4)*128+4+(1-v)*120)/1024)
    obj['conceptAuthored'] = True
    obj['concept_surface'] = 'irregular cobalt plasma lobes and cyan discharge seams'
    return obj


def remove_material_regions(obj, index, spheres):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    def on_shell(face):
        p = face.calc_center_median()
        for center, extent in spheres:
            q = Vector(tuple((p[k]-center[k]) / max(extent[k]*.5, 1e-6) for k in range(3)))
            if .72 < q.length_squared < 1.08:
                return True
        return False
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index == index and on_shell(f)], context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.to_mesh(obj.data)
    bm.free()


def replace_swarm_lenses(asset, obj, plasma_index):
    """Replace every tilted/flattened lens, including its complete back surface.

    World-axis bounding boxes cannot identify these randomly oriented ellipsoids.
    Each connected region is fitted in its own principal-axis coordinates and
    all original plasma faces are removed before adding the new closed surfaces.
    """
    import numpy as np
    regions = welded_subset(obj, plasma_index)
    replacements = []
    for i, points in enumerate(regions):
        if len(points) < 12:
            continue
        coords = np.array([tuple(p) for p in points])
        mean = coords.mean(axis=0)
        _, axes = np.linalg.eigh(np.cov(coords.T))
        if np.linalg.det(axes) < 0:
            axes[:,0] *= -1
        projected = (coords-mean) @ axes
        low, high = projected.min(axis=0), projected.max(axis=0)
        center = Vector(tuple(mean + axes @ ((low+high)*.5)))
        extent = Vector(tuple(high-low))
        if min(extent) < 1e-5:
            continue
        orientation = Matrix(tuple(tuple(float(v) for v in row) for row in axes))
        replacements.append(plasma_sphere(asset, center, extent, i,
                                          segments=12, rings=4, orientation=orientation))
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index==plasma_index], context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.to_mesh(obj.data)
    bm.free()
    assert not any(f.material_index==plasma_index for f in obj.data.polygons)
    return replacements


def retopologize_cages(asset, obj, slug, plasma_index):
    """Analytically rebuild full containment loops with purposeful edge loops.

    Closed circular bands are fitted in their own plane. Blade plates and open
    tapered crescents are excluded, retaining their authored silhouette.
    """
    import numpy as np
    additions, keys_by_material = [], {}
    portal = 'assembly portal' in obj.name.lower()
    oval = slug=='03_dyson_swarm' or portal
    epsilon = max(max(obj.dimensions),1)*1e-5
    def key(p):
        return tuple(round(float(v)/epsilon) for v in p)
    for mi in {f.material_index for f in obj.data.polygons}:
        if mi==plasma_index:
            continue
        for points in welded_subset(obj,mi):
            if len(points)<24:
                continue
            xyz = np.array([tuple(p) for p in points])
            mean = xyz.mean(axis=0)
            values, axes = np.linalg.eigh(np.cov(xyz.T))
            if values[1]<values[2]*(.50 if portal else .58) or values[0]>values[2]*(.20 if portal else .05):
                continue
            if np.linalg.det(axes)<0:
                axes[:,0] *= -1
            projected = (xyz-mean)@axes
            x,y = projected[:,1],projected[:,2]
            fitted = np.linalg.lstsq(np.stack((2*x,2*y,np.ones_like(x)),axis=1),x*x+y*y,rcond=None)[0]
            cx,cy = fitted[:2]
            dx,dy = x-cx,y-cy
            radius = np.sqrt(dx*dx+dy*dy)
            inner,outer = np.quantile(radius,[.005,.995])
            r = (inner+outer)*.5
            if inner<outer*(.45 if oval else .66) or r<.025:
                continue
            angles = np.sort(np.arctan2(dy,dx))
            gaps = np.diff(np.r_[angles,angles[0]+math.tau])
            if gaps.max()>math.radians(45):
                continue
            low,high = projected[:,0].min(),projected[:,0].max()
            half_width,half_depth = (outer-inner)*.5,(high-low)*.5
            ellipse_radii = None
            if oval:
                # Source collectors are intentionally oval (.024 x .031), with
                # a .004/.003 band profile. Preserve that oval rather than using
                # its varying radius as an unnecessarily thick circular band.
                half_width = half_depth*(8/9 if portal else 4/3)
                ellipse_radii = ((x.max()-x.min())*.5-half_width,
                                 (y.max()-y.min())*.5-half_width)
                cx,cy = (x.max()+x.min())*.5,(y.max()+y.min())*.5
            if half_width<r*.00015 or half_depth<r*.00015:
                continue
            center = Vector(tuple(mean+axes@np.array(((low+high)*.5,cx,cy))))
            normal = Vector(tuple(axes[:,0])); a=Vector(tuple(axes[:,1])); b=Vector(tuple(axes[:,2]))
            role = asset.document['materials'][mi].get('extras',{}).get('conceptRole')
            steps = 12 if slug=='03_dyson_swarm' or role=='energy' else 24
            if portal:
                steps = 16
            if 'energy field trace' in obj.name.lower():
                steps = 24
                # Low-poly chords must remain outside the plasma shell; otherwise
                # the preserved animated traces turn into disconnected stubs.
                r *= 1.01
            profile = 3 if role=='energy' or slug=='03_dyson_swarm' else 4
            vertices, faces = [], []
            for i in range(steps):
                theta = math.tau*i/steps
                radial = a*math.cos(theta)+b*math.sin(theta)
                for j in range(profile):
                    cross = math.tau*j/profile
                    rim_position = (a*ellipse_radii[0]*math.cos(theta)+b*ellipse_radii[1]*math.sin(theta)
                                    if ellipse_radii else radial*r)
                    vertices.append(tuple(center+rim_position+radial*half_width*math.cos(cross)+
                                          normal*half_depth*math.sin(cross)))
            for i in range(steps):
                for j in range(profile):
                    faces.append((i*profile+j,((i+1)%steps)*profile+j,
                                  ((i+1)%steps)*profile+(j+1)%profile,i*profile+(j+1)%profile))
            mesh = bpy.data.meshes.new('Retopologized containment band')
            mesh.from_pydata(vertices,[],faces); mesh.update()
            ring = bpy.data.objects.new('NEXUS / low-poly containment band',mesh)
            bpy.context.collection.objects.link(ring)
            for mat in asset.materials: mesh.materials.append(mat)
            for f in mesh.polygons: f.material_index=mi; f.use_smooth=True
            ensure_color(mesh)
            additions.append(ring)
            keys_by_material.setdefault(mi,set()).update(key(p) for p in points)
    if keys_by_material:
        bm = bmesh.new(); bm.from_mesh(obj.data)
        remove = [f for f in bm.faces if f.material_index in keys_by_material and
                  all(key(v.co) in keys_by_material[f.material_index] for v in f.verts)]
        bmesh.ops.delete(bm,geom=remove,context='FACES')
        bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
        bm.to_mesh(obj.data); bm.free()
    return additions


def tube(asset, points, radius, material_index):
    verts, faces = [], []
    for i, point in enumerate(points):
        tangent = (points[min(i+1, len(points)-1)] - points[max(i-1, 0)]).normalized()
        u = tangent.cross(Vector((0, 1, 0)))
        if u.length < .1:
            u = tangent.cross(Vector((1, 0, 0)))
        u.normalize()
        v = tangent.cross(u).normalized()
        # Lens shaped, tapered termini; this is a flush blue conduit, not a vent.
        taper = .20 + .80 * math.sin(math.pi * i / (len(points)-1)) ** .4
        for j in range(4):
            a = j * math.tau / 4
            verts.append(tuple(point + radius * taper * (math.cos(a) * u + math.sin(a) * v)))
    for i in range(len(points)-1):
        for j in range(4):
            faces.append((i*4+j, i*4+(j+1)%4, (i+1)*4+(j+1)%4, (i+1)*4+j))
    faces += [tuple(reversed(range(4))), tuple(range((len(points)-1)*4, len(points)*4))]
    mesh = bpy.data.meshes.new('Blue knife inlay')
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new('NEXUS / blue knife inlay', mesh)
    bpy.context.collection.objects.link(obj)
    for mat in asset.materials:
        mesh.materials.append(mat)
    for face in mesh.polygons:
        face.material_index = material_index
        face.use_smooth = True
    ensure_color(mesh)
    return obj


def blade_inlays(asset, obj, blade_index, light_index):
    """Follow existing blade faces with a narrow inset from the source concept."""
    from numpy import array, cov, linalg
    pieces = []
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    tree = BVHTree.FromBMesh(bm)
    for points in welded_subset(obj, blade_index):
        if len(points) < 10:
            continue
        center, extent = bounds(points)
        # Skip spherical emitters, full hoops, near-cubic nodes, and tiny details.
        if min(extent) > max(extent) * .14 or max(extent) < .4:
            continue
        matrix = array([tuple(p) for p in points])
        vals, axes = linalg.eigh(cov(matrix.T))
        axis = Vector(axes[:, -1]).normalized()
        face_normal = Vector(axes[:, 0]).normalized()
        if face_normal.y < 0:
            face_normal.negate()
        if vals[-1] < vals[-2] * 1.6:
            continue
        projections = [(p-center).dot(axis) for p in points]
        lo, hi = min(projections), max(projections)
        length = hi-lo
        path = []
        for i in range(4):
            t = .23 + i / 3 * .54
            candidate = center + axis * (lo + t * length)
            hit, normal, _, _ = tree.ray_cast(candidate + face_normal * length,
                                             -face_normal, length * 2)
            if hit is not None:
                path.append(hit + normal * length * .0016)
        if len(path) >= 3:
            pieces.append(tube(asset, path, length * .0032, light_index))
    bm.free()
    return pieces


def setup_materials(asset):
    plasma_index = None
    blade_index = None
    for i, material in enumerate(asset.document['materials']):
        name = material.get('name', '')
        if 'Facet A' in name:
            asset.set_material(i, color=(1, 1, 1), metal=0, rough=.82,
                               emission=(1,1,1), strength=1.65,
                               role='plasma', coat=0)
            plasma_index = i
        elif 'Facet B' in name:
            asset.set_material(i, color=(.105, .148, .205), metal=.88, rough=.26,
                               role='hull', coat=.23)
            blade_index = i
        elif 'Structure' in name:
            asset.set_material(i, color=(.009, .018, .029), metal=.74, rough=.36,
                               role='structure', coat=.10)
        elif 'Core' in name:
            asset.set_material(i, color=(.008, .16, .75), metal=.05, rough=.30,
                               emission=(.015, .24, 1), strength=2.4,
                               role='energy', coat=.12)
        elif 'Emission' in name:
            asset.set_material(i, color=(.004, .075, .35), metal=.05, rough=.30,
                               emission=(.007, .20, 1), strength=2.25,
                               role='energy', coat=.12)
        else:
            asset.set_material(i, color=(.029, .047, .071), metal=.91, rough=.29,
                               role='hull', coat=.20)
    if blade_index is None:
        blade_index = 0
    inlay = asset.add_material('NEXUS | Containment blade energy inlay',
                              color=(.004, .11, .44), metal=.05, rough=.28,
                              emission=(.012, .25, 1), strength=2.3,
                              role='energy', coat=.1)
    trace = asset.add_material('NEXUS | Subtle circulating field caustic',
                              color=(.001, .025, .18), metal=0, rough=.8,
                              emission=(.001, .075, .5), strength=.48,
                              role='energy', coat=0)
    cargo = asset.add_material('NEXUS | Preserved cobalt cargo',color=(.006,.105,.52),
                               metal=0,rough=.82,emission=(.006,.105,.52),strength=1.0,role='energy')
    if plasma_index is not None:
        texture = asset.embed_png_texture(ATLAS, name='NEXUS approved cloud painting, 32 charts')
        asset.set_material_texture(plasma_index,texture,base_color=True,emissive=True)
    return plasma_index, blade_index, inlay, trace, cargo


def link_preview_color(asset, plasma_index):
    """The Blender scene uses the same vertex field as the portable GLB."""
    if plasma_index is None:
        return
    mat = asset.materials[plasma_index]
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    principled = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    if asset.document['materials'][plasma_index].get('extras',{}).get('conceptBakedTexture'):
        colors = next(n for n in nodes if n.type=='TEX_IMAGE')
    else:
        colors = nodes.new('ShaderNodeVertexColor')
        colors.layer_name = 'ConceptColor'
        colors.label = 'Reference cobalt plasma / authored vertex field'
    diffuse = nodes.new('ShaderNodeVectorMath')
    diffuse.operation = 'SCALE'
    diffuse.inputs['Scale'].default_value = .08
    mat.node_tree.links.new(colors.outputs['Color'], diffuse.inputs[0])
    mat.node_tree.links.new(diffuse.outputs['Vector'], principled.inputs['Base Color'])
    facing = nodes.new('ShaderNodeLayerWeight')
    rim = nodes.new('ShaderNodeMath')
    rim.operation = 'POWER'
    rim.inputs[1].default_value = 3.8
    mat.node_tree.links.new(facing.outputs['Facing'], rim.inputs[0])
    rim_color = nodes.new('ShaderNodeVectorMath')
    rim_color.operation = 'SCALE'
    rim_color.inputs[0].default_value = (.006, .18, .60)
    mat.node_tree.links.new(rim.outputs[0], rim_color.inputs['Scale'])
    field = nodes.new('ShaderNodeVectorMath')
    field.operation = 'ADD'
    mat.node_tree.links.new(colors.outputs['Color'], field.inputs[0])
    mat.node_tree.links.new(rim_color.outputs['Vector'], field.inputs[1])
    mat.node_tree.links.new(field.outputs['Vector'], principled.inputs['Emission Color'])
    principled.inputs['Emission Strength'].default_value = 1.65
    principled.inputs['Specular IOR Level'].default_value = 0


def render_preview(asset, slug):
    bpy.context.preferences.filepaths.save_version = 0
    asset.save_blend(OUT / f'{slug}.blend')
    # Preview assembled by helper uses glTF coordinates (+Y up, -Z forward).
    scene = bpy.context.scene
    objects = [o for o in scene.objects if o.type == 'MESH' and not o.hide_render]
    pts = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
    center, ext = bounds(pts)
    span = max(ext)
    comparison_key = slug.replace('-before','').replace('-after','')
    camera_path = OUT / f'{comparison_key}-camera.json'
    if slug.endswith('-before') or not camera_path.exists():
        camera_path.write_text(json.dumps({'center':list(center),'span':span},indent=2))
    else:
        camera_settings = json.loads(camera_path.read_text())
        center,span = Vector(camera_settings['center']),camera_settings['span']
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    if scene.world is None:
        scene.world = bpy.data.worlds.new('NEXUS dark studio')
    scene.world.color = (.035, .035, .035)
    world = scene.world
    world.use_nodes = True
    world.node_tree.nodes.get('Background').inputs[0].default_value = (.006, .009, .017, 1)
    world.node_tree.nodes.get('Background').inputs[1].default_value = .35
    def area(name, pos, energy, color, size):
        data = bpy.data.lights.new(name, 'AREA')
        data.energy = energy * span * span
        data.color = color
        data.shape = 'DISK'
        data.size = size * span
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.location = center + Vector(pos) * span
        obj.rotation_euler = (center-obj.location).to_track_quat('-Z', 'Y').to_euler()
    area('Cool upper strip', (.5, 1.0, .1), 15, (.72, .86, 1), .8)
    area('Silver blade edge', (-.7, .2, -.4), 12, (.8, .85, 1), .65)
    area('Blue lower reflection', (.1, -.6, .7), 6, (.08, .35, 1), .5)
    camera_data = bpy.data.cameras.new('Concept camera')
    camera = bpy.data.objects.new('Concept camera', camera_data)
    scene.collection.objects.link(camera)
    camera.location = center + Vector((.92, .73, -1.15)) * span
    camera.rotation_euler = (center-camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.rotation_euler.rotate_axis('Z', math.radians(-23))
    camera_data.type = 'ORTHO'
    camera_data.ortho_scale = span * 1.13
    scene.camera = camera
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False
    scene.view_settings.view_transform = 'AgX'
    scene.use_nodes = True
    tree = scene.node_tree
    tree.nodes.clear()
    layers = tree.nodes.new('CompositorNodeRLayers')
    glare = tree.nodes.new('CompositorNodeGlare')
    glare.glare_type = 'FOG_GLOW'
    glare.threshold = 1.3
    glare.quality = 'HIGH'
    comp = tree.nodes.new('CompositorNodeComposite')
    tree.links.new(layers.outputs['Image'], glare.inputs['Image'])
    tree.links.new(glare.outputs['Image'], comp.inputs['Image'])
    scene.render.filepath = str(OUT / f'{slug}.png')
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / f'{slug}.blend'),compress=True)
    bpy.ops.render.render(write_still=True)


def process(slug):
    global PLASMA_INDEX
    source = ROOT / 'artifacts/model-import/surface-originals/nexus' / (slug+'.glb')
    asset = ConceptAsset('nexus', slug, source=source)
    PLASMA_INDEX, blade_index, light_index, trace_index, cargo_index = setup_materials(asset)
    report = {'id': slug, 'plasma_shells': 0, 'blade_inlays': 0, 'retopologized_bands':0,
              'mesh_count': len(asset.mesh_objects)}
    for mesh_index, obj in list(asset.mesh_objects.items()):
        name = asset.document['meshes'][mesh_index].get('name', '')
        additions = []
        if 'energy field trace' in name.lower():
            for face in obj.data.polygons:
                face.material_index = trace_index
        if PLASMA_INDEX is not None and slug == '03_dyson_swarm':
            additions += replace_swarm_lenses(asset, obj, PLASMA_INDEX)
            report['plasma_shells'] += len(additions)
        elif PLASMA_INDEX is not None:
            regions = welded_subset(obj, PLASMA_INDEX)
            spheres, others = [], []
            for points in regions:
                center, extent = bounds(points)
                if len(points) >= 48 and min(extent) > max(extent) * .64 and 'cargo' not in name.lower():
                    spheres.append((center, extent))
                else:
                    others.append(points)
            if spheres:
                remove_material_regions(obj, PLASMA_INDEX, spheres)
                main_assets = {'01_korvette','02_fregatte','03_zerstoerer','04_kreuzer',
                               '05_schlachtschiff','06_titan','07_arbeiter','08_forschung',
                               '01_aussenposten','02_sternenbasis','03_festung','04_zitadelle',
                               '05_abwehrplattform','06_artillerieplattform'}
                density = 24 if slug in main_assets else 12
                for i, (center, extent) in enumerate(spheres):
                    additions.append(plasma_sphere(asset, center, extent, i,
                                                  segments=density, rings=12 if density==24 else 4))
                    report['plasma_shells'] += 1
            # Non-spherical worker cargo keeps its original animation/geometry
            # and takes a cobalt field tint instead of the new white base factor.
            colors = ensure_color(obj.data)
            for face in obj.data.polygons:
                if face.material_index == PLASMA_INDEX:
                    face.material_index = cargo_index
                    for vi in face.vertices:
                        colors.data[vi].color = (1,1,1,1)
        if not name.lower().startswith('fx') and 'trace' not in name.lower() and 'swarm' not in slug:
            additions += blade_inlays(asset, obj, blade_index, light_index)
            report['blade_inlays'] = len([o for o in additions if 'inlay' in o.name]) + report['blade_inlays']
        cages = retopologize_cages(asset,obj,slug,PLASMA_INDEX)
        additions += cages
        report['retopologized_bands'] += len(cages)
        ensure_color(obj.data)
        asset.replace_mesh(mesh_index, [obj] + additions)
    if slug == '03_dyson_swarm':
        assert report['plasma_shells'] == 88, 'Every Dyson collector needs a closed authored plasma lens'
        assert all(not any(f.material_index == PLASMA_INDEX for f in obj.data.polygons)
                   for obj in asset.mesh_objects.values()), 'No legacy flat-blue plasma faces may remain'
    asset.write()
    report['triangles'] = sum(asset.document['accessors'][p['indices']]['count']//3
                              for mesh in asset.document['meshes'] for p in mesh['primitives'])
    report['bytes'] = (ROOT / 'public/models/nexus' / f'{slug}.glb').stat().st_size
    (OUT / f'{slug}.json').write_text(json.dumps(report, indent=2) + '\n')
    print('NEXUS_REFIT ' + json.dumps(report), flush=True)
    if not ARGS.no_render and (ARGS.render or slug == '06_titan'):
        link_preview_color(asset, PLASMA_INDEX)
        render_preview(asset, slug+'-after')
    return report


if __name__ == '__main__':
    paths = sorted((ROOT / 'public/models/nexus').glob('*.glb'))
    selected = [p.stem for p in paths if ARGS.only is None or p.stem == ARGS.only]
    if ARGS.before_render:
        for slug in selected:
            a=ConceptAsset('nexus',slug,source=ROOT/'artifacts/model-remesh/before/nexus'/(slug+'.glb'))
            pi=next(i for i,m in enumerate(a.document['materials']) if m.get('extras',{}).get('conceptRole')=='plasma')
            link_preview_color(a,pi)
            render_preview(a,slug+'-before')
    else:
        load_reference_field()
        bake_plasma_atlas()
        reports = [process(slug) for slug in selected]
        reports = [json.loads((OUT/(p.stem+'.json')).read_text()) for p in paths
                   if (OUT/(p.stem+'.json')).exists()]
        (OUT / 'report.json').write_text(json.dumps(reports, indent=2) + '\n')
