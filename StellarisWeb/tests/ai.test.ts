import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addPlayer, command, createGame, income, tickGame, viewFor, type GameState } from '../shared/game.ts';
function setup() {
  const game = createGame('A10101');
  addPlayer(game, 'p1', 'Human');
  return game;
}
function advance(game: GameState, seconds: number) {
  for (let i = 0; i < seconds * 4; i++) tickGame(game, 0.25);
}

test('only hosts can add AI, and AI uses a real reserved player slot', () => {
  const game = setup();
  addPlayer(game, 'p2', 'Guest');
  assert.throws(() => command(game, 'p2', { type: 'add_ai' }), /Host/);
  command(game, 'p1', { type: 'add_ai' });
  command(game, 'p1', { type: 'add_ai' });
  assert.equal(game.players.length, 4);
  assert.throws(() => command(game, 'p1', { type: 'add_ai' }), /voll/);
  const bots = game.players.filter((p) => p.ai);
  assert.ok(bots.every((p) => !p.online && p.resources.energy === 420));
  assert.equal(viewFor(game, 'p1').players.filter((p) => p.ai).length, 2);
  assert.equal(game.hostId, 'p1');
});
test('AI has no resource stipend and cannot progress a paused simulation', () => {
  const game = setup();
  command(game, 'p1', { type: 'add_ai' });
  const bot = game.players.find((p) => p.ai)!;
  bot.resources = { energy: 0, minerals: 0, data: 0 };
  // Hold population steady so this isolates AI stipends from legitimate job growth.
  const home = game.systems.find((s) => s.id === bot.home)!;
  home.colony!.sectors[0].districts.find((d) => d.building === 'habitat')!.enabled = false;
  const rate = income(game, bot);
  advance(game, 6);
  for (const r of ['energy', 'minerals'] as const)
    assert.ok(Math.abs(bot.resources[r] - rate[r] * 1.5) < 1e-8);
  assert.ok(Math.abs(bot.resources.data - (rate.data * 1.5 + 6)) < 1e-8, 'idle base Compute produces one data per day');
  const frozen = JSON.stringify(game);
  command(game, 'p1', { type: 'pause' });
  const afterPause = JSON.stringify(game);
  advance(game, 30);
  assert.equal(JSON.stringify(game), afterPause);
  assert.notEqual(frozen, afterPause);
});
test('AI autonomously explores, colonizes, builds and researches through ordinary commands', () => {
  const game = setup();
  command(game, 'p1', { type: 'add_ai' });
  const bot = game.players.find((p) => p.ai)!;
  advance(game, 240);
  assert.ok(bot.surveyed.length >= 3, `Surveyed ${bot.surveyed.length}`);
  assert.ok(
    game.systems.filter((s) => s.owner === bot.id).length >= 3,
    `Colonies ${game.systems.filter((s) => s.owner === bot.id).length}`,
  );
  assert.ok(bot.techs.length >= 2);
  assert.ok(game.fleets.filter((f) => f.owner === bot.id && f.type === 'corvette').length >= 2);
  assert.ok(Object.values(bot.resources).every((v) => Number.isFinite(v) && v >= 0));
});
