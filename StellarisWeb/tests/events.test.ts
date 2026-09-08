import test from 'node:test';
import assert from 'node:assert/strict';
import { EVENT_POOL } from '../shared/events/catalog';
import {
  advanceSituation,
  chooseEvent,
  createSituation,
  matches,
  selectEvent,
  validateEventPool,
} from '../shared/events/engine';
import type { DirectorState, EventContext, EventDefinition } from '../shared/events/types';
const context: EventContext = {
  day: 0,
  trigger: 'test',
  key: 'test:1',
  facts: { techs: ['automation'], day: 0, ownedSystems: 3 },
};
const definition: EventDefinition = {
  id: 'core-test',
  kind: 'project',
  title: 'Test',
  subtitle: '',
  summary: '',
  theme: 'signal',
  triggers: ['test'],
  chance: 1,
  weight: 1,
  repeat: 'once',
  cooldownDays: 30,
  progress: {
    target: 100,
    initial: 20,
    rate: 0.1,
    volatility: 2,
    rates: [{ when: { fact: 'day', op: 'gte', value: 10 }, add: 0.5 }],
  },
  stages: [
    {
      id: 'work',
      title: 'Work',
      blocks: [],
      threshold: 100,
      effects: [{ type: 'resources', amounts: { data: 20 } }],
    },
  ],
};
const director = (): DirectorState => ({ lastDay: 0, sequence: 0, flags: {}, history: {}, recent: [] });
test('event core: catalog, compound conditions, weighted deterministic selection and discovery limits', () => {
  validateEventPool(EVENT_POOL);
  assert(EVENT_POOL.length >= 24);
  assert(
    matches(
      {
        all: [
          { fact: 'techs', op: 'has', value: 'automation' },
          { not: { fact: 'ownedSystems', op: 'lte', value: 1 } },
        ],
      },
      context.facts,
    ),
  );
  assert(!matches({ fact: 'unknown', op: 'gte', value: 1 }, context.facts));
  const selected = selectEvent([definition], director(), context, 'seed', 0);
  assert.equal(selected, definition);
  assert.equal(selectEvent([definition], director(), context, 'seed', 0), selected);
  assert.equal(
    selectEvent(
      [definition],
      { ...director(), history: { 'core-test:empire': { lastDay: 0, count: 1 } } },
      context,
      'seed',
      0,
    ),
    null,
  );
  assert.equal(selectEvent([definition], director(), context, 'seed', 8), null);
  assert.equal(
    selectEvent([{ ...definition, priority: 'critical' }], director(), context, 'seed', 8)?.id,
    definition.id,
  );
  assert.equal(selectEvent([definition], { ...director(), recent: [context.key] }, context, 'seed', 0), null);
  assert.throws(() =>
    validateEventPool([
      {
        ...definition,
        stages: [
          {
            id: 'bad',
            title: '',
            blocks: [],
            choices: [{ id: 'a', title: '', description: '', next: 'missing' }],
          },
        ],
      },
    ]),
  );
});
test('event core: fluctuating progress is partition-independent and completion effects occur once', () => {
  const a = createSituation(definition, 0, 'persistent-seed', 'species'),
    b = structuredClone(a);
  a.status = b.status = 'active';
  advanceSituation(a, definition, { ...context, day: 60 });
  let negative = false;
  for (let day = 1; day <= 60; day++) {
    advanceSituation(b, definition, { ...context, day });
    negative ||= b.lastRate < 0;
  }
  assert(negative, 'setbacks occur');
  assert.equal(a.progress, b.progress);
  assert.equal(a.stage, b.stage);
  const completed = { ...definition, progress: { target: 100, rate: 25 } };
  const c = createSituation(completed, 0, 's', 'species');
  c.status = 'active';
  assert.equal(advanceSituation(c, completed, { ...context, day: 10 }).length, 1);
  assert.equal(c.status, 'completed');
  assert.equal(advanceSituation(c, completed, { ...context, day: 20 }).length, 0);
  const paused = createSituation(definition, 0, 's', 'species');
  paused.status = 'paused';
  const before = structuredClone(paused);
  advanceSituation(paused, definition, { ...context, day: 200 });
  assert.deepEqual(paused, before);
});
test('event core: staged decisions, gated branches and safe deadlines are exactly once', () => {
  const d: EventDefinition = {
    ...definition,
    kind: 'event',
    progress: undefined,
    stages: [
      {
        id: 'choice',
        title: 'Choice',
        blocks: [],
        timeoutDays: 10,
        fallback: 'wait',
        choices: [
          {
            id: 'locked',
            title: 'Locked',
            description: '',
            when: { fact: 'techs', op: 'has', value: 'unknown' },
            finish: 'completed',
          },
          {
            id: 'wait',
            title: 'Wait',
            description: '',
            effects: [{ type: 'flag', key: 'accepted', value: true }],
            finish: 'completed',
          },
        ],
      },
    ],
  };
  validateEventPool([d]);
  const s = createSituation(d, 0, 's', 'species');
  assert.throws(() => chooseEvent(s, d, 'locked', context));
  assert.equal(s.status, 'decision');
  assert.equal(advanceSituation(s, d, { ...context, day: 9 }).length, 0);
  assert.equal(advanceSituation(s, d, { ...context, day: 10 })[0].type, 'flag');
  assert.equal(s.status, 'completed');
  assert.equal(advanceSituation(s, d, { ...context, day: 11 }).length, 0);
  assert.throws(() => chooseEvent(s, d, 'wait', context));
});
