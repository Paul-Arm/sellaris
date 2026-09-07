import test from 'node:test';
import assert from 'node:assert/strict';
import { createGame } from '../shared/game';
import { systemBodies, facilityYield, type Facility } from '../shared/celestial';
import {
  hasStellarStorm,
  stellarWeatherFactor,
  stellarWeatherCycles,
  type StellarWeather,
} from '../shared/stellarWeather';

const weather: StellarWeather = {
  id: 1,
  objectId: '1:0',
  phase: 'warning',
  discoveredAt: 0,
  startsAt: 120,
  endsAt: 180,
};
test('stellar eruptions select reproducible giant stars only', () => {
  const system = createGame('ABC123').systems.find((s) => s.id === 's3')!;
  system.class = 'K5 III';
  const body = systemBodies(system)[0];
  assert(hasStellarStorm(body, system.id));
  assert(!hasStellarStorm(body, 's0'));
  assert(!hasStellarStorm({ ...body, slot: 2 }, system.id));
  system.class = 'NS';
  assert(!hasStellarStorm(systemBodies(system)[0], system.id));
  system.class = 'G2 V';
  assert(!hasStellarStorm(systemBodies(system)[0], system.id));
});
test('solar and Dyson output falls during the eruption only, and stacks with a crisis', () => {
  for (const facility of ['solar', 'dyson'] as const) {
    assert.equal(stellarWeatherFactor(facility, weather, 119), 1);
    assert.equal(stellarWeatherFactor(facility, weather, 120), 0.25);
    assert.equal(stellarWeatherFactor(facility, weather, 179), 0.25);
    assert.equal(stellarWeatherFactor(facility, weather, 180), 1);
  }
  for (const facility of ['mine', 'habitat', 'research', 'gas', 'starbase', 'decompressor'] as Facility[])
    assert.equal(stellarWeatherFactor(facility, weather, 140), 1);
  assert.equal(facilityYield('dyson', 3, 0.5 * stellarWeatherFactor('dyson', weather, 140)).energy, 11.25);
});
test('delayed and split settlements count exact payout boundaries without losing history', () => {
  for (const start of [0, 1, 116, 117, 119, 120, 179, 180]) {
    for (const n of [0, 1, 2, 15, 50]) {
      const expected = Array.from({ length: n }, (_, i) =>
        stellarWeatherFactor('solar', weather, start + (i + 1) * 4),
      ).reduce((a, b) => a + b, 0);
      assert.equal(stellarWeatherCycles('solar', weather, start, n), expected);
      const split = Math.floor(n / 2);
      assert.equal(
        stellarWeatherCycles('solar', weather, start, split) +
          stellarWeatherCycles('solar', weather, start + split * 4, n - split),
        expected,
      );
    }
  }
  assert.equal(stellarWeatherCycles('decompressor', weather, 0, 50), 50);
  assert.equal(stellarWeatherCycles('solar', { ...weather, endsAt: 100, phase: 'cancelled' }, 0, 50), 50);
  assert.equal(stellarWeatherCycles('solar', { ...weather, endsAt: 128, phase: 'cancelled' }, 116, 4), 2.5);
});
