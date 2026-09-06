import { Range } from 'spacetimedb/server';
import { combatStep, effectiveHpLost } from '../../backend/domain';
import { ensureBattleReport, publishBattleReport, recordBattleDamage } from './battle-reports';
import { gameStrategic, gameEconomy } from './game-ticks';
import { gameAI } from './game-ai';
import { db, strategicSchedule, economySchedule, combatSchedule, aiSchedule, type Context } from './tables';
import { finishBattle, move, NEVER, now, refreshJob, shipTemplate, tickAt, wallNow } from './rules';

const due = (at: number) =>
  new Range<bigint>({ tag: 'included', value: 0n }, { tag: 'included', value: tickAt(at) });
function record(ctx: Context, name: string, rows: number, interval: number, lag = 0, nextGameAt?: number) {
  const r = ctx.db.runtime.name.find(name)!;
  const lastLagMs = Math.max(lag * 1000, (wallNow(ctx) - r.lastWallAt - interval) * 1000, 0);
  ctx.db.runtime.name.update({
    ...r,
    calls: r.calls + 1,
    lastWallAt: wallNow(ctx),
    rowsChanged: r.rowsChanged + BigInt(rows),
    lastLagMs,
    maxLagMs: Math.max(r.maxLagMs, lastLagMs),
    nextGameAt: nextGameAt ?? r.nextGameAt,
  });
}
const active = (ctx: Context) =>
  ctx.db.scenario.id.find(1)?.phase === 'ready' && !ctx.db.clock.id.find(1)!.paused;

export const strategicTick = db.reducer(
  { onSchedule: strategicSchedule },
  { arg: strategicSchedule.rowType },
  (ctx) => {
    if (!active(ctx)) return;
    if (ctx.db.gameSettings.id.find(1)) {
      gameStrategic(ctx);
      return;
    }
    const at = now(ctx);
    const clock = ctx.db.clock.id.find(1)!;
    if (wallNow(ctx) - clock.wallTime >= 1)
      ctx.db.clock.id.update({ ...clock, gameTime: at, wallTime: wallNow(ctx) });
    let writes = 0,
      lag = 0;
    for (const arrival of [...ctx.db.arrival.dueTick.filter(due(at))]) {
      const f = ctx.db.fleet.id.find(arrival.fleetId);
      ctx.db.arrival.fleetId.delete(arrival.fleetId);
      if (!f || f.battleId || !f.route.length) continue;
      lag = Math.max(lag, at - f.arrivesAt);
      const updated = {
        ...f,
        systemId: f.route[0],
        route: [],
        fromX: f.toX,
        fromY: f.toY,
        departedAt: f.arrivesAt,
        order: 'idle',
        revision: f.revision + 1,
      };
      ctx.db.fleet.id.update(updated);
      if (f.route.length > 1) move(ctx, updated, f.route.slice(1), f.arrivesAt);
      writes += f.route.length > 1 ? 4 : 2;
    }
    for (const candidate of [...ctx.db.job.dueTick.filter(due(at))]) {
      const j = ctx.db.job.id.find(candidate.id)!;
      if (j.status !== 'active' || j.dueTick > tickAt(at)) continue;
      const e = ctx.db.empire.id.find(j.empireId)!;
      if (j.kind === 'research') {
        ctx.db.empire.id.update({
          ...e,
          researchLevel: e.researchLevel + 1,
          productionModifier: e.productionModifier + 0.05,
        });
        for (const project of ctx.db.job.empireId.filter(e.id)) {
          if (project.id !== j.id && project.status === 'active')
            refreshJob(ctx, project.id, 1 + (e.researchLevel + 1) * 0.05, at);
        }
      }
      if (j.kind === 'construction') {
        const f = ctx.db.fleet.id.find(j.targetId);
        if (f && !f.battleId && f.empireId === e.id && ctx.db.colony.id.find(f.systemId)?.empireId === e.id) {
          ctx.db.ship.insert(shipTemplate(e.id, f.id, j.id + e.seededShips));
          ctx.db.fleet.id.update({ ...f, shipCount: f.shipCount + 1, revision: f.revision + 1 });
        } else {
          // A destroyed/in-combat destination does not silently consume the completed ship.
          const home = [...ctx.db.colony.empireId.filter(e.id)][0];
          if (!home) {
            ctx.db.job.id.update({
              ...j,
              workDone: j.workTotal,
              updatedAt: at,
              dueTick: tickAt(at + 4),
              status: 'active',
            });
            continue;
          }
          const system = ctx.db.star.id.find(home.id)!;
          const replacement = ctx.db.fleet.insert({
            id: 0,
            empireId: e.id,
            name: `Werft ${j.id}`,
            systemId: system.id,
            shipCount: 1,
            formation: 'wedge',
            order: 'idle',
            battleId: 0,
            route: [],
            fromX: system.x,
            fromY: system.y,
            toX: system.x,
            toY: system.y,
            departedAt: at,
            arrivesAt: at,
            speed: 65,
            revision: 0,
          });
          ctx.db.ship.insert(shipTemplate(e.id, replacement.id, j.id + e.seededShips));
        }
      }
      ctx.db.job.id.update({
        ...j,
        workDone: j.workTotal,
        updatedAt: at,
        dueTick: NEVER,
        status: 'complete',
      });
      writes += 3;
    }
    record(ctx, 'strategic', writes, 0.25, lag);
  },
);

