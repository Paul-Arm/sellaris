import test from 'node:test';
import assert from 'node:assert/strict';
import { FACILITIES, facilitySpec, facilityYield, systemBodies } from '../shared/celestial';
import { createGame, addPlayer, income } from '../shared/game';

test('durable orbital slots cover buildable stars, worlds, moons, rocks and ruins', () => {
  const g = createGame('ABC123');
  for (const system of g.systems) {
    const bodies = systemBodies(system);
    assert.deepEqual(systemBodies(structuredClone(system)), bodies);
    assert.equal(new Set(bodies.map((b) => b.slot)).size, bodies.length);
    for (const body of bodies) {
      assert(Object.values(FACILITIES).some((f) => f.kinds.includes(body.kind)));
      if (body.parent !== undefined) assert(bodies.some((b) => b.slot === body.parent));
    }
    const renamed = systemBodies({ ...system, name: 'Renamed', colonyName: 'New colony name' });
    assert.deepEqual(
      renamed.map((b) => [b.slot, b.orbit, b.phase, b.kind]),
      bodies.map((b) => [b.slot, b.orbit, b.phase, b.kind]),
    );
  }
});
test('installation yields are included once in the empire ledger and scale by level and crisis', () => {
  assert.deepEqual(facilityYield('solar', 3, 0.5), { energy: 7.5, minerals: 0, science: 0 });
  assert(facilitySpec('mine', 2).cost.minerals > facilitySpec('mine', 1).cost.minerals);
  const g = createGame('ABC123'),
    p = addPlayer(g, 'a', 'A'),
    before = income(g, p);
  p.installationIncome = { energy: 5, minerals: 4, science: 3 };
  assert.deepEqual(income(g, p), {
    energy: before.energy + 5,
    minerals: before.minerals + 4,
    science: before.science + 3,
  });
});

test('primary orbits leave the stellar centre clear and keep moons with their parent', () => {
  for (const system of createGame('ABC123').systems) {
    const bodies = systemBodies(system);
    const primary = bodies.filter((b) => b.orbit > 0 && b.parent === undefined);
    assert.equal(bodies[0].orbit, 0);
    assert(primary.every((b) => b.orbit >= 460 && b.orbit + b.radius < 1200));
    for (let i = 1; i < primary.length; i++) {
      const previous = primary[i - 1];
      assert(primary[i].orbit - previous.orbit > 120, 'primary orbits have room between them');
    }
    for (const moon of bodies.filter((b) => b.parent !== undefined)) {
      const parent = bodies.find((b) => b.slot === moon.parent)!;
      assert(moon.orbit < 50, 'local moon orbits must not inherit the stellar orbit expansion');
      assert(parent.orbit - moon.orbit - moon.radius > bodies[0].radius + 150);
      assert.equal(moon.period, moon.slot === 2 ? 480 : 680);
    }
  }
});
