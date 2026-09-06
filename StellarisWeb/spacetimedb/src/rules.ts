import { SenderError } from 'spacetimedb/server';
import { gameDay, dueDay } from '../../shared/time';
import { gameTimeAt, positionAt, progressAt } from '../../backend/domain';
import { type Context, type ReadContext, type Fleet, type Ship } from './tables';
import { ensureBattleReport, publishBattleReport } from './battle-reports';

export const NEVER = 0xffff_ffff_ffff_ffffn;
// Keep the durable milliday encoding readable for old saves; new deadlines land on whole days.
export const tickAt = (at: number) => BigInt(dueDay(at) * 1000);
export const wallNow = (ctx: Context) => Number(ctx.timestamp.microsSinceUnixEpoch) / 1e6;
export const clockNow = (ctx: Context) => gameTimeAt(ctx.db.clock.id.find(1)!, wallNow(ctx));
export const now = (ctx: Context) => gameDay(clockNow(ctx));
export function admin(ctx: Context) {
  if (!ctx.db.administrator.id.find(1)?.identity.isEqual(ctx.sender))
    throw new SenderError('Administrator required');
}
export function member(ctx: Context) {
  const row = ctx.db.membership.identity.find(ctx.sender);
  if (!row) throw new SenderError('Join an empire first');
  const time = wallNow(ctx);
  const quota = ctx.db.commandQuota.identity.find(ctx.sender);
  if (!quota || time - quota.windowAt >= 1) {
    const fresh = { identity: ctx.sender, windowAt: time, calls: 1 };
    if (quota) ctx.db.commandQuota.identity.update(fresh);
    else ctx.db.commandQuota.insert(fresh);
  } else {
    if (quota.calls >= 20) throw new SenderError('Command rate exceeded');
    ctx.db.commandQuota.identity.update({ ...quota, calls: quota.calls + 1 });
  }
  return row.empireId;
}
export function ownedFleet(ctx: Context, id: number, owner: number) {
  const f = ctx.db.fleet.id.find(id);
  if (!f || f.empireId !== owner) throw new SenderError('Fleet not owned');
  return f;
}
export function visibleSystems(ctx: Context | ReadContext, empireId: number) {
  const ids = new Set<number>();
  for (const c of ctx.db.colony.empireId.filter(empireId)) ids.add(c.id);
  for (const f of ctx.db.fleet.empireId.filter(empireId)) {
    // No remote destination vision while in hyperspace.
    if (f.systemId) ids.add(f.systemId);
  }
  return ids;
}
export function canSeeBattle(ctx: Context | ReadContext, empireId: number, battleId: number) {
  const b = ctx.db.battle.id.find(battleId);
  return (
    !!b &&
    (b.attackers === empireId || b.defenders === empireId || visibleSystems(ctx, empireId).has(b.systemId))
  );
}
export function move(ctx: Context, f: Fleet, route: number[], at: number) {
  if (f.battleId) throw new SenderError('Withdraw from battle before moving');
  if (!route.length || route.length > 64) throw new SenderError('Route must contain 1–64 systems');
  for (const id of route) if (!ctx.db.star.id.find(id)) throw new SenderError('Unknown destination');
  const target = ctx.db.star.id.find(route[0])!;
  const current = positionAt(f, at);
  const arrivesAt = dueDay(
    at + Math.max(1, Math.hypot(target.x - current.x, target.y - current.y) / f.speed),
  );
  ctx.db.fleet.id.update({
    ...f,
    systemId: 0,
    route,
    fromX: current.x,
    fromY: current.y,
    toX: target.x,
    toY: target.y,
    departedAt: at,
    arrivesAt,
    order: 'move',
    revision: f.revision + 1,
  });
  const a = { fleetId: f.id, dueTick: tickAt(arrivesAt) };
  if (ctx.db.arrival.fleetId.find(f.id)) ctx.db.arrival.fleetId.update(a);
  else ctx.db.arrival.insert(a);
}
export function shipTemplate(empireId: number, fleetId: number, index: number): Ship {
  return {
    id: 0,
    empireId,
    fleetId,
    name: `S-${empireId}-${index}`,
    design: ['corvette', 'destroyer', 'frigate'][index % 3],
    hull: 1000 + (index % 5) * 100,
    maxHull: 1000 + (index % 5) * 100,
    shield: 200,
    maxShield: 200,
    armor: 0.1 + (index % 3) * 0.05,
    experience: index % 100,
    reactor: 'fusion-ii',
    drive: 'warp-i',
    abilities: index % 7 === 0 ? ['evasive-burst', 'sensor-pulse'] : ['evasive-burst'],
    weapons: [
      { kind: 'pulse-laser', damage: 2 + (index % 3), range: 120, cooldown: 1.2 },
      { kind: 'railgun', damage: 1, range: 180, cooldown: 2.4 },
    ],
  };
}
export function enterBattle(ctx: Context, fleetIds: number[], systemId: number, at: number) {
  const fleets = fleetIds.map((id) => ctx.db.fleet.id.find(id));
  if (fleets.some((f) => !f || f.battleId || f.systemId !== systemId || f.route.length))
    throw new SenderError('All battle fleets must be present and idle');
  const owners = [...new Set(fleets.map((f) => f!.empireId))];
  if (owners.length !== 2) throw new SenderError('Prototype battles currently use two sides');
  const b = ctx.db.battle.insert({
    id: 0,
    systemId,
    state: 'active',
    attackers: owners[0],
    defenders: owners[1],
    startedAt: at,
    simulatedAt: at,
    step: 0,
    attackerLosses: 0,
    defenderLosses: 0,
    winnerId: 0,
  });
  let index = 0;
  for (const f of fleets as Fleet[]) {
    ctx.db.arrival.fleetId.delete(f.id);
    ctx.db.fleet.id.update({ ...f, battleId: b.id, order: 'battle', revision: f.revision + 1 });
    for (const s of ctx.db.ship.fleetId.filter(f.id)) {
      const side = f.empireId === owners[0] ? 0 : 1;
      ctx.db.participant.insert({
        shipId: s.id,
        battleId: b.id,
        fleetId: f.id,
        empireId: f.empireId,
        side,
        x: (side ? 90 : -90) + (index % 20) * 2,
        y: (Math.floor(index / 20) % 30) * 6 - 90,
        vx: side ? -2 : 2,
        vy: (index % 5) - 2,
        targetId: 0,
        hull: s.hull,
        shield: s.shield,
        armor: s.armor,
        damage: s.weapons.reduce((sum, w) => sum + w.damage, 0),
        cooldown: 1.2,
        nextFireAt: at + (index % 12) / 10,
        maneuver: 'strafe',
      });
      index++;
    }
  }
  ensureBattleReport(ctx, b, [...ctx.db.participant.battleId.filter(b.id)], wallNow(ctx));
  return b;
}
export function finishBattle(ctx: Context, battleId: number, at: number, peace = false) {
  const b = ctx.db.battle.id.find(battleId)!;
  const survivors = [...ctx.db.participant.battleId.filter(battleId)];
  const owners = new Set(survivors.map((s) => s.empireId));
  if (owners.size > 1 && !peace) return false;
  // Capture survivors before clearing tactical rows; keep the final summary durable.
  const finished = { ...b, state: 'finished', simulatedAt: at, winnerId: peace ? 0 : ([...owners][0] ?? 0) };
  publishBattleReport(ctx, finished, survivors, wallNow(ctx), true);
  for (const p of survivors) ctx.db.participant.shipId.delete(p.shipId);
  for (const f of ctx.db.fleet.battleId.filter(battleId)) {
    if (!f.shipCount) {
      ctx.db.fleet.id.delete(f.id);
      if (ctx.db.gameSettings.id.find(1)) {
        ctx.db.gameFleet.id.delete(f.id);
        ctx.db.gameNavigation.id.delete(f.id);
        ctx.db.gameFleetCondition.id.delete(f.id);
        for (const d of ctx.db.gameDamaged.fleetId.filter(f.id)) ctx.db.gameDamaged.id.delete(d.id);
      }
    } else
      ctx.db.fleet.id.update({
        ...f,
        battleId: 0,
        order: 'idle',
        departedAt: at,
        arrivesAt: at,
        revision: f.revision + 1,
      });
  }
  ctx.db.battle.id.update(finished);
  return true;
}
export function refreshJob(ctx: Context, jobId: number, rate: number, at: number) {
  const j = ctx.db.job.id.find(jobId);
  if (!j || j.status !== 'active') throw new SenderError('No active job');
  const workDone = progressAt(j, at);
  ctx.db.job.id.update({
    ...j,
    workDone,
    updatedAt: at,
    rate,
    dueTick: tickAt(at + Math.max(0, j.workTotal - workDone) / rate),
  });
}
