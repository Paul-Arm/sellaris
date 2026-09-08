import { type EconomyLine } from './economy';
import { productionComputeBonus } from './research';
import type { Player } from './game';

export type ComputePlayer = Partial<Pick<Player, 'compute' | 'research' | 'empire'>>;

/** Only material output is optimized. Upkeep, data and Compute never feed back into capacity. */
export function optimizeProduction(lines: EconomyLine[], player: ComputePlayer) {
  const bonus = productionComputeBonus(((player.compute ?? 0) * (player.research?.production ?? 0)) / 100);
  if (!bonus) return lines;
  for (const line of lines) {
    if (
      line.amount <= 0 ||
      !['jobs', 'mining', 'installations'].includes(line.category) ||
      !['energy', 'minerals'].includes(line.resource)
    )
      continue;
    line.modifiers.push({
      id: 'compute-production',
      name: 'Compute: Produktionsoptimierung',
      delta: line.amount * bonus,
    });
    line.amount *= 1 + bonus;
  }
  return lines;
}
