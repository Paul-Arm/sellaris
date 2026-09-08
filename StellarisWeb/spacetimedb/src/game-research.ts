import { triggerSituation } from './game-situations';
import { completeTerraforming, refreshTerraformingRates } from './game-terraforming';
import { resourceAmounts } from '../../shared/resources';
import { monthsDue, monthBoundary, ECONOMY_MONTH_DAYS, modifyEconomy } from '../../shared/economy';
import { governmentModifiers } from '../../shared/empires';
import { SenderError, t } from 'spacetimedb/server';
import { db, type Context, type ReadContext } from './tables';
import { now } from './rules';
import {
  advanceResearch,
  applyResearch,
  baseCompute,
  TECHS,
  type TechId,
  type ResearchProgram,
  type ResearchCommand,
} from '../../shared/research';
import { colonyEconomy } from '../../shared/planetaryEconomy';
import { colonyPlanet } from '../../shared/planetColonies';
import { empireModifiers } from '../../shared/empireState';
import { event, settleEconomy, refreshColonyRate } from './game-model';

export function researchCapacity(ctx: Context | ReadContext, owner: number) {
  const p = ctx.db.gamePlayer.id.find(owner)!;
  const player = { empire: JSON.parse(p.empireJson) };
  let compute = modifyEconomy(
    baseCompute(p.techs as TechId[]) *
      Math.max(
        0,
        1 + governmentModifiers(player.empire.design.government, player.empire.design.origin).research,
      ),
    player.empire.economyModifiers ?? [],
    { category: 'compute' },
  ).amount;
  for (const c of ctx.db.colony.empireId.filter(owner)) {
    const s = ctx.db.gameSystem.id.find(c.id)!;
    if (s.colonyJson) compute += colonyEconomy(JSON.parse(s.colonyJson), s.planet, player).compute;
  }
  for (const c of ctx.db.gamePlanetColony.empireId.filter(owner)) {
    const body = ctx.db.gameObject.id.find(c.id);
    if (body?.state === 'active')
      compute += colonyEconomy(
        JSON.parse(c.colonyJson),
        colonyPlanet(JSON.parse(body.bodyJson)),
        player,
      ).compute;
  }
  return compute;
}
export function researchState(ctx: Context | ReadContext, owner: number): ResearchProgram {
  return JSON.parse(ctx.db.gameResearch.id.find(owner)!.programJson);
}
function applyUnlocks(ctx: Context, owner: number, completed: TechId[]) {
  if (!completed.length) return;
  const p = ctx.db.gamePlayer.id.find(owner)!;
  for (const c of ctx.db.colony.empireId.filter(owner)) refreshColonyRate(ctx, c.id, owner);
  if (completed.includes('weapons')) {
    const mods = empireModifiers(JSON.parse(p.empireJson));
    for (const s of ctx.db.ship.empireId.filter(owner)) {
      if (s.design !== 'corvette') continue;
      const weapons = s.weapons.map((w) => ({ ...w, damage: 6.5 * 1.4 * Math.max(0.1, 1 + mods.damage) }));
      ctx.db.ship.id.update({ ...s, weapons });
      const fighter = ctx.db.participant.shipId.find(s.id);
      if (fighter)
        ctx.db.participant.shipId.update({ ...fighter, damage: weapons.reduce((n, w) => n + w.damage, 0) });
    }
  }
  for (const id of completed) {
    event(ctx, owner, `${TECHS[id].name} erforscht.`, 'success');
    triggerSituation(ctx, owner, 'technology', `tech:${id}`, p.homeId, { technology: id });
  }
}
export function settleResearch(ctx: Context, owner: number, at = now(ctx)) {
  while (true) {
    const row = ctx.db.gameResearch.id.find(owner)!;
    if (!monthsDue(row.updatedAt, at)) return;
    const boundary = monthBoundary(row.updatedAt) + ECONOMY_MONTH_DAYS;
    settleEconomy(ctx, owner, boundary);
    const e = ctx.db.empire.id.find(owner)!,
      p = ctx.db.gamePlayer.id.find(owner)!;
    const player = {
      empire: JSON.parse(p.empireJson),
      research: researchState(ctx, owner),
      techs: [...p.techs] as TechId[],
      resources: resourceAmounts(e),
    };
    const completed = advanceResearch(player, researchCapacity(ctx, owner), 1);
    ctx.db.empire.id.update({ ...e, ...resourceAmounts(player.resources) });
    if (completed.length) ctx.db.gamePlayer.id.update({ ...p, techs: player.techs });
    ctx.db.gameResearch.id.update({
      ...row,
      programJson: JSON.stringify(player.research),
      updatedAt: boundary,
    });
    applyUnlocks(ctx, owner, completed);
  }
}
export function applyResearchCommand(ctx: Context, owner: number, cmd: ResearchCommand) {
  completeTerraforming(ctx);
  settleResearch(ctx, owner);
  settleEconomy(ctx, owner);
  const e = ctx.db.empire.id.find(owner)!,
    p = ctx.db.gamePlayer.id.find(owner)!;
  const player = {
    empire: JSON.parse(p.empireJson),
    research: researchState(ctx, owner),
    techs: p.techs as TechId[],
    resources: resourceAmounts(e),
  };
  try {
    applyResearch(player, cmd);
  } catch (e) {
    if (e instanceof Error && e.constructor === Error) throw new SenderError(e.message);
    throw e;
  }
  ctx.db.empire.id.update({ ...e, ...resourceAmounts(player.resources) });
  ctx.db.gameResearch.id.update({
    id: owner,
    programJson: JSON.stringify(player.research),
    updatedAt: ctx.db.gameResearch.id.find(owner)!.updatedAt,
  });
  refreshTerraformingRates(ctx, owner);
  for (const c of ctx.db.colony.empireId.filter(owner)) refreshColonyRate(ctx, c.id, owner);
}
export const myResearch = db.view(
  { name: 'my_research', public: true },
  t.array(
    t.object('ResearchSnapshot', {
      id: t.u32(),
      programJson: t.string(),
      updatedAt: t.f64(),
      compute: t.f64(),
    }),
  ),
  (ctx) => {
    const m = ctx.db.membership.identity.find(ctx.sender);
    if (!m) return [];
    const row = ctx.db.gameResearch.id.find(m.empireId);
    return row ? [{ ...row, compute: researchCapacity(ctx, m.empireId) }] : [];
  },
);
