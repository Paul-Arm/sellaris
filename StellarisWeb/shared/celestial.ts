import type { Resources, StarSystem } from './game';
import { type StellarProfile } from './stellar';
import type { Environment } from './empireCatalog';
import { MEGASTRUCTURES, isMegastructure, type Megastructure } from './megastructures';

export type BodyKind =
  'star' | 'planet' | 'moon' | 'gas' | 'asteroid' | 'ruin' | 'blackhole' | 'rift' | 'station';
export interface CelestialBody {
  megastructure?: Megastructure;
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
export type Facility = 'solar' | 'mine' | 'habitat' | 'research' | 'gas' | 'starbase' | Megastructure;
export const FACILITIES: Record<
  Facility,
  { name: string; description: string; kinds: BodyKind[]; cost: Resources; days: number; yield: Resources }
> = {
  decompressor: {
    name: 'Materiedekompressor',
    description: 'Drei Bauetappen erschließen Mineralien an einem Schwarzen Loch.',
    kinds: ['station'],
    cost: { energy: 500, minerals: 400, data: 0 },
    days: 60,
    yield: { energy: 0, minerals: 0, data: 0 },
  },
  dyson: {
    name: 'Dyson-Anlage',
    description: 'Drei Bauetappen erschließen die Energie eines Sterns.',
    kinds: ['station'],
    cost: { energy: 300, minerals: 500, data: 0 },
    days: 60,
    yield: { energy: 0, minerals: 0, data: 0 },
  },
  starbase: {
    name: 'Sternenbasis',
    description: 'Orbitaler Versorgungs- und Handelsstützpunkt am Stern.',
    kinds: ['star'],
    cost: { energy: 150, minerals: 180, data: 0 },
    days: 24,
    yield: { energy: 2, minerals: 2, data: 1 },
  },
  solar: {
    name: 'Sonnenkollektor',
    description: 'Orbitale Segel wandeln Sternenlicht in Energie um.',
    kinds: ['star'],
    cost: { energy: 60, minerals: 100, data: 0 },
    days: 16,
    yield: { energy: 5, minerals: 0, data: 0 },
  },
  mine: {
    name: 'Förderanlage',
    description: 'Automatisierter Abbau und Aufbereitung vor Ort.',
    kinds: ['asteroid', 'moon', 'planet', 'ruin'],
    cost: { energy: 70, minerals: 90, data: 0 },
    days: 16,
    yield: { energy: 0, minerals: 4, data: 0 },
  },
  habitat: {
    name: 'Außenposten',
    description: 'Geschützter Stützpunkt mit Versorgung und lokaler Industrie.',
    kinds: ['planet', 'moon', 'station'],
    cost: { energy: 90, minerals: 120, data: 0 },
    days: 20,
    yield: { energy: 2, minerals: 2, data: 1 },
  },
  research: {
    name: 'Forschungsstation',
    description: 'Analysiert Signale, Relikte und extreme Umgebungen.',
    kinds: ['planet', 'moon', 'ruin', 'blackhole', 'rift', 'station'],
    cost: { energy: 100, minerals: 90, data: 0 },
    days: 20,
    yield: { energy: 0, minerals: 0, data: 3 },
  },
  gas: {
    name: 'Atmosphärenkollektor',
    description: 'Schöpft energiereiche Gase aus der oberen Atmosphäre.',
    kinds: ['gas'],
    cost: { energy: 80, minerals: 110, data: 0 },
    days: 18,
    yield: { energy: 4, minerals: 1, data: 0 },
  },
};
export function facilitySpec(facility: Facility, level: number) {
  if (isMegastructure(facility)) {
    const stage = MEGASTRUCTURES[facility].stages[Math.min(2, Math.max(0, level))];
    return { cost: { energy: stage.energy, minerals: stage.minerals, data: 0 }, days: stage.days };
  }
  const d = FACILITIES[facility],
    m = 1 + level * 0.65;
  return {
    cost: { energy: Math.ceil(d.cost.energy * m), minerals: Math.ceil(d.cost.minerals * m), data: 0 },
    days: d.days + level * 8,
  };
}
export function facilityYield(facility: Facility, level: number, factor = 1): Resources {
  if (isMegastructure(facility)) {
    const spec = MEGASTRUCTURES[facility],
      result = { energy: 0, minerals: 0, data: 0 };
    result[spec.resource] = level > 0 ? spec.stages[Math.min(2, level - 1)].output * factor : 0;
    return result;
  }
  const r = FACILITIES[facility].yield;
  return {
    energy: r.energy * level * factor,
    minerals: r.minerals * level * factor,
    data: r.data * level * factor,
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
      type: 'megastructure_place';
      systemId: string;
      bodySlot: number;
      facility: Megastructure;
      fleetId?: string;
      append?: boolean;
    }
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

export function facilityFits(id: Facility, body: CelestialBody) {
  if (id === 'solar' && !['main', 'giant'].includes(body.stellar?.family || '')) return false;
  return body.megastructure
    ? id === body.megastructure
    : !isMegastructure(id) && FACILITIES[id].kinds.includes(body.kind);
}
