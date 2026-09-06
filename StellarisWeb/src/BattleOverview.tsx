import type { VisibleBattleSummaryProjection } from '../backend/module_bindings/types';

const format = (n: number) => Math.floor(n).toLocaleString('de-DE');
export function BattleOverview({
  battles,
  ownerId,
  selectedId,
  disabled,
  onOpen,
  systemNames,
  empireNames,
}: {
  battles: VisibleBattleSummaryProjection[];
  ownerId?: number;
  selectedId: number;
  disabled: boolean;
  onOpen: (id: number) => void;
  systemNames?: Map<number, string>;
  empireNames?: Map<number, string>;
}) {
  return (
    <section className="lab-battle-overview" aria-label="Gefechtsübersicht">
      <div className="lab-section-label">
        GEFECHTE <span>{battles.length}</span>
      </div>
      {!battles.length && <p className="lab-battle-empty">Keine Gefechte in Sensorreichweite</p>}
      <div className="lab-battle-cards">
        {battles.map((b) => {
          const ownsDefender = ownerId === b.defenders;
          const ownSide = ownerId === b.attackers || ownsDefender;
          const sides = ownsDefender ? [b.defender, b.attacker] : [b.attacker, b.defender];
          const losses = ownsDefender
            ? [b.defenderLosses, b.attackerLosses]
            : [b.attackerLosses, b.defenderLosses];
          return (
            <article key={b.id} className={selectedId === b.id ? 'selected' : ''}>
              <div className="lab-battle-heading">
                <strong>
                  Gefecht {b.id} <small>{systemNames?.get(b.systemId) || `System ${b.systemId}`}</small>
                </strong>
                <span>
                  {b.state === 'active'
                    ? 'LÄUFT'
                    : b.winnerId
                      ? `SIEGER: ${empireNames?.get(b.winnerId) || b.winnerId}`
                      : 'BEENDET'}
                </span>
              </div>
              {b.tracked ? (
                <>
                  <div className="lab-battle-sides">
                    {sides.map((side, i) => {
                      const start = side.startingHull + side.startingShield;
                      const hp = side.hull + side.shield;
                      const label = ownSide
                        ? i === 0
                          ? 'Deine Seite'
                          : 'Gegenseite'
                        : i === 0
                          ? 'Angreifer'
                          : 'Verteidiger';
                      return (
                        <div key={label}>
                          <span>{label}</span>
                          <strong>
                            {format(side.ships)} <small>Schiffe</small>
                          </strong>
                          <progress
                            aria-label={`${label}: verbleibende HP`}
                            value={hp}
                            max={Math.max(1, start)}
                          />
                          <span>
                            {start ? Math.round((hp / start) * 100) : 0} % HP · {losses[i]} Verluste
                          </span>
                          <span>
                            Hülle {format(side.hull)}
                            <br />
                            Schilde {format(side.shield)}
                          </span>
                          <span className="lab-battle-damage">
                            Schaden verursacht<strong>{format(side.damageDealt)} HP</strong>
                          </span>
                        </div>
                      );
                    })}
                  </div>
                  <small
                    className="lab-battle-caption"
                    title="Effektiver Hüllen- und Schildschaden nach Panzerung, ohne Overkill. Rückzüge zählen nicht als Schaden und senken nur die im Gefecht gebundenen HP."
                  >
                    {systemNames
                      ? `${Math.max(0, Math.floor(b.sampledAt - b.baselineAt))} Spieltage erfasst`
                      : `Messbeginn: Tag ${Math.floor(b.baselineAt)} · Stand: Tag ${Math.floor(b.sampledAt)}`}
                  </small>
                </>
              ) : (
                <p className="lab-battle-empty">Keine aufgezeichneten HP-Daten für dieses frühere Gefecht.</p>
              )}
              {b.state === 'active' && (
                <button disabled={disabled} onClick={() => onOpen(b.id)}>
                  {selectedId === b.id ? 'Gefecht geöffnet' : 'Gefecht ansehen'}
                </button>
              )}
            </article>
          );
        })}
      </div>
    </section>
  );
}
