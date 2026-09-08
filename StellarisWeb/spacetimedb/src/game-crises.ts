import { triggerSituation } from './game-situations';
import { resourceAmounts } from '../../shared/resources';
import { RESOURCE_IDS } from '../../shared/resources';
import { SenderError } from 'spacetimedb/server';
import { CRISIS, type CrisisCommand } from '../../shared/crises';
import type { Resources } from '../../shared/game';
import type { Context } from './tables';
import { now } from './rules';
import { event, settleEconomy, refreshColonyRate } from './game-model';
import { pledgeKey } from './game-crisis-state';

const zero = { energy: 0, minerals: 0, data: 0 };
const resources = RESOURCE_IDS;
function transact(ctx: Context, owner: number, cost: Resources, reward: Resources) {
  cost = resourceAmounts(cost);
  reward = resourceAmounts(reward);
  settleEconomy(ctx, owner);
  const e = ctx.db.empire.id.find(owner)!;
  if (resources.some((k) => e[k] < cost[k])) throw new SenderError('Nicht genug verfügbare Rohstoffe.');
  ctx.db.empire.id.update({
    ...e,
    ...Object.fromEntries(resources.map((id) => [id, e[id] - cost[id] + reward[id]])),
  });
}
export function crisisForNewEmpire(ctx: Context, owner: number) {
  for (const meta of ctx.db.gameCrisis.iter()) {
    const c = ctx.db.crisis.id.find(meta.id)!;
    if (['warning', 'active', 'surge'].includes(c.phase))
      triggerSituation(ctx, owner, 'crisis', `crisis:${c.id}`, c.systemId);
  }
}
export function createCrisisWorld(ctx: Context) {
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
  for (const p of ctx.db.gamePlayer.iter()) crisisForNewEmpire(ctx, p.id);
  event(
    ctx,
    0,
    'Resonanzkaskade: Eine galaktische Störung kündigt sich an. Gemeinsame Stabilisierung ist möglich.',
    'warning',
  );
}
export function surveyedCrisis(ctx: Context, systemId: number) {
  const star = ctx.db.star.id.find(systemId)!;
  if (star.kind === 'rift') {
    const c = [...ctx.db.crisis.iter()].find(
      (c) => c.systemId === systemId && ctx.db.gameCrisis.id.find(c.id),
    );
    if (c) warning(ctx, c.id);
  }
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
  event(
    ctx,
    0,
    'Die Resonanzkaskade ist eingedämmt. Kolonien arbeiten wieder normal; Forschungsdaten wurden an die Beteiligten verteilt.',
    'success',
  );
}
export function crisisAction(ctx: Context, owner: number, id: number, action: string) {
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
    event(ctx, owner, 'Ein Stabilisierungspaket wurde bereitgestellt. Nach Eindämmung: +40 Daten.', 'info');
    if (meta.progress + 1 >= meta.target) contain(ctx, id);
  }
}
export function crisisTick(ctx: Context) {
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
}
export function applyCrisisCommand(ctx: Context, owner: number, cmd: CrisisCommand) {
  if (!Number.isSafeInteger(cmd.crisisId) || cmd.crisisId <= 0) throw new SenderError('Ungültige Krise.');
  crisisAction(ctx, owner, cmd.crisisId, cmd.action);
}
