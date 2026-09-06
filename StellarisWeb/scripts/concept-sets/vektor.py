"""VEKTOR concept authoring in Blender 4.5; no generic surface atlas.

The connected delta reference supplies coherent pearl surface colours on every
exterior face. Military ships use closed watertight folded volumes; civilian
appendages and station petals have broad physical roots and supporting keels.
Original animation nodes and buffers are preserved by ConceptAsset. The sparse
authoring mesh keeps the approved folds and silhouette, with only a 2x2 colour
support grid on military panels instead of the former uniform 6x6 subdivision.

blender --background --factory-startup --python scripts/concept-sets/vektor.py -- --render
blender --background --factory-startup --python scripts/concept-sets/vektor.py -- --military --render --overview
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'scripts'))
from concept_asset import ConceptAsset, asset_ids

OUTPUT = ROOT/'artifacts/model-remesh/vektor'
REFERENCE = ROOT/'artifacts/concept-reference/RTS_Designs/01_Sets/Vektor/vektor_connected_concept.png'


class ReferencePearl:
    """Barycentric image samples from actual broad facets in the reference.

    We raise the value to recover a usable material albedo from the shaded
    illustration, while retaining its cyan/lilac/champagne colour ratios.
    Pixels from the black background or blue energy joints are rejected.
    """
    patches = [
        ((406,455),(836,411),(878,483)),
        ((929,345),(1198,152),(1180,386)),
        ((912,539),(1180,690),(1177,536)),
        ((980,544),(1146,655),(1087,573)),
    ]

    def __init__(self):
        image = bpy.data.images.load(str(REFERENCE), check_existing=True)
        self.width, self.height = image.size
        self.pixels = list(image.pixels)
        self.projection=None

    def project(self,points,military=False):
        lo=Vector([min(p[i] for p in points) for i in range(3)])
        hi=Vector([max(p[i] for p in points) for i in range(3)])
        order=sorted(range(3),key=lambda i:hi[i]-lo[i],reverse=True)
        self.projection=(lo,hi,2 if military else order[0],0 if military else order[1])

    def at_position(self,position):
        lo,hi,uaxis,vaxis=self.projection
        u=max(0,min(1,(position[uaxis]-lo[uaxis])/max(1e-8,hi[uaxis]-lo[uaxis])))
        v=max(-1,min(1,(position[vaxis]-(lo[vaxis]+hi[vaxis])*.5)/max(1e-8,(hi[vaxis]-lo[vaxis])*.5)))
        x=80+u/.55*750 if u<=.55 else 830+(u-.55)/.45*410
        if x<=830:half_width=85*(x-80)/750
        else:half_width=85+(x-830)*(.70 if v<0 else .57)
        y=445+v*half_width*.91
        return self.sample(x,y)

    def sample(self,x,y):
        i=(int(self.height-1-y)*self.width+int(x))*4
        rgb=self.pixels[i:i+3]
        if max(rgb)-min(rgb)>.48 or sum(rgb)<.85:rgb=[.64,.67,.76]
        linear=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
        luminance=sum(linear)/3
        scale=.65/max(.09,luminance)*(.88+.22*min(1,luminance/.65))
        chroma=[luminance+(c-luminance)*1.25 for c in linear]
        return tuple(min(.93,max(.20,c*scale)) for c in chroma)+(1,)



class Geometry:
    def __init__(self,name):
        self.name=name; self.vertices=[]; self.faces=[]; self.indices=[]
        self.colours=[]; self.normals=[]

    def triangle(self,points,mat,colours=None,normals=None):
        offset=len(self.vertices)
        self.vertices.extend(tuple(v) for v in points)
        self.faces.append((offset,offset+1,offset+2));self.indices.append(mat)
        self.colours.extend(colours or [(1,1,1,1)]*3)
        if normals is None:
            n=(Vector(points[1])-Vector(points[0])).cross(Vector(points[2])-Vector(points[0])).normalized()
            normals=[n]*3
        self.normals.extend(tuple(n) for n in normals)

    def filament(self,start,end,radius,mat,sections=5):
        a,b=Vector(start),Vector(end);axis=(b-a).normalized()
        side=axis.cross(Vector((0,1,0)))
        if side.length < .1:side=axis.cross(Vector((1,0,0)))
        side.normalize();up=axis.cross(side)
        rings=[]
        for point,width in [(a,radius*.18),(a.lerp(b,.15),radius),(a.lerp(b,.85),radius),(b,radius*.18)]:
            rings.append([point+(side*math.cos(j*math.tau/sections)+up*math.sin(j*math.tau/sections))*width for j in range(sections)])
        for ring,next_ring in zip(rings,rings[1:]):
            for j in range(sections):
                k=(j+1)%sections
                self.triangle((ring[j],ring[k],next_ring[k]),mat)
                self.triangle((ring[j],next_ring[k],next_ring[j]),mat)

    def plate(self,corners,thickness,ridge,mat,normal=Vector((0,1,0))):
        """Closed folded crystal volume; all boundary edges have real walls."""
        points=[Vector(v) for v in corners];normal=Vector(normal).normalized()
        center=sum(points,Vector())/len(points)
        top=[p+normal*thickness*.5 for p in points]
        bottom=[p-normal*thickness*.5 for p in points]
        peak=center+normal*(thickness*.5+ridge)
        belly=center-normal*(thickness*.5+ridge*.6)
        if (points[1]-points[0]).cross(points[2]-points[0]).dot(normal)<0:
            top.reverse();bottom.reverse()
        for i in range(len(top)):
            j=(i+1)%len(top)
            self.triangle((top[i],top[j],peak),mat)
            self.triangle((bottom[j],bottom[i],belly),mat)
            self.triangle((top[j],top[i],bottom[i]),mat)
            self.triangle((top[j],bottom[i],bottom[j]),mat)

    def brace(self,start,end,width_start,width_end,depth,mat):
        """Broad tapered structural crystal, not a connection line."""
        a,b=Vector(start),Vector(end);axis=(b-a).normalized()
        if (b-a).length<1e-7:return
        side=axis.cross(Vector((0,1,0)))
        if side.length<.05:side=axis.cross(Vector((1,0,0)))
        side.normalize();up=axis.cross(side).normalized()
        rings=[]
        for p,w in [(a,width_start),(a.lerp(b,.65),(width_start+width_end)*.52),(b,width_end)]:
            rings.append([p+side*w*.5,p+up*depth*.5,p-side*w*.5,p-up*depth*.5])
        self.triangle((rings[0][0],rings[0][2],rings[0][1]),mat);self.triangle((rings[0][0],rings[0][3],rings[0][2]),mat)
        for left,right in zip(rings,rings[1:]):
            for j in range(4):
                k=(j+1)%4
                self.triangle((left[j],left[k],right[k]),mat);self.triangle((left[j],right[k],right[j]),mat)
        self.triangle((rings[-1][0],rings[-1][1],rings[-1][2]),mat);self.triangle((rings[-1][0],rings[-1][2],rings[-1][3]),mat)

    def object(self,asset):
        mesh=bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.vertices,[],self.faces);mesh.update(calc_edges=True)
        for mat in asset.materials:mesh.materials.append(mat)
        for poly,mat in zip(mesh.polygons,self.indices):poly.material_index=mat;poly.use_smooth=True
        mesh.normals_split_custom_set([self.normals[loop.vertex_index] for loop in mesh.loops])
        attr=mesh.color_attributes.new(name='ConceptPearl',type='FLOAT_COLOR',domain='POINT')
        for i,colour in enumerate(self.colours):attr.data[i].color=colour
        mesh.color_attributes.active_color=attr
        obj=bpy.data.objects.new(self.name,mesh);bpy.context.collection.objects.link(obj)
        return obj


def finishes(asset):
    roles={}
    for i,source in enumerate(asset.document['materials']):
        name=source.get('name','').lower()
        if 'cyan' in name or 'emission' in name:
            asset.set_material(i,color=(.028,.20,.55,1),metal=.02,rough=.25,emission=(.035,.42,1),strength=3.0,role='energy')
            roles[i]='energy'
        elif 'core' in name:
            asset.set_material(i,color=(.06,.34,.72,1),metal=.02,rough=.22,emission=(.10,.49,1),strength=2.1,role='energy')
            roles[i]='core'
        else:
            asset.set_material(i,color=(1,1,1,1),metal=.16,rough=.255,role='crystal',coat=.5,conceptReference='vektor_connected_concept.png',conceptMainShell=True)
            source['doubleSided']=False
            source.setdefault('extensions',{})['KHR_materials_iridescence']={
                'iridescenceFactor':.46,'iridescenceIor':1.3,
                'iridescenceThicknessMinimum':180,'iridescenceThicknessMaximum':420}
            shader=asset.materials[i].node_tree.nodes.get('Principled BSDF')
            if 'Thin Film Thickness' in shader.inputs:shader.inputs['Thin Film Thickness'].default_value=320
            if 'Thin Film IOR' in shader.inputs:shader.inputs['Thin Film IOR'].default_value=1.3
            roles[i]='pearl' if 'pearl' in name or 'hull' in name or 'underside' in name or 'structure' in name else 'ice'
    edge=asset.add_material('VEKTOR | Concept white crystal cutting edge',color=(.77,.83,.90,1),metal=.24,rough=.20,role='crystal',coat=.48)
    roles[edge]='pearl'
    filament=asset.add_material('VEKTOR | Concept electric blue focus filaments',color=(.06,.26,.60,1),metal=0,rough=.24,emission=(.055,.47,1),strength=3.5,role='energy')
    if asset.asset_id=='07_arbeiter':
        cargo=asset.add_material('VEKTOR | Concept captive optical crystal',color=(1,1,1,1),metal=0,rough=.16,role='crystal',coat=.4)
        source=asset.document['materials'][cargo]
        source.setdefault('extensions',{}).update({
            'KHR_materials_transmission':{'transmissionFactor':.32},
            'KHR_materials_ior':{'ior':1.42},
            'KHR_materials_iridescence':{'iridescenceFactor':.30,'iridescenceIor':1.3,'iridescenceThicknessMinimum':180,'iridescenceThicknessMaximum':360},
        })
        shader=asset.materials[cargo].node_tree.nodes.get('Principled BSDF')
        shader.inputs['Transmission Weight'].default_value=.32;shader.inputs['IOR'].default_value=1.42
        roles[cargo]='ice'
        for node in asset.document['nodes']:
            if node.get('name')=='Cargo_optional' and 'mesh' in node:
                for poly in asset.mesh_objects[node['mesh']].data.polygons:
                    if roles.get(poly.material_index) in ['pearl','ice','structure']:poly.material_index=cargo
    # Blender previews use the very same baked colours that the GLB exports.
    for i,mat in enumerate(asset.materials):
        if roles.get(i) not in ['pearl','ice']:continue
        colour=mat.node_tree.nodes.new('ShaderNodeVertexColor');colour.layer_name='ConceptPearl'
        shader=mat.node_tree.nodes.get('Principled BSDF')
        mat.node_tree.links.new(colour.outputs['Color'],shader.inputs['Base Color'])
    return roles,edge,filament


def subdivide(surface,points,normal,mat,reference,patch,tone,n,reference_weights=None):
    p0,p1,p2=points
    reference_weights=reference_weights or [(1,0,0),(0,1,0),(0,0,1)]
    def point(i,j):
        weights=(1-(i+j)/n,i/n,j/n)
        image_weights=[sum(weights[k]*reference_weights[k][v] for k in range(3)) for v in range(3)]
        position=p0*weights[0]+p1*weights[1]+p2*weights[2]
        return position,reference.at_position(position)
    for i in range(n):
        for j in range(n-i):
            p=[point(i,j),point(i+1,j),point(i,j+1)]
            surface.triangle([x[0] for x in p],mat,[x[1] for x in p],[normal]*3)
            if i+j < n-1:
                p=[point(i+1,j),point(i+1,j+1),point(i,j+1)]
                surface.triangle([x[0] for x in p],mat,[x[1] for x in p],[normal]*3)


MILITARY_IDS=['01_korvette','02_fregatte','03_zerstoerer','04_kreuzer','05_schlachtschiff','06_titan']


def military_profile(model):
    """Six separately authored planforms and cross sections, not scaled ranks.

    Each station is (keel Z, half width, keel half width, dorsal height,
    edge half thickness, wing-tip Z). Re-entrant shoulders remain part of one
    continuous skin. Seven-column sections give the heavy classes independent
    wing beds and raised central spines, in addition to their own planforms.
    """
    profiles={
        '01_korvette':dict(name='V1 compact delta',columns=5,belly=.82,keel=.81,wing=.5,rows=[
            (-.5,.001,.00045,.002,.0015,-.5),
            (-.06,.055,.025,.01674,.009,-.06),
            (.055,.09,.037,.027,.014,.055),
            (.265,.20,.045,.02511,.010,.355),
            (.335,.061,.034,.02214,.019,.335),
            (.435,.036,.021,.026,.018,.435),
            (.5,.027,.019,.022,.017,.5),
        ]),
        '02_fregatte':dict(name='Aft-wing lance',columns=5,belly=.62,keel=.73,wing=.5,rows=[
            (-.5,.001,.00045,.002,.0012,-.5),
            (-.32,.016,.008,.016,.004,-.32),
            (-.07,.025,.012,.030,.007,-.07),
            (.15,.030,.014,.039,.009,.15),
            (.285,.040,.018,.038,.009,.285),
            (.345,.142,.023,.030,.006,.425),
            (.417,.041,.023,.027,.012,.443),
            (.466,.032,.019,.024,.017,.466),
            (.5,.027,.019,.022,.017,.5),
        ]),
        '03_zerstoerer':dict(name='Twin-stage assault arrow',columns=5,belly=.74,keel=.86,wing=.5,rows=[
            (-.5,.001,.00045,.002,.0015,-.5),
            (-.38,.033,.015,.023,.006,-.38),
            (-.255,.190,.030,.048,.011,-.285),
            (-.125,.065,.031,.052,.013,-.13),
            (.01,.079,.035,.065,.016,.01),
            (.16,.293,.040,.064,.009,.275),
            (.30,.096,.039,.054,.020,.33),
            (.39,.061,.029,.036,.019,.425),
            (.46,.033,.020,.025,.017,.46),
            (.5,.027,.019,.022,.017,.5),
        ]),
        '04_kreuzer':dict(name='Broad low manta',columns=7,belly=.50,keel=.82,wing=.53,rows=[
            (-.5,.001,.00045,.002,.0015,-.5),
            (-.423,.202,.035,.020,.007,-.435),
            (-.24,.468,.050,.032,.008,-.365),
            (-.07,.592,.058,.039,.010,-.11),
            (.15,.408,.058,.037,.012,.235),
            (.28,.193,.049,.032,.014,.345),
            (.385,.076,.034,.027,.017,.405),
            (.47,.032,.021,.023,.017,.47),
            (.5,.027,.019,.022,.017,.5),
        ]),
        '05_schlachtschiff':dict(name='Armored triple wedge',columns=7,belly=.81,keel=.91,wing=.65,rows=[
            (-.5,.001,.00045,.003,.0018,-.5),
            (-.37,.113,.043,.053,.020,-.38),
            (-.285,.286,.059,.086,.026,-.32),
            (-.20,.190,.063,.103,.035,-.18),
            (-.075,.386,.077,.125,.032,-.105),
            (.025,.277,.080,.139,.047,.04),
            (.155,.468,.085,.135,.036,.17),
            (.25,.332,.078,.111,.042,.28),
            (.36,.198,.057,.083,.037,.39),
            (.446,.067,.029,.042,.022,.455),
            (.5,.027,.019,.022,.017,.5),
        ]),
        '06_titan':dict(name='Axial crystal cathedral',columns=7,belly=.36,keel=.46,wing=.28,rows=[
            (-.5,.001,.00045,.003,.0015,-.5),
            (-.405,.029,.010,.030,.007,-.405),
            (-.305,.188,.022,.067,.012,-.335),
            (-.225,.101,.025,.109,.018,-.22),
            (-.125,.289,.031,.154,.018,-.17),
            (-.01,.170,.036,.194,.025,-.015),
            (.085,.398,.043,.212,.020,.045),
            (.19,.224,.046,.198,.032,.195),
            (.285,.427,.043,.163,.021,.385),
            (.365,.209,.038,.121,.025,.415),
            (.427,.082,.031,.074,.023,.446),
            (.476,.035,.021,.035,.018,.476),
            (.5,.027,.019,.022,.017,.5),
        ]),
    }
    if model in profiles:return profiles[model]
    # The artillery platform is a separate, unchanged design. It must not
    # inherit any new combat-class silhouette through a shared rank lookup.
    return dict(name='Existing artillery delta',columns=5,belly=.82,keel=.81,wing=.5,rows=[
        (-.5,.001,.00045,.002,.0015,-.5),(-.13,.055,.025,.01984,.009,-.13),
        (.055,.09,.037,.032,.014,.055),(.265,.235,.045,.02976,.010,.355),
        (.335,.061,.034,.02624,.019,.335),(.435,.036,.021,.026,.018,.435),
        (.5,.027,.019,.022,.017,.5),
    ])


def rebuild_joined_military(asset,roles):
    """Build a class-specific, watertight main shell with physical wing roots."""
    classes=MILITARY_IDS
    if asset.asset_id not in classes+['06_artillerieplattform']:return False
    profile=military_profile(asset.asset_id)
    hull=next(n for n in asset.document['nodes'] if n.get('name')=='Hull')
    drive=next((n for n in asset.document['nodes'] if n.get('name')=='FX_drive'),None)
    origin=Vector(hull.get('translation',[0,0,0]))
    original=asset.mesh_objects[hull['mesh']].data
    nose=min(v.co.z+origin.z for v in original.vertices)
    rear=drive['translation'][2] if drive else max(v.co.z+origin.z for v in original.vertices)
    span=rear-nose;center=(nose+rear)*.5
    rows=profile['rows'];columns=profile['columns']
    shell=Geometry('VEKTOR '+profile['name']+' main shell')
    pearl=next(i for i,r in roles.items() if r=='pearl')
    ice=[i for i,r in roles.items() if r=='ice']
    tint=ice[0] if ice else pearl
    def point(row,column,upper):
        z,w,k,h,e,tipz=rows[row]
        if columns==5:
            xx=[-w,-k,0,k,w][column]
            zz=tipz if column in [0,4] else z
            yy=[e,h*profile['keel'],h,h*profile['keel'],e][column]
        else:
            shoulder=max(k+(w-k)*.60,w*.52)
            xx=[-w,-shoulder,-k,0,k,shoulder,w][column]
            zz=z+(tipz-z)*[1,.60,0,0,0,.60,1][column]
            yy=[e,h*profile['wing'],h*profile['keel'],h,h*profile['keel'],h*profile['wing'],e][column]
        yy=yy if upper else -yy*profile['belly']
        return Vector((xx*span,yy*span,center+zz*span))-origin
    def quad(points,mat):
        shell.triangle((points[0],points[1],points[2]),mat)
        shell.triangle((points[0],points[2],points[3]),mat)
    count=len(rows)
    for row in range(count-1):
        for col in range(columns-1):
            mat=tint if col in [0,columns-2] and 0<row<count-2 else pearl
            quad([point(row,col,True),point(row+1,col,True),point(row+1,col+1,True),point(row,col+1,True)],mat)
            quad([point(row,col,False),point(row,col+1,False),point(row+1,col+1,False),point(row+1,col,False)],mat)
        quad([point(row,0,True),point(row,0,False),point(row+1,0,False),point(row+1,0,True)],pearl)
        last=columns-1
        quad([point(row,last,True),point(row+1,last,True),point(row+1,last,False),point(row,last,False)],pearl)
    for col in range(columns-1):
        quad([point(0,col,True),point(0,col+1,True),point(0,col+1,False),point(0,col,False)],pearl)
        quad([point(count-1,col,True),point(count-1,col,False),point(count-1,col+1,False),point(count-1,col+1,True)],pearl)
    obj=shell.object(asset)
    asset.mesh_objects[hull['mesh']].data=obj.data;bpy.data.objects.remove(obj,do_unlink=True)
    asset.mesh_objects[hull['mesh']]['joined_shell_source']=True
    # The short plume starts inside the solid aft collar at the untouched
    # original FX marker; its scale animation cannot separate it from the ship.
    if drive:replace_drive(asset,roles,span)
    asset.document.setdefault('extras',{}).update(conceptJoinedHull=True,conceptAllSidePearl=True,
                                                conceptMilitaryProfile=profile['name'])
    return True


def replace_drive(asset,roles,span):
    drive=next((n for n in asset.document['nodes'] if n.get('name')=='FX_drive'),None)
    if not drive:return
    effect=Geometry('VEKTOR inset short ion plume')
    energy=next(i for i,r in roles.items() if r=='energy')
    rings=[]
    for z,rx,ry in [(-.007,.020,.014),(.008,.018,.013),(.042,.011,.008),(.12,.0006,.0006)]:
        rings.append([Vector((math.cos(j*math.tau/8)*rx*span,math.sin(j*math.tau/8)*ry*span,z*span)) for j in range(8)])
    for j in range(1,7):effect.triangle((rings[0][0],rings[0][j+1],rings[0][j]),energy)
    for left,right in zip(rings,rings[1:]):
        for j in range(8):
            k=(j+1)%8
            effect.triangle((left[j],left[k],right[k]),energy);effect.triangle((left[j],right[k],right[j]),energy)
    for j in range(1,7):effect.triangle((rings[-1][0],rings[-1][j],rings[-1][j+1]),energy)
    obj=effect.object(asset);asset.mesh_objects[drive['mesh']].data=obj.data;bpy.data.objects.remove(obj,do_unlink=True)


def set_source(asset,index,geometry):
    obj=geometry.object(asset)
    asset.mesh_objects[index].data=obj.data
    asset.mesh_objects[index]['joined_shell_source']=True
    bpy.data.objects.remove(obj,do_unlink=True)


def add_source(asset,index,geometry):
    original=asset.mesh_objects[index].data;original.calc_loop_triangles()
    for tri in original.loop_triangles:
        geometry.triangle([original.vertices[i].co for i in tri.vertices],tri.material_index,
                          normals=[original.corner_normals[i].vector for i in tri.loops])
    set_source(asset,index,geometry)


def model_span(asset):
    points=[]
    for node in asset.document['nodes']:
        if 'mesh' not in node or node.get('name','').startswith('FX_'):continue
        offset=Vector(node.get('translation',[0,0,0]))
        points.extend(v.co+offset for v in asset.mesh_objects[node['mesh']].data.vertices)
    return max(max(p[i] for p in points)-min(p[i] for p in points) for i in range(3))


def rebuild_civilian(asset,roles):
    if asset.asset_id not in ['07_arbeiter','08_forschung']:return False
    span=model_span(asset)
    pearl=next(i for i,r in roles.items() if r=='pearl')
    hull=next(n for n in asset.document['nodes'] if n.get('name')=='Hull')
    drive=next(n for n in asset.document['nodes'] if n.get('name')=='FX_drive')
    origin=Vector(hull.get('translation',[0,0,0]));drive_point=Vector(drive['translation'])
    body=Geometry('VEKTOR joined civilian keel and broad articulated roots')
    if asset.asset_id=='07_arbeiter':
        arms=[n for n in asset.document['nodes'] if n.get('name','').startswith('gripper_')]
        pivots=[Vector(n.get('translation',[0,0,0])) for n in arms]
        center=sum(pivots,Vector())*.5
        corners=[center+Vector((0,0,-span*.10)),
                 center+Vector((-span*.24,0,span*.01)),
                 drive_point+Vector((-span*.027,0,0)),
                 drive_point+Vector((span*.027,0,0)),
                 center+Vector((span*.24,0,span*.01))]
        body.plate([p-origin for p in corners],span*.055,span*.024,pearl)
        for arm in arms:
            pivot=Vector(arm['translation']);sign=-1 if 'left' in arm['name'] else 1
            body.brace(center-origin,pivot-origin,span*.24,span*.15,span*.08,pearl)
            # A thick, swept pincer grows out of a substantial rotating root.
            claw=Geometry('VEKTOR joined articulated crystal pincer')
            corners=[Vector((-sign*span*.045,0,span*.08)),Vector((sign*span*.075,0,-span*.25)),
                     Vector((-sign*span*.055,0,-span*.68)),Vector((-sign*span*.095,0,-span*.36))]
            claw.plate(corners,span*.035,span*.023,pearl)
            claw.brace(Vector((0,0,span*.045)),Vector((0,0,-span*.19)),span*.14,span*.11,span*.085,pearl)
            set_source(asset,arm['mesh'],claw)
    else:
        sensors=[n for n in asset.document['nodes'] if n.get('name','').startswith('sensor_') and 'mesh' in n]
        center=Vector((-.05,-span*.14,span*.04))
        corners=[center+Vector((0,0,-span*.48)),center+Vector((-span*.27,0,0)),
                 drive_point+Vector((-span*.027,0,0)),drive_point+Vector((span*.027,0,0)),
                 center+Vector((span*.27,0,span*.025))]
        body.plate([p-origin for p in corners],span*.065,span*.032,pearl)
        for sensor in sensors:
            pivot=Vector(sensor.get('translation',[0,0,0]));old=asset.mesh_objects[sensor['mesh']].data
            coords=[v.co.copy() for v in old.vertices]
            direction=max(coords,key=lambda v:v.length_squared).normalized()
            if direction.length_squared<.1:direction=Vector((0,1,0))
            side=direction.cross(Vector((0,1,0)))
            if side.length<.1:side=direction.cross(Vector((1,0,0)))
            side.normalize();normal=side.cross(direction).normalized()
            length=min(span*.27,max(span*.11,max(v.length for v in coords)*.70))
            fin=Geometry('VEKTOR attached crystal sensor fin')
            fin.plate([-direction*length*.22,side*length*.30,direction*length,-side*length*.30],
                      length*.11,length*.10,pearl,normal)
            set_source(asset,sensor['mesh'],fin)
            body.brace(center-origin,pivot-origin,span*.15,length*.42,span*.075,pearl)
        focus_node=next(n for n in asset.document['nodes'] if n.get('name')=='FX_sensor_focus')
        focus=Vector(focus_node.get('translation',[0,0,0]))
        body.brace(center-origin,focus-origin,span*.22,span*.17,span*.10,pearl)
        body.plate([focus-origin+Vector((math.cos(i*math.tau/6)*span*.085,0,math.sin(i*math.tau/6)*span*.085)) for i in range(6)],span*.045,span*.018,pearl)
    set_source(asset,hull['mesh'],body);replace_drive(asset,roles,span)
    asset.document.setdefault('extras',{}).update(conceptJoinedHull=True,conceptAllSidePearl=True)
    return True


def rebuild_station(asset,roles):
    petals=[n for n in asset.document['nodes'] if n.get('name','').startswith('folded_sail_') and 'mesh' in n]
    if not petals:return False
    span=model_span(asset);pearl=next(i for i,r in roles.items() if r=='pearl')
    hull=next(n for n in asset.document['nodes'] if n.get('name')=='Hull')
    origin=Vector(hull.get('translation',[0,0,0]))
    center=sum((Vector(n.get('translation',[0,0,0])) for n in petals),Vector())/len(petals)
    center.y=0
    body=Geometry('VEKTOR connected station crystalline hub and load bearing roots')
    body.plate([center-origin+Vector((math.cos(i*math.tau/8)*span*.11,0,math.sin(i*math.tau/8)*span*.11)) for i in range(8)],span*.07,span*.035,pearl)
    for node in petals:
        pivot=Vector(node['translation']);relative=pivot-center
        direction=relative.normalized();side=direction.cross(Vector((0,1,0)))
        if side.length<.1:side=direction.cross(Vector((1,0,0)))
        side.normalize();normal=side.cross(direction).normalized()
        old=asset.mesh_objects[node['mesh']].data;points=[v.co for v in old.vertices]
        length=max(max(p[i] for p in points)-min(p[i] for p in points) for i in range(3))*.83
        petal=Geometry('VEKTOR solid attached folded station petal')
        petal.plate([-direction*length*.28,side*length*.29,direction*length*.51,-side*length*.29],
                    length*.050,length*.068,pearl,normal)
        set_source(asset,node['mesh'],petal)
        body.brace(center-origin,pivot-origin,span*.18,length*.33,span*.068,pearl)
    # A small blue lens is seated into the broad hub, not suspended between sails.
    energy=next(i for i,r in roles.items() if r=='energy')
    lens=center-origin+Vector((0,span*.065,0))
    body.plate([lens+Vector((math.cos(i*math.tau/8)*span*.027,0,math.sin(i*math.tau/8)*span*.027)) for i in range(8)],span*.006,span*.007,energy)
    set_source(asset,hull['mesh'],body)
    asset.document.setdefault('extras',{}).update(conceptAttachedModules=True,conceptAllSidePearl=True)
    return True


def rebuild_megastructure(asset,roles):
    model=asset.asset_id
    supported=['01_mining_station','02_mining_ring','04_mega_shipyard','05_construction_level_0','orbital_ring']
    if model not in supported:return False
    span=model_span(asset);pearl=next(i for i,r in roles.items() if r=='pearl')
    energy=next(i for i,r in roles.items() if r=='energy')
    if model=='orbital_ring':
        index=next(n['mesh'] for n in asset.document['nodes'] if 'mesh' in n)
        body=Geometry('VEKTOR continuous folded orbital triangle')
        docks=[Vector(n['translation']) for n in asset.document['nodes'] if n.get('extras',{}).get('attachment_role','').startswith('dock_')]
        radius=sum(Vector((p.x,0,p.z)).length for p in docks)/len(docks)
        points=[Vector((p.x,0,p.z))*.983 for p in docks]
        for i,p in enumerate(points):
            q=points[(i+1)%3]
            body.brace(p,q,radius*.095,radius*.095,radius*.050,pearl)
            direction=p.normalized();side=direction.cross(Vector((0,1,0)))
            body.plate([p-direction*radius*.18,p+side*radius*.13,p+direction*radius*.070,p-side*radius*.13],
                       radius*.050,radius*.045,pearl)
            midpoint=(p+q)*.5
            edge_axis=(q-p).normalized();outward=midpoint.normalized()
            body.plate([midpoint-edge_axis*radius*.15-outward*radius*.035,
                        midpoint+edge_axis*radius*.15-outward*radius*.035,
                        midpoint+edge_axis*radius*.12+outward*radius*.090,
                        midpoint-edge_axis*radius*.12+outward*radius*.090],radius*.065,radius*.035,pearl)
            body.brace(p.lerp(q,.20)+Vector((0,radius*.03,0)),p.lerp(q,.80)+Vector((0,radius*.03,0)),radius*.011,radius*.011,radius*.007,energy)
        set_source(asset,index,body)
    else:
        hull=next(n for n in asset.document['nodes'] if n.get('name')=='Hull')
        origin=Vector(hull.get('translation',[0,0,0]))
        body=Geometry('VEKTOR connected folded megastructure backbone')
        if model=='01_mining_station':
            roots=[n for n in asset.document['nodes'] if n.get('name','').startswith('extractor_')]
            center=Vector((origin.x,origin.y,origin.z))
            body.plate([center-origin+Vector((math.cos(i*math.tau/6)*span*.14,0,math.sin(i*math.tau/6)*span*.14)) for i in range(6)],span*.09,span*.04,pearl)
            for node in roots:
                pivot=Vector(node.get('translation',[0,0,0]));direction=(pivot-center).normalized()
                end=pivot-direction*span*.13
                body.brace(center-origin,end-origin,span*.22,span*.13,span*.09,pearl)
                side=direction.cross(Vector((0,1,0))).normalized()
                body.plate([end-origin-direction*span*.11,end-origin+side*span*.11,
                            end-origin+direction*span*.12,end-origin-side*span*.11],span*.05,span*.035,pearl)
        elif model=='02_mining_ring':
            radius=span*.42;y=origin.y
            ring=[Vector((math.sin(i*math.tau/32)*radius,y,math.cos(i*math.tau/32)*radius)) for i in range(32)]
            for i,p in enumerate(ring):body.brace(p-origin,ring[(i+1)%32]-origin,span*.042,span*.042,span*.037,pearl)
            for node in [n for n in asset.document['nodes'] if n.get('name','').startswith('extractor_')]:
                pivot=Vector(node.get('translation',[0,0,0]));direction=Vector((pivot.x,0,pivot.z)).normalized()
                side=direction.cross(Vector((0,1,0)));p=direction*radius+Vector((0,y,0))
                body.plate([p-origin-direction*span*.07,p-origin+side*span*.06,p-origin+direction*span*.078,p-origin-side*span*.06],span*.035,span*.025,pearl)
                # The original Operate track retracts each shaft by 0.973
                # units. The fixed broad socket reaches 1.49 units beyond
                # the most retracted shaft end and follows its lower Y level.
                socket_end=direction*(radius-span*.15)+Vector((0,pivot.y,0))
                body.brace(p-origin,socket_end-origin,span*.10,span*.060,span*.06,pearl)
        elif model=='04_mega_shipyard':
            roots=[n for n in asset.document['nodes'] if n.get('name','').startswith('fabricator_')]
            zvalues=[n['translation'][2] for n in roots]
            y=sum(n['translation'][1] for n in roots)/len(roots)
            front=Vector((0,y,min(zvalues)-span*.10));aft=Vector((0,y,max(zvalues)+span*.10))
            body.brace(front-origin,aft-origin,span*.11,span*.11,span*.085,pearl)
            for node in roots:
                pivot=Vector(node['translation']);anchor=Vector((0,y,pivot.z))
                body.brace(anchor-origin,pivot-origin,span*.15,span*.115,span*.075,pearl)
                sign=-1 if pivot.x<0 else 1
                dock=Geometry('VEKTOR attached solid fabrication delta')
                dock.plate([Vector((-sign*span*.045,0,0)),Vector((sign*span*.07,0,-span*.10)),
                            Vector((sign*span*.14,0,0)),Vector((sign*span*.07,0,span*.10))],span*.045,span*.024,pearl)
                set_source(asset,node['mesh'],dock)
        else:
            roots=[n for n in asset.document['nodes'] if n.get('name','').startswith('build_group_')]
            pivots=[Vector(n['translation']) for n in roots]
            # A substantial partial spaceframe connects the staged build
            # modules; their original scale/assembly animation is retained.
            connected={0};remaining=set(range(1,len(roots)))
            while remaining:
                _,i,j=min(((pivots[i]-pivots[j]).length,i,j) for i in connected for j in remaining)
                body.brace(pivots[i]-origin,pivots[j]-origin,span*.055,span*.055,span*.038,pearl)
                connected.add(j);remaining.remove(j)
            for node,pivot in zip(roots,pivots):
                old=asset.mesh_objects[node['mesh']].data;coords=[v.co for v in old.vertices]
                length=max(max(p[i] for p in coords)-min(p[i] for p in coords) for i in range(3))*.65
                direction=Vector((pivot.x,0,pivot.z)).normalized();side=direction.cross(Vector((0,1,0)))
                part=Geometry('VEKTOR attached staged crystalline construction module')
                part.plate([-direction*length*.25,side*length*.35,direction*length*.75,-side*length*.35],length*.10,length*.075,pearl)
                set_source(asset,node['mesh'],part)
        set_source(asset,hull['mesh'],body)
    asset.document.setdefault('extras',{}).update(conceptAttachedModules=True,conceptAllSidePearl=True)
    return True


def author(asset,reference,roles,edge,filament):
    military=rebuild_joined_military(asset,roles)
    modules=False if military else (rebuild_civilian(asset,roles) or rebuild_station(asset,roles) or rebuild_megastructure(asset,roles))
    stats={'sampled_facets':0,'crystal_returns':0,'focus_frames':0,'triangles':0,
           'joined_main_shell':military,'attached_modules':modules,'all_side_pearl':True}
    for index,obj in asset.mesh_objects.items():
        mesh=obj.data;mesh.calc_loop_triangles()
        points=[v.co for v in mesh.vertices]
        reference.project(points,military)
        joined_source=bool(obj.get('joined_shell_source'))
        span=max(max(v[i] for v in points)-min(v[i] for v in points) for i in range(3))
        areas=[tri.area for tri in mesh.loop_triangles if roles.get(tri.material_index) in ['pearl','ice']]
        biggest=max(areas,default=1)
        surface=Geometry('VEKTOR reference-painted folded crystal')
        details=Geometry('VEKTOR knife-edge returns and focus geometry')
        for ti,tri in enumerate(mesh.loop_triangles):
            mat=tri.material_index;role=roles.get(mat,'energy')
            verts=[mesh.vertices[i].co.copy() for i in tri.vertices]
            if role in ['pearl','ice']:
                # Subdivision retains the original planar facet and its sharp
                # fold normal; it supplies smooth colour detail, not noise.
                if joined_source:
                    # The source triangles already describe the approved
                    # closed hull. Two subdivisions retain colour support on
                    # broad military panels. Small module facets need only
                    # their original corners; no geometry is moved or merged.
                    subdivide(surface,verts,tri.normal,mat,reference,ti,role,2 if military else 1)
                elif tri.area > biggest*.12:
                    # Shallow secondary optical folds follow the three broad
                    # corners of each original crystal. These are actual
                    # planar facets, like the large cuts in the illustration.
                    peak=sum(verts,Vector())/3+tri.normal*min(span*.0011,math.sqrt(tri.area)*.009)
                    weights=[(1,0,0),(0,1,0),(0,0,1)]
                    for k in range(3):
                        p=(verts[k],verts[(k+1)%3],peak)
                        normal=(p[1]-p[0]).cross(p[2]-p[0]).normalized()
                        subdivide(surface,p,normal,mat,reference,ti,role,2,[weights[k],weights[(k+1)%3],(1/3,1/3,1/3)])
                elif tri.area > biggest*.016:
                    subdivide(surface,verts,tri.normal,mat,reference,ti,role,1)
                else:
                    colours=[reference.at_position(p) for p in verts]
                    surface.triangle(verts,mat,colours,[mesh.corner_normals[i].vector.copy() for i in tri.loops])
                stats['sampled_facets']+=1
                if tri.area > biggest*.14 and not joined_source:
                    # A tiny physical polished return follows an existing long
                    # crystal edge. It does not create arbitrary panel seams.
                    pairs=[(verts[0],verts[1],verts[2]),(verts[1],verts[2],verts[0]),(verts[2],verts[0],verts[1])]
                    a,b,c=max(pairs,key=lambda p:(p[0]-p[1]).length)
                    start=a.lerp(b,.03)+tri.normal*span*.00005
                    end=a.lerp(b,.96)+tri.normal*span*.00005
                    inward=(c-(a+b)*.5).normalized()*min(span*.00055,(a-b).length*.002)
                    details.triangle((start,end,start.lerp(end,.60)+inward),edge)
                    stats['crystal_returns']+=1
            else:
                normals=[mesh.corner_normals[i].vector.copy() for i in tri.loops]
                colour=(.74,.79,.87,1) if role in ['pearl','ice'] else (1,1,1,1)
                surface.triangle(verts,mat,[colour]*3,normals)
        objects=[surface.object(asset)]
        if details.faces:objects.append(details.object(asset))
        asset.replace_mesh(index,objects)
        stats['triangles']+=len(surface.faces)+len(details.faces)
    return stats


def render_preview(asset,asset_id):
    OUTPUT.mkdir(parents=True,exist_ok=True)
    collection=asset.save_blend(OUTPUT/(asset_id+'.blend'))
    meshes=[o for o in collection.objects if o.type=='MESH']
    conversion=Matrix.Rotation(math.pi/2,4,'X')
    for obj in meshes:obj.matrix_world=conversion@obj.matrix_world
    bpy.context.view_layer.update()
    corners=[obj.matrix_world@Vector(c) for obj in meshes for c in obj.bound_box]
    lo=Vector([min(v[i] for v in corners) for i in range(3)])
    hi=Vector([max(v[i] for v in corners) for i in range(3)])
    center=(lo+hi)*.5;span=max(hi-lo)
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True
    scene.render.resolution_x=1152;scene.render.resolution_y=1008;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
    world=bpy.data.worlds.new('VEKTOR reference charcoal');scene.world=world;world.use_nodes=True
    world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.025,.025,.025,1)
    world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.50
    for name,delta,power,colour,size in [
        ('Neutral top key',(-.7,-1.0,1.8),1250,(1,1,1),1.5),
        ('Neutral edge',(1.0,1.0,.5),1050,(1,1,1),1.2),
        ('Neutral top fill',(-1.4,1.0,1.2),750,(1,1,1),1.0),
        ('Neutral underside key',(-.7,-1.0,-1.8),1250,(1,1,1),1.5),
        ('Neutral underside fill',(-1.4,1.0,-1.2),750,(1,1,1),1.0),
    ]:
        light=bpy.data.lights.new(name,'AREA');light.energy=power*span*span*.025;light.shape='DISK';light.size=span*size;light.color=colour
        obj=bpy.data.objects.new(name,light);scene.collection.objects.link(obj);obj.location=center+Vector(delta)*span
        obj.rotation_euler=(center-obj.location).to_track_quat('-Z','Y').to_euler()
    camera=bpy.data.cameras.new('VEKTOR concept camera');obj=bpy.data.objects.new('VEKTOR concept camera',camera);scene.collection.objects.link(obj)
    # The diagonal, nose-forward camera follows the illustrated concept view.
    obj.location=center+Vector((-.85,1.4,1.25))*span
    preview_margin=1.27 if asset_id=='04_kreuzer' else 1.10
    obj.rotation_euler=(center-obj.location).to_track_quat('-Z','Y').to_euler();camera.type='ORTHO';camera.ortho_scale=span*preview_margin;scene.camera=obj
    scene.use_nodes=True;tree=scene.node_tree;tree.nodes.clear()
    layers=tree.nodes.new('CompositorNodeRLayers');glow=tree.nodes.new('CompositorNodeGlare');glow.glare_type='FOG_GLOW';glow.quality='HIGH';glow.threshold=1.8
    composite=tree.nodes.new('CompositorNodeComposite');tree.links.new(layers.outputs['Image'],glow.inputs['Image']);tree.links.new(glow.outputs['Image'],composite.inputs['Image'])
    scene.render.image_settings.file_format='PNG';scene.render.filepath=str(OUTPUT/(asset_id+'.png'))
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT/(asset_id+'.blend')))
    views=[('top',(-.85,1.4,1.25)),('bottom',(-.85,1.4,-1.25)),('side',(-1.6,.6,.12))]
    if asset_id in MILITARY_IDS:
        views += [('plan',(0,0,2.5))]
    elif asset_id not in ['07_arbeiter','08_forschung','02_sternenbasis']:views=views[:1]
    for view,direction in views:
        camera.ortho_scale=span*(1.30 if view=='plan' else preview_margin)
        obj.location=center+Vector(direction)*span
        obj.rotation_euler=(center-obj.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(OUTPUT/(asset_id+'_'+view+'.png'))
        bpy.ops.render.render(write_still=True)
    if asset_id=='02_mining_ring':
        # Inspect the pose with least shaft/socket overlap as well as rest.
        nodes=asset.document['nodes']
        operate=next(c for c in asset.document.get('animations',[]) if c['name']=='Operate')
        for channel in operate['channels']:
            idx=channel['target']['node'];node=nodes[idx]
            if not node.get('name','').startswith('extractor_') or channel['target']['path']!='translation':continue
            samples=asset.accessor(operate['samplers'][channel['sampler']]['output'])
            base=Vector(node['translation']);radial=Vector((base.x,0,base.z)).normalized()
            least=min((Vector(p) for p in samples),key=lambda p:p.dot(radial))
            delta=conversion.to_3x3()@(least-base)
            descendants=[idx]
            for current in descendants:descendants.extend(nodes[current].get('children',[]))
            for current in descendants:
                prefix=nodes[current].get('name','')+' / '
                for part in collection.objects:
                    if part.name.startswith(prefix):part.location+=delta
        scene.render.filepath=str(OUTPUT/(asset_id+'_operate_retracted.png'))
        bpy.ops.render.render(write_still=True)


def render_military_overview():
    """Equal maximum span, true orthographic plan views under neutral light."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene;scene.render.engine='CYCLES'
    scene.cycles.samples=40;scene.cycles.use_denoising=True
    scene.render.resolution_x=1800;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
    world=bpy.data.worlds.new('Class comparison charcoal');scene.world=world;world.use_nodes=True
    world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.020,.022,.027,1)
    world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.50
    labels=['KORVETTE','FREGATTE','ZERSTOERER','KREUZER','SCHLACHTSCHIFF','TITAN']
    ink=bpy.data.materials.new('Quiet white labels');ink.use_nodes=True
    bsdf=ink.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(.7,.76,.85,1)
    bsdf.inputs['Emission Color'].default_value=(.7,.76,.85,1);bsdf.inputs['Emission Strength'].default_value=.8
    for index,model in enumerate(MILITARY_IDS):
        with bpy.data.libraries.load(str(OUTPUT/(model+'.blend')),link=False) as (source,target):
            target.collections=['Concept assembly']
        collection=target.collections[0];scene.collection.children.link(collection)
        meshes=[obj for obj in collection.objects if obj.type=='MESH']
        bpy.context.view_layer.update()
        corners=[obj.matrix_world@Vector(c) for obj in meshes for c in obj.bound_box]
        lo=Vector([min(v[i] for v in corners) for i in range(3)])
        hi=Vector([max(v[i] for v in corners) for i in range(3)])
        center=(lo+hi)*.5;scale=9.0/max(hi-lo)
        cell=Vector(((index%3-1)*14,7 if index<3 else -7,0))
        transform=Matrix.Translation(cell)@Matrix.Scale(scale,4)@Matrix.Translation(-center)
        for obj in meshes:obj.matrix_world=transform@obj.matrix_world
        curve=bpy.data.curves.new(labels[index],'FONT');curve.body=labels[index];curve.size=.48;curve.align_x='CENTER'
        label=bpy.data.objects.new(labels[index],curve);scene.collection.objects.link(label)
        label.location=cell+Vector((0,-5.45,0));curve.materials.append(ink)
        for name,delta,power,size in [('Key',(-4,-5,12),1600,11),('Edge',(5,5,6),1200,9),('Fill',(-7,4,8),850,9)]:
            light=bpy.data.lights.new(model+' '+name,'AREA');light.energy=power;light.shape='DISK';light.size=size
            obj=bpy.data.objects.new(light.name,light);scene.collection.objects.link(obj);obj.location=cell+Vector(delta)
            obj.rotation_euler=(cell-obj.location).to_track_quat('-Z','Y').to_euler()
    camera=bpy.data.cameras.new('Class comparison plan');obj=bpy.data.objects.new(camera.name,camera);scene.collection.objects.link(obj)
    obj.location=(0,0,50);obj.rotation_euler=(0,0,0);camera.type='ORTHO';camera.ortho_scale=43;scene.camera=obj
    scene.render.image_settings.file_format='PNG';scene.render.filepath=str(OUTPUT/'military-overview.png')
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT/'military-overview.blend'))
    bpy.ops.render.render(write_still=True)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--only');parser.add_argument('--render',action='store_true')
    parser.add_argument('--military',action='store_true',help='Rebuild only the six military ships, leaving all other assets untouched.')
    parser.add_argument('--overview',action='store_true',help='Render the six saved military Blender assemblies in a 3x2 plan comparison.')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    report=[]
    for model in asset_ids('vektor'):
        if args.only and model!=args.only:continue
        if args.military and model not in MILITARY_IDS:continue
        asset=ConceptAsset('vektor',model);reference=ReferencePearl();roles,edge,filament=finishes(asset)
        stats=author(asset,reference,roles,edge,filament);asset.write()
        stats.update(model=model,bytes=asset.path.stat().st_size,clips=len(asset.original_animations))
        if model in MILITARY_IDS:stats.update(profile=military_profile(model)['name'],profile_rows=len(military_profile(model)['rows']))
        report.append(stats);print(json.dumps(stats),flush=True)
        if args.render and model in MILITARY_IDS+['07_arbeiter','08_forschung','02_sternenbasis','02_mining_ring','04_mega_shipyard','orbital_ring']:
            render_preview(asset,model)
    OUTPUT.mkdir(parents=True,exist_ok=True)
    name='report-'+args.only+'.json' if args.only else ('report-military.json' if args.military else 'report.json')
    (OUTPUT/name).write_text(json.dumps(report,indent=2)+'\n')
    if args.overview:render_military_overview()


if __name__=='__main__':main()
