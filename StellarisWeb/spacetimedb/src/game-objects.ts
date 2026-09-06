import { SenderError, t } from 'spacetimedb/server';
import { db, type Context } from './tables';
import { gameObject, gameObjectCatalog } from './game-tables';
import { member, now } from './rules';
import { environmentForPlanet } from '../../shared/empires';
import { PLANET_COLORS } from '../../shared/terraforming';
import { generateSystemBodies } from '../../shared/systemGeneration';
import type { CelestialBody } from '../../shared/celestial';
import { objectBodies } from '../../shared/systemObjects';

/** Generate the object catalog once, while initializing a new game. */
export function ensureSystemObjects(ctx: Context) {
  for (const meta of ctx.db.gameSystem.iter()) {
    if (ctx.db.gameObjectCatalog.id.find(meta.id)) continue;
    const star = ctx.db.star.id.find(meta.id)!;
    const bodies = generateSystemBodies({
      id: meta.externalId,
      name: star.name,
      kind: star.kind as 'star' | 'blackhole' | 'rift',
      class: meta.starClass,
      color: meta.color,
      planet: meta.planet,
      colonyName: meta.colonyName,
    });
    for (const body of bodies)
      ctx.db.gameObject.insert({
        id: `${meta.id}:${body.slot}`,
        systemId: meta.id,
        slot: body.slot,
        revision: 1,
        state: 'active',
        changedAt: now(ctx),
        parentId: body.parent === undefined ? '' : `${meta.id}:${body.parent}`,
        bodyJson: JSON.stringify(body),
      });
    ctx.db.gameObjectCatalog.insert({
      id: meta.id,
      nextSlot: Math.max(8, ...bodies.map((b) => b.slot)) + 1,
      mainObjectId: bodies.some((b) => b.main) ? `${meta.id}:1` : '',
    });
  }
}

