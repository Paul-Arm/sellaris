import type { Context } from './tables';
import { settleEconomy, settlePopulation, refreshColonyRate } from './game-model';
import { dysonHost } from '../../shared/megastructures';
import { collapsedStar, frozenPlanet } from '../../shared/stellarProjects';
import type { CelestialBody } from '../../shared/celestial';
import { ENVIRONMENTS } from '../../shared/empireCatalog';

/** Atomic consequences of an engineered stellar collapse. */
export function collapseSystemStar(ctx: Context, objectId: string, at: number) {
  const object = ctx.db.gameObject.id.find(objectId);
  if (!object || object.state !== 'active') return false;
  const body: CelestialBody = JSON.parse(object.bodyJson);
  if (!dysonHost(body)) return false;
  const owner = ctx.db.star.id.find(object.systemId)!.ownerId;
  // Settle the old production and population before changing stellar/planetary conditions.
  if (owner) settleEconomy(ctx, owner, at);
  settlePopulation(ctx, object.systemId, at);
  const meta = ctx.db.gameSystem.id.find(object.systemId)!;
  const star = collapsedStar(body);
  ctx.db.gameObject.id.update({
    ...object,
    bodyJson: JSON.stringify(star),
    revision: object.revision + 1,
    changedAt: at,
  });
  ctx.db.gameSystem.id.update({
    ...meta,
    starClass: 'NS',
    color: star.color,
    planet: meta.colonyJson ? ENVIRONMENTS.arctic.name : meta.planet,
  });
  for (const row of ctx.db.gameObject.systemId.filter(object.systemId)) {
    if (row.state !== 'active') continue;
    const old: CelestialBody = JSON.parse(row.bodyJson),
      frozen = frozenPlanet(old);
    if (frozen !== old) {
      ctx.db.gameTerraform.id.delete(row.id);
      ctx.db.gameObject.id.update({
        ...row,
        bodyJson: JSON.stringify(frozen),
        revision: row.revision + 1,
        changedAt: at,
      });
      if (old.main && !meta.colonyJson)
        ctx.db.gameSystem.id.update({
          ...ctx.db.gameSystem.id.find(object.systemId)!,
          planet: ENVIRONMENTS.arctic.name,
        });
    }
  }
  // Remove every Dyson construction stage and all solar production, including upgrades.
  for (const row of [...ctx.db.gameObject.systemId.filter(object.systemId)]) {
    if (row.state !== 'active' || row.parentId !== object.id) continue;
    if (JSON.parse(row.bodyJson).megastructure !== 'dyson') continue;
    ctx.db.gameSite.id.delete(row.id);
    ctx.db.gameObject.id.update({ ...row, state: 'destroyed', revision: row.revision + 1, changedAt: at });
  }
  for (const site of [...ctx.db.gameSite.systemId.filter(object.systemId)])
    if (site.bodySlot === object.slot && site.facility === 'solar') ctx.db.gameSite.id.delete(site.id);
  if (owner && meta.colonyJson) refreshColonyRate(ctx, object.systemId, owner);
  return true;
}
