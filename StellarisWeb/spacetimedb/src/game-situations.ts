import { SenderError, t } from 'spacetimedb/server';
import { db, type Context, type ReadContext } from './tables';
import { gameSituation } from './game-tables';
import { now, tickAt, NEVER } from './rules';
import { event, settleEconomy, refreshColonyRate, dueJobs } from './game-model';
import { EVENT_DEFINITIONS, EVENT_POOL } from '../../shared/events/catalog';
import {
  EVENT_LIMITS,
  TERMINAL,
  matches,
  selectEvent,
  definitionKey,
  createSituation,
  advanceSituation,
  chooseEvent,
  recordHistory,
} from '../../shared/events/engine';
import type {
  DirectorState,
  EventContext,
  EventDefinition,
  EventEffect,
  Facts,
  SituationCommand,
  SituationState,
} from '../../shared/events/types';
import type { EmpireState } from '../../shared/empireState';
import { empireModifiers } from '../../shared/empireState';
import { RESOURCE_IDS, type Resources } from '../../shared/resources';
import { pledgeKey } from './game-crisis-state';
import { crisisAction } from './game-crises';
type Row = NonNullable<ReturnType<Context['db']['gameSituation']['id']['find']>>;
function director(ctx: Context, owner: number): DirectorState {
  const row = ctx.db.gameEventDirector.id.find(owner);
  if (row) return JSON.parse(row.stateJson);
  const state: DirectorState = { lastDay: now(ctx), sequence: 0, flags: {}, history: {}, recent: [] };
  ctx.db.gameEventDirector.insert({ id: owner, stateJson: JSON.stringify(state) });
  return state;
}
function saveDirector(ctx: Context, owner: number, state: DirectorState) {
  ctx.db.gameEventDirector.id.update({ id: owner, stateJson: JSON.stringify(state) });
}
export function situationContext(
  ctx: Context | ReadContext,
  owner: number,
  systemId: number,
  trigger: string,
  key: string,
): EventContext {
  const at = 'timestamp' in ctx ? now(ctx as Context) : Math.floor(ctx.db.clock.id.find(1)!.gameTime);
  const p = ctx.db.gamePlayer.id.find(owner)!;
  const empire: EmpireState = JSON.parse(p.empireJson);
  const meta = ctx.db.gameSystem.id.find(systemId),
    star = ctx.db.star.id.find(systemId);
  const flags: Facts = JSON.parse(ctx.db.gameEventDirector.id.find(owner)?.stateJson ?? '{"flags":{}}').flags;
  const modifiers = empireModifiers(empire);
  const owned = [...ctx.db.star.ownerId.filter(owner)];
  const sourceCrisis = [...ctx.db.crisis.iter()].find((c) => c.systemId === systemId);
  const sourcePledge = sourceCrisis
    ? ctx.db.gameCrisisPledge.id.find(pledgeKey(sourceCrisis.id, owner))
    : undefined;
  return {
    day: at,
    trigger,
    key,
    facts: {
      ...Object.fromEntries(Object.entries(flags).map(([k, v]) => [`flag.${k}`, v])),
      ...Object.fromEntries(Object.entries(modifiers).map(([k, v]) => [`modifier.${k}`, v])),
      day: at,
      techs: p.techs,
      speciesKinds: [...new Set(empire.species.map((s) => s.kind))],
      speciesCount: empire.species.length,
      traits: [...new Set(empire.species.flatMap((s) => s.traits))],
      speciesGeneration: Math.max(0, ...empire.species.map((s) => s.generation)),
      modifiers: (empire.economyModifiers ?? []).map((m) => m.id),
      modifierCount: (empire.economyModifiers ?? []).length,
      ownedSystems: owned.length,
      surveyedSystems: p.surveyed.length,
      colonies:
        [...ctx.db.colony.empireId.filter(owner)].length +
        [...ctx.db.gamePlanetColony.empireId.filter(owner)].length,
      systemId: meta?.externalId ?? '',
      systemKind: star?.kind ?? '',
      anomaly: !!meta?.anomaly,
      systemOwned: star?.ownerId === owner,
      sourceCrisisActive: !!sourceCrisis && ['warning', 'active', 'surge'].includes(sourceCrisis.phase),
      sourceCrisisShielded: sourcePledge?.shielded ?? false,
      crisis: [...ctx.db.crisis.iter()].some((c) => ['warning', 'active', 'surge'].includes(c.phase)),
    },
  };
}
function nextTick(s: SituationState, d: EventDefinition) {
  if (s.status === 'active') return tickAt(s.updatedAt + 1);
  const stage = d.stages[s.stage];
  if (s.status === 'decision' && stage.timeoutDays) return tickAt(s.enteredAt + stage.timeoutDays);
  return NEVER;
}
function save(ctx: Context, row: Row, state: SituationState) {
  ctx.db.gameSituation.id.update({
    ...row,
    stateJson: JSON.stringify(state),
    nextTick: nextTick(state, EVENT_DEFINITIONS[row.definitionId]),
  });
}
function open(ctx: Context, owner: number, d: EventDefinition, systemId: number, key: string) {
  const context = situationContext(ctx, owner, systemId, 'project', key),
    dir = director(ctx, owner);
  const historyKey = definitionKey(d, context);
  if (d.repeat !== 'repeat' && dir.history[historyKey]) return;
  const sourceKey = `${owner}:${d.id}:${key}`;
  if (ctx.db.gameSituation.sourceKey.find(sourceKey)) return;
  const p = ctx.db.gamePlayer.id.find(owner)!;
  const state = createSituation(
    d,
    context.day,
    `${ctx.db.gameSettings.id.find(1)!.code}:${sourceKey}`,
    JSON.parse(p.empireJson).primarySpeciesId,
  );
  ctx.db.gameSituation.insert({
    id: 0,
    empireId: owner,
    definitionId: d.id,
    sourceKey,
    systemId,
    stateJson: JSON.stringify(state),
    nextTick: nextTick(state, d),
  });
  dir.history[historyKey] = { lastDay: context.day, count: (dir.history[historyKey]?.count ?? 0) + 1 };
  saveDirector(ctx, owner, dir);
  event(
    ctx,
    owner,
    `${d.kind === 'project' ? 'Spezialprojekt entdeckt' : 'Neue Übertragung'}: ${d.title}`,
    'info',
  );
  const archived = [...ctx.db.gameSituation.empireId.filter(owner)]
    .filter((r) => TERMINAL.has(JSON.parse(r.stateJson).status))
    .sort((a, b) => b.id - a.id);
  for (const row of archived.slice(EVENT_LIMITS.archived)) ctx.db.gameSituation.id.delete(row.id);
}
/** Server-only trigger bus. Producers supply facts; content never needs a reducer of its own. */
export function triggerSituation(
  ctx: Context,
  owner: number,
  trigger: string,
  key: string,
  systemId = 0,
  extra: Facts = {},
) {
  if (!ctx.db.gamePlayer.id.find(owner)) return;
  const dir = director(ctx, owner),
    context = situationContext(ctx, owner, systemId, trigger, `${trigger}:${key}`);
  Object.assign(context.facts, extra);
  const active = [...ctx.db.gameSituation.empireId.filter(owner)].filter(
    (r) => !TERMINAL.has(JSON.parse(r.stateJson).status),
  ).length;
  const selected = selectEvent(
    EVENT_POOL,
    dir,
    context,
    `${ctx.db.gameSettings.id.find(1)!.code}:${owner}`,
    active,
  );
  if (dir.recent.includes(context.key)) return;
  dir.recent = [...dir.recent, context.key].slice(-256);
  dir.sequence++;
  saveDirector(ctx, owner, dir);
  if (selected) open(ctx, owner, selected, systemId, context.key);
}
function pay(ctx: Context, owner: number, cost: Resources = {}) {
  settleEconomy(ctx, owner);
  const e = ctx.db.empire.id.find(owner)!;
  if (RESOURCE_IDS.some((r) => e[r] < (cost[r] ?? 0)))
    throw new SenderError('Nicht genug verfügbare Rohstoffe.');
  ctx.db.empire.id.update({
    ...e,
    ...Object.fromEntries(RESOURCE_IDS.map((r) => [r, e[r] - (cost[r] ?? 0)])),
  });
}
function effects(ctx: Context, row: Row, state: SituationState, list: EventEffect[]) {
  if (!list.length) return;
  settleEconomy(ctx, row.empireId);
  for (const effect of list) {
    if (effect.type === 'resources') {
      const e = ctx.db.empire.id.find(row.empireId)!;
      ctx.db.empire.id.update({
        ...e,
        ...Object.fromEntries(RESOURCE_IDS.map((r) => [r, Math.max(0, e[r] + (effect.amounts[r] ?? 0))])),
      });
    } else if (effect.type === 'flag') {
      const dir = director(ctx, row.empireId);
      dir.flags[effect.key] = effect.value;
      saveDirector(ctx, row.empireId, dir);
    } else if (effect.type === 'project') {
      open(
        ctx,
        row.empireId,
        EVENT_DEFINITIONS[effect.definition],
        row.systemId,
        `follow:${row.id}:${state.stage}`,
      );
    } else if (effect.type === 'crisis') {
      const crisis = [...ctx.db.crisis.iter()].find((c) => c.systemId === row.systemId);
      if (!crisis) throw new SenderError('Krise nicht verfügbar.');
      crisisAction(ctx, row.empireId, crisis.id, effect.action);
    } else {
      const p = ctx.db.gamePlayer.id.find(row.empireId)!,
        empire: EmpireState = JSON.parse(p.empireJson);
      const target =
        effect.type === 'modifier' ? empire : empire.species.find((s) => s.id === state.speciesId);
      if (!target) throw new SenderError('Zielspezies nicht verfügbar.');
      target.economyModifiers = [
        ...(target.economyModifiers ?? []).filter((m) => m.id !== effect.modifier.id),
        effect.modifier,
      ];
      if (effect.type === 'species_modifier' && effect.evolve) {
        const species = empire.species.find((s) => s.id === state.speciesId)!;
        species.generation++;
        empire.history.push({
          tick: now(ctx),
          kind: 'species',
          text: `${species.name}: Generation ${species.generation} durch ${EVENT_DEFINITIONS[row.definitionId].title}.`,
        });
      }
      empire.revision++;
      ctx.db.gamePlayer.id.update({ ...p, empireJson: JSON.stringify(empire) });
      for (const colony of ctx.db.colony.empireId.filter(p.id)) refreshColonyRate(ctx, colony.id, p.id);
    }
  }
}
export function applySituationCommand(ctx: Context, owner: number, cmd: SituationCommand) {
  if (!Number.isSafeInteger(cmd.id)) throw new SenderError('Ungültiges Ereignis.');
  const row = ctx.db.gameSituation.id.find(cmd.id);
  if (!row || row.empireId !== owner) throw new SenderError('Ereignis nicht verfügbar.');
  const state: SituationState = JSON.parse(row.stateJson),
    d = EVENT_DEFINITIONS[row.definitionId];
  if (cmd.type === 'situation_ack') {
    if (!Number.isSafeInteger(cmd.notice) || cmd.notice < 1 || cmd.notice > state.notice)
      throw new SenderError('Ungültige Benachrichtigung.');
    if (cmd.notice > state.seen) {
      state.seen = cmd.notice;
      save(ctx, row, state);
    }
    return;
  }
  if (!Number.isSafeInteger(cmd.revision) || state.revision !== cmd.revision)
    throw new SenderError('Der Projektstand hat sich geändert. Bitte erneut auswählen.');
  const context = situationContext(ctx, owner, row.systemId, 'command', row.sourceKey);
  if (cmd.type === 'situation_choice') {
    if (state.status !== 'decision') throw new SenderError('Keine offene Entscheidung.');
    const stage = d.stages[state.stage];
    if (stage.timeoutDays && context.day >= state.enteredAt + stage.timeoutDays)
      throw new SenderError('Entscheidungsfrist abgelaufen.');
    const choice = stage.choices?.find((c) => c.id === cmd.choice);
    if (!choice || !matches(choice.when, context.facts))
      throw new SenderError('Entscheidung nicht verfügbar.');
    let result: EventEffect[];
    try {
      result = chooseEvent(state, d, cmd.choice, context);
    } catch (e) {
      throw new SenderError((e as Error).message);
    }
    pay(ctx, owner, choice.cost);
    effects(ctx, row, state, result);
  } else if (cmd.type === 'situation_start') {
    if (state.status !== 'available') throw new SenderError('Projekt bereits gestartet.');
    pay(ctx, owner, d.startCost);
    state.status = d.stages[0].choices?.length ? 'decision' : 'active';
    state.updatedAt = state.enteredAt = context.day;
    state.revision++;
    recordHistory(state, context.day, 'Projekt gestartet');
  } else if (cmd.type === 'situation_pause') {
    if (state.status !== 'active') throw new SenderError('Nur laufende Arbeit kann pausiert werden.');
    effects(ctx, row, state, advanceSituation(state, d, context));
    if (state.status === 'active') {
      state.status = 'paused';
      state.revision++;
      recordHistory(state, context.day, 'Arbeit pausiert');
    }
  } else if (cmd.type === 'situation_resume') {
    if (state.status !== 'paused') throw new SenderError('Projekt ist nicht pausiert.');
    state.status = 'active';
    state.updatedAt = context.day;
    state.revision++;
    recordHistory(state, context.day, 'Arbeit fortgesetzt');
  } else throw new SenderError('Unbekannter Ereignisbefehl.');
  state.seen = state.notice;
  save(ctx, row, state);
}
export function situationsTick(ctx: Context) {
  const at = now(ctx);
  for (const row of ctx.db.gameSituation.nextTick.filter(dueJobs(at))) {
    const s: SituationState = JSON.parse(row.stateJson),
      d = EVENT_DEFINITIONS[row.definitionId];
    effects(
      ctx,
      row,
      s,
      advanceSituation(s, d, situationContext(ctx, row.empireId, row.systemId, 'time', row.sourceKey)),
    );
    save(ctx, row, s);
  }
  for (const p of ctx.db.gamePlayer.iter()) {
    const dir = director(ctx, p.id);
    if (at - dir.lastDay < EVENT_LIMITS.intervalDays) continue;
    dir.lastDay = at;
    saveDirector(ctx, p.id, dir);
    triggerSituation(ctx, p.id, 'time', `day:${Math.floor(at / EVENT_LIMITS.intervalDays)}`, p.homeId);
  }
}
export function situationsAI(ctx: Context, owner: number) {
  for (const row of ctx.db.gameSituation.empireId.filter(owner)) {
    const state: SituationState = JSON.parse(row.stateJson),
      d = EVENT_DEFINITIONS[row.definitionId];
    const e = ctx.db.empire.id.find(owner)!;
    if (state.status === 'available' && RESOURCE_IDS.every((r) => e[r] >= (d.startCost?.[r] ?? 0)))
      applySituationCommand(ctx, owner, { type: 'situation_start', id: row.id, revision: state.revision });
    if (state.status === 'decision') {
      const choice = d.stages[state.stage].choices?.find(
        (c) =>
          !c.effects?.some((e) => e.type === 'crisis') &&
          matches(c.when, situationContext(ctx, owner, row.systemId, 'ai', row.sourceKey).facts) &&
          RESOURCE_IDS.every((r) => e[r] >= (c.cost?.[r] ?? 0)),
      );
      if (
        choice &&
        !(
          d.stages[state.stage].timeoutDays &&
          now(ctx) >= state.enteredAt + d.stages[state.stage].timeoutDays!
        )
      )
        applySituationCommand(ctx, owner, {
          type: 'situation_choice',
          id: row.id,
          revision: state.revision,
          choice: choice.id,
        });
    }
  }
}
export const mySituations = db.view(
  { name: 'my_situations', public: true },
  t.array(
    t.object('SituationSnapshot', {
      id: t.u32(),
      definitionId: t.string(),
      systemId: t.u32(),
      stateJson: t.string(),
      availableChoices: t.array(t.string()),
    }),
  ),
  (ctx) => {
    const member = ctx.db.membership.identity.find(ctx.sender);
    return member
      ? [...ctx.db.gameSituation.empireId.filter(member.empireId)].map((row) => {
          const state: SituationState = JSON.parse(row.stateJson),
            d = EVENT_DEFINITIONS[row.definitionId];
          const facts = situationContext(ctx, member.empireId, row.systemId, 'view', row.sourceKey).facts;
          return {
            id: row.id,
            definitionId: row.definitionId,
            systemId: row.systemId,
            stateJson: row.stateJson,
            availableChoices: (d.stages[state.stage]?.choices ?? [])
              .filter((c) => matches(c.when, facts))
              .map((c) => c.id),
          };
        })
      : [];
  },
);
