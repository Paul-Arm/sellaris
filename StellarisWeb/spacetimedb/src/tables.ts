import { resourceFields } from './resource-schema';
import {
  schema,
  table,
  t,
  type Infer,
  type InferSchema,
  type ReducerCtx,
  type ViewCtx,
} from 'spacetimedb/server';
import { gameTables } from './game-tables';

export const scenario = table(
  { public: true },
  {
    id: t.u32().primaryKey(),
    seed: t.u32(),
    systems: t.u32(),
    empires: t.u32(),
    fleetsPerEmpire: t.u32(),
    shipsPerEmpire: t.u32(),
    battleCount: t.u32(),
    battleFleetsPerSide: t.u32(),
    cohortsPerColony: t.u32(),
    popsPerCohort: t.u32(),
    seededShips: t.u32(),
    phase: t.string(),
    schemaVersion: t.u32(),
  },
);
const administrator = table({}, { id: t.u32().primaryKey(), identity: t.identity() });
export const clock = table(
  { public: true },
  {
    id: t.u32().primaryKey(),
    gameTime: t.f64(),
    wallTime: t.f64(),
    speed: t.f64(),
    paused: t.bool(),
  },
);
export const star = table(
  { public: true },
  {
    id: t.u32().primaryKey(),
    name: t.string(),
    x: t.f32(),
    y: t.f32(),
    kind: t.string(),
    ownerId: t.u32().index('btree'),
  },
);
export const empireSummary = table(
  { public: true },
  { id: t.u32().primaryKey(), name: t.string(), color: t.u32(), ai: t.bool() },
);
export const empire = table(
  {},
  {
    id: t.u32().primaryKey(),
    ...resourceFields(),
    productionModifier: t.f64(),
    researchLevel: t.u32(),
    ai: t.bool(),
    nextDecisionTick: t.u64().index('btree'),
    aiCursor: t.u32(),
    seededShips: t.u32(),
  },
);
const membership = table({}, { identity: t.identity().primaryKey(), empireId: t.u32().unique() });
const commandQuota = table({}, { identity: t.identity().primaryKey(), windowAt: t.f64(), calls: t.u32() });
const focus = table({}, { identity: t.identity().primaryKey(), fleetId: t.u32(), battleId: t.u32() });
export const fleet = table(
  {},
  {
    id: t.u32().primaryKey().autoInc(),
    empireId: t.u32().index('btree'),
    name: t.string(),
    systemId: t.u32().index('btree'),
    shipCount: t.u32(),
    formation: t.string(),
    order: t.string(),
    battleId: t.u32().index('btree'),
    route: t.array(t.u32()),
    fromX: t.f32(),
    fromY: t.f32(),
    toX: t.f32(),
    toY: t.f32(),
    departedAt: t.f64(),
    arrivesAt: t.f64(),
    speed: t.f32(),
    revision: t.u32(),
  },
);
// A due-time index avoids scanning fleets, much less ships, on every strategic pulse.
const arrival = table({}, { fleetId: t.u32().primaryKey(), dueTick: t.u64().index('btree') });
const weapon = t.object('Weapon', { kind: t.string(), damage: t.f32(), range: t.f32(), cooldown: t.f32() });
export const ship = table(
  {},
  {
    id: t.u32().primaryKey().autoInc(),
    empireId: t.u32().index('btree'),
    fleetId: t.u32().index('btree'),
    name: t.string(),
    design: t.string(),
    hull: t.f32(),
    maxHull: t.f32(),
    shield: t.f32(),
    maxShield: t.f32(),
    armor: t.f32(),
    experience: t.u32(),
    reactor: t.string(),
    drive: t.string(),
    abilities: t.array(t.string()),
    weapons: t.array(weapon),
  },
);
export const colony = table(
  {},
  {
    id: t.u32().primaryKey(),
    empireId: t.u32().index('btree'),
    population: t.u32(),
    monthlyProduction: t.object('MonthlyProduction', resourceFields()),
    lastProducedAt: t.f64(),
  },
);
export const cohort = table(
  {},
  {
    id: t.u32().primaryKey().autoInc(),
    colonyId: t.u32().index('btree'),
    empireId: t.u32().index('btree'),
    species: t.string(),
    job: t.string(),
    count: t.u32(),
    productivity: t.f32(),
    happiness: t.f32(),
  },
);
export const job = table(
  {},
  {
    id: t.u32().primaryKey().autoInc(),
    empireId: t.u32().index('btree'),
    kind: t.string().index('btree'),
    topic: t.string(),
    targetId: t.u32(),
    workDone: t.f64(),
    workTotal: t.f64(),
    rate: t.f64(),
    updatedAt: t.f64(),
    dueTick: t.u64().index('btree'),
    status: t.string().index('btree'),
  },
);
export const battle = table(
  {},
  {
    id: t.u32().primaryKey().autoInc(),
    systemId: t.u32().index('btree'),
    state: t.string().index('btree'),
    attackers: t.u32().index('btree'),
    defenders: t.u32().index('btree'),
    startedAt: t.f64(),
    simulatedAt: t.f64(),
    step: t.u32(),
    attackerLosses: t.u32(),
    defenderLosses: t.u32(),
    winnerId: t.u32(),
  },
);
export const participant = table(
  {},
  {
    shipId: t.u32().primaryKey(),
    battleId: t.u32().index('btree'),
    fleetId: t.u32().index('btree'),
    empireId: t.u32(),
    side: t.u32(),
    x: t.f32(),
    y: t.f32(),
    vx: t.f32(),
    vy: t.f32(),
    targetId: t.u32(),
    hull: t.f32(),
    shield: t.f32(),
    armor: t.f32(),
    damage: t.f32(),
    cooldown: t.f32(),
    nextFireAt: t.f64(),
    maneuver: t.string(),
  },
);
const battleSide = t.object('BattleSideSummary', {
  ships: t.u32(),
  hull: t.f64(),
  shield: t.f64(),
  startingHull: t.f64(),
  startingShield: t.f64(),
  damageDealt: t.f64(),
});
export const battleSummaryFields = {
  id: t.u32(),
  systemId: t.u32(),
  state: t.string(),
  attackers: t.u32(),
  defenders: t.u32(),
  winnerId: t.u32(),
  sampledAt: t.f64(),
  startedAt: t.f64(),
  attackerLosses: t.u32(),
  defenderLosses: t.u32(),
  attacker: battleSide,
  defender: battleSide,
};
// Live accounting stays private. Only the frozen report is exposed to overviews.
export const battleReport = table(
  {},
  {
    id: t.u32().primaryKey(),
    systemId: t.u32().index('btree'),
    attackers: t.u32().index('btree'),
    defenders: t.u32().index('btree'),
    attackerDamage: t.f64(),
    defenderDamage: t.f64(),
    nextPublishWallAt: t.f64(),
    report: t.object('BattleSummarySnapshot', battleSummaryFields),
  },
);
// Durable extension points: these deadlines and phases survive disconnects/restarts.
export const treaty = table(
  {},
  {
    id: t.u32().primaryKey().autoInc(),
    empireA: t.u32().index('btree'),
    empireB: t.u32().index('btree'),
    kind: t.string(),
    status: t.string(),
    expiresAt: t.f64(),
  },
);
export const decision = table(
  {},
  {
    id: t.u32().primaryKey().autoInc(),
    empireId: t.u32().index('btree'),
    kind: t.string(),
    phase: t.string(),
    deadlineAt: t.f64(),
    outcome: t.string(),
  },
);
export const trade = table(
  {},
  {
    id: t.u32().primaryKey().autoInc(),
    empireId: t.u32().index('btree'),
    fromSystem: t.u32(),
    toSystem: t.u32(),
    monthlyEnergy: t.f64(),
    deliveredAt: t.f64(),
    status: t.string(),
  },
);
export const crisis = table(
  { public: true },
  { id: t.u32().primaryKey(), systemId: t.u32(), phase: t.string(), nextPhaseAt: t.f64() },
);
export const runtime = table(
  {},
  {
    name: t.string().primaryKey(),
    lastWallAt: t.f64(),
    nextGameAt: t.f64(),
    calls: t.u32(),
    rowsChanged: t.u64(),
    lastLagMs: t.f64(),
    maxLagMs: t.f64(),
  },
);
export const strategicSchedule = table(
  {},
  { id: t.u64().primaryKey().autoInc(), scheduledAt: t.scheduleAt() },
);
export const economySchedule = table({}, { id: t.u64().primaryKey().autoInc(), scheduledAt: t.scheduleAt() });
export const combatSchedule = table({}, { id: t.u64().primaryKey().autoInc(), scheduledAt: t.scheduleAt() });
export const aiSchedule = table({}, { id: t.u64().primaryKey().autoInc(), scheduledAt: t.scheduleAt() });

export const db = schema({
  ...gameTables,
  scenario,
  administrator,
  clock,
  star,
  empireSummary,
  empire,
  membership,
  commandQuota,
  focus,
  fleet,
  arrival,
  ship,
  colony,
  cohort,
  job,
  battle,
  participant,
  battleReport,
  treaty,
  decision,
  trade,
  crisis,
  runtime,
  strategicSchedule,
  economySchedule,
  combatSchedule,
  aiSchedule,
});
export type Context = ReducerCtx<InferSchema<typeof db>>;
export type ReadContext = ViewCtx<InferSchema<typeof db>>;
export type Fleet = Infer<typeof fleet.rowType>;
export type Ship = Infer<typeof ship.rowType>;
export type Battle = Infer<typeof battle.rowType>;
