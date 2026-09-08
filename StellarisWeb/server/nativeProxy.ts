import { request, type IncomingMessage, type ServerResponse, type Server } from 'node:http';
import { WebSocket, WebSocketServer } from 'ws';

const endpoint = () => process.env.SPACETIME_HTTP || 'http://127.0.0.1:3100';
export function proxyNativeHttp(req: IncomingMessage, res: ServerResponse): boolean {
  if (req.url?.split('?')[0] !== '/v1/identity/websocket-token') return false;
  if (req.method !== 'POST') {
    res.writeHead(405);
    res.end();
    return true;
  }
  const upstream = request(
    new URL('/v1/identity/websocket-token', endpoint()),
    {
      method: 'POST',
      headers: {
        ...(req.headers.authorization ? { authorization: req.headers.authorization } : {}),
        'content-length': '0',
      },
    },
    (reply) => {
      res.writeHead(reply.statusCode || 502, {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
      });
      reply.pipe(res);
    },
  );
  upstream.on('error', () => {
    if (!res.headersSent) res.writeHead(502);
    res.end('{"error":"Backend unavailable"}');
  });
  upstream.end();
  return true;
}
/** Same-origin binary tunnel. No simulation, command interpretation, or credentials in URLs/logs. */
export function installNativeUpgrade(server: Server, library: WebSocketServer) {
  const tunnel = new WebSocketServer({ noServer: true, maxPayload: 8 * 1024 * 1024 });
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url || '/', 'http://localhost');
    if (process.env.ALLOWED_ORIGIN && req.headers.origin !== process.env.ALLOWED_ORIGIN) {
      socket.destroy();
      return;
    }
    if (url.pathname === '/ws') {
      library.handleUpgrade(req, socket, head, (ws) => library.emit('connection', ws, req));
      return;
    }
    if (!/^\/v1\/database\/singularity-game-[a-z0-9-]+\/subscribe$/.test(url.pathname)) {
      socket.destroy();
      return;
    }
    tunnel.handleUpgrade(req, socket, head, (downstream) => {
      const target = new URL(url.pathname + url.search, endpoint());
      target.protocol = target.protocol === 'https:' ? 'wss:' : 'ws:';
      const upstream = new WebSocket(target, downstream.protocol ? [downstream.protocol] : undefined, {
        maxPayload: 64 * 1024 * 1024,
      });
      const pending: { data: Buffer; binary: boolean }[] = [];
      let queued = 0;
      const close = () => {
        downstream.close();
        upstream.close();
      };
      downstream.on('message', (raw, binary) => {
        const data = Buffer.isBuffer(raw) ? raw : Buffer.from(raw as ArrayBuffer);
        if (upstream.readyState === WebSocket.OPEN) {
          if (upstream.bufferedAmount > 8 * 1024 * 1024) return close();
          upstream.send(data, { binary });
        } else {
          queued += data.byteLength;
          if (queued > 1024 * 1024) return close();
          pending.push({ data, binary });
        }
      });
      upstream.on('open', () => {
        for (const msg of pending) upstream.send(msg.data, { binary: msg.binary });
        pending.length = 0;
      });
      upstream.on('message', (data, binary) => {
        if (downstream.readyState === WebSocket.OPEN) {
          if (downstream.bufferedAmount > 8 * 1024 * 1024) return close();
          downstream.send(data, { binary });
        }
      });
      upstream.on('error', close);
      downstream.on('error', close);
      upstream.on('close', () => downstream.close());
      downstream.on('close', () => upstream.close());
    });
  });
  return tunnel;
}
