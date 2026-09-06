import type { StarSystem } from '../shared/game';
export interface Point {
  x: number;
  y: number;
}
export interface Territory {
  owner: string;
  cells: Point[][];
  edges: [Point, Point][];
}
export interface MapCamera extends Point {
  zoom: number;
}
export interface LabelPlacement {
  system: StarSystem;
  x: number;
  y: number;
  width: number;
  height: number;
  detail: boolean;
}
export interface MapExclusion {
  x: number;
  y: number;
  width: number;
  height: number;
}
export const isLandmark = (s: StarSystem) => s.id === 'void' || s.kind === 'rift';
export function blackHoleRadius(s: StarSystem, zoom: number) {
  return s.id === 'void' ? 36 * zoom : Math.max(7, Math.min(13, 9 + Math.log2(zoom) * 2));
}
export function galaxyFrame(systems: StarSystem[], width: number, height: number): MapCamera {
  const xs = systems.map((s) => s.x),
    ys = systems.map((s) => s.y);
  const minX = Math.min(...xs),
    maxX = Math.max(...xs),
    minY = Math.min(...ys),
    maxY = Math.max(...ys);
  const available = width > 850 ? Math.max(300, width - 580) : Math.max(260, width - 250);
  return {
    x: (minX + maxX) / 2,
    y: (minY + maxY) / 2,
    zoom: Math.max(
      0.25,
      Math.min(1.3, available / (maxX - minX + 100), Math.max(300, height - 210) / (maxY - minY + 100)),
    ),
  };
}

/** Bounded Voronoi ownership cells: unclaimed stars and separate islands remain unclaimed. */
export function buildTerritories(systems: StarSystem[]): Territory[] {
  const groups = new Map<string, Territory>();
  const radius = Math.max(45, Math.min(110, Math.sqrt(1_000_000 / systems.length) * 1.8));
  for (const s of systems) {
    if (!s.owner) continue;
    let polygon: Point[] = Array.from({ length: 32 }, (_, i) => ({
      x: s.x + Math.cos((i * Math.PI) / 16) * radius,
      y: s.y + Math.sin((i * Math.PI) / 16) * radius,
    }));
    const neighbors = systems.filter(
      (t) => t.id !== s.id && (s.x - t.x) ** 2 + (s.y - t.y) ** 2 < (radius * 2) ** 2,
    );
    for (const t of neighbors) {
      const nx = t.x - s.x,
        ny = t.y - s.y,
        limit = (t.x * t.x + t.y * t.y - s.x * s.x - s.y * s.y) / 2;
      const next: Point[] = [];
      for (let i = 0; i < polygon.length; i++) {
        const a = polygon[i],
          b = polygon[(i + 1) % polygon.length];
        const da = a.x * nx + a.y * ny - limit,
          db = b.x * nx + b.y * ny - limit;
        if (da <= 0) next.push(a);
        if (da <= 0 !== db <= 0) {
          const f = da / (da - db);
          next.push({ x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f });
        }
      }
      polygon = next;
    }
    let group = groups.get(s.owner);
    if (!group) {
      group = { owner: s.owner, cells: [], edges: [] };
      groups.set(s.owner, group);
    }
    group.cells.push(polygon);
    for (let i = 0; i < polygon.length; i++) {
      const a = polygon[i],
        b = polygon[(i + 1) % polygon.length],
        x = (a.x + b.x) / 2,
        y = (a.y + b.y) / 2;
      const d = (x - s.x) ** 2 + (y - s.y) ** 2;
      const internal = neighbors.some(
        (t) => t.owner === s.owner && Math.abs((x - t.x) ** 2 + (y - t.y) ** 2 - d) < 0.01,
      );
      if (!internal) group.edges.push([a, b]);
    }
  }
  return [...groups.values()];
}

/** Screen-space label budgets and collision rejection remain effective at every zoom level. */
export function layoutGalaxyLabels(
  systems: StarSystem[],
  camera: MapCamera,
  size: { width: number; height: number },
  selected: string,
  hover: string | null,
  home: string,
  surveyed: Set<string>,
  measure: (name: string) => number,
  exclusions: MapExclusion[] = [],
): LabelPlacement[] {
  const { zoom } = camera;
  const budget = Math.max(
    10,
    Math.min(
      180,
      Math.floor(
        ((size.width * size.height) / 24000) * (zoom < 0.7 ? 0.45 : zoom < 1.2 ? 0.8 : zoom < 1.8 ? 1.2 : 2),
      ),
    ),
  );
  const score = (s: StarSystem) =>
    s.id === selected
      ? 1000
      : s.id === hover
        ? 950
        : s.id === home
          ? 900
          : s.owner
            ? 800
            : isLandmark(s)
              ? 700
              : s.kind === 'blackhole'
                ? 500
                : surveyed.has(s.id)
                  ? 300
                  : 100;
  const candidates = systems
    .map((s) => ({ s, priority: score(s) }))
    .filter(
      ({ s, priority }) =>
        (zoom >= 0.85 || priority >= 700) &&
        Math.abs((s.x - camera.x) * zoom) < size.width / 2 - 25 &&
        Math.abs((s.y - camera.y) * zoom) < size.height / 2 - 30,
    )
    .sort((a, b) => b.priority - a.priority || a.s.id.localeCompare(b.s.id));
  const placed: LabelPlacement[] = [];
  for (const { s, priority } of candidates) {
    if (placed.length >= budget && priority < 900) break;
    const detail = (s.owner !== null || isLandmark(s)) && (zoom >= 0.7 || priority >= 900);
    const width = Math.max(measure(s.name), detail ? 94 : 0) + 10,
      height = detail ? 30 : 16;
    const x = (s.x - camera.x) * zoom + size.width / 2;
    const y =
      (s.y - camera.y) * zoom + size.height / 2 + (isLandmark(s) ? 47 : s.kind === 'blackhole' ? 20 : 17);
    if (
      exclusions.some(
        (r) =>
          x + width / 2 > r.x - 8 &&
          x - width / 2 < r.x + r.width + 8 &&
          y + height > r.y - 8 &&
          y < r.y + r.height + 8,
      )
    )
      continue;
    if (
      placed.some(
        (p) => Math.abs(x - p.x) < (width + p.width) / 2 && y < p.y + p.height + 4 && y + height + 4 > p.y,
      )
    )
      continue;
    placed.push({ system: s, x, y, width, height, detail });
  }
  return placed;
}
