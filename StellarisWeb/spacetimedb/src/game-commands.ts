import { applyNativeStarbase } from './game-starbases';
import type { StarbaseCommand } from '../../shared/starbases';
import { SenderError, t } from 'spacetimedb/server';
import { command, type GameCommand, type StarSystem } from '../../shared/game';
import { starterLibrary, snapshotTemplate } from '../../shared/empires';
import { empireModifiers } from '../../shared/empireState';
import { progressAt } from '../../backend/domain';
import { db, type Context } from './tables';
import { member, move, NEVER, now, ownedFleet, tickAt } from './rules';
import {
  addJob,
  commandModel,
  event,
  jobsFor,
  refreshColonyRate,
  settleEconomy,
  settlePopulation,
  updateColony,
} from './game-model';
import { foundEmpire, gameClock } from './game-world';
import { DIPLOMACY_TYPES, type DiplomacyCommand } from '../../shared/diplomacy';
import { applyDiplomacy } from './game-diplomacy';
import { applyCrisisCommand } from './game-crises';
import { applySituationCommand, triggerSituation } from './game-situations';
import type { SituationCommand } from '../../shared/events/types';
import { applySiteCommand } from './game-sites';
import { applyStellarCommand } from './game-stellar';
import { applyNavigation, queueConstruction } from './game-navigation';
import { COLONY_COMMANDS, type ColonyCommand } from '../../shared/colonies';
import { applyPlanetColonyCommand } from './game-planet-colonies';
import { colonyPlanet } from '../../shared/planetColonies';
import { applyResearchCommand } from './game-research';

