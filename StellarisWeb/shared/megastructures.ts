import type { CelestialBody } from './celestial';

export const DYSON_STAGES = [
  { name: 'Orbitalgerüst', energy: 300, minerals: 500, days: 60, output: 0 },
  { name: 'Kollektorschwarm', energy: 800, minerals: 1200, days: 100, output: 30 },
  { name: 'Vollständiger Dyson-Schwarm', energy: 1600, minerals: 2400, days: 160, output: 90 },
] as const;

export const DECOMPRESSOR_STAGES = [
  { name: 'Gravitationsanker', energy: 500, minerals: 400, days: 60, output: 0 },
  { name: 'Extraktionsring', energy: 1400, minerals: 900, days: 100, output: 25 },
  { name: 'Vollständiger Materiedekompressor', energy: 2800, minerals: 1800, days: 160, output: 75 },
] as const;
export const MEGASTRUCTURES = {
  dyson: {
    name: 'Dyson-Anlage',
    stages: DYSON_STAGES,
    resource: 'energy',
    resourceName: 'Energie',
    color: '#d3c292',
    description:
      'Ein eigener Kollektorschwarm am Stern. Sternenbasis und planetare Sektoren bleiben nutzbar.',
    hostHint: 'Hauptreihenstern oder Riese benötigt.',
  },
  decompressor: {
    name: 'Materiedekompressor',
    stages: DECOMPRESSOR_STAGES,
    resource: 'minerals',
    resourceName: 'Mineralien',
    color: '#63e4d3',
    description:
      'Ein Extraktionsring erschließt Materie am Schwarzen Loch. Die Mineralienproduktion beginnt ab der zweiten Etappe. Eine Forschungsstation am Schwarzen Loch bleibt nutzbar.',
    hostHint: 'Ein ruhiges Schwarzes Loch benötigt; Quasare sind zu instabil.',
  },
} as const;
export type Megastructure = keyof typeof MEGASTRUCTURES;
export const isMegastructure = (value: string): value is Megastructure =>
  Object.hasOwn(MEGASTRUCTURES, value);
export function megastructureHost(type: Megastructure, body: CelestialBody) {
  return type === 'dyson'
    ? dysonHost(body)
    : body.kind === 'blackhole' && body.stellar?.family === 'blackhole';
}
export function hostMegastructure(body: CelestialBody): Megastructure | undefined {
  return (Object.keys(MEGASTRUCTURES) as Megastructure[]).find((type) => megastructureHost(type, body));
}
export function megastructureStage(type: Megastructure, level: number) {
  return level > 0 ? MEGASTRUCTURES[type].stages[Math.min(2, level - 1)].name : 'Baustelle';
}
/** All installations require territory secured by a starbase. */
export function megastructureTerritory(
  type: Megastructure,
  kind: string,
  owner: string | number | null,
  player: string | number,
) {
  return owner === player;
}

export function dysonHost(body: CelestialBody) {
  return body.kind === 'star' && !!body.stellar && ['main', 'giant'].includes(body.stellar.family);
}
