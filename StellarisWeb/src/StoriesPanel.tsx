import { DetailList } from './DetailList';
import { useState } from 'react';
import { ArrowUpRight, Check, Clock3, Radio, ShieldCheck, Sparkles, Telescope } from 'lucide-react';
import type { GameCommand, GameView, Resources } from '../shared/game';
import {
  CRISIS,
  STORIES,
  phaseNames,
  crisisProductionFactor,
  type CrisisView,
  type StoryChoice,
} from '../shared/stories';
import './stories.css';
import { StellarWeatherPanel } from './StellarWeatherPanel';

const resourceNames = { energy: 'Energie', minerals: 'Mineralien', data: 'Daten' };
const resourceKeys = ['energy', 'minerals', 'data'] as const;
function amounts(r: Resources) {
  return resourceKeys
    .filter((k) => r[k])
    .map((k) => `${r[k]} ${resourceNames[k]}`)
    .join(' · ');
}
const canPay = (funds: Resources, cost: Resources) => resourceKeys.every((k) => funds[k] >= cost[k]);
const daysRemaining = (deadline: number, tick: number) => `${Math.max(0, Math.ceil(deadline - tick))} T`;
export function SituationSummary({ game, onOpen }: { game: GameView; onOpen: () => void }) {
  const open = game.decisions?.filter((d) => d.phase === 'pending').length || 0;
  const crisis = game.crises?.find((c) => !['dormant', 'contained'].includes(c.phase));
  const storm = game.systems.find(
    (s) => s.stellarWeather && s.stellarWeather.phase !== 'cancelled' && game.tick < s.stellarWeather.endsAt,
  );
  if (!open && !crisis && !storm) return null;
  return (
    <button className="situation-summary" onClick={onOpen}>
      <Radio size={18} />
      <span>
        <small>LAGEZENTRUM</small>
        <strong>
          {open
            ? `${open} ${open === 1 ? 'Entscheidung wartet' : 'Entscheidungen warten'}`
            : crisis
              ? phaseNames[crisis.phase]
              : `Sternensturm bei ${storm!.name}`}
        </strong>
        {crisis && (
          <small>
            {CRISIS.title} · {crisis.progress}/{crisis.target} Beiträge
          </small>
        )}
      </span>
      <ArrowUpRight size={15} />
    </button>
  );
}
function CrisisCard({
  crisis: c,
  game,
  command,
  onFocus,
  disabled,
}: {
  crisis: CrisisView;
  game: GameView;
  command: (c: GameCommand) => void;
  onFocus: (id: string) => void;
  disabled: boolean;
}) {
  const live = ['warning', 'active', 'surge'].includes(c.phase),
    loss = Math.round((1 - crisisProductionFactor(c.phase, c.shielded)) * 100);
  const system = game.systems.find((s) => s.id === c.systemId);
  return (
    <article className={`story-crisis ${c.phase}`} aria-label={CRISIS.title}>
      <div className="resonance-orbit" aria-hidden="true">
        <i />
        <i />
        <i />
        <span />
      </div>
      <div className="crisis-heading">
        <span className="eyebrow">GALAKTISCHE LAGE</span>
        <span className="crisis-phase">{phaseNames[c.phase]}</span>
      </div>
      <h3>{CRISIS.title}</h3>
      <p>
        {c.phase === 'dormant'
          ? 'Untersuchung des Risses löst die Vorwarnung vorzeitig aus.'
          : c.phase === 'contained'
            ? 'Krise eingedämmt. Kolonieproduktion wiederhergestellt.'
            : 'Alle Reiche können zur Eindämmung beitragen.'}
      </p>
      <button className="story-location" onClick={() => onFocus(c.systemId)}>
        <Telescope size={13} /> {system?.name || 'Ursprung lokalisieren'} <ArrowUpRight size={13} />
      </button>
      <div className="crisis-stages" aria-label="Krisenverlauf">
        {(['dormant', 'warning', 'active', 'surge', 'contained'] as const).map((phase) => (
          <span key={phase} aria-current={c.phase === phase ? 'step' : undefined}>
            {phaseNames[phase]}
          </span>
        ))}
      </div>
      {c.nextPhaseAt > 0 && (
        <div className="crisis-deadline">
          <Clock3 size={14} />
          <span>{c.phase === 'dormant' ? 'Erwartete Vorwarnung' : 'Nächste Eskalation'}</span>
          <strong>{daysRemaining(c.nextPhaseAt, game.tick)}</strong>
        </div>
      )}
      {live && (
        <>
          <div className="crisis-metrics">
            <div>
              <small>STABILISIERUNG</small>
              <strong>
                {c.progress} <span>/ {c.target}</span>
              </strong>
            </div>
            <div>
              <small>DEINE BEITRÄGE</small>
              <strong>{c.contributions}</strong>
            </div>
            <div>
              <small>DEINE PRODUKTION</small>
              <strong>{c.shielded ? 'Geschützt' : loss ? `−${loss} %` : 'Ungestört'}</strong>
            </div>
          </div>
          <progress aria-label="Gemeinsame Stabilisierung" value={c.progress} max={Math.max(1, c.target)} />
          <p className="story-note">
            Ohne Eindämmung: zuerst −25 %, danach −50 % Kolonieproduktion. Die Grundversorgung bleibt
            erhalten. Abschirmung schützt eigene Kolonien. Alle Fristen zählen Spielzeit.
          </p>
          <div className="crisis-actions">
            <button
              className="primary-button"
              disabled={disabled || !canPay(game.me.resources, CRISIS.contributionCost)}
              onClick={() => command({ type: 'crisis_action', crisisId: c.id, action: 'contribute' })}
            >
              <Sparkles size={14} /> Beitrag leisten <small>60 Energie · 30 Daten</small>
            </button>
            <button
              className="secondary-button"
              disabled={disabled || c.shielded || !canPay(game.me.resources, CRISIS.shieldCost)}
              onClick={() => command({ type: 'crisis_action', crisisId: c.id, action: 'shield' })}
            >
              <ShieldCheck size={14} />
              {c.shielded ? 'Abschirmung aktiv' : 'Kolonien abschirmen'}
              <small>{c.shielded ? 'Für diese Krise' : '120 Energie'}</small>
            </button>
          </div>
          <p className="story-note">
            Nach erfolgreicher Eindämmung: +40 Daten pro finanziertem Beitrag. Beiträge und Abschirmung
            werden sofort bezahlt.
          </p>
        </>
      )}
      {c.phase === 'contained' && (
        <div className="story-result">
          <Check size={16} />
          <span>
            {c.contributions
              ? `Dein Anteil: ${c.contributions} Beiträge · ${c.contributions * CRISIS.dataPerContribution} Daten erhalten.`
              : 'Die Kolonieproduktion ist wiederhergestellt.'}
          </span>
        </div>
      )}
    </article>
  );
}
export function StoriesPanel({
  game,
  command,
  connected,
  onFocus,
}: {
  game: GameView;
  command: (cmd: GameCommand) => void;
  connected: boolean;
  onFocus: (id: string) => void;
}) {
  const [selected, setSelected] = useState(0);
  const decisions = [...(game.decisions || [])].sort(
    (a, b) => Number(b.phase === 'pending') - Number(a.phase === 'pending') || b.id - a.id,
  );
  const active = decisions.find((d) => d.id === selected) || decisions[0];
  const definition = active && STORIES[active.kind];
  const pending = decisions.filter((d) => d.phase === 'pending').length;
  const disabled = !connected || !!game.winner;
  return (
    <section className="stories-panel">
      <div className="stories-title">
        <Radio size={25} />
        <div>
          <h2 id="dialog-title">Lagezentrum</h2>
        </div>
        <span>{pending} offen</span>
      </div>
      {game.crises?.map((c) => (
        <CrisisCard
          key={c.id}
          crisis={c}
          game={game}
          command={command}
          onFocus={onFocus}
          disabled={disabled}
        />
      ))}
      <div className="stories-section-title">
        <h3>Sternereignisse</h3>
      </div>
      {game.systems
        .filter((s) => s.stellarWeather)
        .map((s) => (
          <article key={s.id}>
            <button className="story-location" onClick={() => onFocus(s.id)}>
              <Telescope size={13} />
              {s.name}
              <ArrowUpRight size={13} />
            </button>
            <StellarWeatherPanel system={s} tick={game.tick} paused={game.paused} />
          </article>
        ))}
      {!game.systems.some((s) => s.stellarWeather) && (
        <p>Keine Sternereignisse.</p>
      )}
      <div className="stories-section-title">
        <h3>Entdeckungen & Beschlüsse</h3>
        <span>{decisions.length}</span>
      </div>
      {!active || !definition ? (
        <div className="stories-empty">
          <Telescope size={27} />
          <p>Noch keine Meldungen.</p>
          <small>
            Untersuche Anomalien oder gründe deine erste Außenkolonie. Neue Funde erscheinen hier.
          </small>
        </div>
      ) : (
        <div className="story-workspace">
          <DetailList
            className="story-list"
            label="Entscheidungen"
            items={decisions}
            getKey={(d) => d.id}
            getName={(d) => STORIES[d.kind]?.title || d.kind}
            getSearchText={(d) =>
              `${STORIES[d.kind]?.title || d.kind} ${game.systems.find((s) => s.id === d.systemId)?.name || ''}`
            }
            selectedKey={active.id}
          >
            {(d) => (
              <button key={d.id} aria-pressed={d.id === active.id} onClick={() => setSelected(d.id)}>
                <span>
                  {STORIES[d.kind]?.title || d.kind}
                  <small>{game.systems.find((s) => s.id === d.systemId)?.name || 'Fundort unbekannt'}</small>
                </span>
                <small>
                  {d.phase === 'pending'
                    ? daysRemaining(d.deadlineAt, game.tick)
                    : d.phase === 'expired'
                      ? 'Automatisch'
                      : 'Abgeschlossen'}
                </small>
              </button>
            )}
          </DetailList>
          <article className="story-detail">
            <h3>{definition.title}</h3>
            <details className="story-background">
              <summary>Hintergrund</summary>
              <p>{definition.description}</p>
            </details>
            <button className="story-location" onClick={() => onFocus(active.systemId)}>
              <Telescope size={13} />
              {game.systems.find((s) => s.id === active.systemId)?.name || 'Fundort'}
              <ArrowUpRight size={13} />
            </button>
            {active.phase === 'pending' ? (
              <>
                <div className="story-countdown">
                  <Clock3 size={14} />
                  <span>Entscheidung in {daysRemaining(active.deadlineAt, game.tick)}</span>
                </div>
                <div className="story-choices">
                  {(definition.choices as StoryChoice[]).map((option) => {
                    const cost = amounts(option.cost),
                      reward = amounts(option.reward);
                    const crisis = game.crises?.find((c) => c.systemId === active.systemId);
                    const shielded = option.action === 'shield' && crisis?.shielded;
                    return (
                      <button
                        key={option.id}
                        disabled={
                          disabled ||
                          !!shielded ||
                          active.deadlineAt <= game.tick ||
                          !canPay(game.me.resources, option.cost)
                        }
                        onClick={() => {
                          setSelected(active.id);
                          command({ type: 'resolve_decision', decisionId: active.id, choice: option.id });
                        }}
                      >
                        <strong>
                          {option.title}
                          <ArrowUpRight size={15} />
                        </strong>
                        <span>{option.description}</span>
                        <small>
                          {shielded ? 'Bereits abgeschirmt' : cost ? `Kosten: ${cost}` : 'Keine Kosten'}
                          {reward ? ` · Ertrag: ${reward}` : ''}
                        </small>
                      </button>
                    );
                  })}
                </div>
                <p className="story-note">
                  Nach Ablauf: „{definition.choices.find((o) => o.id === definition.fallback)?.title}“ ohne
                  Kosten. {game.paused ? 'Die Frist ist pausiert.' : ''}
                </p>
              </>
            ) : (
              <div className="story-result">
                <Check size={16} />
                <span>
                  {active.result}
                  {active.phase === 'expired' ? ' Automatisch nach Ablauf der Frist.' : ''}
                </span>
              </div>
            )}
          </article>
        </div>
      )}
    </section>
  );
}
