import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import * as THREE from 'three';
import { createNodeModelLoader } from '../scripts/node-model-loader.mjs';
import { MODEL_ASSETS, ModelInstance, ModelLibrary, ModelSlot, InstancedModel } from '../src/model-assets';
import { SHIP_SET_IDS, isShipSet, shipSetFor } from '../shared/shipSets';
import { parseEmpireTemplate, starterLibrary } from '../shared/empires';
import { instantiateEmpire, planShipSet } from '../shared/empireState';
import { SHIP_MODEL, facilityModel } from '../src/system-models';
import { systemBodies } from '../shared/celestial';
import { createGame } from '../shared/game';
import { ModelSurfaces } from '../src/model-materials';

test('runtime preserves Blender geometry, concept palette and authored surface colors', async () => {
  const surfaces = new ModelSurfaces();
  for (const set of SHIP_SET_IDS) {
    const gltf = await load(`/models/${set}/01_korvette.glb`);
    const geometry = new Map<THREE.Mesh, THREE.BufferGeometry>();
    const finishes = new Map<
      THREE.Material,
      {
        color: number[];
        emission: number[];
        strength: number;
        metal: number;
        rough: number;
        map: THREE.Texture | null;
        emissiveMap: THREE.Texture | null;
        normalMap: THREE.Texture | null;
      }
    >();
    gltf.scene.traverse((node) => {
      if (!(node instanceof THREE.Mesh)) return;
      geometry.set(node, node.geometry);
      for (const material of Array.isArray(node.material) ? node.material : [node.material]) {
        assert(material.userData.conceptAuthored, `${set}: missing concept material`);
        finishes.set(material, {
          color: material.color.toArray(),
          emission: material.emissive.toArray(),
          strength: material.emissiveIntensity,
          metal: material.metalness,
          rough: material.roughness,
          map: material.map,
          emissiveMap: material.emissiveMap,
          normalMap: material.normalMap,
        });
      }
    });
    surfaces.prepare(gltf.scene, set, 6);
    for (const [node, original] of geometry) {
      assert.equal(node.geometry, original, 'finishing does not expand or duplicate vertex buffers');
      for (const material of Array.isArray(node.material) ? node.material : [node.material]) {
        assert.equal(
          material.vertexColors,
          !!original.attributes.color,
          'baked concept color remains enabled',
        );
      }
    }
    for (const [material, finish] of finishes) {
      const m = material as THREE.MeshStandardMaterial;
      assert.deepEqual(m.color.toArray(), finish.color, 'no generic faction tint over the concept');
      assert.deepEqual(m.emissive.toArray(), finish.emission);
      assert.equal(
        m.emissiveIntensity,
        finish.strength,
        'no brightness normalization washing out the palette',
      );
      assert.equal(m.map, finish.map);
      assert.equal(m.emissiveMap, finish.emissiveMap);
      assert.equal(m.normalMap, finish.normalMap);
      if (m.userData.conceptRole !== 'plasma') {
        assert.equal(m.metalness, finish.metal);
        assert.equal(m.roughness, finish.rough);
      }
    }
    const baked = new Set<THREE.Texture>();
    const painted = new Set<THREE.Texture>();
    for (const [node] of geometry) {
      for (const material of Array.isArray(node.material) ? node.material : [node.material]) {
        const surface = material as THREE.MeshStandardMaterial;
        if (surface.map ?? surface.emissiveMap) painted.add((surface.map ?? surface.emissiveMap)!);
        for (const texture of [surface.map, surface.emissiveMap]) {
          if (!texture) continue;
          assert.equal(texture.flipY, false, `${set}: glTF texture orientation`);
          assert.equal(texture.colorSpace, THREE.SRGBColorSpace);
          const uv = node.geometry.getAttribute('uv');
          assert(uv && uv.count === node.geometry.getAttribute('position').count);
          for (const value of uv.array) assert(Number.isFinite(value));
          baked.add(texture);
        }
      }
    }
    if (set === 'nexus' || set === 'parallax') {
      assert(baked.size > 0, `${set}: painted detail must survive as a baked map`);
    }
    for (const texture of baked) {
      const { data, width, height } = (texture as THREE.DataTexture).image;
      assert(data, 'offline model loader must decode real texture pixels');
      assert(width > 0 && width <= 2048 && height > 0 && height <= 2048);
      assert.equal(data.length, width * height * 4);
      let varied = false;
      for (let p = 4; p < data.length; p += 4) {
        if ([0, 1, 2, 3].some((channel) => data[p + channel] !== data[channel])) {
          varied = true;
          break;
        }
      }
      if (painted.has(texture)) {
        assert(varied, `${set}: baked map must contain painted color or alpha detail`);
      }
    }
  }
  surfaces.dispose();
});

