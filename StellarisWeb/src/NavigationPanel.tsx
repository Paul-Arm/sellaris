import type { Fleet, GameCommand, GameView } from '../shared/game';
import { FACILITIES } from '../shared/celestial';
import { localPosition, type Point3 } from '../shared/navigation';
import './navigation.css';

export function NavigationPanel({
  fleet,
  game,
  command,
  disabled,
}: {
  fleet: Fleet;
  game: GameView;
  command: (c: GameCommand) => void;
  disabled: boolean;
}) {
  const nav = fleet.navigation;
  const at = nav ? localPosition(nav.motion, game.tick) : null;
  return (
    <section className="navigation-panel" aria-label="Flugaufträge">
      <h3>Flugaufträge</h3>
      {at && (
        <p>
          Position: {Math.round(at.x)} / {Math.round(at.y)} / {Math.round(at.z)}
        </p>
      )}
      <small>Rechtsklick: Flugziel oder Objektaktionen · Umschalt + Rechtsklick: Flug anhängen.</small>
      {fleet.type === 'scout' && (
        <button
          disabled={disabled || !!fleet.battleId}
          onClick={() => command({ type: 'scan', fleetId: fleet.id, append: true })}
        >
          Alle Himmelskörper erkunden
        </button>
      )}
      {fleet.type === 'colony' && (
        <button
          disabled={disabled || !!fleet.battleId}
          onClick={() => command({ type: 'colonize', fleetId: fleet.id, append: true })}
        >
          Am Ziel kolonisieren
        </button>
      )}
      {nav?.phase.includes('survey') && (
        <p role="status">
          Erkundet: {nav.visited.length} / {nav.totalBodies} Körper ·{' '}
          {nav.motion.paused ? 'Blockiert' : nav.phase === 'survey_scan' ? 'Untersuchung vor Ort' : 'Anflug'}
        </p>
      )}
      {nav?.phase === 'braking' && <p role="status">Schiff bremst ab.</p>}
      {nav?.phase === 'construction_flight' && (
        <p role="status">Anflug zum Bauplatz · Bau beginnt erst in Reichweite.</p>
      )}
      <ol aria-label="Befehlswarteschlange">
        {nav?.orders.map((o, i) => (
          <li key={i}>
            <span>
              {i === 0 ? 'Aktiv: ' : ''}
              {o.type === 'local_move'
                ? `Flug nach ${Math.round(o.point.x)} / ${Math.round(o.point.y)} / ${Math.round(o.point.z)}`
                : o.type === 'move'
                  ? `Nach ${game.systems.find((s) => s.id === o.systemId)?.name || o.systemId}`
                  : o.type === 'scan'
                    ? 'Alle Körper erkunden'
                    : o.type === 'site_build' || o.type === 'station_place'
                      ? `${FACILITIES[o.facility].name} bauen · Anflug zum Bauplatz`
                      : 'Kolonisieren'}
            </span>
            {i > 0 && (
              <button
                disabled={disabled}
                aria-label={`Auftrag ${i + 1} entfernen`}
                onClick={() => command({ type: 'fleet_remove_order', fleetId: fleet.id, index: i })}
              >
                ×
              </button>
            )}
          </li>
        ))}
      </ol>
      {!nav?.orders.length && <small>Keine wartenden Aufträge.</small>}
      <button
        disabled={disabled || !!fleet.battleId}
        onClick={() => command({ type: 'fleet_stop', fleetId: fleet.id })}
      >
        Stoppen und Warteschlange leeren
      </button>
      <small>
        Ein laufender Hyperraumabschnitt endet am nächsten System. Noch nicht ausführbare Aufträge werden mit
        Meldung übersprungen.
      </small>
    </section>
  );
}
export function PointInputs({ point, setPoint }: { point: Point3; setPoint: (p: Point3) => void }) {
  return (
    <div className="point-inputs">
      {(['x', 'y', 'z'] as const).map((axis) => (
        <label key={axis}>
          {axis === 'y' ? 'Höhe Y' : axis.toUpperCase()}
          <input
            type="number"
            min={axis === 'y' ? 0 : -1600}
            max={axis === 'y' ? 400 : 1600}
            step={10}
            value={point[axis]}
            onChange={(e) => setPoint({ ...point, [axis]: Number(e.target.value) })}
          />
        </label>
      ))}
    </div>
  );
}
