import { connect } from './client';
import { adminToken } from './admin';
const [database = 'singularity-lab', action = 'pause', speedText = '1'] = process.argv.slice(2);
if (!['pause', 'resume'].includes(action))
  throw new Error('Usage: npm run backend:clock -- DATABASE pause|resume [0.5|1|2|4]');
const client = await connect(database, { token: adminToken(), uri: process.env.SPACETIME_WS });
try {
  await client.conn.reducers.setClock({ paused: action === 'pause', speed: Number(speedText) });
  console.log(`${database}: ${action}, ${speedText}×`);
} finally {
  client.conn.disconnect();
}
