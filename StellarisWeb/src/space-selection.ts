export type SpaceTarget = { kind: 'body'; slot: number } | { kind: 'fleet'; id: string };
export type SelectionMode = 'replace' | 'add' | 'toggle';
export const targetKey = (target: SpaceTarget) =>
  target.kind === 'body' ? `body:${target.slot}` : `fleet:${target.id}`;

export function selectTargets(
  current: readonly SpaceTarget[],
  incoming: readonly SpaceTarget[],
  mode: SelectionMode,
): SpaceTarget[] {
  const result = new Map((mode === 'replace' ? [] : current).map((target) => [targetKey(target), target]));
  for (const target of new Map(incoming.map((target) => [targetKey(target), target])).values()) {
    const key = targetKey(target);
    if (mode === 'toggle' && result.has(key)) result.delete(key);
    else result.set(key, target);
  }
  return [...result.values()];
}

export interface ScreenTarget {
  target: SpaceTarget;
  x: number;
  y: number;
  radius: number;
  depth: number;
}
export function nearbyTarget(targets: readonly ScreenTarget[], x: number, y: number) {
  let nearest: ScreenTarget | undefined;
  let distance = Infinity;
  for (const target of targets) {
    const candidate = Math.hypot(target.x - x, target.y - y);
    if (candidate > Math.max(14, target.radius + 5)) continue;
    if (candidate < distance || (candidate === distance && target.depth < nearest!.depth)) {
      nearest = target;
      distance = candidate;
    }
  }
  return nearest?.target;
}
export function targetsInBox(
  targets: readonly ScreenTarget[],
  x1: number,
  y1: number,
  x2: number,
  y2: number,
) {
  const left = Math.min(x1, x2),
    right = Math.max(x1, x2),
    top = Math.min(y1, y2),
    bottom = Math.max(y1, y2);
  return selectTargets(
    [],
    targets.filter((t) => t.x >= left && t.x <= right && t.y >= top && t.y <= bottom).map((t) => t.target),
    'replace',
  );
}
