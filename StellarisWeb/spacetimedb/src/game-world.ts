import { SenderError, t } from 'spacetimedb/server';
import { createGalaxy } from '../../shared/galaxy';
import { createColony } from '../../shared/colonies';
import { assertColonies } from '../../shared/colonies';
import { hydrateEmpires, type GameState, type ShipType } from '../../shared/game';
import {
  parseEmpireTemplate,
  parseSpeciesTemplate,
  starterLibrary,
  snapshotTemplate,
  type TemplateSnapshot,
} from '../../shared/empires';
import { instantiateEmpire, type EmpireState } from '../../shared/empireState';
import { ORIGINS, ENVIRONMENTS } from '../../shared/empireCatalog';
import { db, type Context } from './tables';
import { admin, NEVER, now, clockNow, tickAt, wallNow } from './rules';
import { schedule } from './seed';
import { addJob, event, makeShip, updateColony } from './game-model';
import { publishBattleReport } from './battle-reports';
import { ensureStoryWorld, storyForNewEmpire } from './game-stories';
import { ensureSystemObjects } from './game-objects';
import { newResearch } from '../../shared/research';

export function gameClock(ctx: Context, paused: boolean, speed = ctx.db.clock.id.find(1)!.speed) {
  const at = clockNow(ctx),
    clock = ctx.db.clock.id.find(1)!;
  ctx.db.clock.id.update({ ...clock, gameTime: at, wallTime: wallNow(ctx), paused, speed });
  if (paused)
    for (const b of ctx.db.battle.state.filter('active'))
      publishBattleReport(ctx, b, [...ctx.db.participant.battleId.filter(b.id)], wallNow(ctx), true);
}
export function connectPlayer(ctx: Context, owner: number) {
  if (!ctx.connectionId) throw new SenderError('A player connection is required');
  const id = ctx.connectionId.toHexString();
  if (!ctx.db.gameConnection.id.find(id))
    ctx.db.gameConnection.insert({ id, identity: ctx.sender, empireId: owner });
  const presence = ctx.db.gamePresence.id.find(owner);
  if (presence) ctx.db.gamePresence.id.update({ ...presence, online: true });
  else ctx.db.gamePresence.insert({ id: owner, online: true });
  const config = ctx.db.gameSettings.id.find(1)!;
  const hostOnline = ctx.db.gamePresence.id.find(config.hostId)?.online;
  if (!hostOnline || config.autoPaused)
    ctx.db.gameSettings.id.update({
      ...config,
      hostId: hostOnline ? config.hostId : owner,
      autoPaused: false,
    });
  if (config.autoPaused) gameClock(ctx, false);
}
export const gameConnected = db.clientConnected((ctx) => {
  if (!ctx.db.gameSettings.id.find(1)) return;
  const m = ctx.db.membership.identity.find(ctx.sender);
  if (m) connectPlayer(ctx, m.empireId);
});
export const gameDisconnected = db.clientDisconnected((ctx) => {
  const config = ctx.db.gameSettings.id.find(1);
  if (!config || !ctx.connectionId) return;
  ctx.db.gameObjectFocus.id.delete(ctx.connectionId.toHexString());
  const entry = ctx.db.gameConnection.id.find(ctx.connectionId.toHexString());
  if (!entry) return;
  ctx.db.gameConnection.id.delete(entry.id);
  if ([...ctx.db.gameConnection.empireId.filter(entry.empireId)].length) return;
  ctx.db.gamePresence.id.update({ id: entry.empireId, online: false });
  const remaining = [...ctx.db.gameConnection.iter()].sort((a, b) => a.empireId - b.empireId);
  if (!remaining.length) {
    const wasRunning = !ctx.db.clock.id.find(1)!.paused;
    gameClock(ctx, true);
    ctx.db.gameSettings.id.update({ ...config, autoPaused: wasRunning });
  } else if (config.hostId === entry.empireId)
    ctx.db.gameSettings.id.update({ ...config, hostId: remaining[0].empireId });
});

