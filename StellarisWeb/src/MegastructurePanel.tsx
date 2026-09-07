import type { GameCommand, GameView, StarSystem } from '../shared/game';
import type { CelestialBody } from '../shared/celestial';
import {
  MEGASTRUCTURES,
  hostMegastructure,
  megastructureStage,
  megastructureTerritory,
} from '../shared/megastructures';
import { constructionFleet } from '../shared/navigation';

export function MegastructurePanel({
  game,
  system,
  body,
  bodies,
  command,
  disabled,
  onBody,
}: {
  game: GameView;
  system: StarSystem;
  body: CelestialBody;
  bodies: CelestialBody[];
  command: (c: GameCommand) => void;
  disabled: boolean;
  onBody: (slot: number, project?: boolean) => void;
}) {
  const type = body.megastructure || hostMegastructure(body);
  if (!type) return null;
  const definition = MEGASTRUCTURES[type];
  const structure = body.megastructure
    ? body
    : bodies.find((b) => b.megastructure === type && b.parent === body.slot);
  const site =
    structure && game.sites?.find((s) => s.systemId === system.id && s.bodySlot === structure.slot);
  const level = site?.level || 0,
    next = definition.stages[Math.min(2, level)];
  const reason =
    site && site.owner !== game.me.id
      ? 'Diese Megastruktur gehört einem anderen Reich.'
      : !megastructureTerritory(type, system.kind, system.owner, game.me.id)
        ? 'Eigenes System benötigt.'
        : !game.me.surveyed.includes(system.id)
          ? 'System zuerst erkunden.'
          : !game.me.techs.includes('megastructures')
            ? 'Erforsche zuerst Megakonstruktion.'
            : !constructionFleet(game, system.id)
              ? 'Ein eigenes Schiff im System wird benötigt.'
              : game.me.resources.energy < next.energy || game.me.resources.minerals < next.minerals
                ? 'Nicht genug Rohstoffe.'
                : '';
  return (
    <section className="navigation-panel megastructure-panel" aria-label={definition.name}>
      <h3>{definition.name}</h3>
      <ol aria-label={`${definition.name}: Bauetappen`}>
        {definition.stages.map((stage, i) => (
          <li key={stage.name}>
            <strong>
              {i < level ? '✓ ' : ''}
              {stage.name}
            </strong>
            <small>
              {stage.energy} Energie · {stage.minerals} Mineralien · {stage.days} Tage
            </small>
            <small>
              {stage.output} {definition.resourceName} pro 4 Tage nach Abschluss dieser Etappe
            </small>
          </li>
        ))}
      </ol>
      {structure && !body.megastructure ? (
        <button onClick={() => onBody(structure.slot, true)}>{definition.name} verwalten</button>
      ) : site?.building ? (
        <p role="status">
          {next.name} im Bau · {Math.ceil(Math.max(0, site.finishAt - game.tick))} Tage verbleibend
        </p>
      ) : level >= 3 ? (
        <p>Vollständig ausgebaut · {megastructureStage(type, level)}</p>
      ) : (
        <>
          <button
            disabled={disabled || !!reason}
            onClick={() =>
              command(
                structure
                  ? { type: 'site_build', systemId: system.id, bodySlot: structure.slot, facility: type }
                  : {
                      type: 'megastructure_place',
                      systemId: system.id,
                      bodySlot: body.slot,
                      facility: type,
                    },
              )
            }
          >
            {next.name} bauen
          </button>
          <small>
            {reason || 'Schiff fliegt zuerst zum Bauplatz. Kosten bei Baustart; Abbruch erstattet 50 %.'}
          </small>
        </>
      )}
    </section>
  );
}