export const economyTick = db.reducer(
  { onSchedule: economySchedule },
  { arg: economySchedule.rowType },
  (ctx) => {
    if (!active(ctx)) return;
    if (ctx.db.gameSettings.id.find(1)) {
      gameEconomy(ctx);
      return;
    }
    const at = now(ctx);
    const runtime = ctx.db.runtime.name.find('economy')!;
    if (at < runtime.nextGameAt) return;
    // Whole production cycles preserve missed income without replaying one write per pop per tick.
    const cycles = Math.floor((at - runtime.nextGameAt) / 4) + 1;
    const producedAt = runtime.nextGameAt + (cycles - 1) * 4;
    let writes = 0;
    for (const e of ctx.db.empire.iter()) {
      let energy = 0,
        minerals = 0,
        science = 0;
      for (const c of ctx.db.colony.empireId.filter(e.id)) {
        energy += c.energyRate;
        minerals += c.mineralsRate;
        science += c.scienceRate;
        ctx.db.colony.id.update({ ...c, lastProducedAt: producedAt });
        writes++;
      }
      for (const route of ctx.db.trade.empireId.filter(e.id)) {
        if (route.status !== 'active') continue;
        energy += route.energyPerCycle;
        ctx.db.trade.id.update({ ...route, deliveredAt: producedAt });
        writes++;
      }
      ctx.db.empire.id.update({
        ...e,
        energy: e.energy + energy * cycles * e.productionModifier,
        minerals: e.minerals + minerals * cycles * e.productionModifier,
        science: e.science + science * cycles * e.productionModifier,
      });
      writes++;
      for (const d of ctx.db.decision.empireId.filter(e.id)) {
        if (d.phase === 'pending' && d.deadlineAt <= producedAt) {
          ctx.db.decision.id.update({ ...d, phase: 'resolved', outcome: 'observe' });
          writes++;
        }
      }
    }
    for (const treaty of ctx.db.treaty.iter())
      if (treaty.status === 'active' && treaty.expiresAt <= producedAt) {
        ctx.db.treaty.id.update({ ...treaty, status: 'expired' });
        writes++;
      }
    const crisis = ctx.db.crisis.id.find(1)!;
    if (crisis.phase !== 'contained' && crisis.nextPhaseAt <= producedAt) {
      const phase =
        crisis.phase === 'dormant' ? 'warning' : crisis.phase === 'warning' ? 'active' : 'contained';
      ctx.db.crisis.id.update({ ...crisis, phase, nextPhaseAt: producedAt + 120 });
      writes++;
    }
    record(
      ctx,
      'economy',
      writes,
      4 / ctx.db.clock.id.find(1)!.speed,
      at - runtime.nextGameAt,
      producedAt + 4,
    );
  },
);