export const initializeGame = db.reducer(
  { code: t.string(), seed: t.u32(), sourceJson: t.string(), migrationKey: t.string() },
  (ctx, { code, seed, sourceJson, migrationKey }) => {
    admin(ctx);
    const existing = ctx.db.gameSettings.id.find(1);
    if (existing) {
      if (existing.migrationKey !== migrationKey) throw new SenderError('Different world already exists');
      return;
    }
    if (ctx.db.scenario.id.find(1)) throw new SenderError('Cannot overwrite a lab database');
    if (!/^[A-F0-9]{6}$/.test(code) || sourceJson.length > 8_000_000)
      throw new SenderError('Invalid world import');
    const game: GameState = sourceJson ? JSON.parse(sourceJson) : createGalaxy(code, seed);
    if (
      game.code !== code ||
      game.version !== 2 ||
      !Array.isArray(game.systems) ||
      game.systems.length > 2000 ||
      game.players.length > 25
    )
      throw new SenderError('Invalid source world');
    assertColonies(game);
    hydrateEmpires(game);
    const players = new Map(game.players.map((p, i) => [p.id, i + 1])),
      stars = new Map(game.systems.map((s, i) => [s.id, i + 1]));
    const at = game.tick;
    ctx.db.gameSettings.insert({
      id: 1,
      code,
      hostId: players.get(game.hostId) || 0,
      winnerId: game.winner ? players.get(game.winner) || 0 : 0,
      capacity: 25,
      autoPaused: !game.paused,
      migrationKey,
    });
    ctx.db.clock.insert({ id: 1, gameTime: at, wallTime: wallNow(ctx), speed: game.speed, paused: true });
    ctx.db.scenario.insert({
      id: 1,
      seed,
      systems: game.systems.length,
      empires: 25,
      fleetsPerEmpire: 50,
      shipsPerEmpire: 0,
      battleCount: 0,
      battleFleetsPerSide: 0,
      cohortsPerColony: 0,
      popsPerCohort: 0,
      seededShips: game.fleets.length,
      phase: 'ready',
      schemaVersion: 2,
    });
    for (const s of game.systems) {
      const id = stars.get(s.id)!;
      ctx.db.star.insert({
        id,
        name: s.name,
        x: s.x,
        y: s.y,
        kind: s.kind,
        ownerId: s.owner ? players.get(s.owner) || 0 : 0,
      });
      ctx.db.gameSystem.insert({
        id,
        externalId: s.id,
        color: s.color,
        starClass: s.class,
        planet: s.planet,
        energy: s.resources.energy,
        minerals: s.resources.minerals,
        data: s.resources.data,
        defense: s.defense,
        mined: s.mined,
        anomaly: s.anomaly,
        studied: s.studied,
        colonyName: s.colonyName || '',
        colonyJson: s.colony ? JSON.stringify(s.colony) : '',
        growthAt: at,
      });
    }
    for (const [a, b] of game.links) ctx.db.gameLane.insert({ id: 0, a: stars.get(a)!, b: stars.get(b)! });
    for (const p of game.players) {
      const id = players.get(p.id)!;
      ctx.db.gameIncome.insert({ id, producedAt: at });
      ctx.db.empire.insert({
        id,
        energy: p.resources.energy,
        minerals: p.resources.minerals,
        data: p.resources.data,
        productionModifier: 1,
        researchLevel: p.techs.length,
        ai: !!p.ai,
        nextDecisionTick: p.ai ? tickAt(at + id * 0.2) : NEVER,
        aiCursor: 0,
        seededShips: 0,
      });
      ctx.db.empireSummary.insert({ id, name: p.name, color: parseInt(p.color.slice(1), 16), ai: !!p.ai });
      ctx.db.gamePresence.insert({ id, online: false });
      ctx.db.gamePlayer.insert({
        id,
        externalId: p.id,
        homeId: stars.get(p.home)!,
        techs: p.techs,
        surveyed: p.surveyed.map((s) => stars.get(s)!),
        discovered: p.discovered.map((s) => stars.get(s)!),
        empireJson: JSON.stringify(p.empire),
        joinedAt: p.ai?.startedAt ?? at,
      });
      for (const s of game.systems.filter((s) => s.owner === p.id))
        updateColony(ctx, stars.get(s.id)!, s.colony!, id);
      ctx.db.gameResearch.insert({ id, programJson: JSON.stringify(p.research), updatedAt: at });
      p.queue.forEach((j, i) =>
        addJob(
          ctx,
          id,
          'game_build',
          j.type,
          stars.get(j.systemId)!,
          j.total,
          j.remaining,
          i ? 'queued' : 'active',
        ),
      );
      for (const s of game.systems.filter((s) => s.owner === p.id && s.colony?.construction)) {
        const j = s.colony!.construction!;
        addJob(ctx, id, 'game_upgrade', j.building, stars.get(s.id)!, j.total, j.remaining);
      }
    }
    for (const f of game.fleets) {
      const owner = players.get(f.owner)!,
        origin = stars.get(f.systemId)!;
      const created = makeShip(ctx, owner, origin, f.type, { name: f.name, externalId: f.id, hp: f.hp });
      if (f.route.length) {
        const row = ctx.db.fleet.id.find(created.fleetId)!,
          from = ctx.db.star.id.find(origin)!,
          target = ctx.db.star.id.find(stars.get(f.route[0])!)!;
        ctx.db.fleet.id.update({
          ...row,
          systemId: 0,
          route: f.route.map((id) => stars.get(id)!),
          order: 'move',
          fromX: from.x,
          fromY: from.y,
          toX: target.x,
          toY: target.y,
          departedAt: at - f.progress * f.duration,
          arrivesAt: at + (1 - f.progress) * f.duration,
        });
        ctx.db.arrival.insert({
          fleetId: created.fleetId,
          dueTick: tickAt(at + (1 - f.progress) * f.duration),
        });
      }
      if (f.task)
        addJob(
          ctx,
          owner,
          f.task.type === 'scan' ? 'game_scan' : 'game_colonize',
          '',
          created.fleetId,
          f.task.total,
          f.task.remaining,
          f.task.blocked ? 'blocked' : 'active',
        );
    }
    for (const l of game.log.slice(-64))
      ctx.db.gameEvent.insert({
        id: 0,
        empireId: l.playerId ? players.get(l.playerId) || 0 : 0,
        tick: l.tick,
        text: l.text,
        tone: l.tone,
      });
    ensureSystemObjects(ctx);
    ensureStoryWorld(ctx);
    schedule(ctx);
    const runtime = ctx.db.runtime.name.find('economy')!;
    ctx.db.runtime.name.update({ ...runtime, nextGameAt: at });
  },
);

