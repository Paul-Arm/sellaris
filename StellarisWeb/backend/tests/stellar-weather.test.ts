import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { cli } from '../tool.mjs';
import { adminToken } from '../admin';
import { connect, subscribe, type Client } from '../client';
import { GAME_QUERIES, gameView } from '../game-client';
import { addPlayer, createGame, type GameCommand } from '../../shared/game';
import { baseIncome } from '../../shared/colonies';
import { SystemSubscription } from '../system-subscription';
import { objectBodies } from '../../shared/systemObjects';
import { STELLAR_STORM } from '../../shared/stellarWeather';

async function until(check: () => boolean, timeout = 40000) {
  const end = Date.now() + timeout;
  while (!check()) {
    assert(Date.now() < end, 'stellar weather timeout');
    await delay(50);
  }
}

test(
  'survey reveals a durable local storm; pause, private discovery, real payouts and recovery',
  { timeout: 100000 },
  async () => {
    const database = `singularity-game-weather-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const source = createGame('57A0A1'),
      p = addPlayer(source, 'a', 'Stormwatch'),
      other = addPlayer(source, 'b', 'Observer');
    source.paused = true;
    const old = source.systems.find((s) => s.id === p.home)!,
      home = source.systems.find((s) => s.id === 's3')!;
    home.owner = p.id;
    home.colony = old.colony;
    home.colonyName = 'Stormwatch';
    home.planet = old.planet;
    home.class = 'K5 III';
    home.defense = old.defense;
    old.owner = null;
    old.colony = null;
    p.home = home.id;
    p.surveyed = [];
    p.discovered.push(home.id);
    p.resources = { energy: 5000, minerals: 5000, data: 1000 };
    for (const s of source.systems)
      for (const sector of s.colony?.sectors || [])
        for (const district of sector.districts)
          if (district.building === 'habitat') district.enabled = false;
    for (const fleet of source.fleets) {
      if (fleet.owner === p.id) fleet.systemId = home.id;
      if (fleet.type === 'scout') {
        fleet.systemId = home.id;
        fleet.task = {
          type: 'scan',
          total: fleet.owner === p.id ? 4 : 40,
          remaining: fleet.owner === p.id ? 4 : 40,
        };
      }
    }
    const admin = await connect(database, { token: adminToken() }),
      clients: Client[] = [admin];
    try {
      await admin.conn.reducers.initializeGame({
        code: source.code,
        seed: 42,
        sourceJson: JSON.stringify(source),
        migrationKey: 'weather',
      });
      for (const id of [p.id, other.id]) {
        const c = await connect(database);
        clients.push(c);
        const ticket = randomBytes(32).toString('hex');
        await admin.conn.reducers.reserveGameSeat({ ticket, externalId: id, templateJson: '' });
        await c.conn.reducers.redeemGameSeat({ ticket });
        await subscribe(c.conn, GAME_QUERIES);
      }
      const a = clients[1],
        b = clients[2],
        view = () => gameView(a)!;
      const issue = (cmd: GameCommand) => a.conn.reducers.gameCommand({ commandJson: JSON.stringify(cmd) });
      const weather = () => view().systems.find((s) => s.id === home.id)!.stellarWeather;
      const detail = new SystemSubscription(a);
      await detail.focus([...a.conn.db.myGamePlayer.iter()][0].homeId);
      const originalBodies = objectBodies(a.conn.db.focusedSystemObjects.iter());
      assert(!weather());
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => !!weather());
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const forecast = { ...weather()! };
      assert.equal(forecast.phase, 'warning');
      assert.equal(forecast.startsAt - forecast.discoveredAt, STELLAR_STORM.warningDays);
      assert.equal(
        b.conn.db.visibleStellarWeather.count(),
        0n,
        'unsurveyed observer does not receive forecast',
      );
      assert(view().log.some((l) => l.text.includes('Sternensturm vorhergesagt')));
      const anon = await connect(database);
      clients.push(anon);
      await subscribe(anon.conn, ['SELECT * FROM visible_stellar_weather']);
      assert.equal(anon.conn.db.visibleStellarWeather.count(), 0n);
      const rejoined = await connect(database, { token: a.token });
      clients.push(rejoined);
      await subscribe(rejoined.conn, GAME_QUERIES);
      assert.deepEqual(gameView(rejoined)!.systems.find((s) => s.id === home.id)!.stellarWeather, forecast);
      await delay(500);
      assert.deepEqual(weather(), forecast);
      await issue({ type: 'site_build', systemId: home.id, bodySlot: 0, facility: 'solar' });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => view().sites!.some((s) => s.facility === 'solar' && s.level === 1));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert.equal(view().me.installationIncome!.energy, 5);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => b.conn.db.visibleStellarWeather.count() === 1n);
      assert.equal(
        [...b.conn.db.visibleStellarWeather.iter()][0].startsAt,
        forecast.startsAt,
        'second survey does not restart cycle',
      );
      await until(() => weather()!.phase === 'active');
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert.equal(view().me.installationIncome!.energy, 1.25);
      const flush = () =>
        issue({
          type: 'colony_focus',
          systemId: home.id,
          focus: 'balanced',
          revision: view().systems.find((s) => s.id === home.id)!.colony!.revision,
        });
      await flush();
      const start = view(),
        before = start.me.resources.energy,
        anchors = [...a.conn.db.myColonies.iter()];
      const siteStart = start.sites!.find((s) => s.facility === 'solar')!.finishAt;
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => view().tick >= start.tick + 8);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      await flush();
      const end = view(),
        updated = [...a.conn.db.myColonies.iter()];
      const expected =
        before +
        baseIncome(end.me).energy * (Math.floor(end.tick / 4) - Math.floor(start.tick / 4)) +
        anchors.reduce(
          (n, c) =>
            n + c.energyRate * ((updated.find((u) => u.id === c.id)!.lastProducedAt - c.lastProducedAt) / 4),
          0,
        ) +
        1.25 * (Math.floor((end.tick - siteStart) / 4) - Math.floor((start.tick - siteStart) / 4));
      assert(
        Math.abs(end.me.resources.energy - expected) < 1e-6,
        `real reduced solar payout: ${end.me.resources.energy} versus ${expected}`,
      );
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => weather()!.phase === 'resolved');
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert.equal(view().me.installationIncome!.energy, 5);
      assert.equal(weather()!.endsAt, forecast.endsAt);
      assert.equal(view().log.filter((l) => l.text.includes('Sternensturm abgeklungen')).length, 1);
      assert.deepEqual(
        objectBodies(a.conn.db.focusedSystemObjects.iter()),
        originalBodies,
        'natural storm preserves bodies and identities',
      );
      assert.deepEqual(
        view().systems.find((s) => s.id === home.id)!.stellarWeather,
        gameView(rejoined)!.systems.find((s) => s.id === home.id)!.stellarWeather,
      );
      await detail.focus(0);
    } finally {
      clients.forEach((c) => c.conn.disconnect());
      cli(['delete', database, '--server', 'http://127.0.0.1:3100', '--yes']);
    }
  },
);
