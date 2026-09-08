import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { connect, join, subscribe, GALAXY_QUERIES, DETAIL_QUERIES, type Client } from '../client';
import { adminToken, seedDatabase } from '../admin';
import { cli } from '../tool.mjs';
import { SCENARIOS } from '../domain';
import { checkCompactBattle } from '../battle-snapshot';
import { GAME_QUERIES, gameView } from '../game-client';
import { addPlayer, createGame, command } from '../../shared/game';
import { randomBytes } from 'node:crypto';
import { SystemSubscription } from '../system-subscription';
const ALL_DETAIL_QUERIES = [...DETAIL_QUERIES];

test(
  'durable subscription state survives an abrupt standalone server restart',
  { timeout: 60000 },
  async () => {
    const binary =
      process.env.SPACETIME_STANDALONE ||
      resolve(
        '.tools/spacetime',
        process.platform === 'win32' ? 'spacetimedb-standalone.exe' : 'spacetimedb-standalone',
      );
    assert(existsSync(binary), 'Install local standalone binary first');
    mkdirSync('.spacetime/restart-tests', { recursive: true });
    const data = mkdtempSync(resolve('.spacetime/restart-tests/run-'));
    const uri = 'ws://127.0.0.1:3110',
      server = 'http://127.0.0.1:3110';
    const database = `singularity-restart-${Date.now()}`;
    let child: ChildProcess | undefined;
    const clients: Client[] = [];
    let output = '';
    const canonical = (_key: string, value: unknown): unknown => {
      if (typeof value === 'bigint') return value.toString();
      if (
        Array.isArray(value) &&
        value.length &&
        value[0] &&
        typeof value[0] === 'object' &&
        ('id' in value[0] || 'shipId' in value[0])
      ) {
        return [...value].sort((a, b) => (a.id ?? a.shipId) - (b.id ?? b.shipId));
      }
      return value;
    };
    const start = async () => {
      const existing = await fetch(`${server}/v1/metrics`).catch(() => null);
      if (existing) throw new Error('Port 3110 is already in use; refusing to test an unrelated server');
      child = spawn(
        binary,
        [
          'start',
          '--listen-addr',
          '127.0.0.1:3110',
          '--data-dir',
          data,
          '--non-interactive',
          '--jwt-pub-key-path',
          resolve('.spacetime/config/id_ecdsa.pub'),
          '--jwt-priv-key-path',
          resolve('.spacetime/config/id_ecdsa'),
        ],
        { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
      );
      child.stdout?.on('data', (b) => {
        output = (output + String(b)).slice(-8000);
      });
      child.stderr?.on('data', (b) => {
        output = (output + String(b)).slice(-8000);
      });
      for (let i = 0; i < 100; i++) {
        if (child.exitCode !== null) throw new Error(`Isolated server failed: ${output}`);
        try {
          if ((await fetch(`${server}/v1/metrics`)).ok) return;
        } catch {
          /* socket not ready yet */
        }
        await delay(50);
      }
      throw new Error('Isolated restart server did not start');
    };
    const stop = () =>
      new Promise<void>((resolve) => {
        if (!child || child.exitCode !== null) return resolve();
        child.once('exit', () => resolve());
        child.kill('SIGKILL'); // Crash this test-owned process; do not touch the user's running game/server.
      });
    try {
      await start();
      cli([
        'publish',
        database,
        '--server',
        server,
        '--js-path',
        'spacetimedb/dist/bundle.js',
        '--yes=skip-login',
      ]);
      await seedDatabase(database, SCENARIOS.smoke, uri);
      const admin = await connect(database, { uri, token: adminToken() });
      clients.push(admin);
      const player = await connect(database, { uri });
      clients.push(player);
      await join(player, 1, { fleetId: 1, battleId: 1 }, ALL_DETAIL_QUERIES);
      await delay(700);
      await admin.conn.reducers.setClock({ paused: true, speed: 1 });
      await delay(50);
      const snapshot = JSON.stringify(
        {
          ships: [...player.conn.db.fleetShips.iter()],
          battle: [...player.conn.db.focusedBattle.iter()],
          summary: [...player.conn.db.visibleBattleSummaries.iter()],
          roster: [...player.conn.db.battleRoster.iter()],
          motion: [...player.conn.db.battleMotion.iter()],
          vitals: [...player.conn.db.battleVitals.iter()],
          jobs: [...player.conn.db.myJobs.iter()],
          economy: [...player.conn.db.myEmpire.iter()],
          treaties: [...player.conn.db.myTreaties.iter()],
          decisions: [...player.conn.db.myDecisions.iter()],
          crisis: [...player.conn.db.crisis.iter()],
        },
        canonical,
      );
      // Confirmed reads are enabled; pause is durably acknowledged before killing the process.
      const gameDatabase = `singularity-game-restart-${Date.now()}`;
      cli([
        'publish',
        gameDatabase,
        '--server',
        server,
        '--js-path',
        'spacetimedb/dist/bundle.js',
        '--yes=skip-login',
      ]);
      const gameAdmin = await connect(gameDatabase, { uri, token: adminToken() }),
        gameClient = await connect(gameDatabase, { uri });
      clients.push(gameAdmin, gameClient);
      const source = createGame('ABCD12'),
        owner = addPlayer(source, 'persisted-player', 'Durable');
      source.paused = true;
      source.tick = 30;
      owner.techs.push('terraforming');
      owner.resources = { energy: 5000, minerals: 5000, data: 5000 };
      addPlayer(source, 'trade-peer', 'Trade peer');
      command(source, owner.id, { type: 'research', tech: 'extraction' });
      command(source, owner.id, { type: 'move', fleetId: source.fleets[0].id, systemId: 's1' });
      source.fleets[0].progress = 0.4;
      const riftScout = structuredClone(source.fleets[0]);
      riftScout.id = 'restart-rift-scout';
      riftScout.systemId = source.systems.find((s) => s.kind === 'rift')!.id;
      riftScout.route = [];
      riftScout.progress = 0;
      riftScout.task = { type: 'scan', remaining: 0.01, total: 8 };
      source.fleets.push(riftScout);
      await gameAdmin.conn.reducers.initializeGame({
        code: source.code,
        seed: 42,
        sourceJson: JSON.stringify(source),
        creationKey: 'restart',
      });
      const ticket = randomBytes(32).toString('hex');
      await gameAdmin.conn.reducers.reserveGameSeat({ ticket, externalId: owner.id, templateJson: '' });
      await gameClient.conn.reducers.redeemGameSeat({ ticket });
      await subscribe(gameClient.conn, GAME_QUERIES);
      await gameAdmin.conn.reducers.setClock({ paused: false, speed: 4 });
      for (
        let n = 0;
        n < 100 && !gameView(gameClient)!.situations?.some((s) => s.definitionId === 'resonance-response');
        n++
      )
        await delay(50);
      await gameAdmin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert(
        gameView(gameClient)!.situations!.some(
          (s) => s.definitionId === 'resonance-response' && s.state.status === 'decision',
        ),
      );
      await gameClient.conn.reducers.gameCommand({
        commandJson: JSON.stringify({ type: 'crisis_action', crisisId: 1, action: 'contribute' }),
      });
      await delay(65);
      await gameClient.conn.reducers.gameCommand({
        commandJson: JSON.stringify({
          type: 'site_build',
          systemId: owner.home,
          bodySlot: 2,
          facility: 'habitat',
        }),
      });
      await delay(65);
      await gameClient.conn.reducers.gameCommand({
        commandJson: JSON.stringify({
          type: 'offer_treaty',
          empireId: 'trade-peer',
          kind: 'trade',
          give: { energy: 30, minerals: 0, data: 0 },
          receive: { energy: 0, minerals: 10, data: 0 },
        }),
      });
      const objectHome = [...gameClient.conn.db.myGamePlayer.iter()][0].homeId;
      await new SystemSubscription(gameClient).focus(objectHome);
      await gameClient.conn.reducers.renameBody({
        objectId: `${objectHome}:2`,
        revision: 1,
        name: 'Beständigkeit',
      });
      const objectSnapshot = [...gameClient.conn.db.focusedSystemObjects.iter()].sort(
        (a, b) => a.slot - b.slot,
      );
      await gameClient.conn.reducers.startTerraforming({
        objectId: `${objectHome}:3`,
        revision: 1,
        target: 'continental',
      });
      const terraformSnapshot = [...gameClient.conn.db.myTerraformProjects.iter()];
      const localFleet = gameView(gameClient)!.fleets.find(
        (f) => f.owner === owner.id && f.type === 'corvette',
      )!;
      await gameClient.conn.reducers.gameCommand({
        commandJson: JSON.stringify({
          type: 'local_move',
          fleetId: localFleet.id,
          systemId: localFleet.systemId,
          point: { x: 600, y: 100, z: 400 },
        }),
      });
      await gameClient.conn.reducers.gameCommand({
        commandJson: JSON.stringify({
          type: 'local_move',
          fleetId: localFleet.id,
          systemId: localFleet.systemId,
          point: { x: -600, y: 200, z: 400 },
          append: true,
        }),
      });
      await delay(65);
      await gameClient.conn.reducers.gameCommand({
        commandJson: JSON.stringify({
          type: 'starbase_module',
          systemId: owner.home,
          revision: gameView(gameClient)!.systems.find((s) => s.id === owner.home)!.starbase!.revision,
          slot: 1,
          module: 'trade',
        }),
      });
      const gameSnapshot = gameView(gameClient)!;
      await stop();
      await start();
      const resumed = await connect(database, { uri, token: player.token });
      clients.push(resumed);
      await subscribe(resumed.conn, [...GALAXY_QUERIES, ...ALL_DETAIL_QUERIES]);
      assert.equal(checkCompactBattle(resumed, 1), 40);
      assert.equal(resumed.identity, player.identity);
      const restored = JSON.stringify(
        {
          ships: [...resumed.conn.db.fleetShips.iter()],
          battle: [...resumed.conn.db.focusedBattle.iter()],
          summary: [...resumed.conn.db.visibleBattleSummaries.iter()],
          roster: [...resumed.conn.db.battleRoster.iter()],
          motion: [...resumed.conn.db.battleMotion.iter()],
          vitals: [...resumed.conn.db.battleVitals.iter()],
          jobs: [...resumed.conn.db.myJobs.iter()],
          economy: [...resumed.conn.db.myEmpire.iter()],
          treaties: [...resumed.conn.db.myTreaties.iter()],
          decisions: [...resumed.conn.db.myDecisions.iter()],
          crisis: [...resumed.conn.db.crisis.iter()],
        },
        canonical,
      );
      assert.equal(
        restored,
        snapshot,
        'Durable rows must reconstruct exactly, including current weapon cycles and targets',
      );
      const gameResumed = await connect(gameDatabase, { uri, token: gameClient.token });
      clients.push(gameResumed);
      await subscribe(gameResumed.conn, GAME_QUERIES);
      assert.equal(gameResumed.identity, gameClient.identity);
      assert.deepEqual(
        [...gameResumed.conn.db.myTerraformProjects.iter()],
        terraformSnapshot,
        'paid terraforming projects and deadlines survive database restart',
      );
      await new SystemSubscription(gameResumed).focus(objectHome);
      assert.deepEqual(
        [...gameResumed.conn.db.focusedSystemObjects.iter()].sort((a, b) => a.slot - b.slot),
        objectSnapshot,
        'stored bodies, names, revisions and parent references survive an abrupt restart',
      );
      assert.deepEqual(
        gameView(gameResumed)!.systems.map((s) => s.starbase),
        gameSnapshot.systems.map((s) => s.starbase),
        'starbase modules, revisions, paid project and deadline survive a database crash',
      );
      assert.deepEqual(gameView(gameResumed)!.me, gameSnapshot.me);
      assert.deepEqual(gameView(gameResumed)!.fleets, gameSnapshot.fleets);
      assert.equal(gameView(gameResumed)!.tick, gameSnapshot.tick);
      assert.deepEqual(
        gameView(gameResumed)!.sites,
        gameSnapshot.sites,
        'body address, paid construction and completion deadline survive a database crash',
      );
      assert.deepEqual(
        gameView(gameResumed)!.situations,
        gameSnapshot.situations,
        'private event, choices and deadline survive a database crash',
      );
      assert.deepEqual(
        gameView(gameResumed)!.crises,
        gameSnapshot.crises,
        'phase, deadline and paid contributions survive a database crash',
      );
      assert.deepEqual(
        gameView(gameResumed)!.offers,
        gameSnapshot.offers,
        'escrow terms and deadline survive a database crash',
      );
      const escrow = gameSnapshot.offers![0];
      await gameResumed.conn.reducers.gameCommand({
        commandJson: JSON.stringify({ type: 'cancel_treaty', treatyId: escrow.id }),
      });
      assert.equal(
        gameView(gameResumed)!.me.resources.energy,
        gameSnapshot.me.resources.energy + 30,
        'persisted escrow refunded once after restart',
      );
      const gameMonitor = await connect(gameDatabase, { uri, token: adminToken() });
      clients.push(gameMonitor);
      await subscribe(gameMonitor.conn, ['SELECT * FROM clock']);
      await gameResumed.conn.reducers.gameCommand({ commandJson: JSON.stringify({ type: 'pause' }) });
      gameResumed.conn.disconnect();
      for (let n = 0; n < 50 && ![...gameMonitor.conn.db.clock.iter()][0].paused; n++) await delay(50);
      assert(
        [...gameMonitor.conn.db.clock.iter()][0].paused,
        'crash leaves no ghost connection preventing auto-pause',
      );
      const controller = await connect(database, { uri, token: adminToken() });
      clients.push(controller);
      const step = [...resumed.conn.db.focusedBattle.iter()][0].step;
      await controller.conn.reducers.setClock({ paused: false, speed: 1 });
      await delay(600);
      assert(
        [...resumed.conn.db.focusedBattle.iter()][0].step > step,
        'Persisted schedule tables must resume battle simulation',
      );
      mkdirSync('backend/reports', { recursive: true });
      writeFileSync(
        'backend/reports/restart.json',
        JSON.stringify(
          {
            measuredAt: new Date().toISOString(),
            database,
            result: 'pass',
            assertion:
              'Identical durable snapshots after forced process termination, same identity, scheduled battle resumed',
            retained: [
              'ships',
              'battle',
              'participants/targets/weapon cycles',
              'jobs',
              'economy',
              'treaties',
              'decisions',
              'crisis',
              'production game identity, private empire, research, fleet travel and disconnect lifecycle',
              'event instances, crisis phase, deadlines and paid contributions',
            ],
            limitation:
              'Clock was paused immediately before the forced termination to compare exact snapshots; live reconnects are covered separately.',
          },
          null,
          2,
        ) + '\n',
      );
    } finally {
      for (const c of clients) c.conn.disconnect();
      await stop();
    }
  },
);
