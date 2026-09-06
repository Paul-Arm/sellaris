import { createServer } from 'node:http';
import { createReadStream } from 'node:fs';
import { mkdir, stat } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { WebSocketServer, WebSocket } from 'ws';
import { EmpireLibraryStore } from './empireLibrary.ts';
import { NativeGateway } from './nativeGateway';
import { installNativeUpgrade, proxyNativeHttp } from './nativeProxy';
import { snapshotTemplate } from '../shared/empires.ts';
interface Client {
  alive: boolean;
  count: number;
  window: number;
  libraryKey?: string;
  pending: Promise<void>;
}
const clients = new Map<WebSocket, Client>();
const dataDir = resolve(process.env.DATA_DIR || 'data');
const staticDir = resolve('dist');
await mkdir(dataDir, { recursive: true });
const libraries = new EmpireLibraryStore(dataDir);
await libraries.load();
const native = new NativeGateway(dataDir);
await native.load();
const mime: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.woff2': 'font/woff2',
  '.ico': 'image/x-icon',
  '.glb': 'model/gltf-binary',
};
const server = createServer(async (req, res) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  if (proxyNativeHttp(req, res)) return;
  if (req.url === '/api/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', version: 2, backend: 'spacetimedb', rooms: native.size }));
    return;
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405);
    res.end();
    return;
  }
  try {
    const path = decodeURIComponent(new URL(req.url || '/', 'http://localhost').pathname);
    let file = resolve(staticDir, `.${path === '/' ? '/index.html' : path}`);
    if (!file.startsWith(staticDir + sep)) {
      res.writeHead(403);
      res.end();
      return;
    }
    try {
      if (!(await stat(file)).isFile()) throw new Error('Not a file');
    } catch {
      if (extname(path)) {
        res.writeHead(404);
        res.end();
        return;
      }
      file = resolve(staticDir, 'index.html');
    }
    await stat(file);
    res.writeHead(200, {
      'Content-Type': mime[extname(file)] || 'application/octet-stream',
      'Cache-Control': file.includes(`${sep}assets${sep}`)
        ? 'public, max-age=31536000, immutable'
        : 'no-cache',
    });
    if (req.method === 'HEAD') res.end();
    else
      createReadStream(file)
        .on('error', () => res.destroy())
        .pipe(res);
  } catch {
    res.writeHead(404);
    res.end('Client not built. Run npm run build, or use the Vite development server on port 5173.');
  }
});
const wss = new WebSocketServer({
  noServer: true,
  maxPayload: 65536,
  verifyClient: ({ origin }: { origin: string }) =>
    !process.env.ALLOWED_ORIGIN || origin === process.env.ALLOWED_ORIGIN,
});
const nativeTunnel = installNativeUpgrade(server, wss);
function send(ws: WebSocket, data: unknown) {
  if (ws.readyState === WebSocket.OPEN && ws.bufferedAmount < 1_000_000) ws.send(JSON.stringify(data));
}
wss.on('connection', (ws) => {
  clients.set(ws, { alive: true, count: 0, window: Date.now(), pending: Promise.resolve() });
  ws.on('pong', () => {
    const c = clients.get(ws);
    if (c) c.alive = true;
  });
  ws.on('error', () => {
    /* close handles cleanup */
  });
  ws.on('message', (raw) => {
    const client = clients.get(ws)!;
    if (Date.now() - client.window > 1000) {
      client.window = Date.now();
      client.count = 0;
    }
    if (++client.count > 20) {
      send(ws, { type: 'error', message: 'Zu viele Befehle. Bitte kurz warten.' });
      return;
    }
    client.pending = client.pending.then(async () => {
      if (ws.readyState !== WebSocket.OPEN) return;
      let requestId: string | undefined;
      try {
        const msg = JSON.parse(raw.toString());
        if (!msg || typeof msg !== 'object') throw new Error('Ungültige Nachricht.');
        requestId = typeof msg.requestId === 'string' ? msg.requestId.slice(0, 80) : undefined;
        if (msg.type === 'library_open') {
          const profile = await libraries.connect(msg.token);
          client.libraryKey = profile.key;
          send(ws, { type: 'library', token: profile.token, library: profile.library, requestId });
          return;
        }
        if (msg.type === 'library_mutate') {
          if (!client.libraryKey) throw new Error('Öffne zuerst deine Vorlagenbibliothek.');
          await libraries.mutate(client.libraryKey, msg.mutation);
          // Broadcast to the same identity only, including other tabs.
          for (const [peer, peerClient] of clients)
            if (peerClient.libraryKey === client.libraryKey)
              send(peer, {
                type: 'library',
                library: libraries.read(client.libraryKey),
                requestId: peer === ws ? requestId : undefined,
              });
          return;
        }
        if (msg.type === 'ping') {
          send(ws, { type: 'pong', sent: msg.sent });
          return;
        }
        if (msg.type === 'create' || msg.type === 'join') {
          const template = snapshotTemplate(libraries.read(client.libraryKey || ''), msg.templateId);
          const code =
            msg.type === 'join'
              ? String(msg.code ?? '')
                  .trim()
                  .toUpperCase()
              : undefined;
          send(ws, await native.enter({ code, template, galaxy: msg.galaxy }));
          return;
        }
        throw new Error('Dieses Protokoll ist nicht mehr verfügbar. Bitte die Seite neu laden.');
      } catch (error) {
        send(ws, {
          type: 'error',
          message: error instanceof Error ? error.message : 'Ungültige Nachricht.',
          requestId,
        });
      }
    });
  });
  ws.on('close', () => {
    clients.delete(ws);
  });
});
const heartbeat = setInterval(() => {
  for (const [ws, client] of clients) {
    if (!client.alive) {
      ws.terminate();
      continue;
    }
    client.alive = false;
    ws.ping();
  }
}, 15_000);
async function shutdown() {
  clearInterval(heartbeat);
  for (const ws of clients.keys()) ws.close(1001, 'Server restarting');
  await libraries.flush();
  await native.flush();
  server.close();
  wss.close();
  nativeTunnel.close();
  process.exit(0);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
server.listen(Number(process.env.PORT || 3001), process.env.HOST || '0.0.0.0', () => {
  const address = server.address();
  console.log(
    `Singularity server on http://localhost:${address && typeof address === 'object' ? address.port : process.env.PORT || 3001}`,
  );
});
