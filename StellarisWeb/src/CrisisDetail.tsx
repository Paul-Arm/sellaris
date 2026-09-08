import { ArrowUpRight, Check, Clock3, ShieldCheck, Sparkles, Telescope } from 'lucide-react';
import type { GameCommand, GameView, Resources } from '../shared/game';
import { CRISIS, phaseNames, crisisProductionFactor, type CrisisView } from '../shared/crises';
import './crisis-detail.css';
const daysRemaining = (deadline: number, tick: number) => `${Math.max(0, Math.ceil(deadline - tick))} T`;
const canPay = (funds: Resources, cost: Resources) => Object.keys(cost).every((k) => funds[k] >= cost[k]);
export function CrisisDetail({
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
    <article className={`crisis-detail ${c.phase}`} aria-label={CRISIS.title}>
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
      <button className="crisis-location" onClick={() => onFocus(c.systemId)}>
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
          <p className="crisis-note">
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
          <p className="crisis-note">
            Nach erfolgreicher Eindämmung: +40 Daten pro finanziertem Beitrag. Beiträge und Abschirmung werden
            sofort bezahlt.
          </p>
        </>
      )}
      {c.phase === 'contained' && (
        <div className="crisis-result">
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
