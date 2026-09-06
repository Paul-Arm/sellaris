import { type Battle, type Context } from './tables';
import { type Fighter } from '../../backend/domain';

function totals(fighters: Fighter[], side: number) {
  let ships = 0,
    hull = 0,
    shield = 0;
  for (const p of fighters)
    if (p.side === side && p.hull > 0) {
      ships++;
      hull += p.hull;
      shield += p.shield;
    }
  return { ships, hull, shield };
}

export function ensureBattleReport(ctx: Context, b: Battle, fighters: Fighter[], wallAt: number) {
  const existing = ctx.db.battleReport.id.find(b.id);
  if (existing) return existing;
  const a = totals(fighters, 0),
    d = totals(fighters, 1);
  return ctx.db.battleReport.insert({
    id: b.id,
    systemId: b.systemId,
    attackers: b.attackers,
    defenders: b.defenders,
    attackerDamage: 0,
    defenderDamage: 0,
    nextPublishWallAt: wallAt + 1,
    report: {
      id: b.id,
      systemId: b.systemId,
      state: b.state,
      attackers: b.attackers,
      defenders: b.defenders,
      winnerId: b.winnerId,
      sampledAt: b.simulatedAt,
      baselineAt: b.simulatedAt,
      tracked: b.state === 'active',
      attackerLosses: b.attackerLosses,
      defenderLosses: b.defenderLosses,
      attacker: { ...a, startingHull: a.hull, startingShield: a.shield, damageDealt: 0 },
      defender: { ...d, startingHull: d.hull, startingShield: d.shield, damageDealt: 0 },
    },
  });
}

export function publishBattleReport(
  ctx: Context,
  b: Battle,
  fighters: Fighter[],
  wallAt: number,
  force = false,
) {
  const r = ensureBattleReport(ctx, b, fighters, wallAt);
  if (!force && wallAt < r.nextPublishWallAt) return;
  ctx.db.battleReport.id.update({
    ...r,
    nextPublishWallAt: wallAt + 1,
    report: {
      ...r.report,
      state: b.state,
      winnerId: b.winnerId,
      sampledAt: b.simulatedAt,
      attackerLosses: b.attackerLosses,
      defenderLosses: b.defenderLosses,
      attacker: { ...r.report.attacker, ...totals(fighters, 0), damageDealt: r.attackerDamage },
      defender: { ...r.report.defender, ...totals(fighters, 1), damageDealt: r.defenderDamage },
    },
  });
}

export function recordBattleDamage(ctx: Context, battleId: number, attacker: number, defender: number) {
  if (!attacker && !defender) return;
  const r = ctx.db.battleReport.id.find(battleId)!;
  ctx.db.battleReport.id.update({
    ...r,
    attackerDamage: r.attackerDamage + attacker,
    defenderDamage: r.defenderDamage + defender,
  });
}
