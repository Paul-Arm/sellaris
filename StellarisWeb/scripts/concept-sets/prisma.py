"""PRISMA low-poly concept geometry, authored in Blender 4.5.

Run: blender --background --factory-startup --python scripts/concept-sets/prisma.py
      -- [--only 04_kreuzer] [--render] [--before-render]

The concept's split ceramic lances, recessed axial graphite channel, individually
stepped armor and compact cyan ion engines are modeled explicitly. There is no
mechanical texture atlas. Original GLB hierarchy and animation buffers are kept by
ConceptAsset; new geometry is expressed in each original mesh node's local frame.
Rebuilds use immutable unbeveled originals and explicit low-polygon plates,
without the former redundant bevel grids. The approved materials are preserved.
"""
from pathlib import Path
import argparse
import json
import math
import os
import shutil
import struct
import sys

import bpy
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from concept_asset import ConceptAsset

OUT = ROOT / 'artifacts/model-remesh/prisma'
BEFORE = ROOT / 'artifacts/model-remesh/before/prisma'
ORIGINAL = ROOT / 'artifacts/model-import/surface-originals/prisma'
PREVIEW = Path(os.environ.get('TEMP', 'C:/Users/paulp/AppData/Local/Temp')) / 'stellaris-remesh/prisma'
COMPARISONS = {'01_korvette', '06_titan', '04_zitadelle'}


def triangle_count(document):
    return sum(document['accessors'][p['indices']]['count']//3
               for m in document['meshes'] for p in m['primitives'])


def read_document(path):
    data=path.read_bytes(); length=struct.unpack_from('<I',data,12)[0]
    return json.loads(data[20:20+length])


class Shape:
    def __init__(self, name):
        self.name = name
        self.vertices = []
        self.faces = []
        self.materials = []

    def add(self, vertices, faces, materials):
        start = len(self.vertices)
        self.vertices.extend(tuple(v) for v in vertices)
        self.faces.extend(tuple(start + i for i in f) for f in faces)
        self.materials.extend([materials] * len(faces) if isinstance(materials, int) else materials)

    def plate(self, polygon, bottom, top, mat, side=None):
        """Closed custom plan silhouette; heights may vary per polygon corner."""
        if not isinstance(bottom, (list, tuple)):
            bottom = [bottom] * len(polygon)
        if not isinstance(top, (list, tuple)):
            top = [top] * len(polygon)
        n = len(polygon)
        vertices = [(x, bottom[i], z) for i, (x, z) in enumerate(polygon)]
        vertices += [(x, top[i], z) for i, (x, z) in enumerate(polygon)]
        # Polygon handedness is normalized in the XZ plane.
        area = sum(polygon[i][0] * polygon[(i+1)%n][1] - polygon[(i+1)%n][0] * polygon[i][1] for i in range(n))
        faces = [tuple(range(n)), tuple(reversed(range(n, 2*n)))]
        faces += [(i, i+n, (i+1)%n+n, (i+1)%n) for i in range(n)]
        if area < 0:
            faces = [tuple(reversed(f)) for f in faces]
        self.add(vertices, faces, [side if side is not None else mat, mat] + [side if side is not None else mat] * n)

    def box(self, center, size, mat):
        x,y,z=center; w,h,d=(v/2 for v in size)
        self.plate([(x-w,z-d),(x+w,z-d),(x+w,z+d),(x-w,z+d)], y-h,y+h,mat)

    def tube_z(self, center, width, height, depth, wall, outer, rim):
        """Angular engine collar with an actually open aft aperture."""
        x,y,z = center
        profile=[(-.7,-1),(.7,-1),(1,-.55),(1,.55),(.7,1),(-.7,1),(-1,.55),(-1,-.55)]
        rings=[]
        for zz,ww,hh in [(z-depth*.5,width,height),(z+depth*.5,width,height),(z+depth*.5,width-wall*2,height-wall*2),(z-depth*.5,width-wall*2,height-wall*2)]:
            rings.extend((x+px*ww*.5,y+py*hh*.5,zz) for px,py in profile)
        faces=[]; mats=[]
        for j in range(4):
            for k in range(8):
                faces.append((j*8+k,j*8+(k+1)%8,((j+1)%4)*8+(k+1)%8,((j+1)%4)*8+k))
                mats.append(rim if j == 1 else outer)
        self.add(rings,faces,mats)

    def plume(self, p, width, height, length, mat):
        x,y,z=p
        # A narrow, directional spear replaces the generic faceted diamond FX.
        profile=[(-1,0),(-.7,-.7),(0,-1),(.7,-.7),(1,0),(.7,.7),(0,1),(-.7,.7)]
        vertices=[]
        for dz,scale in [(0,1),(length*.18,.8),(length*.63,.32)]:
            vertices.extend((x+px*width*scale*.5,y+py*height*scale*.5,z+dz) for px,py in profile)
        vertices.append((x,y,z+length))
        faces=[tuple(reversed(range(8)))]
        for j in range(2):
            faces.extend((j*8+k,j*8+(k+1)%8,(j+1)*8+(k+1)%8,(j+1)*8+k) for k in range(8))
        faces.extend((16+k,16+(k+1)%8,24) for k in range(8))
        self.add(vertices,faces,mat)

    def object(self, a, offset=(0,0,0), scale=1):
        mesh=bpy.data.meshes.new(self.name)
        mesh.from_pydata([tuple(Vector(v)*scale-Vector(offset)) for v in self.vertices],[],self.faces)
        mesh.update()
        obj=bpy.data.objects.new(self.name,mesh)
        bpy.context.collection.objects.link(obj)
        for material in a.materials: mesh.materials.append(material)
        for face,mat in zip(mesh.polygons,self.materials):
            face.material_index=mat
            face.use_smooth=True
        mesh.set_sharp_from_angle(angle=math.radians(36))
        # The actual ceramic steps and exposed edge faces are already modeled.
        # A previous two-segment bevel replicated every small rail/restraint
        # edge, adding thousands of triangles without changing the silhouette.
        # Preserve the deliberate flat faces with angle-separated normals.
        return obj


