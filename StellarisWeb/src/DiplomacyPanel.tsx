import { DetailList } from './DetailList';
import { useState } from 'react';
import { ArrowLeftRight, Handshake, ShieldCheck, Swords } from 'lucide-react';
import type { GameCommand, GameView, Resource, Resources } from '../shared/game';
import { relationBetween, OFFER_LIFETIME, TRUCE_DURATION } from '../shared/diplomacy';
import { EmpireFlag } from './EmpireFlag';
import { FLAG_PRESETS } from '../shared/flags';
import './diplomacy.css';

const keys: Resource[] = ['energy', 'minerals', 'data'];
const names = { energy: 'Energie', minerals: 'Mineralien', data: 'Daten' };
const statuses = {
  pending: 'Offen',
  accepted: 'Angenommen',
  rejected: 'Abgelehnt',
  cancelled: 'Zurückgezogen',
  expired: 'Abgelaufen',
};
const empty = (): Resources => ({ energy: 0, minerals: 0, data: 0 });
const format = (r: Resources) =>
  keys
    .filter((k) => r[k] > 0)
    .map((k) => `${r[k].toLocaleString('de-DE')} ${names[k]}`)
    .join(' · ') || 'Keine';
export function DiplomacyPanel({
  game,
  command,
  connected,
}: {
  game: GameView;
  command: (cmd: GameCommand) => void;
  connected: boolean;
}) {
  const peers = game.players.filter((p) => p.id !== game.me.id);
  const [selected, setSelected] = useState(peers[0]?.id || '');
  const [give, setGive] = useState<Resources>(empty),
    [receive, setReceive] = useState<Resources>(empty);
  const [composing, setComposing] = useState(false);
  const peer = peers.find((p) => p.id === selected) || peers[0];
  const relation = peer ? relationBetween(game.relations || [], game.me.id, peer.id) : undefined;
  const war = relation?.state === 'war',
    truce = Math.max(0, Math.ceil((relation?.truceUntil || 0) - game.tick));
  const offers = (game.offers || [])
    .filter((o) => o.empireA === peer?.id || o.empireB === peer?.id)
    .sort((a, b) => Number(b.status === 'pending') - Number(a.status === 'pending') || b.id - a.id);
  const pending = offers.find((o) => o.status === 'pending');
  const disabled = !connected || !!game.winner;
  const invalid =
    keys.some(
      (k) =>
        !Number.isInteger(give[k]) ||
        !Number.isInteger(receive[k]) ||
        give[k] < 0 ||
        receive[k] < 0 ||
        give[k] > 10000 ||
        receive[k] > 10000 ||
        give[k] > game.me.resources[k],
    ) || keys.every((k) => !give[k] && !receive[k]);
  const incoming = (game.offers || []).filter(
    (o) => o.empireB === game.me.id && o.status === 'pending',
  ).length;
  return (
    <section className="diplomacy-panel">
      <div className="dip-heading">
        <Handshake size={26} />
        <div>
          <h2 id="dialog-title">Diplomatie</h2>
        </div>
        <span className="dip-count">{incoming} eingehend</span>
      </div>
      {!peer ? (
        <div className="dip-empty">
          <OrbitMark />
          <h3>Noch kein anderes Reich</h3>
          <p>Lade einen Mitspieler ein oder ergänze eine KI in der Multiplayer-Lobby.</p>
        </div>
      ) : (
        <div className="dip-layout">
          <DetailList
            className="dip-peers"
            label="Kontakte"
            items={peers}
            getKey={(p) => p.id}
            getName={(p) => p.name}
            selectedKey={peer.id}
          >
            {(p) => {
              const r = relationBetween(game.relations || [], game.me.id, p.id);
              const messages = (game.offers || []).filter(
                (o) => o.empireA === p.id && o.empireB === game.me.id && o.status === 'pending',
              ).length;
              return (
                <button
                  key={p.id}
                  title={p.name}
                  aria-pressed={p.id === peer.id}
                  onClick={() => {
                    setSelected(p.id);
                    setComposing(false);
                    setGive(empty());
                    setReceive(empty());
                  }}
                >
                  <EmpireFlag flag={p.flag || FLAG_PRESETS[0].flag} width={30} />
                  <span>
                    <strong>{p.name}</strong>
                    <small>
                      {r?.state === 'war' ? 'Im Krieg' : 'Friedlich'}
                      {messages ? ` · ${messages} Angebot` : ''}
                    </small>
                  </span>
                </button>
              );
            }}
          </DetailList>
          <div className="dip-detail">
            <div className="dip-identity">
              <EmpireFlag flag={peer.flag || FLAG_PRESETS[0].flag} width={58} />
              <div>
                <h3>{peer.name}</h3>
                <p>
                  {peer.ai ? 'KI-Imperium' : peer.online ? 'Verbunden' : 'Offline'} · {peer.colonies}{' '}
                  {peer.colonies === 1 ? 'Kolonie' : 'Kolonien'}
                </p>
              </div>
            </div>
            <div className={`dip-relation ${war ? 'war' : ''}`}>
              {war ? <Swords size={18} /> : <ShieldCheck size={18} />}
              <strong>{war ? 'Im Krieg' : truce ? 'Waffenstillstand' : 'Friedliche Beziehungen'}</strong>
              {truce > 0 && <span>{truce} T verbleibend</span>}
            </div>
            <p className="dip-note">
              {war
                ? 'Flotten und Systemverteidigung bekämpfen einander. Angenommener Frieden beendet alle gemeinsamen Gefechte.'
                : 'Flotten können einander friedlich begegnen und fremde Systeme durchqueren.'}
            </p>
            <div className="dip-actions">
              {war ? (
                <button
                  className="primary-button"
                  disabled={disabled || !!pending}
                  onClick={() => command({ type: 'offer_treaty', empireId: peer.id, kind: 'peace' })}
                >
                  <Handshake size={16} /> Frieden anbieten
                </button>
              ) : (
                <>
                  <button
                    className="primary-button"
                    disabled={disabled || !!pending}
                    onClick={() => setComposing(!composing)}
                  >
                    <ArrowLeftRight size={16} /> Handel anbieten
                  </button>
                  <button
                    className="dip-war-button"
                    disabled={disabled || truce > 0}
                    onClick={() => command({ type: 'declare_war', empireId: peer.id })}
                  >
                    <Swords size={16} /> Krieg erklären
                  </button>
                </>
              )}
            </div>
            {composing && !war && !pending && (
              <form
                className="dip-trade"
                onSubmit={(e) => {
                  e.preventDefault();
                  if (invalid || disabled) return;
                  command({ type: 'offer_treaty', empireId: peer.id, kind: 'trade', give, receive });
                  setComposing(false);
                }}
              >
                <h4>Rohstofftausch</h4>
                <div className="dip-amounts">
                  <span>Rohstoff</span>
                  <strong>Du gibst</strong>
                  <strong>Du erhältst</strong>
                  {keys.map((k) => (
                    <div className="dip-resource-row" key={k}>
                      <span>
                        {names[k]}
                        <small>{Math.floor(game.me.resources[k])} verfügbar</small>
                      </span>
                      <input
                        type="number"
                        min="0"
                        max="10000"
                        step="1"
                        aria-label={`${names[k]} anbieten`}
                        value={give[k]}
                        onChange={(e) => setGive({ ...give, [k]: Number(e.target.value) })}
                      />
                      <input
                        type="number"
                        min="0"
                        max="10000"
                        step="1"
                        aria-label={`${names[k]} anfordern`}
                        value={receive[k]}
                        onChange={(e) => setReceive({ ...receive, [k]: Number(e.target.value) })}
                      />
                    </div>
                  ))}
                </div>
                <p className="dip-note">
                  Dein Angebot wird für {OFFER_LIFETIME} Spieltage reserviert. Bei Ablehnung, Rücknahme oder
                  Ablauf erhältst du die Rohstoffe zurück.
                </p>
                <button className="primary-button" disabled={invalid || disabled} type="submit">
                  Angebot senden
                </button>
              </form>
            )}
            {peer.ai && (
              <details className="dip-note">
                <summary>Handelsbewertung</summary>KI: Energie 1 · Mineralien 1,2 · Forschung 2. Akzeptiert
                bezahlbare, mindestens gleichwertige Angebote und Frieden.
              </details>
            )}
            <div className="dip-offers">
              <h4>Angebote & Vereinbarungen</h4>
              {!offers.length && <p className="dip-note">Noch keine Angebote mit diesem Reich.</p>}
              {offers.map((o) => {
                const outbound = o.empireA === game.me.id,
                  open = o.status === 'pending';
                const canPay = keys.every((k) => game.me.resources[k] >= o.receive[k]);
                return (
                  <article key={o.id} className={open ? 'pending' : ''}>
                    <div className="dip-offer-title">
                      <strong>{o.kind === 'peace' ? 'Friedensangebot' : 'Rohstofftausch'}</strong>
                      <span>{statuses[o.status]}</span>
                    </div>
                    <small>
                      {outbound ? 'Von dir' : `Von ${peer.name}`}
                      {open ? ` · ${Math.max(0, Math.ceil(o.expiresAt - game.tick))} T` : ''}
                    </small>
                    {o.kind === 'trade' ? (
                      <dl>
                        <div>
                          <dt>{open && outbound ? 'Reserviert' : 'Du gibst'}</dt>
                          <dd>{format(outbound ? o.give : o.receive)}</dd>
                        </div>
                        <div>
                          <dt>Du erhältst</dt>
                          <dd>{format(outbound ? o.receive : o.give)}</dd>
                        </div>
                      </dl>
                    ) : (
                      <p className="dip-note">
                        Beendet den Krieg. {TRUCE_DURATION} Spieltage Schutz vor einer erneuten
                        Kriegserklärung.
                      </p>
                    )}
                    {open &&
                      (outbound ? (
                        <button
                          className="secondary-button"
                          disabled={disabled}
                          onClick={() => command({ type: 'cancel_treaty', treatyId: o.id })}
                        >
                          Angebot zurückziehen
                        </button>
                      ) : (
                        <div className="dip-actions">
                          <button
                            className="primary-button"
                            disabled={disabled || !canPay || o.expiresAt <= game.tick}
                            onClick={() => command({ type: 'respond_treaty', treatyId: o.id, accept: true })}
                          >
                            Annehmen
                          </button>
                          <button
                            className="secondary-button"
                            disabled={disabled}
                            onClick={() => command({ type: 'respond_treaty', treatyId: o.id, accept: false })}
                          >
                            Ablehnen
                          </button>
                          {!canPay && <small>Zu wenig verfügbare Rohstoffe.</small>}
                        </div>
                      ))}
                  </article>
                );
              })}
            </div>
            {game.paused && (
              <p className="dip-note">
                Spiel pausiert – Angebotsfristen und Waffenstillstand laufen erst beim Fortsetzen weiter.
              </p>
            )}
          </div>
        </div>
      )}
    </section>
  );
}
function OrbitMark() {
  return <Handshake size={40} strokeWidth={1} />;
}
