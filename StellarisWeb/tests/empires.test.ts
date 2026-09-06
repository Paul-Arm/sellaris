import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { EmpireLibraryStore } from '../server/empireLibrary';
import { EMPIRE_KINDS, ORIGINS } from '../shared/empireCatalog';
import {
  governmentFor,
  mutateLibrary,
  newEmpire,
  newSpecies,
  parseEmpireTemplate,
  parseGovernment,
  parseSpeciesTemplate,
  snapshotTemplate,
  starterLibrary,
  validateEmpireLibrary,
  type SpeciesDesign,
} from '../shared/empires';
import {
  addPlayer,
  command,
  createGame,
  hydrateEmpires,
  income,
  tickGame,
  viewFor,
  type GameCommand,
} from '../shared/game';
import { colonyProduction, createColony, assertColonies } from '../shared/colonies';

function setup() {
  const library = starterLibrary();
  const snapshot = snapshotTemplate(library, 'empire-union');
  const game = createGame('EMPIRE');
  const player = addPlayer(game, 'owner', '', snapshot);
  assertColonies(game);
  return { library, snapshot, game, player, home: game.systems.find((s) => s.id === player.home)! };
}
test('all starter templates and all four empire kinds satisfy the shared rules', () => {
  const library = validateEmpireLibrary(starterLibrary());
  assert.equal(library.empires.length, 3);
  for (const kind of Object.keys(EMPIRE_KINDS) as (keyof typeof EMPIRE_KINDS)[]) {
    const species = newSpecies('test', kind === 'machine' ? 'machine' : 'biological');
    assert.equal(parseEmpireTemplate(newEmpire('test', species.id, kind), [species]).government.kind, kind);
  }
});
test('ethic budgets, opposites, authority constraints and civic prerequisites are enforced', () => {
  const government = governmentFor('regular');
  assert.throws(() => parseGovernment({ ...government, ethics: [] }), /3 Ethikpunkte/);
  assert.throws(
    () =>
      parseGovernment({
        ...government,
        ethics: [
          { id: 'militarist', strength: 2 },
          { id: 'pacifist', strength: 1 },
        ],
      }),
    /Gegensätzliche/,
  );
  assert.throws(
    () =>
      parseGovernment({
        ...government,
        ethics: [
          { id: 'authoritarian', strength: 2 },
          { id: 'materialist', strength: 1 },
        ],
      }),
    /Demokratie/,
  );
  assert.throws(() => parseGovernment({ ...government, civics: ['warrior', 'architects'] }), /benötigt/);
  assert.throws(() => parseGovernment({ ...government, civics: ['architects', 'architects'] }), /doppelte/);
  assert.throws(() => parseGovernment({ ...government, authority: 'constructor' }), /unbekannter/);
  assert.throws(
    () => parseGovernment({ ...government, ethics: [{ id: '__proto__', strength: 3 }] }),
    /unbekannter/,
  );
  assert.throws(
    () => parseGovernment({ ...governmentFor('machine'), ethics: [{ id: 'materialist', strength: 1 }] }),
    /Kollektive/,
  );
});
test('species traits use costs, exclusivity, lifeform restrictions and canonical input fields', () => {
  const species = newSpecies('test');
  assert.throws(() => parseSpeciesTemplate({ ...species, traits: ['intelligent', 'industrious'] }), /budget/);
  assert.throws(() => parseSpeciesTemplate({ ...species, traits: ['strong', 'weak'] }), /widerspricht/);
  assert.throws(() => parseSpeciesTemplate({ ...species, traits: ['assembly'] }), /Lebensform/);
  assert.throws(() => parseSpeciesTemplate({ ...species, traits: ['constructor'] }), /unbekannter/);
  assert.throws(() => parseSpeciesTemplate({ ...species, traits: ['swift', 'swift'] }), /doppelte/);
  assert.throws(() => parseSpeciesTemplate({ ...species, name: ' ', lore: 1 }), /Speziesname/);
  assert.throws(() => parseSpeciesTemplate({ ...species, version: 999 }), /version/);
  const clean = parseSpeciesTemplate({
    ...species,
    traits: ['intelligent', 'curious', 'weak'],
    effects: { science: 9999 },
    owner: 'victim',
  });
  assert.equal('effects' in clean, false);
  assert.equal('owner' in clean, false);
  assert.equal(clean.traits.length, 3);
});
test('species and origin compatibility are validated; malformed references cannot start a game', () => {
  const library = starterLibrary();
  const empire = library.empires[0];
  assert.throws(
    () => parseEmpireTemplate({ ...empire, speciesTemplateId: 'species-axiom' }, library.species),
    /Maschinen/,
  );
  assert.throws(
    () => parseEmpireTemplate({ ...empire, origin: 'first_consensus' }, library.species),
    /Ursprung/,
  );
  assert.throws(
    () => parseEmpireTemplate({ ...empire, speciesTemplateId: 'missing' }, library.species),
    /fehlt/,
  );
  assert.throws(
    () => parseEmpireTemplate({ ...empire, color: 'red; display:none' }, library.species),
    /Reichsfarbe/,
  );
});
test('library mutations reject stale edits, references and invalid species changes atomically', () => {
  const initial = starterLibrary();
  const before = JSON.stringify(initial);
  const next = mutateLibrary(initial, {
    type: 'save_empire',
    template: { ...initial.empires[0], name: 'Neue Union' },
  });
  assert.equal(initial.empires[0].name, 'Terranische Union');
  assert.equal(next.empires[0].revision, 2);
  assert.throws(
    () => mutateLibrary(next, { type: 'save_empire', template: initial.empires[0] }),
    /zwischenzeitlich/,
  );
  assert.throws(
    () => mutateLibrary(initial, { type: 'delete_species', id: 'species-human', revision: 1 }),
    /verwendet/,
  );
  assert.throws(
    () =>
      mutateLibrary(initial, { type: 'save_species', template: { ...initial.species[0], kind: 'machine' } }),
    /Maschinen/,
  );
  assert.equal(JSON.stringify(initial), before);
  const withoutEmpire = mutateLibrary(initial, { type: 'delete_empire', id: 'empire-union', revision: 1 });
  const withoutSpecies = mutateLibrary(withoutEmpire, {
    type: 'delete_species',
    id: 'species-human',
    revision: 1,
  });
  assert.equal(withoutSpecies.species.length, 2);
});
test('two matches receive independent deep snapshots; editing and deleting templates has no retroactive effect', () => {
  const { library, game, player } = setup();
  const otherGame = createGame('OTHER');
  const other = addPlayer(otherGame, 'other', '', snapshotTemplate(library, 'empire-union'));
  player.empire!.design.lore = 'Only in this match';
  player.empire!.species[0].traits.push('curious');
  assert.equal(other.empire!.design.lore, '');
  assert.equal(other.empire!.species[0].traits.includes('curious'), false);
  const changed = mutateLibrary(library, {
    type: 'save_empire',
    template: { ...library.empires[0], name: 'Renamed' },
  });
  mutateLibrary(changed, { type: 'delete_empire', id: 'empire-union', revision: 2 });
  assert.equal(player.name, 'Terranische Union');
  assert.equal(player.empire!.founding.empire.name, 'Terranische Union');
  assert.equal(game.players.length, 1);
});
test('every origin awards start resources and populations exactly once, including save hydration', () => {
  for (const [id, origin] of Object.entries(ORIGINS)) {
    const kind = origin.kinds?.[0] || 'regular';
    const species = newSpecies('species', kind === 'machine' ? 'machine' : 'biological');
    const empire = { ...newEmpire('empire', species.id, kind), origin: id };
    const snapshot = { empire: parseEmpireTemplate(empire, [species]), species };
    const game = createGame('ORIGIN');
    const player = addPlayer(game, 'owner', '', snapshot);
    assert.equal(player.resources.energy, 420 + origin.resources.energy);
    assert.equal(player.resources.minerals, 360 + origin.resources.minerals);
    assert.equal(player.resources.science, 130 + origin.resources.science);
    assert.equal(game.systems[0].colony!.population, 6 + origin.population);
    const stored = JSON.stringify(game);
    hydrateEmpires(game);
    hydrateEmpires(game);
    assert.equal(JSON.stringify(game), stored);
  }
});
test('bonuses affect actual production, movement, research, construction and population growth', () => {
  const { game, player, home } = setup();
  const oldGame = createGame('LEGACY');
  const old = addPlayer(oldGame, 'legacy', 'Legacy');
  assert.ok(income(game, player).science > income(oldGame, old).science);
  const scout = game.fleets.find((f) => f.type === 'scout')!;
  const oldScout = oldGame.fleets.find((f) => f.type === 'scout')!;
  command(game, player.id, { type: 'move', fleetId: scout.id, systemId: 's1' });
  command(oldGame, old.id, { type: 'move', fleetId: oldScout.id, systemId: 's1' });
  assert.ok(scout.duration < oldScout.duration);
  command(game, player.id, { type: 'research', tech: 'propulsion' });
  command(game, player.id, { type: 'build', ship: 'scout', systemId: home.id });
  tickGame(game, 1);
  assert.ok(player.research!.remaining < player.research!.total - 1);
  assert.ok(player.queue[0].remaining < player.queue[0].total - 1);
  const hiveGame = createGame('HIVE');
  const hive = addPlayer(hiveGame, 'hive', '', snapshotTemplate(starterLibrary(), 'empire-mycel'));
  const population = hiveGame.systems.find((s) => s.id === hive.home)!.colony!.population;
  tickGame(hiveGame, 1);
  assert.ok(hiveGame.systems[0].colony!.population > population + 1 / 240);
});
test('reform spends authoritative resources once and enforces cooldown, type and revision', () => {
  const { game, player } = setup();
  player.resources.science = 500;
  const origin = player.empire!.design.origin;
  const government = { ...player.empire!.design.government, civics: ['conservation', 'architects'] };
  command(game, player.id, { type: 'empire_reform', government, revision: 1 });
  assert.equal(player.resources.energy, 400);
  assert.equal(player.resources.science, 350);
  assert.equal(player.empire!.design.origin, origin);
});
test('invalid and unaffordable reforms leave both state and resources untouched', () => {
  const { game, player } = setup();
  const before = JSON.stringify(game);
  const government = { ...player.empire!.design.government, civics: ['conservation', 'architects'] };
  assert.throws(
    () => command(game, player.id, { type: 'empire_reform', government, revision: 1 }),
    /Ressourcen/,
  );
  assert.equal(JSON.stringify(game), before);
  player.resources.science = 1000;
  command(game, player.id, { type: 'empire_reform', government, revision: 1 });
  assert.equal(player.resources.science, 850);
  assert.equal(player.resources.energy, 400);
  const after = JSON.stringify(game);
  assert.throws(
    () =>
      command(game, player.id, { type: 'empire_reform', government: governmentFor('regular'), revision: 1 }),
    /zwischenzeitlich/,
  );
  assert.throws(
    () =>
      command(game, player.id, { type: 'empire_reform', government: governmentFor('regular'), revision: 2 }),
    /Spielsekunden/,
  );
  assert.equal(JSON.stringify(game), after);
  game.tick = 121;
  assert.throws(
    () =>
      command(game, player.id, { type: 'empire_reform', government: governmentFor('machine'), revision: 2 }),
    /Reichstyp/,
  );
});
test('species variants convert only selected own populations and affect their production independently', () => {
  const { game, player, home } = setup();
  player.techs.push('extraction');
  player.resources.science = 1000;
  const colony = game.systems[1];
  colony.owner = player.id;
  colony.planet = 'Wüstenwelt';
  colony.colony = createColony();
  hydrateEmpires(game);
  const source = player.empire!.species[0];
  const variant: SpeciesDesign = {
    ...source,
    name: 'Dünenmenschen',
    environment: 'desert',
    traits: ['industrious', 'intelligent'],
  };
  const before = colonyProduction(colony, player);
  const founding = JSON.stringify(player.empire!.founding);
  const pops = colony.colony.population;
  command(game, player.id, {
    type: 'species_modify',
    sourceId: source.id,
    design: variant,
    colonyIds: [colony.id],
    revision: 1,
  });
  const current = player.empire!.species[1];
  assert.equal(current.parentId, source.id);
  assert.equal(current.generation, 1);
  assert.equal(colony.colony.populations![0].speciesId, current.id);
  assert.equal(home.colony!.populations![0].speciesId, source.id);
  assert.equal(colony.colony.population, pops);
  assert.ok(colonyProduction(colony, player).minerals > before.minerals);
  assert.equal(player.resources.science, 700);
  assert.equal(player.resources.minerals, 240);
  assert.equal(JSON.stringify(player.empire!.founding), founding);
  assert.equal(player.empire!.species[0].environment, 'continental');
  assert.throws(
    () =>
      command(game, player.id, {
        type: 'species_modify',
        sourceId: source.id,
        design: variant,
        colonyIds: [home.id],
        revision: 2,
      }),
    /Spielsekunden/,
  );
});
test('malicious species targets and unresearched modifications are atomic; other players cannot read lineage', () => {
  const { game, player, home } = setup();
  const enemy = addPlayer(game, 'enemy', 'Enemy');
  const source = player.empire!.species[0];
  const cmd: GameCommand = {
    type: 'species_modify',
    sourceId: source.id,
    design: { ...source, name: 'Variant' },
    colonyIds: [home.id],
    revision: 1,
  };
  assert.throws(() => command(game, player.id, cmd), /Quantenextraktion/);
  player.techs.push('extraction');
  player.resources.science = 1000;
  const before = JSON.stringify(game);
  assert.throws(() => command(game, player.id, { ...cmd, colonyIds: [enemy.home] }), /eigenen Kolonie/);
  assert.throws(() => command(game, player.id, { ...cmd, colonyIds: [home.id, home.id] }), /doppelte/);
  assert.throws(
    () => command(game, player.id, { ...cmd, sourceId: enemy.empire!.primarySpeciesId }),
    /eigenen Kolonie/,
  );
  assert.equal(JSON.stringify(game), before);
  const peer = viewFor(game, enemy.id);
  assert.equal('empire' in peer.players.find((p) => p.id === player.id)!, false);
  assert.equal(peer.systems.find((s) => s.id === home.id)!.colony, null);
});
test('private libraries persist across store restarts and concurrent stale writes are rejected', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'empire-library-'));
  const store = new EmpireLibraryStore(directory);
  await store.load();
  const a = await store.connect();
  const b = await store.connect();
  assert.notEqual(a.key, b.key);
  const template = { ...a.library.empires[0], name: 'Private design' };
  const changes = await Promise.allSettled([
    store.mutate(a.key, { type: 'save_empire', template }),
    store.mutate(a.key, { type: 'save_empire', template }),
  ]);
  assert.equal(changes.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal(store.read(b.key).empires[0].name, 'Terranische Union');
  const restart = new EmpireLibraryStore(directory);
  await restart.load();
  assert.equal((await restart.connect(a.token)).library.empires[0].name, 'Private design');
  const disk = await readFile(join(directory, 'empire-libraries.json'), 'utf8');
  assert.equal(disk.includes(a.token), false);
  await assert.rejects(restart.connect('0'.repeat(64)), /nicht gefunden/);
  await writeFile(join(directory, 'empire-libraries.json'), '{ broken');
  await assert.rejects(new EmpireLibraryStore(directory).load());
  assert.equal(await readFile(join(directory, 'empire-libraries.json'), 'utf8'), '{ broken');
});

