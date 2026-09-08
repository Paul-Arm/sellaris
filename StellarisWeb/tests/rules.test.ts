import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CORE_RULE_CATALOG, coreRules, PSIONIC_CONTACT_REQUIREMENT } from '../shared/rules/catalog';
import { createRuleEngine } from '../shared/rules/engine';
import { parseRuleCatalog } from '../shared/rules/validation';
import type { Condition, Effect, RuleContext, RuleEntity, RuleSource } from '../shared/rules/types';
import { evaluateGovernmentRules, evaluateSpeciesRules } from '../shared/empireRules';
import { governmentModifiers, speciesModifiers, governmentFor, newSpecies } from '../shared/empires';
import {
  AUTHORITIES,
  CIVICS,
  EMPIRE_KINDS,
  ETHICS,
  ORIGINS,
  SPECIES_KINDS,
  TRAITS,
  addEffects,
  emptyModifiers,
  type Choice,
  type EmpireKind,
  type SpeciesKind,
} from '../shared/empireCatalog';

const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v));
const near = (a: number, b: number) => assert.ok(Math.abs(a - b) < 1e-10, `${a} != ${b}`);
function context(entity: Partial<RuleEntity> = {}): RuleContext {
  return {
    target: 'test',
    tick: 10,
    entities: {
      test: {
        id: 'test',
        kind: 'species',
        properties: { 'species.kind': 'biological' },
        base: {
          'production.research': 100,
          'production.energy': 30,
          'upkeep.energy': 10,
          'upkeep.consumer_goods': 2,
        },
        ...entity,
      },
    },
  };
}
const source = (definition: string, extra: Partial<RuleSource> = {}): RuleSource => ({
  id: definition,
  definition,
  owner: 'test',
  ...extra,
});
function effectsEngine(effects: Effect[]) {
  const catalog = clone(CORE_RULE_CATALOG);
  catalog.definitions['test.modifier'] = {
    name: 'Test',
    description: 'Rechenprüfung',
    category: 'status',
    kinds: ['species'],
    maxStacks: 3,
    effects,
  };
  return createRuleEngine(catalog);
}

test('user examples use years, production percentages, actual upkeep and a queryable capability', () => {
  const ctx = context();
  const rules = ['species.long_lived', 'species.intelligent', 'species.wasteful', 'species.psionic'];
  assert.equal(coreRules.validateTraits(ctx, rules, { budget: 4, maxTraits: 5 }).valid, true);
  const result = coreRules.evaluate(
    ctx,
    rules.map((id) => source(id)),
  );
  assert.equal(result.stats['life.expectancy'].value, 120);
  near(result.stats['production.research'].value, 110);
  assert.equal(result.stats['production.energy'].value, 30);
  assert.equal(result.stats['upkeep.energy'].value, 11);
  assert.equal(result.stats['upkeep.consumer_goods'].value, 2.2);
  assert.equal(result.stats['economy.net_energy'].value, 19);
  assert.deepEqual(result.flags, ['capability.psionic']);
  assert.equal(coreRules.check({ flag: 'capability.psionic' }, ctx, result).met, true);
  assert.equal(
    coreRules.check({ compare: { stat: 'life.expectancy' }, op: 'gte', value: 120 }, ctx, result).met,
    true,
  );
  assert.equal(result.stats['life.expectancy'].contributions[0].definition, 'species.long_lived');
});

test('flat, additive percentages, independent factors, override priority and final limits have defined phases', () => {
  const engine = effectsEngine([
    { id: 'flat', stat: 'production.research', op: 'add', value: 20 },
    { id: 'bonus', stat: 'production.research', op: 'percent', value: 0.2 },
    { id: 'debuff', stat: 'production.research', op: 'percent', value: -0.1 },
    { id: 'factor', stat: 'production.research', op: 'multiply', value: 1.5 },
    { id: 'cap', stat: 'production.research', op: 'cap', value: 190 },
  ]);
  const ctx = context(),
    src = source('test.modifier');
  const research = engine.evaluate(ctx, [src]).stats['production.research'];
  near(research.calculated, (100 + 20) * 1.1 * 1.5);
  assert.equal(research.value, 190);
  const overriding = effectsEngine([
    { id: 'weak', stat: 'life.expectancy', op: 'override', value: 50, priority: 1 },
    { id: 'strong', stat: 'life.expectancy', op: 'override', value: 200, priority: 5 },
    { id: 'limit', stat: 'life.expectancy', op: 'cap', value: 150 },
  ]).evaluate(ctx, [src]);
  assert.equal(overriding.stats['life.expectancy'].value, 150);
  assert.equal(overriding.stats['life.expectancy'].override, 200);
  assert.equal(overriding.contributions.find((c) => c.effect === 'weak')?.applied, false);
});

