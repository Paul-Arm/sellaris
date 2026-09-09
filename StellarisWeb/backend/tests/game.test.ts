import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { cli } from '../tool.mjs';
import { connect, subscribe, type Client } from '../client';
import { GAME_QUERIES, gameView } from '../game-client';
import { BattleDetailSubscription } from '../detail-subscriptions';
import { addPlayer, command, createGame, type GameCommand } from '../../shared/game';
import { adminToken } from '../admin';
import { starterLibrary, snapshotTemplate } from '../../shared/empires';

const issue = (c: Client, command: GameCommand) =>
  c.conn.reducers.gameCommand({ commandJson: JSON.stringify(command) });
async function until(check: () => boolean, label: string, timeout = 15000) {
  const end = Date.now() + timeout;
  while (!check()) {
    assert(Date.now() < end, label);
    await delay(80);
  }
}
async function seat(admin: Client, client: Client, externalId: string, templateJson = '') {
  const ticket = randomBytes(32).toString('hex');
  await admin.conn.reducers.reserveGameSeat({ ticket, externalId, templateJson });
  await client.conn.reducers.redeemGameSeat({ ticket });
  await subscribe(client.conn, GAME_QUERIES);
  return ticket;
}
test('production galaxy: founding, private state and command ownership', { timeout: 30000 }, async () => {
  const database = `singularity-game-test-${Date.now()}`;
  cli([
    'publish',
    database,
    '--server',
    'http://127.0.0.1:3100',
    '--js-path',
    'spacetimedb/dist/bundle.js',
    '--yes=skip-login',
  ]);
  const admin = await connect(database, { token: adminToken() }),
    a = await connect(database),
    b = await connect(database);
  try {
    await admin.conn.reducers.initializeGame({
      code: 'ABCDEF',
      seed: 42,
      sourceJson: '',
      creationKey: 'test',
    });
    const library = starterLibrary(),
      template = snapshotTemplate(library, library.empires[0].id);
    template.empire.shipSet = 'vektor';
    for (const [client, id] of [
      [a, 'player-a'],
      [b, 'player-b'],
    ] as const) {
      const ticket = randomBytes(32).toString('hex');
      await admin.conn.reducers.reserveGameSeat({
        ticket,
        externalId: id,
        templateJson: JSON.stringify(template),
      });
      await client.conn.reducers.redeemGameSeat({ ticket });
      await subscribe(client.conn, GAME_QUERIES);
    }
    await a.conn.reducers.gameCommand({ commandJson: JSON.stringify({ type: 'pause' }) });
    await delay(40);
    assert.equal(a.conn.db.star.count(), 1000n);
    assert.equal(a.conn.db.gamePlayers.count(), 2n);
    assert(gameView(a)!.players.every((p) => p.shipSet === 'vektor'));
    assert(gameView(b)!.players.every((p) => p.shipSet === 'vektor'));
    assert.equal(gameView(a)!.me.empire!.design.shipSet, 'vektor');
    const foundingEmpire = structuredClone(gameView(a)!.me.empire);
    await assert.rejects(
      a.conn.reducers.gameCommand({
        commandJson: JSON.stringify({
          type: 'empire_ship_set',
          shipSet: 'aureole',
          revision: foundingEmpire!.revision,
        }),
      }),
      /Unbekannter Befehl/,
    );
    assert.deepEqual(
      gameView(a)!.me.empire,
      foundingEmpire,
      'founding design cannot be changed in a running game',
    );
    assert(gameView(b)!.players.every((p) => p.shipSet === 'vektor'));
    assert.equal([...a.conn.db.myGamePlayer.iter()][0].externalId, 'player-a');
    assert.equal([...b.conn.db.myGamePlayer.iter()][0].externalId, 'player-b');
    assert.equal(a.conn.db.fleetShips.count(), 0n);
    await admin.conn.reducers.setClock({ paused: true, speed: 3 });
    await until(
      () => [...a.conn.db.clock.iter()][0].speed === 3,
      'production supports its 3x speed during upgrades',
    );
    await admin.conn.reducers.setClock({ paused: true, speed: 1 });
    await assert.rejects(b.conn.reducers.gameCommand({ commandJson: JSON.stringify({ type: 'pause' }) }));
    await assert.rejects(b.conn.reducers.joinEmpire({ empireId: 1 }));
    await assert.rejects(a.conn.reducers.startJob({ kind: 'research', targetId: 0 }));
    const me = [...a.conn.db.myGamePlayer.iter()][0];
    const fleet = gameView(a)!.fleets.find((f) => f.owner === me.externalId)!;
    const beforeMove = structuredClone(fleet);
    await assert.rejects(
      issue(a, { type: 'move', fleetId: fleet.id, systemId: fleet.systemId }),
      /Die Flotte befindet sich bereits in diesem System\./,
    );
    assert.deepEqual(
      gameView(a)!.fleets.find((f) => f.id === fleet.id),
      beforeMove,
    );
    await a.conn.reducers.gameCommand({
      commandJson: JSON.stringify({ type: 'research', tech: 'extraction' }),
    });
    await a.conn.reducers.gameCommand({
      commandJson: JSON.stringify({
        type: 'build',
        ship: 'corvette',
        systemId: a.conn.db.gameAtlas.id.find(me.homeId)!.externalId,
      }),
    });
    assert.equal([...a.conn.db.myJobs.iter()].filter((j) => j.status === 'active').length, 1);
    assert.equal(gameView(a)!.me.research.projects.length, 1);
    for (let i = 2; i < 25; i++) {
      await issue(a, { type: 'add_ai' });
      await delay(75);
    }
    assert.equal(a.conn.db.gamePlayers.count(), 25n);
    assert.equal(new Set([...a.conn.db.gamePlayers.iter()].map((p) => p.homeId)).size, 25);
    await assert.rejects(issue(a, { type: 'add_ai' }));
    await admin.conn.reducers.setClock({ paused: false, speed: 4 });
    const start = gameView(a)!.tick;
    await until(() => gameView(a)!.tick >= start + 12, '25-empire production galaxy continues scheduling');
    assert.equal(a.conn.db.fleetShips.count(), 0n, 'active AI never forces ship details into the galaxy');
  } finally {
    await admin.conn.reducers.setClock({ paused: true, speed: 1 });
    for (const c of [a, b, admin]) c.conn.disconnect();
  }
});

