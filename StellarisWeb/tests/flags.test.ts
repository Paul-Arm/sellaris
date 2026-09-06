import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { defaultFlag, flagForEmpire, FLAG_PATTERNS, FLAG_PRESETS, parseFlag } from '../shared/flags';
import {
  mutateLibrary,
  parseEmpireTemplate,
  snapshotTemplate,
  starterLibrary,
  validateEmpireLibrary,
} from '../shared/empires';
import { addPlayer, createGame, income, viewFor } from '../shared/game';
import { EmpireLibraryStore } from '../server/empireLibrary';

test('legacy templates acquire flag defaults without changing map colors or mutating source data', () => {
  const library = starterLibrary();
  const before = JSON.stringify(library);
  const normalized = validateEmpireLibrary(library);
  for (const empire of normalized.empires) {
    assert.equal(empire.flag!.secondary, empire.color);
    assert.equal(empire.flag!.emblem, empire.emblem);
    assert.equal(empire.flag!.version, 1);
  }
  assert.equal(JSON.stringify(library), before);
  const old = { color: '#123456', emblem: 'wings' as const };
  assert.equal(flagForEmpire(old).emblem, 'wings');
  assert.equal('flag' in old, false);
});
test('all flag patterns and presets validate; unsafe fields and unsupported versions are rejected', () => {
  const fallback = { color: '#9c91ff', emblem: 'orbit' as const };
  for (const pattern of Object.keys(FLAG_PATTERNS))
    assert.equal(parseFlag({ ...defaultFlag(), pattern }, fallback).pattern, pattern);
  for (const preset of FLAG_PRESETS) assert.deepEqual(parseFlag(preset.flag, fallback), preset.flag);
  for (const invalid of [
    null,
    [],
    { ...defaultFlag(), version: 2 },
    { ...defaultFlag(), pattern: '__proto__' },
    { ...defaultFlag(), emblem: 'constructor' },
    { ...defaultFlag(), position: 'outside' },
    { ...defaultFlag(), frame: 'url(image)' },
    { ...defaultFlag(), size: NaN },
    { ...defaultFlag(), size: Infinity },
    { ...defaultFlag(), size: 200 },
    { ...defaultFlag(), rotation: -1 },
    { ...defaultFlag(), rotation: '90' },
    { ...defaultFlag(), primary: 'url(javascript:alert(1))' },
  ])
    assert.throws(() => parseFlag(invalid, fallback));
  const clean = parseFlag(
    { ...defaultFlag(), primary: '#ABCDEF', svg: '<script>alert(1)</script>', effects: { damage: 999 } },
    fallback,
  );
  assert.equal(clean.primary, '#abcdef');
  assert.equal('svg' in clean, false);
  assert.equal('effects' in clean, false);
});
test('flag edits survive private library reloads, keep the map color and reject stale changes', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'singularity-flags-'));
  const store = new EmpireLibraryStore(directory);
  await store.load();
  const profile = await store.connect();
  const template = { ...profile.library.empires[0], flag: FLAG_PRESETS[1].flag };
  await store.mutate(profile.key, { type: 'save_empire', template });
  const restarted = new EmpireLibraryStore(directory);
  await restarted.load();
  const restored = (await restarted.connect(profile.token)).library.empires[0];
  assert.deepEqual(restored.flag, FLAG_PRESETS[1].flag);
  assert.equal(restored.color, template.color);
  assert.equal(restored.emblem, restored.flag!.emblem);
  assert.equal(restored.revision, 2);
  await assert.rejects(restarted.mutate(profile.key, { type: 'save_empire', template }), /zwischenzeitlich/);
});
test('flag snapshots are independent across templates, matches, founding history and public projections', () => {
  let library = starterLibrary();
  library = mutateLibrary(library, {
    type: 'save_empire',
    template: { ...library.empires[0], flag: FLAG_PRESETS[2].flag },
  });
  const firstGame = createGame('FIRST');
  const first = addPlayer(firstGame, 'first', '', snapshotTemplate(library, 'empire-union'));
  const secondGame = createGame('SECOND');
  const second = addPlayer(secondGame, 'second', '', snapshotTemplate(library, 'empire-union'));
  library = mutateLibrary(library, {
    type: 'save_empire',
    template: { ...library.empires[0], flag: FLAG_PRESETS[0].flag },
  });
  assert.deepEqual(first.empire!.design.flag, FLAG_PRESETS[2].flag);
  assert.deepEqual(second.empire!.design.flag, FLAG_PRESETS[2].flag);
  first.empire!.design.flag!.secondary = '#102030';
  assert.notEqual(first.empire!.founding.empire.flag!.secondary, '#102030');
  assert.notEqual(second.empire!.design.flag!.secondary, '#102030');
  addPlayer(firstGame, 'peer', 'Peer');
  const projection = viewFor(firstGame, 'peer').players.find((player) => player.id === first.id)!;
  assert.equal(projection.flag!.secondary, '#102030');
  assert.equal('empire' in projection, false);
  projection.flag!.primary = '#ffffff';
  assert.notEqual(first.empire!.design.flag!.primary, '#ffffff');
});
test('custom flags remain cosmetic and do not change founding resources or production', () => {
  const library = starterLibrary();
  const beforeGame = createGame('BEFORE');
  const before = addPlayer(beforeGame, 'owner', '', snapshotTemplate(library, 'empire-union'));
  const changed = parseEmpireTemplate(
    { ...library.empires[0], flag: { ...FLAG_PRESETS[3].flag, size: 65, rotation: 345, position: 'upper' } },
    library.species,
  );
  const afterGame = createGame('AFTER');
  const after = addPlayer(
    afterGame,
    'owner',
    '',
    snapshotTemplate({ ...library, empires: [changed] }, changed.id),
  );
  assert.deepEqual(after.resources, before.resources);
  assert.deepEqual(income(afterGame, after), income(beforeGame, before));
  assert.equal(after.color, before.color);
});
