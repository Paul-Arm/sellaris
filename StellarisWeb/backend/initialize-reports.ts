import { adminToken } from './admin';
import { connect, subscribe } from './client';

// Additive upgrade: initialize only missing summaries, without changing the world clock.
const databases = process.argv.slice(2);
if (!databases.length) throw new Error('Pass one or more previously published database names');
for (const database of databases) {
  const client = await connect(database, { uri: process.env.SPACETIME_WS, token: adminToken() });
  try {
    await subscribe(client.conn, ['SELECT * FROM clock']);
    const before = JSON.stringify([...client.conn.db.clock.iter()]);
    await client.conn.reducers.initializeBattleReports({});
    if (JSON.stringify([...client.conn.db.clock.iter()]) !== before)
      throw new Error('Clock changed during initialization');
    console.log(`${database}: missing battle summaries initialized; clock unchanged.`);
  } finally {
    client.conn.disconnect();
  }
}
