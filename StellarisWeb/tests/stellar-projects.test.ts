import test from 'node:test';
import assert from 'node:assert/strict';
import { collapsedStar, frozenPlanet } from '../shared/stellarProjects';
import { facilityFits, systemBodies } from '../shared/celestial';
import { createGame } from '../shared/game';

test('stellar collapse preserves coordinates and freezes worlds without replacing their identity', () => {
  const bodies = systemBodies(createGame('BABC12').systems[0]);
  const old = bodies[0],
    next = collapsedStar(old);
  assert.equal(next.stellar!.family, 'neutron');
  assert.equal(next.slot, old.slot);
  assert.equal(next.orbit, old.orbit);
  assert.notEqual(next.radius, old.radius);
  assert(facilityFits('starbase', next));
  assert(!facilityFits('solar', next));
  const planet = bodies.find((b) => b.kind === 'planet' && b.environment)!;
  const frozen = frozenPlanet(planet);
  assert.equal(frozen.environment, 'arctic');
  assert.equal(frozen.name, planet.name);
  assert.equal(frozen.slot, planet.slot);
  assert.equal(frozen.phase, planet.phase);
  assert.equal(frozenPlanet(old), old);
  assert.notEqual(planet.environment, frozen.environment);
});
