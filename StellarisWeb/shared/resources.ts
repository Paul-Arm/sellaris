/** Resource identity, labels and defaults live here. Rates are per 30-day month. */
export const RESOURCE_CATALOG = {
  energy: { name: 'Energie', color: '#efc46b', icon: 'Zap', base: 2 },
  minerals: { name: 'Mineralien', color: '#ed8d78', icon: 'Diamond', base: 1 },
  data: { name: 'Daten', color: '#84b9ed', icon: 'FlaskConical', base: 1 },
  unity: { name: 'Einigkeit', color: '#c5a1ed', icon: 'Users', base: 0 },
} as const;
export type Resource = keyof typeof RESOURCE_CATALOG;
/** Sparse content definitions may omit zero-valued resources. Use resourceAmounts at boundaries. */
export type Resources = Record<string, number>;
export const RESOURCE_IDS = Object.keys(RESOURCE_CATALOG) as Resource[];
export const RESOURCE_NAMES = Object.fromEntries(
  RESOURCE_IDS.map((id) => [id, RESOURCE_CATALOG[id].name]),
) as Record<Resource, string>;
export function resourceAmounts(
  values: Partial<Record<Resource, number>> = {},
): Record<Resource, number> & Resources {
  return Object.fromEntries(RESOURCE_IDS.map((id) => [id, values[id] ?? 0])) as Record<Resource, number> &
    Resources;
}
export function addResources(target: Resources, values: Partial<Resources>, factor = 1) {
  for (const id of RESOURCE_IDS) target[id] = (target[id] ?? 0) + (values[id] ?? 0) * factor;
  return target;
}
