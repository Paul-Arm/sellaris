import { SenderError } from 'spacetimedb/server';
import { FACILITIES, facilitySpec, facilityFits, type SiteCommand } from '../../shared/celestial';
import {
  MEGASTRUCTURES,
  isMegastructure,
  megastructureHost,
  megastructureStage,
  megastructureTerritory,
} from '../../shared/megastructures';
import { storedSystemBodies, addSystemObject, removeSystemObject } from './game-objects';
import {
  bodyPosition,
  validPoint,
  localPosition,
  fleetAnchor,
  BUILD_REACH,
  type Point3,
} from '../../shared/navigation';
import { type Context } from './tables';
import { now, NEVER, tickAt } from './rules';
import { dueJobs, event, settleEconomy } from './game-model';

export function constructionTarget(
  ctx: Context,
  cmd: Exclude<SiteCommand, { type: 'site_cancel' }>,
  at: number,
) {
  const system = ctx.db.gameSystem.externalId.find(cmd.systemId);
  if (!system) throw new SenderError('System nicht gefunden.');
  if (cmd.type === 'station_place') return { point: cmd.point, radius: 0, systemId: system.id };
  const bodies = storedSystemBodies(ctx, system.id),
    body = bodies.find((b) => b.slot === cmd.bodySlot);
  if (!body) throw new SenderError('Bauobjekt nicht gefunden.');
  return { point: bodyPosition(body, bodies, at), radius: body.radius, systemId: system.id };
}
function requireBuilder(
  ctx: Context,
  owner: number,
  fleetId: string | undefined,
  target: { point: Point3; radius: number; systemId: number },
) {
  const meta = fleetId ? ctx.db.gameFleet.externalId.find(fleetId) : undefined;
  const fleet = meta && ctx.db.fleet.id.find(meta.id);
  if (
    !fleet ||
    fleet.empireId !== owner ||
    fleet.systemId !== target.systemId ||
    fleet.route.length ||
    fleet.battleId
  )
    throw new SenderError('Ein eigenes Schiff muss zum Bauplatz fliegen.');
  const nav = ctx.db.gameNavigation.id.find(fleet.id);
  const p = nav ? localPosition(JSON.parse(nav.motionJson), now(ctx)) : fleetAnchor(fleetId!);
  if (
    Math.hypot(p.x - target.point.x, p.y - target.point.y, p.z - target.point.z) >
    target.radius + BUILD_REACH
  )
    throw new SenderError('Schiff ist noch zu weit vom Bauplatz entfernt.');
}
export function applySiteCommand(ctx: Context, owner: number, cmd: SiteCommand, validateOnly = false) {
  const at = now(ctx);
  if (cmd.type === 'megastructure_place') {
    const system = ctx.db.gameSystem.externalId.find(cmd.systemId);
    const star = system && ctx.db.star.id.find(system.id);
    if (
      !isMegastructure(cmd.facility) ||
      !star ||
      !system ||
      !megastructureTerritory(cmd.facility, star.kind, star.ownerId, owner)
    )
      throw new SenderError('Megastruktur benötigt ein eigenes System mit Außenposten.');
    const definition = MEGASTRUCTURES[cmd.facility];
    const player = ctx.db.gamePlayer.id.find(owner)!;
    if (!player.surveyed.includes(system.id) || !player.techs.includes('megastructures'))
      throw new SenderError('System untersuchen und Megakonstruktion erforschen.');
    const bodies = storedSystemBodies(ctx, system.id),
      host = bodies.find((b) => b.slot === cmd.bodySlot);
    if (!host || !megastructureHost(cmd.facility, host)) throw new SenderError(definition.hostHint);
    if (bodies.some((b) => b.megastructure && b.parent === host.slot))
      throw new SenderError('An diesem Himmelskörper existiert bereits eine Megastruktur.');
    settleEconomy(ctx, owner);
    const cost = facilitySpec(cmd.facility, 0).cost,
      empire = ctx.db.empire.id.find(owner)!;
    if (empire.energy < cost.energy || empire.minerals < cost.minerals)
      throw new SenderError('Nicht genug Rohstoffe.');
    if (validateOnly) return;
    requireBuilder(ctx, owner, cmd.fleetId, constructionTarget(ctx, cmd, at));
    const row = addSystemObject(ctx, system.id, {
      kind: 'station',
      megastructure: cmd.facility,
      parent: host.slot,
      name: `${definition.name} ${host.name}`,
      radius: host.radius,
      orbit: 0,
      phase: 0,
      period: 1,
      color: definition.color,
      description: definition.description,
    });
    applySiteCommand(ctx, owner, {
      type: 'site_build',
      systemId: cmd.systemId,
      bodySlot: row.slot,
      facility: cmd.facility,
      fleetId: cmd.fleetId,
    });
    return;
  }
  if (cmd.type === 'station_place') {
    if (!validPoint(cmd.point) || !['habitat', 'research'].includes(cmd.facility))
      throw new SenderError('Ungültige Stationsposition.');
    const system = ctx.db.gameSystem.externalId.find(cmd.systemId);
    if (
      !system ||
      ctx.db.star.id.find(system.id)?.ownerId !== owner ||
      !ctx.db.gamePlayer.id.find(owner)!.surveyed.includes(system.id)
    )
      throw new SenderError('Stationen benötigen ein eigenes untersuchtes System.');
    const bodies = storedSystemBodies(ctx, system.id);
    if (bodies.filter((b) => b.kind === 'station').length >= 24)
      throw new SenderError('Maximal 24 freie Stationen je System.');
    for (const b of bodies) {
      const pos = bodyPosition(b, bodies, at);
      if (Math.hypot(cmd.point.x - pos.x, cmd.point.y - pos.y, cmd.point.z - pos.z) < b.radius + 60)
        throw new SenderError('Zu nah an einem Systemobjekt.');
      // Keep fixed stations clear of complete orbital paths, including moon envelopes.
      if (!b.position) {
        const parent = b.parent === undefined ? undefined : bodies.find((p) => p.slot === b.parent);
        const orbit = parent ? parent.orbit : b.orbit,
          envelope = b.radius + 40 + (parent ? b.orbit : 0);
        if (Math.hypot(Math.hypot(cmd.point.x, cmd.point.z) - orbit, cmd.point.y - pos.y) < envelope)
          throw new SenderError('Diese Position liegt zu nah an einer Umlaufbahn.');
      }
    }
    const cost = facilitySpec(cmd.facility, 0).cost;
    settleEconomy(ctx, owner);
    const empire = ctx.db.empire.id.find(owner)!;
    if (empire.energy < cost.energy || empire.minerals < cost.minerals)
      throw new SenderError('Nicht genug Rohstoffe für diese Anlage.');
    if (validateOnly) return;
    requireBuilder(ctx, owner, cmd.fleetId, constructionTarget(ctx, cmd, at));
    const row = addSystemObject(ctx, system.id, {
      kind: 'station',
      name: cmd.facility === 'research' ? 'Freie Forschungsstation' : 'Freies Orbitalhabitat',
      color: '#95bfc8',
      radius: 12,
      orbit: 0,
      phase: 0,
      period: 1,
      position: cmd.point,
      description: 'Frei platzierte Station im Systemraum.',
    });
    applySiteCommand(ctx, owner, {
      type: 'site_build',
      systemId: cmd.systemId,
      bodySlot: row.slot,
      facility: cmd.facility,
      fleetId: cmd.fleetId,
    });
    return;
  }
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
    if (!site.level) {
      const object = ctx.db.gameObject.id.find(site.id);
      if (object && JSON.parse(object.bodyJson).kind === 'station')
        removeSystemObject(ctx, site.id, object.revision);
    }
    event(ctx, owner, 'Anlagenbau abgebrochen. 50 % der Baukosten erstattet.');
    return;
  }
  if (
    typeof cmd.systemId !== 'string' ||
    !Number.isInteger(cmd.bodySlot) ||
    cmd.bodySlot < 0 ||
    cmd.bodySlot > 0xffffffff ||
    !Object.hasOwn(FACILITIES, cmd.facility)
  )
    throw new SenderError('Ungültiger Anlagenbau.');
  const meta = ctx.db.gameSystem.externalId.find(cmd.systemId);
  if (!meta) throw new SenderError('System nicht gefunden.');
  const system = ctx.db.star.id.find(meta.id)!,
    p = ctx.db.gamePlayer.id.find(owner)!;
  if (!p.surveyed.includes(system.id)) throw new SenderError('Untersuche zuerst das System.');
  if (system.ownerId !== owner) throw new SenderError('Errichte zuerst einen Außenposten in diesem System.');
  const body = storedSystemBodies(ctx, system.id).find((b) => b.slot === cmd.bodySlot);
  if (!body || !facilityFits(cmd.facility, body))
    throw new SenderError('Diese Anlage passt nicht zu diesem Himmelskörper.');
  if (isMegastructure(cmd.facility)) {
    const host = storedSystemBodies(ctx, system.id).find((b) => b.slot === body.parent);
    if (!p.techs.includes('megastructures') || !host || !megastructureHost(cmd.facility, host))
      throw new SenderError('Megakonstruktion und ein geeigneter aktiver Himmelskörper werden benötigt.');
  }
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
  if (validateOnly) return;
  requireBuilder(ctx, owner, cmd.fleetId, constructionTarget(ctx, cmd, at));
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
    finishAt: at + spec.days,
    finishTick: tickAt(at + spec.days),
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
    const body = isMegastructure(site.facility)
      ? storedSystemBodies(ctx, site.systemId).find((b) => b.slot === site.bodySlot)
      : undefined;
    const host = body
      ? storedSystemBodies(ctx, site.systemId).find((b) => b.slot === body.parent)
      : undefined;
    if (
      s.ownerId !== site.empireId ||
      (isMegastructure(site.facility) &&
        (!body ||
          !host ||
          !megastructureHost(site.facility, host) ||
          !megastructureTerritory(site.facility, s.kind, s.ownerId, site.empireId)))
    ) {
      // Retained stations are dormant until their owner's system is recovered.
      ctx.db.gameSite.id.update({
        ...site,
        building: false,
        finishTick: NEVER,
        paidEnergy: 0,
        paidMinerals: 0,
      });
      event(ctx, site.empireId, 'Anlagenbau durch Verlust des Systems oder Bauziels abgebrochen.', 'warning');
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
      isMegastructure(site.facility)
        ? `${FACILITIES[site.facility].name}: ${megastructureStage(site.facility, site.level + 1)} fertiggestellt.`
        : `${FACILITIES[site.facility as keyof typeof FACILITIES].name} Stufe ${site.level + 1} einsatzbereit.`,
      'success',
    );
  }
}
