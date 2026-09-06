import { PORTAL_TAIL_END, SPACETIME_RADIUS } from './spacetime-surface';

/** A fixed galactic bearing at both ends, with a shallow bow beyond the throat. */
export function hyperlanePath(radius: number, direction: { x: number; z: number }, turn = 1) {
  const magnitude = Math.hypot(direction.x, direction.z);
  if (magnitude < 1e-8 || radius <= 0) throw new Error('Hyperlane needs a radius and a bearing');
  const dx = direction.x / magnitude,
    dz = direction.z / magnitude;
  const straight = PORTAL_TAIL_END + 40;
  const endRadius = Math.max(SPACETIME_RADIUS * 1.55, radius + straight + 200);
  const span = endRadius - radius,
    curveLength = span - straight;
  const amplitude = Math.sign(turn) * Math.min(60, curveLength * 0.075);
  const segments = Math.ceil(span / 6);
  let length = 0;
  const points: { x: number; z: number; along: number; travel: number; tx: number; tz: number }[] = [];
  for (let i = 0; i <= segments; i++) {
    const along = (i * span) / segments;
    const t = Math.max(0, Math.min(1, (along - straight) / curveLength));
    // Zero slope and curvature at both joins keep the straight throat and final bearing intact.
    const bow = amplitude * 64 * t ** 3 * (1 - t) ** 3;
    const slope = (amplitude * 192 * t ** 2 * (1 - t) ** 2 * (1 - 2 * t)) / curveLength;
    const x = dx * (radius + along) - dz * bow;
    const z = dz * (radius + along) + dx * bow;
    if (i) length += Math.hypot(x - points[i - 1].x, z - points[i - 1].z);
    const tangentLength = Math.hypot(1, slope);
    points.push({
      x,
      z,
      along,
      travel: length,
      tx: (dx - dz * slope) / tangentLength,
      tz: (dz + dx * slope) / tangentLength,
    });
  }
  return { points, length, endRadius };
}
