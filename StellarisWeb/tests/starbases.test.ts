import test from 'node:test';
import assert from 'node:assert/strict';
import { addPlayer, command, createGame, tickGame, viewFor, type GameCommand } from '../shared/game';
import { completeStarbase, hasShipyard, starbaseDefense, starbaseLedger } from '../shared/starbases';
import { economyTotals } from '../shared/economy';

function fixture() {
  const game = createGame('BA5E01'),
    p = addPlayer(game, 'a', 'Builder'),
    other = addPlayer(game, 'b', 'Rival');
  p.resources = { energy: 10000, minerals: 10000, data: 0 };
  const s = game.systems.find((s) => !s.owner && s.kind === 'star' && !s.defense)!;
  const issue = (c: GameCommand) => command(game, p.id, c);
  const finish = () => {
    game.tick = s.starbase!.project!.finishAt;
    completeStarbase(s, game.tick);
  };
  return { game, p, other, s, issue, finish };
}
test('outposts require a complete survey, reserve once, claim on completion and do not found colonies', () => {
  const { game, p, other, s, issue, finish } = fixture();
  const before = JSON.stringify(game);
  assert.throws(() => issue({ type: 'starbase_build', systemId: s.id }));
  assert.equal(JSON.stringify(game), before);
  p.surveyed.push(s.id);
  other.surveyed.push(s.id);
  issue({ type: 'starbase_build', systemId: s.id });
  assert.equal(s.owner, null);
  assert.equal(s.starbase!.level, 0);
  assert.equal(p.resources.minerals, 9850);
  const reserved = JSON.stringify(game);
  assert.throws(() => command(game, other.id, { type: 'starbase_build', systemId: s.id }));
  assert.equal(JSON.stringify(game), reserved);
  assert.equal(viewFor(game, other.id).systems.find((x) => x.id === s.id)!.starbase, null);
  game.paused = true;
  tickGame(game, 60);
  assert.equal(s.owner, null);
  finish();
  assert.equal(s.owner, p.id);
  assert.equal(s.colony ?? null, null);
  assert.equal(s.defense, 40);
  assert.equal(economyTotals(starbaseLedger(s)).energy, -1);
});
test('cancellation releases unbuilt territory, refunds once and checks revisions and owner', () => {
  const { game, p, other, s, issue } = fixture();
  p.surveyed.push(s.id);
  issue({ type: 'starbase_build', systemId: s.id });
  const revision = s.starbase!.revision;
  assert.throws(() => issue({ type: 'starbase_cancel', systemId: s.id, revision: revision - 1 }));
  assert.throws(() => command(game, other.id, { type: 'starbase_cancel', systemId: s.id, revision }));
  issue({ type: 'starbase_cancel', systemId: s.id, revision });
  assert.equal(s.starbase, null);
  assert.equal(s.owner, null);
  assert.equal(p.resources.minerals, 9925);
  issue({ type: 'starbase_build', systemId: s.id });
  assert(s.starbase!.revision > revision);
  assert.throws(() => issue({ type: 'starbase_cancel', systemId: s.id, revision }));
});
test('tiers unlock slots, modules have real costs and effects, shipbuilding requires a finished shipyard', () => {
  const { p, s, issue, finish } = fixture();
  p.surveyed.push(s.id);
  issue({ type: 'starbase_build', systemId: s.id });
  finish();
  const module = (slot: number, module: 'shipyard' | 'battery' | 'trade') =>
    issue({ type: 'starbase_module', systemId: s.id, revision: s.starbase!.revision, slot, module });
  assert.throws(() => module(0, 'shipyard'));
  assert.throws(() => issue({ type: 'build', systemId: s.id, ship: 'scout' }));
  issue({ type: 'starbase_upgrade', systemId: s.id, revision: s.starbase!.revision });
  finish();
  module(0, 'shipyard');
  assert(!hasShipyard(s));
  finish();
  assert(hasShipyard(s));
  issue({ type: 'build', systemId: s.id, ship: 'scout' });
  assert.throws(() =>
    issue({ type: 'starbase_remove', systemId: s.id, slot: 0, revision: s.starbase!.revision }),
  );
  module(1, 'battery');
  finish();
  assert.equal(starbaseDefense(s.starbase), 180);
  module(1, 'battery');
  finish();
  assert.equal(starbaseDefense(s.starbase), 260);
  module(1, 'battery');
  finish();
  assert.equal(starbaseDefense(s.starbase), 340);
  assert.throws(() => module(1, 'battery'));
  assert.throws(() => module(2, 'trade'));
  issue({ type: 'starbase_remove', systemId: s.id, slot: 1, revision: s.starbase!.revision });
  assert.equal(s.defense, 100);
  module(1, 'trade');
  finish();
  assert.equal(economyTotals(starbaseLedger(s)).energy, 1);
});
test('forged slots, prototype modules and insufficient funds are atomic; upgrades cancel without losing modules', () => {
  const { game, p, s, issue, finish } = fixture();
  p.surveyed.push(s.id);
  issue({ type: 'starbase_build', systemId: s.id });
  finish();
  issue({ type: 'starbase_upgrade', systemId: s.id, revision: s.starbase!.revision });
  finish();
  for (const [slot, module] of [
    [-1, 'trade'],
    [NaN, 'trade'],
    [0, '__proto__'],
    [5, 'trade'],
  ] as const) {
    const before = JSON.stringify(game);
    assert.throws(() =>
      issue({
        type: 'starbase_module',
        systemId: s.id,
        revision: s.starbase!.revision,
        slot,
        module,
      } as GameCommand),
    );
    assert.equal(JSON.stringify(game), before);
  }
  p.resources.energy = 0;
  const before = JSON.stringify(game);
  assert.throws(() => issue({ type: 'starbase_upgrade', systemId: s.id, revision: s.starbase!.revision }));
  assert.equal(JSON.stringify(game), before);
  p.resources.energy = 1000;
  issue({ type: 'starbase_upgrade', systemId: s.id, revision: s.starbase!.revision });
  issue({ type: 'starbase_cancel', systemId: s.id, revision: s.starbase!.revision });
  assert.equal(s.starbase!.level, 2);
  assert.equal(s.owner, p.id);
});
test('all system kinds can be claimed; destroyed territory loses its base and pending upgrade', () => {
  const { game, p, other, issue } = fixture();
  for (const s of game.systems.filter((s) => s.kind !== 'star')) {
    s.defense = 0;
    p.surveyed.push(s.id);
    issue({ type: 'starbase_build', systemId: s.id });
    completeStarbase(s, s.starbase!.project!.finishAt);
    assert.equal(s.owner, p.id);
  }
  const home = game.systems.find((s) => s.id === p.home)!;
  issue({ type: 'starbase_upgrade', systemId: home.id, revision: home.starbase!.revision });
  home.defense = 1;
  game.fleets = game.fleets.filter((f) => f.owner === other.id);
  game.fleets.find((f) => f.type === 'corvette')!.systemId = home.id;
  tickGame(game, 1);
  assert.equal(home.owner, null);
  assert.equal(home.starbase, null);
});