test(
  'current operator snapshots retain identity, economy, work and routes; production, exploration, formations and hot reconnect',
  { timeout: 120000 },
  async () => {
    const database = `singularity-game-snapshot-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const game = createGame('ABC123'),
      p = addPlayer(game, 'old-a', 'A'),
      enemy = addPlayer(game, 'old-b', 'B');
    game.tick = 120;
    game.paused = true;
    p.resources = { energy: 1500, minerals: 1500, data: 900, unity: 500 };
    command(game, p.id, { type: 'research', tech: 'extraction' });
    p.research.projects[0].done = 157;
    command(game, p.id, { type: 'build', ship: 'corvette', systemId: p.home });
    p.queue[0].remaining = 1;
    command(game, p.id, { type: 'build', ship: 'corvette', systemId: p.home });
    p.queue[1].remaining = 1;
    command(game, p.id, {
      type: 'colony_build',
      slot: 0,
      systemId: p.home,
      building: 'reactor',
      sectorId: 3,
      revision: 0,
    });
    game.systems.find((s) => s.id === p.home)!.colony!.construction!.remaining = 2;
    const scout = game.fleets.find((f) => f.owner === p.id && f.type === 'scout')!,
      colony = game.fleets.find((f) => f.owner === p.id && f.type === 'colony')!;
    command(game, p.id, { type: 'move', fleetId: scout.id, systemId: 's1' });
    scout.progress = 0.75;
    scout.duration = 2;
    colony.systemId = 's1';
    const admin = await connect(database, { token: adminToken() }),
      a = await connect(database),
      b = await connect(database);
    const clients = [a, b, admin];
    try {
      const input = {
        code: game.code,
        seed: 42,
        sourceJson: JSON.stringify(game),
        creationKey: 'fixture-1',
      };
      await admin.conn.reducers.initializeGame(input);
      const ticket = await seat(admin, a, p.id);
      await seat(admin, b, enemy.id);
      await assert.rejects(b.conn.reducers.redeemGameSeat({ ticket }));
      const initial = gameView(a)!;
      assert.equal(initial.systems.length, 30);
      assert.equal(initial.tick, 120);
      assert.deepEqual(initial.me.resources, p.resources);
      assert.deepEqual(initial.me.empire, p.empire);
      assert.equal(initial.me.research.projects[0].done, 157);
      assert.equal(initial.me.queue.length, 2);
      assert.equal(initial.fleets.find((f) => f.id === scout.id)!.progress, 0.75);
      assert.equal(initial.systems.find((s) => s.id === p.home)!.colony!.construction!.remaining, 2);
      assert(!gameView(b)!.fleets.some((f) => f.owner === p.id), 'foreign fleets remain hidden');
      assert(
        !gameView(b)!.systems.find((s) => s.id === p.home)!.colony,
        'foreign colony details remain private',
      );
      await assert.rejects(issue(b, { type: 'move', fleetId: scout.id, systemId: 's2' }));
      await admin.conn.reducers.initializeGame(input);
      assert.deepEqual(
        gameView(a)!.me.resources,
        p.resources,
        'import retry never reapplies starting bonuses',
      );
      await assert.rejects(admin.conn.reducers.initializeGame({ ...input, creationKey: 'different' }));
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(
        () => gameView(a)!.fleets.some((f) => f.id === scout.id && !f.route.length),
        'imported route finishes',
      );
      await issue(a, { type: 'scan', fleetId: scout.id });
      await until(() => gameView(a)!.me.surveyed.includes('s1'), 'survey finishes', 90000);
      await issue(a, { type: 'starbase_build', systemId: 's1' });
      await until(
        () => gameView(a)!.systems.find((s) => s.id === 's1')!.owner === p.id,
        'outpost claims system',
      );
      await issue(a, { type: 'colonize', fleetId: colony.id });
      await until(() => !!gameView(a)!.systems.find((s) => s.id === 's1')!.colony, 'colony finishes');
      assert(!gameView(a)!.fleets.some((f) => f.id === colony.id), 'colony ship consumed exactly once');
      assert(gameView(a)!.me.techs.includes('extraction'));
      assert.equal(
        gameView(a)!.systems.find((s) => s.id === p.home)!.colony!.sectors[3].districts[0].building,
        'reactor',
      );
      assert(gameView(a)!.me.resources.energy > p.resources.energy - 180, 'economy keeps producing');
      const fleet = gameView(a)!.fleets.find((f) => f.type === 'corvette')!;
      assert.equal(fleet.shipCount, 3, 'new ships reinforce existing military formation');
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const details = new BattleDetailSubscription(a);
      await details.focus(fleet.nativeId!, 0);
      assert.equal(a.conn.db.fleetShips.count(), 3n);
      const id = [...a.conn.db.fleetShips.iter()][0].id;
      await assert.rejects(a.conn.reducers.splitFleet({ fleetId: fleet.nativeId!, shipIds: [id, id] }));
      await a.conn.reducers.splitFleet({ fleetId: fleet.nativeId!, shipIds: [id] });
      const split = gameView(a)!.fleets.find((f) => f.type === 'corvette' && f.nativeId !== fleet.nativeId)!;
      assert.equal(split.shipCount, 1);
      assert.equal(gameView(a)!.fleets.find((f) => f.id === fleet.id)!.shipCount, 2);
      await assert.rejects(
        b.conn.reducers.mergeFleets({ sourceId: split.nativeId!, targetId: fleet.nativeId! }),
      );
      await a.conn.reducers.mergeFleets({ sourceId: split.nativeId!, targetId: fleet.nativeId! });
      assert.equal(gameView(a)!.fleets.find((f) => f.id === fleet.id)!.shipCount, 3);
      await details.focus(0, 0);
      assert.equal(a.conn.db.fleetShips.count(), 0n);
      details.dispose();
      // Settle the last earned production cycle before measuring the exact reform debit.
      await issue(a, {
        type: 'colony_focus',
        systemId: p.home,
        focus: 'balanced',
        revision: gameView(a)!.systems.find((s) => s.id === p.home)!.colony!.revision,
      });
      const beforeReform = gameView(a)!.me,
        founding = JSON.stringify(beforeReform.empire!.founding);
      const government = {
        ...beforeReform.empire!.design.government,
        civics: ['conservation', 'architects'],
      };
      await issue(a, { type: 'empire_reform', government, revision: beforeReform.empire!.revision });
      assert.equal(gameView(a)!.me.resources.unity, beforeReform.resources.unity - 150);
      await assert.rejects(
        issue(a, { type: 'empire_reform', government, revision: beforeReform.empire!.revision }),
      );
      const sourceSpecies = gameView(a)!.me.empire!.species[0],
        pops = gameView(a)!.systems.find((s) => s.id === 's1')!.colony!.population;
      await issue(a, {
        type: 'species_modify',
        sourceId: sourceSpecies.id,
        design: {
          ...sourceSpecies,
          name: 'Ocean settlers',
          environment: 'ocean',
          traits: ['industrious', 'intelligent'],
        },
        colonyIds: ['s1'],
        revision: gameView(a)!.me.empire!.revision,
      });
      const variant = gameView(a)!.me.empire!.species.at(-1)!;
      assert.equal(variant.parentId, sourceSpecies.id);
      assert.equal(
        gameView(a)!.systems.find((s) => s.id === 's1')!.colony!.populations![0].speciesId,
        variant.id,
      );
      assert.equal(gameView(a)!.systems.find((s) => s.id === 's1')!.colony!.population, pops);
      assert.equal(JSON.stringify(gameView(a)!.me.empire!.founding), founding);
      const saved = gameView(a)!.me;
      a.conn.disconnect();
      await until(() => gameView(b)!.hostId === enemy.id, 'host transfers on disconnect');
      const resumed = await connect(database, { token: a.token });
      clients.push(resumed);
      await subscribe(resumed.conn, GAME_QUERIES);
      assert.equal(resumed.identity, a.identity);
      assert.deepEqual(gameView(resumed)!.me, saved);
      assert.equal(resumed.conn.db.fleetShips.count(), 0n);
      await issue(b, { type: 'pause' });
      b.conn.disconnect();
      resumed.conn.disconnect();
      const monitor = await subscribe(admin.conn, ['SELECT * FROM clock', 'SELECT * FROM game_settings']);
      await until(() => [...admin.conn.db.clock.iter()][0].paused, 'empty galaxy auto-pauses');
      const time = [...admin.conn.db.clock.iter()][0].gameTime;
      await delay(250);
      assert.equal([...admin.conn.db.clock.iter()][0].gameTime, time);
      const final = await connect(database, { token: a.token });
      clients.push(final);
      await subscribe(final.conn, GAME_QUERIES);
      assert.equal(gameView(final)!.paused, false, 'auto-pause resumes when player returns');
      assert.equal(gameView(final)!.hostId, p.id);
      monitor.unsubscribe();
    } finally {
      await admin.conn.reducers.setClock({ paused: true, speed: 1 });
      clients.forEach((c) => c.conn.disconnect());
    }
  },
);

test(
  'native AI progresses its economy and civilian missions independently',
  { timeout: 120000 },
  async () => {
    const database = `singularity-game-ai-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const game = createGame('A1B2C3'),
      p = addPlayer(game, 'ai-test', 'Planner');
    game.paused = true;
    p.ai = { startedAt: 0, nextDecision: 0 } as typeof p.ai;
    p.resources = { energy: 2000, minerals: 2000, data: 1000 };
    // Monthly research, accelerated for a bounded integration run.
    p.empire.economyModifiers = [
      { id: 'test-compute', name: 'Test Compute', category: 'compute', factor: 30 },
    ];
    const admin = await connect(database, { token: adminToken() }),
      a = await connect(database);
    try {
      await admin.conn.reducers.initializeGame({
        code: game.code,
        seed: 42,
        sourceJson: JSON.stringify(game),
        creationKey: 'ai',
      });
      await seat(admin, a, p.id);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(
        () =>
          gameView(a)!.players[0].colonies >= 2 &&
          gameView(a)!.me.techs.length > 0 &&
          gameView(a)!.fleets.some((f) => f.type === 'corvette' && f.shipCount! > 1),
        'AI researches, reinforces and colonizes',
        90000,
      );
    } finally {
      await admin.conn.reducers.setClock({ paused: true, speed: 1 });
      a.conn.disconnect();
      admin.conn.disconnect();
    }
  },
);