export function foundEmpire(ctx: Context, externalId: string, snapshot: TemplateSnapshot, ai = false) {
  const config = ctx.db.gameSettings.id.find(1)!;
  if (ctx.db.empire.count() >= config.capacity) throw new SenderError('Die Galaxie ist voll (25 Imperien).');
  const existing = [...ctx.db.gamePlayer.iter()];
  const id = Math.max(0, ...existing.map((p) => p.id)) + 1;
  const occupied = existing.map((p) => ctx.db.star.id.find(p.homeId)!);
  const candidates = [...ctx.db.star.iter()].filter(
    (s) => s.kind === 'star' && !s.ownerId && ![...ctx.db.fleet.systemId.filter(s.id)].length,
  );
  candidates.sort((a, b) => {
    const score = (s: typeof a) =>
      occupied.length
        ? Math.min(...occupied.map((h) => (s.x - h.x) ** 2 + (s.y - h.y) ** 2))
        : -((s.x - 460) ** 2 + (s.y - 570) ** 2);
    return score(b) - score(a);
  });
  const home = candidates[0];
  if (!home) throw new SenderError('Kein freies Heimatsystem.');
  const at = now(ctx),
    instance = instantiateEmpire(snapshot, externalId, at),
    origin = ORIGINS[instance.design.origin];
  ctx.db.gameIncome.insert({ id, producedAt: at });
  ctx.db.empire.insert({
    id,
    energy: 420 + (origin.resources.energy || 0),
    minerals: 360 + (origin.resources.minerals || 0),
    data: 130 + (origin.resources.data || 0),
    productionModifier: 1,
    researchLevel: 0,
    ai,
    nextDecisionTick: ai ? tickAt(at + id * 0.2) : NEVER,
    aiCursor: 0,
    seededShips: 3,
  });
  ctx.db.empireSummary.insert({
    id,
    name: instance.design.name,
    color: parseInt(instance.design.color.slice(1), 16),
    ai,
  });
  ctx.db.gamePresence.insert({ id, online: false });
  ctx.db.gameResearch.insert({ id, programJson: JSON.stringify(newResearch()), updatedAt: at });
  ctx.db.gamePlayer.insert({
    id,
    externalId,
    homeId: home.id,
    techs: [],
    surveyed: [home.id],
    discovered: [...ctx.db.star.iter()].map((s) => s.id),
    empireJson: JSON.stringify(instance),
    joinedAt: at,
  });
  ctx.db.star.id.update({ ...home, name: instance.design.systemName, ownerId: id });
  const m = ctx.db.gameSystem.id.find(home.id)!;
  ctx.db.gameSystem.id.update({
    ...m,
    defense: 30,
    planet: ENVIRONMENTS[instance.species[0].environment].name,
    colonyName: instance.design.homeworldName,
    growthAt: at,
  });
  const colony = createColony(
    true,
    `${ctx.db.gameSettings.id.find(1)!.code}:${m.externalId}:1`,
    ENVIRONMENTS[instance.species[0].environment].name,
  );
  colony.population += origin.population;
  colony.populations = [{ speciesId: instance.primarySpeciesId, population: colony.population }];
  updateColony(ctx, home.id, colony, id);
  for (const kind of ['scout', 'colony', 'corvette'] as ShipType[])
    makeShip(ctx, id, home.id, kind, {
      name:
        kind === 'scout'
          ? `${instance.design.shipPrefix} Horizon`
          : kind === 'colony'
            ? `${instance.design.shipPrefix} Genesis`
            : '1. Expeditionsflotte',
    });
  event(ctx, 0, `${instance.design.name} hat die Galaxie betreten.`, 'success');
  storyForNewEmpire(ctx, id);
  return id;
}
export const reserveGameSeat = db.reducer(
  { ticket: t.string(), externalId: t.string(), templateJson: t.string() },
  (ctx, { ticket, externalId, templateJson }) => {
    admin(ctx);
    const config = ctx.db.gameSettings.id.find(1);
    if (!config) throw new SenderError('Partie nicht verfügbar.');
    if (!/^[a-f0-9]{64}$/.test(ticket) || externalId.length > 80 || templateJson.length > 20000)
      throw new SenderError('Invalid ticket');
    let owner = ctx.db.gamePlayer.externalId.find(externalId)?.id;
    if (!owner) {
      if (config.winnerId) throw new SenderError('Die Partie ist bereits beendet.');
      const raw = JSON.parse(templateJson),
        species = parseSpeciesTemplate(raw.species),
        empire = parseEmpireTemplate(raw.empire, [species]);
      owner = foundEmpire(ctx, externalId, { empire, species });
    }
    for (const t of ctx.db.gameTicket.iter())
      if (t.expiresAt < wallNow(ctx)) ctx.db.gameTicket.ticket.delete(t.ticket);
    ctx.db.gameTicket.insert({ ticket, empireId: owner, expiresAt: wallNow(ctx) + 180 });
  },
);
export const redeemGameSeat = db.reducer({ ticket: t.string() }, (ctx, { ticket }) => {
  const t = ctx.db.gameTicket.ticket.find(ticket);
  if (!t || t.expiresAt < wallNow(ctx))
    throw new SenderError('Einladung abgelaufen. Bitte erneut beitreten.');
  const old = ctx.db.membership.empireId.find(t.empireId),
    current = ctx.db.membership.identity.find(ctx.sender);
  if (current && current.empireId !== t.empireId)
    throw new SenderError('Identität steuert bereits ein anderes Reich.');
  // Only the trusted gateway can mint this one-use recovery capability after checking the existing session.
  if (old && !old.identity.isEqual(ctx.sender)) {
    if ([...ctx.db.gameConnection.empireId.filter(t.empireId)].length)
      throw new SenderError('Reich ist bereits verbunden.');
    ctx.db.membership.identity.delete(old.identity);
    ctx.db.focus.identity.delete(old.identity);
  }
  if (!current) {
    ctx.db.membership.insert({ identity: ctx.sender, empireId: t.empireId });
    ctx.db.focus.insert({ identity: ctx.sender, fleetId: 0, battleId: 0 });
  }
  ctx.db.gameTicket.ticket.delete(ticket);
  connectPlayer(ctx, t.empireId);
});
