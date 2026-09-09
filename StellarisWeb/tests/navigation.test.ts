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
import { addPlayer, command, createGame, neighbors } from '../shared/game';
import { fleetGroupCommands, MAX_FLEET_GROUP, type FleetGroupCommand } from '../shared/fleetGroups';
import {
  nearbyTarget,
  selectTargets,
  targetsInBox,
  type ScreenTarget,
  type SpaceTarget,
} from '../src/space-selection';

test('space selection replaces, adds and toggles objects without duplicate fleets', () => {
  const body: SpaceTarget = { kind: 'body', slot: 1 },
    fleet: SpaceTarget = { kind: 'fleet', id: 'scout' };
  const current = [body];
  assert.deepEqual(selectTargets(current, [fleet, fleet], 'replace'), [fleet]);
  assert.deepEqual(selectTargets(current, [body, fleet, fleet], 'add'), [body, fleet]);
  assert.deepEqual(selectTargets([body, fleet], [body, body], 'toggle'), [fleet]);
  assert.deepEqual(selectTargets(current, [], 'replace'), []);
  assert.deepEqual(selectTargets(current, [], 'add'), current);
  assert.deepEqual(current, [body], 'selection changes do not mutate React state');
});

test('space picking provides a minimum target size and box selection works in every direction', () => {
  const body: SpaceTarget = { kind: 'body', slot: 1 },
    fleet: SpaceTarget = { kind: 'fleet', id: 'scout' };
  const targets: ScreenTarget[] = [
    { target: body, x: 100, y: 100, radius: 40, depth: 100 },
    { target: fleet, x: 130, y: 100, radius: 1, depth: 90 },
    { target: fleet, x: 132, y: 102, radius: 1, depth: 92 },
  ];
  assert.deepEqual(nearbyTarget(targets, 142, 100), fleet, 'small ships are selectable beside their mesh');
  assert.equal(nearbyTarget(targets, 160, 100), undefined);
  for (const [x1, y1, x2, y2] of [
    [90, 90, 140, 110],
    [140, 110, 90, 90],
    [90, 110, 140, 90],
    [140, 90, 90, 110],
  ])
    assert.deepEqual(targetsInBox(targets, x1, y1, x2, y2), [body, fleet]);
  assert.deepEqual(targetsInBox(targets, 0, 0, 10, 10), []);
});

test('fleet groups allow only bounded distinct fleets and navigation orders', () => {
  const group: FleetGroupCommand = {
    type: 'fleet_group',
    fleetIds: ['a', 'b'],
    order: { type: 'local_move', systemId: 'home', point: { x: 20, y: 30, z: 40 }, append: true },
  };
  assert.deepEqual(
    fleetGroupCommands(group),
    group.fleetIds.map((fleetId) => ({ ...group.order, fleetId })),
  );
  for (const fleetIds of [
    [],
    ['a', 'a'],
    [''],
    Array.from({ length: MAX_FLEET_GROUP + 1 }, (_, i) => `${i}`),
  ])
    assert.throws(() => fleetGroupCommands({ ...group, fleetIds }));
  for (const type of ['fleet_group', 'build', 'pause'])
    assert.throws(() => fleetGroupCommands({ ...group, order: { type } } as unknown as FleetGroupCommand));
});

test('simulated fleet groups validate all ownership before moving any fleet', () => {
  const game = createGame('ABC123'),
    owner = addPlayer(game, 'a', 'Navigator'),
    other = addPlayer(game, 'b', 'Observer');
  const fleets = game.fleets.filter((f) => f.owner === owner.id);
  const foreign = game.fleets.find((f) => f.owner === other.id)!;
  const destination = neighbors(game, owner.home)[0];
  owner.discovered.push(destination);
  const before = structuredClone(game);
  assert.throws(() =>
    command(game, owner.id, {
      type: 'fleet_group',
      fleetIds: [fleets[0].id, foreign.id],
      order: { type: 'move', systemId: destination },
    }),
  );
  assert.deepEqual(game, before);
  command(game, owner.id, {
    type: 'fleet_group',
    fleetIds: fleets.map((f) => f.id),
    order: { type: 'move', systemId: destination },
  });
  assert(fleets.every((f) => f.route.at(-1) === destination));
});
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
