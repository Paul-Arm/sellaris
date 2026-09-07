import type { Condition, RuleCatalog, RuleDefinition, StatDefinition } from './types';
import { createRuleEngine } from './engine';

const stat = (
  name: string,
  unit: string,
  base = 0,
  better: StatDefinition['better'] = 'higher',
): StatDefinition => ({ name, unit, default: base, min: 0, better });
const organic: Condition = {
  any: [
    { property: 'species.kind', op: 'eq', value: 'biological' },
    { property: 'species.kind', op: 'eq', value: 'lithoid' },
  ],
};
const subject = (...kinds: string[]): Condition => ({ any: kinds.map((kind) => ({ kind })) });
const sameSector: Condition = {
  all: [
    { kind: 'planet' },
    { same: { left: { root: 'target', path: ['sector'] }, right: { root: 'source', path: ['sector'] } } },
    { same: { left: { root: 'target', path: ['owner'] }, right: { root: 'source', path: ['owner'] } } },
  ],
};
const definitions: Record<string, RuleDefinition> = {
  'species.long_lived': {
    name: 'Langlebig',
    description: '+40 Jahre durchschnittliche Lebensdauer.',
    category: 'trait',
    kinds: ['species'],
    cost: 1,
    requires: organic,
    excludes: ['species.short_lived'],
    effects: [
      { id: 'lifespan', stat: 'life.expectancy', op: 'add', value: 40, when: subject('species', 'leader') },
    ],
  },
  'species.short_lived': {
    name: 'Kurzlebig',
    description: '−20 Jahre durchschnittliche Lebensdauer.',
    category: 'trait',
    kinds: ['species'],
    cost: -1,
    requires: organic,
    excludes: ['species.long_lived'],
    effects: [
      { id: 'lifespan', stat: 'life.expectancy', op: 'add', value: -20, when: subject('species', 'leader') },
    ],
  },
  'species.intelligent': {
    name: 'Intelligent',
    description: '+10 % produzierte Daten.',
    category: 'trait',
    kinds: ['species'],
    cost: 2,
    effects: [
      {
        id: 'research',
        stat: 'production.research',
        op: 'percent',
        value: 0.1,
        when: subject('species', 'population'),
      },
    ],
  },
  'species.wasteful': {
    name: 'Verschwenderisch',
    description: '+10 % Energie- und Konsumgüterunterhalt.',
    category: 'trait',
    kinds: ['species'],
    cost: -1,
    effects: ['energy', 'consumer_goods'].map((resource) => ({
      id: resource,
      stat: `upkeep.${resource}`,
      op: 'percent',
      value: 0.1,
      when: subject('species', 'population'),
    })),
  },
  'species.psionic': {
    name: 'Psionisch',
    description: 'Psionische Begabung ermöglicht besondere Interaktionen und Ereignisse.',
    category: 'trait',
    kinds: ['species'],
    cost: 2,
    requires: organic,
    effects: [
      {
        id: 'psionic',
        flag: 'capability.psionic',
        grant: true,
        when: subject('species', 'population', 'leader'),
      },
    ],
  },
  'leader.scholar': {
    name: 'Gelehrter',
    description: '+5 % Forschungstempo pro Erfahrungsstufe, höchstens +25 %.',
    category: 'trait',
    kinds: ['leader'],
    cost: 1,
    requires: { property: 'leader.role', op: 'eq', value: 'scientist' },
    effects: [
      {
        id: 'research',
        stat: 'research.speed',
        op: 'percent',
        when: { kind: 'leader' },
        value: {
          op: 'min',
          values: [
            0.25,
            { op: 'product', values: [0.05, { property: 'leader.level', scope: { root: 'source' } }] },
          ],
        },
      },
    ],
  },
  'leader.sector_architect': {
    name: 'Sektorarchitekt',
    description: '+10 % Bautempo auf Planeten des eigenen verwalteten Sektors.',
    category: 'trait',
    kinds: ['leader'],
    cost: 1,
    requires: { property: 'leader.role', op: 'eq', value: 'governor' },
    effects: [
      {
        id: 'construction',
        stat: 'construction.speed',
        op: 'percent',
        value: 0.1,
        when: sameSector,
        stacking: { group: 'governor.architect', policy: 'highest' },
      },
    ],
  },
  'planet.fertile': {
    name: 'Fruchtbare Biosphäre',
    description: '+20 % Bevölkerungswachstum, wenn der Planet besiedelt ist.',
    category: 'trait',
    kinds: ['planet'],
    requires: { property: 'planet.habitable', op: 'eq', value: true },
    effects: [
      {
        id: 'growth',
        stat: 'population.growth',
        op: 'percent',
        value: 0.2,
        when: { all: [{ kind: 'planet' }, { property: 'planet.population', op: 'gt', value: 0 }] },
      },
    ],
  },
  'planet.mineral_rich': {
    name: 'Reiche Lagerstätten',
    description: '+4 Mineralienproduktion vor prozentualen Boni.',
    category: 'trait',
    kinds: ['planet'],
    effects: [{ id: 'minerals', stat: 'production.minerals', op: 'add', value: 4, when: { kind: 'planet' } }],
  },
  'sector.research_grant': {
    name: 'Forschungsförderung',
    description: '+15 % Forschungsproduktion innerhalb des eigenen Sektors.',
    category: 'policy',
    kinds: ['sector'],
    effects: [
      {
        id: 'research',
        stat: 'production.research',
        op: 'percent',
        value: 0.15,
        when: {
          all: [
            { kind: 'planet' },
            { same: { left: { root: 'target', path: ['sector'] }, right: { root: 'source' } } },
            {
              same: { left: { root: 'target', path: ['owner'] }, right: { root: 'source', path: ['owner'] } },
            },
          ],
        },
      },
    ],
  },
  'status.psionic_suppression': {
    name: 'Psionische Unterdrückung',
    description: 'Blockiert psionische Fähigkeiten während der Wirkungsdauer.',
    category: 'status',
    kinds: ['species', 'leader', 'population'],
    effects: [{ id: 'suppressed', flag: 'capability.psionic', grant: false, priority: 100 }],
  },
  'status.research_inspiration': {
    name: 'Wissenschaftliche Inspiration',
    description: 'Abschließender Faktor 1,2 auf die Forschungsproduktion.',
    category: 'event',
    kinds: ['empire', 'planet', 'population'],
    effects: [
      {
        id: 'research',
        stat: 'production.research',
        op: 'multiply',
        value: 1.2,
        stacking: { group: 'research.inspiration', policy: 'highest' },
      },
    ],
  },
};

