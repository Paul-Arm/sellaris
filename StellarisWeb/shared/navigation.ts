import { stableHash, type CelestialBody } from './celestial';

export interface Point3 {
  x: number;
  y: number;
  z: number;
}
export interface LocalMotion {
  velocity?: Point3;
  paused?: boolean;
  from: Point3;
  to: Point3;
  startedAt: number;
  finishAt: number;
}
export type FleetOrder =
  | {
      type: 'megastructure_place';
      systemId: string;
      bodySlot: number;
      facility: import('./megastructures').Megastructure;
    }
  | { type: 'move'; systemId: string }
  | { type: 'local_move'; systemId: string; point: Point3 }
  | { type: 'site_build'; systemId: string; bodySlot: number; facility: import('./celestial').Facility }
  | { type: 'station_place'; systemId: string; point: Point3; facility: 'research' | 'habitat' }
  | { type: 'scan' | 'colonize'; bodySlot?: number; systemId?: string };
export interface FleetNavigation {
  motion: LocalMotion;
  orders: FleetOrder[];
  phase: string;
  visited: number[];
  targetSlot: number;
  totalBodies: number;
}
// Average speed in system units per game day; easing peaks at 1.5 times this value.
export const LOCAL_SPEED = 80;
export const BUILD_REACH = 100;
export function constructionFleet(
  game: import('./game').GameView,
  systemId: string,
  preferred?: string | null,
) {
  const candidates = game.fleets.filter(
    (f) => f.owner === game.me.id && f.systemId === systemId && !f.route.length && !f.battleId,
  );
  return (
    candidates.find((f) => f.id === preferred) ||
    candidates.sort(
      (a, b) =>
        Number(!!a.navigation?.orders.length) - Number(!!b.navigation?.orders.length) ||
        Number(b.type === 'colony') - Number(a.type === 'colony') ||
        (a.nativeId || 0) - (b.nativeId || 0),
    )[0]
  );
}
export function fleetAnchor(id: string): Point3 {
  const a = (stableHash(id) / 0xffffffff) * Math.PI * 2;
  return { x: Math.cos(a) * 120, y: 24, z: Math.sin(a) * 120 };
}
export const validPoint = (p: Point3) =>
  p && [p.x, p.y, p.z].every(Number.isFinite) && Math.hypot(p.x, p.z) <= 1600 && p.y >= 0 && p.y <= 400;
export function localPosition(m: LocalMotion, at: number): Point3 {
  if (m.paused) return m.from;
  const t =
    m.finishAt <= m.startedAt ? 1 : Math.max(0, Math.min(1, (at - m.startedAt) / (m.finishAt - m.startedAt)));
  const f = t * t * (3 - 2 * t);
  // Cubic Hermite keeps the incoming velocity when a destination changes.
  // This produces an actual curved turn, rather than resetting speed on each click.
  const tangent = t * (1 - t) * (1 - t) * Math.max(0, m.finishAt - m.startedAt);
  return {
    x: m.from.x + (m.to.x - m.from.x) * f + (m.velocity?.x || 0) * tangent,
    y: m.from.y + (m.to.y - m.from.y) * f + (m.velocity?.y || 0) * tangent,
    z: m.from.z + (m.to.z - m.from.z) * f + (m.velocity?.z || 0) * tangent,
  };
}
export function localVelocity(m: LocalMotion, at: number): Point3 {
  const duration = m.finishAt - m.startedAt;
  if (m.paused || duration <= 0 || at < m.startedAt || at >= m.finishAt) return { x: 0, y: 0, z: 0 };
  const t = (at - m.startedAt) / duration,
    f = (6 * t * (1 - t)) / duration;
  const tangent = (1 - t) * (1 - 3 * t);
  return {
    x: (m.to.x - m.from.x) * f + (m.velocity?.x || 0) * tangent,
    y: (m.to.y - m.from.y) * f + (m.velocity?.y || 0) * tangent,
    z: (m.to.z - m.from.z) * f + (m.velocity?.z || 0) * tangent,
  };
}
export function braking(m: LocalMotion, at: number): LocalMotion {
  const from = localPosition(m, at),
    velocity = localVelocity(m, at);
  const duration = Math.hypot(velocity.x, velocity.y, velocity.z) > 0.01 ? 3 : 0;
  return {
    from,
    velocity,
    to: {
      x: from.x + (velocity.x * duration) / 2,
      y: from.y + (velocity.y * duration) / 2,
      z: from.z + (velocity.z * duration) / 2,
    },
    startedAt: at,
    finishAt: at + duration,
  };
}
export function bodyPosition(body: CelestialBody, bodies: CelestialBody[], at: number): Point3 {
  if (body.position) return body.position;
  const angle = body.phase + (at / body.period) * Math.PI * 2;
  const parent = body.parent === undefined ? undefined : bodies.find((b) => b.slot === body.parent);
  const p = parent ? bodyPosition(parent, bodies, at) : { x: 0, y: 0, z: 0 };
  return {
    x: p.x + Math.cos(angle) * body.orbit,
    y: body.radius * 0.45 - 12,
    z: p.z + Math.sin(angle) * body.orbit,
  };
}
export function flight(
  from: Point3,
  to: Point3,
  at: number,
  velocity: Point3 = { x: 0, y: 0, z: 0 },
): LocalMotion {
  return {
    from,
    to,
    velocity,
    startedAt: at,
    finishAt: at + Math.max(4, Math.hypot(to.x - from.x, to.y - from.y, to.z - from.z) / LOCAL_SPEED),
  };
}
