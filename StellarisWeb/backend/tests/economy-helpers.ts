import type { GameView } from '../../shared/game';
import { empireLedger } from '../../shared/empireEconomy';
import { economyTotals, type EconomyCategory } from '../../shared/economy';
export const categoryIncome = (view: GameView, category: EconomyCategory) =>
  economyTotals(empireLedger(view, view.me).filter((line) => line.category === category));
export const planetIncome = (view: GameView) => {
  const prefixes = (view.planetColonies ?? []).map((c) => `${c.systemId}:${c.bodySlot}:`);
  return economyTotals(
    empireLedger(view, view.me).filter((line) => prefixes.some((prefix) => line.id.startsWith(prefix))),
  );
};

/** Orbital installations only; the installations category also contains starbase income/upkeep. */
export const siteIncome = (view: GameView) =>
  economyTotals(empireLedger(view, view.me).filter((line) => line.id.startsWith('site:')));
