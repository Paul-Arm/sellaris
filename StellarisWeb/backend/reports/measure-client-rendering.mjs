// Run from StellarisWeb: node --import tsx backend/reports/measure-client-rendering.mjs
// Read-only model inspection and CPU microbenchmark. No server connection or GPU rendering.
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { cpus } from 'node:os';
import * as THREE from 'three';
import { createNodeModelLoader } from '../../scripts/node-model-loader.mjs';
import { MODEL_ASSETS, InstancedModel } from '../../src/model-assets.ts';

const root = new URL('../../', import.meta.url);
const loader = createNodeModelLoader();
const assets = MODEL_ASSETS.filter((a) => ['01_korvette', '07_arbeiter', '08_forschung'].includes(a.id));
const models = [];
const cpu = [];
for (const asset of assets) {
  const bytes = await readFile(new URL(`public${asset.url}`, root));
  const gltf = await loader.parseAsync(
    bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength),
    '',
  );
  const row = { set: asset.set, id: asset.id, meshParts: 0, drawsPerBatch: 0, trianglesPerInstance: 0 };
  gltf.scene.traverse((node) => {
    if (!(node instanceof THREE.Mesh)) return;
    row.meshParts++;
    row.drawsPerBatch += Array.isArray(node.material) ? node.geometry.groups.length : 1;
    row.trianglesPerInstance += (node.geometry.index?.count ?? node.geometry.attributes.position.count) / 3;
  });
  models.push(row);
  if (asset.id === '01_korvette' && ['prisma', 'nexus'].includes(asset.set)) {
    for (const count of [100, 1000, 3000]) {
      const batch = new InstancedModel({ load: async () => gltf }, asset, 25);
      await new Promise(setImmediate);
      const matrix = new THREE.Matrix4();
      const samples = [];
      for (let frame = 0; frame < 350; frame++) {
        const start = performance.now();
        batch.begin();
        for (let i = 0; i < count; i++) {
          matrix.makeTranslation((i % 100) + frame * 0.001, 0, Math.floor(i / 100));
          batch.add(matrix, 'review-fleet');
        }
        batch.end(frame / 60);
        if (frame >= 50) samples.push(performance.now() - start);
      }
      samples.sort((a, b) => a - b);
      const fullMatrixBytes = [...new Set(batch.meshes.map((mesh) => mesh.instanceMatrix))].reduce(
        (sum, attribute) => sum + attribute.array.byteLength,
        0,
      );
      cpu.push({
        set: asset.set,
        instances: count,
        samples: samples.length,
        p50Ms: samples[150],
        p95Ms: samples[285],
        fullMatrixBytes,
        dirtyMatrixBytes: batch.uploadBytes,
        uniqueMatrixBuffers: new Set(batch.meshes.map((m) => m.instanceMatrix)).size,
        theoreticalDirtyMatrixMiBPerSecondAt165Hz: (batch.uploadBytes * 165) / 1048576,
      });
      batch.dispose();
    }
  }
  const resources = new Set();
  gltf.scene.traverse((node) => {
    if (!(node instanceof THREE.Mesh)) return;
    resources.add(node.geometry);
    for (const material of Array.isArray(node.material) ? node.material : [node.material]) {
      resources.add(material);
      for (const value of Object.values(material)) if (value instanceof THREE.Texture) resources.add(value);
    }
  });
  resources.forEach((resource) => resource.dispose());
}
const sourceSha256 = {};
for (const path of [
  'src/model-assets.ts',
  'src/SystemSpaceScene.tsx',
  'src/LabScene.tsx',
  'backend/game-client.ts',
]) {
  sourceSha256[path] = createHash('sha256')
    .update(await readFile(new URL(path, root)))
    .digest('hex');
}
console.log(
  JSON.stringify(
    {
      measuredAt: new Date().toISOString(),
      node: process.version,
      cpu: cpus()[0]?.model,
      sourceSha256,
      limitations: [
        'CPU timing covers only InstancedModel begin/add/end and simple formation matrices in Node.',
        'No browser, GPU, complete frame, raycast, network or live game benchmark.',
        'Upload rates are calculated from dirty occupied matrix spans, not measured bus throughput.',
        '165 Hz is the user-confirmed display cap, not a measured performance capacity.',
      ],
      models,
      instancedModelCpu: cpu,
    },
    null,
    2,
  ),
);