test('legacy migration preserves economy and templates are also used by AI in new games', () => {
  const legacy = createGame('OLD');
  const player = addPlayer(legacy, 'old', 'Old Player');
  delete player.empire;
  delete legacy.systems[0].colony!.populations;
  const oldResources = structuredClone(player.resources);
  const oldIncome = income(legacy, player);
  hydrateEmpires(legacy);
  assert.equal(player.empire!.legacy, true);
  assert.deepEqual(player.resources, oldResources);
  assert.deepEqual(income(legacy, player), oldIncome);
  const { game, player: human } = setup();
  command(game, human.id, { type: 'add_ai' });
  const ai = game.players.find((p) => p.ai)!;
  assert.equal(ai.empire!.legacy, false);
  assert.equal(ai.empire!.species[0].kind, 'biological');
  assert.equal(ai.empire!.design.government.kind, 'hive');
});

test('editing a shared species changes future founding snapshots without mutating past matches', () => {
  const { library, game, player } = setup();
  const changed = mutateLibrary(library, {
    type: 'save_species',
    template: { ...library.species[0], name: 'New Humanity', traits: ['industrious'] },
  });
  const next = snapshotTemplate(changed, 'empire-union');
  assert.equal(next.species.revision, 2);
  assert.equal(next.species.name, 'New Humanity');
  assert.equal(player.empire!.species[0].name, 'Mensch');
  assert.equal(player.empire!.founding.species.revision, 1);
  assert.equal(viewFor(game, player.id).me.empire!.founding.species.name, 'Mensch');
});
