import { SenderError, t } from 'spacetimedb/server';
import { db, type Context } from './tables';
import { now, NEVER } from './rules';
import { addJob, event, jobsFor, playerModel, settleEconomy, systemModel } from './game-model';
import {
  colonyProduction,
  createColony,
  growColony,
  applyColonyCommand,
  completeColonyConstruction,
  maxDefense,
  type Colony,
  type ColonyCommand,
} from '../../shared/colonies';
import { colonizableBody, colonyPlanet } from '../../shared/planetColonies';
import type { CelestialBody } from '../../shared/celestial';
import type { Resources, TechId } from '../../shared/game';
import { productionFactor } from './game-crisis-state';

export function planetColonyTarget(ctx: Context, owner: number, systemId: number, slot: number) {
  const object = ctx.db.gameObject.id.find(`${systemId}:${slot}`);
  if (!Number.isSafeInteger(slot) || !object || object.state !== 'active')
    throw new SenderError('Planet nicht verfügbar.');
  const body: CelestialBody = JSON.parse(object.bodyJson);
  if (ctx.db.star.id.find(systemId)?.ownerId !== owner)
    throw new SenderError('Gründe zuerst die Hauptkolonie dieses Systems.');
  if (!ctx.db.gamePlayer.id.find(owner)!.surveyed.includes(systemId))
    throw new SenderError('Untersuche zuerst das System.');
  if (!colonizableBody(body)) throw new SenderError('Dieser Körper ist kein besiedelbarer Nebenplanet.');
  if (ctx.db.gamePlanetColony.id.find(object.id))
    throw new SenderError('Dieser Planet ist bereits besiedelt.');
  return { object, body };
}
export function startPlanetColony(ctx: Context, owner: number, fleetId: number, slot: number) {
  const fleet = ctx.db.fleet.id.find(fleetId)!;
  const { object } = planetColonyTarget(ctx, owner, fleet.systemId, slot);
  if (
    [...ctx.db.job.empireId.filter(owner)].some(
      (j) => j.kind === 'game_colonize' && j.topic === object.id && ['active', 'blocked'].includes(j.status),
    )
  )
    throw new SenderError('Dieser Planet wird bereits kolonisiert.');
  settleEconomy(ctx, owner);
  const e = ctx.db.empire.id.find(owner)!;
  if (e.energy < 80 || e.minerals < 80)
    throw new SenderError('Kolonisierung benötigt 80 Energie und 80 Mineralien.');
  ctx.db.empire.id.update({ ...e, energy: e.energy - 80, minerals: e.minerals - 80 });
  addJob(ctx, owner, 'game_colonize', object.id, fleetId, 12);
}
export function completePlanetColony(
  ctx: Context,
  owner: number,
  objectId: string,
  fleetId: number,
  at: number,
): boolean {
  const f = ctx.db.fleet.id.find(fleetId),
    object = ctx.db.gameObject.id.find(objectId);
  if (!f || f.empireId !== owner || !object || f.systemId !== object.systemId) return false;
  try {
    planetColonyTarget(ctx, owner, object.systemId, object.slot);
  } catch (e) {
    if (e instanceof SenderError) return false;
    throw e;
  }
  const body: CelestialBody = JSON.parse(object.bodyJson),
    empire = JSON.parse(ctx.db.gamePlayer.id.find(owner)!.empireJson),
    colony = createColony(false, `${ctx.db.gameSettings.id.find(1)!.code}:${object.id}`, colonyPlanet(body));
  colony.populations = [{ speciesId: empire.primarySpeciesId, population: colony.population }];
  ctx.db.gamePlanetColony.insert({
    id: object.id,
    systemId: object.systemId,
    empireId: owner,
    colonyJson: JSON.stringify(colony),
    growthAt: at,
    lastProducedAt: at,
  });
  event(ctx, owner, `${body.name} besiedelt. Eine weitere Kolonie im System ist gegründet.`, 'success');
  return true;
}
/** Settle the old climate/empire/building state before any change to its inputs. */
export function settlePlanetColonies(ctx: Context, owner: number, at: number): Resources {
  const p = ctx.db.gamePlayer.id.find(owner)!,
    player = { techs: p.techs as TechId[], empire: JSON.parse(p.empireJson) },
    result = { energy: 0, minerals: 0, data: 0 };
  for (const row of ctx.db.gamePlanetColony.empireId.filter(owner)) {
    const object = ctx.db.gameObject.id.find(row.id);
    if (!object || object.state !== 'active' || ctx.db.star.id.find(row.systemId)?.ownerId !== owner)
      continue;
    const body: CelestialBody = JSON.parse(object.bodyJson),
      colony: Colony = JSON.parse(row.colonyJson),
      planet = colonyPlanet(body),
      n = Math.floor(Math.max(0, at - row.lastProducedAt) / 4),
      elapsed = Math.max(0, at - row.growthAt);
    if (!n && !elapsed) continue;
    const rate = colonyProduction(
      {
        ...systemModel(ctx, row.systemId),
        colony,
        planet,
        mined: false,
        productionFactor: productionFactor(ctx, owner),
      },
      player,
    );
    for (const r of ['energy', 'minerals', 'data'] as const) result[r] += rate[r] * n;
    growColony(colony, planet, player, elapsed);
    ctx.db.gamePlanetColony.id.update({
      ...row,
      colonyJson: JSON.stringify(colony),
      growthAt: at,
      lastProducedAt: row.lastProducedAt + n * 4,
    });
  }
  return result;
}
export function applyPlanetColonyCommand(ctx: Context, owner: number, cmd: ColonyCommand) {
  const system = ctx.db.gameSystem.externalId.find(cmd.systemId);
  if (!system || ctx.db.star.id.find(system.id)?.ownerId !== owner || !Number.isSafeInteger(cmd.bodySlot))
    throw new SenderError('Eigene Planetenkolonie nicht gefunden.');
  const id = `${system.id}:${cmd.bodySlot}`;
  if (ctx.db.gamePlanetColony.id.find(id)?.empireId !== owner)
    throw new SenderError('Eigene Planetenkolonie nicht gefunden.');
  settleEconomy(ctx, owner);
  const row = ctx.db.gamePlanetColony.id.find(id)!,
    object = ctx.db.gameObject.id.find(id)!;
  const model = {
    ...systemModel(ctx, system.id),
    colony: JSON.parse(row.colonyJson) as Colony,
    planet: colonyPlanet(JSON.parse(object.bodyJson)),
    mined: false,
  };
  const player = playerModel(ctx, owner, now(ctx));
  try {
    applyColonyCommand(model, player, cmd);
  } catch (e) {
    if (e instanceof Error && e.constructor === Error) throw new SenderError(e.message);
    throw e;
  }
  ctx.db.empire.id.update({ ...ctx.db.empire.id.find(owner)!, ...player.resources });
  ctx.db.gamePlanetColony.id.update({ ...row, colonyJson: JSON.stringify(model.colony) });
  const meta = ctx.db.gameSystem.id.find(system.id)!;
  ctx.db.gameSystem.id.update({
    ...meta,
    defense: Math.min(meta.defense, maxDefense(systemModel(ctx, system.id))),
  });
  if (cmd.type === 'colony_build' || cmd.type === 'colony_upgrade')
    addJob(ctx, owner, 'game_planet_upgrade', id, system.id, model.colony.construction!.total);
  if (cmd.type === 'colony_cancel') {
    const job = jobsFor(ctx, owner).find((j) => j.kind === 'game_planet_upgrade' && j.topic === id);
    if (job) ctx.db.job.id.update({ ...job, status: 'cancelled', dueTick: NEVER });
  }
}
export function completePlanetUpgrade(ctx: Context, owner: number, id: string, at: number): string {
  settleEconomy(ctx, owner, at);
  const row = ctx.db.gamePlanetColony.id.find(id);
  if (!row || row.empireId !== owner || ctx.db.star.id.find(row.systemId)?.ownerId !== owner)
    return 'cancelled';
  const colony: Colony = JSON.parse(row.colonyJson);
  if (!colony.construction) return 'cancelled';
  const before = maxDefense(systemModel(ctx, row.systemId));
  completeColonyConstruction(colony);
  ctx.db.gamePlanetColony.id.update({ ...row, colonyJson: JSON.stringify(colony) });
  const after = maxDefense(systemModel(ctx, row.systemId)),
    meta = ctx.db.gameSystem.id.find(row.systemId)!;
  ctx.db.gameSystem.id.update({
    ...meta,
    defense: Math.min(after, meta.defense + Math.max(0, after - before)),
  });
  event(
    ctx,
    owner,
    `Ausbau auf ${JSON.parse(ctx.db.gameObject.id.find(id)!.bodyJson).name} abgeschlossen.`,
    'success',
  );
  return 'complete';
}
export const myPlanetColonies = db.view(
  { name: 'my_planet_colonies', public: true },
  t.array(
    t.row('PlanetColonyRow', {
      id: t.string().primaryKey(),
      systemId: t.u32(),
      bodySlot: t.u32(),
      bodyJson: t.string(),
      colonyJson: t.string(),
    }),
  ),
  (ctx) => {
    const member = ctx.db.membership.identity.find(ctx.sender);
    return member
      ? [...ctx.db.gamePlanetColony.empireId.filter(member.empireId)].flatMap((c) => {
          const body = ctx.db.gameObject.id.find(c.id);
          return body?.state === 'active' && ctx.db.star.id.find(c.systemId)?.ownerId === member.empireId
            ? [
                {
                  id: c.id,
                  systemId: c.systemId,
                  bodySlot: body.slot,
                  bodyJson: body.bodyJson,
                  colonyJson: c.colonyJson,
                },
              ]
            : [];
        })
      : [];
  },
);
