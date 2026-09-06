import type { CelestialBody } from './celestial';

export interface SystemObject {
  id: string;
  systemId: number;
  slot: number;
  revision: number;
  state: string;
  changedAt: number;
  parentId: string;
  bodyJson: string;
}
export interface StoredBody extends CelestialBody {
  objectId: string;
  revision: number;
}
export function objectBodies(rows: Iterable<SystemObject>): StoredBody[] {
  return [...rows]
    .filter((row) => row.state === 'active')
    .sort((a, b) => a.slot - b.slot)
    .map((row) => ({
      ...JSON.parse(row.bodyJson),
      slot: row.slot,
      objectId: row.id,
      revision: row.revision,
    }));
}
// Gravity is a rendering budget, never a limit on persistent objects.
export function gravitySlots(bodies: CelestialBody[], limit = 10): Map<number, number> {
  return new Map(
    bodies
      .filter((b) => b.kind !== 'asteroid' && b.kind !== 'station')
      .sort((a, b) => Number(!!b.stellar) - Number(!!a.stellar) || b.radius - a.radius || a.slot - b.slot)
      .slice(0, limit)
      .map((body, index) => [body.slot, index]),
  );
}
