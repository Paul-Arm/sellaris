import { Range } from 'spacetimedb/server';
import { progressAt, positionAt } from '../../backend/domain';
import { baseIncome, colonyProduction, growColony, type Colony } from '../../shared/colonies';
import {
  SHIPS,
  type GameState,
  type Player,
  type StarSystem,
  type ShipType,
  type TechId,
} from '../../shared/game';
import { empireModifiers, populationGrowth, type EmpireState } from '../../shared/empireState';
import { environmentForPlanet } from '../../shared/empires';
import { type Context, type ReadContext } from './tables';
import { NEVER, now, tickAt } from './rules';
import { atWar } from './game-relations';
import { productionFactor } from './game-crisis-state';
import { facilityYield, type Facility } from '../../shared/celestial';
import { syncPrimaryObjects } from './game-objects';

export const dueJobs = (at: number) =>
  new Range<bigint>({ tag: 'included', value: 0n }, { tag: 'included', value: tickAt(at) });
export function event(ctx: Context, owner: number, text: string, tone = 'info') {
  ctx.db.gameEvent.insert({ id: 0, empireId: owner, tick: now(ctx), text, tone });
  const rows = [...ctx.db.gameEvent.empireId.filter(owner)].sort((a, b) => a.id - b.id);
  for (const row of rows.slice(0, Math.max(0, rows.length - 64))) ctx.db.gameEvent.id.delete(row.id);
}
export function systemModel(ctx: Context | ReadContext, id: number): StarSystem {
  const s = ctx.db.star.id.find(id)!,
    m = ctx.db.gameSystem.id.find(id)!;
  return {
    id: m.externalId,
    name: s.name,
    x: s.x,
    y: s.y,
    kind: s.kind as StarSystem['kind'],
    color: m.color,
    class: m.starClass,
    planet: m.planet,
    owner: s.ownerId ? ctx.db.gamePlayer.id.find(s.ownerId)!.externalId : null,
    resources: { energy: m.energy, minerals: m.minerals, science: m.science },
    productionFactor: s.ownerId ? productionFactor(ctx, s.ownerId) : 1,
    defense: m.defense,
    mined: m.mined,
    anomaly: m.anomaly,
    studied: m.studied,
    colony: m.colonyJson ? JSON.parse(m.colonyJson) : null,
    colonyName: m.colonyName || undefined,
  };
}
export function jobsFor(ctx: Context | ReadContext, owner: number) {
  return [...ctx.db.job.empireId.filter(owner)]
    .filter((j) => j.kind.startsWith('game_') && ['active', 'queued', 'blocked'].includes(j.status))
    .sort((a, b) => a.id - b.id);
}
export function playerModel(ctx: Context | ReadContext, owner: number, at: number): Player {
  const e = ctx.db.empire.id.find(owner)!,
    p = ctx.db.gamePlayer.id.find(owner)!,
    summary = ctx.db.empireSummary.id.find(owner)!;
  const jobs = jobsFor(ctx, owner),
    research = jobs.find((j) => j.kind === 'game_research');
  const remaining = (j: (typeof jobs)[number]) =>
    j.workTotal - (j.status === 'active' ? progressAt(j, at) : j.workDone);
  return {
    id: p.externalId,
    name: summary.name,
    color: `#${summary.color.toString(16).padStart(6, '0')}`,
    home: ctx.db.gameSystem.id.find(p.homeId)!.externalId,
    resources: { energy: e.energy, minerals: e.minerals, science: e.science },
    techs: p.techs as TechId[],
    surveyed: p.surveyed.map((id) => ctx.db.gameSystem.id.find(id)!.externalId),
    discovered: p.discovered.map((id) => ctx.db.gameSystem.id.find(id)!.externalId),
    empire: JSON.parse(p.empireJson),
    online: ctx.db.gamePresence.id.find(owner)?.online ?? false,
    ai: e.ai ? { startedAt: p.joinedAt, nextDecision: Number(e.nextDecisionTick) / 1000 } : undefined,
    research: research
      ? { id: research.topic as TechId, total: research.workTotal, remaining: remaining(research) }
      : null,
    queue: jobs
      .filter((j) => j.kind === 'game_build')
      .map((j) => ({
        type: j.topic as ShipType,
        systemId: ctx.db.gameSystem.id.find(j.targetId)!.externalId,
        total: j.workTotal,
        remaining: remaining(j),
      })),
  };
}
/** Compatibility facade for pure command validation, never a stored/broadcast world blob.
 * Reads strategic rows and this player's projects, not individual ship tables. */
