import { CRISIS } from '../crises';
import { addResources, resourceAmounts } from '../resources';
import { stableHash } from '../celestial';
import type {
  Condition,
  DirectorState,
  EventContext,
  EventDefinition,
  EventEffect,
  EventChoice,
  SituationState,
} from './types';

export function choiceCosts(choice: EventChoice) {
  const cost = resourceAmounts(choice.cost);
  for (const effect of choice.effects ?? [])
    if (effect.type === 'crisis')
      addResources(cost, effect.action === 'shield' ? CRISIS.shieldCost : CRISIS.contributionCost);
  return cost;
}
export const TERMINAL = new Set(['completed', 'failed']);
export const EVENT_LIMITS = { active: 8, intervalDays: 30, history: 48, archived: 64 } as const;
export function matches(condition: Condition | undefined, facts: EventContext['facts']): boolean {
  if (!condition) return true;
  if ('all' in condition) return condition.all.every((c) => matches(c, facts));
  if ('any' in condition) return condition.any.some((c) => matches(c, facts));
  if ('not' in condition) return !matches(condition.not, facts);
  const value = facts[condition.fact];
  if (condition.op === 'is') return value === condition.value;
  if (condition.op === 'has') return Array.isArray(value) && value.includes(String(condition.value));
  return (
    typeof value === 'number' &&
    typeof condition.value === 'number' &&
    (condition.op === 'gte' ? value >= condition.value : value <= condition.value)
  );
}
const roll = (seed: string) => stableHash(seed) / 0x100000000;
export const definitionKey = (d: EventDefinition, context: EventContext) =>
  `${d.id}:${d.repeat === 'system' ? String(context.facts.systemId) : 'empire'}`;
