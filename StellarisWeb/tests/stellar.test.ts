import test from 'node:test';
import assert from 'node:assert/strict';
import { createGalaxy } from '../shared/galaxy';
import { stellarClass, stellarProfile } from '../shared/stellar';
import { systemBodies } from '../shared/celestial';
import { createGame } from '../shared/game';

test('stellar diversity preserves legacy build addresses and stays stable through class projection', () => {
  const sol = createGame('ABC123').systems[0];
  const slots = systemBodies(sol).map((b) => [b.slot, b.kind, b.orbit, b.parent]);
  for (let i = 30; i < 1000; i++) {
    const s = { ...sol, id: `s${i}`, name: 'Procedural', class: ['G2 V', 'B2 V', 'K1 III', 'A0 V'][i % 4] };
    const projected = { ...s, class: stellarClass(s) };
    assert.deepEqual(stellarProfile(s), stellarProfile(projected));
    assert.deepEqual(
      systemBodies(projected).map((b) => [b.slot, b.kind, b.orbit, b.parent]),
      slots,
    );
  }
  assert.equal(stellarClass(sol), 'G2 V');
  assert.equal(stellarProfile(sol).spill, '#ff7dbb', 'reducing glare must retain Sol’s field illumination');
});

test('new galaxies contain every stellar family without changing connected navigation or IDs', () => {
  const game = createGalaxy('ABC123', 42);
  assert.equal(game.systems.length, 1000);
  assert.equal(new Set(game.systems.map((s) => s.id)).size, 1000);
  const families = new Set(game.systems.map((s) => stellarProfile(s).family));
  for (const family of ['main', 'giant', 'neutron', 'pulsar', 'blackhole', 'quasar', 'rift'])
    assert(
      [...families].some((f) => f === family),
      family,
    );
  assert(game.systems.some((s) => s.class.startsWith('O')));
  for (const s of game.systems.filter((s) => s.class === 'Quasar')) {
    assert.equal(s.kind, 'blackhole');
    assert(!systemBodies(s).some((b) => b.main), 'quasars must not create a colonizable main world');
  }
  const reachable = new Set([game.systems[0].id]);
  let changed = true;
  while (changed) {
    changed = false;
    for (const [a, b] of game.links)
      if (reachable.has(a) !== reachable.has(b)) {
        reachable.add(a);
        reachable.add(b);
        changed = true;
      }
  }
  assert.equal(reachable.size, 1000);
  assert.deepEqual(createGalaxy('ABC123', 42), game);
});
