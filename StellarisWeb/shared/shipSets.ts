/** Visual identity only; selecting a set never changes simulation stats. */
export const SHIP_SETS = {
  prisma: { name: 'PRISMA', description: 'Helle Keramik, kantige Gürtel und cyanblaue Energie.' },
  aureole: { name: 'AUREOLE', description: 'Elfenbeinfarbene Sicheln, Goldfassungen und warme Amberkerne.' },
  bastion: { name: 'BASTION', description: 'Massive Panzerung und magentafarbene Reaktoren.' },
  parallax: {
    name: 'PARALLAX',
    description: 'Obsidianfragmente, roséfarbene Schneiden und mintfarbene Gravitationsfelder.',
  },
  nexus: { name: 'NEXUS', description: 'Blaue Energiekerne in offenen Ringen und Käfigen.' },
  vektor: { name: 'VEKTOR', description: 'Irisierende Kristallklingen und eisblaue Lichtspalten.' },
} as const;

export type ShipSet = keyof typeof SHIP_SETS;
export const SHIP_SET_IDS = Object.keys(SHIP_SETS) as ShipSet[];

export function isShipSet(value: unknown): value is ShipSet {
  return typeof value === 'string' && Object.hasOwn(SHIP_SETS, value);
}

export function shipSetFor(design?: { shipSet?: ShipSet }): ShipSet {
  return isShipSet(design?.shipSet) ? design.shipSet : 'prisma';
}
