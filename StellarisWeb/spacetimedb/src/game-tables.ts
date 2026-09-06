import { table, t } from 'spacetimedb/server';

// Additive production schema. Lab databases keep their existing rules and rows.
export const gameSettings = table(
  { public: true },
  {
    id: t.u32().primaryKey(),
    code: t.string(),
    hostId: t.u32(),
    winnerId: t.u32(),
    capacity: t.u32(),
    autoPaused: t.bool(),
    migrationKey: t.string(),
  },
);
export const gamePlayer = table(
  {},
  {
    id: t.u32().primaryKey(),
    externalId: t.string().unique(),
    homeId: t.u32(),
    techs: t.array(t.string()),
    surveyed: t.array(t.u32()),
    discovered: t.array(t.u32()),
    empireJson: t.string(),
    joinedAt: t.f64(),
  },
);
export const gamePresence = table({ public: true }, { id: t.u32().primaryKey(), online: t.bool() });
export const gameConnection = table(
  {},
  {
    id: t.string().primaryKey(),
    identity: t.identity().index('btree'),
    empireId: t.u32().index('btree'),
  },
);
export const gameTicket = table(
  {},
  {
    ticket: t.string().primaryKey(),
    empireId: t.u32(),
    expiresAt: t.f64(),
  },
);
export const gameSystem = table(
  {},
  {
    id: t.u32().primaryKey(),
    externalId: t.string().unique(),
    color: t.string(),
    starClass: t.string(),
    planet: t.string(),
    energy: t.f64(),
    minerals: t.f64(),
    science: t.f64(),
    defense: t.f64(),
    mined: t.bool(),
    anomaly: t.bool(),
    studied: t.bool(),
    colonyName: t.string(),
    colonyJson: t.string(),
    growthAt: t.f64(),
  },
);
export const gameLane = table(
  { public: true },
  {
    id: t.u32().primaryKey().autoInc(),
    a: t.u32().index('btree'),
    b: t.u32().index('btree'),
  },
);
export const gameFleet = table(
  {},
  {
    id: t.u32().primaryKey(),
    externalId: t.string().unique(),
    kind: t.string(),
    lastSystemId: t.u32(),
    retreatUntil: t.f64(),
  },
);
export const gameEvent = table(
  {},
  {
    id: t.u32().primaryKey().autoInc(),
    empireId: t.u32().index('btree'),
    tick: t.f64(),
    text: t.string(),
    tone: t.string(),
  },
);
export const gameDamaged = table({}, { id: t.u32().primaryKey(), fleetId: t.u32().index('btree') });
export const gameFleetCondition = table(
  {},
  { id: t.u32().primaryKey(), hull: t.f64(), maxHull: t.f64(), shield: t.f64() },
);
export const gameIncome = table({}, { id: t.u32().primaryKey(), producedAt: t.f64() });
// Relations are public strategic facts; offer terms remain private to both participants.
export const gameRelation = table(
  { public: true },
  {
    id: t.string().primaryKey(),
    empireA: t.u32(),
    empireB: t.u32(),
    state: t.string(),
    truceUntil: t.f64(),
    changedAt: t.f64(),
  },
);
const resources = t.object('DiplomaticResources', { energy: t.f64(), minerals: t.f64(), science: t.f64() });
export const gameOffer = table(
  {},
  {
    id: t.u32().primaryKey(),
    give: resources,
    receive: resources,
    createdAt: t.f64(),
  },
);
export const gameStory = table(
  {},
  {
    id: t.u32().primaryKey(),
    sourceKey: t.string().unique(),
    systemId: t.u32(),
    createdAt: t.f64(),
    resolvedAt: t.f64(),
    result: t.string(),
  },
);
export const gameCrisis = table(
  { public: true },
  {
    id: t.u32().primaryKey(),
    kind: t.string(),
    target: t.u32(),
    progress: t.u32(),
    startedAt: t.f64(),
    endedAt: t.f64(),
  },
);
export const gameCrisisPledge = table(
  {},
  {
    id: t.string().primaryKey(),
    crisisId: t.u32().index('btree'),
    empireId: t.u32().index('btree'),
    contributions: t.u32(),
    shielded: t.bool(),
  },
);
export const gameSite = table(
  {},
  {
    id: t.string().primaryKey(),
    systemId: t.u32().index('btree'),
    bodySlot: t.u32(),
    empireId: t.u32().index('btree'),
    facility: t.string(),
    level: t.u32(),
    building: t.bool(),
    startedAt: t.f64(),
    finishAt: t.f64(),
    finishTick: t.u64().index('btree'),
    paidEnergy: t.f64(),
    paidMinerals: t.f64(),
    lastProducedAt: t.f64(),
  },
);
export const gameTables = {
  gameSite,
  gameStory,
  gameCrisis,
  gameCrisisPledge,
  gameRelation,
  gameOffer,
  gameSettings,
  gamePlayer,
  gamePresence,
  gameConnection,
  gameTicket,
  gameSystem,
  gameLane,
  gameFleet,
  gameEvent,
  gameDamaged,
  gameFleetCondition,
  gameIncome,
};
