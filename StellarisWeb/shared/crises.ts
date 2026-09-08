import type { Resources } from './game';

export const CRISIS = {
  kind: 'resonance_v1',
  title: 'Die Resonanzkaskade',
  dormantSeconds: 180,
  warningSeconds: 120,
  activeSeconds: 120,
  contributionCost: { energy: 60, minerals: 0, data: 30 },
  shieldCost: { energy: 120, minerals: 0, data: 0 },
  dataPerContribution: 40,
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
export type CrisisCommand = { type: 'crisis_action'; crisisId: number; action: 'contribute' | 'shield' };
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
