import type { AdminMatch } from '../shared/admin';
import type { EmpireState } from '../shared/empireState';

type Query = (database: string, query: string) => Promise<unknown[][]>;
export async function inspectMatch(code: string, database: string, rows: Query): Promise<AdminMatch> {
  const [
    stars,
    lanes,
    summaries,
    players,
    resources,
    presence,
    settings,
    colonies,
    fleets,
    meta,
    relations,
    clocks,
  ] = await Promise.all([
    rows(database, 'SELECT id, name, x, y, kind, owner_id FROM star'),
    rows(database, 'SELECT a, b FROM game_lane'),
    rows(database, 'SELECT id, name, color, ai FROM empire_summary'),
    rows(database, 'SELECT id, home_id, techs, surveyed, empire_json FROM game_player'),
    rows(database, 'SELECT id, energy, minerals, data FROM empire'),
    rows(database, 'SELECT id, online FROM game_presence'),
    rows(database, 'SELECT host_id FROM game_settings'),
    rows(database, 'SELECT id, empire_id, population, energy_rate, minerals_rate, data_rate FROM colony'),
    rows(
      database,
      'SELECT id, empire_id, name, system_id, ship_count, "order", battle_id, from_x, from_y, to_x, to_y, departed_at, arrives_at FROM fleet',
    ),
    rows(database, 'SELECT id, planet, colony_name FROM game_system'),
    rows(database, 'SELECT empire_a, empire_b, state FROM game_relation'),
    rows(database, 'SELECT game_time, wall_time, speed, paused FROM clock'),
  ]);
  const metadata = new Map(meta.map((r) => [Number(r[0]), r]));
  const systems = stars.map(([id, name, x, y, kind, ownerId]) => ({
    id: Number(id),
    name: String(name),
    x: Number(x),
    y: Number(y),
    kind: String(kind),
    ownerId: Number(ownerId),
    planet: String(metadata.get(Number(id))?.[1] ?? ''),
    colonyName: String(metadata.get(Number(id))?.[2] ?? ''),
  }));
  const byId = new Map(systems.map((s) => [s.id, s]));
  const [time, wall, speed, paused] = clocks[0];
  const now = Number(time) + (paused ? 0 : Math.max(0, Date.now() / 1000 - Number(wall)) * Number(speed));
  return {
    code,
    updatedAt: new Date().toISOString(),
    systems,
    lanes: lanes.map(([a, b]) => ({ a: Number(a), b: Number(b) })),
    relations: relations.map(([a, b, state]) => ({ a: Number(a), b: Number(b), state: String(state) })),
    empires: summaries.map(([id, name, color, ai]) => {
      const player = players.find((p) => p[0] === id)!;
      const economy = resources.find((p) => p[0] === id)!;
      const empire = JSON.parse(String(player[4])) as EmpireState;
      return {
        id: Number(id),
        name: String(name),
        color: `#${Number(color).toString(16).padStart(6, '0')}`,
        ai: Boolean(ai),
        online: !ai && presence.some(([p, online]) => p === id && online === true),
        host: settings[0][0] === id,
        homeId: Number(player[1]),
        energy: Number(economy[1]),
        minerals: Number(economy[2]),
        data: Number(economy[3]),
        techs: player[2] as string[],
        surveyed: (player[3] as number[]).length,
        design: empire.design,
        species: empire.species.map(
          ({ name, plural, adjective, kind, portrait, environment, traits, description, lore }) => ({
            name,
            plural,
            adjective,
            kind,
            portrait,
            environment,
            traits,
            description,
            lore,
          }),
        ),
        colonies: colonies
          .filter((c) => c[1] === id)
          .map(([system, , population, energy, minerals, data]) => ({
            id: Number(system),
            name: byId.get(Number(system))?.colonyName || byId.get(Number(system))?.name || String(system),
            population: Number(population) / 1000000,
            energy: Number(energy),
            minerals: Number(minerals),
            data: Number(data),
          })),
      };
    }),
    fleets: fleets.map(
      ([id, empireId, name, systemId, ships, order, battleId, fromX, fromY, toX, toY, departed, arrives]) => {
        const system = byId.get(Number(systemId));
        const progress = Math.max(
          0,
          Math.min(1, (now - Number(departed)) / Math.max(0.001, Number(arrives) - Number(departed))),
        );
        return {
          id: Number(id),
          empireId: Number(empireId),
          name: String(name),
          systemId: Number(systemId),
          ships: Number(ships),
          order: String(order),
          battleId: Number(battleId),
          x: system?.x ?? Number(fromX) + (Number(toX) - Number(fromX)) * progress,
          y: system?.y ?? Number(fromY) + (Number(toY) - Number(fromY)) * progress,
        };
      },
    ),
  };
}
