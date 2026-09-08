import { MODIFIER_NAMES, type Modifier, type Modifiers } from './empireCatalog';
import type { Government, SpeciesDesign } from './empires';
import { coreRules } from './rules/catalog';
import { EMPIRE_STAT_IDS } from './rules/empire-content';
import type { RuleResult, RuleSource } from './rules/types';

function run(kind: string, selection: { definition: string; stacks?: number }[]): RuleResult {
  const owner = 'subject';
  const sources: RuleSource[] = selection.map((s) => ({ id: s.definition, owner, ...s }));
  return coreRules.evaluate({ target: owner, tick: 0, entities: { [owner]: { id: owner, kind } } }, sources);
}
export function evaluateGovernmentRules(government: Government, origin: string): RuleResult {
  return run('empire', [
    { definition: `empire.kind.${government.kind}` },
    { definition: `empire.authority.${government.authority}` },
    { definition: `empire.origin.${origin}` },
    ...government.ethics.map((e) => ({ definition: `empire.ethic.${e.id}`, stacks: e.strength })),
    ...government.civics.map((id) => ({ definition: `empire.civic.${id}` })),
  ]);
}
export function evaluateSpeciesRules(species: Pick<SpeciesDesign, 'kind' | 'traits'>): RuleResult {
  return run('species', [
    { definition: `species.lifeform.${species.kind}` },
    ...species.traits.map((id) => ({ definition: `species.${id}` })),
  ]);
}
function ruleModifiers(result: RuleResult): Modifiers {
  return Object.fromEntries(
    (Object.keys(MODIFIER_NAMES) as Modifier[]).map((id) => [
      id,
      id === 'habitability'
        ? result.stats[EMPIRE_STAT_IDS[id]].flat
        : result.stats[EMPIRE_STAT_IDS[id]].percent,
    ]),
  ) as Modifiers;
}
// Tick loops repeatedly request identical immutable designs. Keep only numeric deltas in a bounded cache;
// callers receive fresh objects and reforms/variants naturally use new keys.
const cache = new Map<string, Modifiers>();
function cached(key: string, calculate: () => RuleResult): Modifiers {
  let result = cache.get(key);
  if (!result) {
    result = ruleModifiers(calculate());
    if (cache.size >= 256) cache.delete(cache.keys().next().value!);
    cache.set(key, result);
  }
  return { ...result };
}
export function governmentRuleModifiers(government: Government, origin: string): Modifiers {
  return cached(`government:${JSON.stringify(government)}:${origin}`, () =>
    evaluateGovernmentRules(government, origin),
  );
}
export function speciesRuleModifiers(species: Pick<SpeciesDesign, 'kind' | 'traits'>): Modifiers {
  return cached(`species:${species.kind}:${JSON.stringify(species.traits)}`, () =>
    evaluateSpeciesRules(species),
  );
}