// Internal event/project primitives; deliberately not exposed as player reducers.
export function addSystemObject(ctx: Context, systemId: number, body: Omit<CelestialBody, 'slot'>) {
  const system = ctx.db.gameObjectCatalog.id.find(systemId);
  if (!system) throw new SenderError('Systemobjekte sind noch nicht übernommen.');
  const slot = system.nextSlot;
  if (body.main || body.stellar || ['star', 'blackhole', 'rift'].includes(body.kind))
    throw new SenderError('Stern- und Kolonieereignisse benötigen eigene Folgeregeln.');
  const parentId = body.parent === undefined ? '' : `${systemId}:${body.parent}`;
  if (parentId && ctx.db.gameObject.id.find(parentId)?.state !== 'active')
    throw new SenderError('Elternkörper nicht verfügbar.');
  const row = {
    id: `${systemId}:${slot}`,
    systemId,
    slot,
    revision: 1,
    state: 'active',
    changedAt: now(ctx),
    parentId,
    bodyJson: JSON.stringify({ ...body, slot }),
  };
  ctx.db.gameObject.insert(row);
  ctx.db.gameObjectCatalog.id.update({ ...system, nextSlot: slot + 1 });
  return row;
}
export function renameSystemObject(ctx: Context, id: string, revision: number, name: string) {
  const row = ctx.db.gameObject.id.find(id);
  if (!row || row.state !== 'active' || row.revision !== revision)
    throw new SenderError('Objekt wurde zwischenzeitlich verändert. Bitte erneut auswählen.');
  const clean = name.trim();
  if (!clean || clean.length > 60 || /[\u0000-\u001f\u007f]/.test(clean))
    throw new SenderError('Der Name muss 1 bis 60 Zeichen enthalten.');
  const body: CelestialBody = JSON.parse(row.bodyJson);
  if (body.slot === 0 || body.main)
    throw new SenderError('Stern und Hauptkolonie behalten ihren Systemnamen.');
  ctx.db.gameObject.id.update({
    ...row,
    bodyJson: JSON.stringify({ ...body, name: clean }),
    revision: row.revision + 1,
    changedAt: now(ctx),
  });
}
export function removeSystemObject(ctx: Context, id: string, revision: number) {
  const row = ctx.db.gameObject.id.find(id);
  if (!row || row.state !== 'active' || row.revision !== revision)
    throw new SenderError('Objekt wurde zwischenzeitlich verändert.');
  const body: CelestialBody = JSON.parse(row.bodyJson);
  if (
    body.slot === 0 ||
    body.main ||
    ctx.db.gameSite.id.find(id) ||
    ctx.db.gameTerraform.id.find(id) ||
    [...ctx.db.gameObject.systemId.filter(row.systemId)].some(
      (r) => r.state === 'active' && r.parentId === id,
    )
  )
    throw new SenderError('Abhängige Anlagen, Kolonien oder Körper müssen zuerst behandelt werden.');
  ctx.db.gameObject.id.update({ ...row, state: 'removed', revision: row.revision + 1, changedAt: now(ctx) });
}
export const renameBody = db.reducer(
  { objectId: t.string(), revision: t.u32(), name: t.string() },
  (ctx, { objectId, revision, name }) => {
    const owner = member(ctx),
      row = ctx.db.gameObject.id.find(objectId);
    if (!row || ctx.db.star.id.find(row.systemId)?.ownerId !== owner)
      throw new SenderError('Nur eigene Himmelskörper können benannt werden.');
    if (ctx.db.gameSettings.id.find(1)?.winnerId) throw new SenderError('Die Partie ist beendet.');
    renameSystemObject(ctx, objectId, revision, name);
  },
);
export const focusSystemObjects = db.reducer({ systemId: t.u32() }, (ctx, { systemId }) => {
  member(ctx);
  if (!ctx.connectionId) throw new SenderError('Verbindung erforderlich.');
  const id = ctx.connectionId.toHexString();
  if (!systemId) {
    ctx.db.gameObjectFocus.id.delete(id);
    return;
  }
  // The atlas is currently public; object details follow that rule, but require membership.
  if (!ctx.db.gameObjectCatalog.id.find(systemId)) throw new SenderError('System nicht verfügbar.');
  const row = { id, identity: ctx.sender, systemId };
  if (ctx.db.gameObjectFocus.id.find(id)) ctx.db.gameObjectFocus.id.update(row);
  else ctx.db.gameObjectFocus.insert(row);
});
export const focusedSystemObjects = db.view(
  { name: 'focused_system_objects', public: true },
  t.array(gameObject.rowType),
  (ctx) => {
    if (!ctx.db.membership.identity.find(ctx.sender)) return [];
    const ids = new Set([...ctx.db.gameObjectFocus.identity.filter(ctx.sender)].map((f) => f.systemId));
    return [...ids].flatMap((id) => [...ctx.db.gameObject.systemId.filter(id)]);
  },
);
export const focusedObjectSystems = db.view(
  { name: 'focused_object_systems', public: true },
  t.array(gameObjectCatalog.rowType),
  (ctx) => {
    if (!ctx.db.membership.identity.find(ctx.sender)) return [];
    const ids = new Set([...ctx.db.gameObjectFocus.identity.filter(ctx.sender)].map((f) => f.systemId));
    return [...ids].flatMap((id) => {
      const row = ctx.db.gameObjectCatalog.id.find(id);
      return row ? [row] : [];
    });
  },
);
export function storedSystemBodies(ctx: Context, id: number) {
  return objectBodies(ctx.db.gameObject.systemId.filter(id));
}
/** Founding and colony naming update the same objects, never their orbits or IDs. */
export function syncPrimaryObjects(ctx: Context, systemId: number) {
  const meta = ctx.db.gameSystem.id.find(systemId)!,
    star = ctx.db.star.id.find(systemId)!;
  const mainId = ctx.db.gameObjectCatalog.id.find(systemId)?.mainObjectId;
  for (const id of [`${systemId}:0`, ...(mainId ? [mainId] : [])]) {
    const row = ctx.db.gameObject.id.find(id);
    if (!row || row.state !== 'active') continue;
    const body: CelestialBody = JSON.parse(row.bodyJson);
    const name = body.main ? meta.colonyName || body.name : star.name;
    const description = body.main ? `${meta.planet}. Die Hauptwelt des Systems.` : body.description;
    const environment = body.main ? environmentForPlanet(meta.planet) : body.environment;
    if (body.name === name && body.description === description && body.environment === environment) continue;
    ctx.db.gameObject.id.update({
      ...row,
      bodyJson: JSON.stringify({
        ...body,
        name,
        description,
        ...(environment ? { environment, color: PLANET_COLORS[environment] } : {}),
      }),
      revision: row.revision + 1,
      changedAt: now(ctx),
    });
  }
}