export function commandModel(ctx: Context, owner: number): GameState {
  const at = now(ctx),
    config = ctx.db.gameSettings.id.find(1)!,
    clock = ctx.db.clock.id.find(1)!;
  const player = playerModel(ctx, owner, at),
    jobs = jobsFor(ctx, owner);
  const systems = [...ctx.db.star.iter()].map((s) => {
    const model = systemModel(ctx, s.id);
    // Peaceful foreign defenses do not obstruct civilian routing or surveying.
    if (s.ownerId && s.ownerId !== owner && !atWar(ctx, owner, s.ownerId)) model.defense = 0;
    return model;
  });
  for (const j of jobs.filter((j) => j.kind === 'game_upgrade')) {
    const c = systems.find((s) => s.id === ctx.db.gameSystem.id.find(j.targetId)!.externalId)?.colony;
    if (c?.construction) c.construction.remaining = j.workTotal - progressAt(j, at);
  }
  return {
    version: 1,
    code: config.code,
    tick: at,
    speed: clock.speed,
    paused: clock.paused,
    hostId: ctx.db.gamePlayer.id.find(config.hostId)?.externalId || '',
    winner: config.winnerId ? ctx.db.gamePlayer.id.find(config.winnerId)!.externalId : null,
    systems,
    links: [...ctx.db.gameLane.iter()].map((l) => [
      ctx.db.gameSystem.id.find(l.a)!.externalId,
      ctx.db.gameSystem.id.find(l.b)!.externalId,
    ]),
    players: [player],
    log: [],
    nextId: 1,
    fleets: [...ctx.db.fleet.empireId.filter(owner)].map((f) => {
      const m = ctx.db.gameFleet.id.find(f.id)!;
      const task = jobs.find((j) => ['game_scan', 'game_colonize'].includes(j.kind) && j.targetId === f.id);
      return {
        id: m.externalId,
        owner: player.id,
        name: f.name,
        type: m.kind as ShipType,
        systemId: ctx.db.gameSystem.id.find(f.systemId || m.lastSystemId)!.externalId,
        route: f.route.map((id) => ctx.db.gameSystem.id.find(id)!.externalId),
        progress: f.route.length
          ? Math.min(1, (at - f.departedAt) / Math.max(0.001, f.arrivesAt - f.departedAt))
          : 0,
        duration: f.arrivesAt - f.departedAt,
        hp: 100,
        task: task
          ? {
              type: task.kind === 'game_scan' ? ('scan' as const) : ('colonize' as const),
              total: task.workTotal,
              remaining: task.workTotal - (task.status === 'active' ? progressAt(task, at) : task.workDone),
              blocked: task.status === 'blocked',
            }
          : null,
      };
    }),
  };
}
export function updateColony(ctx: Context, id: number, colony: Colony | null, owner: number) {
  syncPrimaryObjects(ctx, id);
  const m = ctx.db.gameSystem.id.find(id)!;
  ctx.db.gameSystem.id.update({ ...m, colonyJson: colony ? JSON.stringify(colony) : '' });
  for (const c of ctx.db.cohort.colonyId.filter(id)) ctx.db.cohort.id.delete(c.id);
  if (!colony) {
    for (const project of [...ctx.db.gameTerraform.systemId.filter(id)]) {
      ctx.db.gameTerraform.id.delete(project.id);
      event(
        ctx,
        project.empireId,
        'Terraforming durch Verlust des Systems beendet; Kosten verloren.',
        'warning',
      );
    }
    ctx.db.colony.id.delete(id);
    return;
  }
  for (const group of colony.populations || [])
    ctx.db.cohort.insert({
      id: 0,
      colonyId: id,
      empireId: owner,
      species: group.speciesId,
      job: 'population',
      count: Math.round(group.population * 1000000),
      productivity: 1,
      happiness: 0.75,
    });
  refreshColonyRate(ctx, id, owner);
}
export function settlePopulation(ctx: Context, id: number, at = now(ctx), force = false) {
  const meta = ctx.db.gameSystem.id.find(id)!,
    owner = ctx.db.star.id.find(id)!.ownerId;
  if (!owner || !meta.colonyJson) return;
  const elapsed = Math.max(0, at - meta.growthAt);
  if (elapsed <= 0 || (!force && elapsed < 4)) return;
  const colony: Colony = JSON.parse(meta.colonyJson);
  const empire: EmpireState = JSON.parse(ctx.db.gamePlayer.id.find(owner)!.empireJson);
  growColony(colony, meta.planet, { empire }, elapsed);
  ctx.db.gameSystem.id.update({ ...meta, growthAt: at });
  updateColony(ctx, id, colony, owner);
}
export function refreshColonyRate(ctx: Context, id: number, owner: number) {
  const s = systemModel(ctx, id),
    p = ctx.db.gamePlayer.id.find(owner)!;
  const rate = colonyProduction(s, { techs: p.techs as TechId[], empire: JSON.parse(p.empireJson) });
  const old = ctx.db.colony.id.find(id);
  const row = {
    id,
    empireId: owner,
    population: Math.round((s.colony?.population || 0) * 1000000),
    energyRate: rate.energy,
    mineralsRate: rate.minerals,
    scienceRate: rate.science,
    lastProducedAt: old?.lastProducedAt ?? now(ctx),
  };
  if (old) ctx.db.colony.id.update(row);
  else ctx.db.colony.insert(row);
}
export function makeShip(
  ctx: Context,
  owner: number,
  systemId: number,
  kind: ShipType,
  options: { fleetId?: number; name?: string; externalId?: string; hp?: number } = {},
) {
  const s = ctx.db.star.id.find(systemId)!,
    p = ctx.db.gamePlayer.id.find(owner)!,
    instance: EmpireState = JSON.parse(p.empireJson),
    mods = empireModifiers(instance);
  const speed = 24 * (p.techs.includes('propulsion') ? 1.35 : 1) * Math.max(0.1, 1 + mods.speed);
  let f = options.fleetId ? ctx.db.fleet.id.find(options.fleetId) : undefined;
  if (!f) {
    f = ctx.db.fleet.insert({
      id: 0,
      empireId: owner,
      name: options.name || `${SHIPS[kind].name}`,
      systemId,
      shipCount: 0,
      formation: 'wedge',
      order: 'idle',
      battleId: 0,
      route: [],
      fromX: s.x,
      fromY: s.y,
      toX: s.x,
      toY: s.y,
      departedAt: now(ctx),
      arrivesAt: now(ctx),
      speed,
      revision: 0,
    });
    ctx.db.gameFleet.insert({
      id: f.id,
      externalId: options.externalId || `nf${f.id}`,
      kind,
      lastSystemId: systemId,
      retreatUntil: 0,
    });
  }
  const ship = ctx.db.ship.insert({
    id: 0,
    empireId: owner,
    fleetId: f.id,
    name: options.name || `${instance.design.shipPrefix} ${kind} ${f.shipCount + 1}`,
    design: kind,
    hull: options.hp ?? 100,
    maxHull: 100,
    shield: kind === 'corvette' ? 20 : 0,
    maxShield: kind === 'corvette' ? 20 : 0,
    armor: kind === 'corvette' ? 0.1 : 0,
    experience: 0,
    reactor: 'fusion-i',
    drive: 'warp-i',
    abilities: kind === 'scout' ? ['survey'] : kind === 'colony' ? ['colonize'] : ['evasive-burst'],
    weapons:
      kind === 'corvette'
        ? [
            {
              kind: 'pulse-laser',
              damage: 6.5 * (p.techs.includes('weapons') ? 1.4 : 1) * Math.max(0.1, 1 + mods.damage),
              range: 120,
              cooldown: 1.2,
            },
          ]
        : [],
  });
  ctx.db.fleet.id.update({ ...f, shipCount: f.shipCount + 1, revision: f.revision + 1 });
  refreshFleetCondition(ctx, f.id);
  if (ship.hull < ship.maxHull) ctx.db.gameDamaged.insert({ id: ship.id, fleetId: f.id });
  return { fleetId: f.id, shipId: ship.id };
}
export function refreshFleetCondition(ctx: Context, id: number) {
  let hull = 0,
    maxHull = 0,
    shield = 0;
  for (const s of ctx.db.ship.fleetId.filter(id)) {
    hull += s.hull;
    maxHull += s.maxHull;
    shield += s.shield;
  }
  const previous = ctx.db.gameFleetCondition.id.find(id),
    row = { id, hull, maxHull, shield };
  if (previous) {
    if (previous.hull !== hull || previous.maxHull !== maxHull || previous.shield !== shield)
      ctx.db.gameFleetCondition.id.update(row);
  } else ctx.db.gameFleetCondition.insert(row);
}
export function addJob(
  ctx: Context,
  owner: number,
  kind: string,
  topic: string,
  targetId: number,
  total: number,
  remaining = total,
  status = 'active',
) {
  const at = now(ctx),
    p = ctx.db.gamePlayer.id.find(owner)!;
  const mods = empireModifiers(JSON.parse(p.empireJson));
  const rate =
    kind === 'game_research'
      ? Math.max(0.1, 1 + mods.research)
      : ['game_build', 'game_upgrade'].includes(kind)
        ? Math.max(0.1, 1 + mods.construction)
        : 1;
  return ctx.db.job.insert({
    id: 0,
    empireId: owner,
    kind,
    topic,
    targetId,
    workTotal: total,
    workDone: total - remaining,
    rate,
    updatedAt: at,
    dueTick: status === 'active' ? tickAt(at + remaining / rate) : NEVER,
    status,
  });
}
export function settleEconomy(ctx: Context, owner: number, at = now(ctx)) {
  const e = ctx.db.empire.id.find(owner)!,
    p = ctx.db.gamePlayer.id.find(owner)!;
  const base = baseIncome({ techs: p.techs as TechId[] });
  const anchor = ctx.db.gameIncome.id.find(owner)!;
  const cycles = Math.floor(Math.max(0, at - anchor.producedAt) / 4);
  if (cycles) ctx.db.gameIncome.id.update({ ...anchor, producedAt: anchor.producedAt + cycles * 4 });
  let energy = base.energy * cycles,
    minerals = base.minerals * cycles,
    science = base.science * cycles;
  for (const c of ctx.db.colony.empireId.filter(owner)) {
    const n = Math.floor(Math.max(0, at - c.lastProducedAt) / 4);
    if (!n) continue;
    energy += c.energyRate * n;
    minerals += c.mineralsRate * n;
    science += c.scienceRate * n;
    ctx.db.colony.id.update({ ...c, lastProducedAt: c.lastProducedAt + n * 4 });
  }
  const factor = productionFactor(ctx, owner);
  for (const site of ctx.db.gameSite.empireId.filter(owner)) {
    const n = Math.floor(Math.max(0, at - site.lastProducedAt) / 4);
    if (!n) continue;
    const star = ctx.db.star.id.find(site.systemId)!;
    if (star.kind !== 'star' || star.ownerId === owner) {
      const rate = facilityYield(site.facility as Facility, site.level, factor);
      energy += rate.energy * n;
      minerals += rate.minerals * n;
      science += rate.science * n;
    }
    ctx.db.gameSite.id.update({ ...site, lastProducedAt: site.lastProducedAt + n * 4 });
  }
  if (energy || minerals || science)
    ctx.db.empire.id.update({
      ...e,
      energy: e.energy + energy,
      minerals: e.minerals + minerals,
      science: e.science + science,
    });
}
