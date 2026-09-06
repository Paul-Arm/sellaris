// Current generation rules; old worlds do not constrain this generator.
import type { StarSystem } from './game';
import type { CelestialBody, BodyKind } from './celestial';
import { stellarProfile } from './stellar';
import { environmentForPlanet } from './empires';
import { ENVIRONMENTS, type Environment } from './empireCatalog';
import { PLANET_COLORS } from './terraforming';
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
export function generateSystemBodies(
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
    const environment: Environment | undefined =
      kind === 'planet'
        ? extra.main
          ? environmentForPlanet(s.planet)
          : slot === 3
            ? 'arid'
            : 'arctic'
        : undefined;
    return {
      slot,
      name,
      kind,
      orbit: distance,
      radius,
      color: environment ? PLANET_COLORS[environment] : color,
      description: environment
        ? `${ENVIRONMENTS[environment].name}.${extra.main ? ' Die Hauptwelt des Systems.' : ' Ein Planet mit veränderbarem Klima.'}`
        : description,
      ...(environment ? { environment } : {}),
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