test('exhaust has a soft finish while engine apertures and hull remain solid', async () => {
  const surfaces = new ModelSurfaces();
  const gltf = await load('/models/prisma/01_korvette.glb');
  surfaces.prepare(gltf.scene, 'prisma', 6);
  let exhaust = 0,
    solid = 0;
  gltf.scene.traverse((node) => {
    if (!(node instanceof THREE.Mesh)) return;
    for (const m of Array.isArray(node.material) ? node.material : [node.material]) {
      const material = m as THREE.MeshStandardMaterial;
      if (/^FX_/i.test(node.name) || material.userData.conceptRole === 'plume') {
        assert(material.transparent && !material.depthWrite);
        assert.equal(material.blending, THREE.AdditiveBlending);
        exhaust++;
      } else {
        assert(!material.transparent && material.depthWrite);
        solid++;
      }
    }
  });
  assert(solid > 0 && exhaust > 0);
  surfaces.dispose();
});

test('finishes do not accumulate on repeat calls or modify models after scene closure', () => {
  const surfaces = new ModelSurfaces();
  const material = new THREE.MeshPhysicalMaterial({ color: '#aabbcc' });
  const model = new THREE.Mesh(new THREE.BoxGeometry(), material);
  surfaces.prepare(model, 'vektor', 1);
  const finishedColor = material.color.clone();
  surfaces.prepare(model, 'vektor', 1);
  assert.deepEqual(material.color, finishedColor);
  const late = new THREE.Mesh(new THREE.BoxGeometry(), new THREE.MeshPhysicalMaterial());
  const original = late.material.color.clone();
  surfaces.dispose();
  surfaces.prepare(late, 'prisma', 1);
  assert.deepEqual(late.material.color, original);
  model.geometry.dispose();
  material.dispose();
  late.geometry.dispose();
  late.material.dispose();
});

const loader = createNodeModelLoader();
async function load(url: string) {
  const bytes = await readFile(`public${url}`);
  return loader.parseAsync(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength), '');
}
test('all six complete sets contain 120 portable models and 204 valid clips', async () => {
  assert.equal(MODEL_ASSETS.length, 120);
  assert.equal(new Set(MODEL_ASSETS.map((a) => a.url)).size, 120);
  let clips = 0;
  for (const set of SHIP_SET_IDS) {
    const assets = MODEL_ASSETS.filter((a) => a.set === set);
    assert.equal(assets.length, 20, set);
    for (const id of Object.values(SHIP_MODEL)) assert(assets.some((a) => a.id === id));
    assert(assets.find((a) => a.id === 'orbital_ring')!.planetRadius! > 0);
    for (const asset of assets) {
      const gltf = await load(asset.url);
      assert.deepEqual(
        gltf.animations.map((c) => c.name),
        asset.clips.map((c) => c.name),
      );
      const bounds = new THREE.Box3().setFromObject(gltf.scene);
      assert(!bounds.isEmpty(), asset.url);
      assert(
        bounds
          .getSize(new THREE.Vector3())
          .toArray()
          .every((v) => Number.isFinite(v) && v > 0),
      );
      for (const clip of gltf.animations) {
        assert(clip.duration > 0 && clip.validate(), `${asset.url}: ${clip.name}`);
        clips++;
      }
      const instance = new ModelInstance(gltf, 25);
      instance.group.position.set(100, 50, 20);
      instance.update(3);
      instance.group.updateMatrixWorld(true);
      const pose: number[] = [];
      instance.scene.traverse((o) => pose.push(...o.matrix.elements));
      instance.update(3);
      instance.group.updateMatrixWorld(true);
      const pausedPose: number[] = [];
      instance.scene.traverse((o) => pausedPose.push(...o.matrix.elements));
      assert.deepEqual(pausedPose, pose, 'paused simulation time holds the pose');
      instance.update(4);
      instance.group.updateMatrixWorld(true);
      const movingPose: number[] = [];
      instance.scene.traverse((o) => movingPose.push(...o.matrix.elements));
      assert.notDeepEqual(movingPose, pose, `${asset.url}: idle clip must move geometry`);
      assert.deepEqual(
        instance.group.position.toArray(),
        [100, 50, 20],
        'animation never overwrites placement',
      );
      instance.operate(true);
      instance.update(4);
      instance.dispose();
    }
  }
  assert.equal(clips, 204);
});

