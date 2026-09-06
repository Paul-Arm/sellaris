import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { MODEL_ASSETS } from '../src/model-assets';

test('shipped meshes stay within the RTS geometry budgets', async () => {
  let libraryTriangles = 0;
  for (const asset of MODEL_ASSETS) {
    const bytes = await readFile(`public${asset.url}`);
    assert.equal(bytes.readUInt32LE(8), bytes.length, `${asset.url}: complete GLB`);
    const gltf = JSON.parse(bytes.toString('utf8', 20, 20 + bytes.readUInt32LE(12)));
    let triangles = 0;
    const visit = (index: number) => {
      const node = gltf.nodes[index];
      if (node.mesh !== undefined) {
        for (const primitive of gltf.meshes[node.mesh].primitives) {
          assert.equal(primitive.mode ?? 4, 4);
          const accessor = primitive.indices ?? primitive.attributes.POSITION;
          triangles += gltf.accessors[accessor].count / 3;
        }
      }
      for (const child of node.children ?? []) visit(child);
    };
    for (const root of gltf.scenes[gltf.scene ?? 0].nodes) visit(root);
    // Budget one rendered model including repeated collectors/modules. Paint
    // detail belongs in maps; large arrays still need their real silhouettes.
    const ship = /_(korvette|fregatte|zerstoerer|kreuzer|schlachtschiff|titan|arbeiter|forschung)$/.test(
      asset.id,
    );
    const budget = ship ? 6_000 : asset.id === '03_dyson_swarm' ? 32_000 : 16_000;
    assert(triangles > 0 && triangles <= budget, `${asset.url}: ${triangles} triangles, budget ${budget}`);
    libraryTriangles += triangles;
  }
  assert(libraryTriangles <= 400_000, `Complete library: ${libraryTriangles} triangles, budget 400000`);
});
