import { SenderError } from 'spacetimedb/server';
import { CRISIS, STORIES, type StoryKind, type StoryChoice, type StoryCommand } from '../../shared/stories';
import type { Resources } from '../../shared/game';
import { db, type Context } from './tables';
import { admin, now } from './rules';
import { event, settleEconomy, refreshColonyRate } from './game-model';
import { pledgeKey } from './game-crisis-state';

const zero = { energy: 0, minerals: 0, data: 0 };
const resources = ['energy', 'minerals', 'data'] as const;
const names = { energy: 'Energie', minerals: 'Mineralien', data: 'Daten' };
function rewardText(value: Resources) {
  return resources
    .filter((k) => value[k])
    .map((k) => `+${value[k]} ${names[k]}`)
    .join(' · ');
}
function transact(ctx: Context, owner: number, cost: Resources, reward: Resources) {
  settleEconomy(ctx, owner);
  const e = ctx.db.empire.id.find(owner)!;
  if (resources.some((k) => e[k] < cost[k])) throw new SenderError('Nicht genug verfügbare Rohstoffe.');
  ctx.db.empire.id.update({
    ...e,
    energy: e.energy - cost.energy + reward.energy,
    minerals: e.minerals - cost.minerals + reward.minerals,
    data: e.data - cost.data + reward.data,
  });
}
export function openStory(ctx: Context, owner: number, kind: StoryKind, sourceKey: string, systemId: number) {
  if (ctx.db.gameStory.sourceKey.find(sourceKey)) return;
  const at = now(ctx),
    story = STORIES[kind];
  const d = ctx.db.decision.insert({
    id: 0,
    empireId: owner,
    kind,
    phase: 'pending',
    deadlineAt: at + story.duration,
    outcome: '',
  });
  ctx.db.gameStory.insert({ id: d.id, sourceKey, systemId, createdAt: at, resolvedAt: 0, result: '' });
  event(ctx, owner, `${story.title} – eine Entscheidung wartet.`, 'warning');
}
export function storyForNewEmpire(ctx: Context, owner: number) {
  for (const meta of ctx.db.gameCrisis.iter()) {
    const c = ctx.db.crisis.id.find(meta.id)!;
    if (['warning', 'active', 'surge'].includes(c.phase))
      openStory(ctx, owner, 'resonance_v1', `crisis:${c.id}:${owner}`, c.systemId);
  }
}
export function ensureStoryWorld(ctx: Context) {
  if (!ctx.db.gameSettings.id.find(1) || ctx.db.gameCrisis.id.find(1)) return;
  const rift = [...ctx.db.star.iter()].find((s) => s.kind === 'rift');
  if (!rift) return;
  const at = now(ctx);
  ctx.db.crisis.insert({
    id: 1,
    systemId: rift.id,
    phase: 'dormant',
    nextPhaseAt: at + CRISIS.dormantSeconds,
  });
  ctx.db.gameCrisis.insert({ id: 1, kind: CRISIS.kind, target: 0, progress: 0, startedAt: at, endedAt: 0 });
}
export const initializeStories = db.reducer((ctx) => {
  admin(ctx);
  ensureStoryWorld(ctx);
});