export const combatTick = db.reducer(
  { onSchedule: combatSchedule },
  { arg: combatSchedule.rowType },
  (ctx) => {
    if (!active(ctx)) return;
    const at = now(ctx),
      production = !!ctx.db.gameSettings.id.find(1);
    let writes = 0,
      lag = 0;
    for (const initial of ctx.db.battle.state.filter('active')) {
      let b = initial;
      // Bounded catch-up: keep the remaining backlog visible in metrics, never discard battle time.
      for (let catchup = 0; catchup < 4 && at - b.simulatedAt >= 0.2 - 1e-8; catchup++) {
        const stepAt = b.simulatedAt + 0.2;
        const fighters = [...ctx.db.participant.battleId.filter(b.id)];
        ensureBattleReport(ctx, b, fighters, wallNow(ctx));
        const result = combatStep(fighters, stepAt, 0.2);
        const previous = new Map(fighters.map((p) => [p.shipId, p]));
        const fleetLosses = new Map<number, number>();
        const killedIds = new Set(result.killed.map((p) => p.shipId));
        let attackerLosses = b.attackerLosses,
          defenderLosses = b.defenderLosses;
        let attackerDamage = 0,
          defenderDamage = 0;
        for (const p of result.updated) {
          const old = previous.get(p.shipId)!;
          if (
            production &&
            (p.hull !== old.hull || p.shield !== old.shield) &&
            !ctx.db.gameDamaged.id.find(p.shipId)
          )
            ctx.db.gameDamaged.insert({ id: p.shipId, fleetId: p.fleetId });
          if (p.side === 0) defenderDamage += effectiveHpLost(old, p);
          else attackerDamage += effectiveHpLost(old, p);
          if (p.hull <= 0) {
            ctx.db.participant.shipId.delete(p.shipId);
            ctx.db.ship.id.delete(p.shipId);
            fleetLosses.set(p.fleetId, (fleetLosses.get(p.fleetId) ?? 0) + 1);
            if (p.side === 0) attackerLosses++;
            else defenderLosses++;
            writes += 2;
          } else {
            if (killedIds.has(p.targetId)) p.targetId = 0;
            ctx.db.participant.shipId.update(p);
            writes++;
            if (p.hull !== old.hull || p.shield !== old.shield) {
              const s = ctx.db.ship.id.find(p.shipId)!;
              ctx.db.ship.id.update({ ...s, hull: p.hull, shield: p.shield });
              writes++;
            }
          }
        }
        for (const [id, loss] of fleetLosses) {
          const f = ctx.db.fleet.id.find(id)!;
          ctx.db.fleet.id.update({ ...f, shipCount: f.shipCount - loss, revision: f.revision + 1 });
          writes++;
        }
        b = { ...b, simulatedAt: stepAt, step: b.step + 1, attackerLosses, defenderLosses };
        ctx.db.battle.id.update(b);
        recordBattleDamage(ctx, b.id, attackerDamage, defenderDamage);
        writes++;
        if (finishBattle(ctx, b.id, stepAt)) break;
        if (wallNow(ctx) >= ctx.db.battleReport.id.find(b.id)!.nextPublishWallAt)
          publishBattleReport(ctx, b, [...ctx.db.participant.battleId.filter(b.id)], wallNow(ctx));
      }
      lag = Math.max(lag, at - b.simulatedAt - 0.2);
    }
    record(ctx, 'combat', writes, 0.1, lag);
  },
);

export const aiTick = db.reducer({ onSchedule: aiSchedule }, { arg: aiSchedule.rowType }, (ctx) => {
  if (!active(ctx)) return;
  if (ctx.db.gameSettings.id.find(1)) {
    gameAI(ctx);
    return;
  }
  const at = now(ctx);
  let writes = 0,
    processed = 0,
    lag = 0;
  // At most four planners per invocation. Each empire has its own durable next-decision deadline.
  for (const e of ctx.db.empire.nextDecisionTick.filter(due(at))) {
    if (processed++ >= 4) break;
    lag = Math.max(lag, at - Number(e.nextDecisionTick) / 1000);
    if (!e.ai) continue;
    const systems = [...ctx.db.star.ownerId.filter(e.id)];
    const fleets = [...ctx.db.fleet.empireId.filter(e.id)].sort((a, b) => a.id - b.id);
    for (let i = 0; i < Math.min(8, fleets.length); i++) {
      const f = fleets[(e.aiCursor + i) % fleets.length];
      if (!f.battleId && f.systemId && !f.route.length && systems.length > 1) {
        let target = systems[(e.aiCursor + i + 1) % systems.length];
        if (target.id === f.systemId) target = systems[(e.aiCursor + i + 2) % systems.length];
        move(ctx, f, [target.id], at);
        writes += 2;
      }
    }
    ctx.db.empire.id.update({ ...e, nextDecisionTick: tickAt(at + 5), aiCursor: e.aiCursor + 8 });
    writes++;
  }
  record(ctx, 'ai', writes, 0.2, lag);
});