test(
  'completed games remain viewable but cannot be resumed or acquire new players',
  { timeout: 10000 },
  async () => {
    const database = `singularity-game-finished-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const game = createGame('AA11BB'),
      p = addPlayer(game, 'winner', 'Winner');
    game.winner = p.id;
    game.paused = true;
    const admin = await connect(database, { token: adminToken() }),
      a = await connect(database);
    try {
      await admin.conn.reducers.initializeGame({
        code: game.code,
        seed: 42,
        sourceJson: JSON.stringify(game),
        creationKey: 'complete',
      });
      await seat(admin, a, p.id);
      assert.equal(gameView(a)!.winner, p.id);
      await assert.rejects(admin.conn.reducers.setClock({ paused: false, speed: 1 }));
      await assert.rejects(issue(a, { type: 'pause' }));
      await assert.rejects(
        admin.conn.reducers.reserveGameSeat({
          ticket: randomBytes(32).toString('hex'),
          externalId: 'new-player',
          templateJson: '',
        }),
      );
    } finally {
      a.conn.disconnect();
      admin.conn.disconnect();
    }
  },
);

test(
  'normal-game combat has private overview, explicit tactics, hot-join state and atomic withdrawal',
  { timeout: 25000 },
  async () => {
    const database = `singularity-game-combat-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const game = createGame('ABCCBA');
    game.paused = true;
    for (const id of ['a', 'b', 'c']) addPlayer(game, id, id);
    const fighting = game.fleets.filter((f) => f.type === 'corvette' && f.owner !== 'c');
    fighting.forEach((f) => (f.systemId = 's1'));
    game.systems.find((s) => s.id === 's1')!.defense = 0;
    const admin = await connect(database, { token: adminToken() }),
      a = await connect(database),
      b = await connect(database),
      c = await connect(database);
    const clients = [admin, a, b, c];
    try {
      await admin.conn.reducers.initializeGame({
        code: game.code,
        seed: 42,
        sourceJson: JSON.stringify(game),
        creationKey: 'combat',
      });
      for (const [client, id] of [
        [a, 'a'],
        [b, 'b'],
        [c, 'c'],
      ] as const)
        await seat(admin, client, id);
      await issue(a, { type: 'declare_war', empireId: 'b' });
      await admin.conn.reducers.setClock({ paused: false, speed: 2 });
      await until(() => a.conn.db.visibleBattleSummaries.count() === 1n, 'automatic battle starts');
      const battle = [...a.conn.db.visibleBattleSummaries.iter()][0],
        fleet = gameView(a)!.fleets.find((f) => f.id === fighting[0].id)!;
      assert.equal(a.conn.db.battleMotion.count(), 0n);
      assert.equal(c.conn.db.visibleBattleSummaries.count(), 0n);
      assert(
        ![...c.conn.db.myGameEvents.iter()].some((e) => e.text.startsWith('Gefecht')),
        'foreign fight events remain private',
      );
      await assert.rejects(c.conn.reducers.setFocus({ battleId: battle.id, fleetId: 0 }));
      const scope = new BattleDetailSubscription(a);
      await scope.focus(fleet.nativeId!, battle.id);
      assert.equal(a.conn.db.battleRoster.count(), 2n);
      await until(
        () => [...a.conn.db.visibleBattleSummaries.iter()][0].attacker.damageDealt > 0,
        'effective damage reaches overview',
      );
      await admin.conn.reducers.setClock({ paused: true, speed: 2 });
      const motion = [...a.conn.db.battleMotion.iter()].sort((a, b) => a.shipId - b.shipId);
      const restored = await connect(database, { token: a.token });
      clients.push(restored);
      await subscribe(restored.conn, GAME_QUERIES);
      assert.equal(
        restored.conn.db.battleMotion.count(),
        0n,
        'joining galaxy does not load a saved focus implicitly',
      );
      const restoredScope = new BattleDetailSubscription(restored);
      await restoredScope.focus(fleet.nativeId!, battle.id);
      assert.deepEqual(
        [...restored.conn.db.battleMotion.iter()].sort((a, b) => a.shipId - b.shipId),
        motion,
      );
      await a.conn.reducers.withdrawFleet({ fleetId: fleet.nativeId! });
      const final = [...a.conn.db.visibleBattleSummaries.iter()][0];
      assert.equal(final.state, 'finished');
      assert(final.attacker.damageDealt > 0);
      assert.equal(gameView(a)!.fleets.find((f) => f.id === fleet.id)!.battleId, 0);
      await issue(a, { type: 'move', fleetId: fleet.id, systemId: gameView(a)!.me.home });
      assert(gameView(a)!.fleets.find((f) => f.id === fleet.id)!.route.length > 0);
      await scope.focus(0, 0);
      await restoredScope.focus(0, 0);
      assert.equal(a.conn.db.battleMotion.count(), 0n);
      assert.equal(a.conn.db.fleetShips.count(), 0n);
      scope.dispose();
      restoredScope.dispose();
    } finally {
      await admin.conn.reducers.setClock({ paused: true, speed: 1 });
      clients.forEach((c) => c.conn.disconnect());
    }
  },
);
