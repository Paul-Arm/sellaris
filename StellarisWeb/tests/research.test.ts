import test from 'node:test';
import assert from 'node:assert/strict';
import { addPlayer, createGame } from '../shared/game';
import {
  TECHS,
  advanceResearch,
  applyResearch,
  baseCompute,
  dataCost,
  newResearch,
  researchAllocation,
  researchPath,
  visibleResearch,
  type TechId,
} from '../shared/research';
import { colonyEconomy } from '../shared/planetaryEconomy';
const player = (data = 10000) => ({
  techs: [] as TechId[],
  research: newResearch(),
  resources: { energy: 0, minerals: 0, data },
});
test('the complete technology graph has valid acyclic prerequisites and a unique topological route', () => {
  for (const id of Object.keys(TECHS) as TechId[]) {
    const route = researchPath(id);
    assert.equal(new Set(route).size, route.length);
    assert.equal(route.at(-1), id);
    for (const node of route)
      for (const parent of TECHS[node].requires) assert(route.indexOf(parent) < route.indexOf(node));
    assert(TECHS[id].data > 0 && TECHS[id].work > 0);
  }
  assert.deepEqual(researchPath('quantum', ['computing', 'distributed', 'propulsion']), ['quantum']);
});
test('undiscovered technologies cannot be planned or charged; discovery advances one frontier', () => {
  const p = player();
  assert.deepEqual(visibleResearch(p.techs), ['computing', 'archives', 'extraction', 'propulsion']);
  const before = structuredClone(p);
  assert.throws(() => applyResearch(p, { type: 'research', tech: 'quantum' }), /noch nicht entdeckt/);
  assert.deepEqual(p, before);
  p.techs.push('computing');
  assert(visibleResearch(p.techs).includes('distributed'));
  assert(visibleResearch(p.techs).includes('parallelism'));
  assert(!visibleResearch(p.techs).includes('quantum'));
  p.techs.push('distributed');
  assert(!visibleResearch(p.techs).includes('quantum'), 'all cross-field prerequisites must be known');
  p.techs.push('propulsion');
  assert(visibleResearch(p.techs).includes('quantum'));
  applyResearch(p, { type: 'research', tech: 'quantum' });
  assert.equal(p.resources.data, 9650);
  assert.throws(() => applyResearch(p, { type: 'research', tech: 'quantum' }), /Bereits/);
  assert.equal(p.resources.data, 9650);
});

test('Compute is conserved across weighted projects and data synthesis', () => {
  const p = player();
  applyResearch(p, { type: 'research', tech: 'computing' });
  applyResearch(p, { type: 'research', tech: 'propulsion' });
  applyResearch(p, { type: 'research_weight', tech: 'propulsion', weight: 3 });
  const a = researchAllocation(p.research, p.techs, 8);
  assert.equal(a.rates.get('computing'), 1.5);
  assert.equal(a.rates.get('propulsion'), 4.5);
  assert.equal(a.synthesis, 2);
  assert.equal(a.data, 0.5);
  const balance = p.resources.data;
  advanceResearch(p, 8, 2);
  assert.equal(p.research.projects[0].done, 3);
  assert.equal(p.research.projects[1].done, 9);
  assert.equal(p.resources.data, balance + 1);
});
test('parked work retains progress and paid data; 100% synthesis suspends every project', () => {
  const p = player();
  applyResearch(p, { type: 'research', tech: 'computing' });
  advanceResearch(p, 4, 2);
  const paid = p.research.projects[0].paid,
    done = p.research.projects[0].done;
  applyResearch(p, { type: 'research_weight', tech: 'computing', weight: 0 });
  advanceResearch(p, 4, 2);
  assert.equal(p.research.projects[0].done, done);
  applyResearch(p, { type: 'research_weight', tech: 'computing', weight: 1 });
  assert.equal(p.research.projects[0].paid, paid);
  applyResearch(p, { type: 'research_synthesis', percent: 100 });
  const before = p.resources.data;
  advanceResearch(p, 4, 2);
  assert.equal(p.research.projects[0].done, done);
  assert.equal(p.resources.data, before + 2);
});
test('idle Compute can bootstrap research from zero data without negative balances', () => {
  const p = player(0);
  p.research.synthesis = 0;
  applyResearch(p, { type: 'research', tech: 'computing' });
  for (let i = 0; i < 51; i++) advanceResearch(p, 4, 1);
  assert.equal(p.research.projects[0].paid, 50);
  assert.equal(p.research.projects[0].done, 4);
  assert.equal(p.resources.data, 0);
});
test('completion unlocks dependents once and new technology effects affect costs and capacity', () => {
  const p = player();
  p.research.synthesis = 0;
  applyResearch(p, { type: 'research', tech: 'archives' });
  assert.deepEqual(advanceResearch(p, 100, 1), ['archives']);
  assert(visibleResearch(p.techs).includes('simulation'));
  applyResearch(p, { type: 'research', tech: 'simulation' });
  advanceResearch(p, 4, 1);
  assert.equal(p.research.projects[0].paid, 85);
  assert.equal(dataCost('quantum', ['archives', 'compression']), 245);
  assert.equal(baseCompute(['computing', 'distributed', 'quantum']), 18);
});
test('invalid priorities and allocations reject without corrupting the research program', () => {
  const p = player();
  applyResearch(p, { type: 'research', tech: 'computing' });
  const before = structuredClone(p);
  for (const value of [-1, 101, NaN, 0.5])
    assert.throws(() => applyResearch(p, { type: 'research_synthesis', percent: value }));
  for (const weight of [-1, 6, NaN, 1.5])
    assert.throws(() => applyResearch(p, { type: 'research_weight', tech: 'computing', weight }));
  assert.deepEqual(p, before);
});
test('data centers need employed jobs and stop providing Compute when disabled', () => {
  const g = createGame('C0FFEE'),
    p = addPlayer(g, 'a', 'A'),
    s = g.systems.find((s) => s.id === p.home)!;
  const c = s.colony!;
  c.sectors[0].districts.push({ id: c.nextDistrictId++, building: 'datacenter', enabled: true, level: 1 });
  assert(colonyEconomy(c, s.planet, p).compute > 0);
  c.sectors[0].districts.at(-1)!.enabled = false;
  assert.equal(colonyEconomy(c, s.planet, p).compute, 0);
});
