import { t } from 'spacetimedb/server';
import {
  db,
  empire,
  ship,
  colony,
  job,
  cohort,
  battle,
  participant,
  battleSummaryFields,
  treaty,
  decision,
  trade,
  runtime,
  type ReadContext,
} from './tables';
import { canSeeBattle, visibleSystems } from './rules';

const fleetOverview = t.row('FleetOverview', {
  id: t.u32().primaryKey(),
  empireId: t.u32(),
  name: t.string(),
  systemId: t.u32(),
  shipCount: t.u32(),
  battleId: t.u32(),
  fromX: t.f32(),
  fromY: t.f32(),
  toX: t.f32(),
  toY: t.f32(),
  departedAt: t.f64(),
  arrivesAt: t.f64(),
  revision: t.u32(),
});
export const myEmpire = db.view({ name: 'my_empire', public: true }, t.option(empire.rowType), (ctx) => {
  const m = ctx.db.membership.identity.find(ctx.sender);
  return m ? (ctx.db.empire.id.find(m.empireId) ?? undefined) : undefined;
});
export const galaxyFleets = db.view(
  { name: 'galaxy_fleets', public: true },
  t.array(fleetOverview),
  (ctx) => {
    const m = ctx.db.membership.identity.find(ctx.sender);
    if (!m) return [];
    const fleets = new Map([...ctx.db.fleet.empireId.filter(m.empireId)].map((f) => [f.id, f]));
    for (const id of visibleSystems(ctx, m.empireId))
      for (const f of ctx.db.fleet.systemId.filter(id)) fleets.set(f.id, f);
    return [...fleets.values()].map((f) => ({
      id: f.id,
      empireId: f.empireId,
      name: f.name,
      systemId: f.systemId,
      shipCount: f.shipCount,
      battleId: f.battleId,
      fromX: f.fromX,
      fromY: f.fromY,
      toX: f.toX,
      toY: f.toY,
      departedAt: f.departedAt,
      arrivesAt: f.arrivesAt,
      revision: f.revision,
    }));
  },
);
export const fleetShips = db.view({ name: 'fleet_ships', public: true }, t.array(ship.rowType), (ctx) => {
  const m = ctx.db.membership.identity.find(ctx.sender),
    focus = ctx.db.focus.identity.find(ctx.sender);
  if (!m || !focus?.fleetId) return [];
  const f = ctx.db.fleet.id.find(focus.fleetId);
  return f?.empireId === m.empireId ? [...ctx.db.ship.fleetId.filter(f.id)] : [];
});
export const myColonies = db.view({ name: 'my_colonies', public: true }, t.array(colony.rowType), (ctx) => {
  const m = ctx.db.membership.identity.find(ctx.sender);
  return m ? [...ctx.db.colony.empireId.filter(m.empireId)] : [];
});
export const myCohorts = db.view({ name: 'my_cohorts', public: true }, t.array(cohort.rowType), (ctx) => {
  const m = ctx.db.membership.identity.find(ctx.sender);
  return m ? [...ctx.db.cohort.empireId.filter(m.empireId)] : [];
});
export const myJobs = db.view({ name: 'my_jobs', public: true }, t.array(job.rowType), (ctx) => {
  const m = ctx.db.membership.identity.find(ctx.sender);
  return m ? [...ctx.db.job.empireId.filter(m.empireId)] : [];
});
export const visibleBattles = db.view(
  { name: 'visible_battles', public: true },
  t.array(battle.rowType),
  (ctx) => {
    const m = ctx.db.membership.identity.find(ctx.sender);
    if (!m) return [];
    const battles = new Map<number, typeof battle.rowType.type>();
    for (const id of visibleSystems(ctx, m.empireId))
      for (const b of ctx.db.battle.systemId.filter(id)) battles.set(b.id, b);
    for (const b of ctx.db.battle.attackers.filter(m.empireId)) battles.set(b.id, b);
    for (const b of ctx.db.battle.defenders.filter(m.empireId)) battles.set(b.id, b);
    // Historical own battle records remain available after retreat, independently of sensor visibility.
    // Active battle detail permission is evaluated again by the separate view below.
    return [...battles.values()];
  },
);
export const visibleBattleSummaries = db.view(
  { name: 'visible_battle_summaries', public: true },
  t.array(t.row('VisibleBattleSummaryProjection', { ...battleSummaryFields, id: t.u32().primaryKey() })),
  (ctx) => {
    const m = ctx.db.membership.identity.find(ctx.sender);
    if (!m) return [];
    const rows = new Map([...ctx.db.battleReport.attackers.filter(m.empireId)].map((r) => [r.id, r]));
    for (const r of ctx.db.battleReport.defenders.filter(m.empireId)) rows.set(r.id, r);
    for (const id of visibleSystems(ctx, m.empireId))
      for (const r of ctx.db.battleReport.systemId.filter(id)) rows.set(r.id, r);
    return [...rows.values()].map((r) => r.report);
  },
);
export const focusedBattle = db.view(
  { name: 'focused_battle', public: true },
  t.array(battle.rowType),
  (ctx) => {
    const m = ctx.db.membership.identity.find(ctx.sender),
      focus = ctx.db.focus.identity.find(ctx.sender);
    if (!m || !focus?.battleId || !canSeeBattle(ctx, m.empireId, focus.battleId)) return [];
    const b = ctx.db.battle.id.find(focus.battleId);
    return b ? [b] : [];
  },
);
export const battleParticipants = db.view(
  { name: 'battle_participants', public: true },
  t.array(participant.rowType),
  (ctx) => {
    const m = ctx.db.membership.identity.find(ctx.sender),
      focus = ctx.db.focus.identity.find(ctx.sender);
    return m && focus?.battleId && canSeeBattle(ctx, m.empireId, focus.battleId)
      ? [...ctx.db.participant.battleId.filter(focus.battleId)]
      : [];
  },
);

