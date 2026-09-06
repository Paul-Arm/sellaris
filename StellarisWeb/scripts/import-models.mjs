import { readdir, readFile, mkdir, copyFile, writeFile } from 'node:fs/promises';
import { resolve, join, basename } from 'node:path';
import { Box3, Vector3 } from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';

// Import extracted, user-provided model packages. Never execute their generators.
const roots = process.argv.slice(2);
if (!roots.length) throw new Error('Usage: node scripts/import-models.mjs <extracted-package> [...]');
const sets = ['prisma', 'aureole', 'bastion', 'parallax', 'nexus', 'vektor'];
const output = resolve('public/models');
const catalogPath = resolve('src/assets/model-catalog.json');
const catalog = new Map();
const loader = new GLTFLoader();
async function walk(path) {
  const files = [];
  for (const e of await readdir(path, { withFileTypes: true })) {
    if (e.isDirectory()) files.push(...(await walk(join(path, e.name))));
    else if (e.name.endsWith('.glb')) files.push(join(path, e.name));
  }
  return files;
}
for (const root of roots) {
  for (const file of await walk(resolve(root))) {
    const set = sets.find((s) =>
      basename(file)
        .toLowerCase()
        .startsWith(s + '_'),
    );
    if (!set) throw new Error(`Unknown set: ${file}`);
    const bytes = await readFile(file);
    const gltf = await loader.parseAsync(
      bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength),
      '',
    );
    const id = basename(file, '.glb')
      .slice(set.length + 1)
      .replace(/_animated$/, '');
    const bounds = new Box3().setFromObject(gltf.scene);
    const size = bounds.getSize(new Vector3()).toArray();
    let planetRadius;
    const center = new Vector3();
    gltf.scene.traverse((node) => {
      if (node.name.endsWith('planet_center')) node.getWorldPosition(center);
    });
    gltf.scene.traverse((node) => {
      if (node.name.endsWith('planet_surface_reference'))
        planetRadius = node.getWorldPosition(new Vector3()).distanceTo(center);
    });
    const url = `/models/${set}/${id}.glb`;
    await mkdir(join(output, set), { recursive: true });
    await copyFile(file, join(output, set, id + '.glb'));
    catalog.set(`${set}/${id}`, {
      set,
      id,
      url,
      bytes: bytes.length,
      size,
      planetRadius,
      clips: gltf.animations.map((c) => ({ name: c.name, duration: c.duration })),
    });
    gltf.scene.traverse((node) => {
      if (node.isMesh) {
        node.geometry.dispose();
        for (const m of Array.isArray(node.material) ? node.material : [node.material]) m.dispose();
      }
    });
  }
}
await mkdir(resolve('src/assets'), { recursive: true });
await writeFile(
  catalogPath,
  JSON.stringify(
    [...catalog.values()].sort((a, b) => a.set.localeCompare(b.set) || a.id.localeCompare(b.id)),
    null,
    2,
  ) + '\n',
);
console.log(`Imported ${catalog.size} GLBs into public/models; catalog: ${catalogPath}`);
