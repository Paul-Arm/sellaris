import type { GameCommand, GameView, StarSystem } from '../shared/game';
import type { StoredBody } from '../shared/systemObjects';
import { dysonHost } from '../shared/megastructures';
import { STELLAR_COLLAPSE as spec } from '../shared/stellarProjects';

export function StellarProjectPanel({
  game,
  system,
  body,
  bodies,
  command,
  disabled,
}: {
  game: GameView;
  system: StarSystem;
  body: StoredBody;
  bodies: StoredBody[];
  command: (cmd: GameCommand) => void;
  disabled: boolean;
}) {
  if (body.slot !== 0 || !dysonHost(body)) return null;
  const project = game.stellarProjects?.find((p) => p.systemId === system.id);
  const dyson = bodies.find((b) => b.megastructure === 'dyson' && b.parent === body.slot);
  const ready =
    dyson &&
    game.sites?.some(
      (s) =>
        s.bodySlot === dyson.slot &&
        s.systemId === system.id &&
        s.owner === game.me.id &&
        s.level === 3 &&
        !s.building,
    );
  const reason =
    system.owner !== game.me.id
      ? 'Eigenes System benötigt.'
      : !game.me.techs.includes('megastructures')
        ? 'Megakonstruktion erforschen.'
        : !game.me.surveyed.includes(system.id)
          ? 'System zuerst erkunden.'
          : !ready
            ? 'Ein vollständiger Dyson-Schwarm wird benötigt.'
            : (['energy', 'minerals', 'data'] as const).some((r) => game.me.resources[r] < spec[r])
              ? 'Nicht genug Rohstoffe.'
              : '';
  return (
    <section className="navigation-panel" aria-label="Sternkollaps">
      <h3>Kontrollierter Sternkollaps</h3>
      <p>
        Opfere den vollständigen Dyson-Schwarm für {spec.reward} Daten. Der Stern wird dauerhaft zum
        Neutronenstern.
      </p>
      <p>
        Dyson-Anlage und Sonnenkollektoren gehen verloren. Bewohnbare Planeten vereisen; laufendes
        Terraforming endet ohne Erstattung. Bevölkerung, Sektoren und andere Anlagen bleiben bestehen, ihre
        Erträge folgen dem neuen Klima.
      </p>
      {project ? (
        <>
          <p role="status">
            {game.paused ? 'Projekt pausiert' : 'Kollaps vorbereitet'} · {Math.ceil(project.remaining)} Tage
            verbleibend
          </p>
          <progress aria-label="Sternprojekt" max={project.total} value={project.total - project.remaining} />
          <button disabled={disabled} onClick={() => command({ type: 'stellar_cancel', jobId: project.id })}>
            Sternprojekt abbrechen · 50 % Erstattung
          </button>
        </>
      ) : (
        <>
          <small>
            {spec.energy} Energie · {spec.minerals} Mineralien · {spec.data} Daten · {spec.days} Tage
          </small>
          <button
            disabled={disabled || !!reason}
            onClick={() =>
              command({
                type: 'stellar_collapse',
                systemId: system.id,
                objectId: body.objectId,
                revision: body.revision,
              })
            }
          >
            Sternkollaps vorbereiten
          </button>
          <small>{reason || 'Kosten bei Projektstart. Abbruch bis zum Kollaps: 50 % Erstattung.'}</small>
        </>
      )}
    </section>
  );
}
