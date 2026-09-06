import { subscribe, type Client } from './client';
import { unsubscribe } from './detail-subscriptions';

/** One serialized scope per connection prevents stale cleanup from closing a newer system. */
export class SystemSubscription {
  private handle?: Awaited<ReturnType<typeof subscribe>>;
  private tail: Promise<void> = Promise.resolve();
  constructor(private readonly client: Client) {}
  focus(systemId: number): Promise<void> {
    const work = this.tail
      .catch(() => {})
      .then(async () => {
        if (!this.client.conn.isActive) return;
        if (this.handle) {
          await unsubscribe(this.handle);
          this.handle = undefined;
        }
        await this.client.conn.reducers.focusSystemObjects({ systemId });
        if (systemId)
          this.handle = await subscribe(this.client.conn, [
            `SELECT * FROM focused_system_objects WHERE system_id = ${systemId}`,
            `SELECT * FROM focused_object_systems WHERE id = ${systemId}`,
          ]);
      });
    this.tail = work;
    return work;
  }
}
const scopes = new WeakMap<Client, SystemSubscription>();
export function systemSubscription(client: Client) {
  let scope = scopes.get(client);
  if (!scope) scopes.set(client, (scope = new SystemSubscription(client)));
  return scope;
}
