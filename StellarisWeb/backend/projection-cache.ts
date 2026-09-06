/** Dependency tuples avoid parsing unchanged JSON and preserve presentation identities. */
export class ProjectionCache {
  private entries = new Map<string, { deps: readonly unknown[]; value: unknown }>();
  private rows = new WeakMap<object, { deps: readonly unknown[]; value: unknown }>();
  private tables = new WeakMap<object, () => unknown[]>();
  private cleanup: (() => void)[] = [];
  table<R extends { id: unknown }>(table: ReadTable<R>): R[] {
    let read = this.tables.get(table);
    if (!read) {
      const index = new Map([...table.iter()].map((r) => [r.id, r]));
      let rows: R[] | undefined;
      const insert = (_ctx: unknown, row: R) => {
        index.set(row.id, row);
        rows = undefined;
      };
      const update = (_ctx: unknown, old: R, row: R) => {
        if (old.id !== row.id) index.delete(old.id);
        insert(_ctx, row);
      };
      const remove = (_ctx: unknown, row: R) => {
        index.delete(row.id);
        rows = undefined;
      };
      table.onInsert(insert);
      table.onUpdate(update);
      table.onDelete(remove);
      this.cleanup.push(() => {
        table.removeOnInsert(insert);
        table.removeOnUpdate(update);
        table.removeOnDelete(remove);
      });
      read = () => (rows ??= [...index.values()]);
      this.tables.set(table, read);
    }
    return read() as R[];
  }
  dispose() {
    this.cleanup.forEach((f) => f());
    this.cleanup = [];
  }
  get<T>(key: string | object, deps: readonly unknown[], make: () => T): T {
    const previous = typeof key === 'string' ? this.entries.get(key) : this.rows.get(key);
    if (
      previous &&
      deps.length === previous.deps.length &&
      deps.every((d, i) => Object.is(d, previous.deps[i]))
    )
      return previous.value as T;
    let value = make();
    // Row projections may have been visited even though their collection is unchanged.
    if (
      previous &&
      Array.isArray(value) &&
      Array.isArray(previous.value) &&
      value.length === previous.value.length &&
      value.every((v, i) => v === (previous.value as unknown[])[i])
    )
      value = previous.value as T;
    const entry = { deps, value };
    if (typeof key === 'string') this.entries.set(key, entry);
    else this.rows.set(key, entry);
    return value;
  }
}

export interface ReadTable<R> {
  iter(): IterableIterator<R>;
  onInsert(cb: (ctx: unknown, row: R) => void): void;
  onUpdate(cb: (ctx: unknown, old: R, row: R) => void): void;
  onDelete(cb: (ctx: unknown, row: R) => void): void;
  removeOnInsert(cb: (ctx: unknown, row: R) => void): void;
  removeOnUpdate(cb: (ctx: unknown, old: R, row: R) => void): void;
  removeOnDelete(cb: (ctx: unknown, row: R) => void): void;
}

interface TableEvents {
  onInsert(cb: () => void): void;
  onUpdate(cb: () => void): void;
  onDelete(cb: () => void): void;
  removeOnInsert(cb: () => void): void;
  removeOnUpdate(cb: () => void): void;
  removeOnDelete(cb: () => void): void;
}

/** Coalesce SDK row callbacks AFTER the complete transaction has reached the cache. */
export function watchTables(tables: readonly TableEvents[], changed: () => void) {
  let queued = false,
    disposed = false;
  const invalidate = () => {
    if (queued || disposed) return;
    queued = true;
    queueMicrotask(() => {
      queued = false;
      if (!disposed) changed();
    });
  };
  for (const table of tables) {
    table.onInsert(invalidate);
    table.onUpdate(invalidate);
    table.onDelete(invalidate);
  }
  return () => {
    disposed = true;
    for (const table of tables) {
      table.removeOnInsert(invalidate);
      table.removeOnUpdate(invalidate);
      table.removeOnDelete(invalidate);
    }
  };
}