export function selectEvent(
  pool: readonly EventDefinition[],
  director: DirectorState,
  context: EventContext,
  seed: string,
  active: number,
) {
  if (director.recent.includes(context.key)) return null;
  const eligible = pool.flatMap((d) => {
    const previous = director.history[definitionKey(d, context)];
    if (
      (active >= EVENT_LIMITS.active && d.priority !== 'critical') ||
      !d.triggers.includes(context.trigger) ||
      !matches(d.when, context.facts) ||
      (previous && (d.repeat !== 'repeat' || context.day - previous.lastDay < d.cooldownDays)) ||
      roll(`${seed}:${context.key}:${d.id}:chance`) >= d.chance
    )
      return [];
    const weight = (d.weights ?? []).reduce(
      (w, rule) => (matches(rule.when, context.facts) ? w * rule.multiply : w),
      d.weight,
    );
    return weight > 0 ? [{ definition: d, weight }] : [];
  });
  let n =
    roll(`${seed}:${context.key}:${director.sequence}:pick`) * eligible.reduce((s, d) => s + d.weight, 0);
  for (const d of eligible) {
    n -= d.weight;
    if (n < 0) return d.definition;
  }
  return null;
}
export function recordHistory(state: SituationState, day: number, text: string) {
  state.history.push({ day, text, progress: state.progress });
  state.history = state.history.slice(-EVENT_LIMITS.history);
}
export function createSituation(
  d: EventDefinition,
  day: number,
  seed: string,
  speciesId: string,
): SituationState {
  return {
    revision: 1,
    status: d.kind === 'project' ? 'available' : d.stages[0].choices?.length ? 'decision' : 'active',
    stage: 0,
    progress: d.progress?.initial ?? 0,
    rateBonus: 0,
    lastRate: 0,
    createdAt: day,
    enteredAt: day,
    updatedAt: day,
    resolvedAt: 0,
    notice: 1,
    seen: 0,
    seed,
    speciesId,
    history: [
      {
        day,
        text: d.kind === 'project' ? 'Spezialprojekt entdeckt' : 'Ereignis entdeckt',
        progress: d.progress?.initial ?? 0,
      },
    ],
  };
}
function enterStage(s: SituationState, d: EventDefinition, index: number, day: number) {
  s.stage = index;
  s.enteredAt = day;
  s.updatedAt = day;
  if (index >= d.stages.length) {
    s.status = 'completed';
    s.resolvedAt = day;
    s.notice++;
    recordHistory(s, day, 'Abgeschlossen');
  } else {
    s.status = d.stages[index].choices?.length ? 'decision' : 'active';
    s.notice++;
    recordHistory(s, day, d.stages[index].title);
  }
}
export function chooseEvent(
  s: SituationState,
  d: EventDefinition,
  choiceId: string,
  context: EventContext,
): EventEffect[] {
  if (s.status !== 'decision') throw new Error('Keine offene Entscheidung.');
  const choice = d.stages[s.stage]?.choices?.find((c) => c.id === choiceId);
  if (!choice || !matches(choice.when, context.facts))
    throw new Error('Diese Entscheidung ist nicht verfügbar.');
  s.progress = Math.max(0, Math.min(d.progress?.target ?? 100, s.progress + (choice.progress ?? 0)));
  s.rateBonus += choice.rate ?? 0;
  recordHistory(s, context.day, choice.title);
  if (choice.finish) {
    s.status = choice.finish;
    s.resolvedAt = context.day;
    s.notice++;
  } else
    enterStage(
      s,
      d,
      choice.next ? d.stages.findIndex((stage) => stage.id === choice.next) : s.stage + 1,
      context.day,
    );
  s.updatedAt = context.day;
  s.revision++;
  return choice.effects ?? [];
}
export function progressRate(s: SituationState, d: EventDefinition, context: EventContext, day: number) {
  const p = d.progress;
  if (!p) return 0;
  return (
    p.rate +
    s.rateBonus +
    (p.rates ?? []).reduce(
      (n, rule) => n + (matches(rule.when, { ...context.facts, day }) ? rule.add : 0),
      0,
    ) +
    (roll(`${s.seed}:drift:${day}`) * 2 - 1) * (p.volatility ?? 0)
  );
}
/** Daily deterministic integration gives identical results across tick/reconnect partitions. */
export function advanceSituation(
  s: SituationState,
  d: EventDefinition,
  context: EventContext,
): EventEffect[] {
  const effects: EventEffect[] = [];
  if (s.status === 'decision') {
    const stage = d.stages[s.stage];
    if (stage.timeoutDays && context.day >= s.enteredAt + stage.timeoutDays && stage.fallback)
      return chooseEvent(s, d, stage.fallback, { ...context, day: s.enteredAt + stage.timeoutDays });
    return effects;
  }
  if (s.status !== 'active' || !d.progress) return effects;
  const previous = s.updatedAt;
  for (
    let day = Math.floor(s.updatedAt) + 1;
    day <= Math.floor(context.day) && s.status === 'active';
    day++
  ) {
    s.lastRate = progressRate(s, d, context, day);
    s.progress = Math.max(0, Math.min(d.progress.target, s.progress + s.lastRate));
    s.updatedAt = day;
    if (s.progress === 0 && d.progress.failAtZero) {
      s.status = 'failed';
      s.resolvedAt = day;
      s.notice++;
      recordHistory(s, day, 'Projekt gescheitert');
      break;
    }
    const stage = d.stages[s.stage];
    if (stage.threshold !== undefined && s.progress >= stage.threshold) {
      effects.push(...(stage.effects ?? []));
      enterStage(s, d, s.stage + 1, day);
    }
  }
  if (s.updatedAt !== previous) s.revision++;
  return effects;
}
export function validateEventPool(pool: readonly EventDefinition[]) {
  const ids = new Set(pool.map((d) => d.id));
  if (ids.size !== pool.length) throw new Error('Doppelte Ereignis-ID.');
  for (const d of pool) {
    if (
      !d.id ||
      !d.stages.length ||
      !Number.isFinite(d.chance) ||
      !Number.isFinite(d.cooldownDays) ||
      d.cooldownDays < 0 ||
      d.chance < 0 ||
      d.chance > 1 ||
      !Number.isFinite(d.weight) ||
      d.weight <= 0
    )
      throw new Error(`Ungültiges Ereignis: ${d.id}`);
    if (Object.values(d.startCost ?? {}).some((v) => !Number.isFinite(v) || v < 0))
      throw new Error(`Ungültige Startkosten: ${d.id}`);
    const stages = new Set(d.stages.map((s) => s.id));
    if (stages.size !== d.stages.length) throw new Error(`Doppelte Phase: ${d.id}`);
    if (
      d.progress &&
      (!(d.progress.target > 0) ||
        !Number.isFinite(d.progress.target) ||
        !Number.isFinite(d.progress.rate) ||
        !Number.isFinite(d.progress.volatility ?? 0) ||
        (d.progress.volatility ?? 0) < 0)
    )
      throw new Error(`Ungültiger Fortschritt: ${d.id}`);
    for (const s of d.stages) {
      const choices = s.choices ?? [];
      if (new Set(choices.map((c) => c.id)).size !== choices.length)
        throw new Error(`Doppelte Entscheidung: ${d.id}`);
      if (
        !choices.length &&
        (!d.progress ||
          s.threshold === undefined ||
          !Number.isFinite(s.threshold) ||
          s.threshold < 0 ||
          s.threshold > d.progress.target)
      )
        throw new Error(`Phase ohne Übergang: ${d.id}/${s.id}`);
      if (s.timeoutDays !== undefined && (!Number.isFinite(s.timeoutDays) || s.timeoutDays <= 0))
        throw new Error(`Ungültige Frist: ${d.id}`);
      for (const e of s.effects ?? [])
        if (e.type === 'project' && !ids.has(e.definition))
          throw new Error(`Unbekanntes Folgeprojekt: ${e.definition}`);
      if (
        s.timeoutDays &&
        !choices.some(
          (c) => c.id === s.fallback && !c.when && !Object.values(choiceCosts(c)).some((v) => v > 0),
        )
      )
        throw new Error(`Frist benötigt kostenlose Standardoption: ${d.id}`);
      for (const c of choices) {
        if (c.next && !stages.has(c.next)) throw new Error(`Unbekannte Folgephase: ${d.id}`);
        if (Object.values(c.cost ?? {}).some((v) => !Number.isFinite(v) || v < 0))
          throw new Error(`Ungültige Kosten: ${d.id}`);
        for (const e of c.effects ?? [])
          if (e.type === 'project' && !ids.has(e.definition))
            throw new Error(`Unbekanntes Folgeprojekt: ${e.definition}`);
      }
    }
  }
}
