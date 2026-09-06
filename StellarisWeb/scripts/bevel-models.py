"""Blender 4.5: bake narrow bevels and weighted normals into the runtime GLBs.

Run from the repository root:
  blender --background --factory-startup --python scripts/bevel-models.py -- [--only prisma/01_korvette]

Only mesh primitives are replaced. Original nodes, transforms, markers, animation
accessors and clips remain byte-for-byte intact. The first run saves originals in
artifacts/model-import/surface-originals; subsequent runs always start from those.
"""
import argparse
import bmesh
import bpy
import json
import math
from pathlib import Path
import shutil
import struct
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--only')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
root = Path.cwd()
catalog_path = root / 'src/assets/model-catalog.json'
catalog = json.loads(catalog_path.read_text())
report = []

def process(asset):
    relative = Path(asset['set']) / (asset['id'] + '.glb')
    output = root / 'public/models' / relative
    original = root / 'artifacts/model-import/surface-originals' / relative
    original.parent.mkdir(parents=True, exist_ok=True)
    if not original.exists():
        shutil.copy2(output, original)
    data = original.read_bytes()
    json_length = struct.unpack_from('<I', data, 12)[0]
    document = json.loads(data[20:20 + json_length])
    binary_start = 20 + json_length + 8
    binary = bytearray(data[binary_start:])

    def accessor(index):
        a = document['accessors'][index]
        view = document['bufferViews'][a['bufferView']]
        offset = view.get('byteOffset', 0) + a.get('byteOffset', 0)
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
        code = {5121: 'B', 5123: 'H', 5125: 'I', 5126: 'f'}[a['componentType']]
        fmt = '<' + code * width
        stride = view.get('byteStride', struct.calcsize(fmt))
        return [struct.unpack_from(fmt, binary, offset + n * stride) for n in range(a['count'])]

    def append(values, kind='VEC3'):
        while len(binary) % 4:
            binary.append(0)
        start = len(binary)
        indices = kind == 'SCALAR'
        binary.extend(struct.pack('<' + ('I' if indices else 'f') * len(values), *values))
        document['bufferViews'].append({'buffer': 0, 'byteOffset': start, 'byteLength': len(binary)-start, 'target': 34963 if indices else 34962})
        width = 1 if indices else 3
        document['accessors'].append({
            'bufferView': len(document['bufferViews'])-1,
            'componentType': 5125 if indices else 5126, 'count': len(values)//width, 'type': kind,
            'min': [min(values[i::width]) for i in range(width)],
            'max': [max(values[i::width]) for i in range(width)],
        })
        return len(document['accessors'])-1

    def is_energy(material):
        return material.get('extensions', {}).get('KHR_materials_emissive_strength', {}).get('emissiveStrength', 0) >= 2 or material.get('alphaMode') == 'BLEND'

    changed = 0
    triangles_before = triangles_after = 0
    for source in document['meshes']:
        primitives = source['primitives']
        if all(is_energy(document['materials'][p['material']]) for p in primitives):
            continue
        vertices, faces, material_indices = [], [], []
        for p in primitives:
            assert p.get('mode', 4) == 4 and not p.get('targets'), 'Only rigid triangle meshes are supported'
            positions = accessor(p['attributes']['POSITION'])
            indices = [i[0] for i in accessor(p['indices'])] if 'indices' in p else list(range(len(positions)))
            offset = len(vertices)
            vertices.extend(positions)
            faces.extend(tuple(offset + i for i in indices[n:n+3]) for n in range(0,len(indices),3))
            material_indices.extend([p['material']] * (len(indices)//3))
        mesh = bpy.data.meshes.new('surface')
        mesh.from_pydata(vertices, [], faces)
        mesh.update()
        obj = bpy.data.objects.new('surface', mesh)
        bpy.context.collection.objects.link(obj)
        for m in document['materials']:
            mesh.materials.append(bpy.data.materials.get(m['name']) or bpy.data.materials.new(m['name']))
        for face, index in zip(mesh.polygons, material_indices):
            face.material_index = index
            face.use_smooth = True
        bm = bmesh.new()
        bm.from_mesh(mesh)
        span = max(max(v[i] for v in vertices)-min(v[i] for v in vertices) for i in range(3))
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=max(span*1e-7, 1e-8))
        bm.to_mesh(mesh)
        bm.free()
        mesh.set_sharp_from_angle(angle=math.radians(36))
        bevel = obj.modifiers.new('Machined edges', 'BEVEL')
        bevel.width = span * (0.0012 if asset['set'] == 'vektor' else 0.0025)
        bevel.segments = 2
        bevel.limit_method = 'ANGLE'
        bevel.angle_limit = math.radians(28)
        bevel.use_clamp_overlap = True
        bevel.harden_normals = True
        weighted = obj.modifiers.new('Face weighted normals', 'WEIGHTED_NORMAL')
        weighted.keep_sharp = True
        weighted.weight = 50
        evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        result = evaluated.to_mesh()
        result.calc_loop_triangles()
        groups = {}
        for triangle in result.loop_triangles:
            pos, norm = groups.setdefault(triangle.material_index, ([], []))
            for vertex, loop in zip(triangle.vertices, triangle.loops):
                pos.extend(result.vertices[vertex].co)
                norm.extend(result.corner_normals[loop].vector)
        source['primitives'] = []
        for index, (pos, norm) in groups.items():
            lookup, compact_pos, compact_norm, indices = {}, [], [], []
            for i in range(0, len(pos), 3):
                key = tuple(pos[i:i+3] + norm[i:i+3])
                if key not in lookup:
                    lookup[key] = len(compact_pos)//3
                    compact_pos.extend(pos[i:i+3])
                    compact_norm.extend(norm[i:i+3])
                indices.append(lookup[key])
            source['primitives'].append({
                'attributes': {'POSITION': append(compact_pos), 'NORMAL': append(compact_norm)},
                'indices': append(indices, 'SCALAR'), 'material': index, 'mode': 4,
            })
        source.setdefault('extras', {})['surface_finish'] = 'bevel-weighted-normals-v1'
        triangles_before += len(faces)
        triangles_after += len(result.loop_triangles)
        changed += 1
        evaluated.to_mesh_clear()
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(mesh)
    document['buffers'][0]['byteLength'] = len(binary)
    encoded = json.dumps(document, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    binary.extend(b'\0' * (-len(binary) % 4))
    result = struct.pack('<III', 0x46546c67, 2, 28 + len(encoded) + len(binary))
    result += struct.pack('<II', len(encoded), 0x4e4f534a) + encoded
    result += struct.pack('<II', len(binary), 0x004e4942) + binary
    output.write_bytes(result)
    asset['bytes'] = len(result)
    entry = {'model': str(relative), 'meshes': changed, 'triangles_before': triangles_before, 'triangles_after': triangles_after, 'bytes': len(result)}
    print(json.dumps(entry), flush=True)
    report.append(entry)

for asset in catalog:
    if not args.only or f"{asset['set']}/{asset['id']}" == args.only:
        process(asset)
catalog_path.write_text(json.dumps(catalog, indent=2)+'\n')
(root / 'artifacts/model-import/bevel-report.json').write_text(json.dumps(report, indent=2)+'\n')
