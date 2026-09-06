import { colonyRepair } from '../../shared/colonies';
import { WIN_SYSTEMS } from '../../shared/game';
import { maxDefense } from '../../shared/colonies';
import { progressAt } from '../../backend/domain';
import { type Context } from './tables';
import { enterBattle, move, NEVER, now, clockNow, tickAt, wallNow } from './rules';
import {
  dueJobs,
  event,
  refreshFleetCondition,
  settleEconomy,
  settlePopulation,
  systemModel,
  updateColony,
} from './game-model';
import { gameClock } from './game-world';
import { completeGameJob, contested, destroyGameFleet } from './game-jobs';
import { atWar } from './game-relations';
import { expireDiplomacy } from './game-diplomacy';
import { storyTick } from './game-stories';
import { completeSites } from './game-sites';
import { completeTerraforming } from './game-terraforming';
import { navigationTick } from './game-navigation';

function checkBattle(ctx: Context, systemId: number, at: number) {
  const present = [...ctx.db.fleet.systemId.filter(systemId)].filter(
    (f) => !f.battleId && f.shipCount && ctx.db.gameFleet.id.find(f.id)!.retreatUntil <= at,
  );
  if ([...ctx.db.battle.systemId.filter(systemId)].some((b) => b.state === 'active')) return;
  const aggressor = present.find(
    (f) =>
      ctx.db.gameFleet.id.find(f.id)?.kind === 'corvette' &&
      present.some((other) => atWar(ctx, f.empireId, other.empireId)),
  );
  if (!aggressor) return;
  const enemy = present.find((f) => atWar(ctx, f.empireId, aggressor.empireId));
  if (!enemy) return;
  const ids = present
    .filter((f) => [aggressor.empireId, enemy.empireId].includes(f.empireId))
    .map((f) => f.id);
  const battle = enterBattle(ctx, ids, systemId, at);
  for (const id of ids) {
    const n = ctx.db.gameNavigation.id.find(id);
    if (n && n.ordersJson !== '[]') ctx.db.gameNavigation.id.update({ ...n, dueTick: tickAt(at) });
  }
  for (const owner of [battle.attackers, battle.defenders])
    event(ctx, owner, `Gefecht ${battle.id} bei ${ctx.db.star.id.find(systemId)!.name}.`, 'warning');
}
export function gameStrategic(ctx: Context) {
  completeTerraforming(ctx);
  completeSites(ctx);
  const at = now(ctx),
    clock = ctx.db.clock.id.find(1)!;
  if (wallNow(ctx) - clock.wallTime >= 1)
    ctx.db.clock.id.update({ ...clock, gameTime: clockNow(ctx), wallTime: wallNow(ctx) });
  for (const a of [...ctx.db.arrival.dueTick.filter(dueJobs(at))]) {
    const f = ctx.db.fleet.id.find(a.fleetId);
    ctx.db.arrival.fleetId.delete(a.fleetId);
    if (!f || !f.route.length || f.battleId) continue;
    const id = f.route[0],
      m = ctx.db.gameFleet.id.find(f.id)!,
      info = ctx.db.gameSystem.id.find(id)!;
    const arrived = {
      ...f,
      systemId: id,
      route: [],
      fromX: f.toX,
      fromY: f.toY,
      departedAt: f.arrivesAt,
      order: 'idle',
      revision: f.revision + 1,
    };
    ctx.db.fleet.id.update(arrived);
    ctx.db.gameFleet.id.update({ ...m, lastSystemId: id });
    if (f.route.length > 1 && (!info.defense || !atWar(ctx, ctx.db.star.id.find(id)!.ownerId, f.empireId)))
      move(ctx, arrived, f.route.slice(1), f.arrivesAt);
    else {
      event(ctx, f.empireId, `${f.name} erreicht ${ctx.db.star.id.find(id)!.name}.`);
      checkBattle(ctx, id, at);
    }
  }
  for (const kind of ['game_scan', 'game_colonize'])
    for (const j of ctx.db.job.kind.filter(kind)) {
      if (kind === 'game_scan' && ctx.db.gameNavigation.id.find(j.targetId)?.phase.includes('survey'))
        continue;
      if (!['active', 'blocked'].includes(j.status)) continue;
      const f = ctx.db.fleet.id.find(j.targetId);
      if (!f) {
        ctx.db.job.id.update({ ...j, status: 'cancelled', dueTick: NEVER });
        continue;
      }
      const blocked = !!f.battleId || contested(ctx, f.systemId, j.empireId);
      if (blocked && j.status === 'active')
        ctx.db.job.id.update({
          ...j,
          status: 'blocked',
          workDone: Math.min(j.workTotal, progressAt(j, at)),
          updatedAt: at,
          dueTick: NEVER,
        });
      else if (!blocked && j.status === 'blocked')
        ctx.db.job.id.update({
          ...j,
          status: 'active',
          updatedAt: at,
          dueTick: tickAt(at + (j.workTotal - j.workDone) / j.rate),
        });
    }
  for (const j of [...ctx.db.job.dueTick.filter(dueJobs(at))])
    if (j.status === 'active' && j.kind.startsWith('game_')) completeGameJob(ctx, j, at);
  navigationTick(ctx);
  const config = ctx.db.gameSettings.id.find(1)!;
  for (const p of ctx.db.gamePlayer.iter())
    if ([...ctx.db.colony.empireId.filter(p.id)].length >= WIN_SYSTEMS) {
      ctx.db.gameSettings.id.update({ ...config, winnerId: p.id });
      event(ctx, 0, `${ctx.db.empireSummary.id.find(p.id)!.name} gewinnt die Galaxie!`, 'success');
      gameClock(ctx, true);
      break;
    }
}
export function gameEconomy(ctx: Context) {
  const at = now(ctx),
    runtime = ctx.db.runtime.name.find('economy')!,
    dt = Math.max(0, Math.min(4, at - runtime.nextGameAt));
  if (at <= runtime.nextGameAt) return;
  expireDiplomacy(ctx, at);
  storyTick(ctx);
  for (const p of ctx.db.gamePlayer.iter()) {
    settleEconomy(ctx, p.id, at);
    for (const c of ctx.db.colony.empireId.filter(p.id)) settlePopulation(ctx, c.id, at);
  }
  const occupied = new Set<number>();
  for (const f of ctx.db.fleet.iter())
    if (f.systemId && ctx.db.gameFleet.id.find(f.id)?.kind === 'corvette') occupied.add(f.systemId);
  for (const id of occupied) {
    checkBattle(ctx, id, at);
    const s = ctx.db.star.id.find(id)!,
      m = ctx.db.gameSystem.id.find(id)!;
    if (m.defense <= 0) continue;
    const attacking = [...ctx.db.fleet.systemId.filter(id)].filter(
      (f) =>
        !f.battleId &&
        atWar(ctx, f.empireId, s.ownerId) &&
        ctx.db.gameFleet.id.find(f.id)?.kind === 'corvette',
    );
    if (!attacking.length) continue;
    let damage = 0;
    const count = Math.max(
      1,
      attacking.reduce((n, a) => n + a.shipCount, 0),
    );
    for (const f of attacking)
      for (const ship of ctx.db.ship.fleetId.filter(f.id)) {
        damage += ship.weapons.reduce((n, w) => n + w.damage, 0) * 1.5 * dt;
        const hull = Math.max(0, ship.hull - (4 * dt) / count);
        if (hull <= 0) ctx.db.ship.id.delete(ship.id);
        else {
          ctx.db.ship.id.update({ ...ship, hull });
          if (!ctx.db.gameDamaged.id.find(ship.id)) ctx.db.gameDamaged.insert({ id: ship.id, fleetId: f.id });
        }
      }
    for (const f of attacking) {
      const shipCount = [...ctx.db.ship.fleetId.filter(f.id)].length;
      if (!shipCount) destroyGameFleet(ctx, f.id);
      else {
        ctx.db.fleet.id.update({ ...f, shipCount });
        refreshFleetCondition(ctx, f.id);
      }
    }
    const defense = Math.max(0, m.defense - damage);
    ctx.db.gameSystem.id.update({ ...m, defense });
    if (defense === 0) {
      ctx.db.star.id.update({ ...s, ownerId: 0 });
      for (const site of ctx.db.gameSite.systemId.filter(id)) ctx.db.gameSite.id.delete(site.id);
      ctx.db.gameSystem.id.update({ ...ctx.db.gameSystem.id.find(id)!, mined: false });
      updateColony(ctx, id, null, s.ownerId);
      event(ctx, 0, `Die Verteidigung von ${s.name} ist gefallen.`, 'warning');
    }
  }
  const dirty = new Set<number>();
  for (const d of [...ctx.db.gameDamaged.iter()]) {
    const s = ctx.db.ship.id.find(d.id),
      f = s ? ctx.db.fleet.id.find(s.fleetId) : null;
    dirty.add(d.fleetId);
    if (!s || !f) {
      ctx.db.gameDamaged.id.delete(d.id);
      continue;
    }
    if (
      f.battleId ||
      !f.systemId ||
      ctx.db.star.id.find(f.systemId)?.ownerId !== f.empireId ||
      contested(ctx, f.systemId, f.empireId)
    )
      continue;
    const system = systemModel(ctx, f.systemId),
      hull = Math.min(s.maxHull, s.hull + colonyRepair(system) * dt),
      shield = Math.min(s.maxShield, s.shield + dt * 3);
    ctx.db.ship.id.update({ ...s, hull, shield });
    if (hull === s.maxHull && shield === s.maxShield) ctx.db.gameDamaged.id.delete(d.id);
  }
  for (const id of dirty) if (ctx.db.fleet.id.find(id)) refreshFleetCondition(ctx, id);
  for (const c of ctx.db.colony.iter()) {
    if (contested(ctx, c.id, c.empireId)) continue;
    const m = ctx.db.gameSystem.id.find(c.id)!,
      defense = Math.min(maxDefense(systemModel(ctx, c.id)), m.defense + dt * 0.75);
    if (defense !== m.defense) ctx.db.gameSystem.id.update({ ...m, defense });
  }
  ctx.db.runtime.name.update({
    ...runtime,
    nextGameAt: at,
    lastWallAt: wallNow(ctx),
    calls: runtime.calls + 1,
  });
}
