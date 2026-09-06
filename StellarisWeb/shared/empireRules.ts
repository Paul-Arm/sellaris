import {
  AUTHORITIES,
  CIVICS,
  EMPIRE_KINDS,
  ETHICS,
  MODIFIER_NAMES,
  ORIGINS,
  SPECIES_KINDS,
  TRAITS,
  type Choice,
  type Modifier,
  type Modifiers,
} from './empireCatalog';
import type { Government, SpeciesDesign } from './empires';
import { createRuleEngine } from './rules/engine';
import type { RuleCatalog, RuleDefinition, RuleResult, RuleSource } from './rules/types';

/** Version-1 save adapter. These values remain additive deltas, including legacy wasteful. */
const definitions: Record<string, RuleDefinition> = {};
for (const [category, choices, kind] of [
  ['kind', EMPIRE_KINDS, 'empire'],
  ['authority', AUTHORITIES, 'empire'],
  ['origin', ORIGINS, 'empire'],
  ['ethic', ETHICS, 'empire'],
  ['civic', CIVICS, 'empire'],
  ['lifeform', SPECIES_KINDS, 'species'],
  ['trait', TRAITS, 'species'],
] as const) {
  for (const [id, choice] of Object.entries(choices) as [string, Choice][]) {
    definitions[`legacy.${category}.${id}`] = {
      name: choice.name,
      description: choice.description,
      category: category === 'trait' ? 'trait' : 'government',
      kinds: [kind],
      maxStacks: category === 'ethic' ? 2 : 1,
      effects: Object.entries(choice.effects ?? {}).map(([stat, amount]) => ({
        id: stat,
        stat: `legacy.${stat}`,
        op: 'add',
        value: amount,
      })),
    };
  }
}
const catalog: RuleCatalog = {
  version: 1,
  kinds: ['empire', 'species'],
  relations: [],
  properties: {},
  flags: {},
  definitions,
  stats: Object.fromEntries(
    Object.entries(MODIFIER_NAMES).map(([id, name]) => [
      `legacy.${id}`,
      { name, unit: id === 'habitability' ? 'Prozentpunkte' : 'Anteil', default: 0, better: 'higher' },
    ]),
  ),
};
export const empireRuleEngine = createRuleEngine(catalog);
function run(kind: string, selection: { definition: string; stacks?: number }[]): RuleResult {
  const owner = 'subject';
  const sources: RuleSource[] = selection.map((s) => ({ id: s.definition, owner, ...s }));
  return empireRuleEngine.evaluate(
    { target: owner, tick: 0, entities: { [owner]: { id: owner, kind } } },
    sources,
  );
}
export function evaluateGovernmentRules(government: Government, origin: string): RuleResult {
  return run('empire', [
    { definition: `legacy.kind.${government.kind}` },
    { definition: `legacy.authority.${government.authority}` },
    { definition: `legacy.origin.${origin}` },
    ...government.ethics.map((e) => ({ definition: `legacy.ethic.${e.id}`, stacks: e.strength })),
    ...government.civics.map((id) => ({ definition: `legacy.civic.${id}` })),
  ]);
}
export function evaluateSpeciesRules(species: Pick<SpeciesDesign, 'kind' | 'traits'>): RuleResult {
  return run('species', [
    { definition: `legacy.lifeform.${species.kind}` },
    ...species.traits.map((id) => ({ definition: `legacy.trait.${id}` })),
  ]);
}
export function legacyModifiers(result: RuleResult): Modifiers {
  return Object.fromEntries(
    (Object.keys(MODIFIER_NAMES) as Modifier[]).map((id) => [id, result.stats[`legacy.${id}`].value]),
  ) as Modifiers;
}
// Tick loops repeatedly request identical immutable designs. Keep only numeric deltas in a bounded cache;
// callers receive fresh objects and reforms/variants naturally use new keys.
const cache = new Map<string, Modifiers>();
function cached(key: string, calculate: () => RuleResult): Modifiers {
  let result = cache.get(key);
  if (!result) {
    result = legacyModifiers(calculate());
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
