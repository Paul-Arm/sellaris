import { SenderError } from 'spacetimedb/server';
import { FACILITIES, facilitySpec, systemBodies, type SiteCommand } from '../../shared/celestial';
import { type Context } from './tables';
import { now, NEVER, tickAt } from './rules';
import { dueJobs, event, settleEconomy, systemModel } from './game-model';

export function applySiteCommand(ctx: Context, owner: number, cmd: SiteCommand) {
  const at = now(ctx);
  if (cmd.type === 'site_cancel') {
    if (typeof cmd.siteId !== 'string') throw new SenderError('Ungültiger Bauplatz.');
    const site = ctx.db.gameSite.id.find(cmd.siteId);
    if (!site || site.empireId !== owner || !site.building)
      throw new SenderError('Kein eigener laufender Bauauftrag.');
    settleEconomy(ctx, owner);
    const e = ctx.db.empire.id.find(owner)!;
    ctx.db.empire.id.update({
      ...e,
      energy: e.energy + site.paidEnergy / 2,
      minerals: e.minerals + site.paidMinerals / 2,
    });
    if (!site.level) ctx.db.gameSite.id.delete(site.id);
    else
      ctx.db.gameSite.id.update({
        ...ctx.db.gameSite.id.find(site.id)!,
        building: false,
        finishTick: NEVER,
        paidEnergy: 0,
        paidMinerals: 0,
      });
    event(ctx, owner, 'Anlagenbau abgebrochen. 50 % der Baukosten erstattet.');
    return;
  }
  if (
    typeof cmd.systemId !== 'string' ||
    !Number.isInteger(cmd.bodySlot) ||
    cmd.bodySlot < 0 ||
    cmd.bodySlot > 8 ||
    !Object.hasOwn(FACILITIES, cmd.facility)
  )
    throw new SenderError('Ungültiger Anlagenbau.');
  const meta = ctx.db.gameSystem.externalId.find(cmd.systemId);
  if (!meta) throw new SenderError('System nicht gefunden.');
  const system = ctx.db.star.id.find(meta.id)!,
    p = ctx.db.gamePlayer.id.find(owner)!;
  if (!p.surveyed.includes(system.id)) throw new SenderError('Untersuche zuerst das System.');
  if (system.ownerId !== owner) {
    if (system.ownerId || system.kind === 'star') throw new SenderError('Baue nur in eigenen Sternsystemen.');
    if (
      ![...ctx.db.fleet.systemId.filter(system.id)].some(
        (f) => f.empireId === owner && !f.battleId && !f.route.length,
      )
    )
      throw new SenderError('Für eine Außenstation muss eine eigene Flotte vor Ort sein.');
  }
  const body = systemBodies(systemModel(ctx, system.id)).find((b) => b.slot === cmd.bodySlot);
  if (!body || !FACILITIES[cmd.facility].kinds.includes(body.kind))
    throw new SenderError('Diese Anlage passt nicht zu diesem Himmelskörper.');
  const id = `${system.id}:${body.slot}`,
    old = ctx.db.gameSite.id.find(id);
  if (old && old.empireId !== owner) throw new SenderError('Dieser Bauplatz gehört einem anderen Reich.');
  if (old?.building) throw new SenderError('An diesem Körper wird bereits gebaut.');
  if (old && old.facility !== cmd.facility) throw new SenderError('Der Anlagenplatz ist bereits belegt.');
  if ((old?.level || 0) >= 3) throw new SenderError('Maximale Ausbaustufe erreicht.');
  settleEconomy(ctx, owner);
  const spec = facilitySpec(cmd.facility, old?.level || 0),
    e = ctx.db.empire.id.find(owner)!;
  if (e.energy < spec.cost.energy || e.minerals < spec.cost.minerals)
    throw new SenderError('Nicht genug Rohstoffe für diese Anlage.');
  ctx.db.empire.id.update({
    ...e,
    energy: e.energy - spec.cost.energy,
    minerals: e.minerals - spec.cost.minerals,
  });
  const row = {
    id,
    systemId: system.id,
    bodySlot: body.slot,
    empireId: owner,
    facility: cmd.facility,
    level: old?.level || 0,
    building: true,
    startedAt: at,
    finishAt: at + spec.seconds,
    finishTick: tickAt(at + spec.seconds),
    paidEnergy: spec.cost.energy,
    paidMinerals: spec.cost.minerals,
    lastProducedAt: ctx.db.gameSite.id.find(id)?.lastProducedAt ?? at,
  };
  if (old) ctx.db.gameSite.id.update(row);
  else ctx.db.gameSite.insert(row);
  event(ctx, owner, `${FACILITIES[cmd.facility].name} bei ${body.name} in Auftrag gegeben.`);
}
export function completeSites(ctx: Context) {
  const at = now(ctx);
  for (const site of [...ctx.db.gameSite.finishTick.filter(dueJobs(at))]) {
    if (!site.building) continue;
    const s = ctx.db.star.id.find(site.systemId)!;
    if (s.kind === 'star' && s.ownerId !== site.empireId) {
      // Retained stations are dormant until their owner's system is recovered.
      ctx.db.gameSite.id.update({
        ...site,
        building: false,
        finishTick: NEVER,
        paidEnergy: 0,
        paidMinerals: 0,
      });
      event(ctx, site.empireId, 'Anlagenbau durch Verlust des Systems abgebrochen.', 'warning');
      continue;
    }
    settleEconomy(ctx, site.empireId, at);
    ctx.db.gameSite.id.update({
      ...ctx.db.gameSite.id.find(site.id)!,
      level: site.level + 1,
      building: false,
      finishTick: NEVER,
      paidEnergy: 0,
      paidMinerals: 0,
      lastProducedAt: site.level ? ctx.db.gameSite.id.find(site.id)!.lastProducedAt : at,
    });
    event(
      ctx,
      site.empireId,
      `${FACILITIES[site.facility as keyof typeof FACILITIES].name} Stufe ${site.level + 1} einsatzbereit.`,
      'success',
    );
  }
}
