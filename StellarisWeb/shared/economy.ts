import { resourceAmounts, type Resource, type Resources } from './resources';

export const ECONOMY_MONTH_DAYS = 30;
export const monthAt = (day: number) => Math.floor((day + 1e-8) / ECONOMY_MONTH_DAYS);
export const monthBoundary = (day: number) => monthAt(day) * ECONOMY_MONTH_DAYS;
export const monthsDue = (from: number, to: number) => Math.max(0, monthAt(to) - monthAt(from));
export function economyDate(day: number) {
  const month = monthAt(day);
  return `${2200 + Math.floor(month / 12)}.${String((month % 12) + 1).padStart(2, '0')}.${String((Math.floor(day + 1e-8) % ECONOMY_MONTH_DAYS) + 1).padStart(2, '0')}`;
}

export type EconomyCategory =
  | 'base'
  | 'jobs'
  | 'mining'
  | 'installations'
  | 'upkeep'
  | 'synthesis'
  | 'population'
  | 'compute'
  | 'housing'
  | 'supply'
  | 'growth'
  | 'defense'
  | 'repair';
export const ECONOMY_CATEGORIES: Record<EconomyCategory, string> = {
  base: 'Grundversorgung',
  jobs: 'Arbeitsplätze',
  mining: 'Orbitaler Bergbau',
  installations: 'Anlagen',
  upkeep: 'Gebäudeunterhalt',
  synthesis: 'Datensynthese',
  population: 'Bevölkerung & Regierung',
  compute: 'Rechenleistung',
  housing: 'Wohnraum',
  supply: 'Versorgung',
  growth: 'Bevölkerungswachstum',
  defense: 'Verteidigung',
  repair: 'Reparatur',
};
/** Percent bonuses stack additively, factors multiplicatively. Negative percentages are debuffs.
 * Selectors are conjunctive; omitted selectors match everything. No per-pop objects are needed. */
export interface EconomyModifier {
  id: string;
  name: string;
  category?: EconomyCategory;
  resource?: Resource;
  job?: string;
  speciesId?: string;
  flat?: number;
  percent?: number;
  factor?: number;
}
export interface EconomyContext {
  category: EconomyCategory;
  resource?: Resource;
  job?: string;
  speciesId?: string;
}
export interface AppliedModifier {
  id: string;
  name: string;
  delta: number;
}
export function modifyEconomy(base: number, modifiers: readonly EconomyModifier[], context: EconomyContext) {
  let flat = 0,
    percent = 0,
    factor = 1;
  const applied: AppliedModifier[] = [];
  let previous = Math.max(0, base);
  for (const m of modifiers) {
    if (
      (m.category && m.category !== context.category) ||
      (m.resource && m.resource !== context.resource) ||
      (m.job && m.job !== context.job) ||
      (m.speciesId && m.speciesId !== context.speciesId)
    )
      continue;
    flat += m.flat ?? 0;
    percent += m.percent ?? 0;
    factor *= Math.max(0, m.factor ?? 1);
    const next = Math.max(0, base + flat) * Math.max(0, 1 + percent) * factor;
    applied.push({ id: m.id, name: m.name, delta: next - previous });
    previous = next;
  }
  return { amount: previous, modifiers: applied };
}
export interface EconomyLine {
  systemId?: string;
  worldId?: string;
  id: string;
  source: string;
  category: EconomyCategory;
  resource: Resource;
  base: number;
  amount: number;
  modifiers: AppliedModifier[];
  species?: string;
  employed?: number;
}
export function economyLine(
  id: string,
  source: string,
  base: number,
  modifiers: readonly EconomyModifier[],
  context: EconomyContext & { resource: Resource },
  expense = false,
): EconomyLine {
  const result = modifyEconomy(base, modifiers, context),
    sign = expense ? -1 : 1;
  return {
    id,
    source,
    category: context.category,
    resource: context.resource,
    base: base * sign,
    amount: result.amount * sign,
    modifiers: result.modifiers.map((m) => ({ ...m, delta: m.delta * sign })),
  };
}
export function economyTotals(lines: readonly EconomyLine[]): Resources {
  const totals = resourceAmounts();
  for (const line of lines) totals[line.resource] += line.amount;
  return totals;
}
export function resourceBalance(lines: readonly EconomyLine[], resource: Resource) {
  const entries = lines.filter((l) => l.resource === resource && (l.amount !== 0 || l.base !== 0));
  const income = entries.reduce((n, l) => n + Math.max(0, l.amount), 0);
  const expenses = entries.reduce((n, l) => n - Math.min(0, l.amount), 0);
  return { entries, income, expenses, net: income - expenses };
}
