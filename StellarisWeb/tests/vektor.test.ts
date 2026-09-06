import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import * as THREE from 'three';
import { createNodeModelLoader } from '../scripts/node-model-loader.mjs';
import { MODEL_ASSETS } from '../src/model-assets';

const loader = createNodeModelLoader();
const combatIds = [
  '01_korvette',
  '02_fregatte',
  '03_zerstoerer',
  '04_kreuzer',
  '05_schlachtschiff',
  '06_titan',
];
async function load(id: string) {
  const bytes = await readFile(`public/models/vektor/${id}.glb`);
  return loader.parseAsync(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength), '');
}

function triangles(
  mesh: THREE.Mesh,
  visit: (a: THREE.Vector3, b: THREE.Vector3, c: THREE.Vector3, material: THREE.MeshPhysicalMaterial) => void,
) {
  const geometry = mesh.geometry;
  const p = geometry.attributes.position;
  const indices = geometry.index;
  const a = new THREE.Vector3(),
    b = new THREE.Vector3(),
    c = new THREE.Vector3();
  for (let offset = 0; offset < (indices?.count ?? p.count); offset += 3) {
    const slot =
      geometry.groups.find((g) => offset >= g.start && offset < g.start + g.count)?.materialIndex ?? 0;
    const material = (
      Array.isArray(mesh.material) ? mesh.material[slot] : mesh.material
    ) as THREE.MeshPhysicalMaterial;
    a.fromBufferAttribute(p, indices ? indices.getX(offset) : offset);
    b.fromBufferAttribute(p, indices ? indices.getX(offset + 1) : offset + 1);
    c.fromBufferAttribute(p, indices ? indices.getX(offset + 2) : offset + 2);
    visit(a, b, c, material);
  }
}

test('VEKTOR uses painted pearlescent material on undersides, sidewalls and upper armor', async () => {
  for (const asset of MODEL_ASSETS.filter((a) => a.set === 'vektor')) {
    const gltf = await load(asset.id);
    let upper = 0,
      lower = 0,
      sides = 0;
    gltf.scene.updateMatrixWorld(true);
    gltf.scene.traverse((node) => {
      if (!(node instanceof THREE.Mesh) || /^FX_/.test(node.name)) return;
      const materials = Array.isArray(node.material) ? node.material : [node.material];
      for (const material of materials) {
        if (
          !/titanium underside|structure|pearl|ice facet|lilac facet|hull|facet [ab]/i.test(material.name) &&
          !material.userData.conceptMainShell
        )
          continue;
        const m = material as THREE.MeshPhysicalMaterial;
        assert.equal(
          m.userData.conceptRole,
          'crystal',
          `${asset.id}: ${m.name} still has a separate plain finish`,
        );
        assert(
          m.vertexColors && node.geometry.attributes.color,
          `${asset.id}: ${m.name} missing painted surface`,
        );
        assert(m.iridescence >= 0.15, `${asset.id}: ${m.name} missing pearl finish`);
      }
      triangles(node, (a, b, c, material) => {
        if (material.userData.conceptRole !== 'crystal') return;
        const normal = new THREE.Vector3().subVectors(b, a).cross(new THREE.Vector3().subVectors(c, a));
        const area = normal.length() * 0.5;
        normal.applyNormalMatrix(new THREE.Matrix3().getNormalMatrix(node.matrixWorld));
        if (normal.y > 0.3) upper += area;
        else if (normal.y < -0.3) lower += area;
        else sides += area;
      });
    });
    assert(
      upper > 0 && lower > 0 && sides > 0,
      `${asset.id}: requires painted physical upper/lower/side surfaces`,
    );
  }
});

