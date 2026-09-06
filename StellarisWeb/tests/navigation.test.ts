import test from 'node:test';
import assert from 'node:assert/strict';
import {
  bodyPosition,
  flight,
  localPosition,
  localVelocity,
  braking,
  validPoint,
} from '../shared/navigation';
import { systemBodies } from '../shared/celestial';
import { createGame } from '../shared/game';
test('local flight interpolation clamps to committed endpoints and respects height', () => {
  const motion = flight({ x: 0, y: 20, z: 0 }, { x: 600, y: 220, z: 0 }, 10);
  assert.deepEqual(localPosition(motion, 0), motion.from);
  assert.deepEqual(localPosition(motion, 100), motion.to);
  assert.deepEqual(localPosition(motion, (motion.startedAt + motion.finishAt) / 2), { x: 300, y: 120, z: 0 });
  assert(!validPoint({ x: 1200, y: 100, z: 1200 }));
  assert(!validPoint({ x: 0, y: NaN, z: 0 }));
  assert(!validPoint({ x: 0, y: -1, z: 0 }));
});
test('system flight takes time and eases acceleration and braking on the authoritative clock', () => {
  const motion = flight({ x: 0, y: 24, z: 0 }, { x: 800, y: 24, z: 0 }, 10);
  const duration = motion.finishAt - motion.startedAt;
  assert.equal(duration, 10, '800 units take ten game days');
  const at = (progress: number) => localPosition(motion, 10 + duration * progress).x;
  assert(at(0.25) < 200, 'acceleration starts slower than constant-speed flight');
  assert(at(0.75) > 600, 'braking begins before the destination');
  assert(at(0.01) < at(0.51) - at(0.5), 'initial speed is below cruising speed');
  assert(800 - at(0.99) < at(0.5) - at(0.49), 'arrival slows without overshooting');
  assert.deepEqual(localPosition({ ...motion, paused: true }, 100), motion.from);
  assert.equal(flight(motion.from, { ...motion.from, x: 1 }, 0).finishAt, 4);
  // A replacement order starts at the same eased position used by the renderer.
  const midway = localPosition(motion, 12.5);
  const replacement = flight(midway, { x: -800, y: 60, z: 100 }, 12.5);
  assert.deepEqual(localPosition(replacement, 12.5), midway);
});

test('turning preserves momentum and stopping has a finite braking distance', () => {
  const straight = flight({ x: 0, y: 24, z: 0 }, { x: 800, y: 24, z: 0 }, 0);
  const from = localPosition(straight, 5),
    velocity = localVelocity(straight, 5);
  const turn = flight(from, { x: 400, y: 24, z: 800 }, 5, velocity);
  assert.deepEqual(localVelocity(turn, 5), velocity, 'a new course preserves instantaneous velocity');
  assert(localPosition(turn, 6).x > from.x + 50, 'ship visibly drifts along the old heading while turning');
  assert(localPosition(turn, 6).z > 0, 'the new heading bends the trajectory');
  assert.deepEqual(localPosition(turn, turn.finishAt), turn.to);
  assert.deepEqual(localVelocity(turn, turn.finishAt), { x: 0, y: 0, z: 0 });
  const stop = braking(straight, 5);
  assert.deepEqual(localVelocity(stop, 5), velocity);
  assert(stop.to.x > from.x + 100, 'stop has a visible braking distance');
  assert(localVelocity(stop, 6).x < velocity.x);
  assert.deepEqual(localVelocity(stop, stop.finishAt), { x: 0, y: 0, z: 0 });
});

test('survey targeting shares moving moon orbits and fixed station coordinates', () => {
  const bodies = systemBodies(createGame('ABC123').systems[0]);
  const moon = bodies.find((b) => b.parent !== undefined)!;
  const parent = bodies.find((b) => b.slot === moon.parent)!;
  const m = bodyPosition(moon, bodies, 120),
    p = bodyPosition(parent, bodies, 120);
  assert(Math.abs(Math.hypot(m.x - p.x, m.z - p.z) - moon.orbit) < 1e-7);
  assert.notDeepEqual(bodyPosition(moon, bodies, 120), bodyPosition(moon, bodies, 240));
  assert.deepEqual(bodyPosition({ ...moon, position: { x: 300, y: 200, z: -100 } }, bodies, 999), {
    x: 300,
    y: 200,
    z: -100,
  });
});
