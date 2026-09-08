import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import { resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { performance, monitorEventLoopDelay } from 'node:perf_hooks';
import { createHash } from 'node:crypto';
import { cli } from './tool.mjs';
import {
  connect,
  join,
  subscribe,
  GALAXY_QUERIES,
  DETAIL_QUERIES,
  type Client,
  type Compression,
} from './client';
import { checkCompactBattle } from './battle-snapshot';
import { seedDatabase, adminToken } from './admin';
import { SCENARIOS, validateScenario, type Scenario } from './domain';

const options = Object.fromEntries(
  process.argv.slice(2).map((arg) => {
    const [k, ...v] = arg.replace(/^--/, '').split('=');
    return [k, v.join('=')];
  }),
);
const profile = options.profile || 'standard';
const scenario: Scenario = options.scenario
  ? JSON.parse(readFileSync(options.scenario, 'utf8'))
  : SCENARIOS[profile];
if (!scenario) throw new Error(`Unknown profile ${profile}`);
validateScenario(scenario);
const seconds = Number(options.seconds || 60);
if (!Number.isFinite(seconds) || seconds < 10 || seconds > 3600) throw new Error('Use --seconds=10..3600');
const detail = 'compact';
if (options.detail !== undefined && options.detail !== detail)
  throw new Error('Only compact battle views are supported');
const compression = (options.compression || 'gzip') as Compression;
if (!['none', 'gzip'].includes(compression)) throw new Error('Use --compression=none|gzip');
const battleCopies = Number(options['battle-copies'] || 1);
if (!Number.isInteger(battleCopies) || battleCopies < 1 || battleCopies > 100)
  throw new Error('Use --battle-copies=1..100 (connections per battle identity)');
const detailQueries = DETAIL_QUERIES;
const database = `singularity-bench-${profile.replace(/[^a-z0-9-]/g, '')}-${Date.now()}`;
const http = process.env.SPACETIME_HTTP || 'http://127.0.0.1:3100';
const uri = process.env.SPACETIME_WS || 'ws://127.0.0.1:3100';
const output = resolve(
  options.output || `backend/reports/${profile}-${detail}-${compression}-${battleCopies}x.json`,
);
const sourceFiles = [
  'backend/domain.ts',
  ...['tables', 'rules', 'seed', 'simulation', 'commands', 'views', 'index', 'battle-reports'].map(
    (f) => `spacetimedb/src/${f}.ts`,
  ),
];
const simulationSha256 = createHash('sha256')
  .update(sourceFiles.map((path) => readFileSync(path, 'utf8')).join('\n'))
  .digest('hex');
const clientSha256 = createHash('sha256')
  .update(
    ['backend/client.ts', 'backend/transport.ts', 'backend/battle-snapshot.ts', 'backend/benchmark.ts']
      .map((path) => readFileSync(path, 'utf8'))
      .join('\n'),
  )
  .digest('hex');
mkdirSync(resolve('backend/reports'), { recursive: true });

type Metric = { name: string; labels: Record<string, string>; value: number };
async function metrics(): Promise<Metric[]> {
  const response = await fetch(`${http}/v1/metrics`);
  if (!response.ok) throw new Error(`Native metrics unavailable (${response.status})`);
  return (await response.text()).split('\n').flatMap((line) => {
    const m = /^([a-zA-Z0-9_]+)(?:\{(.*)\})?\s+([^ ]+)$/.exec(line);
    if (!m) return [];
    const labels = Object.fromEntries(
      [...(m[2] || '').matchAll(/([a-zA-Z0-9_]+)="([^"]*)"/g)].map((r) => [r[1], r[2]]),
    );
    return [{ name: m[1], labels, value: Number(m[3]) }];
  });
}
const percentile = (values: number[], q: number) =>
  values.length
    ? [...values].sort((a, b) => a - b)[Math.min(values.length - 1, Math.floor(values.length * q))]
    : null;
const summary = (values: number[]) => ({
  count: values.length,
  p50: percentile(values, 0.5),
  p95: percentile(values, 0.95),
  max: values.length ? Math.max(...values) : null,
});
type Seat = {
  client: Client;
  empireId: number;
  mode: 'battle' | 'galaxy';
  totals: {
    down: number;
    up: number;
    frames: number;
    decoded: number;
    decodeMs: number;
    compressedFrames: number;
  };
  peakPendingBytes: number;
  initialBytes: number;
};
const seats: Seat[] = [];
const joins: { kind: string; mode: string; ms: number; bytes: number; battleStep: number | null }[] = [];
const lags: Record<string, number[]> = {};
let admin: Client | undefined;
const assertions = { snapshotsChecked: 0, errors: [] as string[] };

async function openSeat(empireId: number, token?: string, replicaJoin = false) {
  const start = performance.now();
  const mode = empireId <= scenario.battleCount * 2 && empireId % 2 === 1 ? 'battle' : 'galaxy';
  const client = await connect(database, { uri, token, compression });
  try {
    const focus =
      mode === 'battle'
        ? { fleetId: (empireId - 1) * scenario.fleetsPerEmpire + 1, battleId: Math.ceil(empireId / 2) }
        : undefined;
    if (token)
      await subscribe(
        client.conn,
        mode === 'battle' ? [...GALAXY_QUERIES, ...detailQueries] : GALAXY_QUERIES,
      );
    else {
      await join(client, empireId, focus, detailQueries);
      await client.conn.reducers.setAutomation({ enabled: true });
    }
    if (Number(client.conn.db.star.count()) !== scenario.systems) throw new Error('Incomplete star snapshot');
    if ([...client.conn.db.myEmpire.iter()][0]?.id !== empireId) throw new Error('Wrong empire snapshot');
    if (mode === 'galaxy' && client.conn.db.fleetShips.count() !== 0n)
      throw new Error('Galaxy subscription leaked ship details');
    if (focus) {
      const f = client.conn.db.galaxyFleets.id.find(focus.fleetId);
      if (!f || f.shipCount !== Number(client.conn.db.fleetShips.count()))
        throw new Error('Fleet/ship snapshot mismatch');
      const participants = [...client.conn.db.battleVitals.iter()];
      const b = client.conn.db.focusedBattle.id.find(focus.battleId);
      if (!b || (b.state === 'active' && !participants.length))
        throw new Error('Battle reconstruction failed');
      const ids = new Set(participants.map((p) => p.shipId));
      if (participants.some((p) => p.targetId && !ids.has(p.targetId)))
        throw new Error('Dangling battle target in initial snapshot');
      checkCompactBattle(client, focus.battleId);
    }
    assertions.snapshotsChecked++;
    joins.push({
      kind: replicaJoin ? 'replica-join' : token ? 'reconnect' : 'hot-join',
      mode,
      ms: performance.now() - start,
      bytes: client.traffic.receivedBytes,
      battleStep:
        mode === 'battle'
          ? (client.conn.db.focusedBattle.id.find(Math.ceil(empireId / 2))?.step ?? null)
          : null,
    });
    return {
      client,
      empireId,
      mode,
      totals: { down: 0, up: 0, frames: 0, decoded: 0, decodeMs: 0, compressedFrames: 0 },
      peakPendingBytes: client.traffic.peakPendingBytes,
      initialBytes: client.traffic.receivedBytes,
    } satisfies Seat;
  } catch (e) {
    client.conn.disconnect();
    throw e;
  }
}

console.log(`Publishing ${database}`);
const published = cli([
  'publish',
  database,
  '--server',
  http,
  '--js-path',
  'spacetimedb/dist/bundle.js',
  '--yes=skip-login',
]);
const databaseIdentity = /identity: ([0-9a-f]{64})/.exec(published)?.[1];
if (!databaseIdentity) throw new Error('Cannot resolve benchmark database identity from local publish');
const seedingAt = performance.now();
await seedDatabase(database, scenario, uri);
const seedingMs = performance.now() - seedingAt;
console.log(
  `Seeded ${scenario.empires * scenario.shipsPerEmpire} ships in ${Math.round(seedingMs)} ms. Connecting ${scenario.empires} independent identities.`,
);

try {
  admin = await connect(database, { uri, token: adminToken() });
  await subscribe(admin.conn, ['SELECT * FROM diagnostics', 'SELECT * FROM clock', 'SELECT * FROM scenario']);
  for (let empireId = 1; empireId <= scenario.empires; empireId++) seats.push(await openSeat(empireId));
  // Extra connections reuse an authorized player's identity. They measure fan-out,
  // not additional independent players or a new spectator permission policy.
  for (const seat of seats.filter((s) => s.mode === 'battle'))
    for (let copy = 1; copy < battleCopies; copy++)
      seats.push(await openSeat(seat.empireId, seat.client.token, true));
  await delay(3000);
  const beforeMetrics = await metrics();
  for (const seat of seats) {
    seat.totals.down = -seat.client.traffic.receivedBytes;
    seat.totals.up = -seat.client.traffic.sentBytes;
    seat.totals.frames = -seat.client.traffic.frames;
    seat.totals.decoded = -seat.client.traffic.decodedBytes;
    seat.totals.decodeMs = -seat.client.traffic.decodeMs;
    seat.totals.compressedFrames = -seat.client.traffic.compressedFrames;
  }
  const eventLoop = monitorEventLoopDelay({ resolution: 10 });
  eventLoop.enable();
  const start = performance.now();
  let nextReconnectAt = start + 2500,
    reconnectIndex = 0;
  let progressAt = start + 10000;
  while (performance.now() - start < seconds * 1000) {
    await delay(250);
    for (const seat of seats)
      if (!seat.client.conn.isActive) throw new Error('Unexpected disconnected load client');
    for (const m of admin.conn.db.diagnostics.iter()) (lags[m.name] ??= []).push(m.lastLagMs);
    if (performance.now() >= nextReconnectAt) {
      const seat = seats[reconnectIndex++ % seats.length];
      const previous = seat.client;
      seat.totals.down += previous.traffic.receivedBytes;
      seat.totals.up += previous.traffic.sentBytes;
      seat.totals.frames += previous.traffic.frames;
      seat.totals.decoded += previous.traffic.decodedBytes;
      seat.totals.decodeMs += previous.traffic.decodeMs;
      seat.totals.compressedFrames += previous.traffic.compressedFrames;
      seat.peakPendingBytes = Math.max(seat.peakPendingBytes, previous.traffic.peakPendingBytes);
      previous.conn.disconnect();
      const replacement = await openSeat(seat.empireId, previous.token);
      seat.client = replacement.client;
      nextReconnectAt += 2500;
    }
    if (performance.now() >= progressAt) {
      console.log(
        `${Math.round((performance.now() - start) / 1000)} s: ${joins.length} coherent snapshots, combat lag ${Math.round(lags.combat.at(-1) ?? 0)} ms`,
      );
      progressAt += 10000;
    }
  }
  const measuredSeconds = (performance.now() - start) / 1000;
  const afterMetrics = await metrics();
  eventLoop.disable();
  const native = (name: string, reducer?: string, data = afterMetrics) =>
    data
      .filter(
        (m) =>
          m.name === name &&
          (m.labels.db || m.labels.database_identity) === databaseIdentity &&
          (!reducer || m.labels.reducer === reducer),
      )
      .reduce((sum, m) => sum + m.value, 0);
  const gauge = (name: string) =>
    afterMetrics.some(
      (m) => m.name === name && (m.labels.db || m.labels.database_identity) === databaseIdentity,
    )
      ? native(name)
      : null;
  const delta = (name: string, reducer?: string) =>
    native(name, reducer) - native(name, reducer, beforeMetrics);
  const reducerMetrics = ['strategic_tick', 'economy_tick', 'combat_tick', 'ai_tick'].map((reducer) => {
    const base = 'spacetime_reducer_plus_query_duration_sec';
    const count = delta(`${base}_count`, reducer);
    const buckets = afterMetrics
      .filter(
        (m) =>
          m.name === `${base}_bucket` && m.labels.db === databaseIdentity && m.labels.reducer === reducer,
      )
      .map((m) => ({
        bound: Number(m.labels.le),
        count:
          m.value -
          (beforeMetrics.find(
            (b) =>
              b.name === m.name &&
              b.labels.db === databaseIdentity &&
              b.labels.reducer === reducer &&
              b.labels.le === m.labels.le,
          )?.value ?? 0),
      }))
      .sort((a, b) => a.bound - b.bound);
    return {
      reducer,
      calls: count,
      meanExecutionAndSubscriptionMs: count ? (delta(`${base}_sum`, reducer) / count) * 1000 : null,
      p95UpperBoundMs: (buckets.find((b) => b.count >= count * 0.95)?.bound ?? 0) * 1000,
      meanQueueWaitMs:
        native('spacetime_reducer_wait_time_sec_count', reducer) > 0
          ? (delta('spacetime_reducer_wait_time_sec_sum', reducer) /
              Math.max(1, delta('spacetime_reducer_wait_time_sec_count', reducer))) *
            1000
          : null,
    };
  });
  const traffic = seats.map((seat) => ({
    empireId: seat.empireId,
    mode: seat.mode,
    receivedBytes: seat.totals.down + seat.client.traffic.receivedBytes,
    sentBytes: seat.totals.up + seat.client.traffic.sentBytes,
    frames: seat.totals.frames + seat.client.traffic.frames,
    decodedBytes: seat.totals.decoded + seat.client.traffic.decodedBytes,
    decodeMs: seat.totals.decodeMs + seat.client.traffic.decodeMs,
    compressedFrames: seat.totals.compressedFrames + seat.client.traffic.compressedFrames,
    peakPendingBytes: Math.max(seat.peakPendingBytes, seat.client.traffic.peakPendingBytes),
    initialSnapshotBytes: seat.initialBytes,
  }));
  const totals = traffic.reduce(
    (acc, s) => ({
      receivedBytes: acc.receivedBytes + s.receivedBytes,
      sentBytes: acc.sentBytes + s.sentBytes,
    }),
    { receivedBytes: 0, sentBytes: 0 },
  );
  const report = {
    schemaVersion: 2,
    measuredAt: new Date().toISOString(),
    database,
    databaseIdentity,
    spacetimedbVersion: '2.10.0',
    simulationSha256,
    clientSha256,
    hardware: {
      platform: os.platform(),
      osRelease: os.release(),
      cpu: os.cpus()[0]?.model,
      logicalCpus: os.cpus().length,
      ramGiB: os.totalmem() / 2 ** 30,
      node: process.version,
      network: 'loopback; server and load clients on same machine',
    },
    scenario,
    workload: {
      totalShips: scenario.empires * scenario.shipsPerEmpire,
      totalFleets: scenario.empires * scenario.fleetsPerEmpire,
      colonies: scenario.empires * Math.min(10, Math.floor(scenario.systems / scenario.empires)),
      battleParticipantsAtStart:
        scenario.battleCount *
        2 *
        scenario.battleFleetsPerSide *
        Math.ceil(scenario.shipsPerEmpire / scenario.fleetsPerEmpire),
      connectedIdentities: new Set(seats.map((s) => s.client.identity)).size,
      connectedClients: seats.length,
      battleCopiesPerIdentity: battleCopies,
      activeAiPlanners: scenario.empires,
      detailedBattleClients: seats.filter((s) => s.mode === 'battle').length,
      detail,
      compression,
      productionCycleGameSeconds: 4,
      combatStepGameSeconds: 0.2,
    },
    seedingMs,
    measuredSeconds,
    joins: {
      hotJoinMs: summary(joins.filter((j) => j.kind === 'hot-join').map((j) => j.ms)),
      replicaJoinMs: summary(joins.filter((j) => j.kind === 'replica-join').map((j) => j.ms)),
      reconnectMs: summary(joins.filter((j) => j.kind === 'reconnect').map((j) => j.ms)),
      samples: joins,
    },
    schedulerLagMs: Object.fromEntries(
      Object.entries(lags).map(([name, samples]) => [name, summary(samples)]),
    ),
    nativeReducers: reducerMetrics,
    scheduledReducerMeanQueueWaitMs:
      (delta('spacetime_reducer_wait_time_sec_sum', 'scheduled reducer') /
        Math.max(1, delta('spacetime_reducer_wait_time_sec_count', 'scheduled reducer'))) *
      1000,
    network: {
      ...totals,
      downstreamKiBPerSecond: totals.receivedBytes / measuredSeconds / 1024,
      perClient: traffic.map((s) => ({
        ...s,
        downstreamKiBPerSecond: s.receivedBytes / measuredSeconds / 1024,
      })),
      measurement:
        'WebSocket binary message bytes, including reconnect snapshots; excluding HTTP auth, TCP/TLS/WebSocket frame overhead',
    },
    storage: {
      rowBytes: gauge('spacetime_data_size_bytes_used_by_rows'),
      indexBytes: gauge('spacetime_data_size_table_bytes_used_by_index_keys'),
      blobBytes: gauge('spacetime_data_size_blob_store_bytes_used_by_blobs'),
      messageLogBytes: gauge('spacetime_message_log_size_bytes'),
      workerV8HeapBytes: gauge('spacetime_worker_v8_used_heap_size_bytes'),
    },
    loadGenerator: {
      eventLoopP95Ms: eventLoop.percentile(95) / 1e6,
      heapUsedMiB: process.memoryUsage().heapUsed / 2 ** 20,
    },
    assertions,
    limitations: [
      'Prototype combat: linear target assignment, strafing and weapon cooldowns; no projectiles/pathfinding/collision avoidance.',
      'Short loopback test, no WAN latency/packet loss or long soak; browser FPS is recorded separately.',
      '25k/75k are scenarios, not capacity limits. Capacity validation requires larger single battles, longer runs and deployment-hardware tests.',
    ],
  };
  writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
  console.log(
    JSON.stringify(
      {
        report: output,
        database,
        seconds: measuredSeconds,
        reconnects: report.joins.reconnectMs,
        networkKiBs: report.network.downstreamKiBPerSecond,
        reducers: reducerMetrics,
      },
      null,
      2,
    ),
  );
} catch (error) {
  assertions.errors.push(String(error));
  writeFileSync(
    output.replace(/\.json$/, '.failed.json'),
    JSON.stringify({ database, scenario, assertions, joins }, null, 2),
  );
  throw error;
} finally {
  if (admin) {
    await admin.conn.reducers.setClock({ paused: true, speed: 1 });
    admin.conn.disconnect();
  }
  for (const seat of seats) seat.client.conn.disconnect();
}
