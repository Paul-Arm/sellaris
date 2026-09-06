export const GALAXY_TYPES = {
  spiral: { name: 'Spiralgalaxie', description: 'Zwei geschwungene Arme um einen dichten Kern.' },
  barred: {
    name: 'Balkenspirale',
    description: 'Ein länglicher Kern verbindet zwei auslaufende Spiralarme.',
  },
  elliptical: {
    name: 'Elliptische Galaxie',
    description: 'Eine weiche, ovale Verteilung mit dichtem Zentrum.',
  },
  ring: { name: 'Ringgalaxie', description: 'Ein breiter Sternenring um eine ruhige, leere Mitte.' },
} as const;
export const GALAXY_SIZES = [400, 700, 1000] as const;
export const HYPERLANE_DENSITIES = {
  sparse: { name: 'Wenige', description: 'Mehr Engpässe und längere Umwege.', edges: 1.15 },
  normal: { name: 'Standard', description: 'Ein ausgewogenes Netz mit alternativen Routen.', edges: 1.65 },
  dense: { name: 'Viele', description: 'Mehr Verbindungen und Ausweichrouten.', edges: 2.4 },
} as const;
export interface GalaxySettings {
  type: keyof typeof GALAXY_TYPES;
  systems: (typeof GALAXY_SIZES)[number];
  hyperlaneDensity: keyof typeof HYPERLANE_DENSITIES;
}
export const DEFAULT_GALAXY_SETTINGS: GalaxySettings = {
  type: 'spiral',
  systems: 1000,
  hyperlaneDensity: 'normal',
};
/** Validate before reserving a database or writing the creation registry. */
export function parseGalaxySettings(value: unknown): GalaxySettings {
  if (value === undefined) return { ...DEFAULT_GALAXY_SETTINGS };
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new Error('Ungültige Galaxieparameter.');
  const v = value as Record<string, unknown>;
  if (
    typeof v.type !== 'string' ||
    !Object.hasOwn(GALAXY_TYPES, v.type) ||
    !GALAXY_SIZES.includes(v.systems as GalaxySettings['systems']) ||
    typeof v.hyperlaneDensity !== 'string' ||
    !Object.hasOwn(HYPERLANE_DENSITIES, v.hyperlaneDensity)
  )
    throw new Error('Wähle einen Galaxietyp, 400, 700 oder 1.000 Systeme und eine Hyperlane-Dichte.');
  return { type: v.type, systems: v.systems, hyperlaneDensity: v.hyperlaneDensity } as GalaxySettings;
}
