import type { Resources, StarSystem } from './game';
import { stellarProfile, type StellarProfile } from './stellar';

export type BodyKind = 'star' | 'planet' | 'moon' | 'gas' | 'asteroid' | 'ruin' | 'blackhole' | 'rift';
export interface CelestialBody {
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
}
export const BODY_NAMES: Record<BodyKind, string> = {
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
/** Orbital atlas. Slots are durable build addresses; never reorder/reuse them. */
export function systemBodies(
  s: Pick<StarSystem, 'id' | 'name' | 'kind' | 'class' | 'color' | 'planet' | 'colonyName'>,
): CelestialBody[] {
  const seed = stableHash(s.id),
    sol = s.name === 'Sol',
    belt = systemHasAsteroidBelt(s);
  const phase = (slot: number) => (stableHash(`${seed}:${slot}`) % 6283) / 1000;
  const body = (
    slot: number,
    name: string,
    kind: BodyKind,
    orbit: number,
    radius: number,
    color: string,
    description: string,
    extra: Partial<CelestialBody> = {},
  ): CelestialBody => {
    // Spread primary orbits across the sheet while keeping moons near their parent.
    const distance = orbit > 0 && extra.parent === undefined ? 200 + orbit * 1.9 : orbit;
    return {
      slot,
      name,
      kind,
      orbit: distance,
      radius,
      color,
      description,
      phase: phase(slot),
      period: 1600 + distance * 9,
      ...extra,
    };
  };
  const profile = stellarProfile(s);
  const core = body(0, s.name, s.kind, 0, profile.radius, profile.color, profile.description, {
    stellar: profile,
  });
  if (s.kind !== 'star')
    return [
      core,
      body(
        4,
        belt ? 'Trümmerwolke' : 'Trümmerfragment',
        'asteroid',
        165,
        16,
        '#b9cbd8',
        belt
          ? 'Eine seltene, lockere Wolke gebundener Körper und metallhaltigen Materials.'
          : 'Ein kleiner, gebundener Verband metallhaltiger Fragmente.',
      ),
      body(
        7,
        'Verlorenes Observatorium',
        'ruin',
        280,
        14,
        '#78c6c0',
        'Eine aufgegebene Plattform am Rand der gravitativen Scherung.',
      ),
      body(
        8,
        'Eisfragment',
        'moon',
        370,
        12,
        '#9fbbcd',
        'Ein kalter, eingefangener Körper mit stabiler Oberfläche.',
      ),
    ];
  return [
    core,
    body(
      1,
      s.colonyName || (sol ? 'Erde' : `${s.name} Prime`),
      'planet',
      138,
      20,
      '#70a2af',
      `${s.planet}. Die Hauptwelt des Systems.`,
      { main: true },
    ),
    body(
      2,
      sol ? 'Luna' : 'Selene',
      'moon',
      35,
      7,
      '#b8babd',
      'Regolith und Silikate. Geeignet für geschützte Außenposten.',
      { parent: 1, period: 480 },
    ),
    body(
      3,
      sol ? 'Mars' : `${s.name} II`,
      'planet',
      222,
      14,
      '#bc7958',
      'Eine felsige Welt mit eisenreichen Ebenen und dünner Atmosphäre.',
    ),
    body(
      4,
      belt ? (sol ? 'Ceres-Wolke' : 'Metallwolke') : sol ? 'Ceres' : 'Metallfragment',
      'asteroid',
      287,
      15,
      '#bdcfda',
      belt
        ? 'Eine seltene, lockere Wolke mineralreicher Körper mit ergiebigen Metalladern.'
        : 'Ein kompakter Verband mineralreicher Fragmente.',
    ),
    body(
      5,
      sol ? 'Jupiter' : `${s.name} III`,
      'gas',
      366,
      28,
      '#c1ad89',
      'Bänder aus Wasserstoff und Helium. Orbitale Kollektoren erschließen die Gase.',
    ),
    body(
      6,
      sol ? 'Europa' : 'Neris',
      'moon',
      43,
      8,
      '#a2c3cd',
      'Unter dem Eis liegt ein abgeschirmter Ozean.',
      { parent: 5, period: 680 },
    ),
    body(
      7,
      'Verlassenes Relais',
      'ruin',
      440,
      13,
      '#79bcb2',
      'Ein zerbrochener Orbitalring. Seine Archive und Werkstoffe können erschlossen werden.',
    ),
    body(
      8,
      sol ? 'Neptun' : `${s.name} IV`,
      'planet',
      508,
      16,
      '#597fbd',
      'Eine kalte äußere Welt. Automatisierte Stationen trotzen der Entfernung.',
    ),
  ];
}
export type Facility = 'solar' | 'mine' | 'habitat' | 'research' | 'gas';
export const FACILITIES: Record<
  Facility,
  { name: string; description: string; kinds: BodyKind[]; cost: Resources; seconds: number; yield: Resources }
> = {
  solar: {
    name: 'Sonnenkollektor',
    description: 'Orbitale Segel wandeln Sternenlicht in Energie um.',
    kinds: ['star'],
    cost: { energy: 60, minerals: 100, science: 0 },
    seconds: 16,
    yield: { energy: 5, minerals: 0, science: 0 },
  },
  mine: {
    name: 'Förderanlage',
    description: 'Automatisierter Abbau und Aufbereitung vor Ort.',
    kinds: ['asteroid', 'moon', 'planet', 'ruin'],
    cost: { energy: 70, minerals: 90, science: 0 },
    seconds: 16,
    yield: { energy: 0, minerals: 4, science: 0 },
  },
  habitat: {
    name: 'Außenposten',
    description: 'Geschützter Stützpunkt mit Versorgung und lokaler Industrie.',
    kinds: ['planet', 'moon'],
    cost: { energy: 90, minerals: 120, science: 0 },
    seconds: 20,
    yield: { energy: 2, minerals: 2, science: 1 },
  },
  research: {
    name: 'Forschungsstation',
    description: 'Analysiert Signale, Relikte und extreme Umgebungen.',
    kinds: ['planet', 'moon', 'ruin', 'blackhole', 'rift'],
    cost: { energy: 100, minerals: 90, science: 0 },
    seconds: 20,
    yield: { energy: 0, minerals: 0, science: 3 },
  },
  gas: {
    name: 'Atmosphärenkollektor',
    description: 'Schöpft energiereiche Gase aus der oberen Atmosphäre.',
    kinds: ['gas'],
    cost: { energy: 80, minerals: 110, science: 0 },
    seconds: 18,
    yield: { energy: 4, minerals: 1, science: 0 },
  },
};
export function facilitySpec(facility: Facility, level: number) {
  const d = FACILITIES[facility],
    m = 1 + level * 0.65;
  return {
    cost: { energy: Math.ceil(d.cost.energy * m), minerals: Math.ceil(d.cost.minerals * m), science: 0 },
    seconds: d.seconds + level * 8,
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
  | { type: 'site_build'; systemId: string; bodySlot: number; facility: Facility }
  | { type: 'site_cancel'; siteId: string };
