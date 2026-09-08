import { starbaseLedger } from './starbases';
import { optimizeProduction } from './compute';
import type { GameState, GameView, Player } from './game';
import { baseLedger, colonyLedger, colonyEconomy } from './planetaryEconomy';
import { planetWorld } from './planetColonies';
import { facilityLedger, FACILITIES } from './celestial';
import { stellarWeatherFactor } from './stellarWeather';
import { baseCompute, researchAllocation } from './research';
import { governmentModifiers } from './empires';
import { economyLine, modifyEconomy, type EconomyLine } from './economy';

type EconomyWorld = Pick<GameState, 'systems'> & Partial<Pick<GameView, 'planetColonies' | 'sites' | 'tick'>>;
export function empireCompute(game: EconomyWorld, player: Player) {
  const government = player.empire
    ? governmentModifiers(player.empire.design.government, player.empire.design.origin).research
    : 0;
  let compute = modifyEconomy(
    baseCompute(player.techs) * Math.max(0, 1 + government),
    player.empire?.economyModifiers ?? [],
    { category: 'compute' },
  ).amount;
  const systems = new Map(game.systems.filter((s) => s.owner === player.id).map((s) => [s.id, s]));
  for (const s of systems.values())
    if (s.colony) compute += colonyEconomy(s.colony, s.planet, player).compute;
  for (const c of game.planetColonies ?? [])
    if (systems.has(c.systemId)) compute += colonyEconomy(c.colony, c.planet, player).compute;
  return compute;
}
/** The same source lines feed the topbar, detailed balances and monthly resource totals. */
export function empireLedger(game: EconomyWorld, player: Player): EconomyLine[] {
  player = { ...player, compute: player.compute ?? empireCompute(game, player) };
  const lines = baseLedger(player);
  const byId = new Map(game.systems.map((system) => [system.id, system]));
  const systems = new Map(game.systems.filter((s) => s.owner === player.id).map((s) => [s.id, s]));
  for (const system of systems.values())
    lines.push(...colonyLedger(system, player), ...starbaseLedger(system));
  for (const colony of game.planetColonies ?? []) {
    const system = systems.get(colony.systemId);
    if (system) lines.push(...colonyLedger(planetWorld(system, colony), player));
  }
  const modifiers = player.empire?.economyModifiers ?? [];
  const production =
    player.productionFactor ?? Math.min(1, ...[...systems.values()].map((s) => s.productionFactor ?? 1));
  for (const site of game.sites ?? []) {
    if (site.owner !== player.id || site.suspended) continue;
    const system = byId.get(site.systemId);
    lines.push(
      ...optimizeProduction(
        facilityLedger(
          site.facility,
          site.level,
          modifiers,
          production,
          stellarWeatherFactor(site.facility, system?.stellarWeather, game.tick ?? 0),
          site.id,
          `${system?.name ?? site.systemId} · ${FACILITIES[site.facility].name}`,
        ),
        player,
      ).map((line) => ({ ...line, systemId: site.systemId })),
    );
  }
  const compute = player.compute ?? empireCompute(game, player);
  const synthesis = researchAllocation(player.research, player.techs, compute).data;
  lines.push(
    economyLine('synthesis', 'Datensynthese', synthesis, modifiers, {
      category: 'synthesis',
      resource: 'data',
    }),
  );
  return lines;
}
