import test from 'node:test';
import assert from 'node:assert/strict';
import { ProjectionCache, watchTables } from '../backend/projection-cache';

type Row = { id: number; value: string };
type Insert = (ctx: unknown, row: Row) => void;
type Update = (ctx: unknown, old: Row, row: Row) => void;
class Table {
  rows: Row[] = [
    { id: 1, value: 'A' },
    { id: 2, value: 'B' },
  ];
  inserts = new Set<Insert>();
  updates = new Set<Update>();
  deletes = new Set<Insert>();
  scans = 0;
  *iter() {
    this.scans++;
    yield* this.rows;
  }
  onInsert(fn: Insert) {
    this.inserts.add(fn);
  }
  onUpdate(fn: Update) {
    this.updates.add(fn);
  }
  onDelete(fn: Insert) {
    this.deletes.add(fn);
  }
  removeOnInsert(fn: Insert) {
    this.inserts.delete(fn);
  }
  removeOnUpdate(fn: Update) {
    this.updates.delete(fn);
  }
  removeOnDelete(fn: Insert) {
    this.deletes.delete(fn);
  }
  replace(row: Row) {
    const i = this.rows.findIndex((r) => r.id === row.id),
      old = this.rows[i];
    this.rows[i] = row;
    this.updates.forEach((fn) => fn(null, old, row));
  }
}
test('normalized tables scan once, preserve ordering and unchanged rows, and publish after the transaction', async () => {
  const cache = new ProjectionCache(),
    table = new Table();
  const original = cache.table(table);
  assert.equal(cache.table(table), original);
  let publications = 0;
  const dispose = watchTables([table], () => {
    publications++;
    assert.deepEqual(
      cache.table(table).map((r) => r.value),
      ['new A', 'new B'],
    );
  });
  table.replace({ id: 1, value: 'new A' });
  assert.equal(cache.table(table)[1], original[1]);
  table.replace({ id: 2, value: 'new B' });
  assert.equal(publications, 0);
  await Promise.resolve();
  assert.equal(publications, 1);
  assert.equal(table.scans, 1);
  assert.deepEqual(
    cache.table(table).map((r) => r.id),
    [1, 2],
  );
  dispose();
  cache.dispose();
  assert.equal(table.updates.size, 0);
  assert.equal(table.inserts.size, 0);
});
test('projection cache does not reparse unchanged data and stabilizes unchanged collections', () => {
  const cache = new ProjectionCache(),
    source = { id: 1 },
    metadata = { text: 'x' };
  let parsed = 0;
  const build = () =>
    cache.get(source, [metadata], () => {
      parsed++;
      return { id: 1, value: 'parsed' };
    });
  const first = build();
  assert.equal(build(), first);
  assert.equal(parsed, 1);
  const array = cache.get('rows', [1], () => [first]);
  assert.equal(
    cache.get('rows', [2], () => [build()]),
    array,
  );
});
