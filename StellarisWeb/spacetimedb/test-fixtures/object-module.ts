// Compiled only by system-objects.test.ts, never part of the production entry point.
export * from '../src/index';
export { default } from '../src/index';
import { db } from '../src/tables';
import { t } from 'spacetimedb/server';
import { admin } from '../src/rules';
import { addSystemObject, removeSystemObject } from '../src/game-objects';
import { updateColony } from '../src/game-model';
export const fixtureLoseSystem = db.reducer({ systemId: t.u32() }, (ctx, { systemId }) => {
  admin(ctx);
  const star = ctx.db.star.id.find(systemId)!;
  ctx.db.star.id.update({ ...star, ownerId: 0 });
  updateColony(ctx, systemId, null, star.ownerId);
});
export const fixtureEmpty = db.reducer({ systemId: t.u32() }, (ctx, { systemId }) => {
  admin(ctx);
  for (const row of [...ctx.db.gameObject.systemId.filter(systemId)]) ctx.db.gameObject.id.delete(row.id);
});
export const fixtureObject = db.reducer(
  { systemId: t.u32(), removeId: t.string(), revision: t.u32() },
  (ctx, { systemId, removeId, revision }) => {
    admin(ctx);
    if (removeId) removeSystemObject(ctx, removeId, revision);
    else
      addSystemObject(ctx, systemId, {
        name: 'Testmond',
        kind: 'moon',
        color: '#a2c3cd',
        radius: 8,
        orbit: 1100,
        phase: 0,
        period: 6000,
        description: 'Integration fixture',
      });
  },
);