def node(a, name):
    return next((n for n in a.document['nodes'] if n.get('name') == name), None)


def index_for(a, fragment, fallback=0):
    return next((i for i,m in enumerate(a.document['materials']) if fragment.lower() in m['name'].lower()), fallback)


def finishes(a):
    for i,m in enumerate(a.document['materials']):
        name=m.get('name','').lower()
        if 'emission' in name or 'core' in name:
            a.set_material(i,color=(.006,.3,.5,1),metal=.08,rough=.24,
                           emission=(.018,.66,1),strength=3.2 if 'core' in name else 2.8,role='energy')
        elif 'structure' in name:
            a.set_material(i,color=(.014,.024,.033,1),metal=.64,rough=.36,role='structure')
        else:
            color=(.67,.715,.75,1) if 'hull' in name else ((.54,.60,.64,1) if 'facet a' in name else (.60,.66,.71,1))
            a.set_material(i,color=color,metal=.13,rough=.34,role='hull',coat=.25)
    return dict(
        white=index_for(a,'Hull'), dark=index_for(a,'Structure'), energy=index_for(a,'Emission'),
        satin=a.add_material('PRISMA | Concept ceramic edge',color=(.42,.49,.55,1),metal=.23,rough=.38,role='hull',coat=.2),
        metal=a.add_material('PRISMA | Concept axial graphite',color=(.035,.057,.073,1),metal=.7,rough=.33,role='structure'),
        ice=a.add_material('PRISMA | Concept pale cyan aperture',color=(.08,.57,.75,1),metal=.08,rough=.22,emission=(.10,.73,1),strength=3.0,role='energy'),
        plasma=a.add_material('PRISMA | Concept tapered ion plume',color=(.01,.28,.46,.7),metal=0,rough=.4,emission=(.005,.53,1),strength=3.8,role='plume'),
    )