test('stack counts, strongest groups and unique effects are deterministic under source reordering', () => {
  const engine = effectsEngine([
    {
      id: 'flat',
      stat: 'production.research',
      op: 'add',
      value: 10,
      stacking: { group: 'flat', policy: 'highest' },
    },
    {
      id: 'factor',
      stat: 'production.research',
      op: 'multiply',
      value: 1.1,
      stacking: { group: 'factor', policy: 'unique' },
    },
    {
      id: 'discount',
      stat: 'upkeep.energy',
      op: 'percent',
      value: -0.1,
      stacking: { group: 'discount', policy: 'lowest' },
    },
  ]);
  const sources = [
    source('test.modifier', { id: 'a', stacks: 1 }),
    source('test.modifier', { id: 'b', stacks: 3 }),
  ];
  const forward = engine.evaluate(context(), sources),
    backward = engine.evaluate(context(), [...sources].reverse());
  assert.deepEqual(forward, backward);
  near(forward.stats['production.research'].value, 130 * 1.1);
  near(forward.stats['upkeep.energy'].value, 7);
  assert.equal(forward.contributions.filter((c) => !c.applied).length, 3);
  assert.throws(() => engine.evaluate(context(), [sources[0], sources[0]]), /Doppelte Quelleninstanz/);
  assert.throws(() => engine.evaluate(context(), [source('test.modifier', { stacks: 4 })]), /Stapelgrenze/);
});

test('temporary grants and suppression obey half-open game-time windows and deterministic flag priorities', () => {
  const ctx = context();
  const grants = [
    source('species.psionic'),
    source('status.psionic_suppression', { startsAt: 10, expiresAt: 20 }),
  ];
  assert.deepEqual(coreRules.evaluate({ ...ctx, tick: 9 }, grants).flags, ['capability.psionic']);
  assert.deepEqual(coreRules.evaluate({ ...ctx, tick: 10 }, grants).flags, []);
  const expired = coreRules.evaluate({ ...ctx, tick: 20 }, grants);
  assert.deepEqual(expired.flags, ['capability.psionic']);
  assert.equal(
    expired.contributions.find((c) => c.source === 'status.psionic_suppression')?.reason,
    'Abgelaufen',
  );
  assert.deepEqual(coreRules.evaluate(ctx, []).flags, []);
  const tied = effectsEngine([
    { id: 'grant', flag: 'capability.psionic', grant: true },
    { id: 'block', flag: 'capability.psionic', grant: false },
  ]);
  assert.deepEqual(tied.evaluate(ctx, [source('test.modifier')]).flags, []);
});

test('prerequisites support Boolean expressions, full-selection traits, exclusions, budgets and typed properties', () => {
  const organic = context(),
    machine = context({ properties: { 'species.kind': 'machine' } });
  assert.equal(coreRules.validateTraits(machine, ['species.long_lived']).valid, false);
  assert.equal(coreRules.validateTraits(organic, ['species.long_lived', 'species.short_lived']).valid, false);
  assert.equal(
    coreRules.validateTraits(organic, ['species.intelligent', 'species.psionic'], { budget: 2 }).valid,
    false,
  );
  assert.throws(() => coreRules.validateTraits(organic, ['species.psionic', 'species.psionic']), /Doppelte/);
  assert.equal(coreRules.validateTraits(context({ kind: 'planet' }), ['species.psionic']).valid, false);
  const catalog = clone(CORE_RULE_CATALOG);
  catalog.definitions['species.intelligent'].requires = { trait: 'species.psionic' };
  const engine = createRuleEngine(catalog);
  assert.equal(engine.validateTraits(organic, ['species.intelligent', 'species.psionic']).valid, true);
  assert.equal(engine.validateTraits(organic, ['species.intelligent']).valid, false);
});

test('missing or ambiguous scope fails closed, including nested negation and event gates', () => {
  const ctx = context();
  const result = coreRules.evaluate(ctx, [source('species.psionic')]);
  const missing = coreRules.check(PSIONIC_CONTACT_REQUIREMENT, ctx, result);
  assert.equal(missing.met, false);
  assert.equal(missing.missing, true);
  ctx.entities.test.relations = { owner: ['empire'] };
  ctx.entities.empire = { id: 'empire', kind: 'empire', properties: { 'empire.at_war': false } };
  assert.equal(coreRules.check(PSIONIC_CONTACT_REQUIREMENT, ctx, result).met, true);
  ctx.entities.empire.properties!['empire.at_war'] = true;
  assert.equal(coreRules.check(PSIONIC_CONTACT_REQUIREMENT, ctx, result).met, false);
  ctx.entities.test.relations.owner.push('other');
  ctx.entities.other = { id: 'other', kind: 'empire' };
  assert.equal(coreRules.check(PSIONIC_CONTACT_REQUIREMENT, ctx, result).missing, true);
});

