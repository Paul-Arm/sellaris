import type { Context, ReadContext } from './tables';
import { crisisProductionFactor } from '../../shared/crises';
export const pledgeKey = (crisisId: number, owner: number) => `${crisisId}:${owner}`;
export function productionFactor(ctx: Context | ReadContext, owner: number) {
  let factor = 1;
  for (const c of ctx.db.gameCrisis.iter()) {
    const phase = ctx.db.crisis.id.find(c.id)?.phase || 'dormant';
    const shielded = ctx.db.gameCrisisPledge.id.find(pledgeKey(c.id, owner))?.shielded || false;
    factor = Math.min(factor, crisisProductionFactor(phase, shielded));
  }
  return factor;
}
