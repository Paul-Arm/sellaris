import test from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import { createGame } from '../shared/game';
import { systemBodies, systemHasAsteroidBelt } from '../shared/celestial';
import { createAsteroidBelt } from '../src/asteroid-belts';
import { bodyGravityWell, surfaceHeight } from '../src/spacetime-surface';
import type { Disposable } from '../src/system-objects';

test('belts are deterministic complete rings and fit between worlds', () => {
  const resources: Disposable[] = [];
  try {
    const system = createGame('ABC123').systems.find((s) => s.kind === 'star' && systemHasAsteroidBelt(s))!;
    const bodies = systemBodies(system);
    const field = bodies.find((b) => b.kind === 'asteroid')!;
    const first = createAsteroidBelt(system.id, field, resources);
    const repeat = createAsteroidBelt(system.id, field, resources);
    const other = createAsteroidBelt('another-system', field, resources);
    assert.deepEqual(first.mesh.instanceMatrix.array, repeat.mesh.instanceMatrix.array);
    assert.deepEqual(first.mesh.instanceColor!.array, repeat.mesh.instanceColor!.array);
    assert.notDeepEqual(first.mesh.instanceMatrix.array, other.mesh.instanceMatrix.array);
    assert(first.mesh.count >= 280 && first.mesh.count < 400);
    const matrix = new THREE.Matrix4();
    const position = new THREE.Vector3();
    const sectors = new Set<number>();
    for (let i = 0; i < first.mesh.count; i++) {
      first.mesh.getMatrixAt(i, matrix);
      position.setFromMatrixPosition(matrix);
      const radius = Math.hypot(position.x, position.z);
      assert(Math.abs(radius - field.orbit) <= 28);
      assert(position.y >= -6.5 && position.y <= -1.5);
      sectors.add(Math.floor(((Math.atan2(position.z, position.x) + Math.PI) / (Math.PI * 2)) * 24));
      for (const body of bodies.filter((b) => b.kind !== 'asteroid' && b.parent === undefined))
        assert(Math.abs(radius - body.orbit) > body.radius + 10);
    }
    assert.equal(sectors.size, 24, 'debris covers the full ring');
    first.animate(0);
    const initialRotation = first.group.rotation.y;
    first.animate(field.period);
    assert(Math.abs(first.group.rotation.y - initialRotation + Math.PI * 2) < 1e-10);
  } finally {
    resources.forEach((r) => r.dispose());
  }
});

test('complete belts are rare and stable while existing resource slots remain usable', () => {
  for (const size of [400, 700, 1000]) {
    const systems = Array.from({ length: size }, (_, i) => ({ id: `s${i}` }));
    const withBelts = systems.filter(systemHasAsteroidBelt);
    assert(withBelts.length / size >= 0.04 && withBelts.length / size <= 0.12);
    assert.deepEqual(structuredClone(systems).filter(systemHasAsteroidBelt), withBelts);
  }
  for (const system of createGame('ABC123').systems) {
    const renamed = { ...system, name: 'Renamed', colonyName: 'Renamed colony' };
    assert.equal(systemHasAsteroidBelt(system), systemHasAsteroidBelt(renamed));
    const field = systemBodies(system).find((b) => b.slot === 4)!;
    assert.equal(field.kind, 'asteroid', 'saved mining installations retain their address');
    assert.equal(/gürtel/i.test(field.name), systemHasAsteroidBelt(system));
  }
});

test('asteroids leave spacetime heights unchanged in stellar and exotic systems', () => {
  for (const system of createGame('ABC123').systems) {
    const bodies = systemBodies(system);
    const wells = bodies.map((body) => ({
      ...bodyGravityWell(body),
      x: Math.cos(body.phase) * body.orbit,
      y: Math.sin(body.phase) * body.orbit,
    }));
    const withoutAsteroids = wells.filter((_, i) => bodies[i].kind !== 'asteroid');
    for (const [i, body] of bodies.entries()) {
      assert.equal(wells[i].w === 0, body.kind === 'asteroid');
      for (const offset of [0, 20, 100, 400]) {
        const x = wells[i].x + offset;
        const z = wells[i].y - offset;
        assert.equal(surfaceHeight(x, z, wells, []), surfaceHeight(x, z, withoutAsteroids, []));
      }
    }
  }
});
