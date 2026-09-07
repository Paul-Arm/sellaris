import { randomBytes, timingSafeEqual } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { adminToken } from '../backend/admin';
import { connect } from '../backend/client';
import { cliAsync } from '../backend/tool.mjs';
import type { AdminServer, AdminOverview } from '../shared/admin';
import type { NativeGateway } from './nativeGateway';
import { inspectMatch } from './adminMatch';
import { validAdminEmpireAction } from '../shared/admin';

const endpoint = () => process.env.SPACETIME_HTTP || 'http://127.0.0.1:3100';
async function rows(database: string, query: string): Promise<unknown[][]> {
  const response = await fetch(`${endpoint()}/v1/database/${database}/sql`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${adminToken()}`, 'Content-Type': 'text/plain' },
    body: query,
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) throw new Error('Status nicht abrufbar. Backend und Datenbank prüfen.');
  const result = (await response.json()) as { rows: unknown[][] }[];
  return result[0].rows;
}
export async function inspectServer(
  entry: ReturnType<NativeGateway['listServers']>[number],
): Promise<AdminServer> {
  const base = { code: entry.code, database: entry.database, galaxy: entry.galaxy };
  if (entry.status === 'provisioning') return { ...base, status: 'provisioning' };
  try {
    const [clocks, empires, presence, settings] = await Promise.all([
      rows(entry.database, 'SELECT game_time, wall_time, speed, paused FROM clock'),
      rows(entry.database, 'SELECT id, name, ai FROM empire_summary'),
      rows(entry.database, 'SELECT id, online FROM game_presence'),
      rows(entry.database, 'SELECT capacity, host_id, winner_id FROM game_settings'),
    ]);
    if (!clocks[0] || !settings[0]) throw new Error('Galaxie ist noch nicht initialisiert.');
    const [gameTime, wallTime, speed, paused] = clocks[0];
    const [capacity, host, winner] = settings[0];
    return {
      ...base,
      status: winner ? 'finished' : paused ? 'paused' : 'running',
      day: Math.floor(
        Number(gameTime) + (paused ? 0 : Math.max(0, Date.now() / 1000 - Number(wallTime)) * Number(speed)),
      ),
      speed: Number(speed),
      capacity: Number(capacity),
      players: empires.map(([id, name, ai]) => ({
        id: Number(id),
        name: String(name),
        ai: Boolean(ai),
        online: !ai && presence.some(([player, online]) => player === id && online === true),
        host: id === host,
      })),
    };
  } catch {
    return { ...base, status: 'unavailable', error: 'Status nicht abrufbar. Backend und Datenbank prüfen.' };
  }
}

export function createAdminPanel(
  native: NativeGateway,
  token = process.env.ADMIN_PANEL_TOKEN || randomBytes(24).toString('hex'),
) {
  const expected = Buffer.from(`Bearer ${token}`);
  let pending: Promise<AdminOverview> | undefined;
  const overview = () =>
    (pending ??= (async () => {
      const entries = native.listServers();
      const servers: AdminServer[] = [];
      // Bound upstream concurrency even when the gateway contains its full 64 galaxies.
      for (let i = 0; i < entries.length; i += 4)
        servers.push(...(await Promise.all(entries.slice(i, i + 4).map(inspectServer))));
      return { servers, updatedAt: new Date().toISOString(), uptime: process.uptime() };
    })().finally(() => {
      pending = undefined;
    }));
  return {
    token,
    async handle(req: IncomingMessage, res: ServerResponse) {
      const path = new URL(req.url || '/', 'http://localhost').pathname;
      if (!path.startsWith('/api/admin/')) return false;
      const reply = (status: number, body: unknown) => {
        res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
        res.end(JSON.stringify(body));
      };
      const actual = Buffer.from(req.headers.authorization || '');
      if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
        reply(401, { error: 'Admin-Schlüssel ungültig.' });
        return true;
      }
      try {
        if (path === '/api/admin/servers' && req.method === 'GET') {
          reply(200, await overview());
          return true;
        }
        const match = /^\/api\/admin\/servers\/([A-F0-9]{6})$/.exec(path);
        if (!match) {
          reply(404, { error: 'Admin-Endpunkt nicht gefunden.' });
          return true;
        }
        if (req.method === 'GET') {
          const entry = native.listServers().find((e) => e.code === match[1]);
          if (!entry) reply(404, { error: 'Galaxie nicht gefunden.' });
          else reply(200, await inspectMatch(entry.code, entry.database, rows));
          return true;
        }
        if (req.method !== 'POST') {
          reply(405, { error: 'Methode nicht erlaubt.' });
          return true;
        }
        if (!req.headers['content-type']?.startsWith('application/json')) {
          reply(415, { error: 'JSON erforderlich.' });
          return true;
        }
        let body = '';
        for await (const chunk of req) {
          body += chunk.toString();
          if (Buffer.byteLength(body) > 4096) {
            reply(413, { error: 'Anfrage zu groß.' });
            return true;
          }
        }
        let action;
        try {
          action = JSON.parse(body);
        } catch {
          reply(400, { error: 'Ungültiges JSON.' });
          return true;
        }
        if (!action || typeof action !== 'object') {
          reply(400, { error: 'Ungültige Aktion.' });
          return true;
        }
        const code = match[1];
        if (!native.listServers().some((e) => e.code === code)) {
          reply(404, { error: 'Galaxie nicht gefunden.' });
          return true;
        }
        if (action.action === 'delete' && action.confirmation === code) {
          await native.administer(
            code,
            async (database) => {
              await cliAsync(['delete', database, '--server', endpoint(), '--yes']);
            },
            true,
          );
        } else if (
          action.action === 'clock' &&
          typeof action.paused === 'boolean' &&
          [1, 2, 3, 4].includes(action.speed)
        ) {
          await native.administer(code, async (database) => {
            const client = await connect(database, { uri: process.env.SPACETIME_WS, token: adminToken() });
            try {
              await client.conn.reducers.setClock({ paused: action.paused, speed: action.speed });
            } finally {
              client.conn.disconnect();
            }
          });
        } else if (validAdminEmpireAction(action)) {
          await native.administer(code, async (database) => {
            const response = await fetch(`${endpoint()}/v1/database/${database}/call/administer_game`, {
              method: 'POST',
              headers: { Authorization: `Bearer ${adminToken()}`, 'Content-Type': 'application/json' },
              body: JSON.stringify([JSON.stringify(action)]),
              signal: AbortSignal.timeout(10000),
            });
            if (!response.ok) throw new Error('Admin-Aktion abgelehnt.');
          });
        } else {
          reply(400, { error: 'Ungültige Aktion oder Löschbestätigung.' });
          return true;
        }
        reply(200, { ok: true });
      } catch {
        reply(502, {
          error:
            'Aktion fehlgeschlagen. Backend-Verbindung und Zustand der Galaxie prüfen, dann aktualisieren.',
        });
      }
      return true;
    },
  };
}
