import test from 'node:test';
import assert from 'node:assert/strict';
import { ClientClock } from '../backend/client-clock';
import { BattleTimeline, type Motion } from '../backend/battle-timeline';
import { combatDay, combatStep, type Fighter } from '../backend/domain';
import { gameDay, dueDay, nextGameDay, travelProgress } from '../shared/time';

test('RTT clock ignores calendar skew and preserves fractional day across pause/speed/reconnect', () => {
  let mono = 1200;
  const oldDate = Date.now;
  try {
    for (const skew of [-30000, 30000]) {
      Date.now = () => 1900000000000 + skew;
      const clock = new ClientClock(() => mono);
      const anchor = { gameTime: 20.25, wallTime: 1000, speed: 4, paused: false };
      clock.sample({ ...anchor, serverTime: 1000.1 }, 1000, 1200);
      assert(Math.abs(clock.now() - 21.05) < 1e-8);
      mono = 1450;
      assert(Math.abs(clock.now() - 22.05) < 1e-8);
      clock.observe({ ...anchor, gameTime: 22.05, wallTime: 1000.45, paused: true });
      mono = 12000;
      assert.equal(clock.now(), 22.05);
      clock.observe({ ...anchor, gameTime: 22.05, wallTime: 1011, speed: 1 });
      mono = 12500;
      assert(Math.abs(clock.now() - 22.55) < 1e-8);
      clock.freeze();
      mono = 20000;
      assert(Math.abs(clock.now() - 22.55) < 1e-8);
      const reconnected = new ClientClock(() => mono);
      reconnected.sample({ ...anchor, gameTime: 90, wallTime: 2000, serverTime: 2000 }, 20000, 20000);
      assert.equal(reconnected.now(), 90);
      mono = 1200;
    }
  } finally {
    Date.now = oldDate;
  }
});

test('queued time probes do not replace a good RTT estimate', () => {
  const clock = new ClientClock(() => 1000);
  clock.sample({ gameTime: 10, wallTime: 100, serverTime: 100, speed: 1, paused: false }, 980, 1000);
  const before = clock.now(3000);
  clock.sample({ gameTime: 10, wallTime: 100, serverTime: 100, speed: 1, paused: false }, 1000, 3000);
  assert.equal(clock.now(3000), before);
});

test('authoritative day boundaries and travel descriptions handle pause, arrival and replacement', () => {
  assert.equal(gameDay(4.99), 4);
  assert.equal(dueDay(4.01), 5);
  assert.equal(nextGameDay(4.2), 5); // old fractional save reaches next integer tick
  assert.equal(nextGameDay(5), 6);
  assert.equal(travelProgress({ departedAt: 4, arrivesAt: 8 }, 5.5), 0.375);
  assert.equal(travelProgress({ departedAt: 6, arrivesAt: 10 }, 5.5), 0);
  assert.equal(travelProgress({ departedAt: 4, arrivesAt: 8 }, 99), 1);
});

const motion = (x: number, vx = 10, shipId = 1): Motion => ({ shipId, x, y: 0, vx, vy: 0 });
test('battle timeline interpolates complete days, limits extrapolation at 1×/4× and removes deaths', () => {
  for (const speed of [1, 4]) {
    const timeline = new BattleTimeline();
    const result = motion(0);
    timeline.capture(10, [motion(0), motion(5, 10, 2)], 0);
    timeline.capture(11, [motion(10), motion(15, 10, 2)], 1000 / speed);
    timeline.frame(11.5, speed, false);
    assert(timeline.sample(1, 10.5, result));
    assert.equal(result.x, 5);
    const target = timeline.frame(100, speed, false);
    timeline.sample(1, target, result);
    assert(Math.abs(result.x - (10 + 1.5 * speed)) < 1e-7);
    timeline.capture(12, [motion(7, -10)], 2100 / speed);
    assert.equal(timeline.sample(2, 11.5, result), false);
    const paused = timeline.frame(100, speed, true);
    timeline.sample(1, paused, result);
    assert.equal(result.x, 7);
    timeline.reset();
    assert.equal(timeline.sample(1, 12, result), false);
  }
});

test('daily combat commits the same movement, weapon cadence and deaths as internal integration', () => {
  const a: Fighter = {
    shipId: 1,
    battleId: 1,
    fleetId: 1,
    empireId: 1,
    side: 0,
    x: 0,
    y: 0,
    vx: 10,
    vy: 2,
    targetId: 2,
    hull: 100,
    shield: 10,
    armor: 0.2,
    damage: 7,
    cooldown: 0.3,
    nextFireAt: 0,
    maneuver: 'line',
  };
  const rows = [a, { ...a, shipId: 2, empireId: 2, side: 1, targetId: 1, hull: 5, damage: 9 }];
  const expected = new Map(rows.map((r) => [r.shipId, r]));
  let alive = rows;
  for (let i = 1; i <= 5; i++) {
    const step = combatStep(alive, i * 0.2, 0.2);
    step.updated.forEach((r) => expected.set(r.shipId, r));
    alive = step.updated.filter((r) => r.hull > 0);
  }
  const day = combatDay(rows, 0, 1);
  for (const row of day.updated) {
    const reference = expected.get(row.shipId)!;
    assert.equal(row.hull, reference.hull);
    assert(Math.abs(row.x - reference.x) < 1e-8);
    assert.equal(row.nextFireAt, reference.nextFireAt);
  }
  assert.equal(day.killed.length, 1);
});

test('same-day metadata refreshes do not distort snapshot interval or jitter', () => {
  const timeline = new BattleTimeline();
  timeline.capture(10, [motion(0)], 0);
  timeline.frame(10, 1, false);
  timeline.capture(10, [motion(0)], 990);
  timeline.capture(11, [motion(10)], 1000);
  timeline.frame(11, 1, false);
  assert.equal(timeline.delayMs, 1030);
  timeline.capture(11, [motion(10)], 1980);
  timeline.capture(12, [motion(20)], 2000);
  timeline.frame(12, 1, false);
  assert.equal(timeline.delayMs, 1030);
});
