import type { Context, ReadContext } from './tables';

export const pairKey = (a: number, b: number) => `${Math.min(a, b)}:${Math.max(a, b)}`;
export function atWar(ctx: Context | ReadContext, a: number, b: number) {
  if (a === b) return false;
  if (!a || !b) return true; // Independent guardians remain hostile.
  return ctx.db.gameRelation.id.find(pairKey(a, b))?.state === 'war';
}
