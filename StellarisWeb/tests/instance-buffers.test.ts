import test from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import { InstancedModel, type ModelLibrary, type ModelAsset } from '../src/model-assets';
import { instanceColor, instanceMatrix, flushInstances } from '../src/instance-buffers';

test('shared ship matrices preserve part transforms, normals, animation and actual ray picking after growth', async () => {
  const scene = new THREE.Group();
  for (const x of [-2, 2]) {
    const part = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), new THREE.MeshStandardMaterial());
    part.position.x = x;
    part.scale.set(1, 2, 0.5);
    scene.add(part);
  }
  scene.children[0].name = 'moving';
  const clip = new THREE.AnimationClip('idle', 2, [
    new THREE.NumberKeyframeTrack('moving.position[y]', [0, 1, 2], [0, 4, 0]),
  ]);
  const library = { load: async () => ({ scene, animations: [clip] }) } as unknown as ModelLibrary;
  const model = new InstancedModel(library, { url: 'test' } as ModelAsset, 10);
  await Promise.resolve();
  model.begin();
  for (let i = 0; i < 300; i++) model.add(new THREE.Matrix4().makeTranslation(i * 20, 0, 0), String(i));
  model.end(0.5);
  assert.equal(new Set(model.meshes.map((m) => m.instanceMatrix)).size, 1);
  assert.equal(model.uploadBytes, 300 * 64);
  const part = model.meshes[0];
  const normal = new THREE.Matrix3().getNormalMatrix(part.partTransform.value);
  assert.deepEqual(part.partNormal.value.elements, normal.elements);
  const ship = new THREE.Matrix4();
  part.getMatrixAt(299, ship);
  const center = new THREE.Vector3().applyMatrix4(part.partTransform.value).applyMatrix4(ship);
  model.group.updateMatrixWorld(true);
  const ray = new THREE.Raycaster(
    center.clone().add(new THREE.Vector3(0, 0, 100)),
    new THREE.Vector3(0, 0, -1),
  );
  const hit = ray.intersectObjects(model.group.children, true)[0];
  assert.equal(hit.instanceId, 299);
  assert.equal(hit.object.userData.fleets[hit.instanceId!], '299');
  const oldPart = part.partTransform.value.clone();
  model.begin();
  for (let i = 0; i < 300; i++) model.add(new THREE.Matrix4().makeTranslation(i * 20, 0, 0), String(i));
  model.end(1);
  assert.equal(model.uploadBytes, 0, 'animated parts do not cause ship matrix uploads');
  assert(!oldPart.equals(part.partTransform.value));
  model.begin();
  model.end(2);
  assert.equal(model.group.visible, false);
  model.dispose();
});

test('fallback instance uploads include only dirty occupied ranges and changed colors', () => {
  const mesh = new THREE.InstancedMesh(new THREE.BoxGeometry(), new THREE.MeshBasicMaterial(), 4096);
  const matrix = new THREE.Matrix4().makeTranslation(4, 0, 0),
    color = new THREE.Color('red');
  instanceMatrix(mesh, 3, matrix);
  instanceColor(mesh, 3, color);
  assert.equal(flushInstances(mesh), 76);
  assert.deepEqual(mesh.instanceMatrix.updateRanges, [{ start: 48, count: 16 }]);
  instanceMatrix(mesh, 3, matrix);
  instanceColor(mesh, 3, color);
  assert.equal(flushInstances(mesh), 0);
  mesh.dispose();
  mesh.geometry.dispose();
  (mesh.material as THREE.Material).dispose();
});
