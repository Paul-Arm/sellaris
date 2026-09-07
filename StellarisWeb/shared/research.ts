import type { Player } from './game';

export type ResearchField = 'compute' | 'models' | 'industry' | 'frontier';
export const RESEARCH_FIELDS = {
  compute: { name: 'Rechensysteme', color: '#a7a0ff' },
  models: { name: 'Daten & Modelle', color: '#57d7cc' },
  industry: { name: 'Materie & Konstruktion', color: '#e5b674' },
  frontier: { name: 'Raum & Leben', color: '#df8fbb' },
};
export type TechId =
  | 'computing'
  | 'distributed'
  | 'parallelism'
  | 'quantum'
  | 'simulation'
  | 'prediction'
  | 'archives'
  | 'compression'
  | 'propulsion'
  | 'weapons'
  | 'extraction'
  | 'automation'
  | 'terraforming'
  | 'megastructures'
  | 'stellar_computing';
export interface Technology {
  name: string;
  description: string;
  field: ResearchField;
  data: number;
  work: number;
  requires: TechId[];
  compute?: number;
}
export const TECHS: Record<TechId, Technology> = {
  computing: {
    name: 'Rechenarchitektur',
    description: '+2 Compute pro Spieltag.',
    field: 'compute',
    data: 50,
    work: 80,
    requires: [],
    compute: 2,
  },
  distributed: {
    name: 'Verteilte Systeme',
    description: '+4 Compute pro Spieltag.',
    field: 'compute',
    data: 130,
    work: 220,
    requires: ['computing'],
    compute: 4,
  },
  parallelism: {
    name: 'Parallelarchitektur',
    description: '+3 Compute pro Spieltag.',
    field: 'compute',
    data: 100,
    work: 180,
    requires: ['computing'],
    compute: 3,
  },
  quantum: {
    name: 'Quantenprozessoren',
    description: '+8 Compute pro Spieltag.',
    field: 'compute',
    data: 350,
    work: 650,
    requires: ['distributed', 'propulsion'],
    compute: 8,
  },
  archives: {
    name: 'Wissensarchive',
    description: 'Neue Forschungsprojekte benötigen 15 % weniger Daten.',
    field: 'models',
    data: 60,
    work: 100,
    requires: [],
  },
  simulation: {
    name: 'Simulationsmodelle',
    description: 'Compute erzeugt 0,5 statt 0,25 Daten je Recheneinheit.',
    field: 'models',
    data: 100,
    work: 160,
    requires: ['archives'],
  },
  compression: {
    name: 'Semantische Kompression',
    description: 'Weitere 15 % weniger Datenkosten für neue Projekte.',
    field: 'models',
    data: 180,
    work: 300,
    requires: ['archives', 'parallelism'],
  },
  prediction: {
    name: 'Prädiktive Wissenschaft',
    description: 'Simulationen erzeugen 0,75 Daten je Compute.',
    field: 'models',
    data: 300,
    work: 500,
    requires: ['simulation', 'distributed'],
  },
  extraction: {
    name: 'Quantenextraktion',
    description: 'Kolonien produzieren 50 % mehr Energie und Mineralien.',
    field: 'industry',
    data: 120,
    work: 160,
    requires: [],
  },
  automation: {
    name: 'Autonome Fertigung',
    description: '+3 Compute durch vernetzte Industrieprozessoren.',
    field: 'industry',
    data: 150,
    work: 240,
    requires: ['extraction'],
    compute: 3,
  },
  weapons: {
    name: 'Plasmalanzen',
    description: 'Die Kampfkraft aller Schiffe steigt um 40 %.',
    field: 'industry',
    data: 150,
    work: 180,
    requires: ['extraction'],
  },
  megastructures: {
    name: 'Megakonstruktion',
    description: 'Schaltet Dyson-Anlagen und Materiedekompressoren frei.',
    field: 'industry',
    data: 500,
    work: 600,
    requires: ['automation', 'propulsion'],
  },
  propulsion: {
    name: 'Raumfaltung',
    description: 'Flotten reisen 35 % schneller durch den Hyperraum.',
    field: 'frontier',
    data: 100,
    work: 140,
    requires: [],
  },
  terraforming: {
    name: 'Klimagestaltung',
    description: 'Schaltet Terraforming in neun bewohnbare Klimaklassen frei.',
    field: 'frontier',
    data: 250,
    work: 320,
    requires: ['simulation', 'propulsion'],
  },
  stellar_computing: {
    name: 'Stellare Rechennetze',
    description: '+10 Compute durch ein interstellares Rechenverbund-Protokoll.',
    field: 'compute',
    data: 650,
    work: 1100,
    requires: ['quantum', 'megastructures'],
    compute: 10,
  },
};
export interface ResearchProject {
  tech: TechId;
  done: number;
  paid: number | null;
  weight: number;
}
export interface ResearchProgram {
  projects: ResearchProject[];
  synthesis: number;
}
export type ResearchCommand =
  | { type: 'research'; tech: TechId }
  | { type: 'research_weight'; tech: TechId; weight: number }
  | { type: 'research_synthesis'; percent: number };
