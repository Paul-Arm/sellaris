import { SenderError } from 'spacetimedb/server';
import type { Context } from './tables';
import { now, NEVER, tickAt, ownedFleet } from './rules';
import { addJob, dueJobs, event, jobsFor } from './game-model';
import { storedSystemBodies } from './game-objects';
import { completeGameJob, contested } from './game-jobs';
import { applyGameCommand } from './game-commands';
import { atWar } from './game-relations';
import type { GameCommand } from '../../shared/game';
import type { SiteCommand } from '../../shared/celestial';
import { applySiteCommand, constructionTarget } from './game-sites';
import {
  bodyPosition,
  fleetAnchor,
  flight,
  localPosition,
  localVelocity,
  braking,
  BUILD_REACH,
  validPoint,
  type FleetOrder,
  type LocalMotion,
} from '../../shared/navigation';

type Nav = NonNullable<ReturnType<Context['db']['gameNavigation']['id']['find']>>;
const ordersOf = (n: Nav): FleetOrder[] => JSON.parse(n.ordersJson);
function navigation(ctx: Context, id: number): Nav {
  const old = ctx.db.gameNavigation.id.find(id);
  if (old) return old;
  const f = ctx.db.fleet.id.find(id)!;
  const point = fleetAnchor(ctx.db.gameFleet.id.find(id)!.externalId);
  return {
    id,
    systemId: f.systemId,
    motionJson: JSON.stringify({ from: point, to: point, startedAt: now(ctx), finishAt: now(ctx) }),
    ordersJson: '[]',
    phase: 'idle',
    visited: [],
    targetSlot: 0,
    totalBodies: 0,
    dueTick: NEVER,
  };
}
function save(ctx: Context, n: Nav) {
  if (ctx.db.gameNavigation.id.find(n.id)) ctx.db.gameNavigation.id.update(n);
  else ctx.db.gameNavigation.insert(n);
}
function surveyLeg(ctx: Context, n: Nav, at: number): boolean {
  const bodies = storedSystemBodies(ctx, n.systemId).filter((b) => b.kind !== 'station');
  const next = bodies.filter((b) => !n.visited.includes(b.slot)).sort((a, b) => a.slot - b.slot)[0];
  if (!next) return false;
  const from = localPosition(JSON.parse(n.motionJson), at);
  let pos = bodyPosition(next, bodies, at);
  let motion = flight(
    from,
    { ...pos, x: pos.x + next.radius + 25, y: Math.max(24, pos.y + next.radius) },
    at,
  );
  // Intercept the moving body, using the same orbital clock as the renderer.
  for (let i = 0; i < 4; i++) {
    pos = bodyPosition(next, bodies, motion.finishAt);
    motion = flight(from, { ...pos, x: pos.x + next.radius + 25, y: Math.max(24, pos.y + next.radius) }, at);
  }
  save(ctx, {
    ...n,
    phase: 'survey_flight',
    targetSlot: next.slot,
    totalBodies: bodies.length,
    motionJson: JSON.stringify(motion),
    dueTick: tickAt(motion.finishAt),
  });
  return true;
}
type Construction = Exclude<SiteCommand, { type: 'site_cancel' }>;
export function queueConstruction(ctx: Context, owner: number, cmd: Construction) {
  applySiteCommand(ctx, owner, cmd, true);
  const target = constructionTarget(ctx, cmd, now(ctx));
  const candidates = [...ctx.db.fleet.systemId.filter(target.systemId)].filter(
    (f) => f.empireId === owner && !f.route.length && !f.battleId,
  );
  const selected = cmd.fleetId ? ctx.db.gameFleet.externalId.find(cmd.fleetId) : undefined;
  const builder = cmd.fleetId
    ? candidates.find((f) => f.id === selected?.id)
    : candidates.sort((a, b) => {
        const an = navigation(ctx, a.id),
          bn = navigation(ctx, b.id);
        const busy = Number(ordersOf(an).length > 0) - Number(ordersOf(bn).length > 0);
        const worker =
          Number(ctx.db.gameFleet.id.find(b.id)!.kind === 'colony') -
          Number(ctx.db.gameFleet.id.find(a.id)!.kind === 'colony');
        return busy || worker || a.id - b.id;
      })[0];
  if (!builder) throw new SenderError('Ein eigenes Schiff im System wird zum Bauen benötigt.');
  // A body or fixed point has at most one outstanding construction approach.
  for (const f of candidates) {
    if (
      ordersOf(navigation(ctx, f.id)).some(
        (o) =>
          o.type === cmd.type &&
          o.systemId === cmd.systemId &&
          (o.type === 'site_build' && cmd.type === 'site_build'
            ? o.bodySlot === cmd.bodySlot
            : o.type === 'station_place' &&
              cmd.type === 'station_place' &&
              Math.hypot(o.point.x - cmd.point.x, o.point.y - cmd.point.y, o.point.z - cmd.point.z) < 60),
      )
    )
      throw new SenderError('Für diesen Bauplatz ist bereits ein Schiff unterwegs.');
  }
  applyNavigation(ctx, owner, {
    ...cmd,
    fleetId: ctx.db.gameFleet.id.find(builder.id)!.externalId,
    append: true,
  });
}
function constructionLeg(ctx: Context, n: Nav, cmd: Construction) {
  const at = now(ctx),
    f = ctx.db.fleet.id.find(n.id)!;
  const fleetId = ctx.db.gameFleet.id.find(n.id)!.externalId;
  applySiteCommand(ctx, f.empireId, cmd, true);
  const target = constructionTarget(ctx, cmd, at);
  if (target.systemId !== f.systemId) throw new SenderError('Bauplatz liegt in einem anderen System.');
  const old: LocalMotion = JSON.parse(n.motionJson),
    from = localPosition(old, at);
  if (
    Math.hypot(from.x - target.point.x, from.y - target.point.y, from.z - target.point.z) <=
    target.radius + BUILD_REACH
  ) {
    applySiteCommand(ctx, f.empireId, { ...cmd, fleetId });
    event(ctx, f.empireId, 'Schiff am Bauplatz angekommen. Anlagenbau gestartet.');
    finish(ctx, n);
    return;
  }
  let motion = flight(from, target.point, at, localVelocity(old, at));
  // Intercept moving planets and moons, then recheck the true distance at arrival.
  for (let i = 0; i < 6; i++) {
    const next = constructionTarget(ctx, cmd, motion.finishAt);
    motion = flight(
      from,
      { ...next.point, x: next.point.x + next.radius + 35, y: Math.max(24, next.point.y) },
      at,
      localVelocity(old, at),
    );
  }
  save(ctx, {
    ...n,
    phase: 'construction_flight',
    motionJson: JSON.stringify(motion),
    dueTick: tickAt(motion.finishAt),
  });
}
function begin(ctx: Context, n: Nav) {
  const order = ordersOf(n)[0],
    f = ctx.db.fleet.id.find(n.id)!,
    m = ctx.db.gameFleet.id.find(n.id)!;
  if (!order) {
    save(ctx, { ...n, phase: 'idle', dueTick: NEVER });
    return;
  }
  if (f.battleId || !f.systemId || f.route.length)
    throw new SenderError('Flotte ist noch unterwegs oder im Gefecht.');
  const at = now(ctx);
  n = { ...n, systemId: f.systemId, visited: [], totalBodies: 0 };
  if (order.type === 'local_move') {
    if (ctx.db.gameSystem.externalId.find(order.systemId)?.id !== f.systemId)
      throw new SenderError('Lokales Ziel liegt in einem anderen System.');
    const old: LocalMotion = JSON.parse(n.motionJson);
    const motion = flight(localPosition(old, at), order.point, at, localVelocity(old, at));
    save(ctx, { ...n, phase: 'local', motionJson: JSON.stringify(motion), dueTick: tickAt(motion.finishAt) });
  } else if (order.type === 'site_build' || order.type === 'station_place') {
    constructionLeg(ctx, n, order);
  } else if (order.type === 'scan') {
    const p = ctx.db.gamePlayer.id.find(f.empireId)!,
      s = ctx.db.star.id.find(f.systemId)!,
      meta = ctx.db.gameSystem.id.find(f.systemId)!;
    if (m.kind !== 'scout') throw new SenderError('Ein Forschungsschiff wird benötigt.');
    if (p.surveyed.includes(f.systemId)) throw new SenderError('Dieses System ist bereits untersucht.');
    if (contested(ctx, f.systemId, f.empireId) || (meta.defense && atWar(ctx, s.ownerId, f.empireId)))
      throw new SenderError('Feindliche Verteidigung verhindert die Untersuchung.');
    const count = storedSystemBodies(ctx, f.systemId).filter((b) => b.kind !== 'station').length;
    addJob(ctx, f.empireId, 'game_scan', '', f.id, Math.max(1, count * 4));
    const j = jobsFor(ctx, f.empireId).find((j) => j.kind === 'game_scan' && j.targetId === f.id)!;
    ctx.db.job.id.update({ ...j, rate: 0, dueTick: NEVER });
    if (!surveyLeg(ctx, n, at)) {
      completeGameJob(ctx, j, at);
      finish(ctx, n);
    }
  } else {
    applyGameCommand(ctx, f.empireId, { ...order, fleetId: m.externalId } as GameCommand, true);
    save(ctx, { ...n, phase: order.type === 'move' ? 'travel' : 'colonize', dueTick: tickAt(at + 0.5) });
  }
}
function finish(ctx: Context, n: Nav) {
  const next = { ...n, ordersJson: JSON.stringify(ordersOf(n).slice(1)), phase: 'idle', dueTick: NEVER };
  save(ctx, next);
  if (ordersOf(next).length) {
    try {
      begin(ctx, next);
    } catch (e) {
      if (!(e instanceof SenderError)) throw e;
      event(
        ctx,
        ctx.db.fleet.id.find(n.id)!.empireId,
        `Flottenauftrag übersprungen: ${String(e)}`,
        'warning',
      );
      save(ctx, { ...next, phase: 'skip', dueTick: tickAt(now(ctx) + 0.5) });
    }
  }
}
export function applyNavigation(ctx: Context, owner: number, cmd: GameCommand) {
  if (!('fleetId' in cmd)) throw new SenderError('Flotte fehlt.');
  if (!cmd.fleetId) throw new SenderError('Flotte fehlt.');
  const meta = ctx.db.gameFleet.externalId.find(cmd.fleetId);
  if (!meta) throw new SenderError('Flotte nicht gefunden.');
  const f = ownedFleet(ctx, meta.id, owner),
    n = navigation(ctx, f.id),
    orders = ordersOf(n);
  if (cmd.type === 'fleet_remove_order') {
    if (!Number.isInteger(cmd.index) || cmd.index < 1 || cmd.index >= orders.length)
      throw new SenderError('Nur wartende Aufträge können entfernt werden.');
    orders.splice(cmd.index, 1);
    save(ctx, { ...n, ordersJson: JSON.stringify(orders) });
    return;
  }
  if (cmd.type === 'fleet_stop') {
    if (f.battleId) throw new SenderError('Ziehe die Flotte zuerst aus dem Gefecht zurück.');
    for (const j of jobsFor(ctx, owner).filter(
      (j) => j.targetId === f.id && ['game_scan', 'game_colonize'].includes(j.kind),
    )) {
      if (j.kind === 'game_colonize') {
        const e = ctx.db.empire.id.find(owner)!;
        ctx.db.empire.id.update({ ...e, energy: e.energy + 80, minerals: e.minerals + 80 });
      }
      ctx.db.job.id.update({ ...j, status: 'cancelled', dueTick: NEVER });
    }
    const motion = braking(JSON.parse(n.motionJson), now(ctx));
    // A committed hyperlane leg finishes; every subsequent leg/order is discarded.
    if (f.route.length) ctx.db.fleet.id.update({ ...f, route: f.route.slice(0, 1) });
    save(ctx, {
      ...n,
      ordersJson: '[]',
      phase: motion.finishAt > now(ctx) ? 'braking' : 'idle',
      motionJson: JSON.stringify(motion),
      dueTick: motion.finishAt > now(ctx) ? tickAt(motion.finishAt) : NEVER,
    });
    return;
  }
  if (!['move', 'local_move', 'scan', 'colonize', 'site_build', 'station_place'].includes(cmd.type))
    throw new SenderError('Ungültiger Flottenauftrag.');
  if (
    cmd.type === 'local_move' &&
    (!validPoint(cmd.point) || !ctx.db.gameSystem.externalId.find(cmd.systemId))
  )
    throw new SenderError('Ungültige Systemkoordinaten.');
  if (cmd.type === 'move' && !ctx.db.gameSystem.externalId.find(cmd.systemId))
    throw new SenderError('Unbekanntes Zielsystem.');
  if (cmd.type === 'scan' && meta.kind !== 'scout')
    throw new SenderError('Ein Forschungsschiff wird benötigt.');
  if (cmd.type === 'colonize' && meta.kind !== 'colony')
    throw new SenderError('Ein Kolonieschiff wird benötigt.');
  const append = 'append' in cmd && cmd.append === true;
  // Direct local destinations replace the current order in this same transaction.
  // Any validation failure in begin rolls back both cancellation and replacement.
  if (cmd.type === 'local_move' && !append) {
    if (f.route.length) throw new SenderError('Flotte ist noch im Hyperraum.');
    applyNavigation(ctx, owner, { type: 'fleet_stop', fleetId: cmd.fleetId });
    const { fleetId: _, ...order } = cmd;
    begin(ctx, { ...navigation(ctx, f.id), ordersJson: JSON.stringify([order]) });
    return;
  }
  if (orders.length >= 32) throw new SenderError('Maximal 32 Flottenaufträge.');
  if (
    !append &&
    (orders.length ||
      f.route.length ||
      jobsFor(ctx, owner).some((j) => j.targetId === f.id && ['game_scan', 'game_colonize'].includes(j.kind)))
  )
    throw new SenderError('Flotte beschäftigt. Auftrag anhängen oder zuerst stoppen.');
  const { fleetId: _, ...order } = cmd;
  const next = { ...n, ordersJson: JSON.stringify([...orders, order]) };
  if (orders.length) save(ctx, next);
  else if (f.route.length) save(ctx, { ...next, phase: 'await_arrival', dueTick: tickAt(now(ctx) + 0.5) });
  else begin(ctx, next);
}
export function navigationTick(ctx: Context) {
  const at = now(ctx);
  for (const n of [...ctx.db.gameNavigation.dueTick.filter(dueJobs(at))]) {
    const f = ctx.db.fleet.id.find(n.id);
    if (!f) {
      ctx.db.gameNavigation.id.delete(n.id);
      continue;
    }
    if (f.battleId || contested(ctx, f.systemId, f.empireId)) {
      const motion: LocalMotion = JSON.parse(n.motionJson),
        point = localPosition(motion, Math.min(at, Number(n.dueTick) / 1000));
      const remaining = Math.max(0.5, motion.finishAt - at);
      save(ctx, {
        ...n,
        motionJson: motion.paused
          ? n.motionJson
          : JSON.stringify({
              ...motion,
              velocity: { x: 0, y: 0, z: 0 },
              from: point,
              startedAt: at,
              finishAt: at + remaining,
              paused: true,
            }),
        dueTick: tickAt(at + 0.5),
      });
      continue;
    }
    const motion: LocalMotion = JSON.parse(n.motionJson);
    if (motion.paused) {
      const finishAt = at + Math.max(0.5, motion.finishAt - motion.startedAt);
      save(ctx, {
        ...n,
        motionJson: JSON.stringify({ ...motion, paused: false, startedAt: at, finishAt }),
        dueTick: tickAt(finishAt),
      });
      continue;
    }
    if (n.phase === 'travel' || n.phase === 'await_arrival') {
      if (f.route.length) {
        save(ctx, { ...n, dueTick: tickAt(at + 0.5) });
        continue;
      }
      const point = fleetAnchor(ctx.db.gameFleet.id.find(f.id)!.externalId);
      const arrived = {
        ...n,
        systemId: f.systemId,
        motionJson: JSON.stringify({ from: point, to: point, startedAt: at, finishAt: at }),
      };
      if (n.phase === 'await_arrival') {
        save(ctx, arrived);
        try {
          begin(ctx, arrived);
        } catch (e) {
          if (!(e instanceof SenderError)) throw e;
          finish(ctx, arrived);
        }
      } else finish(ctx, arrived);
    } else if (n.phase === 'construction_flight') {
      const order = ordersOf(n)[0];
      try {
        if (order?.type === 'site_build' || order?.type === 'station_place') constructionLeg(ctx, n, order);
        else finish(ctx, n);
      } catch (e) {
        if (!(e instanceof SenderError)) throw e;
        event(ctx, f.empireId, `Bauauftrag abgebrochen: ${String(e)}`, 'warning');
        finish(ctx, n);
      }
    } else if (n.phase === 'colonize') {
      if (jobsFor(ctx, f.empireId).some((j) => j.kind === 'game_colonize' && j.targetId === f.id))
        save(ctx, { ...n, dueTick: tickAt(at + 0.5) });
      else finish(ctx, n);
    } else if (n.phase === 'survey_flight') {
      save(ctx, { ...n, phase: 'survey_scan', dueTick: tickAt(at + 1) });
    } else if (n.phase === 'survey_scan') {
      const next = { ...n, visited: [...n.visited, n.targetSlot] };
      const progress = jobsFor(ctx, f.empireId).find((j) => j.kind === 'game_scan' && j.targetId === f.id);
      if (progress)
        ctx.db.job.id.update({
          ...progress,
          workDone: Math.min(progress.workTotal, next.visited.length * 4),
          updatedAt: at,
        });
      if (!surveyLeg(ctx, next, at)) {
        const j = jobsFor(ctx, f.empireId).find((j) => j.kind === 'game_scan' && j.targetId === f.id);
        if (j) completeGameJob(ctx, j, at);
        finish(ctx, next);
      }
    } else finish(ctx, n);
  }
}
