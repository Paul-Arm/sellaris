/** Transport-independent simulation math. Time is always authoritative game seconds. */
export interface ClockAnchor {
  gameTime: number;
  wallTime: number;
  speed: number;
  paused: boolean;
}

export function gameTimeAt(clock: ClockAnchor, wallTime: number) {
  return clock.gameTime + (clock.paused ? 0 : Math.max(0, wallTime - clock.wallTime) * clock.speed);
}

export interface Journey {
  fromX: number;
  fromY: number;
  toX: number;
  toY: number;
  departedAt: number;
  arrivesAt: number;
}

export function positionAt(fleet: Journey, gameTime: number) {
  const duration = fleet.arrivesAt - fleet.departedAt;
  const fraction = duration > 0 ? Math.min(1, Math.max(0, (gameTime - fleet.departedAt) / duration)) : 1;
  return {
    x: fleet.fromX + (fleet.toX - fleet.fromX) * fraction,
    y: fleet.fromY + (fleet.toY - fleet.fromY) * fraction,
  };
}

export function progressAt(
  job: { workDone: number; workTotal: number; rate: number; updatedAt: number },
  time: number,
) {
  return Math.min(job.workTotal, job.workDone + Math.max(0, time - job.updatedAt) * job.rate);
}

export interface Scenario {
  seed: number;
  systems: number;
  empires: number;
  fleetsPerEmpire: number;
  shipsPerEmpire: number;
  battleCount: number;
  battleFleetsPerSide: number;
  cohortsPerColony: number;
  popsPerCohort: number;
}

export const SCENARIOS: Record<string, Scenario> = {
  standard: {
    seed: 42,
    systems: 1000,
    empires: 25,
    fleetsPerEmpire: 50,
    shipsPerEmpire: 1000,
    battleCount: 5,
    battleFleetsPerSide: 5,
    cohortsPerColony: 4,
    popsPerCohort: 25,
  },
  large: {
    seed: 42,
    systems: 1000,
    empires: 25,
    fleetsPerEmpire: 50,
    shipsPerEmpire: 3000,
    battleCount: 5,
    battleFleetsPerSide: 5,
    cohortsPerColony: 4,
    popsPerCohort: 100,
  },
  smoke: {
    seed: 7,
    systems: 100,
    empires: 4,
    fleetsPerEmpire: 10,
    shipsPerEmpire: 100,
    battleCount: 1,
    battleFleetsPerSide: 2,
    cohortsPerColony: 2,
    popsPerCohort: 10,
  },
};

export function validateScenario(s: Scenario) {
  for (const [name, value] of Object.entries(s)) {
    if (!Number.isSafeInteger(value) || value < 0 || value > 0xffff_ffff) throw new Error(`Invalid ${name}`);
  }
  if (
    s.empires < 2 ||
    s.systems < s.empires * 2 ||
    s.fleetsPerEmpire < 2 ||
    s.shipsPerEmpire < s.fleetsPerEmpire
  )
    throw new Error('Scenario needs systems, empires and nonempty fleets');
  if (
    s.battleCount * 2 > s.empires ||
    s.battleFleetsPerSide < 1 ||
    s.battleFleetsPerSide >= s.fleetsPerEmpire
  )
    throw new Error('Battles need distinct empire pairs and reserve fleets');
  if (s.cohortsPerColony < 1 || s.popsPerCohort < 1) throw new Error('Population must be positive');
  if (s.empires * s.shipsPerEmpire > 0xffff_fffe || s.empires * s.fleetsPerEmpire > 0xffff_fffe)
    throw new Error('Scenario exceeds the current ID address space');
}

export function seededRandom(seed: number) {
  let state = seed >>> 0;
  return () => {
    state += 0x6d2b79f5;
    let n = Math.imul(state ^ (state >>> 15), 1 | state);
    n ^= n + Math.imul(n ^ (n >>> 7), 61 | n);
    return ((n ^ (n >>> 14)) >>> 0) / 4294967296;
  };
}

export interface Fighter {
  shipId: number;
  battleId: number;
  fleetId: number;
  empireId: number;
  side: number;
  x: number;
  y: number;
  vx: number;
  vy: number;
  targetId: number;
  hull: number;
  shield: number;
  armor: number;
  damage: number;
  cooldown: number;
  nextFireAt: number;
  maneuver: string;
}

/** Effective HP loss after armor/overkill, at the precision stored by the server. */
export function effectiveHpLost(
  before: { hull: number; shield: number },
  after: { hull: number; shield: number },
) {
  return (
    Math.max(0, before.hull - Math.max(0, Math.fround(after.hull))) +
    Math.max(0, before.shield - Math.max(0, Math.fround(after.shield)))
  );
}

/** Linear target assignment and simultaneous damage; no all-pairs ship search. */
export function combatStep(rows: Fighter[], at: number, dt: number) {
  const alive = rows.filter((r) => r.hull > 0);
  const sides = [alive.filter((r) => r.side === 0), alive.filter((r) => r.side === 1)];
  const byId = new Map(alive.map((r) => [r.shipId, r]));
  const damage = new Map<number, number>();
  const updated = alive.map((r, i) => {
    const enemy = sides[1 - r.side];
    const oldTarget = byId.get(r.targetId);
    const target = oldTarget && oldTarget.side !== r.side ? oldTarget : enemy[i % enemy.length];
    const next = { ...r, targetId: target?.shipId ?? 0, x: r.x + r.vx * dt, y: r.y + r.vy * dt };
    if (Math.abs(next.x) > 180) next.vx *= -1;
    if (Math.abs(next.y) > 100) next.vy *= -1;
    if (target && at >= r.nextFireAt) {
      damage.set(target.shipId, (damage.get(target.shipId) ?? 0) + r.damage);
      next.nextFireAt = at + r.cooldown;
    }
    return next;
  });
  const killed: Fighter[] = [];
  for (const r of updated) {
    const hit = damage.get(r.shipId) ?? 0;
    const shieldHit = Math.min(r.shield, hit);
    r.shield -= shieldHit;
    r.hull = Math.max(0, r.hull - Math.max(0, hit - shieldHit) * (1 - r.armor));
    if (r.hull === 0) killed.push(r);
  }
  return { updated, killed, hits: damage.size };
}
