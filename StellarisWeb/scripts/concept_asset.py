"""Blender-only, animation-preserving GLB mesh authoring helpers.

All geometry stays in glTF coordinates: +Y up, -Z forward. Set scripts own a
single public/models/<set> directory. Catalog updates belong to the coordinator.
"""
import bpy
import copy
import json
from pathlib import Path
import shutil
import struct
from mathutils import Matrix, Vector, Quaternion

ROOT = Path(__file__).resolve().parent.parent


class ConceptAsset:
    def __init__(self, ship_set, asset_id, source=None):
        self.ship_set, self.asset_id = ship_set, asset_id
        self.path = ROOT / 'public/models' / ship_set / (asset_id + '.glb')
        baseline = ROOT / 'artifacts/concept-refit/base' / ship_set / (asset_id + '.glb')
        baseline.parent.mkdir(parents=True, exist_ok=True)
        if not baseline.exists():
            shutil.copy2(self.path, baseline)
        data = Path(source).read_bytes() if source is not None else baseline.read_bytes()
        length = struct.unpack_from('<I', data, 12)[0]
        self.document = json.loads(data[20:20+length])
        self.binary = bytearray(data[28+length:])
        self.original_nodes = copy.deepcopy(self.document['nodes'])
        self.original_animations = copy.deepcopy(self.document.get('animations', []))
        bpy.ops.wm.read_factory_settings(use_empty=True)
        self.materials = []
        self.mesh_objects = {}
        self._parts = {}
        self._texture_images = {}
        for i, material in enumerate(self.document.get('materials', [])):
            name = material.get('name', f'Material_{i}')
            mat = bpy.data.materials.new(name)
            mat.use_nodes = True
            self.materials.append(mat)
            energy = material.get('extensions', {}).get('KHR_materials_emissive_strength', {}).get('emissiveStrength', 0) >= 2
            extras = material.setdefault('extras', {})
            extras['conceptAuthored'] = True
            extras.setdefault('conceptRole', 'energy' if energy else 'structure' if 'structure' in name.lower() else 'hull')
            self._sync_material(i)
        for i, source in enumerate(self.document['meshes']):
            vertices, faces, normals, material_indices, uvs, colors = [], [], [], [], [], []
            has_uv = has_color = False
            for primitive in source['primitives']:
                positions = self.accessor(primitive['attributes']['POSITION'])
                source_normals = self.accessor(primitive['attributes']['NORMAL']) if 'NORMAL' in primitive['attributes'] else [(0,1,0)] * len(positions)
                indices = [v[0] for v in self.accessor(primitive['indices'])] if 'indices' in primitive else list(range(len(positions)))
                offset = len(vertices)
                vertices.extend(positions)
                normals.extend(source_normals)
                faces.extend(tuple(offset+j for j in indices[k:k+3]) for k in range(0,len(indices),3))
                material_indices.extend([primitive.get('material', 0)] * (len(indices)//3))
                has_uv |= 'TEXCOORD_0' in primitive['attributes']
                has_color |= 'COLOR_0' in primitive['attributes']
                uvs.extend(self.accessor(primitive['attributes']['TEXCOORD_0']) if 'TEXCOORD_0' in primitive['attributes'] else [(0,0)]*len(positions))
                colors.extend(self.accessor(primitive['attributes']['COLOR_0']) if 'COLOR_0' in primitive['attributes'] else [(1,1,1,1)]*len(positions))
            mesh = bpy.data.meshes.new(source.get('name', f'Mesh_{i}'))
            mesh.from_pydata(vertices, [], faces)
            mesh.materials.clear()
            for mat in self.materials:
                mesh.materials.append(mat)
            for polygon, mat_index in zip(mesh.polygons, material_indices):
                polygon.material_index = mat_index
                polygon.use_smooth = True
            mesh.validate(clean_customdata=False)
            mesh.update(calc_edges=True)
            mesh.normals_split_custom_set([normals[loop.vertex_index] for loop in mesh.loops])
            if has_uv:
                layer = mesh.uv_layers.new(name='UVMap')
                for loop in mesh.loops:
                    u, v = uvs[loop.vertex_index]
                    layer.data[loop.index].uv = (u, 1-v)
            if has_color:
                layer = mesh.color_attributes.new(name='ConceptColor', type='FLOAT_COLOR', domain='POINT')
                for k, value in enumerate(colors):
                    layer.data[k].color = tuple(value) if len(value)==4 else (*value,1)
            obj = bpy.data.objects.new(source.get('name', f'Mesh_{i}'), mesh)
            obj['gltf_mesh_index'] = i
            bpy.context.collection.objects.link(obj)
            self.mesh_objects[i] = obj
            self._parts[i] = [obj]

    def embed_png_texture(self, path, name=None, repeat=False):
        """Embed a standard Blender RGB/RGBA 8-bit PNG, with no external URLs.

        Assign ordinary Blender UV coordinates; write() flips V for glTF.
        The same image node is used for Blender previews and the GLB texture.
        """
        path = Path(path)
        data = path.read_bytes()
        assert data[:8] == b'\x89PNG\r\n\x1a\n', 'Expected PNG'
        width, height, depth, colour = struct.unpack_from('>IIBB', data, 16)
        assert depth == 8 and colour in (2, 6), 'Use 8-bit RGB or RGBA PNG'
        assert 0 < width <= 2048 and 0 < height <= 2048, 'Texture exceeds 2048 pixels'
        while len(self.binary)%4: self.binary.append(0)
        start = len(self.binary); self.binary.extend(data)
        views = self.document.setdefault('bufferViews', [])
        views.append({'buffer':0, 'byteOffset':start, 'byteLength':len(data)})
        images = self.document.setdefault('images', [])
        images.append({'bufferView':len(views)-1, 'mimeType':'image/png', 'name':name or path.stem})
        samplers = self.document.setdefault('samplers', [])
        sampler = {'magFilter':9729, 'minFilter':9987, 'wrapS':10497 if repeat else 33071, 'wrapT':10497 if repeat else 33071}
        if sampler not in samplers: samplers.append(sampler)
        textures = self.document.setdefault('textures', [])
        textures.append({'source':len(images)-1, 'sampler':samplers.index(sampler), 'name':name or path.stem})
        index = len(textures)-1
        image = bpy.data.images.load(str(path), check_existing=True)
        image.colorspace_settings.name = 'sRGB'
        image.pack()
        self._texture_images[index] = image
        return index

    def set_material_texture(self, material, texture, base_color=True, emissive=False):
        """Use one embedded image for base colour and/or authored emission."""
        index = self._material_index(material)
        source = self.document['materials'][index]
        if base_color: source.setdefault('pbrMetallicRoughness', {})['baseColorTexture'] = {'index':texture}
        if emissive: source['emissiveTexture'] = {'index':texture}
        nodes = self.materials[index].node_tree.nodes
        shader = nodes.get('Principled BSDF')
        node = nodes.new('ShaderNodeTexImage'); node.image = self._texture_images[texture]
        node.interpolation = 'Linear'
        sampler = self.document['samplers'][self.document['textures'][texture]['sampler']]
        node.extension = 'REPEAT' if sampler['wrapS'] == 10497 else 'EXTEND'
        links = self.materials[index].node_tree.links
        for enabled, socket, factor in [
            (base_color, 'Base Color', source.get('pbrMetallicRoughness', {}).get('baseColorFactor',[1,1,1,1])),
            (emissive, 'Emission Color', source.get('emissiveFactor',[0,0,0])+[1]),
        ]:
            if not enabled: continue
            multiply = nodes.new('ShaderNodeMixRGB'); multiply.blend_type = 'MULTIPLY'
            multiply.inputs[0].default_value = 1
            multiply.inputs[2].default_value = factor
            links.new(node.outputs['Color'], multiply.inputs[1])
            links.new(multiply.outputs['Color'], shader.inputs[socket])
        if base_color and source.get('alphaMode') in ('BLEND', 'MASK'):
            alpha = nodes.new('ShaderNodeMath'); alpha.operation = 'MULTIPLY'
            alpha.inputs[1].default_value = source.get('pbrMetallicRoughness', {}).get('baseColorFactor',[1,1,1,1])[3]
            links.new(node.outputs['Alpha'], alpha.inputs[0])
            links.new(alpha.outputs[0], shader.inputs['Alpha'])
        source.setdefault('extras', {})['conceptBakedTexture'] = True
        return texture

    def accessor(self, index):
        a = self.document['accessors'][index]
        view = self.document['bufferViews'][a['bufferView']]
        offset = view.get('byteOffset', 0) + a.get('byteOffset', 0)
        width = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
        code = {5120:'b',5121:'B',5122:'h',5123:'H',5125:'I',5126:'f'}[a['componentType']]
        fmt = '<'+code*width
        stride = view.get('byteStride', struct.calcsize(fmt))
        values = [struct.unpack_from(fmt, self.binary, offset+n*stride) for n in range(a['count'])]
        if a.get('normalized') and a['componentType'] != 5126:
            maximum = {5120:127,5121:255,5122:32767,5123:65535}[a['componentType']]
            values = [tuple(max(-1,v/maximum) for v in row) for row in values]
        return values

    def _material_index(self, value):
        if isinstance(value, int):
            return value
        return next(i for i,m in enumerate(self.materials) if m.name == value)

    def _sync_material(self, index):
        source, mat = self.document['materials'][index], self.materials[index]
        pbr = source.get('pbrMetallicRoughness', {})
        color = pbr.get('baseColorFactor', [1,1,1,1])
        shader = mat.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Base Color'].default_value = color
        shader.inputs['Metallic'].default_value = pbr.get('metallicFactor', 1)
        shader.inputs['Roughness'].default_value = pbr.get('roughnessFactor', 1)
        shader.inputs['Alpha'].default_value = color[3]
        shader.inputs['Emission Color'].default_value = (*source.get('emissiveFactor', [0,0,0]),1)
        shader.inputs['Emission Strength'].default_value = source.get('extensions', {}).get('KHR_materials_emissive_strength', {}).get('emissiveStrength',1)
        coat = source.get('extensions', {}).get('KHR_materials_clearcoat', {})
        shader.inputs['Coat Weight'].default_value = coat.get('clearcoatFactor',0)
        shader.inputs['Coat Roughness'].default_value = coat.get('clearcoatRoughnessFactor',0.25)
        mat.diffuse_color = color
        mat['conceptRole'] = source.get('extras', {}).get('conceptRole','hull')

    def set_material(self, index_or_name, color=None, metal=None, rough=None, emission=None, strength=None, role=None, coat=None, **extra):
        index = self._material_index(index_or_name)
        material = self.document['materials'][index]
        pbr = material.setdefault('pbrMetallicRoughness', {})
        if color is not None:
            pbr['baseColorFactor'] = list(color) if len(color)==4 else [*color,1]
        if metal is not None: pbr['metallicFactor'] = metal
        if rough is not None: pbr['roughnessFactor'] = rough
        if emission is not None: material['emissiveFactor'] = list(emission)[:3]
        if strength is not None:
            material.setdefault('extensions', {})['KHR_materials_emissive_strength'] = {'emissiveStrength':strength}
        if coat is not None:
            material.setdefault('extensions', {})['KHR_materials_clearcoat'] = {'clearcoatFactor':coat,'clearcoatRoughnessFactor':0.25}
        material.setdefault('extras', {})['conceptAuthored'] = True
        if role is not None: material['extras']['conceptRole'] = role
        material['extras'].update(extra)
        self._sync_material(index)
        return index

    def add_material(self, name, **kwargs):
        index = len(self.materials)
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        self.materials.append(mat)
        self.document['materials'].append({'name':name, 'doubleSided':True, 'pbrMetallicRoughness':{'baseColorFactor':[1,1,1,1],'metallicFactor':0,'roughnessFactor':0.4}})
        for obj in self.mesh_objects.values(): obj.data.materials.append(mat)
        self.set_material(index, **kwargs)
        return index

    def replace_mesh(self, index, objects):
        self._parts[index] = list(objects) if isinstance(objects,(tuple,list)) else [objects]

    def append_geometry(self, index, objects):
        self._parts[index].extend(list(objects) if isinstance(objects,(tuple,list)) else [objects])

    def _append(self, values, width, integer=False):
        while len(self.binary)%4: self.binary.append(0)
        start = len(self.binary)
        self.binary.extend(struct.pack('<'+('I' if integer else 'f')*len(values),*values))
        self.document['bufferViews'].append({'buffer':0,'byteOffset':start,'byteLength':len(self.binary)-start,'target':34963 if integer else 34962})
        a = {'bufferView':len(self.document['bufferViews'])-1,'componentType':5125 if integer else 5126,'count':len(values)//width,'type':{1:'SCALAR',2:'VEC2',3:'VEC3',4:'VEC4'}[width]}
        if width==3:
            a['min'] = [min(values[i::width]) for i in range(width)]
            a['max'] = [max(values[i::width]) for i in range(width)]
        self.document['accessors'].append(a)
        return len(self.document['accessors'])-1

    def write(self, path=None):
        for mesh_index, objects in self._parts.items():
            groups = {}
            for obj in objects:
                evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
                mesh = evaluated.to_mesh()
                mesh.calc_loop_triangles()
                transform = obj.matrix_world.copy()
                normal_transform = transform.to_3x3().inverted_safe().transposed()
                uv_layer = mesh.uv_layers.active
                color_layer = mesh.color_attributes.active_color
                for triangle in mesh.loop_triangles:
                    local_index = triangle.material_index
                    mat = mesh.materials[local_index] if local_index < len(mesh.materials) else None
                    mat_index = self.materials.index(mat) if mat in self.materials else min(local_index,len(self.materials)-1)
                    has_uv, has_color = bool(uv_layer), bool(color_layer)
                    group = groups.setdefault((mat_index,has_uv,has_color), {'pos':[],'normal':[],'uv':[],'color':[],'indices':[],'lookup':{}})
                    for vertex_index, loop_index in zip(triangle.vertices, triangle.loops):
                        pos = tuple(transform @ mesh.vertices[vertex_index].co)
                        normal = normal_transform @ mesh.corner_normals[loop_index].vector
                        if normal.length_squared < 1e-12:
                            normal = normal_transform @ triangle.normal
                        if normal.length_squared < 1e-12:
                            normal = Vector((0, 1, 0))
                        norm = tuple(normal.normalized())
                        uv = (uv_layer.data[loop_index].uv.x, 1-uv_layer.data[loop_index].uv.y) if has_uv else ()
                        color = tuple(color_layer.data[loop_index if color_layer.domain=='CORNER' else vertex_index].color) if has_color else ()
                        key = (*pos,*norm,*uv,*color)
                        if key not in group['lookup']:
                            group['lookup'][key] = len(group['pos'])//3
                            group['pos'].extend(pos); group['normal'].extend(norm)
                            group['uv'].extend(uv); group['color'].extend(color)
                        group['indices'].append(group['lookup'][key])
                evaluated.to_mesh_clear()
            primitives = []
            for (mat_index,has_uv,has_color),group in groups.items():
                attributes = {'POSITION':self._append(group['pos'],3),'NORMAL':self._append(group['normal'],3)}
                if has_uv: attributes['TEXCOORD_0'] = self._append(group['uv'],2)
                if has_color: attributes['COLOR_0'] = self._append(group['color'],4)
                primitives.append({'attributes':attributes,'indices':self._append(group['indices'],1,True),'material':mat_index,'mode':4})
            self.document['meshes'][mesh_index]['primitives'] = primitives
        assert self.document['nodes'] == self.original_nodes
        assert self.document.get('animations',[]) == self.original_animations
        extensions = set(self.document.get('extensionsUsed',[]))
        for mat in self.document['materials']: extensions.update(mat.get('extensions',{}))
        self.document['extensionsUsed'] = sorted(extensions)
        self.document.setdefault('extras',{}).update(conceptRefit=True,conceptSet=self.ship_set)
        self.document['buffers'][0]['byteLength'] = len(self.binary)
        encoded = json.dumps(self.document,separators=(',',':')).encode()
        encoded += b' ' * (-len(encoded)%4)
        self.binary.extend(b'\0'*(-len(self.binary)%4))
        result = struct.pack('<III',0x46546c67,2,28+len(encoded)+len(self.binary))
        result += struct.pack('<II',len(encoded),0x4e4f534a)+encoded
        result += struct.pack('<II',len(self.binary),0x004e4942)+self.binary
        target = Path(path) if path else self.path
        target.parent.mkdir(parents=True,exist_ok=True)
        # A full disk must not truncate the last usable model.
        staging = target.with_name(target.name + '.tmp')
        try:
            staging.write_bytes(result)
            try:
                staging.replace(target)
            except PermissionError as error:
                if getattr(error, 'winerror', None) != 5 or not target.is_file():
                    raise
                # Windows readers may allow writes but deny file replacement.
                # Keep the old bytes for rollback and truncate only after the
                # complete already-built candidate has been written.
                previous = target.read_bytes()
                try:
                    with target.open('r+b') as output:
                        assert output.write(result) == len(result)
                        output.truncate()
                    assert target.read_bytes() == result
                except Exception:
                    target.write_bytes(previous)
                    raise
        finally:
            staging.unlink(missing_ok=True)
        print(f'CONCEPT {self.ship_set}/{self.asset_id}: {len(result)} bytes',flush=True)
        return target

    def save_blend(self, path):
        """Create assembly copies for preview without modifying the export objects."""
        collection = bpy.data.collections.new('Concept assembly')
        bpy.context.scene.collection.children.link(collection)
        nodes, parents = self.document['nodes'], {}
        for i,node in enumerate(nodes):
            for child in node.get('children',[]): parents[child]=i
        def matrix(i):
            n = nodes[i]
            if 'matrix' in n:
                local = Matrix([n['matrix'][j::4] for j in range(4)])
            else:
                q = n.get('rotation',[0,0,0,1])
                local = Matrix.LocRotScale(Vector(n.get('translation',[0,0,0])),Quaternion((q[3],q[0],q[1],q[2])),Vector(n.get('scale',[1,1,1])))
            return matrix(parents[i])@local if i in parents else local
        originals = set(self.mesh_objects.values()) | {obj for objects in self._parts.values() for obj in objects}
        for obj in originals: obj.hide_render=True; obj.hide_set(True)
        for i,node in enumerate(nodes):
            if 'mesh' not in node: continue
            for obj in self._parts[node['mesh']]:
                duplicate=obj.copy(); duplicate.data=obj.data
                duplicate.name=node.get('name',str(i))+' / '+obj.name
                collection.objects.link(duplicate)
                duplicate.matrix_world=matrix(i)@obj.matrix_world
                duplicate.hide_render=False; duplicate.hide_set(False)
        target = Path(path); target.parent.mkdir(parents=True,exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(target))
        return collection


def asset_ids(ship_set):
    return [p.stem for p in sorted((ROOT/'public/models'/ship_set).glob('*.glb'))]