export function applyGameCommand(ctx: Context, owner: number, cmd: GameCommand, executing = false) {
  const config = ctx.db.gameSettings.id.find(1);
  if (!config || config.winnerId) throw new SenderError('Partie nicht verfügbar.');
  if (!cmd || typeof cmd !== 'object') throw new SenderError('Ungültiger Befehl.');
  if (cmd.type === 'mine')
    throw new SenderError('Bergbaustationen werden am Systemobjekt mit einem Schiff gebaut.');
  const at = now(ctx);
  if (cmd.type.startsWith('starbase_')) {
    applyNativeStarbase(ctx, owner, cmd as StarbaseCommand);
    return;
  }
  if (cmd.type === 'research' || cmd.type === 'research_weight' || cmd.type === 'compute_allocation') {
    applyResearchCommand(ctx, owner, cmd);
    return;
  }
  if (
    (COLONY_COMMANDS as readonly string[]).includes(cmd.type) &&
    'bodySlot' in cmd &&
    cmd.bodySlot !== undefined
  ) {
    applyPlanetColonyCommand(ctx, owner, cmd as ColonyCommand);
    return;
  }
  if (cmd.type === 'stellar_collapse' || cmd.type === 'stellar_cancel') {
    applyStellarCommand(ctx, owner, cmd);
    return;
  }
  if (
    !executing &&
    ['move', 'scan', 'colonize', 'local_move', 'fleet_stop', 'fleet_remove_order'].includes(cmd.type)
  ) {
    applyNavigation(ctx, owner, cmd);
    return;
  }
  if (
    cmd.type === 'site_build' ||
    cmd.type === 'site_cancel' ||
    cmd.type === 'station_place' ||
    cmd.type === 'megastructure_place'
  ) {
    if (cmd.type !== 'site_cancel' && !executing) queueConstruction(ctx, owner, cmd);
    else applySiteCommand(ctx, owner, cmd);
    return;
  }
  if (cmd.type.startsWith('situation_')) {
    applySituationCommand(ctx, owner, cmd as SituationCommand);
    return;
  }
  if (cmd.type === 'crisis_action') {
    applyCrisisCommand(ctx, owner, cmd);
    return;
  }
  if ((DIPLOMACY_TYPES as readonly string[]).includes(cmd.type)) {
    applyDiplomacy(ctx, owner, cmd as DiplomacyCommand);
    return;
  }
  if (cmd.type === 'pause' || cmd.type === 'speed') {
    if (owner !== config.hostId) throw new SenderError('Nur der Host steuert die Spielzeit.');
    const c = ctx.db.clock.id.find(1)!;
    if (cmd.type === 'speed' && ![1, 2, 3, 4].includes(cmd.value)) throw new SenderError('Ungültiges Tempo.');
    gameClock(ctx, cmd.type === 'pause' ? !c.paused : c.paused, cmd.type === 'speed' ? cmd.value : c.speed);
    ctx.db.gameSettings.id.update({ ...config, autoPaused: false });
    return;
  }
  if (cmd.type === 'add_ai') {
    if (owner !== config.hostId) throw new SenderError('Nur der Host kann eine KI hinzufügen.');
    const lib = starterLibrary(),
      n = Number(ctx.db.empire.count()) + 1,
      snapshot = snapshotTemplate(lib, lib.empires[n % lib.empires.length].id);
    snapshot.empire.name = `${snapshot.empire.name} ${n}`;
    foundEmpire(ctx, `ai-${n}`, snapshot, true);
    return;
  }
  settleEconomy(ctx, owner, at);
  if (cmd.type.startsWith('colony_') && 'systemId' in cmd && cmd.systemId) {
    const meta = ctx.db.gameSystem.externalId.find(cmd.systemId);
    if (meta && ctx.db.star.id.find(meta.id)?.ownerId === owner) settlePopulation(ctx, meta.id, at);
  }
  const game = commandModel(ctx, owner),
    player = game.players[0],
    beforeEmpire = JSON.stringify(player.empire);
  // Species selection addresses worlds, including each separately settled planet.
  if (cmd.type === 'species_modify')
    for (const world of ctx.db.gamePlanetColony.empireId.filter(owner)) {
      const body = ctx.db.gameObject.id.find(world.id)!;
      const system = game.systems.find(
        (s) => s.id === ctx.db.gameSystem.id.find(world.systemId)!.externalId,
      )!;
      game.systems.push({
        ...system,
        id: world.id,
        planet: colonyPlanet(JSON.parse(body.bodyJson)),
        colony: JSON.parse(world.colonyJson),
        mined: false,
      });
    }
  const oldSystems = new Map(game.systems.map((s) => [s.id, JSON.stringify(s)]));
  if (['move', 'scan', 'colonize'].includes(cmd.type)) {
    const meta = ctx.db.gameFleet.externalId.find((cmd as { fleetId: string }).fleetId);
    const f = meta ? ownedFleet(ctx, meta.id, owner) : undefined;
    if (!f) throw new SenderError('Eigene Flotte nicht gefunden.');
    if (f.battleId) throw new SenderError('Ziehe die Flotte zuerst aus dem Gefecht zurück.');
  }
  // Pure rules validate templates, species, costs, ownership, queues, routes and races.
  try {
    command(game, player.id, cmd);
  } catch (error) {
    // Shared rule rejections must reach the client as reducer failures, not fatal errors.
    // Keep programming errors (TypeError, etc.) visible as internal failures.
    if (error instanceof Error && error.constructor === Error) throw new SenderError(error.message);
    throw error;
  }
  const e = ctx.db.empire.id.find(owner)!;
  if (
    e.energy !== player.resources.energy ||
    e.minerals !== player.resources.minerals ||
    e.data !== player.resources.data
  )
    ctx.db.empire.id.update({ ...e, ...player.resources });
  const p = ctx.db.gamePlayer.id.find(owner)!;
  const instanceChanged = beforeEmpire !== JSON.stringify(player.empire);
  if (instanceChanged) ctx.db.gamePlayer.id.update({ ...p, empireJson: JSON.stringify(player.empire) });
  for (const s of game.systems) {
    if (s.owner !== player.id || JSON.stringify(s) === oldSystems.get(s.id)) continue;
    const planetColony = ctx.db.gamePlanetColony.id.find(s.id);
    if (planetColony) {
      ctx.db.gamePlanetColony.id.update({ ...planetColony, colonyJson: JSON.stringify(s.colony) });
      continue;
    }
    const m = ctx.db.gameSystem.externalId.find(s.id)!;
    ctx.db.gameSystem.id.update({ ...m, mined: s.mined, defense: s.defense, colonyName: s.colonyName || '' });
    updateColony(ctx, m.id, s.colony || null, owner);
  }
  if (instanceChanged)
    triggerSituation(
      ctx,
      owner,
      cmd.type === 'species_modify' ? 'species' : 'modification',
      `change:${player.empire.revision}`,
      p.homeId,
    );
  const jobs = jobsFor(ctx, owner),
    mods = empireModifiers(player.empire);
  if (cmd.type === 'build') {
    const next = player.queue.at(-1)!;
    addJob(
      ctx,
      owner,
      'game_build',
      next.type,
      ctx.db.gameSystem.externalId.find(next.systemId)!.id,
      next.total,
      next.remaining,
      player.queue.length > 1 ? 'queued' : 'active',
    );
  }
  if (cmd.type === 'colony_build' || cmd.type === 'colony_upgrade') {
    const s = game.systems.find((s) => s.id === cmd.systemId)!,
      j = s.colony!.construction!;
    addJob(ctx, owner, 'game_upgrade', j.building, ctx.db.gameSystem.externalId.find(s.id)!.id, j.total);
  }
  if (cmd.type === 'colony_cancel') {
    const id = ctx.db.gameSystem.externalId.find(cmd.systemId)!.id;
    const j = jobs.find((j) => j.kind === 'game_upgrade' && j.targetId === id)!;
    ctx.db.job.id.update({ ...j, status: 'cancelled', dueTick: NEVER });
  }
  if (cmd.type === 'move') {
    const model = game.fleets.find((f) => f.id === cmd.fleetId)!,
      meta = ctx.db.gameFleet.externalId.find(model.id)!,
      f = ctx.db.fleet.id.find(meta.id)!;
    const speed = 24 * (player.techs.includes('propulsion') ? 1.35 : 1) * Math.max(0.1, 1 + mods.speed);
    move(
      ctx,
      { ...f, speed },
      model.route.map((id) => ctx.db.gameSystem.externalId.find(id)!.id),
      at,
    );
  }
  if (cmd.type === 'scan' || cmd.type === 'colonize') {
    const model = game.fleets.find((f) => f.id === cmd.fleetId)!,
      f = ctx.db.gameFleet.externalId.find(model.id)!;
    addJob(ctx, owner, cmd.type === 'scan' ? 'game_scan' : 'game_colonize', '', f.id, model.task!.total);
  }
  if (instanceChanged) {
    for (const s of ctx.db.ship.empireId.filter(owner))
      if (s.design === 'corvette') {
        const weapons = s.weapons.map((w) => ({
          ...w,
          damage: 6.5 * (player.techs.includes('weapons') ? 1.4 : 1) * Math.max(0.1, 1 + mods.damage),
        }));
        ctx.db.ship.id.update({ ...s, weapons });
        const fighter = ctx.db.participant.shipId.find(s.id);
        if (fighter)
          ctx.db.participant.shipId.update({ ...fighter, damage: weapons.reduce((n, w) => n + w.damage, 0) });
      }
    for (const c of ctx.db.colony.empireId.filter(owner)) refreshColonyRate(ctx, c.id, owner);
    for (const j of jobs.filter((j) =>
      ['game_build', 'game_upgrade', 'game_planet_upgrade'].includes(j.kind),
    )) {
      const workDone = j.status === 'active' ? progressAt(j, at) : j.workDone;
      const rate = Math.max(0.1, 1 + mods.construction);
      ctx.db.job.id.update({
        ...j,
        workDone,
        rate,
        updatedAt: at,
        dueTick: j.status === 'active' ? tickAt(at + (j.workTotal - workDone) / rate) : NEVER,
      });
    }
    // Existing travel legs retain their committed duration. Future orders read new modifiers.
  }
  for (const l of game.log) event(ctx, l.playerId ? owner : 0, l.text, l.tone);
}
export const gameCommand = db.reducer({ commandJson: t.string() }, (ctx, { commandJson }) => {
  if (commandJson.length > 24000) throw new SenderError('Befehl zu groß.');
  const owner = member(ctx);
  applyGameCommand(ctx, owner, JSON.parse(commandJson));
});
