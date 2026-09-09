import { useEffect, useLayoutEffect, useRef } from 'react';
import type { GameCommand, GameView, Fleet, StarSystem } from '../shared/game';
import {
  FACILITIES,
  facilitySpec,
  facilityFits,
  type CelestialBody,
  type Facility,
} from '../shared/celestial';
import { MEGASTRUCTURES, hostMegastructure, isMegastructure } from '../shared/megastructures';
import { bodyPosition, constructionFleet } from '../shared/navigation';
import type { SystemTarget } from './SystemSpaceScene';
import { colonizableBody } from '../shared/planetColonies';
import { MAX_FLEET_GROUP, type FleetGroupOrder } from '../shared/fleetGroups';

export function SystemContextMenu({
  target,
  x,
  y,
  game,
  system,
  bodies,
  fleet,
  groupCount,
  onGroupOrder,
  disabled,
  command,
  close,
  onBody,
  onFleet,
  onNavigate,
  onColony,
}: {
  target: SystemTarget;
  x: number;
  y: number;
  game: GameView;
  system: StarSystem;
  bodies: CelestialBody[];
  fleet?: Fleet;
  groupCount: number;
  onGroupOrder: (order: FleetGroupOrder) => void;
  disabled: boolean;
  command: (c: GameCommand) => void;
  close: () => void;
  onBody: (slot: number, project?: boolean) => void;
  onFleet: (id: string) => void;
  onNavigate: (id: string) => void;
  onColony: (objectId?: string) => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const previousFocus = useRef<Element | null>(null);
  useLayoutEffect(() => {
    previousFocus.current = document.activeElement;
    return () => {
      const previous = previousFocus.current;
      if (previous instanceof HTMLElement && previous.isConnected) previous.focus();
    };
  }, []);
  useLayoutEffect(() => {
    const el = ref.current!;
    const rect = el.getBoundingClientRect();
    el.style.left = `${Math.max(8, Math.min(x, window.innerWidth - rect.width - 8))}px`;
    el.style.top = `${Math.max(8, Math.min(y, window.innerHeight - rect.height - 8))}px`;
    el.querySelector<HTMLButtonElement>('button:not(:disabled)')?.focus();
  }, [x, y]);
  useEffect(() => {
    const outside = (e: PointerEvent) => {
      if (!ref.current?.contains(e.target as Node)) close();
    };
    const key = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        close();
      }
      if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(e.key)) {
        e.preventDefault();
        const buttons = [...ref.current!.querySelectorAll<HTMLButtonElement>('button:not(:disabled)')];
        const at = buttons.indexOf(document.activeElement as HTMLButtonElement);
        const next =
          e.key === 'Home'
            ? 0
            : e.key === 'End'
              ? buttons.length - 1
              : (at + (e.key === 'ArrowDown' ? 1 : -1) + buttons.length) % buttons.length;
        buttons[next]?.focus();
      }
    };
    document.addEventListener('pointerdown', outside);
    document.addEventListener('keydown', key);
    return () => {
      document.removeEventListener('pointerdown', outside);
      document.removeEventListener('keydown', key);
    };
  }, [close]);
  const body = target.kind === 'body' ? bodies.find((b) => b.slot === target.slot) : undefined;
  const targetFleet = target.kind === 'fleet' ? game.fleets.find((f) => f.id === target.id) : undefined;
  const destination = target.kind === 'exit' ? game.systems.find((s) => s.id === target.id) : undefined;
  const own = system.owner === game.me.id,
    surveyed = game.me.surveyed.includes(system.id);
  const localFleet =
    fleet?.owner === game.me.id && fleet.systemId === system.id && !fleet.route.length && !fleet.battleId
      ? fleet
      : undefined;
  const scout =
    (localFleet?.type === 'scout' ? localFleet : undefined) ||
    game.fleets.find(
      (f) =>
        f.owner === game.me.id &&
        f.systemId === system.id &&
        f.type === 'scout' &&
        !f.route.length &&
        !f.battleId,
    );
  const site = body && game.sites?.find((s) => s.systemId === system.id && s.bodySlot === body.slot);
  const builder = constructionFleet(game, system.id, fleet?.id);
  const planetColony =
    body && game.planetColonies?.find((c) => c.systemId === system.id && c.bodySlot === body.slot);
  const colonist =
    (localFleet?.type === 'colony' ? localFleet : undefined) ||
    game.fleets.find(
      (f) =>
        f.owner === game.me.id &&
        f.systemId === system.id &&
        f.type === 'colony' &&
        !f.route.length &&
        !f.battleId &&
        !f.task,
    );
  const allowed = surveyed && own;
  const run = (c: GameCommand) => {
    command(c);
    close();
  };
  const visit = (append: boolean) => {
    if (!body || !localFleet) return;
    const p = bodyPosition(body, bodies, game.tick);
    run({
      type: 'local_move',
      fleetId: localFleet.id,
      systemId: system.id,
      point: { ...p, x: p.x + body.radius + 25, y: Math.max(24, Math.min(400, p.y + body.radius)) },
      append,
    });
  };
  return (
    <div
      ref={ref}
      className="system-context-menu"
      role="menu"
      aria-label="Objektaktionen"
      style={{ left: x, top: y }}
      onContextMenu={(e) => e.preventDefault()}
    >
      <strong>{body?.name || targetFleet?.name || destination?.name || 'Systemobjekt'}</strong>
      {groupCount > 0 && (body || destination) && (
        <button
          role="menuitem"
          disabled={disabled || groupCount > MAX_FLEET_GROUP}
          onClick={(e) => {
            if (destination) onGroupOrder({ type: 'move', systemId: destination.id, append: e.shiftKey });
            else if (body) {
              const p = bodyPosition(body, bodies, game.tick);
              onGroupOrder({
                type: 'local_move',
                systemId: system.id,
                point: { ...p, x: p.x + body.radius + 25, y: Math.max(24, Math.min(400, p.y + body.radius)) },
                append: e.shiftKey,
              });
            }
            close();
          }}
        >
          {groupCount} Flotten {destination ? 'verlegen' : 'anfliegen lassen'}
          <small>Umschalt: anhängen</small>
        </button>
      )}
      <button
        role="menuitem"
        onClick={() => {
          if (body) onBody(body.slot);
          else if (targetFleet) onFleet(targetFleet.id);
          else if (destination) onNavigate(destination.id);
          close();
        }}
      >
        Details ansehen
      </button>
      {body && localFleet && !groupCount && (
        <>
          <button role="menuitem" disabled={disabled} onClick={(e) => visit(e.shiftKey)}>
            Anfliegen <small>Umschalt: anhängen</small>
          </button>
          <button role="menuitem" disabled={disabled} onClick={() => visit(true)}>
            Anflug anhängen
          </button>
        </>
      )}
      {destination && localFleet && !groupCount && (
        <button
          role="menuitem"
          disabled={disabled}
          onClick={() =>
            run({ type: 'move', fleetId: localFleet.id, systemId: destination.id, append: true })
          }
        >
          Reise anhängen
        </button>
      )}
      {surveyed && !system.owner && !system.starbase && body && (
        <button
          role="menuitem"
          disabled={disabled || system.defense > 0}
          onClick={() => run({ type: 'starbase_build', systemId: system.id })}
        >
          Außenposten errichten<small>100 Energie / 150 Mineralien · 24 T</small>
        </button>
      )}
      {body?.main && own && !system.colony && surveyed && (
        <button
          role="menuitem"
          disabled={disabled || !colonist}
          onClick={() => colonist && run({ type: 'colonize', fleetId: colonist.id })}
        >
          Hauptkolonie gründen
        </button>
      )}
      {!surveyed && body && (
        <button
          role="menuitem"
          disabled={disabled || !scout}
          onClick={() => scout && run({ type: 'scan', fleetId: scout.id, append: true })}
        >
          System erkunden{!scout && <small>Forschungsschiff vor Ort benötigt</small>}
        </button>
      )}
      {((body?.main && system.colony) || planetColony) && own && (
        <button
          role="menuitem"
          onClick={() => {
            onColony(planetColony?.objectId);
            close();
          }}
        >
          Kolonie verwalten
        </button>
      )}
      {body && own && surveyed && colonizableBody(body) && !planetColony && (
        <button
          role="menuitem"
          disabled={disabled || !colonist}
          onClick={() =>
            colonist &&
            run({
              type: 'colonize',
              fleetId: colonist.id,
              systemId: system.id,
              bodySlot: body.slot,
              append: true,
            })
          }
        >
          Planeten besiedeln
          <small>
            {colonist ? 'Anflug und Gründung · 80 Energie / 80 Mineralien' : 'Kolonieschiff vor Ort benötigt'}
          </small>
        </button>
      )}
      {body && hostMegastructure(body) && (
        <button
          role="menuitem"
          onClick={() => {
            onBody(body.slot, true);
            close();
          }}
        >
          {MEGASTRUCTURES[hostMegastructure(body)!].name} verwalten
        </button>
      )}
      {body &&
        (!site || site.owner === game.me.id) &&
        (site?.building ? (
          <button
            role="menuitem"
            disabled={disabled}
            onClick={() => run({ type: 'site_cancel', siteId: site.id })}
          >
            {FACILITIES[site.facility].name}: Bau abbrechen<small>50 % Kostenerstattung</small>
          </button>
        ) : (
          (Object.keys(FACILITIES) as Facility[])
            .filter((id) => facilityFits(id, body) && (!site || site.facility === id))
            .map((id) => {
              const spec = facilitySpec(id, site?.level || 0);
              const reason =
                isMegastructure(id) && !game.me.techs.includes('megastructures')
                  ? 'Megakonstruktion erforschen'
                  : !surveyed
                    ? 'System zuerst erkunden'
                    : !builder
                      ? 'Eigenes Schiff im System benötigt'
                      : !allowed
                        ? 'Eigenes System benötigt'
                        : (site?.level || 0) >= 3
                          ? 'Voll ausgebaut'
                          : game.me.resources.energy < spec.cost.energy ||
                              game.me.resources.minerals < spec.cost.minerals
                            ? 'Nicht genug Rohstoffe'
                            : '';
              const name = id === 'mine' ? 'Bergbaustation' : FACILITIES[id].name;
              return (
                <button
                  role="menuitem"
                  key={id}
                  disabled={disabled || !!reason}
                  onClick={() =>
                    run({ type: 'site_build', systemId: system.id, bodySlot: body.slot, facility: id })
                  }
                >
                  {isMegastructure(id) ? MEGASTRUCTURES[id].stages[Math.min(2, site?.level || 0)].name : name}{' '}
                  {site?.level ? 'ausbauen' : 'bauen'}
                  <small>
                    {reason ||
                      `${spec.cost.energy} Energie · ${spec.cost.minerals} Mineralien · ${spec.days} T`}
                  </small>
                  {!reason && <small>Anflug mit {builder?.name} · Kosten bei Baustart</small>}
                </button>
              );
            })
        ))}
      {site && site.owner !== game.me.id && <small>Die Anlage gehört einem anderen Reich.</small>}
      {targetFleet?.owner === game.me.id && (
        <button
          role="menuitem"
          disabled={disabled || !!targetFleet.battleId}
          onClick={() => run({ type: 'fleet_stop', fleetId: targetFleet.id })}
        >
          Stoppen und Warteschlange leeren
        </button>
      )}
      <button role="menuitem" onClick={close}>
        Schließen
      </button>
    </div>
  );
}
