import test from 'node:test';
import assert from 'node:assert/strict';
import {
  combatStep,
  effectiveHpLost,
  gameTimeAt,
  positionAt,
  progressAt,
  SCENARIOS,
  validateScenario,
  type Fighter,
} from '../backend/domain';
test('game-clock pause/speed anchors and route interpolation remain continuous', () => {
  const anchor = { gameTime: 10, wallTime: 100, speed: 4, paused: false };
  assert.equal(gameTimeAt(anchor, 105), 30);
  assert.equal(gameTimeAt({ ...anchor, paused: true }, 105), 10);
  assert.equal(gameTimeAt(anchor, 99), 10);
  const route = { fromX: 0, fromY: 0, toX: 100, toY: 60, departedAt: 10, arrivesAt: 30 };
  assert.deepEqual(positionAt(route, 20), { x: 50, y: 30 });
  assert.deepEqual(positionAt(route, 100), { x: 100, y: 60 });
  assert.equal(progressAt({ workDone: 20, workTotal: 100, rate: 2, updatedAt: 50 }, 70), 60);
});
test('scenario examples are configurable rather than ship-count caps', () => {
  validateScenario(SCENARIOS.standard);
  validateScenario(SCENARIOS.large);
  validateScenario({ ...SCENARIOS.large, shipsPerEmpire: 7000 });
  assert.throws(() => validateScenario({ ...SCENARIOS.standard, battleCount: 13 }));
  assert.throws(() => validateScenario({ ...SCENARIOS.standard, fleetsPerEmpire: 0 }));
});
test('effective damage counts shield and hull loss after armor, without overkill or healing', () => {
  assert.equal(effectiveHpLost({ hull: 100, shield: 20 }, { hull: 90, shield: 0 }), 30);
  assert.equal(effectiveHpLost({ hull: 10, shield: 5 }, { hull: -100, shield: 0 }), 15);
  assert.equal(effectiveHpLost({ hull: 10, shield: 5 }, { hull: 20, shield: 10 }), 0);
});
test('battle resolves simultaneous lethal hits independent of participant iteration order', () => {
  const fighter: Fighter = {
    shipId: 1,
    battleId: 1,
    fleetId: 1,
    empireId: 1,
    side: 0,
    x: 0,
    y: 0,
    vx: 1,
    vy: 0,
    targetId: 2,
    hull: 10,
    shield: 2,
    armor: 0,
    damage: 12,
    cooldown: 1,
    nextFireAt: 0,
    maneuver: 'strafe',
  };
  const enemy = { ...fighter, shipId: 2, empireId: 2, side: 1, targetId: 1 };
  const result = combatStep([fighter, enemy], 1, 0.2);
  const reverse = combatStep([enemy, fighter], 1, 0.2);
  assert.equal(result.killed.length, 2);
  assert.equal(reverse.killed.length, 2);
  assert.equal(fighter.hull, 10, 'Pure simulation must not mutate its inputs');
});
