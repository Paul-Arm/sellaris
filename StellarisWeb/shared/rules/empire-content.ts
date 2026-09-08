import {
  AUTHORITIES,
  CIVICS,
  EMPIRE_KINDS,
  ETHICS,
  ORIGINS,
  SPECIES_KINDS,
  TRAITS,
  type Choice,
  type Modifier,
} from '../empireCatalog';
import type { RuleDefinition } from './types';

export const EMPIRE_STAT_IDS: Record<Modifier, string> = {
  energy: 'production.energy',
  minerals: 'production.minerals',
  data: 'production.research',
  unity: 'population.unity',
  growth: 'population.growth',
  research: 'research.speed',
  construction: 'construction.speed',
  speed: 'fleet.speed',
  damage: 'combat.damage',
  habitability: 'environment.habitability',
  upkeep: 'upkeep.energy',
};
/** Current empire content uses the same stat IDs and operations as every other rule source. */
export const EMPIRE_RULE_DEFINITIONS: Record<string, RuleDefinition> = {};
for (const [category, choices, kind] of [
  ['empire.kind', EMPIRE_KINDS, 'empire'],
  ['empire.authority', AUTHORITIES, 'empire'],
  ['empire.origin', ORIGINS, 'empire'],
  ['empire.ethic', ETHICS, 'empire'],
  ['empire.civic', CIVICS, 'empire'],
  ['species.lifeform', SPECIES_KINDS, 'species'],
  ['species', TRAITS, 'species'],
] as const) {
  for (const [id, choice] of Object.entries(choices) as [string, Choice][]) {
    EMPIRE_RULE_DEFINITIONS[`${category}.${id}`] = {
      name: choice.name,
      description: choice.description,
      category: category === 'species' ? 'trait' : 'government',
      kinds: [kind],
      maxStacks: category === 'empire.ethic' ? 2 : 1,
      effects: Object.entries(choice.effects ?? {}).map(([modifier, amount]) => ({
        id: modifier,
        stat: EMPIRE_STAT_IDS[modifier as Modifier],
        op: modifier === 'habitability' ? 'add' : 'percent',
        value: amount,
      })),
    };
  }
}