/** Content examples for distinct domain models sharing only rule evaluation. */
export const CORE_RULE_CATALOG: RuleCatalog = {
  version: 1,
  kinds: [
    'empire',
    'species',
    'leader',
    'population',
    'planet',
    'sector',
    'fleet',
    'ship',
    'building',
    'technology',
  ],
  relations: ['owner', 'species', 'sector', 'governor', 'planet', 'populations', 'leaders', 'planets'],
  properties: {
    'species.kind': { name: 'Lebensform', type: 'string', values: ['biological', 'lithoid', 'machine'] },
    'leader.level': { name: 'Erfahrungsstufe', type: 'number' },
    'leader.role': { name: 'Aufgabe', type: 'string', values: ['scientist', 'governor', 'admiral'] },
    'planet.habitable': { name: 'Besiedelbar', type: 'boolean' },
    'planet.population': { name: 'Bevölkerung', type: 'number' },
    'planet.climate': { name: 'Klima', type: 'string' },
    'empire.at_war': { name: 'Im Krieg', type: 'boolean' },
  },
  flags: {
    'capability.psionic': { name: 'Psionisch', description: 'Kann psionische Interaktionen auslösen.' },
  },
  stats: {
    'production.energy': stat('Energieproduktion', 'Energie / Zyklus'),
    'production.minerals': stat('Mineralienproduktion', 'Mineralien / Zyklus'),
    'production.research': stat('Forschungsproduktion', 'Forschung / Zyklus'),
    'population.growth': stat('Bevölkerungswachstum', 'Faktor', 1),
    'research.speed': stat('Forschungstempo', 'Faktor', 1),
    'construction.speed': stat('Bautempo', 'Faktor', 1),
    'fleet.speed': stat('Reisetempo', 'Faktor', 1),
    'combat.damage': stat('Waffenschaden', 'Schaden', 1),
    'environment.habitability': { ...stat('Bewohnbarkeit', 'Anteil', 1), max: 1 },
    'life.expectancy': {
      ...stat('Durchschnittliche Lebensdauer', 'Jahre', 80),
      kinds: ['species', 'leader'],
    },
    'upkeep.energy': stat('Energieunterhalt', 'Energie / Zyklus', 0, 'lower'),
    'upkeep.consumer_goods': stat('Konsumgüterunterhalt', 'Konsumgüter / Zyklus', 0, 'lower'),
    'economy.net_energy': {
      name: 'Energiebilanz',
      unit: 'Energie / Zyklus',
      default: 0,
      better: 'higher',
      derived: {
        op: 'sum',
        values: [{ stat: 'production.energy' }, { op: 'product', values: [-1, { stat: 'upkeep.energy' }] }],
      },
    },
  },
  definitions,
};
export const coreRules = createRuleEngine(CORE_RULE_CATALOG);

/** Event/interaction code queries resolved capabilities; it never compares localized trait names. */
export const PSIONIC_CONTACT_REQUIREMENT: Condition = {
  all: [
    { flag: 'capability.psionic' },
    { not: { property: 'empire.at_war', scope: { root: 'target', path: ['owner'] }, op: 'eq', value: true } },
  ],
};