function refreshEconomies(ctx: Context) {
  for (const c of ctx.db.colony.iter()) refreshColonyRate(ctx, c.id, c.empireId);
}
function settleAll(ctx: Context) {
  for (const e of ctx.db.gamePlayer.iter()) settleEconomy(ctx, e.id);
}
function warning(ctx: Context, id: number) {
  const c = ctx.db.crisis.id.find(id)!,
    meta = ctx.db.gameCrisis.id.find(id)!;
  if (c.phase !== 'dormant') return;
  const at = now(ctx);
  ctx.db.crisis.id.update({ ...c, phase: 'warning', nextPhaseAt: at + CRISIS.warningSeconds });
  ctx.db.gameCrisis.id.update({ ...meta, target: 3 + Math.ceil(Number(ctx.db.gamePlayer.count()) / 2) });
  for (const p of ctx.db.gamePlayer.iter()) storyForNewEmpire(ctx, p.id);
  event(
    ctx,
    0,
    'Resonanzkaskade: Eine galaktische Störung kündigt sich an. Gemeinsame Stabilisierung ist möglich.',
    'warning',
  );
}
export function surveyedStory(ctx: Context, owner: number, systemId: number, first: boolean) {
  const star = ctx.db.star.id.find(systemId)!,
    m = ctx.db.gameSystem.id.find(systemId)!;
  if (star.kind === 'rift') {
    const c = [...ctx.db.crisis.iter()].find(
      (c) => c.systemId === systemId && ctx.db.gameCrisis.id.find(c.id),
    );
    if (c) warning(ctx, c.id);
  } else if (m.anomaly && first) openStory(ctx, owner, 'archive_v1', `anomaly:${systemId}`, systemId);
}
function contain(ctx: Context, id: number) {
  const c = ctx.db.crisis.id.find(id)!,
    meta = ctx.db.gameCrisis.id.find(id)!;
  if (c.phase === 'contained') return;
  settleAll(ctx);
  ctx.db.crisis.id.update({ ...c, phase: 'contained', nextPhaseAt: 0 });
  ctx.db.gameCrisis.id.update({ ...meta, endedAt: now(ctx) });
  refreshEconomies(ctx);
  for (const p of ctx.db.gameCrisisPledge.crisisId.filter(id)) {
    if (p.contributions)
      transact(ctx, p.empireId, zero, { ...zero, data: p.contributions * CRISIS.dataPerContribution });
  }
  // Close remaining response requests without overwriting an already recorded choice.
  for (const p of ctx.db.gamePlayer.iter()) {
    const story = ctx.db.gameStory.sourceKey.find(`crisis:${id}:${p.id}`);
    if (!story) continue;
    const d = ctx.db.decision.id.find(story.id)!;
    if (d.phase === 'pending') {
      ctx.db.decision.id.update({ ...d, phase: 'resolved', outcome: 'contained' });
      ctx.db.gameStory.id.update({
        ...story,
        resolvedAt: now(ctx),
        result: 'Die Krise wurde gemeinsam eingedämmt. Kein weiterer Beschluss erforderlich.',
      });
    }
  }
  event(
    ctx,
    0,
    'Die Resonanzkaskade ist eingedämmt. Kolonien arbeiten wieder normal; Forschungsdaten wurden an die Beteiligten verteilt.',
    'success',
  );
}
function crisisAction(ctx: Context, owner: number, id: number, action: string) {
  const c = ctx.db.crisis.id.find(id),
    meta = ctx.db.gameCrisis.id.find(id);
  if (!c || !meta || !['warning', 'active', 'surge'].includes(c.phase))
    throw new SenderError('Diese Krise erfordert derzeit keinen Eingriff.');
  const key = pledgeKey(id, owner),
    old = ctx.db.gameCrisisPledge.id.find(key),
    pledge = old || { id: key, crisisId: id, empireId: owner, contributions: 0, shielded: false };
  if (action === 'contribute') {
    if (meta.progress >= meta.target) throw new SenderError('Die Stabilisierung ist bereits finanziert.');
    transact(ctx, owner, CRISIS.contributionCost, zero);
    pledge.contributions++;
  } else if (action === 'shield') {
    if (pledge.shielded) throw new SenderError('Deine Kolonien sind bereits abgeschirmt.');
    transact(ctx, owner, CRISIS.shieldCost, zero);
    pledge.shielded = true;
  } else throw new SenderError('Unbekannter Kriseneingriff.');
  if (old) ctx.db.gameCrisisPledge.id.update(pledge);
  else ctx.db.gameCrisisPledge.insert(pledge);
  if (action === 'shield') {
    for (const colony of ctx.db.colony.empireId.filter(owner)) refreshColonyRate(ctx, colony.id, owner);
    event(ctx, owner, 'Raumanker schützen deine Kolonien vor der Resonanzkaskade.', 'success');
  } else {
    ctx.db.gameCrisis.id.update({ ...meta, progress: meta.progress + 1 });
    event(
      ctx,
      owner,
      'Ein Stabilisierungspaket wurde bereitgestellt. Nach Eindämmung: +40 Daten.',
      'info',
    );
    if (meta.progress + 1 >= meta.target) contain(ctx, id);
  }
}
function resolve(ctx: Context, owner: number, id: number, choiceId: string, automatic = false) {
  const d = ctx.db.decision.id.find(id),
    story = ctx.db.gameStory.id.find(id);
  if (!d || !story || d.empireId !== owner) throw new SenderError('Entscheidung nicht verfügbar.');
  if (d.phase !== 'pending') throw new SenderError('Diese Entscheidung wurde bereits getroffen.');
  if (!automatic && d.deadlineAt <= now(ctx)) throw new SenderError('Die Entscheidungsfrist ist abgelaufen.');
  const definition = STORIES[d.kind as StoryKind];
  if (!definition) throw new SenderError('Unbekanntes Ereignis.');
  const option = definition.choices.find((o) => o.id === choiceId) as StoryChoice | undefined;
  if (!option) throw new SenderError('Unbekannte Entscheidung.');
  let result = `${option.title}. ${rewardText(option.reward)}`.trim();
  if (option.action) {
    const crisis = [...ctx.db.crisis.iter()].find(
      (c) => c.systemId === story.systemId && ctx.db.gameCrisis.id.find(c.id),
    );
    if (!crisis) throw new SenderError('Krise nicht verfügbar.');
    crisisAction(ctx, owner, crisis.id, option.action);
    result =
      option.action === 'shield'
        ? 'Alle eigenen Kolonien sind für diese Krise abgeschirmt.'
        : 'Ein Stabilisierungspaket finanziert. Nach Eindämmung: +40 Daten.';
  } else transact(ctx, owner, option.cost, option.reward);
  ctx.db.decision.id.update({ ...d, phase: automatic ? 'expired' : 'resolved', outcome: choiceId });
  ctx.db.gameStory.id.update({ ...story, resolvedAt: now(ctx), result });
  event(
    ctx,
    owner,
    `${definition.title}: ${result}${automatic ? ' (Automatische Entscheidung)' : ''}`,
    'success',
  );
}
export function storyTick(ctx: Context) {
  const at = now(ctx);
  for (const meta of ctx.db.gameCrisis.iter()) {
    const c = ctx.db.crisis.id.find(meta.id)!;
    if (c.nextPhaseAt <= 0 || c.nextPhaseAt > at) continue;
    if (c.phase === 'dormant') warning(ctx, c.id);
    else if (c.phase === 'warning' || c.phase === 'active') {
      settleAll(ctx);
      const phase = c.phase === 'warning' ? 'active' : 'surge';
      ctx.db.crisis.id.update({
        ...c,
        phase,
        nextPhaseAt: phase === 'active' ? at + CRISIS.activeSeconds : 0,
      });
      refreshEconomies(ctx);
      event(
        ctx,
        0,
        `Resonanzkaskade: Ungeschützte Kolonien produzieren ${phase === 'active' ? '25' : '50'} % weniger.`,
        'warning',
      );
    }
  }
  for (const story of ctx.db.gameStory.iter()) {
    const d = ctx.db.decision.id.find(story.id)!;
    if (d.phase === 'pending' && d.deadlineAt <= at)
      resolve(ctx, d.empireId, d.id, STORIES[d.kind as StoryKind].fallback, true);
  }
}
export function applyStoryCommand(ctx: Context, owner: number, cmd: StoryCommand) {
  if (cmd.type === 'resolve_decision') {
    if (!Number.isSafeInteger(cmd.decisionId) || cmd.decisionId <= 0 || typeof cmd.choice !== 'string')
      throw new SenderError('Ungültige Entscheidung.');
    resolve(ctx, owner, cmd.decisionId, cmd.choice);
  } else {
    if (!Number.isSafeInteger(cmd.crisisId) || cmd.crisisId <= 0) throw new SenderError('Ungültige Krise.');
    crisisAction(ctx, owner, cmd.crisisId, cmd.action);
  }
}
export function storyAI(ctx: Context, owner: number) {
  for (const d of ctx.db.decision.empireId.filter(owner)) {
    if (d.phase !== 'pending' || !ctx.db.gameStory.id.find(d.id) || d.deadlineAt <= now(ctx)) continue;
    const choices = STORIES[d.kind as StoryKind].choices;
    const e = ctx.db.empire.id.find(owner)!;
    const chosen = choices.find((o) => resources.every((r) => e[r] >= o.cost[r]));
    if (chosen) resolve(ctx, owner, d.id, chosen.id);
  }
}
