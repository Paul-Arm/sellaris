import type { GameView } from '../shared/game';

const indices = new WeakMap<object, unknown>();
function cached<T>(rows: object, build: () => T): T {
  if (!indices.has(rows)) indices.set(rows, build());
  return indices.get(rows) as T;
}
const noSites: NonNullable<GameView['sites']> = [];
/** References are stable across time-only updates; build each index once per changed collection. */
export function gameIndices(game: GameView) {
  return {
    systems: cached(game.systems, () => new Map(game.systems.map((s) => [s.id, s]))),
    players: cached(game.players, () => new Map(game.players.map((p) => [p.id, p]))),
    fleetsBySystem: cached(game.fleets, () => {
      const groups = new Map<string, GameView['fleets']>();
      for (const fleet of game.fleets) {
        const rows = groups.get(fleet.systemId) ?? [];
        rows.push(fleet);
        groups.set(fleet.systemId, rows);
      }
      return groups;
    }),
    sites: cached(
      game.sites ?? noSites,
      () => new Map((game.sites ?? []).map((s) => [`${s.systemId}:${s.bodySlot}`, s])),
    ),
  };
}
