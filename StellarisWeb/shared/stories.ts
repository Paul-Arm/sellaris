import type { Resources } from './game';

export const CRISIS = {
  kind: 'resonance_v1',
  title: 'Die Resonanzkaskade',
  dormantSeconds: 180,
  warningSeconds: 120,
  activeSeconds: 120,
  contributionCost: { energy: 60, minerals: 0, science: 30 },
  shieldCost: { energy: 120, minerals: 0, science: 0 },
  sciencePerContribution: 40,
} as const;
export type CrisisPhase = 'dormant' | 'warning' | 'active' | 'surge' | 'contained';
export const phaseNames: Record<CrisisPhase, string> = {
  dormant: 'Schwaches Signal',
  warning: 'Vorwarnung',
  active: 'Resonanzwelle',
  surge: 'Kaskade',
  contained: 'Eingedämmt',
};
export function crisisProductionFactor(phase: string, shielded = false) {
  return shielded ? 1 : phase === 'surge' ? 0.5 : phase === 'active' ? 0.75 : 1;
}
export interface StoryChoice {
  id: string;
  title: string;
  description: string;
  cost: Resources;
  reward: Resources;
  action?: 'contribute' | 'shield';
}
const free = (): Resources => ({ energy: 0, minerals: 0, science: 0 });
export const STORIES = {
  archive_v1: {
    title: 'Eine Stimme aus der Leere',
    eyebrow: 'ANOMALIE / VERSCHOLLENES ARCHIV',
    duration: 90,
    fallback: 'observe',
    description:
      'Zwischen den Interferenzen wiederholt sich ein künstliches Signal. Eine uralte Sonde hält ihre letzten Erinnerungen fest. Wir können das Archiv entschlüsseln oder die seltenen Bauteile bergen.',
    choices: [
      {
        id: 'decode',
        title: 'Das Archiv entschlüsseln',
        description: 'Versorge die Sonde mit Energie und sichere ihr Wissen.',
        cost: { ...free(), energy: 40 },
        reward: { ...free(), science: 100 },
      },
      {
        id: 'salvage',
        title: 'Die Sonde bergen',
        description: 'Verwerte die fremdartigen Werkstoffe. Das Archiv geht dabei verloren.',
        cost: free(),
        reward: { ...free(), minerals: 90 },
      },
      {
        id: 'observe',
        title: 'Aus der Ferne beobachten',
        description: 'Zeichne das Signal auf, ohne einzugreifen.',
        cost: free(),
        reward: { ...free(), science: 25 },
      },
    ],
  },
  frontier_v1: {
    title: 'Lichter am Horizont',
    eyebrow: 'ERSTE KOLONIE / NEUBEGINN',
    duration: 90,
    fallback: 'survey',
    description:
      'Die erste Außenkolonie meldet verlassene Speicher unter der Oberfläche. Der Kolonierat wartet auf eine Priorität: Energie für den Aufbau, Rohstoffe für die Werften oder eine sorgfältige Untersuchung.',
    choices: [
      {
        id: 'restore',
        title: 'Die Speicher reaktivieren',
        description: 'Ersetze die defekten Bauteile und gewinne die gespeicherte Energie.',
        cost: { ...free(), minerals: 40 },
        reward: { ...free(), energy: 110 },
      },
      {
        id: 'recycle',
        title: 'Bauteile zurückgewinnen',
        description: 'Zerlege die stillgelegten Anlagen für kommende Bauvorhaben.',
        cost: free(),
        reward: { ...free(), minerals: 60 },
      },
      {
        id: 'survey',
        title: 'Die Fundstätte untersuchen',
        description: 'Bewahre die Anlage und dokumentiere ihre Geschichte.',
        cost: free(),
        reward: { ...free(), science: 35 },
      },
    ],
  },
  resonance_v1: {
    title: 'Ein Riss im Sternennetz',
    eyebrow: 'GALAKTISCHE KRISE / ERSTE REAKTION',
    duration: 120,
    fallback: 'observe',
    description:
      'Eine Resonanzfront breitet sich vom Raumzeitriss aus. Planetare Energienetze werden bald gestört. Unsere Wissenschaftler schlagen eine gemeinsame Stabilisierung vor; alternativ können wir unsere eigenen Kolonien abschirmen.',
    choices: [
      {
        id: 'contribute',
        title: 'Stabilisierung finanzieren',
        description:
          'Ein Beitrag zur gemeinsamen Eindämmung. Nach Erfolg erhältst du 40 Forschung pro Beitrag.',
        cost: { ...CRISIS.contributionCost },
        reward: free(),
        action: 'contribute',
      },
      {
        id: 'shield',
        title: 'Eigene Kolonien abschirmen',
        description:
          'Schützt alle deine heutigen und künftigen Kolonien für diese Krise. Beendet die Krise nicht.',
        cost: { ...CRISIS.shieldCost },
        reward: free(),
        action: 'shield',
      },
      {
        id: 'observe',
        title: 'Die Lage beobachten',
        description: 'Keine Kosten und kein Schutz. Du kannst später weiterhin eingreifen.',
        cost: free(),
        reward: free(),
      },
    ],
  },
} satisfies Record<
  string,
  {
    title: string;
    eyebrow: string;
    duration: number;
    fallback: string;
    description: string;
    choices: StoryChoice[];
  }
>;
export type StoryKind = keyof typeof STORIES;
export type StoryCommand =
  | { type: 'resolve_decision'; decisionId: number; choice: string }
  | { type: 'crisis_action'; crisisId: number; action: 'contribute' | 'shield' };
export interface StoryDecision {
  id: number;
  kind: StoryKind;
  phase: string;
  deadlineAt: number;
  outcome: string;
  systemId: string;
  createdAt: number;
  resolvedAt: number;
  result: string;
}
export interface CrisisView {
  id: number;
  kind: string;
  systemId: string;
  phase: CrisisPhase;
  nextPhaseAt: number;
  target: number;
  progress: number;
  startedAt: number;
  endedAt: number;
  contributions: number;
  shielded: boolean;
}
