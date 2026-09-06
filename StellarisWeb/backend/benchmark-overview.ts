import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';
import { adminToken, seedDatabase } from './admin';
import { connect, join, type Client } from './client';
import { BattleDetailSubscription } from './detail-subscriptions';
import { validateScenario, type Scenario } from './domain';
import { cli } from './tool.mjs';

// Fresh world, same connection: overview -> battle -> overview. No saved games are reset.
const database = `singularity-overview-bench-${Date.now()}`;
const http = process.env.SPACETIME_HTTP || 'http://127.0.0.1:3100';
const uri = process.env.SPACETIME_WS || 'ws://127.0.0.1:3100';
const scenario: Scenario = JSON.parse(readFileSync('backend/scenarios/battle-heavy.json', 'utf8'));
validateScenario(scenario);
const seconds = 12;
console.log(`Publishing ${database}`);
cli(['publish', database, '--server', http, '--js-path', 'spacetimedb/dist/bundle.js', '--yes=skip-login']);
await seedDatabase(database, scenario, uri);
const admin = await connect(database, { uri, token: adminToken() });
const clients: Client[] = [];
let scope: BattleDetailSubscription | undefined;
try {
  await admin.conn.reducers.setClock({ paused: true, speed: 1 });
  for (let id = 1; id <= scenario.empires; id++) {
    const client = await connect(database, { uri });
    clients.push(client);
    await join(client, id);
  }
  const player = clients[0];
  scope = new BattleDetailSubscription(player);
  const counts = () => ({
    motion: Number(player.conn.db.battleMotion.count()),
    roster: Number(player.conn.db.battleRoster.count()),
    vitals: Number(player.conn.db.battleVitals.count()),
    ships: Number(player.conn.db.fleetShips.count()),
    battleClock: Number(player.conn.db.focusedBattle.count()),
    legacyBattleClock: Number(player.conn.db.visibleBattles.count()),
  });
  const noDetails = () => {
    for (const value of Object.values(counts())) assert.equal(value, 0);
  };
  const totalBytes = () => clients.reduce((sum, c) => sum + c.traffic.receivedBytes, 0);
  async function measure(mode: string) {
    let summaryUpdates = 0,
      detailUpdates = 0;
    const summaryChanged = () => {
      summaryUpdates++;
    };
    const detailChanged = () => {
      detailUpdates++;
    };
    player.conn.db.visibleBattleSummaries.onUpdate(summaryChanged);
    player.conn.db.battleMotion.onUpdate(detailChanged);
    const from = player.conn.db.visibleBattleSummaries.id.find(1)!.sampledAt;
    const bytes = player.traffic.receivedBytes,
      aggregateBytes = totalBytes(),
      at = performance.now();
    await delay(seconds * 1000);
    const elapsed = (performance.now() - at) / 1000;
    const to = player.conn.db.visibleBattleSummaries.id.find(1)!.sampledAt;
    player.conn.db.visibleBattleSummaries.removeOnUpdate(summaryChanged);
    player.conn.db.battleMotion.removeOnUpdate(detailChanged);
    assert(to > from + seconds - 3, 'Combat must keep progressing without a detail subscriber');
    assert(summaryUpdates >= seconds - 2 && summaryUpdates <= seconds + 2);
    if (mode !== 'battle') {
      noDetails();
      assert.equal(detailUpdates, 0);
    } else assert.equal(counts().motion, 3000);
    const result = {
      mode,
      elapsed,
      receivedKiBps: (player.traffic.receivedBytes - bytes) / elapsed / 1024,
      all25ClientsKiBps: (totalBytes() - aggregateBytes) / elapsed / 1024,
      summaryUpdates,
      detailUpdates,
      simulatedFrom: from,
      simulatedTo: to,
      rows: counts(),
    };
    console.log(JSON.stringify(result));
    return result;
  }
  noDetails();
  await admin.conn.reducers.setClock({ paused: false, speed: 1 });
  await delay(1000);
  const before = await measure('overview-before');
  const openAt = performance.now(),
    openBytes = player.traffic.receivedBytes;
  await scope.focus(1, 1);
  const open = { ms: performance.now() - openAt, wireBytes: player.traffic.receivedBytes - openBytes };
  await delay(500);
  const battle = await measure('battle');
  const lastStep = player.conn.db.focusedBattle.id.find(1)!.step;
  await scope.focus(0, 0);
  await delay(500);
  const after = await measure('overview-after');
  await scope.focus(1, 1);
  const rejoinedStep = player.conn.db.focusedBattle.id.find(1)!.step;
  assert(rejoinedStep > lastStep + 45, 'Reopening must reconstruct the progressed battle');
  await scope.focus(0, 0);
  noDetails();
  const sourceFiles = [
    'backend/client.ts',
    'backend/detail-subscriptions.ts',
    'backend/transport.ts',
    'backend/domain.ts',
    'backend/benchmark-overview.ts',
    ...['tables', 'rules', 'simulation', 'commands', 'views', 'seed', 'index', 'battle-reports'].map(
      (f) => `spacetimedb/src/${f}.ts`,
    ),
  ];
  const result = {
    timestamp: new Date().toISOString(),
    database,
    scenario,
    compression: 'gzip',
    clients: 25,
    sourceSha256: createHash('sha256')
      .update(sourceFiles.map((f) => readFileSync(f, 'utf8')).join('\n'))
      .digest('hex'),
    phases: [before, battle, after],
    open,
    lastStep,
    rejoinedStep,
    reductionPercent: (1 - after.receivedKiBps / battle.receivedKiBps) * 100,
  };
  mkdirSync('backend/reports', { recursive: true });
  writeFileSync('backend/reports/overview.json', JSON.stringify(result, null, 2) + '\n');
  writeFileSync(
    'backend/reports/OVERVIEW.md',
    `# Gefechtsübersicht und Detailabonnement\n\nGemessen: ${result.timestamp}. SpacetimeDB 2.10.0, lokal unter Windows, Gzip. Frische Galaxie mit 1.000 Systemen, 75.000 Schiffen und 25 unabhängigen Spieleridentitäten. Ein Gefecht mit 3.000 Teilnehmern. 24 Clients bleiben in der Galaxie; ein beteiligter Spieler wechselt die Ansicht. Je Phase zwölf Sekunden, nach kurzer Aufwärmzeit. Initiale Snapshots und Ansichtswechsel sind aus den laufenden Raten ausgeschlossen. Keine WAN-, FPS- oder Skalierungszusage.\n\n| Ansicht des beteiligten Spielers | Empfang KiB/s | Alle 25 Clients KiB/s | Übersichtsupdates | Bewegungsupdates | Taktische Schiffe im Cache |\n|---|---:|---:|---:|---:|---:|\n${result.phases.map((p) => `| ${p.mode} | ${p.receivedKiBps.toFixed(2)} | ${p.all25ClientsKiBps.toFixed(2)} | ${p.summaryUpdates} | ${p.detailUpdates} | ${p.rows.motion} |`).join('\n')}\n\nNach Verlassen des Gefechts: **${result.reductionPercent.toFixed(2)} % weniger Empfang** für diesen Client als während der Detailansicht. Die Übersichtsrate enthält auch Spieluhr, Wirtschaft und berechtigte Flottenänderungen. Es werden weder Schiffsdaten noch die laufende Gefechtsuhr abonniert; HP-Zusammenfassungen werden ungefähr einmal je Echtzeitsekunde veröffentlicht.\n\nErstes Öffnen einschließlich Snapshot: ${open.ms.toFixed(1)} ms und ${(open.wireBytes / 1024).toFixed(1)} KiB. Beim Wiederöffnen ist der Gefechtsstand von Schritt ${lastStep} auf ${rejoinedStep} fortgeschritten. Simulation und Schaden laufen weiter, während niemand die Details betrachtet.\n\nPrüfungen im Skript: null Detailzeilen und null Bewegungsereignisse in beiden Übersichtsphasen, 3.000 Teilnehmer in der Gefechtsansicht, etwa 1 Hz Zusammenfassungen, fortgeschrittener Snapshot beim Wiederöffnen. Rohdaten und Quellstand-Fingerprint: [overview.json](overview.json). Reproduzieren: \`npm run backend:bench:overview\` nach \`npm run backend:build\`. Jede Ausführung legt eine neue Testdatenbank an und pausiert sie abschließend.\n`,
  );
} finally {
  scope?.dispose();
  await admin.conn.reducers.setClock({ paused: true, speed: 1 });
  for (const client of clients) client.conn.disconnect();
  admin.conn.disconnect();
}
