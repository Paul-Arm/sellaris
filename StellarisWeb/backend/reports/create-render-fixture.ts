// Creates an isolated, paused 3,000-participant battle. Never changes registered games.
import { cli } from '../tool.mjs';
import { adminToken, seedDatabase } from '../admin';
import { connect } from '../client';
const database = `singularity-render-${Date.now()}`;
cli([
  'publish',
  database,
  '--server',
  'http://127.0.0.1:3100',
  '--js-path',
  'spacetimedb/dist/bundle.js',
  '--yes=skip-login',
]);
await seedDatabase(database, {
  seed: 42,
  systems: 1000,
  empires: 2,
  fleetsPerEmpire: 2,
  shipsPerEmpire: 3000,
  battleCount: 1,
  battleFleetsPerSide: 1,
  cohortsPerColony: 2,
  popsPerCohort: 25,
});
const client = await connect(database, { token: adminToken() });
try {
  await client.conn.reducers.setClock({ paused: true, speed: 1 });
} finally {
  client.conn.disconnect();
}
console.log(database);
