import { useEffect, useState } from 'react';
import type { Client } from '../backend/client';
import type { Fleet, GameView } from '../shared/game';
import { SHIPS } from '../shared/game';

export function NativeFleetPanel({
  client,
  game,
  fleet,
  onError,
}: {
  client: Client;
  game: GameView;
  fleet: Fleet;
  onError: (e: string) => void;
}) {
  const [selection, setSelection] = useState<number[]>([]),
    [target, setTarget] = useState(''),
    [busy, setBusy] = useState(false);
  useEffect(() => {
    setSelection([]);
    setTarget('');
  }, [fleet.id]);
  const ships = [...client.conn.db.fleetShips.iter()].filter((s) => s.fleetId === fleet.nativeId);
  const targets = game.fleets.filter(
    (f) =>
      f.owner === game.me.id &&
      f.id !== fleet.id &&
      f.systemId === fleet.systemId &&
      f.type === 'corvette' &&
      !f.route.length &&
      !f.battleId,
  );
  const idle = !fleet.route.length && !fleet.battleId && !fleet.task;
  async function action(fn: () => Promise<unknown>) {
    setBusy(true);
    try {
      await fn();
      setSelection([]);
      onError('');
    } catch (e) {
      onError(String(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="native-fleet-panel">
      <span className="eyebrow">FLOTTENVERBAND</span>
      <h2 id="dialog-title">{fleet.name}</h2>
      <p>
        {fleet.shipCount ?? 1} {(fleet.shipCount ?? 1) === 1 ? 'Schiff' : 'Schiffe'} · {Math.round(fleet.hp)}{' '}
        % Hülle
      </p>
      {fleet.battleId ? (
        <button
          className="secondary-button"
          disabled={busy}
          onClick={() => void action(() => client.conn.reducers.withdrawFleet({ fleetId: fleet.nativeId! }))}
        >
          Aus Gefecht zurückziehen
        </button>
      ) : null}
      <div className="native-ship-list" aria-label="Schiffe auswählen">
        {!ships.length && <p>Schiffsdaten werden geladen …</p>}
        {ships.map((ship) => (
          <label key={ship.id}>
            <input
              type="checkbox"
              checked={selection.includes(ship.id)}
              onChange={(e) =>
                setSelection((s) => (e.target.checked ? [...s, ship.id] : s.filter((id) => id !== ship.id)))
              }
            />
            <span>
              {ship.name}
              <small>
                {SHIPS[ship.design as keyof typeof SHIPS]?.name || ship.design} · {ship.weapons.length} Waffen
              </small>
            </span>
            <strong>
              {Math.round(ship.hull)} / {ship.maxHull}
              <small>Hülle · {Math.round(ship.shield)} Schilde</small>
            </strong>
          </label>
        ))}
      </div>
      <button
        className="secondary-button"
        disabled={busy || !idle || selection.length === 0 || selection.length >= ships.length}
        onClick={() =>
          void action(() => client.conn.reducers.splitFleet({ fleetId: fleet.nativeId!, shipIds: selection }))
        }
      >
        Ausgewählte Schiffe abteilen
      </button>
      {fleet.type === 'corvette' && (
        <div className="native-merge">
          <label htmlFor="merge-target">Mit eigenem Verband im selben System vereinen</label>
          <select id="merge-target" value={target} onChange={(e) => setTarget(e.target.value)}>
            <option value="">Zielverband wählen</option>
            {targets.map((f) => (
              <option key={f.id} value={f.nativeId}>
                {f.name} · {f.shipCount} Schiffe
              </option>
            ))}
          </select>
          <button
            className="secondary-button"
            disabled={busy || !idle || !target}
            onClick={() =>
              void action(() =>
                client.conn.reducers.mergeFleets({ sourceId: fleet.nativeId!, targetId: Number(target) }),
              )
            }
          >
            Verbände vereinen
          </button>
        </div>
      )}
    </section>
  );
}
