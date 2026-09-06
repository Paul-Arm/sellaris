import test from 'node:test';
import assert from 'node:assert/strict';
import { createGame } from '../shared/game';
import { generateSystemBodies } from '../shared/systemGeneration';
import { gravitySlots, objectBodies } from '../shared/systemObjects';
test('stored atlas supports empty systems and more bodies than the gravity budget', () => {
  assert.deepEqual(objectBodies([]), []);
  const base = generateSystemBodies(createGame('ABC123').systems[0]);
  const bodies = Array.from({ length: 30 }, (_, i) => ({ ...base[1], slot: i + 10, radius: i + 1 }));
  bodies.push(base[0]);
  const gravity = gravitySlots(bodies);
  assert.equal(gravity.size, 10);
  assert(gravity.has(0), 'star is retained in gravity budget');
  assert.equal(bodies.length, 31, 'no gameplay objects dropped');
  const rows = bodies.map((body) => ({
    id: `1:${body.slot}`,
    systemId: 1,
    slot: body.slot,
    revision: 2,
    state: body.slot === 10 ? 'removed' : 'active',
    changedAt: 42,
    parentId: '',
    bodyJson: JSON.stringify(body),
  }));
  const projected = objectBodies(rows);
  assert.equal(projected.length, 30);
  assert.equal(projected[0].objectId, '1:0');
  assert(!projected.some((body) => body.slot === 10));
});