test('VEKTOR combat ships have one closed, connected main hull with physical volume', async () => {
  for (const id of combatIds) {
    const gltf = await load(id);
    const hull = gltf.scene.getObjectByName('Hull');
    assert(hull, `${id}: Hull node`);
    const span = new THREE.Box3().setFromObject(hull).getSize(new THREE.Vector3()).length();
    const vertices = new Map<string, number>();
    const edges = new Map<string, { count: number; direction: number }>();
    const parents: number[] = [];
    const pointId = (point: THREE.Vector3) => {
      const key = point
        .toArray()
        .map((v) => Math.round((v / span) * 1e6))
        .join(',');
      if (!vertices.has(key)) {
        vertices.set(key, vertices.size);
        parents.push(parents.length);
      }
      return vertices.get(key)!;
    };
    const root = (id: number): number => (parents[id] === id ? id : (parents[id] = root(parents[id])));
    let shellArea = 0,
      solidArea = 0,
      volume = 0;
    hull.traverse((node) => {
      if (!(node instanceof THREE.Mesh)) return;
      triangles(node, (a, b, c, material) => {
        const area =
          new THREE.Vector3().subVectors(b, a).cross(new THREE.Vector3().subVectors(c, a)).length() * 0.5;
        if (material.userData.conceptRole === 'crystal') solidArea += area;
        if (!material.userData.conceptMainShell) return;
        shellArea += area;
        volume += a.dot(new THREE.Vector3().crossVectors(b, c)) / 6;
        const ids = [pointId(a), pointId(b), pointId(c)];
        assert.equal(new Set(ids).size, 3, `${id}: collapsed shell triangle`);
        for (let i = 0; i < 3; i++) {
          const p = ids[i],
            q = ids[(i + 1) % 3];
          parents[root(p)] = root(q);
          const key = p < q ? `${p}/${q}` : `${q}/${p}`;
          const edge = edges.get(key) ?? { count: 0, direction: 0 };
          edge.count++;
          edge.direction += p < q ? 1 : -1;
          edges.set(key, edge);
        }
      });
    });
    assert(shellArea > solidArea * 0.55, `${id}: main shell must form the body, not a small connector`);
    assert.equal(new Set(parents.map((_, i) => root(i))).size, 1, `${id}: detached primary armor pieces`);
    assert(Math.abs(volume) > span ** 3 * 1e-5, `${id}: shell has no physical thickness`);
    for (const edge of edges.values()) {
      assert.equal(edge.count, 2, `${id}: open or non-manifold hull edge`);
      assert.equal(edge.direction, 0, `${id}: inconsistent front/back winding`);
    }
  }
});

async function hullSilhouette(id: string) {
  const gltf = await load(id);
  const hull = gltf.scene.getObjectByName('Hull');
  assert(hull);
  gltf.scene.updateMatrixWorld(true);
  const faces: THREE.Vector3[][] = [];
  const box = new THREE.Box3();
  hull.traverse((node) => {
    if (!(node instanceof THREE.Mesh)) return;
    triangles(node, (a, b, c, material) => {
      if (!material.userData.conceptMainShell) return;
      const points = [a, b, c].map((p) => p.clone().applyMatrix4(node.matrixWorld));
      points.forEach((p) => box.expandByPoint(p));
      faces.push(points);
    });
  });
  const size = box.getSize(new THREE.Vector3());
  assert(size.x > 0 && size.z > 0);
  const resolution = 128;
  const mask = new Uint8Array(resolution * resolution);
  // Normalize width and length independently: merely widening one shared
  // arrow shape must not qualify as a recognizable new ship class.
  const project = (p: THREE.Vector3) => ({
    x: ((p.x - box.min.x) / size.x) * (resolution - 4) + 2,
    y: ((p.z - box.min.z) / size.z) * (resolution - 4) + 2,
  });
  const edge = (a: { x: number; y: number }, b: { x: number; y: number }, x: number, y: number) =>
    (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x);
  for (const face of faces) {
    const [a, b, c] = face.map(project);
    const orientation = Math.sign(edge(a, b, c.x, c.y));
    if (!orientation) continue;
    const left = Math.max(0, Math.floor(Math.min(a.x, b.x, c.x)));
    const right = Math.min(resolution - 1, Math.ceil(Math.max(a.x, b.x, c.x)));
    const top = Math.max(0, Math.floor(Math.min(a.y, b.y, c.y)));
    const bottom = Math.min(resolution - 1, Math.ceil(Math.max(a.y, b.y, c.y)));
    for (let y = top; y <= bottom; y++)
      for (let x = left; x <= right; x++) {
        if (
          edge(a, b, x + 0.5, y + 0.5) * orientation >= -1e-6 &&
          edge(b, c, x + 0.5, y + 0.5) * orientation >= -1e-6 &&
          edge(c, a, x + 0.5, y + 0.5) * orientation >= -1e-6
        )
          mask[y * resolution + x] = 1;
      }
  }
  return mask;
}

test('VEKTOR combat classes remain distinct after removing size, aspect ratio and material cues', async () => {
  const masks = await Promise.all(combatIds.map(hullSilhouette));
  for (let a = 0; a < masks.length; a++)
    for (let b = a + 1; b < masks.length; b++) {
      let intersection = 0;
      let union = 0;
      for (let p = 0; p < masks[a].length; p++) {
        intersection += masks[a][p] & masks[b][p];
        union += masks[a][p] | masks[b][p];
      }
      assert(union > 0);
      const overlap = intersection / union;
      assert(
        overlap < 0.9,
        `${combatIds[a]} / ${combatIds[b]}: ${(overlap * 100).toFixed(1)}% silhouette overlap; needs its own hull outline`,
      );
    }
});
