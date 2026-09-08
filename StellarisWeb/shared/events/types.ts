import type { EconomyModifier } from '../economy';
import type { Resources } from '../resources';

export type Facts = Record<string, string | number | boolean | string[]>;
export type Condition =
  | { all: Condition[] }
  | { any: Condition[] }
  | { not: Condition }
  | { fact: string; op: 'is' | 'has' | 'gte' | 'lte'; value: string | number | boolean };
export type EventBlock =
  | { type: 'text'; text: string }
  | { type: 'dialogue'; speaker: string; role?: string; text: string; portrait?: string }
  | { type: 'image'; src: string; alt: string; caption?: string }
  | { type: 'map'; caption: string }
  | { type: 'callout'; title: string; text: string; tone?: 'warning' | 'info' };
export type EventEffect =
  | { type: 'resources'; amounts: Resources }
  | { type: 'flag'; key: string; value: string | number | boolean }
  | { type: 'modifier'; modifier: EconomyModifier }
  | { type: 'species_modifier'; modifier: EconomyModifier; evolve?: boolean }
  | { type: 'project'; definition: string }
  | { type: 'crisis'; action: 'contribute' | 'shield' };
export interface EventChoice {
  id: string;
  title: string;
  description: string;
  cost?: Resources;
  when?: Condition;
  effects?: EventEffect[];
  progress?: number;
  rate?: number;
  next?: string;
  finish?: 'completed' | 'failed';
}
export interface EventStage {
  id: string;
  title: string;
  blocks: EventBlock[];
  /** Decisions stop the clock for this stage until a choice or timeout. */
  choices?: EventChoice[];
  timeoutDays?: number;
  fallback?: string;
  /** Work stages advance when progress reaches this threshold. */
  threshold?: number;
  effects?: EventEffect[];
}
export interface EventDefinition {
  id: string;
  kind: 'event' | 'project';
  title: string;
  subtitle: string;
  summary: string;
  theme: 'signal' | 'biology' | 'industry' | 'crisis' | 'society';
  artwork?: string;
  triggers: string[];
  when?: Condition;
  chance: number;
  weight: number;
  priority?: 'critical';
  weights?: { when: Condition; multiply: number }[];
  repeat: 'once' | 'system' | 'repeat';
  cooldownDays: number;
  startCost?: Resources;
  stages: EventStage[];
  progress?: {
    target: number;
    initial?: number;
    rate: number;
    volatility?: number;
    rates?: { when: Condition; add: number }[];
    failAtZero?: boolean;
  };
}
export interface EventHistory {
  day: number;
  text: string;
  progress: number;
}
export interface SituationState {
  revision: number;
  status: 'available' | 'active' | 'decision' | 'paused' | 'completed' | 'failed';
  stage: number;
  progress: number;
  rateBonus: number;
  lastRate: number;
  createdAt: number;
  updatedAt: number;
  enteredAt: number;
  resolvedAt: number;
  notice: number;
  seen: number;
  seed: string;
  speciesId: string;
  history: EventHistory[];
}
export interface Situation {
  id: number;
  definitionId: string;
  systemId: string;
  state: SituationState;
  availableChoices: string[];
}
export interface EventContext {
  day: number;
  trigger: string;
  key: string;
  facts: Facts;
}
export interface DirectorState {
  lastDay: number;
  sequence: number;
  flags: Facts;
  history: Record<string, { lastDay: number; count: number }>;
  recent: string[];
}
export type SituationCommand =
  | { type: 'situation_ack'; id: number; notice: number }
  | { type: 'situation_choice'; id: number; revision: number; choice: string }
  | {
      type: 'situation_start' | 'situation_pause' | 'situation_resume';
      id: number;
      revision: number;
    };