test('governor and sector effects reach only same-owner planets in the explicitly assigned sector', () => {
  const entities: Record<string, RuleEntity> = {
    empire: { id: 'empire', kind: 'empire' },
    rival: { id: 'rival', kind: 'empire' },
    sector: { id: 'sector', kind: 'sector', relations: { owner: ['empire'] } },
    other: { id: 'other', kind: 'sector', relations: { owner: ['empire'] } },
    governor: {
      id: 'governor',
      kind: 'leader',
      properties: { 'leader.role': 'governor' },
      relations: { sector: ['sector'], owner: ['empire'] },
    },
    planet: {
      id: 'planet',
      kind: 'planet',
      base: { 'production.research': 100 },
      relations: { sector: ['sector'], owner: ['empire'] },
    },
  };
  const ctx = { target: 'planet', tick: 1, entities };
  const sources = [
    source('leader.sector_architect', { owner: 'governor' }),
    source('sector.research_grant', { owner: 'sector' }),
  ];
  const result = coreRules.evaluate(ctx, sources);
  near(result.stats['construction.speed'].value, 1.1);
  near(result.stats['production.research'].value, 115);
  assert.equal('life.expectancy' in result.stats, false);
  assert.equal(coreRules.evaluate(ctx, []).stats['construction.speed'].value, 1);
  entities.planet.relations!.sector = ['other'];
  assert.equal(coreRules.evaluate(ctx, sources).stats['construction.speed'].value, 1);
  entities.planet.relations!.sector = ['sector'];
  entities.planet.relations!.owner = ['rival'];
  assert.equal(coreRules.evaluate(ctx, sources).stats['production.research'].value, 100);
});

test('planet and leader mechanics keep their own properties, trait eligibility and scaling', () => {
  const planet = context({
    kind: 'planet',
    properties: { 'planet.habitable': true, 'planet.population': 3 },
  });
  assert.equal(coreRules.validateTraits(planet, ['planet.fertile', 'planet.mineral_rich']).valid, true);
  const result = coreRules.evaluate(
    planet,
    ['planet.fertile', 'planet.mineral_rich'].map((id) => source(id)),
  );
  near(result.stats['population.growth'].value, 1.2);
  assert.equal(result.stats['production.minerals'].value, 4);
  planet.entities.test.properties!['planet.population'] = 0;
  assert.equal(coreRules.evaluate(planet, [source('planet.fertile')]).stats['population.growth'].value, 1);
  const leader = context({ kind: 'leader', properties: { 'leader.level': 3, 'leader.role': 'scientist' } });
  assert.equal(coreRules.validateTraits(leader, ['leader.scholar']).valid, true);
  near(coreRules.evaluate(leader, [source('leader.scholar')]).stats['research.speed'].value, 1.15);
  leader.entities.test.properties!['leader.level'] = 20;
  assert.equal(coreRules.evaluate(leader, [source('leader.scholar')]).stats['research.speed'].value, 1.25);
});

test('relation quantifiers use actual entities and do not accept an empty every group', () => {
  const ctx = context();
  ctx.entities.test.relations = { leaders: [] };
  const query: Condition = {
    related: 'leaders',
    quantifier: 'every',
    condition: { flag: 'capability.psionic' },
  };
  assert.equal(coreRules.check(query, ctx).met, false);
  ctx.entities.test.relations.leaders = ['leader'];
  ctx.entities.leader = { id: 'leader', kind: 'leader', flags: ['capability.psionic'] };
  assert.equal(coreRules.check(query, ctx).met, true);
  assert.equal(coreRules.check({ not: query }, ctx).met, false);
});

