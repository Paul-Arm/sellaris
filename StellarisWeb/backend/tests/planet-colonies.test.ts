import { planetIncome } from './economy-helpers';
import { resourceAmounts } from '../../shared/resources';
import { ECONOMY_MONTH_DAYS, monthsDue } from '../../shared/economy';
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { cli } from '../tool.mjs';
import { adminToken } from '../admin';
import { connect, subscribe, type Client } from '../client';
import { GAME_QUERIES, gameView } from '../game-client';
import { SystemSubscription } from '../system-subscription';
import { addPlayer, createGame, income, type GameCommand } from '../../shared/game';
import { objectBodies } from '../../shared/systemObjects';
import { colonizableBody, ownedColonyWorlds, planetWorld } from '../../shared/planetColonies';
import { baseIncome, colonyProduction, districtSpec, occupiedDistricts } from '../../shared/colonies';
import { ENVIRONMENTS } from '../../shared/empireCatalog';

async function until(check: () => boolean, timeout = 60000) {
  const end = Date.now() + timeout;
  while (!check()) {
    assert(Date.now() < end, 'planet colony timeout');
    await delay(60);
  }
}
test(
  'planet colonies require approach, keep separate populations/jobs, produce, reconnect and terraform',
  { timeout: 180000 },
  async () => {
    const database = `singularity-game-planets-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const source = createGame('C010A1'),
      p = addPlayer(source, 'a', 'Planet Builder'),
      other = addPlayer(source, 'b', 'Observer');
    p.resources = { energy: 9000, minerals: 9000, data: 9000 };
    p.techs = ['terraforming', 'extraction'];
    source.paused = true;
    const invader = source.fleets.find((f) => f.owner === other.id && f.type === 'corvette')!;
    for (let i = 0; i < 12; i++)
      source.fleets.push({ ...structuredClone(invader), id: `invader-${i}`, systemId: p.home });
    const admin = await connect(database, { token: adminToken() }),
      clients: Client[] = [admin];
    try {
      await admin.conn.reducers.initializeGame({
        code: source.code,
        seed: 42,
        sourceJson: JSON.stringify(source),
        creationKey: 'planet-colonies',
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
        view = () => gameView(a)!,
        issue = (cmd: GameCommand) => a.conn.reducers.gameCommand({ commandJson: JSON.stringify(cmd) });
      const focus = new SystemSubscription(a);
      await focus.focus([...a.conn.db.myGamePlayer.iter()][0].homeId);
      const bodies = () => objectBodies(a.conn.db.focusedSystemObjects.iter());
      const target = bodies().find(colonizableBody)!;
      assert(target, 'home has secondary habitable planet');
      const colonyShip = view().fleets.find((f) => f.type === 'colony' && f.owner === p.id)!;
      const order: GameCommand = {
        type: 'colonize',
        fleetId: colonyShip.id,
        systemId: p.home,
        bodySlot: target.slot,
      };
      await assert.rejects(issue({ ...order, bodySlot: 0 }), /Nebenplanet/);
      await assert.rejects(issue({ ...order, systemId: other.home }), /anderen System/);
      await assert.rejects(b.conn.reducers.gameCommand({ commandJson: JSON.stringify(order) }));
      const cash = view().me.resources.minerals;
      await issue(order);
      assert.equal(view().fleets.find((f) => f.id === colonyShip.id)!.navigation!.phase, 'colony_flight');
      assert.equal(view().me.resources.minerals, cash, 'no remote charge/construction');
      assert.equal(view().planetColonies!.length, 0);
      await delay(500);
      assert.equal(view().planetColonies!.length, 0, 'pause freezes approach');
      await issue({ type: 'fleet_stop', fleetId: colonyShip.id });
      assert.equal(view().me.resources.minerals, cash, 'stopping unpaid approach gives no refund');
      await issue(order);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => !!view().fleets.find((f) => f.id === colonyShip.id)?.task);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const charged = view().me.resources.minerals;
      await issue({ type: 'fleet_stop', fleetId: colonyShip.id });
      assert.equal(view().me.resources.minerals, charged + 80);
      await issue(order);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => view().planetColonies!.length === 1);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert(!view().fleets.some((f) => f.id === colonyShip.id), 'colony ship consumed');
      const world = () => view().planetColonies![0],
        home = () => view().systems.find((s) => s.id === p.home)!;
      assert.equal(world().objectId, target.objectId);
      assert.equal(b.conn.db.myPlanetColonies.count(), 0n, 'foreign population is private');
      assert.equal(ownedColonyWorlds(view()).length, 2);
      assert.equal(world().colony.populations![0].speciesId, view().me.empire!.primarySpeciesId);
      assert.notDeepEqual(world().colony.sectors, home().colony!.sectors);
      const sector = world().colony.sectors.find((s) => s.districts.length < s.slots)!;
      const homeSector = home().colony!.sectors.find((s) => s.districts.length < s.slots)!;
      const build: GameCommand = {
        type: 'colony_build',
        slot: sector.districts.length,
        systemId: p.home,
        bodySlot: target.slot,
        revision: world().colony.revision,
        sectorId: sector.id,
        building: 'reactor',
      };
      const before = view().me.resources.minerals;
      await issue(build);
      assert.equal(view().me.resources.minerals, before - districtSpec('reactor', 1).cost.minerals);
      await assert.rejects(issue(build), /zwischenzeitlich/);
      await assert.rejects(
        b.conn.reducers.gameCommand({
          commandJson: JSON.stringify({ ...build, revision: world().colony.revision }),
        }),
      );
      await issue({
        type: 'colony_build',
        slot: homeSector.districts.length,
        systemId: p.home,
        revision: home().colony!.revision,
        sectorId: homeSector.id,
        building: 'laboratory',
      });
      assert(home().colony!.construction && world().colony.construction, 'both worlds build independently');
      await issue({
        type: 'colony_cancel',
        systemId: p.home,
        bodySlot: target.slot,
        revision: world().colony.revision,
      });
      assert(home().colony!.construction && !world().colony.construction, 'cancellation targets one world');
      await issue({ ...build, revision: world().colony.revision });
      const joined = await connect(database, { token: a.token });
      clients.push(joined);
      await subscribe(joined.conn, GAME_QUERIES);
      assert.deepEqual(
        gameView(joined)!.planetColonies,
        view().planetColonies,
        'reconnect restores populations and project',
      );
      const buildings = occupiedDistricts(world().colony),
        population = world().colony.population;
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => !world().colony.construction && !home().colony!.construction);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert.equal(occupiedDistricts(world().colony), buildings + 1);
      assert(world().colony.population >= population);
      const rate = colonyProduction(planetWorld(home(), world()), view().me);
      assert.deepEqual(planetIncome(view()), rate);
      const total = income(view(), view().me),
        mainRate = colonyProduction(home(), view().me),
        base = baseIncome(view().me);
      assert(Math.abs(total.energy - base.energy - mainRate.energy - rate.energy + 5) < 1e-6);
      const energy = view().me.resources.energy,
        producedFrom = view().tick;
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      // Both worlds participate in the next common monthly payout.
      await until(() => view().tick >= producedFrom + ECONOMY_MONTH_DAYS);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert(
        view().me.resources.energy - energy >= total.energy - 0.1,
        'server pays primary and additional colony output',
      );
      const old = structuredClone(world()),
        body = bodies().find((b) => b.objectId === target.objectId)!;
      const climate = body.environment === 'arctic' ? 'continental' : 'arctic';
      await a.conn.reducers.startTerraforming({
        objectId: body.objectId,
        revision: body.revision,
        target: climate,
      });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => world().planet === ENVIRONMENTS[climate].name);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert.equal(world().objectId, old.objectId);
      assert.deepEqual(
        world().colony.sectors,
        old.colony.sectors,
        'terraforming preserves districts and surface',
      );
      assert.equal(
        home().planet,
        source.systems.find((s) => s.id === p.home)!.planet,
        'other planet climate unchanged',
      );
      await a.conn.reducers.renameBody({
        objectId: body.objectId,
        revision: bodies().find((b) => b.objectId === body.objectId)!.revision,
        name: 'Aurora',
      });
      assert.equal(world().name, 'Aurora', 'overview follows live object name without refocus');
      // A staffed bastion on a secondary world contributes to the shared system defense.
      for (const district of world()
        .colony.sectors.flatMap((s) => s.districts)
        .filter((d) => d.building === 'reactor' || d.building === 'foundry'))
        await issue({
          type: 'colony_toggle',
          systemId: p.home,
          bodySlot: target.slot,
          districtId: district.id,
          enabled: false,
          revision: world().colony.revision,
        });
      await issue({
        ...build,
        building: 'bastion',
        sectorId: world().colony.sectors.find((s) => s.districts.length < s.slots)!.id,
        slot: world().colony.sectors.find((s) => s.districts.length < s.slots)!.districts.length,
        revision: world().colony.revision,
      });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => !world().colony.construction);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert(
        home().planetDefense! > 0 && home().defense > 30,
        'secondary bastion raises actual system defense',
      );
      const bastion = world()
        .colony.sectors.flatMap((s) => s.districts)
        .find((d) => d.building === 'bastion')!;
      await issue({
        type: 'colony_toggle',
        systemId: p.home,
        bodySlot: target.slot,
        districtId: bastion.id,
        enabled: false,
        revision: world().colony.revision,
      });
      assert.equal(home().planetDefense, 0);
      assert.equal(home().defense, 100, 'disabled bastion cannot leave extra defense behind');
      const empire = view().me.empire!,
        species = empire.species.find((s) => s.id === empire.primarySpeciesId)!;
      await issue({
        type: 'species_modify',
        sourceId: species.id,
        design: { ...species, name: 'Auroraner', environment: climate },
        colonyIds: [world().objectId],
        revision: empire.revision,
      });
      assert.notEqual(
        world().colony.populations![0].speciesId,
        species.id,
        'secondary colony receives its own species modification',
      );
      assert.equal(home().colony!.populations![0].speciesId, species.id, 'main world species unaffected');
      await issue({
        ...build,
        sectorId: world().colony.sectors.find((s) => s.districts.length < s.slots)!.id,
        slot: world().colony.sectors.find((s) => s.districts.length < s.slots)!.districts.length,
        revision: world().colony.revision,
      });
      assert(world().colony.construction);
      await b.conn.reducers.gameCommand({
        commandJson: JSON.stringify({ type: 'declare_war', empireId: p.id }),
      });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => home().owner === null);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert.equal(view().planetColonies!.length, 0, 'loss removes every planet colony in system');
      assert.deepEqual(planetIncome(view()), resourceAmounts());
      assert(
        ![...a.conn.db.myJobs.iter()].some((j) => j.kind === 'game_planet_upgrade' && j.status === 'active'),
        'lost world construction is cancelled',
      );
      await focus.focus(0);
    } finally {
      for (const c of clients) c.conn.disconnect();
      cli(['delete', database, '--server', 'http://127.0.0.1:3100', '--yes']);
    }
  },
);