def military(a, ship_id, mats):
    rank=int(ship_id[:2])-1
    hull=node(a,'Hull'); hull_index=hull['mesh']; origin=hull.get('translation',[0,0,0])
    old=a.mesh_objects[hull_index]
    coords=[v.co+Vector(origin) for v in old.data.vertices]
    length=max(v.z for v in coords)-min(v.z for v in coords)
    energy_nodes=[n for n in a.document['nodes'] if n.get('name','').startswith('energy_') and 'mesh' in n]
    spread=abs(energy_nodes[0]['translation'][0])/length if energy_nodes else .105
    e=spread
    white,dark,metal,energy=mats['white'],mats['dark'],mats['metal'],mats['energy']
    shape=Shape('PRISMA bespoke split ceramic lances')
    for sign in [-1,1]:
        def poly(points): return [(sign*x,z) for x,z in points]
        # Graphite load-bearing lance is visibly deeper than the top plates.
        footprint=[(.012,-.5),(e+.07,.23),(e+.042,.46),(e-.049,.445),(.035,.16)]
        shape.plate(poly(footprint),-.052,.016,dark)
        # Long porcelain foreblade and asymmetric diagonal shoulder joint.
        fore=[(.020,-.5),(e*.72+.030,-.13),(.062,-.055),(.027,-.305)]
        shape.plate(poly(fore),.012,[.027,.065,.060,.036],white,mats['satin'])
        aft=[(e*.72+.030,-.121),(e+.058,.228),(e+.031,.397),(e-.040,.429),(.057,.166),(.063,-.043)]
        shape.plate(poly(aft),.014,[.066,.072,.040,.033,.054,.060],white,mats['satin'])
        # A separate lower ceramic edge follows the sweep, as in the illustration.
        flank=[(e*.73+.034,-.1),(e+.071,.227),(e+.043,.406),(e+.026,.392),(e+.046,.222)]
        shape.plate(poly(flank),-.025,.004,mats['satin'],dark)
        # Raised aft service casing: one bespoke stepped plate per lance.
        cap=[(e-.009,.145),(e+.037,.245),(e+.020,.358),(e-.030,.397),(e-.047,.312)]
        shape.plate(poly(cap),.055,[.067,.088,.064,.048,.081],white,mats['satin'])
        # Thin light rail sits down inside a graphite rail bed.
        shape.box((sign*.031,.012,-.065),(.016,.016,.58),dark)
        shape.box((sign*.031,.020,-.065),(.0036,.0028,.55),energy)
        # There are deliberate individual restraints, not a tiled texture.
        for z,w in [(-.18,.025),(.055,.038),(.235,.049)]:
            shape.box((sign*.063,.018,z),(w,.017,.023),metal)
            shape.box((sign*.059,.028,z+.002),(.011,.004,.008),energy)
        if rank >= 1:
            swept=[(e+.010,-.073),(e+.135,.259),(e+.060,.397),(e+.044,.210)]
            shape.plate(poly(swept),-.011,[.041,.047,.02,.053],white,mats['satin'])
            shape.plate(poly([(e+.027,-.028),(e+.13,.25),(e+.116,.279),(e+.023,.006)]),-.025,-.007,dark)
        if rank >= 3:
            oute=e+.145
            outer=[(e+.083,.015),(e+.225,.35),(e+.165,.438),(e+.112,.32)]
            shape.plate(poly(outer),-.035,[.010,.028,.007,.013],white,dark)
            shape.tube_z((sign*oute,-.025,.428),.073,.062,.106,.009,dark,mats['satin'])
            shape.box((sign*oute,-.025,.484),(.047,.036,.004),mats['ice'])
            shape.plume((sign*oute,-.025,.49),.043,.027,.10,mats['plasma'])
        if rank >= 4:
            # Capital silhouette has a second nested sweep and distinct stepped terraces.
            for k in range(rank-2):
                z=.21-k*.115
                ridge=[(e-.007,z-.08),(e+.065,z+.045),(e+.013,z+.092),(e-.026,z+.005)]
                shape.plate(poly(ridge),.061+k*.003,[.079,.091,.068,.075],white,mats['satin'])
    # Deep axial spine; narrow gaps remain visible through the fore channel.
    shape.plate([(-.030,-.325),(.030,-.325),(.060,.34),(.042,.43),(-.042,.43),(-.060,.34)],-.052,-.009,dark)
    shape.box((0,-.013,.33),(e*2,.035,.053),dark)
    if rank>=2:
        shape.plate([(-.014,-.365),(.014,-.365),(.015,.27),(-.015,.27)],-.013,-.001,metal)
        shape.box((0,.004,-.031),(.0045 if rank<5 else .009,.004,.64),energy)
    if rank>=3:
        shape.plate([(-.055,.12),(.0,-.02),(.055,.12),(.042,.287),(-.042,.287)],.019,[.068,.048,.068,.075,.075],white,mats['satin'])
        shape.box((0,.081,.217),(.029,.006,.035),metal)
        shape.box((0,.085,.209),(.018,.003,.008),energy)
    # Match the preserved animated aperture locations exactly.
    for n in energy_nodes:
        p=Vector(n.get('translation',[0,0,0]))/length
        shape.tube_z((p.x,p.y,p.z-.035),.091,.068,.106,.010,dark,mats['satin'])
        sign=1 if p.x>=0 else -1
        shape.plate([(p.x-.038,p.z-.08),(p.x+.038,p.z-.08),(p.x+.039,p.z-.003),(p.x-.039,p.z-.003)],p.y+.031,p.y+.042,white,mats['satin'])
        plume=Shape('PRISMA aligned ion spear')
        plume.plume((0,0,.004),.048,.026,.12 if rank<4 else .14,mats['plasma'])
        a.append_geometry(n['mesh'],plume.object(a,scale=length))
    a.replace_mesh(hull_index,shape.object(a,origin,length))
    # Existing source drive marker/animation stays; turn its conspicuous diamond
    # into a tiny nozzle glow because actual exhaust now lives on both engines.
    drive=node(a,'FX_drive')
    if drive:
        dot=Shape('PRISMA aft status core'); dot.box((0,0,0),(.001,.001,.001),energy)
        a.replace_mesh(drive['mesh'],dot.object(a,scale=length))
    return {'authored':'full split-lance ceramic / axial bed / paired engines','length':length}


