import test from 'node:test';
import assert from 'node:assert/strict';
import { layoutResearch, nodesInViewport, type MapTechnology } from '../src/research-map-model';

test('500 technology layout is stable, bounded in columns, overlap-free and viewport culled', () => {
  const catalog: Record<string, MapTechnology> = {};
  for (let i = 0; i < 500; i++)
    catalog[`t${i}`] = { field: `f${i % 4}`, requires: i < 20 ? [] : [`t${i - 20}`] };
  const layout = layoutResearch(catalog, Object.keys(catalog));
  assert.deepEqual(layoutResearch(catalog, Object.keys(catalog)), layout);
  assert.equal(layout.nodes.length, 500);
  assert(layout.width <= 3200);
  for (let i = 0; i < layout.nodes.length; i++)
    for (let j = i + 1; j < layout.nodes.length; j++) {
      const a = layout.nodes[i],
        b = layout.nodes[j];
      assert(Math.abs(a.x - b.x) >= 220 || Math.abs(a.y - b.y) >= 80, 'cards do not overlap');
    }
  const first = nodesInViewport(layout.nodes, { x: 0, y: 0, width: 1000, height: 500 });
  assert(first.length > 0 && first.length < 40, 'only a small viewport window is mounted');
  const last = layout.nodes.at(-1)!;
  assert(
    nodesInViewport(layout.nodes, { x: last.x - 200, y: last.y - 200, width: 500, height: 500 }).some(
      (n) => n.id === last.id,
    ),
  );
});

test('hidden branches change neither positions, dimensions nor edges of revealed knowledge', () => {
  const catalog = { root: { field: 'f', requires: [] }, hidden: { field: 'f', requires: ['root'] } };
  assert.deepEqual(layoutResearch(catalog, ['root']), layoutResearch({ root: catalog.root }, ['root']));
  assert.equal(layoutResearch(catalog, ['root']).edges.length, 0);
  assert.equal(layoutResearch(catalog, ['root', 'hidden']).edges.length, 1);
});
