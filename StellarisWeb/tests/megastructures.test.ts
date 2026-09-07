import test from 'node:test';
import assert from 'node:assert/strict';
import { facilityFits, facilitySpec, facilityYield, systemBodies } from '../shared/celestial';
import { createGame } from '../shared/game';
import { DYSON_STAGES, dysonHost, megastructureHost, megastructureTerritory } from '../shared/megastructures';
import { facilityModel } from '../src/system-models';

test('Dyson stages have distinct total yields and require their own object', () => {
  const star = systemBodies(createGame('D750A1').systems[0])[0];
  assert(dysonHost(star));
  assert(!dysonHost({ ...star, kind: 'blackhole' }));
  assert(!dysonHost({ ...star, stellar: { ...star.stellar!, family: 'pulsar' } }));
  const structure = {
    ...star,
    kind: 'station' as const,
    stellar: undefined,
    megastructure: 'dyson' as const,
  };
  assert(facilityFits('dyson', structure));
  assert(!facilityFits('dyson', star));
  assert(!facilityFits('dyson', { ...structure, megastructure: undefined }));
  assert(!facilityFits('habitat', structure));
  assert.deepEqual(
    [0, 1, 2, 3].map((level) => facilityYield('dyson', level).energy),
    [0, 0, 30, 90],
  );
  assert.equal(facilityYield('dyson', 3, 0.5).energy, 45);
  assert.deepEqual(
    DYSON_STAGES.map((_, level) => facilitySpec('dyson', level).days),
    [60, 100, 160],
  );
  const site = {
    id: 's:9',
    systemId: 's',
    bodySlot: 9,
    facility: 'dyson' as const,
    owner: 'a',
    level: 2,
    building: false,
    startedAt: 0,
    finishAt: 0,
    suspended: false,
  };
  assert(facilityModel({ ...site, level: 3 }, structure).span > facilityModel(site, structure).span);
});

test('decompressors reserve a separate object at quiet black holes and produce minerals only', () => {
  const star = systemBodies(createGame('DC0001').systems[0])[0];
  const hole = {
    ...star,
    kind: 'blackhole' as const,
    stellar: { ...star.stellar!, family: 'blackhole' as const },
  };
  assert(megastructureHost('decompressor', hole));
  assert(!megastructureHost('decompressor', star));
  assert(!megastructureHost('decompressor', { ...hole, stellar: { ...hole.stellar, family: 'quasar' } }));
  assert(megastructureTerritory('decompressor', 'blackhole', null, 'a'));
  assert(!megastructureTerritory('decompressor', 'blackhole', 'b', 'a'));
  assert(!megastructureTerritory('dyson', 'blackhole', null, 'a'));
  const body = {
    ...hole,
    kind: 'station' as const,
    stellar: undefined,
    megastructure: 'decompressor' as const,
  };
  assert(facilityFits('decompressor', body));
  assert(!facilityFits('decompressor', hole));
  assert(!facilityFits('research', body));
  assert(!facilityFits('dyson', body));
  assert.deepEqual(
    [0, 1, 2, 3].map((level) => facilityYield('decompressor', level).minerals),
    [0, 0, 25, 75],
  );
  assert.deepEqual(facilityYield('decompressor', 3, 0.5), { energy: 0, minerals: 37.5, data: 0 });
  const base = {
    id: 's:9',
    systemId: 's',
    bodySlot: 9,
    facility: 'decompressor' as const,
    owner: 'a',
    level: 0,
    building: true,
    startedAt: 0,
    finishAt: 60,
    suspended: false,
  };
  const models = [0, 1, 2, 3].map((level) => facilityModel({ ...base, level }, body));
  assert.equal(new Set(models.map((m) => m.id)).size, 3);
  assert(models[3].span > models[2].span);
  assert(
    models.every((m) => m.height! > body.radius),
    'collectors leave the event horizon visible',
  );
});
