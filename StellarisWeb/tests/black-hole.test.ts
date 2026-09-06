import test from 'node:test';
import assert from 'node:assert/strict';
import { CRITICAL_IMPACT, traceSchwarzschild } from '../src/black-hole-geodesic';

test('Schwarzschild capture boundary agrees with the analytic photon-sphere impact', () => {
  for (const scale of [0.2, 0.8, 0.99, 0.999])
    assert.equal(traceSchwarzschild(CRITICAL_IMPACT * scale).captured, true);
  for (const scale of [1.001, 1.01, 1.2, 2])
    assert.equal(traceSchwarzschild(CRITICAL_IMPACT * scale).captured, false);
  const grazing = traceSchwarzschild(CRITICAL_IMPACT * 1.001);
  assert(grazing.minRadius > 1.5 && grazing.minRadius < 1.55);
  assert(grazing.angle > 3 * Math.PI, 'near-critical rays wrap around the hole before escaping');
});

test('escaping rays conserve their analytic turning-point energy', () => {
  for (const b of [3, 4, 10, 100]) {
    const ray = traceSchwarzschild(b);
    const u = 1 / ray.minRadius;
    assert(Math.abs(u * u * (1 - u) * b * b - 1) < 0.002);
  }
});

test('weak-field deflection approaches Einstein’s 2 rs / b prediction', () => {
  for (const b of [100, 300, 1000]) {
    const deflection = traceSchwarzschild(b, 0.005).angle - Math.PI;
    assert(Math.abs(deflection / (2 / b) - 1) < 0.016);
  }
});

test('shader-sized integration steps converge against a finer reference', () => {
  for (const b of [CRITICAL_IMPACT * 1.001, 2.7, 3, 4, 10, 100]) {
    const ray = traceSchwarzschild(b);
    const fine = traceSchwarzschild(b, 0.002);
    assert.equal(ray.captured, fine.captured);
    assert(Math.abs(ray.angle - fine.angle) < 0.0002, `angular error at b=${b}`);
  }
});
