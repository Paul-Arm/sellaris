import { seededRandom } from '../backend/domain';
import { createGame, type GameState, type StarSystem } from './game';
import { stellarClass, stellarProfile } from './stellar';
import {
  DEFAULT_GALAXY_SETTINGS,
  HYPERLANE_DENSITIES,
  parseGalaxySettings,
  type GalaxySettings,
} from './galaxySettings';

/** Seeded morphology shared by gateway and native bootstrap. Existing worlds are never regenerated. */
export function createGalaxy(
  code: string,
  seed: number,
  options: GalaxySettings | number = DEFAULT_GALAXY_SETTINGS,
): GameState {
  const settings = parseGalaxySettings(
    typeof options === 'number' ? { ...DEFAULT_GALAXY_SETTINGS, systems: options } : options,
  );
  const game = createGame(code),
    random = seededRandom(seed);
  const names = ['Aster', 'Nyx', 'Helion', 'Orion', 'Vesper', 'Talos', 'Lyra', 'Nereid', 'Aquila', 'Caelum'];
  const scale = Math.sqrt(settings.systems / 1000) * 0.4 + 0.6;
  const rotation = (random() - 0.5) * 0.6;
  const gaussian = () =>
    Math.sqrt(-2 * Math.log(Math.max(0.000001, random()))) * Math.cos(random() * Math.PI * 2);
  const sample = () => {
    let r: number,
      angle = random() * Math.PI * 2;
    if (settings.type === 'ring') {
      r = 0.72 + gaussian() * 0.11;
      if (r < 0.48 || r > 1) return null;
    } else if (settings.type === 'elliptical') {
      r = Math.pow(random(), 0.7);
    } else if (settings.type === 'barred' && random() < 0.24) {
      const x = (random() - 0.5) * 0.86,
        y = gaussian() * 0.065;
      return {
        x: 800 + (x * Math.cos(rotation) - y * Math.sin(rotation)) * 720 * scale,
        y: 525 + (x * Math.sin(rotation) + y * Math.cos(rotation)) * 440 * scale,
      };
    } else {
      r = Math.sqrt(random());
      // Central bulge and diffuse inter-arm stars keep the arms organic.
      if (random() < 0.15) r *= 0.32;
      else if (random() < 0.86) {
        const arm = random() < 0.5 ? 0 : Math.PI;
        angle =
          arm +
          (settings.type === 'barred' ? Math.max(0, r - 0.35) * 4.5 : r * 4.8) +
          gaussian() * (0.1 + 0.09 / Math.max(0.25, r));
      }
    }
    angle += rotation;
    return { x: 800 + Math.cos(angle) * r * 720 * scale, y: 525 + Math.sin(angle) * r * 440 * scale };
  };
  const positions: { x: number; y: number }[] = [];
  // Rejection budget relaxes spacing in crowded cores. The final fallback is bounded, too.
  for (let attempts = 0; positions.length < settings.systems; attempts++) {
    if (attempts >= settings.systems * 1000)
      throw new Error('Galaxie konnte nicht erzeugt werden. Bitte erneut versuchen.');
    const p = sample();
    const spacing = attempts < settings.systems * 120 ? 15 : attempts < settings.systems * 240 ? 10 : 5;
    if (!p || positions.some((q) => (p.x - q.x) ** 2 + (p.y - q.y) ** 2 < spacing ** 2)) continue;
    positions.push({ x: Math.round(p.x * 100) / 100, y: Math.round(p.y * 100) / 100 });
  }
  while (game.systems.length < settings.systems) {
    const i = game.systems.length,
      kind = i % 97 === 0 ? 'blackhole' : 'star';
    const starClass =
      kind === 'blackhole'
        ? i % 194 === 0
          ? 'Quasar'
          : 'Schwarzes Loch'
        : stellarClass({ id: `s${i}`, kind, class: ['G2 V', 'B2 V', 'K1 III', 'A0 V'][i % 4] });
    game.systems.push({
      id: `s${i}`,
      name: `${names[i % names.length]} ${String(i).padStart(3, '0')}`,
      x: 0,
      y: 0,
      color: stellarProfile({ id: `s${i}`, kind, class: starClass, color: '#ddd5ff' }).color,
      kind,
      class: starClass,
      planet:
        kind === 'blackhole'
          ? 'Nicht kolonisierbar'
          : ['Kontinentalwelt', 'Ozeanwelt', 'Wüstenwelt', 'Alpine Welt', 'Savannenwelt'][i % 5],
      owner: null,
      resources: {
        energy: 2 + Math.floor(random() * 6),
        minerals: 2 + Math.floor(random() * 6),
        science: 1 + Math.floor(random() * 3),
      },
      defense: i % 29 === 0 ? 85 : 0,
      mined: false,
      anomaly: kind === 'blackhole' || i % 23 === 0,
      studied: false,
      colony: null,
    });
  }
  game.systems.forEach((s, i) => Object.assign(s, positions[i]));
  game.links = connectGalaxy(game.systems, settings.hyperlaneDensity);
  return game;
}

/** Minimum spanning tree joins every arm; short additional lanes provide alternate routes. */
export function connectGalaxy(
  systems: StarSystem[],
  density: GalaxySettings['hyperlaneDensity'],
): [string, string][] {
  if (systems.length < 2) return [];
  const distance = (a: number, b: number) =>
    (systems[a].x - systems[b].x) ** 2 + (systems[a].y - systems[b].y) ** 2;
  const links: [string, string][] = [],
    edges = new Set<string>();
  const add = (a: number, b: number) => {
    const key = `${Math.min(a, b)}:${Math.max(a, b)}`;
    if (edges.has(key)) return;
    edges.add(key);
    links.push([systems[a].id, systems[b].id]);
  };
  const visited = new Uint8Array(systems.length),
    best = new Float64Array(systems.length).fill(Infinity),
    parent = new Int32Array(systems.length);
  best[0] = 0;
  for (let step = 0; step < systems.length; step++) {
    let next = -1;
    for (let i = 0; i < systems.length; i++) if (!visited[i] && (next < 0 || best[i] < best[next])) next = i;
    visited[next] = 1;
    if (step) add(next, parent[next]);
    for (let i = 0; i < systems.length; i++)
      if (!visited[i]) {
        const d = distance(next, i);
        if (d < best[i]) {
          best[i] = d;
          parent[i] = next;
        }
      }
  }
  const candidates: { a: number; b: number; d: number }[] = [];
  for (let a = 0; a < systems.length; a++) {
    const near = systems
      .map((_, b) => ({ a, b, d: distance(a, b) }))
      .filter((v) => v.a !== v.b)
      .sort((x, y) => x.d - y.d);
    candidates.push(...near.slice(0, 7));
  }
  candidates.sort((a, b) => a.d - b.d || a.a - b.a || a.b - b.b);
  const target = Math.round(systems.length * HYPERLANE_DENSITIES[density].edges);
  for (const { a, b } of candidates) {
    if (links.length >= target) break;
    add(a, b);
  }
  return links;
}
