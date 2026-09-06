import { subscribe, DETAIL_QUERIES, type Client } from './client';

type Handle = Awaited<ReturnType<typeof subscribe>>;
export function unsubscribe(handle: Handle) {
  return new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Detail unsubscribe timed out')), 15000);
    try {
      handle.unsubscribeThen(() => {
        clearTimeout(timer);
        resolve();
      });
    } catch (error) {
      clearTimeout(timer);
      reject(error);
    }
  });
}

/** One explicit system/battle UI owns this scope. Close it on navigation away.
 * Serialize transitions so a late open cannot leave details running after close.
 */
export class BattleDetailSubscription {
  private handle?: Handle;
  private tail: Promise<void> = Promise.resolve();
  private disposed = false;
  constructor(private readonly client: Client) {}

  focus(fleetId: number, battleId: number): Promise<void> {
    const work = this.tail
      .catch(() => {})
      .then(async () => {
        if (this.disposed) return;
        if (!battleId && !fleetId) {
          const old = this.handle;
          this.handle = undefined;
          if (old) await unsubscribe(old);
          if (!this.disposed) await this.client.conn.reducers.setFocus({ fleetId: 0, battleId: 0 });
          return;
        }
        await this.client.conn.reducers.setFocus({ fleetId, battleId });
        if (!this.handle && !this.disposed) {
          const handle = await subscribe(this.client.conn, DETAIL_QUERIES);
          if (this.disposed) handle.unsubscribe();
          else this.handle = handle;
        }
      });
    this.tail = work;
    return work;
  }

  dispose() {
    this.disposed = true;
    if (this.client.conn.isActive) this.handle?.unsubscribe();
    this.handle = undefined;
  }
}
