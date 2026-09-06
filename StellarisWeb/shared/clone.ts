/** Domain objects are JSON values. This also works in SpacetimeDB's JS runtime,
 * which does not expose the browser/Node structuredClone global. */
export function cloneData<T>(value: T): T {
  return JSON.parse(JSON.stringify(value));
}