export const newResearch = (): ResearchProgram => ({ projects: [], synthesis: 25 });
/** Only completed knowledge and the immediately reachable frontier are revealed. */
export function visibleResearch(known: readonly TechId[]): TechId[] {
  const unlocked = new Set(known);
  return (Object.keys(TECHS) as TechId[]).filter(
    (id) => unlocked.has(id) || TECHS[id].requires.every((parent) => unlocked.has(parent)),
  );
}
export const dataCost = (tech: TechId, known: readonly TechId[]) =>
  Math.ceil(
    TECHS[tech].data *
      (1 - (known.includes('archives') ? 0.15 : 0) - (known.includes('compression') ? 0.15 : 0)),
  );
export const synthesisEfficiency = (known: readonly TechId[]) =>
  known.includes('prediction') ? 0.75 : known.includes('simulation') ? 0.5 : 0.25;
export const baseCompute = (known: readonly TechId[]) =>
  4 + known.reduce((n, id) => n + (TECHS[id]?.compute || 0), 0);
export function researchPath(target: TechId, known: readonly TechId[] = []) {
  const path: TechId[] = [],
    visited = new Set(known);
  const visit = (id: TechId) => {
    if (visited.has(id)) return;
    visited.add(id);
    TECHS[id].requires.forEach(visit);
    path.push(id);
  };
  visit(target);
  return path;
}
export function researchAllocation(program: ResearchProgram, known: readonly TechId[], compute: number) {
  const active = program.projects.filter(
    (p) => p.paid !== null && p.weight > 0 && TECHS[p.tech].requires.every((id) => known.includes(id)),
  );
  const weights = active.reduce((n, p) => n + p.weight, 0);
  const research = weights ? compute * (1 - program.synthesis / 100) : 0;
  return {
    rates: new Map(active.map((p) => [p.tech, (research * p.weight) / weights])),
    research,
    synthesis: compute - research,
    data: (compute - research) * synthesisEfficiency(known),
  };
}
export function activateResearch(player: Pick<Player, 'research' | 'techs' | 'resources'>) {
  for (const project of player.research.projects) {
    if (
      project.paid !== null ||
      !project.weight ||
      player.research.synthesis === 100 ||
      !TECHS[project.tech].requires.every((id) => player.techs.includes(id))
    )
      continue;
    const cost = dataCost(project.tech, player.techs);
    if (player.resources.data < cost) continue;
    player.resources.data -= cost;
    project.paid = cost;
  }
}
export function applyResearch(
  player: Pick<Player, 'research' | 'techs' | 'resources'>,
  cmd: ResearchCommand,
) {
  if (cmd.type === 'research_synthesis') {
    if (!Number.isInteger(cmd.percent) || cmd.percent < 0 || cmd.percent > 100)
      throw new Error('Compute-Verteilung muss zwischen 0 und 100 % liegen.');
    player.research.synthesis = cmd.percent;
  } else {
    if (!Object.hasOwn(TECHS, cmd.tech)) throw new Error('Unbekannte Technologie.');
    if (cmd.type === 'research') {
      if (player.techs.includes(cmd.tech)) throw new Error('Bereits erforscht.');
      if (!visibleResearch(player.techs).includes(cmd.tech))
        throw new Error('Diese Technologie ist noch nicht entdeckt. Erforsche zunächst ihre Grundlagen.');
      if (player.research.projects.some((p) => p.tech === cmd.tech))
        throw new Error('Bereits im Forschungsprogramm.');
      for (const tech of researchPath(cmd.tech, player.techs))
        if (!player.research.projects.some((p) => p.tech === tech))
          player.research.projects.push({ tech, done: 0, paid: null, weight: 1 });
    } else {
      const p = player.research.projects.find((p) => p.tech === cmd.tech);
      if (!p || !Number.isInteger(cmd.weight) || cmd.weight < 0 || cmd.weight > 5)
        throw new Error('Projektpriorität muss zwischen 0 und 5 liegen.');
      p.weight = cmd.weight;
    }
  }
  activateResearch(player);
}
/** One authoritative day. Completion unlocks follow-up work on the next day. */
export function advanceResearch(
  player: Pick<Player, 'research' | 'techs' | 'resources'>,
  compute: number,
  dt: number,
) {
  activateResearch(player);
  const allocation = researchAllocation(player.research, player.techs, compute);
  player.resources.data += allocation.data * dt;
  const completed: TechId[] = [];
  for (const p of player.research.projects) {
    p.done = Math.min(TECHS[p.tech].work, p.done + (allocation.rates.get(p.tech) || 0) * dt);
    if (p.done >= TECHS[p.tech].work) {
      player.techs.push(p.tech);
      completed.push(p.tech);
    }
  }
  player.research.projects = player.research.projects.filter((p) => !completed.includes(p.tech));
  return completed;
}