def ceramic_layers(a,mats,model_id):
    """One inset raised ceramic shape per broad original armor face.

    The layer follows the actual original face outline. No UV projection or
    repeating panel atlas is used, and moving subassemblies keep their pivots.
    """
    import bmesh
    layer_count=0
    for mesh_index,obj in list(a.mesh_objects.items()):
        if not obj.data.vertices: continue
        # Convex plate top regions are discovered after welding/dissolving the
        # tiny bevel triangles. This groups every original design-specific face.
        bm=bmesh.new(); bm.from_mesh(obj.data)
        coords=[v.co for v in bm.verts]
        span=max(max(v[i] for v in coords)-min(v[i] for v in coords) for i in range(3))
        if span<1e-5: bm.free(); continue
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=max(span*1e-6,1e-7))
        bmesh.ops.dissolve_limit(bm,angle_limit=.008,verts=list(bm.verts),edges=list(bm.edges),delimit={'MATERIAL'})
        bm.normal_update()
        details=Shape('PRISMA individual raised ceramic layers')
        for f in bm.faces:
            material=a.document['materials'][f.material_index]
            if material.get('extras',{}).get('conceptRole') != 'hull' or f.normal.y < .64:
                continue
            area=f.calc_area()
            if area < span*span*.0014 or len(f.verts)<3:
                continue
            # The inset is large and singular: it describes the actual armor
            # component, instead of chopping the design into a tile grid.
            center=f.calc_center_median(); normal=f.normal.copy()
            points=[center+(v.co-center)*.80 for v in f.verts]
            rise=min(math.sqrt(area)*.055,span*.012)
            bottom=[p+normal*span*.0004 for p in points]
            top=[p+normal*rise for p in points]
            n=len(points)
            faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
            faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
            details.add(bottom+top,faces,[mats['satin'],mats['white']]+[mats['satin']]*n)
            layer_count+=1
        bm.free()
        if details.faces:
            a.append_geometry(mesh_index,details.object(a))
    return layer_count