test('module slots can be filled out of order, persist through JSON and never shift on removal', () => {
  const { p, s, issue, finish } = fixture();
  p.surveyed.push(s.id);
  issue({ type: 'starbase_build', systemId: s.id });
  finish();
  for (let i = 0; i < 3; i++) {
    issue({ type: 'starbase_upgrade', systemId: s.id, revision: s.starbase!.revision });
    finish();
  }
  const build = (slot: number, module: 'trade' | 'battery') =>
    issue({ type: 'starbase_module', systemId: s.id, revision: s.starbase!.revision, slot, module });
  build(5, 'trade');
  finish();
  build(2, 'battery');
  finish();
  s.starbase = JSON.parse(JSON.stringify(s.starbase));
  assert.equal(s.starbase!.modules.find((m) => m.slot === 5)!.type, 'trade');
  issue({ type: 'starbase_remove', systemId: s.id, revision: s.starbase!.revision, slot: 2 });
  assert.deepEqual(
    s.starbase!.modules.map((m) => m.slot),
    [5],
  );
  build(2, 'trade');
  issue({ type: 'starbase_cancel', systemId: s.id, revision: s.starbase!.revision });
  assert.deepEqual(
    s.starbase!.modules.map((m) => m.slot),
    [5],
  );
  build(2, 'battery');
  finish();
  assert.equal(s.starbase!.modules.find((m) => m.slot === 2)!.type, 'battery');
  assert.throws(() => build(5, 'battery'));
});
