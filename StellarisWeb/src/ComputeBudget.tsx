import { useEffect, useState } from 'react';
import {
  COMPUTE_USES,
  COMPUTE_LABELS,
  reservedCompute,
  researchAllocation,
  type ComputeUse,
} from '../shared/research';
import { empireCompute } from '../shared/empireEconomy';
import type { GameView, GameCommand } from '../shared/game';

const fmt = (n: number) => n.toLocaleString('de-DE', { maximumFractionDigits: 2 });
function BudgetSlider({
  use,
  value,
  max,
  disabled,
  commit,
}: {
  use: ComputeUse;
  value: number;
  max: number;
  disabled: boolean;
  commit: (percent: number) => void;
}) {
  const [draft, setDraft] = useState(value);
  useEffect(() => setDraft(value), [value]);
  return (
    <label className="ra-share">
      {COMPUTE_LABELS[use]} <b>{draft} %</b>
      <input
        type="range"
        min={0}
        max={max}
        step={1}
        value={Math.min(draft, max)}
        disabled={disabled}
        aria-label={`Compute-Anteil für ${COMPUTE_LABELS[use]}`}
        onChange={(e) => setDraft(Number(e.target.value))}
        onPointerUp={(e) => commit(Number(e.currentTarget.value))}
        onKeyUp={(e) => {
          if (
            ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End', 'PageUp', 'PageDown'].includes(
              e.key,
            )
          )
            commit(Number(e.currentTarget.value));
        }}
        onBlur={(e) => {
          if (Number(e.currentTarget.value) !== value) commit(Number(e.currentTarget.value));
        }}
      />
    </label>
  );
}
export function ComputeBudget({
  game,
  command,
  disabled,
}: {
  game: GameView;
  command: (cmd: GameCommand) => void;
  disabled: boolean;
}) {
  const program = game.me.research;
  const compute = game.me.compute ?? empireCompute(game, game.me);
  const allocation = researchAllocation(program, game.me.techs, compute);
  const reserved = reservedCompute(program);
  const effects: Record<ComputeUse, string> = {
    synthesis: `+${fmt(allocation.data)} Daten / Monat einschließlich freier Forschungskapazität`,
    production: `+${fmt(allocation.productionBonus * 100)} % Energie und Mineralien aus Jobs, Bergbau und Anlagen`,
    terraforming:
      'Budget wird unter laufenden Projekten geteilt. 10 Compute je Projekt: +50 % Tempo; maximal +100 %.',
  };
  return (
    <section className="ra-allocation" aria-label="Compute verteilen">
      <div className="ra-section-head">
        <h3>Dein Rechenbudget</h3>
        <span>{fmt(compute)} C / MONAT</span>
      </div>
      <p>
        <strong>
          {100 - reserved} % für Forschung · {fmt(allocation.research)} C / Monat aktiv
        </strong>
      </p>
      <div className="ra-compute-grid">
        {COMPUTE_USES.map((use) => (
          <div className="ra-compute-use" key={use}>
            <BudgetSlider
              use={use}
              value={program[use]}
              max={100 - reserved + program[use]}
              disabled={disabled}
              commit={(percent) => command({ type: 'compute_allocation', use, percent })}
            />
            <small>{fmt(allocation[use])} C / Monat</small>
            <p>{effects[use]}</p>
          </div>
        ))}
      </div>
      <p>
        Die Regler reservieren zusammen höchstens 100 %. Unbeschäftigte Forschung erzeugt Daten.
        Klimasimulation bleibt auch ohne Projekt reserviert. Produktionsoptimierung nähert sich bei mehr
        Compute einem Bonus von +50 %.
      </p>
    </section>
  );
}
