import type { CelestialBody } from './celestial';
import { stellarProfile } from './stellar';
import { PLANET_COLORS } from './terraforming';

export const STELLAR_COLLAPSE = {
  energy: 1200,
  minerals: 800,
  data: 400,
  days: 120,
  reward: 2500,
} as const;
export type StellarCommand =
  | { type: 'stellar_collapse'; systemId: string; objectId: string; revision: number }
  | { type: 'stellar_cancel'; jobId: number };
export interface StellarProject {
  id: number;
  systemId: string;
  remaining: number;
  total: number;
}

/** An engineered collapse preserves the star's identity and orbit. */
export function collapsedStar(body: CelestialBody): CelestialBody {
  const stellar = stellarProfile({ id: '', kind: 'star', class: 'NS', color: '#c4f3ff' });
  return {
    ...body,
    stellar,
    radius: stellar.radius,
    color: stellar.color,
    description:
      'Durch kontrollierten Kollaps entstandener Neutronenstern. Solare Anlagen sind hier nicht nutzbar.',
  };
}
export function frozenPlanet(body: CelestialBody): CelestialBody {
  return body.kind === 'planet' && body.environment
    ? {
        ...body,
        environment: 'arctic',
        color: PLANET_COLORS.arctic,
        description:
          'Arktische Welt. Nach dem Sternkollaps vereist; Bevölkerung und Infrastruktur bestehen fort.',
      }
    : body;
}
