import type { CelestialBody } from './celestial';
import type { Colony } from './colonies';
import type { GameView, StarSystem } from './game';
import { ENVIRONMENTS } from './empireCatalog';

export interface PlanetColony {
  objectId: string;
  systemId: string;
  bodySlot: number;
  name: string;
  planet: string;
  colony: Colony;
}
export function colonizableBody(body: CelestialBody): boolean {
  return !body.main && body.kind === 'planet' && !!body.environment;
}
export function colonyPlanet(body: CelestialBody): string {
  return body.environment ? ENVIRONMENTS[body.environment].name : body.description;
}
export function planetWorld(system: StarSystem, colony: PlanetColony): StarSystem {
  return {
    ...system,
    planet: colony.planet,
    colony: colony.colony,
    colonyName: colony.name,
    mined: false,
    planetDefense: 0,
  };
}
export function ownedColonyWorlds(game: GameView) {
  const bySystem = new Map<string, PlanetColony[]>();
  for (const colony of game.planetColonies || []) {
    const group = bySystem.get(colony.systemId);
    if (group) group.push(colony);
    else bySystem.set(colony.systemId, [colony]);
  }
  return game.systems
    .filter((s) => s.owner === game.me.id)
    .flatMap((s) => [
      ...(s.colony ? [{ ...s, worldId: s.id, bodySlot: undefined as number | undefined }] : []),
      ...(bySystem.get(s.id) || [])
        .map((c) => ({
          ...planetWorld(s, c),
          worldId: c.objectId,
          bodySlot: c.bodySlot,
        })),
    ]);
}
