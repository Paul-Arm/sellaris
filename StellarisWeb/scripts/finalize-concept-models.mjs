import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir, rename, rm, truncate } from 'node:fs/promises';
import { Box3, Vector3 } from 'three';
import { createNodeModelLoader } from './node-model-loader.mjs';

// Remove superseded Blender mesh buffers, preserving animation values and node
// transforms. Accessor numbers may change; animation channels and samples may not.
const sets = process.argv.slice(2);
const catalog = JSON.parse(await readFile('src/assets/model-catalog.json', 'utf8'));
const loader = createNodeModelLoader();
const reports = [];
function decode(bytes) {
  const size = bytes.readUInt32LE(12);
  return { json: JSON.parse(bytes.toString('utf8', 20, 20 + size)), bin: bytes.subarray(28 + size) };
}
function accessorBytes(document, bin, index) {
  const a = document.accessors[index];
  const v = document.bufferViews[a.bufferView];
  const width = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 }[a.type];
  const itemSize = width * { 5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4 }[a.componentType];
  const start = (v.byteOffset ?? 0) + (a.byteOffset ?? 0);
  const bytes = [];
  for (let i = 0; i < a.count; i++) {
    const offset = start + i * (v.byteStride ?? itemSize);
    bytes.push(bin.subarray(offset, offset + itemSize));
  }
  return Buffer.concat(bytes);
}
function animationSignature(json, bin) {
  return (json.animations ?? []).map((animation) => ({
    ...animation,
    samplers: animation.samplers.map((s) => ({
      ...s,
      input: accessorBytes(json, bin, s.input).toString('base64'),
      output: accessorBytes(json, bin, s.output).toString('base64'),
    })),
  }));
}
function compact(source) {
  const document = structuredClone(source.json);
  const accessors = new Set();
  function references(visit) {
    for (const mesh of document.meshes ?? [])
      for (const p of mesh.primitives) {
        assert(!p.extensions?.KHR_draco_mesh_compression, 'compressed primitives need a separate path');
        for (const key of Object.keys(p.attributes)) p.attributes[key] = visit(p.attributes[key]);
        if (p.indices !== undefined) p.indices = visit(p.indices);
        for (const target of p.targets ?? [])
          for (const key of Object.keys(target)) target[key] = visit(target[key]);
      }
    for (const animation of document.animations ?? [])
      for (const s of animation.samplers) {
        s.input = visit(s.input);
        s.output = visit(s.output);
      }
    for (const skin of document.skins ?? [])
      if (skin.inverseBindMatrices !== undefined) skin.inverseBindMatrices = visit(skin.inverseBindMatrices);
  }
  references((i) => {
    accessors.add(i);
    return i;
  });
  const indices = [...accessors].sort((a, b) => a - b);
  const lookup = new Map(indices.map((value, index) => [value, index]));
  references((i) => lookup.get(i));
  document.accessors = indices.map((i) => document.accessors[i]);
  const views = new Set();
  function viewReferences(visit) {
    for (const a of document.accessors) {
      if (a.bufferView !== undefined) a.bufferView = visit(a.bufferView);
      if (a.sparse) {
        a.sparse.indices.bufferView = visit(a.sparse.indices.bufferView);
        a.sparse.values.bufferView = visit(a.sparse.values.bufferView);
      }
    }
    for (const image of document.images ?? [])
      if (image.bufferView !== undefined) image.bufferView = visit(image.bufferView);
  }
  viewReferences((i) => {
    views.add(i);
    return i;
  });
  const viewIndices = [...views].sort((a, b) => a - b);
  const viewLookup = new Map(viewIndices.map((value, index) => [value, index]));
  const chunks = [];
  let byteLength = 0;
  document.bufferViews = viewIndices.map((i) => {
    const view = document.bufferViews[i];
    assert.equal(view.buffer ?? 0, 0);
    const pad = (4 - (byteLength % 4)) % 4;
    if (pad) {
      chunks.push(Buffer.alloc(pad));
      byteLength += pad;
    }
    const offset = byteLength;
    const chunk = source.bin.subarray(view.byteOffset ?? 0, (view.byteOffset ?? 0) + view.byteLength);
    assert.equal(chunk.length, view.byteLength);
    chunks.push(chunk);
    byteLength += chunk.length;
    return { ...view, buffer: 0, byteOffset: offset };
  });
  viewReferences((i) => viewLookup.get(i));
  const bin = Buffer.concat(chunks);
  document.buffers = [{ byteLength: bin.length }];
  assert.deepEqual(document.nodes, source.json.nodes);
  assert.deepEqual(animationSignature(document, bin), animationSignature(source.json, source.bin));
  const json = Buffer.from(JSON.stringify(document));
  const jsonPadding = Buffer.alloc((4 - (json.length % 4)) % 4, 0x20);
  const binPadding = Buffer.alloc((4 - (bin.length % 4)) % 4);
  const header = Buffer.alloc(20),
    binHeader = Buffer.alloc(8);
  header.writeUInt32LE(0x46546c67, 0);
  header.writeUInt32LE(2, 4);
  header.writeUInt32LE(28 + json.length + jsonPadding.length + bin.length + binPadding.length, 8);
  header.writeUInt32LE(json.length + jsonPadding.length, 12);
  header.writeUInt32LE(0x4e4f534a, 16);
  binHeader.writeUInt32LE(bin.length + binPadding.length, 0);
  binHeader.writeUInt32LE(0x004e4942, 4);
  return Buffer.concat([header, json, jsonPadding, binHeader, bin, binPadding]);
}
for (const asset of catalog) {
  if (sets.length && !sets.includes(asset.set)) continue;
  const path = `public${asset.url}`;
  const original = await readFile(path);
  const source = decode(original);
  assert(source.json.extras?.conceptRefit, `${asset.url} has not been authored yet`);
  const baseline = decode(await readFile(`artifacts/concept-refit/base/${asset.set}/${asset.id}.glb`));
  assert.deepEqual(source.json.nodes, baseline.json.nodes, `${asset.url}: original nodes`);
  assert.deepEqual(
    animationSignature(source.json, source.bin),
    animationSignature(baseline.json, baseline.bin),
    `${asset.url}: original animation samples`,
  );
  const bytes = compact(source);
  const gltf = await loader.parseAsync(
    bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength),
    '',
  );
  const size = new Box3().setFromObject(gltf.scene).getSize(new Vector3()).toArray();
  assert(size.every((v) => Number.isFinite(v) && v > 0));
  let vertices = 0,
    triangles = 0;
  gltf.scene.traverse((node) => {
    if (!node.isMesh) return;
    const p = node.geometry.attributes.position,
      n = node.geometry.attributes.normal;
    vertices += p.count;
    triangles += (node.geometry.index?.count ?? p.count) / 3;
    for (let i = 0; i < p.count; i++) {
      assert(Number.isFinite(p.getX(i) + p.getY(i) + p.getZ(i)), `${path}: nonfinite position`);
      const length = Math.hypot(n.getX(i), n.getY(i), n.getZ(i));
      assert(Math.abs(length - 1) < 0.01, `${path}: invalid normal ${length}`);
    }
    for (const index of node.geometry.index?.array ?? []) assert(index < p.count, `${path}: invalid index`);
    for (const color of node.geometry.attributes.color?.array ?? [])
      assert(Number.isFinite(color) && color >= 0 && color <= 1, `${path}: invalid concept color`);
    const materials = Array.isArray(node.material) ? node.material : [node.material];
    for (const material of materials) {
      assert(material.userData.conceptAuthored, `${path}: untagged material`);
      if (material.map || material.emissiveMap) {
        const uv = node.geometry.attributes.uv;
        assert(uv && uv.count === p.count, `${path}: missing baked texture coordinates`);
        for (const value of uv.array) assert(Number.isFinite(value), `${path}: invalid UV`);
      }
    }
  });
  for (const clip of gltf.animations) assert(clip.validate() && clip.duration > 0);
  const staging = `${path}.tmp`;
  try {
    await writeFile(staging, bytes);
    try {
      await rename(staging, path);
    } catch (error) {
      if (process.platform !== 'win32' || error.code !== 'EPERM') throw error;
      // A live Windows reader can allow writes while denying replacement. The
      // complete candidate is validated above and the original is held in RAM.
      // Write without early truncation, then trim; restore on any failure.
      try {
        await writeFile(path, bytes, { flag: 'r+' });
        await truncate(path, bytes.length);
        assert((await readFile(path)).equals(bytes), `${path}: replacement verification`);
      } catch (writeError) {
        await writeFile(path, original, { flag: 'r+' });
        await truncate(path, original.length);
        throw writeError;
      }
    }
  } finally {
    await rm(staging, { force: true });
  }
  asset.bytes = bytes.length;
  asset.size = size;
  asset.clips = gltf.animations.map((c) => ({ name: c.name, duration: c.duration }));
  reports.push({
    set: asset.set,
    id: asset.id,
    before: original.length,
    bytes: bytes.length,
    vertices,
    triangles,
    clips: asset.clips.length,
    preservedNodesAndAnimationSamples: true,
  });
}
await writeFile('src/assets/model-catalog.json', JSON.stringify(catalog, null, 2) + '\n');
await mkdir('artifacts/concept-refit', { recursive: true });
const report = {
  models: reports.length,
  bytes: reports.reduce((n, a) => n + a.bytes, 0),
  removedBytes: reports.reduce((n, a) => n + a.before - a.bytes, 0),
  clips: reports.reduce((n, a) => n + a.clips, 0),
  assets: reports,
};
await writeFile(
  `artifacts/concept-refit/final-validation${sets.length ? '-' + sets.join('-') : ''}.json`,
  JSON.stringify(report, null, 2) + '\n',
);
console.log(JSON.stringify({ ...report, assets: undefined }, null, 2));
