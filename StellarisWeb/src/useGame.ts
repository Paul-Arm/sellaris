import { useCallback, useEffect, useRef, useState } from 'react';
import type { GameCommand, GameView } from '../shared/game';
import type { EmpireLibrary, LibraryMutation } from '../shared/empires';
import type { GalaxySettings } from '../shared/galaxySettings';
import { connect as connectNative, subscribe, type Client } from '../backend/client';
import { GAME_QUERIES, observeGame } from '../backend/game-client';
import { BattleDetailSubscription } from '../backend/detail-subscriptions';

type NativeSession = { code: string; database: string; token?: string; ticket?: string };
export function useGame() {
  const [state, setState] = useState<GameView | null>(null);
  const [hasSession, setHasSession] = useState(() => {
    try {
      const saved = JSON.parse(sessionStorage.getItem('singularity.native-session') || 'null');
      const room = new URLSearchParams(location.search).get('room');
      return !!saved && (!room || saved.code === room.toUpperCase());
    } catch {
      return false;
    }
  });
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState('');
  const [latency, setLatency] = useState(0);
  const [library, setLibrary] = useState<EmpireLibrary | null>(null);
  const [libraryError, setLibraryError] = useState('');
  const [libraryUnavailable, setLibraryUnavailable] = useState(false);
  const openingLibrary = useRef(false);
  const [nativeClient, setNativeClient] = useState<Client | null>(null);
  const native = useRef<Client | null>(null),
    nativeSession = useRef<NativeSession | null>(null),
    details = useRef<BattleDetailSubscription | null>(null);
  const profileToken = useRef<string | null>(null);
  const pendingLibrary = useRef(
    new Map<
      string,
      {
        resolve: (library: EmpireLibrary) => void;
        reject: (error: Error) => void;
        timer: ReturnType<typeof setTimeout>;
      }
    >(),
  );
  const [invite, setInvite] = useState(new URLSearchParams(location.search).get('room') || '');
  const socket = useRef<WebSocket | null>(null);
  const inviteRef = useRef(invite);
  useEffect(() => {
    try {
      nativeSession.current = JSON.parse(sessionStorage.getItem('singularity.native-session') || 'null');
    } catch {
      nativeSession.current = null;
    }
    try {
      profileToken.current = localStorage.getItem('singularity.library-token');
    } catch {
      /* The current connection still has a private profile. */
    }
    let stopped = false;
    let unobserve = () => {};
    let retry: ReturnType<typeof setTimeout>;
    let attempts = 0;
    let nativeRetry: ReturnType<typeof setTimeout>,
      nativeGeneration = 0,
      nativeAttempts = 0;
    async function attachNative(saved: NativeSession) {
      setHasSession(true);
      clearTimeout(nativeRetry);
      const generation = ++nativeGeneration;
      unobserve();
      details.current?.dispose();
      details.current = null;
      native.current?.conn.disconnect();
      native.current = null;
      setNativeClient(null);
      setConnected(false);
      setState(null);
      nativeSession.current = saved;
      const persist = () =>
        sessionStorage.setItem('singularity.native-session', JSON.stringify(nativeSession.current));
      persist();
      try {
        const availability = await fetch(`/api/galaxies/${encodeURIComponent(saved.code)}`);
        if (stopped || generation !== nativeGeneration) return;
        if (availability.status === 404) {
          nativeGeneration++;
          nativeSession.current = null;
          setHasSession(false);
          sessionStorage.removeItem('singularity.native-session');
          inviteRef.current = '';
          setInvite('');
          history.replaceState(null, '', location.pathname);
          setConnected(socket.current?.readyState === WebSocket.OPEN);
          setError('Diese Galaxie wurde gelöscht. Du kannst eine neue Expedition gründen.');
          return;
        }
        const client = await connectNative(saved.database, {
          uri: `${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}`,
          token: saved.token,
          onDisconnect: () => {
            if (stopped || generation !== nativeGeneration) return;
            setConnected(false);
            nativeRetry = setTimeout(() => {
              void attachNative(nativeSession.current!);
            }, 1500);
          },
        });
        if (stopped || generation !== nativeGeneration) {
          client.conn.disconnect();
          return;
        }
        native.current = client;
        nativeSession.current = { ...saved, token: client.token };
        persist();
        await subscribe(client.conn, GAME_QUERIES);
        if (![...client.conn.db.myGamePlayer.iter()].length && saved.ticket)
          await client.conn.reducers.redeemGameSeat({ ticket: saved.ticket });
        if (![...client.conn.db.myGamePlayer.iter()].length)
          throw new Error('Keine Reichssitzung gefunden. Bitte über die Lobby beitreten.');
        await client.conn.reducers.setFocus({ fleetId: 0, battleId: 0 });
        if (stopped || generation !== nativeGeneration) {
          client.conn.disconnect();
          return;
        }
        delete nativeSession.current.ticket;
        persist();
        sessionStorage.removeItem('singularity.session');
        nativeAttempts = 0;
        details.current = new BattleDetailSubscription(client);
        setNativeClient(client);
        unobserve = observeGame(client, setState);
        setConnected(true);
        setError('');
        inviteRef.current = '';
        setInvite('');
        history.replaceState(null, '', `${location.pathname}?room=${saved.code}`);
      } catch (e) {
        if (stopped || generation !== nativeGeneration) return;
        setError(e instanceof Error ? e.message : String(e));
        setConnected(false);
        // Keep the saved capability/token for a recoverable reconnect, never silently claim another empire.
        if (native.current?.conn.isActive) {
          nativeGeneration++;
          native.current.conn.disconnect();
        }
        nativeRetry = setTimeout(
          () => {
            if (!stopped) void attachNative(nativeSession.current!);
          },
          Math.min(8000, 1000 * 2 ** nativeAttempts++),
        );
      }
    }
    function connect() {
      const ws = new WebSocket(`${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/ws`);
      socket.current = ws;
      ws.onopen = () => {
        if (stopped) {
          ws.close();
          return;
        }
        attempts = 0;
        setConnected(true);
        setError('');
        setLibraryError('');
        setLibraryUnavailable(false);
        openingLibrary.current = true;
        ws.send(
          JSON.stringify({ type: 'library_open', token: profileToken.current, requestId: 'library-open' }),
        );
        if (
          nativeSession.current &&
          (!inviteRef.current || nativeSession.current.code === inviteRef.current.toUpperCase())
        ) {
          if (!native.current?.conn.isActive) void attachNative(nativeSession.current);
        }
      };
      ws.onmessage = (event) => {
        if (stopped) return;
        const msg = JSON.parse(event.data);
        if (msg.type === 'library') {
          if (msg.requestId === 'library-open') {
            openingLibrary.current = false;
            setLibraryError('');
            setLibraryUnavailable(false);
            setError('');
          }
          setLibrary(msg.library);
          if (msg.token) {
            profileToken.current = msg.token;
            try {
              localStorage.setItem('singularity.library-token', msg.token);
            } catch {
              setError(
                'Dein Browser kann den Bibliotheksschlüssel nicht dauerhaft speichern. Erlaube lokale Speicherung, um später wieder darauf zuzugreifen.',
              );
            }
          }
          const pending = pendingLibrary.current.get(msg.requestId);
          if (pending) {
            clearTimeout(pending.timer);
            pendingLibrary.current.delete(msg.requestId);
            pending.resolve(msg.library);
          }
        } else if (msg.type === 'native_ready') {
          void attachNative({ code: msg.code, database: msg.database, ticket: msg.ticket });
        } else if (msg.type === 'error') {
          setError(msg.message);
          if (msg.requestId === 'library-open') {
            openingLibrary.current = false;
            setLibraryError(msg.message);
            setLibraryUnavailable(msg.code === 'LIBRARY_PROFILE_UNAVAILABLE');
          }
          const pending = pendingLibrary.current.get(msg.requestId);
          if (pending) {
            clearTimeout(pending.timer);
            pendingLibrary.current.delete(msg.requestId);
            pending.reject(new Error(msg.message));
          }
        } else if (msg.type === 'pong') setLatency(Math.max(1, Date.now() - msg.sent));
      };
      ws.onclose = () => {
        if (stopped) return;
        openingLibrary.current = false;
        for (const pending of pendingLibrary.current.values()) {
          clearTimeout(pending.timer);
          pending.reject(
            new Error('Verbindung unterbrochen. Prüfe den Speicherstand nach dem Wiederverbinden.'),
          );
        }
        pendingLibrary.current.clear();
        if (!native.current?.conn.isActive) setConnected(false);
        retry = setTimeout(connect, Math.min(1000 * 2 ** attempts++, 8000));
      };
      ws.onerror = () => ws.close();
    }
    connect();
    // Only the day/readout changes here; atlas, fleets, JSON and indices stay untouched.
    const nativeFrames = setInterval(() => {
      const client = native.current;
      if (!client?.conn.isActive || !details.current) return;
      const tick = Math.floor(client.clock.now());
      setState((view) =>
        view &&
        (view.tick !== tick || view.paused !== client.clock.paused || view.speed !== client.clock.rate)
          ? { ...view, tick, paused: client.clock.paused, speed: client.clock.rate }
          : view,
      );
    }, 100);
    const ping = setInterval(() => {
      if (socket.current?.readyState === WebSocket.OPEN)
        socket.current.send(JSON.stringify({ type: 'ping', sent: Date.now() }));
    }, 4000);
    return () => {
      stopped = true;
      nativeGeneration++;
      clearTimeout(nativeRetry);
      clearInterval(nativeFrames);
      unobserve();
      details.current?.dispose();
      native.current?.conn.disconnect();
      native.current = null;
      clearTimeout(retry);
      clearInterval(ping);
      socket.current?.close();
      for (const pending of pendingLibrary.current.values()) {
        clearTimeout(pending.timer);
        pending.reject(new Error('Verbindung geschlossen.'));
      }
      pendingLibrary.current.clear();
    };
  }, []);
  const send = useCallback((data: unknown) => {
    if (socket.current?.readyState !== WebSocket.OPEN) {
      setError('Keine Serververbindung. Verbindung wird wiederhergestellt …');
      return;
    }
    setError('');
    socket.current.send(JSON.stringify(data));
  }, []);
  const mutateLibrary = useCallback((mutation: LibraryMutation): Promise<EmpireLibrary> => {
    if (socket.current?.readyState !== WebSocket.OPEN)
      return Promise.reject(new Error('Keine Serververbindung.'));
    const requestId = crypto.randomUUID();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pendingLibrary.current.delete(requestId);
        reject(new Error('Speicherbestätigung fehlt. Prüfe die Bibliothek nach dem Wiederverbinden.'));
      }, 15000);
      pendingLibrary.current.set(requestId, { resolve, reject, timer });
      socket.current!.send(JSON.stringify({ type: 'library_mutate', mutation, requestId }));
    });
  }, []);
  const openLibrary = useCallback((createNew = false) => {
    if (openingLibrary.current || socket.current?.readyState !== WebSocket.OPEN) return;
    if (createNew && profileToken.current) {
      try {
        // Preserve access to the previous server's library before replacing its key.
        localStorage.setItem(`singularity.library-token.backup.${Date.now()}`, profileToken.current);
      } catch {
        setLibraryError(
          'Der bisherige Bibliotheksschlüssel konnte nicht gesichert werden. Erlaube lokale Speicherung und versuche es erneut.',
        );
        return;
      }
    }
    openingLibrary.current = true;
    setLibraryError('');
    setLibraryUnavailable(false);
    setError('');
    socket.current.send(
      JSON.stringify({
        type: 'library_open',
        token: createNew ? null : profileToken.current,
        requestId: 'library-open',
      }),
    );
  }, []);
  return {
    state,
    hasSession,
    connected,
    error,
    setError,
    latency,
    invite,
    library,
    libraryError,
    libraryUnavailable,
    openLibrary,
    mutateLibrary,
    nativeClient,
    battles: nativeClient ? [...nativeClient.conn.db.visibleBattleSummaries.iter()] : [],
    focusDetails: useCallback(async (fleetId: number, battleId: number) => {
      try {
        await details.current?.focus(fleetId, battleId);
      } catch (e) {
        setError(String(e));
      }
    }, []),
    command: useCallback((cmd: GameCommand) => {
      if (native.current) {
        if (!native.current.conn.isActive) {
          setError('Verbindung wird wiederhergestellt …');
          return;
        }
        setError('');
        void native.current.conn.reducers
          .gameCommand({ commandJson: JSON.stringify(cmd) })
          .catch((e) => setError(String(e)));
      } else setError('Keine Reichssitzung verbunden.');
    }, []),
    join: (templateId: string, code: string) => send({ type: 'join', templateId, code }),
    create: (templateId: string, galaxy?: GalaxySettings) => send({ type: 'create', templateId, galaxy }),
  };
}
