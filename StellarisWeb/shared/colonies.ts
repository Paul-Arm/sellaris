import type { GameState, Player, Resources, StarSystem } from './game';
import { colonyModifiers, type PopulationGroup } from './empireState';
import { environmentForPlanet } from './empires';

export type BuildingId = 'reactor' | 'foundry' | 'laboratory' | 'bastion';
export type ColonyFocus = 'balanced' | 'energy' | 'minerals' | 'science';
export interface Colony {
  population: number;
  populations?: PopulationGroup[];
  focus: ColonyFocus;
  buildings: Record<BuildingId, number>;
  construction: {
    building: BuildingId;
    remaining: number;
    total: number;
    cost: Resources;
  } | null;
}
export const BUILDINGS: Record<
  BuildingId,
  {
    name: string;
    field: string;
    description: string;
    yield: Resources;
    cost: Resources;
    time: number;
    maxLevel: number;
  }
> = {
  reactor: {
    name: 'Fusionsreaktor',
    field: 'ENERGIE',
    description: '+4 Energie pro Zyklus und Stufe.',
    yield: { energy: 4, minerals: 0, science: 0 },
    cost: { energy: 50, minerals: 100, science: 0 },
    time: 16,
    maxLevel: 3,
  },
  foundry: {
    name: 'Orbitalindustrie',
    field: 'INDUSTRIE',
    description: '+4 Mineralien pro Zyklus und Stufe.',
    yield: { energy: 0, minerals: 4, science: 0 },
    cost: { energy: 80, minerals: 80, science: 0 },
    time: 18,
    maxLevel: 3,
  },
  laboratory: {
    name: 'Quantenlabor',
    field: 'WISSENSCHAFT',
    description: '+3 Forschung pro Zyklus und Stufe.',
    yield: { energy: 0, minerals: 0, science: 3 },
    cost: { energy: 90, minerals: 120, science: 0 },
    time: 22,
    maxLevel: 3,
  },
  bastion: {
    name: 'Schildbastion',
    field: 'VERTEIDIGUNG',
    description: '+40 Verteidigung und schnellere Schiffsreparatur pro Stufe.',
    yield: { energy: 0, minerals: 0, science: 0 },
    cost: { energy: 60, minerals: 120, science: 0 },
    time: 20,
    maxLevel: 3,
  },
};
export const FOCUSES: Record<ColonyFocus, { name: string; description: string }> = {
  balanced: { name: 'Ausgewogen', description: 'Alle Erträge bei 100 %.' },
  energy: { name: 'Energie', description: '+40 % Energie · −15 % Mineralien und Forschung.' },
  minerals: { name: 'Industrie', description: '+40 % Mineralien · −15 % Energie und Forschung.' },
  science: { name: 'Forschung', description: '+40 % Forschung · −15 % Energie und Mineralien.' },
};
export function createColony(capital = false): Colony {
  return {
    population: capital ? 6 : 2,
    focus: 'balanced',
    buildings: { reactor: 0, foundry: 0, laboratory: 0, bastion: 0 },
    construction: null,
  };
}
/** Additive save migration: preserves IDs, resources, orders and existing sessions. */
export function hydrateColonies(game: GameState) {
  for (const system of game.systems) {
    if (system.colony === undefined) {
      system.colony = system.owner
        ? createColony(game.players.some((p) => p.id === system.owner && p.home === system.id))
        : null;
    }
  }
}
export function districtCapacity(colony: Colony) {
  return Math.min(10, 4 + Math.floor(colony.population / 2));
}
export function occupiedDistricts(colony: Colony) {
  return Object.values(colony.buildings).reduce((sum, n) => sum + n, 0);
}
export function upgradeSpec(colony: Colony, building: BuildingId) {
  const spec = BUILDINGS[building],
    level = colony.buildings[building];
  const multiplier = 1 + level * 0.65;
  return {
    cost: {
      energy: Math.ceil(spec.cost.energy * multiplier),
      minerals: Math.ceil(spec.cost.minerals * multiplier),
      science: 0,
    },
    time: spec.time + level * 8,
  };
}
export function colonyProduction(system: StarSystem, player: Pick<Player, 'techs' | 'empire'>): Resources {
  const output: Resources = {
    energy: system.resources.energy * (system.mined ? 2 : 1),
    minerals: system.resources.minerals * (system.mined ? 2 : 1),
    science: system.resources.science,
  };
  const colony = system.colony;
  if (colony) {
    for (const id of Object.keys(BUILDINGS) as BuildingId[]) {
      for (const key of Object.keys(output) as (keyof Resources)[])
        output[key] += BUILDINGS[id].yield[key] * colony.buildings[id];
    }
    if (colony.focus !== 'balanced') {
      for (const key of Object.keys(output) as (keyof Resources)[])
        output[key] *= colony.focus === key ? 1.4 : 0.85;
    }
  }
  if (player.techs.includes('extraction')) {
    output.energy *= 1.5;
    output.minerals *= 1.5;
  }
  const modifiers = colonyModifiers(player.empire, colony?.populations, environmentForPlanet(system.planet));
  for (const key of Object.keys(output) as (keyof Resources)[])
    output[key] *= Math.max(0.1, 1 + modifiers[key]) * (system.productionFactor ?? 1);
  return output;
}
export function baseIncome(player: Pick<Player, 'techs'>): Resources {
  return player.techs.includes('extraction')
    ? { energy: 3, minerals: 1.5, science: 1 }
    : { energy: 2, minerals: 1, science: 1 };
}
export function maxDefense(system: StarSystem) {
  return 30 + (system.colony?.buildings.bastion || 0) * 40;
}
