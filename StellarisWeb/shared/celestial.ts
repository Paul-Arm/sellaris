import type { Resources, StarSystem } from './game';
import { type StellarProfile } from './stellar';
import type { Environment } from './empireCatalog';

export type BodyKind =
  'star' | 'planet' | 'moon' | 'gas' | 'asteroid' | 'ruin' | 'blackhole' | 'rift' | 'station';
export interface CelestialBody {
  position?: import('./navigation').Point3;
  slot: number;
  name: string;
  kind: BodyKind;
  color: string;
  radius: number;
  orbit: number;
  phase: number;
  period: number;
  parent?: number;
  main?: boolean;
  description: string;
  stellar?: StellarProfile;
  environment?: Environment;
}
export const BODY_NAMES: Record<BodyKind, string> = {
  station: 'Raumstation',
  star: 'Stern',
  planet: 'Planet',
  moon: 'Mond',
  gas: 'Gasriese',
  asteroid: 'Asteroidenfeld',
  ruin: 'Orbitale Ruine',
  blackhole: 'Schwarzes Loch',
  rift: 'Raumzeitriss',
};
export function stableHash(text: string) {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619);
  return h >>> 0;
}
/** Rare, stable scenery; independent of names, ownership and the simulation clock. */
export function systemHasAsteroidBelt(system: Pick<StarSystem, 'id'>): boolean {
  return stableHash(`${system.id}:asteroid-belt`) % 100 < 8;
}
// Generation is only used when a new world is created.
export { generateSystemBodies as systemBodies } from './systemGeneration';
export type Facility = 'solar' | 'mine' | 'habitat' | 'research' | 'gas' | 'starbase';
export const FACILITIES: Record<
  Facility,
  { name: string; description: string; kinds: BodyKind[]; cost: Resources; days: number; yield: Resources }
> = {
  starbase: {
    name: 'Sternenbasis',
    description: 'Orbitaler Versorgungs- und Handelsstützpunkt am Stern.',
    kinds: ['star'],
    cost: { energy: 150, minerals: 180, science: 0 },
    days: 24,
    yield: { energy: 2, minerals: 2, science: 1 },
  },
  solar: {
    name: 'Sonnenkollektor',
    description: 'Orbitale Segel wandeln Sternenlicht in Energie um.',
    kinds: ['star'],
    cost: { energy: 60, minerals: 100, science: 0 },
    days: 16,
    yield: { energy: 5, minerals: 0, science: 0 },
  },
  mine: {
    name: 'Förderanlage',
    description: 'Automatisierter Abbau und Aufbereitung vor Ort.',
    kinds: ['asteroid', 'moon', 'planet', 'ruin'],
    cost: { energy: 70, minerals: 90, science: 0 },
    days: 16,
    yield: { energy: 0, minerals: 4, science: 0 },
  },
  habitat: {
    name: 'Außenposten',
    description: 'Geschützter Stützpunkt mit Versorgung und lokaler Industrie.',
    kinds: ['planet', 'moon', 'station'],
    cost: { energy: 90, minerals: 120, science: 0 },
    days: 20,
    yield: { energy: 2, minerals: 2, science: 1 },
  },
  research: {
    name: 'Forschungsstation',
    description: 'Analysiert Signale, Relikte und extreme Umgebungen.',
    kinds: ['planet', 'moon', 'ruin', 'blackhole', 'rift', 'station'],
    cost: { energy: 100, minerals: 90, science: 0 },
    days: 20,
    yield: { energy: 0, minerals: 0, science: 3 },
  },
  gas: {
    name: 'Atmosphärenkollektor',
    description: 'Schöpft energiereiche Gase aus der oberen Atmosphäre.',
    kinds: ['gas'],
    cost: { energy: 80, minerals: 110, science: 0 },
    days: 18,
    yield: { energy: 4, minerals: 1, science: 0 },
  },
};
export function facilitySpec(facility: Facility, level: number) {
  const d = FACILITIES[facility],
    m = 1 + level * 0.65;
  return {
    cost: { energy: Math.ceil(d.cost.energy * m), minerals: Math.ceil(d.cost.minerals * m), science: 0 },
    days: d.days + level * 8,
  };
}
export function facilityYield(facility: Facility, level: number, factor = 1): Resources {
  const r = FACILITIES[facility].yield;
  return {
    energy: r.energy * level * factor,
    minerals: r.minerals * level * factor,
    science: r.science * level * factor,
  };
}
export interface BodySite {
  id: string;
  systemId: string;
  bodySlot: number;
  owner: string;
  facility: Facility;
  level: number;
  building: boolean;
  startedAt: number;
  finishAt: number;
  suspended: boolean;
}
export type SiteCommand =
  | {
      type: 'station_place';
      fleetId?: string;
      append?: boolean;
      systemId: string;
      point: import('./navigation').Point3;
      facility: 'habitat' | 'research';
    }
  | {
      type: 'site_build';
      systemId: string;
      bodySlot: number;
      facility: Facility;
      fleetId?: string;
      append?: boolean;
    }
  | { type: 'site_cancel'; siteId: string };
