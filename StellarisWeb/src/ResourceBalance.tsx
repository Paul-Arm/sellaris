import { useState, type ReactNode } from 'react';
import { RESOURCE_CATALOG, type Resource } from '../shared/resources';
import {
  ECONOMY_CATEGORIES,
  ECONOMY_MONTH_DAYS,
  monthBoundary,
  resourceBalance,
  type EconomyLine,
} from '../shared/economy';
import './resource-balance.css';
import { Cpu } from 'lucide-react';
import type { GameView } from '../shared/game';
import { empireCompute } from '../shared/empireEconomy';
import { colonyEconomy } from '../shared/colonies';
import { ownedColonyWorlds } from '../shared/planetColonies';
import { researchAllocation, COMPUTE_LABELS } from '../shared/research';

const number = (n: number) => n.toLocaleString('de-DE', { maximumFractionDigits: 2 });
export const signedAmount = (n: number) => `${n > 0 ? '+' : n < 0 ? '−' : ''}${number(Math.abs(n))}`;
export function ComputeBalance({ game, onOpen }: { game: GameView | null; onOpen: () => void }) {
  const [open, setOpen] = useState(false);
  const compute = game ? (game.me.compute ?? empireCompute(game, game.me)) : 0;
  const allocation = game ? researchAllocation(game.me.research, game.me.techs, compute) : null;
  return (
    <div
      className="resource-balance"
      onMouseEnter={() => setOpen(true)}
      onMouseLeave={() => setOpen(false)}
      onFocus={() => setOpen(true)}
      onBlur={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false);
      }}
      onKeyDown={(event) => {
        if (event.key === 'Escape') {
          setOpen(false);
          event.stopPropagation();
        }
      }}
    >
      <button
        className="resource compute"
        aria-label="Compute: Rechenbudget und Forschung öffnen"
        aria-describedby={open ? 'balance-compute' : undefined}
        onClick={onOpen}
      >
        <Cpu size={17} />
        <strong>{number(compute)}</strong>
        <span>Compute / M</span>
      </button>
      {open && (
        <section id="balance-compute" className="balance-popover" aria-label="Compute: Monatsbilanz">
          <header>
            <strong>Compute</strong>
            <span>Rechenleistung pro Monat</span>
          </header>
          <div className="balance-net">
            <span>Gesamtkapazität</span>
            <b>{number(compute)}</b>
          </div>
          <div className="balance-summary">
            <span>
              Forschung<b>{number(allocation?.research ?? 0)}</b>
            </span>
            <span>
              Datensynthese<b>{number(allocation?.synthesis ?? 0)}</b>
            </span>
          </div>
          {(['production', 'terraforming'] as const).map((use) => (
            <div className="balance-net" key={use}>
              <span>{COMPUTE_LABELS[use]}</span>
              <b>{number(allocation?.[use] ?? 0)}</b>
            </div>
          ))}
          <p>Rechenleistung wird monatlich genutzt und nicht gelagert. Freie Kapazität erzeugt Daten.</p>
          {game && (
            <div className="balance-sources">
              <div className="balance-net">
                <span>Grundversorgung & Technologien</span>
                <b>{number(empireCompute({ systems: [] }, game.me))}</b>
              </div>
              {ownedColonyWorlds(game).map((world) => {
                const value = colonyEconomy(world.colony!, world.planet, game.me).compute;
                return value > 0 ? (
                  <div className="balance-net" key={world.worldId}>
                    <span>{world.colonyName ?? world.name}</span>
                    <b>{number(value)}</b>
                  </div>
                ) : null;
              })}
            </div>
          )}
          <footer>Inklusive Regierung, Spezies, Jobbesetzung und Versorgung.</footer>
        </section>
      )}
    </div>
  );
}
export function ResourceBalance({
  resource,
  stock,
  lines,
  day,
  onOpen,
  children,
}: {
  resource: Resource;
  stock: number;
  lines: EconomyLine[];
  day: number;
  onOpen: () => void;
  children: ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const balance = resourceBalance(lines, resource);
  const id = `balance-${resource}`;
  return (
    <div
      className="resource-balance"
      onMouseEnter={() => setOpen(true)}
      onMouseLeave={() => setOpen(false)}
      onFocus={() => setOpen(true)}
      onBlur={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false);
      }}
      onKeyDown={(event) => {
        if (event.key === 'Escape') {
          setOpen(false);
          event.stopPropagation();
        }
      }}
    >
      <button
        className={`resource ${resource}`}
        onClick={onOpen}
        aria-describedby={open ? id : undefined}
        aria-label={`${RESOURCE_CATALOG[resource].name}: Wirtschaftsübersicht öffnen`}
      >
        {children}
        <div>
          <strong>{number(stock)}</strong>
          <span className={balance.net < 0 ? 'balance-negative' : ''}>{signedAmount(balance.net)} / M</span>
        </div>
      </button>
      {open && (
        <section
          id={id}
          className="balance-popover"
          aria-label={`${RESOURCE_CATALOG[resource].name}: Monatsbilanz`}
        >
          <header>
            <strong>{RESOURCE_CATALOG[resource].name}</strong>
            <span>Monatsbilanz · {ECONOMY_MONTH_DAYS} Tage</span>
          </header>
          <div className="balance-summary">
            <span>
              Einnahmen<b>{signedAmount(balance.income)}</b>
            </span>
            <span>
              Ausgaben<b className="balance-negative">{signedAmount(-balance.expenses)}</b>
            </span>
          </div>
          <div className="balance-net">
            <strong>Netto pro Monat</strong>
            <b className={balance.net < 0 ? 'balance-negative' : ''}>{signedAmount(balance.net)}</b>
          </div>
          <p>
            Nächste Buchung: Tag {monthBoundary(day) + ECONOMY_MONTH_DAYS}. Prognose mit aktuellen Jobs und
            Modifikatoren.
          </p>
          <div className="balance-sources">
            {Object.entries(ECONOMY_CATEGORIES).map(([category, name]) => {
              const entries = balance.entries.filter((line) => line.category === category);
              if (!entries.length) return null;
              return (
                <details key={category} open>
                  <summary>
                    {name}
                    <b>{signedAmount(entries.reduce((n, l) => n + l.amount, 0))}</b>
                  </summary>
                  {entries.map((line) => (
                    <details className="balance-source" key={line.id}>
                      <summary>
                        <span>
                          {line.source}
                          {line.species && (
                            <small>
                              {line.species} · {number(line.employed ?? 0)} Jobs
                            </small>
                          )}
                        </span>
                        <b>{signedAmount(line.amount)}</b>
                      </summary>
                      <div>
                        <span>Grundwert</span>
                        <b>{signedAmount(line.base)}</b>
                      </div>
                      {line.modifiers
                        .filter((m) => Math.abs(m.delta) > 1e-8)
                        .map((m, i) => (
                          <div key={`${m.id}:${i}`}>
                            <span>{m.name}</span>
                            <b className={m.delta < 0 ? 'balance-negative' : ''}>{signedAmount(m.delta)}</b>
                          </div>
                        ))}
                    </details>
                  ))}
                </details>
              );
            })}
          </div>
          <footer>
            Bestand {number(stock)} · Nach Buchung {number(stock + balance.net)}
          </footer>
        </section>
      )}
    </div>
  );
}