test('catalog and instances reject malformed identifiers, non-JSON code, bad types, cycles and feedback loops', () => {
  assert.throws(() => parseRuleCatalog({ ...CORE_RULE_CATALOG, version: 2 }), /version/);
  assert.throws(() => parseRuleCatalog({ ...CORE_RULE_CATALOG, script: () => 100 }), /JSON/);
  assert.throws(() => effectsEngine([{ id: 'bad', stat: 'missing', op: 'add', value: 10 }]), /Unbekannte ID/);
  assert.throws(
    () =>
      effectsEngine([
        { id: 'bad', stat: 'production.energy', op: 'percent', value: { stat: 'production.energy' } },
      ]),
    /Endwerte/,
  );
  assert.throws(
    () => effectsEngine([{ id: 'bad', stat: 'production.energy', op: 'add', value: NaN }]),
    /Zahl/,
  );
  const cycle = clone(CORE_RULE_CATALOG);
  cycle.stats['production.energy'].derived = { stat: 'economy.net_energy' };
  assert.throws(() => createRuleEngine(cycle), /Zyklische/);
  const ctx = context();
  assert.throws(() => coreRules.evaluate({ ...ctx, tick: Infinity }, []), /Spielzeitpunkt/);
  assert.throws(
    () => coreRules.evaluate(context({ properties: { 'species.kind': 'alien' } }), []),
    /ausprägung/,
  );
  assert.throws(() => coreRules.evaluate(ctx, [source('constructor')]), /Unbekannte ID/);
  assert.throws(() => coreRules.evaluate(ctx, [source('species.psionic', { expiresAt: 0 })]), /Ablaufdatum/);
  assert.throws(
    () => coreRules.evaluate(context({ kind: 'planet', base: { 'life.expectancy': 900 } }), []),
    /Fachmodell/,
  );
  const ambiguous = {
    property: 'planet.population',
    op: 'gt',
    value: 0,
    not: { kind: 'planet' },
  } as Condition;
  assert.throws(() => coreRules.check(ambiguous, ctx), /Mehrdeutige/);
});

test('invalid arithmetic and conflicting bounds fail rather than creating corrupt stats', () => {
  const divide = effectsEngine([
    { id: 'divide', stat: 'production.energy', op: 'add', value: { op: 'divide', left: 1, right: 0 } },
  ]);
  assert.throws(() => divide.evaluate(context(), [source('test.modifier')]), /Division/);
  const bounds = effectsEngine([
    { id: 'floor', stat: 'production.energy', op: 'floor', value: 10 },
    { id: 'cap', stat: 'production.energy', op: 'cap', value: 5 },
  ]);
  assert.throws(() => bounds.evaluate(context(), [source('test.modifier')]), /Widersprüchliche/);
  const negative = effectsEngine([{ id: 'debuff', stat: 'production.energy', op: 'percent', value: -2 }]);
  assert.equal(negative.evaluate(context(), [source('test.modifier')]).stats['production.energy'].value, 0);
});

test('serialization and evaluation are detached: no source, catalog, template or cross-match mutation', () => {
  const catalog = clone(CORE_RULE_CATALOG),
    engine = createRuleEngine(catalog);
  catalog.definitions['species.long_lived'].effects.length = 0;
  const ctx = context(),
    sources = [source('species.long_lived')],
    original = JSON.stringify({ ctx, sources });
  const first = engine.evaluate(ctx, sources);
  first.stats['life.expectancy'].value = 999;
  first.contributions[0].applied = false;
  const second = engine.evaluate(clone(ctx), clone(sources));
  assert.equal(second.stats['life.expectancy'].value, 120);
  assert.equal(JSON.stringify({ ctx, sources }), original);
  assert.deepEqual(clone(second), second);
  assert.ok(Object.isFrozen(engine.catalog.definitions['species.long_lived'].effects));
});

test('live empires use canonical rules, including upkeep, and expose provenance', () => {
  for (const kind of Object.keys(SPECIES_KINDS) as SpeciesKind[]) {
    for (const [id, trait] of Object.entries(TRAITS)) {
      if (trait.speciesKinds && !trait.speciesKinds.includes(kind)) continue;
      const species = { ...newSpecies('test', kind), traits: [id] };
      const old = addEffects(addEffects(emptyModifiers(), SPECIES_KINDS[kind].effects), trait.effects);
      const current = speciesModifiers(species);
      for (const key of Object.keys(old) as (keyof typeof old)[]) near(current[key], old[key]);
      assert.equal(
        evaluateSpeciesRules(species).contributions.some((c) => c.definition === `species.${id}`),
        true,
      );
      current.energy = 999;
      assert.notEqual(speciesModifiers(species).energy, 999);
    }
  }
  for (const kind of Object.keys(EMPIRE_KINDS) as EmpireKind[]) {
    const government = governmentFor(kind);
    for (const [originId, origin] of Object.entries(ORIGINS)) {
      const old = emptyModifiers();
      for (const choice of [EMPIRE_KINDS[kind], AUTHORITIES[government.authority], origin] as Choice[])
        addEffects(old, choice.effects);
      for (const ethic of government.ethics) addEffects(old, ETHICS[ethic.id].effects, ethic.strength);
      for (const civic of government.civics) addEffects(old, CIVICS[civic].effects);
      const current = governmentModifiers(government, originId);
      for (const key of Object.keys(old) as (keyof typeof old)[]) near(current[key], old[key]);
      assert.ok(evaluateGovernmentRules(government, originId).stats['production.research']);
    }
  }
});