def civilian(a,model_id,mats):
    count=ceramic_layers(a,mats,model_id)
    if model_id=='07_arbeiter':
        cargo=node(a,'Cargo_optional')
        if cargo:
            idx=cargo['mesh']; source=a.mesh_objects[idx]
            points=[v.co for v in source.data.vertices]
            span=max(max(v[i] for v in points)-min(v[i] for v in points) for i in range(3))
            s=Shape('PRISMA angular cargo cassette')
            s.box((0,0,0),(span*.82,span*.63,span*.98),mats['metal'])
            s.box((0,span*.35,0),(span*.80,span*.08,span*.93),mats['white'])
            for sign in [-1,1]:
                s.box((sign*span*.41,0,0),(span*.065,span*.60,span*.98),mats['satin'])
            s.box((0,0,span*.505),(span*.49,span*.22,span*.024),mats['dark'])
            s.box((0,0,span*.523),(span*.38,span*.10,span*.010),mats['energy'])
            a.replace_mesh(idx,s.object(a))
    if model_id=='08_forschung':
        hull=node(a,'Hull'); origin=Vector(hull.get('translation',[0,0,0])); idx=hull['mesh']
        points=[v.co+origin for v in a.mesh_objects[idx].data.vertices]
        length=max(v.z for v in points)-min(v.z for v in points)
        shape=Shape('PRISMA research swept ceramic shoulders')
        for sign in [-1,1]:
            pts=[(sign*.018,-.47),(sign*.235,.21),(sign*.175,.345),(sign*.093,.21),(sign*.092,-.13)]
            shape.plate(pts,-.022,[.026,.018,.025,.043,.033],mats['white'],mats['dark'])
        a.append_geometry(idx,shape.object(a,origin,length))
    # Civilian drive point is converted into one elongated ion plume. Its
    # original node location, channels, marker and idle pulse remain untouched.
    drive=node(a,'FX_drive')
    if drive:
        idx=drive['mesh']; source=a.mesh_objects[idx]
        pts=[v.co for v in source.data.vertices]
        radius=max((v.length for v in pts),default=.1)
        shape=Shape('PRISMA civilian directional exhaust')
        shape.plume((0,0,-radius*.22),radius*.75,radius*.48,radius*4,mats['plasma'])
        a.replace_mesh(idx,shape.object(a))
    return {'authored':'individual ceramic outline layers; bespoke civilian assembly','layers':count}


