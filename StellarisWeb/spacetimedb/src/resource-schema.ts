import { t } from 'spacetimedb/server';
import { RESOURCE_IDS, type Resource } from '../../shared/resources';

/** Adding a catalog entry also adds its authoritative storage/transport field. */
export function resourceFields() {
  return Object.fromEntries(RESOURCE_IDS.map((id) => [id, t.f64()])) as Record<
    Resource,
    ReturnType<typeof t.f64>
  >;
}