test('design selection survives validation and founding; legacy templates remain valid', () => {
  const library = starterLibrary();
  for (const set of SHIP_SET_IDS) {
    const empire = parseEmpireTemplate({ ...library.empires[0], shipSet: set }, library.species);
    const instance = instantiateEmpire({ empire, species: library.species[0] }, 'p', 0);
    assert.equal(instance.design.shipSet, set);
    const before = structuredClone(instance.founding);
    const changed = planShipSet(instance, 'nexus', 10, instance.revision);
    assert.equal(changed.design.shipSet, 'nexus');
    assert.deepEqual(changed.founding, before, 'cosmetic changes preserve the founding template');
  }
  assert.equal(
    parseEmpireTemplate({ ...library.empires[0], shipSet: undefined }, library.species).shipSet,
    'prisma',
  );
  assert.equal(shipSetFor(), 'prisma');
  assert(!isShipSet('__proto__'));
  assert.throws(() => parseEmpireTemplate({ ...library.empires[0], shipSet: '../secret' }, library.species));
});

test('facility stages use construction, production and planet-scaled ring models', () => {
  const body = systemBodies(createGame('MODELS').systems[0]).find((b) => b.main)!;
  const site = {
    id: 'site',
    systemId: 'system',
    bodySlot: body.slot,
    owner: 'p',
    facility: 'habitat' as const,
    level: 0,
    building: true,
    suspended: false,
    startedAt: 0,
    finishAt: 20,
  };
  assert.equal(facilityModel(site, body).id, '05_construction_level_0');
  const ring = facilityModel({ ...site, level: 3, building: false }, body);
  assert.equal(ring.id, 'orbital_ring');
  assert.equal(ring.planetRadius, body.radius * 1.05);
  assert.equal(facilityModel({ ...site, facility: 'mine', level: 2 }, body).id, '02_mining_ring');
});

test('instancing keeps fleet picking IDs when capacity grows and late slots cannot resurrect', async () => {
  const asset = MODEL_ASSETS.find((a) => a.set === 'prisma' && a.id === '01_korvette')!;
  const gltf = await load(asset.url);
  const library = { load: async () => gltf } as unknown as ModelLibrary;
  const model = new InstancedModel(library, asset, 25);
  await Promise.resolve();
  model.begin();
  for (let i = 0; i < 300; i++) model.add(new THREE.Matrix4().makeTranslation(i * 50, 0, 0), `fleet-${i}`);
  model.end(3);
  for (const mesh of model.meshes) {
    assert.equal(mesh.count, 300);
    assert.equal(mesh.userData.fleets[0], 'fleet-0');
    assert.equal(mesh.userData.fleets[299], 'fleet-299');
  }
  model.dispose();
  const slot = new ModelSlot(library);
  slot.set(asset, 25);
  slot.dispose();
  await Promise.resolve();
  assert.equal(slot.ready, false);
  assert.equal(slot.group.children.length, 0);
});

test('instanced resize retains shared texture images until the model library closes', async () => {
  let imageCloses = 0;
  let textureDisposals = 0;
  const image = { close: () => imageCloses++ } as unknown as ImageBitmap;
  const first = new THREE.Texture(image);
  const second = first.clone();
  for (const texture of [first, second]) {
    texture.addEventListener('dispose', () => textureDisposals++);
  }
  const scene = new THREE.Group();
  const geometry = new THREE.BoxGeometry();
  scene.add(new THREE.Mesh(geometry, new THREE.MeshStandardMaterial({ map: first })));
  scene.add(new THREE.Mesh(geometry, new THREE.MeshStandardMaterial({ map: second })));
  const library = new ModelLibrary();
  Object.assign(library, { loader: { loadAsync: async () => ({ scene, animations: [] }) } });
  const asset = MODEL_ASSETS[0];
  await library.load(asset);
  const fleet = new InstancedModel(library, asset, 10);
  await Promise.resolve();
  assert(fleet.ready);
  fleet.begin();
  for (let i = 0; i < 300; i++) fleet.add(new THREE.Matrix4().makeTranslation(i * 20, 0, 0));
  fleet.end(0);
  assert.equal(imageCloses, 0, 'resizing must leave shared decoded images usable');
  assert.equal(textureDisposals, 0);
  fleet.dispose();
  assert.equal(imageCloses, 0, 'disposing a fleet must not close library-owned images');
  library.dispose();
  library.dispose();
  await Promise.resolve();
  assert.equal(textureDisposals, 2, 'each texture releases its GPU storage once');
  assert.equal(imageCloses, 1, 'two textures sharing one decoded bitmap close it only once');
});