def render_preview(a,model_id,before=False):
    folder=OUT; folder.mkdir(parents=True,exist_ok=True)
    PREVIEW.mkdir(parents=True,exist_ok=True)
    name=model_id+('-before' if before else '-after')
    for obj in bpy.context.scene.objects:
        obj.hide_render=True
    bpy.context.preferences.filepaths.save_version=0
    a.save_blend(PREVIEW/(name+'.blend'))
    # save_blend assembles original node transforms. Render that scene after a
    # single world conversion from GLTF Y-up to Blender Z-up.
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and not o.hide_render]
    if not meshes: return
    root=bpy.data.objects.new('PRISMA preview orientation',None); bpy.context.collection.objects.link(root)
    for obj in meshes:
        if obj is root or obj.parent: continue
        obj.parent=root
    root.rotation_euler.x=math.pi/2
    bpy.context.view_layer.update()
    corners=[obj.matrix_world@Vector(corner) for obj in meshes for corner in obj.bound_box]
    lo=Vector(tuple(min(v[i] for v in corners) for i in range(3)))
    hi=Vector(tuple(max(v[i] for v in corners) for i in range(3)))
    center=(lo+hi)*.5; span=max(hi-lo)
    camera_path=folder/(model_id+'-camera.json')
    if before or not camera_path.exists():
        camera_path.write_text(json.dumps({'center':list(center),'span':span},indent=2)+'\n')
    else:
        saved=json.loads(camera_path.read_text());center=Vector(saved['center']);span=saved['span']
    scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.samples=20
    scene.cycles.use_denoising=True
    scene.render.resolution_x=1080;scene.render.resolution_y=900;scene.render.resolution_percentage=100
    if scene.world is None: scene.world=bpy.data.worlds.new('PRISMA charcoal backdrop')
    scene.world.use_nodes=True
    background=scene.world.node_tree.nodes.get('Background')
    background.inputs['Color'].default_value=(.022,.032,.043,1)
    background.inputs['Strength'].default_value=.45
    scene.view_settings.view_transform='AgX'
    for light_name,delta,power,color,size in [
        ('Large cool key',(1,-1.1,2),1100,(.88,.94,1),1.2),
        ('Soft pale rim',(-1,1.3,.8),1500,(.60,.81,1),1.0),
        ('Small warm fill',(-1,-1,.3),450,(1,.91,.80),.8),
    ]:
        light=bpy.data.lights.new(light_name,'AREA'); light.energy=power*span*span*.025;light.shape='DISK';light.size=span*size;light.color=color
        obj=bpy.data.objects.new(light_name,light);scene.collection.objects.link(obj);obj.location=center+Vector(delta)*span
        obj.rotation_euler=(center-obj.location).to_track_quat('-Z','Y').to_euler()
    camera=bpy.data.cameras.new('Concept inspection');obj=bpy.data.objects.new('Concept inspection',camera);scene.collection.objects.link(obj)
    obj.location=center+Vector((.90,-1.50,1.3))*span
    obj.rotation_euler=(center-obj.location).to_track_quat('-Z','Y').to_euler();camera.type='ORTHO';camera.ortho_scale=span*1.10;scene.camera=obj
    scene.use_nodes=True
    tree=scene.node_tree;tree.nodes.clear()
    layers=tree.nodes.new('CompositorNodeRLayers')
    glow=tree.nodes.new('CompositorNodeGlare');glow.glare_type='FOG_GLOW';glow.quality='HIGH';glow.threshold=1.5
    composite=tree.nodes.new('CompositorNodeComposite')
    tree.links.new(layers.outputs['Image'],glow.inputs['Image']);tree.links.new(glow.outputs['Image'],composite.inputs['Image'])
    # Finish the render on the roomy temporary disk before copying its small
    # review image into the workspace. A full output disk must not truncate it.
    scene.render.image_settings.file_format='PNG';scene.render.filepath=str(PREVIEW/(name+'.png'))
    bpy.ops.wm.save_as_mainfile(filepath=str(PREVIEW/(name+'.blend')),compress=True)
    bpy.ops.render.render(write_still=True)
    shutil.copy2(PREVIEW/(name+'.png'), folder/(name+'.png'))


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--only');parser.add_argument('--render',action='store_true')
    parser.add_argument('--before-render',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    report=[]
    for path in sorted((ROOT/'public/models/prisma').glob('*.glb')):
        model_id=path.stem
        if args.only and model_id!=args.only:continue
        if args.before_render:
            if args.only or model_id in COMPARISONS:
                a=ConceptAsset('prisma',model_id,source=BEFORE/path.name)
                render_preview(a,model_id,before=True)
            continue
        a=ConceptAsset('prisma',model_id,source=ORIGINAL/path.name)
        mats=finishes(a)
        if model_id in ['01_korvette','02_fregatte','03_zerstoerer','04_kreuzer','05_schlachtschiff','06_titan']:
            entry=military(a,model_id,mats)
        elif model_id in ['07_arbeiter','08_forschung']:
            entry=civilian(a,model_id,mats)
        else:
            entry={'authored':'silhouette-matched individual ceramic layers','layers':ceramic_layers(a,mats,model_id)}
        a.write()
        before_tri=triangle_count(read_document(BEFORE/path.name));after_tri=triangle_count(a.document)
        entry.update(model=model_id,bytes=path.stat().st_size,before_triangles=before_tri,
                     triangles=after_tri,reduction_percent=round(100*(1-after_tri/before_tri),2))
        OUT.mkdir(parents=True,exist_ok=True)
        (OUT/(model_id+'.json')).write_text(json.dumps(entry,indent=2)+'\n')
        report.append(entry);print(json.dumps(entry),flush=True)
        if args.render and (args.only or model_id in COMPARISONS):
            render_preview(a,model_id)
    if not args.before_render:
        report=[json.loads((OUT/(p.stem+'.json')).read_text())
                for p in sorted((ROOT/'public/models/prisma').glob('*.glb')) if (OUT/(p.stem+'.json')).exists()]
        (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':main()
