import { SenderError, t } from 'spacetimedb/server';
import { gameTimeAt, progressAt } from '../../backend/domain';
import { db } from './tables';
import { ensureBattleReport, publishBattleReport } from './battle-reports';
import { refreshFleetCondition } from './game-model';
import {
  admin,
  canSeeBattle,
  finishBattle,
  member,
  move,
  NEVER,
  now,
  ownedFleet,
  tickAt,
  wallNow,
} from './rules';

export const joinEmpire = db.reducer({ empireId: t.u32() }, (ctx, { empireId }) => {
  if (ctx.db.gameSettings.id.find(1)) throw new SenderError('Spielbeitritt benötigt ein Lobby-Ticket.');
  if (ctx.db.scenario.id.find(1)?.phase !== 'ready') throw new SenderError('World is not ready');
  const existing = ctx.db.membership.identity.find(ctx.sender);
  if (existing) {
    if (existing.empireId !== empireId) throw new SenderError('Identity already controls another empire');
    return;
  }
  const e = ctx.db.empire.id.find(empireId);
  if (!e || ctx.db.membership.empireId.find(empireId)) throw new SenderError('Empire unavailable');
  ctx.db.membership.insert({ identity: ctx.sender, empireId });
  ctx.db.focus.insert({ identity: ctx.sender, fleetId: 0, battleId: 0 });
  ctx.db.empire.id.update({ ...e, ai: false, nextDecisionTick: NEVER });
  const summary = ctx.db.empireSummary.id.find(empireId)!;
  ctx.db.empireSummary.id.update({ ...summary, ai: false });
});
export const setFocus = db.reducer({ fleetId: t.u32(), battleId: t.u32() }, (ctx, { fleetId, battleId }) => {
  const owner = member(ctx);
  if (fleetId) ownedFleet(ctx, fleetId, owner);
  if (battleId && !canSeeBattle(ctx, owner, battleId)) throw new SenderError('Battle is not visible');
  ctx.db.focus.identity.update({ identity: ctx.sender, fleetId, battleId });
});
export const setAutomation = db.reducer({ enabled: t.bool() }, (ctx, { enabled }) => {
  const owner = member(ctx),
    e = ctx.db.empire.id.find(owner)!;
  ctx.db.empire.id.update({
    ...e,
    ai: enabled,
    nextDecisionTick: enabled ? tickAt(now(ctx) + owner * 0.2) : NEVER,
  });
  ctx.db.empireSummary.id.update({ ...ctx.db.empireSummary.id.find(owner)!, ai: enabled });
});
export const moveFleet = db.reducer(
  { fleetId: t.u32(), route: t.array(t.u32()) },
  (ctx, { fleetId, route }) => {
    if (ctx.db.gameSettings.id.find(1)) throw new SenderError('Use game_command to validate game routes.');
    const owner = member(ctx);
    move(ctx, ownedFleet(ctx, fleetId, owner), route, now(ctx));
  },
);
export const splitFleet = db.reducer(
  { fleetId: t.u32(), shipIds: t.array(t.u32()) },
  (ctx, { fleetId, shipIds }) => {
    const owner = member(ctx);
    const f = ownedFleet(ctx, fleetId, owner);
    if (f.battleId || f.route.length || !f.systemId)
      throw new SenderError('Split requires an idle fleet in a system');
    if (
      !shipIds.length ||
      shipIds.length >= f.shipCount ||
      shipIds.length > 4096 ||
      new Set(shipIds).size !== shipIds.length
    )
      throw new SenderError('Select a unique, nonempty proper subset, at most 4096 ships');
    const ships = shipIds.map((id) => ctx.db.ship.id.find(id));
    if (ships.some((s) => !s || s.fleetId !== f.id || s.empireId !== owner))
      throw new SenderError('Ship is not in this fleet');
    const split = ctx.db.fleet.insert({
      ...f,
      id: 0,
      name: `${f.name} / Detachment`,
      shipCount: shipIds.length,
      revision: 0,
    });
    for (const s of ships) ctx.db.ship.id.update({ ...s!, fleetId: split.id });
    ctx.db.fleet.id.update({ ...f, shipCount: f.shipCount - shipIds.length, revision: f.revision + 1 });
    const meta = ctx.db.gameFleet.id.find(f.id);
    if (meta) {
      if (
        [...ctx.db.job.empireId.filter(owner)].some(
          (j) =>
            j.targetId === f.id &&
            ['game_scan', 'game_colonize'].includes(j.kind) &&
            ['active', 'blocked'].includes(j.status),
        )
      )
        throw new SenderError('Flotte führt einen Auftrag aus.');
      ctx.db.gameFleet.insert({ ...meta, id: split.id, externalId: `nf${split.id}` });
      for (const s of ships) {
        const d = ctx.db.gameDamaged.id.find(s!.id);
        if (d) ctx.db.gameDamaged.id.update({ ...d, fleetId: split.id });
      }
      refreshFleetCondition(ctx, f.id);
      refreshFleetCondition(ctx, split.id);
    }
  },
);
export const mergeFleets = db.reducer(
  { sourceId: t.u32(), targetId: t.u32() },
  (ctx, { sourceId, targetId }) => {
    const owner = member(ctx);
    const source = ownedFleet(ctx, sourceId, owner),
      target = ownedFleet(ctx, targetId, owner);
    if (
      source.id === target.id ||
      source.battleId ||
      target.battleId ||
      source.route.length ||
      target.route.length ||
      !source.systemId ||
      source.systemId !== target.systemId
    )
      throw new SenderError('Merge requires two idle fleets in the same system');
    if (ctx.db.gameSettings.id.find(1)) {
      const a = ctx.db.gameFleet.id.find(sourceId)!,
        b = ctx.db.gameFleet.id.find(targetId)!;
      if (a.kind !== b.kind || a.kind !== 'corvette')
        throw new SenderError('Nur militärische Verbände desselben Typs können zusammengeführt werden.');
    }
    for (const s of ctx.db.ship.fleetId.filter(sourceId)) ctx.db.ship.id.update({ ...s, fleetId: targetId });
    // Retarget queued construction in the same transaction.
    for (const j of ctx.db.job.empireId.filter(owner))
      if (j.kind === 'construction' && j.status === 'active' && j.targetId === sourceId)
        ctx.db.job.id.update({ ...j, targetId });
    ctx.db.fleet.id.update({
      ...target,
      shipCount: source.shipCount + target.shipCount,
      revision: target.revision + 1,
    });
    ctx.db.fleet.id.delete(sourceId);
    if (ctx.db.gameSettings.id.find(1)) {
      ctx.db.gameFleet.id.delete(sourceId);
      ctx.db.gameFleetCondition.id.delete(sourceId);
      for (const d of ctx.db.gameDamaged.fleetId.filter(sourceId))
        ctx.db.gameDamaged.id.update({ ...d, fleetId: targetId });
      refreshFleetCondition(ctx, targetId);
    }
    const focus = ctx.db.focus.identity.find(ctx.sender)!;
    if (focus.fleetId === sourceId) ctx.db.focus.identity.update({ ...focus, fleetId: targetId });
  },
);
export const withdrawFleet = db.reducer({ fleetId: t.u32() }, (ctx, { fleetId }) => {
  const owner = member(ctx),
    f = ownedFleet(ctx, fleetId, owner);
  if (!f.battleId) throw new SenderError('Fleet is not in battle');
  const at = now(ctx);
  const battle = ctx.db.battle.id.find(f.battleId)!;
  const meta = ctx.db.gameFleet.id.find(f.id);
  if (meta) ctx.db.gameFleet.id.update({ ...meta, retreatUntil: at + 5 });
  ensureBattleReport(ctx, battle, [...ctx.db.participant.battleId.filter(f.battleId)], wallNow(ctx));
  const leaving = new Set([...ctx.db.participant.fleetId.filter(f.id)].map((p) => p.shipId));
  for (const id of leaving) ctx.db.participant.shipId.delete(id);
  for (const p of ctx.db.participant.battleId.filter(f.battleId)) {
    if (leaving.has(p.targetId)) ctx.db.participant.shipId.update({ ...p, targetId: 0 });
  }
  ctx.db.fleet.id.update({
    ...f,
    battleId: 0,
    order: 'idle',
    departedAt: at,
    arrivesAt: at,
    revision: f.revision + 1,
  });
  if (!finishBattle(ctx, f.battleId, at))
    publishBattleReport(ctx, battle, [...ctx.db.participant.battleId.filter(f.battleId)], wallNow(ctx), true);
});
export const setClock = db.reducer({ paused: t.bool(), speed: t.f64() }, (ctx, { paused, speed }) => {
  // The lab operator and the human controlling the first empire may manage the shared clock.
  if (!ctx.db.administrator.id.find(1)?.identity.isEqual(ctx.sender)) {
    if (member(ctx) !== (ctx.db.gameSettings.id.find(1)?.hostId ?? 1))
      throw new SenderError('Only the host controls the clock');
  }
  if (!(ctx.db.gameSettings.id.find(1) ? [1, 2, 3, 4] : [0.5, 1, 2, 4]).includes(speed))
    throw new SenderError('Unsupported game speed');
  if (!paused && ctx.db.gameSettings.id.find(1)?.winnerId) throw new SenderError('Die Partie ist beendet.');
  const c = ctx.db.clock.id.find(1);
  if (!c || ctx.db.scenario.id.find(1)?.phase !== 'ready') throw new SenderError('World is not running');
  const wallTime = wallNow(ctx);
  ctx.db.clock.id.update({ ...c, gameTime: gameTimeAt(c, wallTime), wallTime, paused, speed });
  if (paused)
    for (const b of ctx.db.battle.state.filter('active'))
      publishBattleReport(ctx, b, [...ctx.db.participant.battleId.filter(b.id)], wallTime, true);
  // Planned pauses are not scheduler stalls.
  for (const r of ctx.db.runtime.iter())
    ctx.db.runtime.name.update({ ...r, lastWallAt: wallTime, lastLagMs: 0 });
});
// Additive migration: initialize only missing summaries, including paused worlds.
// Historical damage cannot be reconstructed; baselineAt marks when accounting starts.
export const initializeBattleReports = db.reducer((ctx) => {
  admin(ctx);
  for (const b of ctx.db.battle.iter())
    ensureBattleReport(ctx, b, [...ctx.db.participant.battleId.filter(b.id)], wallNow(ctx));
});
export const startJob = db.reducer({ kind: t.string(), targetId: t.u32() }, (ctx, { kind, targetId }) => {
  if (ctx.db.gameSettings.id.find(1)) throw new SenderError('Use game_command for game production.');
  const owner = member(ctx),
    e = ctx.db.empire.id.find(owner)!;
  if (!['research', 'construction'].includes(kind)) throw new SenderError('Unknown project kind');
  if ([...ctx.db.job.empireId.filter(owner)].filter((j) => j.status === 'active').length >= 8)
    throw new SenderError('Project queue full');
  if (kind === 'construction') ownedFleet(ctx, targetId, owner);
  if (kind === 'research' ? e.science < 100 : e.minerals < 100)
    throw new SenderError('Insufficient resources');
  ctx.db.empire.id.update({
    ...e,
    science: e.science - (kind === 'research' ? 100 : 0),
    minerals: e.minerals - (kind === 'construction' ? 100 : 0),
  });
  const at = now(ctx),
    workTotal = kind === 'research' ? 90 : 60,
    rate = 1 + e.researchLevel * 0.05;
  ctx.db.job.insert({
    id: 0,
    empireId: owner,
    kind,
    topic: kind === 'research' ? 'extraction' : 'corvette',
    targetId,
    workDone: 0,
    workTotal,
    rate,
    updatedAt: at,
    dueTick: tickAt(at + workTotal / rate),
    status: 'active',
  });
});
export const cancelJob = db.reducer({ jobId: t.u32() }, (ctx, { jobId }) => {
  if (ctx.db.gameSettings.id.find(1)) throw new SenderError('Use game_command for game production.');
  const owner = member(ctx),
    j = ctx.db.job.id.find(jobId);
  if (!j || j.empireId !== owner || j.status !== 'active')
    throw new SenderError('Project cannot be cancelled');
  const at = now(ctx);
  ctx.db.job.id.update({
    ...j,
    workDone: progressAt(j, at),
    updatedAt: at,
    status: 'cancelled',
    dueTick: NEVER,
  });
});
