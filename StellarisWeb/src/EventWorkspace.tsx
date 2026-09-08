import { useEffect, useRef, useState } from 'react';
import {
  ArrowLeft,
  ArrowRight,
  Check,
  ChevronRight,
  Clock3,
  Compass,
  FlaskConical,
  Pause,
  Play,
  Radio,
  Search,
  Sparkles,
  X,
} from 'lucide-react';
import type { GameCommand, GameView } from '../shared/game';
import type { Situation } from '../shared/events/types';
import { EVENT_DEFINITIONS } from '../shared/events/catalog';
import { TERMINAL, choiceCosts } from '../shared/events/engine';
import { economyDate } from '../shared/economy';
import { EventContent, EventCosts, EventPanel, EventProgress, canAfford } from './EventContent';
import { CrisisDetail } from './CrisisDetail';
import { StellarWeatherPanel } from './StellarWeatherPanel';
import { CRISIS, phaseNames } from '../shared/crises';
import './events.css';

const statusNames: Record<string, string> = {
  available: 'Entdeckt',
  active: 'In Arbeit',
  decision: 'Entscheidung offen',
  paused: 'Pausiert',
  completed: 'Abgeschlossen',
  failed: 'Beendet',
};
type Props = {
  game: GameView;
  command: (cmd: GameCommand) => void;
  connected: boolean;
  selection: string | null;
  onSelect: (id: string | null) => void;
  onFocus: (id: string) => void;
};
function SituationDetail({
  item,
  game,
  command,
  connected,
  onFocus,
}: Omit<Props, 'selection' | 'onSelect'> & { item: Situation }) {
  const d = EVENT_DEFINITIONS[item.definitionId],
    s = item.state,
    stage = d.stages[s.stage];
  const finished = TERMINAL.has(s.status);
  const action = (type: 'situation_start' | 'situation_pause' | 'situation_resume') =>
    command({ type, id: item.id, revision: s.revision });
  return (
    <div className={`situation-detail event-theme-${d.theme}`}>
      <header
        className="event-detail-hero"
        style={{ backgroundImage: `linear-gradient(90deg,#0c1523 5%,#0c152344),url(${d.artwork})` }}
      >
        <span className="event-kicker">
          {d.kind === 'project' ? 'SPEZIALPROJEKT' : 'EREIGNIS'} <i /> {statusNames[s.status]}
        </span>
        <h1 id="dialog-title">{d.title}</h1>
        <p>{d.summary}</p>
        {d.progress && (
          <EventProgress
            value={s.progress}
            max={d.progress.target}
            rate={s.status === 'active' ? s.lastRate : undefined}
            paused={game.paused || s.status === 'paused'}
          />
        )}
      </header>
      <div className="event-detail-grid">
        <nav className="event-stage-list" aria-label="Projektphasen">
          <span className="event-kicker">VERLAUF</span>
          {d.stages.map((st, i) => (
            <div
              key={st.id}
              className={i === s.stage ? 'current' : i < s.stage ? 'done' : ''}
              aria-current={i === s.stage ? 'step' : undefined}
            >
              <span>{i < s.stage ? <Check size={13} /> : String(i + 1).padStart(2, '0')}</span>
              <div>
                {st.title}
                <small>
                  {i < s.stage ? 'Erreicht' : i === s.stage ? statusNames[s.status] : 'Ausstehend'}
                </small>
              </div>
            </div>
          ))}
          <p className="event-muted">Entdeckt am {economyDate(s.createdAt)}</p>
        </nav>
        <main className="event-detail-main">
          <h2>
            {finished
              ? s.status === 'completed'
                ? 'Auswertung abgeschlossen'
                : 'Vorhaben beendet'
              : stage?.title}
          </h2>
          <EventContent
            blocks={
              stage?.blocks ?? [
                {
                  type: 'text',
                  text: 'Die Ergebnisse wurden archiviert. Ressourcen und dauerhafte Veränderungen sind bereits deinem Reich zugeordnet.',
                },
              ]
            }
            game={game}
            item={item}
            onFocus={onFocus}
          />
          {s.status === 'available' && (
            <EventPanel title="Bereit für den nächsten Schritt">
              <p>
                Das Projekt beginnt nach deiner Freigabe. Während der Arbeit können Fortschritt und
                Rückschläge einander ablösen.
              </p>
              <div className="event-start">
                <EventCosts cost={d.startCost} />
                <button
                  className="primary-button"
                  disabled={!connected || !canAfford(game.me.resources, d.startCost)}
                  onClick={() => action('situation_start')}
                >
                  <Play size={15} />
                  Projekt starten
                </button>
              </div>
            </EventPanel>
          )}
          {s.status === 'decision' && stage && (
            <EventPanel title="Deine Entscheidung">
              {stage.timeoutDays && (
                <p className="event-deadline">
                  <Clock3 size={14} />
                  {Math.max(0, Math.ceil(s.enteredAt + stage.timeoutDays - game.tick))} Tage verbleibend
                  {game.paused ? ' · pausiert' : ''}
                </p>
              )}
              <div className="event-choices">
                {stage.choices?.map((choice) => {
                  const eligible = item.availableChoices.includes(choice.id),
                    affordable = canAfford(game.me.resources, choiceCosts(choice));
                  return (
                    <button
                      key={choice.id}
                      disabled={!connected || !eligible || !affordable}
                      onClick={() =>
                        command({
                          type: 'situation_choice',
                          id: item.id,
                          revision: s.revision,
                          choice: choice.id,
                        })
                      }
                    >
                      <span>
                        <strong>{choice.title}</strong>
                        <p>{choice.description}</p>
                        <EventCosts cost={choiceCosts(choice)} />
                        {!eligible && <small>Bedingungen nicht erfüllt</small>}
                        {eligible && !affordable && <small>Ressourcen fehlen</small>}
                      </span>
                      <ArrowRight size={18} />
                    </button>
                  );
                })}
              </div>
            </EventPanel>
          )}
          {(s.status === 'active' || s.status === 'paused') && (
            <div className="event-work-controls">
              <span>
                {game.paused
                  ? 'Die Simulation ist pausiert.'
                  : s.status === 'paused'
                    ? 'Fortschritt bleibt erhalten.'
                    : 'Messungen werden täglich ausgewertet.'}
              </span>
              <button
                className="secondary-button"
                disabled={!connected}
                onClick={() => action(s.status === 'paused' ? 'situation_resume' : 'situation_pause')}
              >
                {s.status === 'paused' ? <Play size={14} /> : <Pause size={14} />}{' '}
                {s.status === 'paused' ? 'Fortsetzen' : 'Projekt pausieren'}
              </button>
            </div>
          )}
        </main>
        <aside className="event-history">
          <span className="event-kicker">PROJEKTPROTOKOLL</span>
          {[...s.history].reverse().map((h, i) => (
            <article key={`${h.day}:${i}`}>
              <small>{economyDate(h.day)}</small>
              <p>{h.text}</p>
              {d.progress && (
                <span>
                  {h.progress.toFixed(1)} / {d.progress.target}
                </span>
              )}
            </article>
          ))}
        </aside>
      </div>
    </div>
  );
}
export function EventWorkspace(props: Props) {
  const { game, selection, onSelect, command, connected, onFocus } = props;
  const [tab, setTab] = useState<'all' | 'event' | 'project' | 'archive'>('all');
  const [query, setQuery] = useState('');
  const situations = game.situations ?? [];
  const item = situations.find((s) => `s:${s.id}` === selection);
  const crisis = game.crises?.find((c) => `c:${c.id}` === selection);
  const weatherSystem = game.systems.find((s) => s.stellarWeather && `w:${s.id}` === selection);
  const active = situations.filter((s) => !TERMINAL.has(s.state.status));
  const open = (s: Situation) => {
    onSelect(`s:${s.id}`);
    if (s.state.seen < s.state.notice) command({ type: 'situation_ack', id: s.id, notice: s.state.notice });
  };
  if (item || crisis || weatherSystem)
    return (
      <section className="event-workspace">
        <div className="event-breadcrumb">
          <button onClick={() => onSelect(null)}>
            <ArrowLeft size={16} />
            Lagezentrum
          </button>
          <ChevronRight size={14} />
          <span>
            {item ? EVENT_DEFINITIONS[item.definitionId].title : crisis ? CRISIS.title : 'Sternensturm'}
          </span>
        </div>
        {item ? (
          <SituationDetail {...props} item={item} />
        ) : crisis ? (
          <CrisisDetail
            crisis={crisis}
            game={game}
            command={command}
            onFocus={onFocus}
            disabled={!connected}
          />
        ) : weatherSystem ? (
          <StellarWeatherPanel system={weatherSystem} tick={game.tick} paused={game.paused} />
        ) : null}
      </section>
    );
  const visible = situations
    .filter((s) => {
      const d = EVENT_DEFINITIONS[s.definitionId];
      return (
        (tab === 'archive'
          ? TERMINAL.has(s.state.status)
          : !TERMINAL.has(s.state.status) && (tab === 'all' || d.kind === tab)) &&
        `${d.title} ${d.summary}`.toLocaleLowerCase('de').includes(query.toLocaleLowerCase('de'))
      );
    })
    .sort(
      (a, b) => Number(b.state.status === 'decision') - Number(a.state.status === 'decision') || b.id - a.id,
    );
  return (
    <section className="event-workspace">
      <header className="event-overview-header">
        <div>
          <span className="event-kicker">
            <Radio size={14} />
            REICHSNACHRICHTENDIENST
          </span>
          <h1 id="dialog-title">Lagezentrum</h1>
          <p>Entdeckungen verfolgen. Entscheidungen treffen. Möglichkeiten erforschen.</p>
        </div>
        <div className="event-overview-stat">
          <strong>{active.length}</strong>
          <span>aktive Vorgänge</span>
        </div>
      </header>
      <div className="event-toolbar">
        <div role="tablist" aria-label="Vorgänge filtern">
          {(
            [
              ['all', 'Alle Vorgänge'],
              ['event', 'Ereignisse'],
              ['project', 'Spezialprojekte'],
              ['archive', 'Archiv'],
            ] as const
          ).map(([id, label]) => (
            <button key={id} role="tab" aria-selected={tab === id} onClick={() => setTab(id)}>
              {label}
            </button>
          ))}
        </div>
        <label>
          <Search size={15} />
          <input
            aria-label="Vorgänge durchsuchen"
            placeholder="Suchen …"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </label>
      </div>
      {tab === 'all' && !query && (
        <div className="event-alert-strip">
          {game.crises
            ?.filter((c) => !['dormant', 'contained'].includes(c.phase))
            .map((c) => (
              <button key={c.id} onClick={() => onSelect(`c:${c.id}`)}>
                <Radio size={17} />
                <span>
                  {CRISIS.title}
                  <small>{phaseNames[c.phase]}</small>
                </span>
                <ArrowRight size={16} />
              </button>
            ))}
          {game.systems
            .filter((s) => s.stellarWeather && ['warning', 'active'].includes(s.stellarWeather.phase))
            .map((s) => (
              <button key={s.id} onClick={() => onSelect(`w:${s.id}`)}>
                <Sparkles size={17} />
                <span>
                  Sternensturm<small>{s.name}</small>
                </span>
                <ArrowRight size={16} />
              </button>
            ))}
        </div>
      )}
      <div className="event-card-grid">
        {visible.map((s) => {
          const d = EVENT_DEFINITIONS[s.definitionId];
          return (
            <button key={s.id} className={`event-card event-theme-${d.theme}`} onClick={() => open(s)}>
              <div className="event-card-art" style={{ backgroundImage: `url(${d.artwork})` }}>
                <span>
                  {d.kind === 'project' ? <FlaskConical size={14} /> : <Radio size={14} />}{' '}
                  {d.kind === 'project' ? 'Spezialprojekt' : 'Ereignis'}
                </span>
                {s.state.seen < s.state.notice && <b>NEU</b>}
              </div>
              <div className="event-card-body">
                <span className={`event-status ${s.state.status}`}>{statusNames[s.state.status]}</span>
                <h2>{d.title}</h2>
                <p>{d.summary}</p>
                {d.progress && <EventProgress value={s.state.progress} max={d.progress.target} />}
                <footer>
                  <span>{game.systems.find((w) => w.id === s.systemId)?.name ?? 'Reichsweit'}</span>
                  <ArrowRight size={16} />
                </footer>
              </div>
            </button>
          );
        })}
      </div>
      {!visible.length && (
        <div className="event-empty">
          <Compass size={34} />
          <h2>
            {query
              ? 'Keine passenden Vorgänge'
              : tab === 'archive'
                ? 'Noch keine abgeschlossenen Vorgänge'
                : 'Der nächste Fund liegt hinter dem Horizont'}
          </h2>
          <p>
            {query
              ? 'Ändere den Suchbegriff oder den Filter.'
              : 'Erkundung, Forschung und die Entwicklung deines Reichs eröffnen neue Ereignisse und Projekte.'}
          </p>
        </div>
      )}
    </section>
  );
}
export function EventAnnouncement({
  game,
  connected,
  command,
  onOpen,
}: {
  game: GameView;
  connected: boolean;
  command: (c: GameCommand) => void;
  onOpen: (id: string) => void;
}) {
  const item = [...(game.situations ?? [])]
    .filter((s) => s.state.notice > s.state.seen)
    .sort(
      (a, b) => Number(b.state.status === 'decision') - Number(a.state.status === 'decision') || a.id - b.id,
    )[0];
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    if (item && dialog && !dialog.open) dialog.showModal();
    return () => dialog?.close();
  }, [item?.id, item?.state.notice]);
  if (!item) return null;
  const d = EVENT_DEFINITIONS[item.definitionId],
    s = item.state;
  const dismiss = () => command({ type: 'situation_ack', id: item.id, notice: s.notice });
  const label =
    s.status === 'decision'
      ? 'Eine Entscheidung wartet'
      : s.status === 'completed'
        ? 'Projekt abgeschlossen'
        : d.kind === 'project' && s.status === 'available'
          ? 'Neues Spezialprojekt entdeckt'
          : 'Neue Nachricht';
  return (
    <dialog
      ref={ref}
      className={`event-announcement event-theme-${d.theme}`}
      aria-labelledby="event-announcement-title"
      onKeyDown={(e) => e.stopPropagation()}
      onCancel={(e) => {
        e.preventDefault();
        dismiss();
      }}
    >
      <div className="event-announcement-art" style={{ backgroundImage: `url(${d.artwork})` }}>
        <span className="event-kicker">
          <Radio size={14} />
          {label}
        </span>
        <button aria-label="Ankündigung schließen" disabled={!connected} onClick={dismiss}>
          <X size={18} />
        </button>
      </div>
      <div className="event-announcement-body">
        <span className="event-kicker">{d.subtitle}</span>
        <h2 id="event-announcement-title">{d.title}</h2>
        <p>{d.summary}</p>
        <div>
          <button className="secondary-button" disabled={!connected} onClick={dismiss}>
            Später ansehen
          </button>
          <button
            className="primary-button"
            disabled={!connected}
            onClick={() => {
              dismiss();
              onOpen(`s:${item.id}`);
            }}
          >
            Vorgang öffnen
            <ArrowRight size={15} />
          </button>
        </div>
      </div>
    </dialog>
  );
}