// Additive wire projections: the durable participant keeps its full simulation state.
// Movement must not resend equipment/affiliation or unchanged health/weapon state.
function focusedParticipants(ctx: ReadContext) {
  const m = ctx.db.membership.identity.find(ctx.sender);
  const focus = ctx.db.focus.identity.find(ctx.sender);
  return m && focus?.battleId && canSeeBattle(ctx, m.empireId, focus.battleId)
    ? [...ctx.db.participant.battleId.filter(focus.battleId)]
    : [];
}
export const battleRoster = db.view(
  { name: 'battle_roster', public: true },
  t.array(
    t.row('BattleRosterProjection', {
      shipId: t.u32().primaryKey(),
      battleId: t.u32(),
      fleetId: t.u32(),
      empireId: t.u32(),
      side: t.u8(),
    }),
  ),
  (ctx) =>
    focusedParticipants(ctx).map(({ shipId, battleId, fleetId, empireId, side }) => ({
      shipId,
      battleId,
      fleetId,
      empireId,
      side,
    })),
);
export const battleMotion = db.view(
  { name: 'battle_motion', public: true },
  t.array(
    t.row('BattleMotionProjection', {
      shipId: t.u32().primaryKey(),
      x: t.f32(),
      y: t.f32(),
      vx: t.f32(),
      vy: t.f32(),
    }),
  ),
  (ctx) => focusedParticipants(ctx).map(({ shipId, x, y, vx, vy }) => ({ shipId, x, y, vx, vy })),
);
export const battleVitals = db.view(
  { name: 'battle_vitals', public: true },
  t.array(
    t.row('BattleVitalsProjection', {
      shipId: t.u32().primaryKey(),
      targetId: t.u32(),
      hull: t.f32(),
      shield: t.f32(),
      nextFireAt: t.f64(),
    }),
  ),
  (ctx) =>
    focusedParticipants(ctx).map(({ shipId, targetId, hull, shield, nextFireAt }) => ({
      shipId,
      targetId,
      hull,
      shield,
      nextFireAt,
    })),
);
export const myTreaties = db.view({ name: 'my_treaties', public: true }, t.array(treaty.rowType), (ctx) => {
  const m = ctx.db.membership.identity.find(ctx.sender);
  if (!m) return [];
  return [...ctx.db.treaty.empireA.filter(m.empireId), ...ctx.db.treaty.empireB.filter(m.empireId)];
});
export const myDecisions = db.view(
  { name: 'my_decisions', public: true },
  t.array(decision.rowType),
  (ctx) => {
    const m = ctx.db.membership.identity.find(ctx.sender);
    return m ? [...ctx.db.decision.empireId.filter(m.empireId)] : [];
  },
);
export const myTrade = db.view({ name: 'my_trade', public: true }, t.array(trade.rowType), (ctx) => {
  const m = ctx.db.membership.identity.find(ctx.sender);
  return m ? [...ctx.db.trade.empireId.filter(m.empireId)] : [];
});
export const diagnostics = db.view({ name: 'diagnostics', public: true }, t.array(runtime.rowType), (ctx) => {
  if (!ctx.db.administrator.id.find(1)?.identity.isEqual(ctx.sender)) return [];
  return ['strategic', 'economy', 'combat', 'ai'].flatMap((name) => {
    const r = ctx.db.runtime.name.find(name);
    return r ? [r] : [];
  });
});
