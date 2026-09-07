import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { ArrowUpRight, Check, Cpu, Database, Pause, Play, Sparkles } from 'lucide-react';
import type { GameCommand, GameView } from '../shared/game';
import {
  baseCompute,
  dataCost,
  RESEARCH_FIELDS,
  researchAllocation,
  visibleResearch,
  TECHS,
  type TechId,
} from '../shared/research';
import './research-atlas.css';
import { ResearchMap } from './ResearchMap';

const fmt = (n: number) => n.toLocaleString('de-DE', { maximumFractionDigits: 2 });
const color = (id: TechId) => RESEARCH_FIELDS[TECHS[id].field].color;
export function ResearchAtlas({
  game,
  command,
  connected,
}: {
  game: GameView;
  command: (cmd: GameCommand) => void;
  connected: boolean;
}) {
  const [selection, select] = useState<TechId>('computing');
  const [focusRequest, setFocusRequest] = useState<{ id: TechId; revision: number } | null>(null);
  const revealed = visibleResearch(game.me.techs);
  const selected = revealed.includes(selection) ? selection : revealed[0];
  const [share, setShare] = useState(game.me.research.synthesis);
  const pendingShare = useRef<number | null>(null);
  const me = game.me,
    program = me.research,
    spec = TECHS[selected];
  const compute = me.compute ?? baseCompute(me.techs);
  const allocation = researchAllocation(program, me.techs, compute);
  const disabled = !connected || !!game.winner;
  const selectedProject = program.projects.find((p) => p.tech === selected);
  const complete = me.techs.includes(selected);
  const activeCount = [...allocation.rates.values()].filter((r) => r > 0).length;
  useEffect(() => {
    if (pendingShare.current === null || pendingShare.current === program.synthesis) {
      pendingShare.current = null;
      setShare(program.synthesis);
    }
  }, [program.synthesis]);
  const focus = (id: TechId) => {
    if (!revealed.includes(id)) return;
    select(id);
    setFocusRequest((previous) => ({ id, revision: (previous?.revision || 0) + 1 }));
  };
  return (
    <section className="research-atlas">
      <header className="ra-header">
        <div>
          <span className="eyebrow">
            FORSCHUNGSNETZ / {me.techs.length} ERKENNTNISSE · {revealed.length - me.techs.length} NEUE WEGE
          </span>
          <h2 id="dialog-title">
            Das nächste <em>Unbekannte.</em>
          </h2>
          <p>Wähle dein Ziel. Verbinde Erkenntnisse. Verteile Rechenleistung.</p>
        </div>
        <div className="ra-resource">
          <Database size={20} />
          <div>
            <strong>{fmt(me.resources.data)}</strong>
            <span>Daten im Archiv</span>
          </div>
        </div>
        <div className="ra-resource compute">
          <Cpu size={20} />
          <div>
            <strong>{fmt(compute)}</strong>
            <span>Compute / Tag</span>
          </div>
        </div>
      </header>
      <div className="ra-workspace">
        <div className="ra-map-column">
          <ResearchMap
            known={me.techs}
            program={program}
            selected={selected}
            onSelect={select}
            focusRequest={focusRequest}
          />
          <section className="ra-allocation" aria-label="Compute verteilen">
            <div className="ra-section-head">
              <h3>Dein Rechenbudget</h3>
              <span>{game.paused ? 'SIMULATION PAUSIERT' : 'LIVE'}</span>
            </div>
            <div className="ra-budget-labels">
              <span>
                <Cpu size={14} /> Forschung <b>{fmt(allocation.research)} C/Tag</b>
              </span>
              <span>
                <Sparkles size={14} /> Datensynthese <b>{fmt(allocation.synthesis)} C/Tag</b>
              </span>
            </div>
            <div className="ra-budget-bar">
              <span style={{ width: `${compute ? (allocation.research / compute) * 100 : 0}%` }} />
            </div>
            <label className="ra-share">
              Compute für Datensynthese <b>{share} %</b>
              <input
                type="range"
                min="0"
                max="100"
                step="5"
                aria-label="Compute-Anteil für Datensynthese"
                value={share}
                disabled={disabled}
                onChange={(e) => {
                  pendingShare.current = Number(e.target.value);
                  setShare(pendingShare.current);
                }}
                onPointerUp={(e) =>
                  command({ type: 'research_synthesis', percent: Number(e.currentTarget.value) })
                }
                onKeyUp={(e) => {
                  if (
                    [
                      'ArrowLeft',
                      'ArrowRight',
                      'ArrowUp',
                      'ArrowDown',
                      'Home',
                      'End',
                      'PageUp',
                      'PageDown',
                    ].includes(e.key)
                  )
                    command({ type: 'research_synthesis', percent: Number(e.currentTarget.value) });
                }}
                onBlur={(e) => {
                  if (pendingShare.current !== null)
                    command({ type: 'research_synthesis', percent: Number(e.currentTarget.value) });
                }}
              />
            </label>
            <p>
              <strong>+{fmt(allocation.data)} Daten / Tag</strong> aus Simulationen. Freies Compute erzeugt
              automatisch Daten. Rechenzentren und Technologien erhöhen dein Budget.
            </p>
          </section>
        </div>
        <aside className="ra-inspector">
          <section className="ra-detail" style={{ '--node-color': color(selected) } as CSSProperties}>
            <span className="eyebrow">{RESEARCH_FIELDS[spec.field].name}</span>
            <h3>{spec.name}</h3>
            <p>{spec.description}</p>
            <div className="ra-costs">
              <span>
                <Database size={15} />
                <b>{dataCost(selected, me.techs)}</b> Daten
              </span>
              <span>
                <Cpu size={15} />
                <b>{spec.work}</b> Rechenarbeit
              </span>
            </div>
            <div className="ra-prerequisites">
              <small>VORAUSSETZUNGEN</small>
              {spec.requires.length ? (
                spec.requires.map((id) => (
                  <button key={id} onClick={() => focus(id)}>
                    {me.techs.includes(id) ? <Check size={13} /> : <span className="ra-open-dot" />}
                    {TECHS[id].name}
                    <ArrowUpRight size={12} />
                  </button>
                ))
              ) : (
                <p>Grundlagentechnologie · frei zugänglich</p>
              )}
            </div>
            {!complete && (
              <p className="ra-path-note">
                Neue Erkenntnisse decken weitere Forschungswege auf. Daten werden jeweils beim Projektstart
                bezahlt.
              </p>
            )}
            <button
              className="ra-plan-button"
              disabled={disabled || complete || !!selectedProject}
              onClick={() => command({ type: 'research', tech: selected })}
            >
              {complete ? (
                <>
                  <Check size={15} />
                  Erforscht
                </>
              ) : selectedProject ? (
                'Im Forschungsprogramm'
              ) : (
                <>
                  Forschung einplanen <ArrowUpRight size={16} />
                </>
              )}
            </button>
          </section>
          <section className="ra-program">
            <div className="ra-section-head">
              <h3>Forschungsprogramm</h3>
              <span>{activeCount} AKTIV</span>
            </div>
            {!program.projects.length && (
              <div className="ra-empty">
                <Sparkles size={24} />
                <p>Jeder Fortschritt beginnt mit einer Frage.</p>
                <small>Wähle einen Knoten auf der Karte und plane deinen Weg.</small>
              </div>
            )}
            {program.projects
              .filter((p) => revealed.includes(p.tech))
              .map((p) => {
                const rate = allocation.rates.get(p.tech) || 0,
                  t = TECHS[p.tech];
                const missing = t.requires.filter((id) => !me.techs.includes(id));
                return (
                  <article key={p.tech} className={selected === p.tech ? 'selected' : ''}>
                    <button className="ra-project-name" onClick={() => focus(p.tech)}>
                      <i style={{ background: color(p.tech) }} />
                      {t.name}
                      <ArrowUpRight size={12} />
                    </button>
                    <progress aria-label={`${t.name}: Fortschritt`} max={t.work} value={p.done} />
                    <div className="ra-project-status">
                      {!p.weight
                        ? 'Geparkt · Fortschritt gespeichert'
                        : missing.length
                          ? `Wartet auf ${missing.map((id) => TECHS[id].name).join(', ')}`
                          : program.synthesis === 100
                            ? 'Compute vollständig in Datensynthese'
                            : p.paid === null
                              ? `Wartet auf ${dataCost(p.tech, me.techs)} Daten`
                              : rate
                                ? `${fmt(rate)} C/Tag · ${Math.ceil((t.work - p.done) / rate)} Tage${game.paused ? ' · pausiert' : ''}`
                                : 'Wartet auf Compute'}
                    </div>
                    <div className="ra-project-controls">
                      <button
                        disabled={disabled}
                        aria-label={`${t.name} ${p.weight ? 'parken' : 'fortsetzen'}`}
                        onClick={() =>
                          command({ type: 'research_weight', tech: p.tech, weight: p.weight ? 0 : 1 })
                        }
                      >
                        {p.weight ? <Pause size={13} /> : <Play size={13} />}
                      </button>
                      <label>
                        Priorität{' '}
                        <select
                          aria-label={`${t.name}: Priorität`}
                          disabled={disabled}
                          value={p.weight}
                          onChange={(e) =>
                            command({ type: 'research_weight', tech: p.tech, weight: Number(e.target.value) })
                          }
                        >
                          <option value="0">Geparkt</option>
                          {[1, 2, 3, 4, 5].map((w) => (
                            <option key={w} value={w}>
                              {w}×
                            </option>
                          ))}
                        </select>
                      </label>
                      <span>{Math.round((p.done / t.work) * 100)} %</span>
                    </div>
                  </article>
                );
              })}
          </section>
        </aside>
      </div>
    </section>
  );
}
