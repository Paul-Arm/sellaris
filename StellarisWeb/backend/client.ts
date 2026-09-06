import { DbConnection } from './module_bindings';
import { setGlobalLogLevel } from 'spacetimedb';
import { OrderedReceiver, receiveStats, type ReceiveStats } from './transport';

setGlobalLogLevel('warn');
export const GALAXY_QUERIES = [
  'clock',
  'scenario',
  'star',
  'empire_summary',
  'my_empire',
  'galaxy_fleets',
  'visible_battle_summaries',
  'my_jobs',
  'my_colonies',
  'crisis',
  'my_decisions',
  'my_treaties',
  'my_trade',
].map((t) => `SELECT * FROM ${t}`);
export const LEGACY_DETAIL_QUERIES = [
  'SELECT * FROM fleet_ships',
  'SELECT * FROM battle_participants',
  'SELECT * FROM visible_battles',
];
export const BATTLE_QUERIES = ['focused_battle', 'battle_roster', 'battle_motion', 'battle_vitals'].map(
  (t) => `SELECT * FROM ${t}`,
);
export const DETAIL_QUERIES = ['SELECT * FROM fleet_ships', ...BATTLE_QUERIES];
export type Compression = 'none' | 'gzip';
export interface Traffic extends ReceiveStats {
  receivedBytes: number;
  sentBytes: number;
  frames: number;
  connectedAt: number;
}
export interface Client {
  conn: DbConnection;
  token: string;
  identity: string;
  traffic: Traffic;
}
type WSFactory = Parameters<ReturnType<typeof DbConnection.builder>['withWSFn']>[0];

/** SDK-supported transport adapter. Count wire bytes BEFORE decompression and
 * decoded bytes separately. Never log credentials or payloads.
 */
function meteredTransport(traffic: Traffic): WSFactory {
  return async (args) => {
    const httpUrl = new URL(args.url);
    httpUrl.protocol = httpUrl.protocol === 'wss:' ? 'https:' : 'http:';
    let shortToken: string | undefined;
    if (args.authToken) {
      const response = await fetch(new URL('/v1/identity/websocket-token', httpUrl), {
        method: 'POST',
        headers: { Authorization: `Bearer ${args.authToken}` },
      });
      if (!response.ok) throw new Error(`Token exchange failed: ${response.status}`);
      shortToken = (await response.json()).token;
    }
    const url = new URL(`/v1/database/${args.nameOrAddress}/subscribe`, args.url);
    if (shortToken) url.searchParams.set('token', shortToken);
    url.searchParams.set('compression', args.compression === 'gzip' ? 'Gzip' : 'None');
    if (args.confirmedReads !== undefined) url.searchParams.set('confirmed', String(args.confirmedReads));
    const ws = new WebSocket(url, args.wsProtocol);
    ws.binaryType = 'arraybuffer';
    let receiver: OrderedReceiver | undefined;
    return {
      get protocol() {
        return ws.protocol;
      },
      get readyState() {
        return ws.readyState;
      },
      send(msg) {
        traffic.sentBytes += msg.byteLength;
        ws.send(msg);
      },
      close() {
        receiver?.close();
        ws.close();
      },
      set onopen(fn: () => void) {
        ws.onopen = () => {
          traffic.connectedAt = performance.now();
          fn();
        };
      },
      set onclose(fn: (event: CloseEvent) => void) {
        ws.onclose = (event) => {
          receiver?.close();
          fn(event);
        };
      },
      set onerror(fn: (event: ErrorEvent) => void) {
        ws.onerror = (ev) => fn(ev as ErrorEvent);
      },
      set onmessage(fn: (message: { data: Uint8Array }) => void) {
        receiver = new OrderedReceiver(
          (data) => fn({ data }),
          () => {
            // Never skip an undecodable transaction: invalidate this connection.
            ws.close(4002, 'Invalid or overloaded receive stream');
          },
          traffic,
        );
        ws.onmessage = (event) => {
          const bytes = new Uint8Array(event.data as ArrayBuffer);
          traffic.receivedBytes += bytes.byteLength;
          traffic.frames++;
          void receiver!.push(bytes);
        };
      },
    };
  };
}

export function connect(
  database: string,
  options: { uri?: string; token?: string; compression?: Compression; onDisconnect?: () => void } = {},
): Promise<Client> {
  return new Promise((resolve, reject) => {
    const traffic = { ...receiveStats(), receivedBytes: 0, sentBytes: 0, frames: 0, connectedAt: 0 };
    const timeout = setTimeout(() => {
      conn.disconnect();
      reject(new Error('Connection timed out'));
    }, 20000);
    const conn = DbConnection.builder()
      .withUri(options.uri || 'ws://127.0.0.1:3100')
      .withDatabaseName(database)
      .withToken(options.token)
      .withCompression(options.compression ?? 'gzip')
      .withConfirmedReads(true)
      .withWSFn(meteredTransport(traffic))
      .onConnect((conn, identity, token) => {
        clearTimeout(timeout);
        resolve({ conn, token, identity: identity.toHexString(), traffic });
      })
      .onConnectError((_ctx, error) => {
        clearTimeout(timeout);
        reject(error);
      })
      .onDisconnect(() => options.onDisconnect?.())
      .build();
  });
}

export function subscribe(conn: DbConnection, queries = GALAXY_QUERIES) {
  return new Promise<ReturnType<ReturnType<DbConnection['subscriptionBuilder']>['subscribe']>>(
    (resolve, reject) => {
      const timer = setTimeout(() => {
        handle.unsubscribe();
        reject(new Error('Subscription timed out'));
      }, 20000);
      const handle = conn
        .subscriptionBuilder()
        .onApplied(() => {
          clearTimeout(timer);
          resolve(handle);
        })
        .onError((ctx) => {
          clearTimeout(timer);
          reject(ctx.event);
        })
        .subscribe(queries);
    },
  );
}

export async function join(
  client: Client,
  empireId: number,
  focus?: { fleetId: number; battleId: number },
  detailQueries = DETAIL_QUERIES,
) {
  await client.conn.reducers.joinEmpire({ empireId });
  if (focus) await client.conn.reducers.setFocus(focus);
  // All initial related rows arrive in one atomic snapshot; expose the world only after onApplied.
  return subscribe(client.conn, focus ? [...GALAXY_QUERIES, ...detailQueries] : GALAXY_QUERIES);
}
