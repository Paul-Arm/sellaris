import { completeNativeStarbase } from './game-starbases';
import { hasShipyard } from '../../shared/starbases';
import { SHIPS, TECHS, type ShipType, type TechId } from '../../shared/game';
import { createColony, completeColonyConstruction, maxDefense, type Colony } from '../../shared/colonies';
import { empireModifiers, type EmpireState } from '../../shared/empireState';
import { type Context } from './tables';
import { NEVER, tickAt } from './rules';
import {
  event,
  jobsFor,
  makeShip,
  refreshColonyRate,
  updateColony,
  systemModel,
  settleEconomy,
  settlePopulation,
} from './game-model';
import { atWar } from './game-relations';
import { surveyedCrisis } from './game-crises';
import { triggerSituation } from './game-situations';
import { completeStellarProject } from './game-stellar';
import { discoverStellarWeather } from './game-stellar-weather';
import { completePlanetColony, completePlanetUpgrade } from './game-planet-colonies';

export function contested(ctx: Context, systemId: number, owner: number) {
  return [...ctx.db.fleet.systemId.filter(systemId)].some(
    (f) => atWar(ctx, f.empireId, owner) && ctx.db.gameFleet.id.find(f.id)?.kind === 'corvette',
  );
}
export function destroyGameFleet(ctx: Context, id: number) {
  for (const s of ctx.db.ship.fleetId.filter(id)) {
    ctx.db.ship.id.delete(s.id);
    ctx.db.gameDamaged.id.delete(s.id);
  }
  ctx.db.fleet.id.delete(id);
  ctx.db.gameFleet.id.delete(id);
  ctx.db.gameFleetCondition.id.delete(id);
  ctx.db.gameNavigation.id.delete(id);
  ctx.db.arrival.fleetId.delete(id);
}
export function completeGameJob(ctx: Context, j: ReturnType<typeof jobsFor>[number], at: number) {
  const p = ctx.db.gamePlayer.id.find(j.empireId)!;
  if (j.kind === 'game_upgrade') settleEconomy(ctx, j.empireId, at);
  if (j.kind === 'game_upgrade') settlePopulation(ctx, j.targetId, at);
  let status = 'complete';
  if (j.kind === 'game_starbase') {
    status = completeNativeStarbase(ctx, p.id, j.targetId, at);
  } else if (j.kind === 'game_planet_upgrade') {
    status = completePlanetUpgrade(ctx, p.id, j.topic, at);
  } else if (j.kind === 'game_stellar') {
    status = completeStellarProject(ctx, j, at);
  } else if (j.kind === 'game_build') {
    const system = ctx.db.star.id.find(j.targetId);
    if (system?.ownerId !== p.id || !hasShipyard(systemModel(ctx, j.targetId))) status = 'cancelled';
    else {
      const target =
        j.topic === 'corvette'
          ? [...ctx.db.fleet.systemId.filter(system.id)].find(
              (f) =>
                f.empireId === p.id && !f.battleId && ctx.db.gameFleet.id.find(f.id)?.kind === 'corvette',
            )
          : undefined;
      makeShip(ctx, p.id, system.id, j.topic as ShipType, { fleetId: target?.id });
      event(ctx, p.id, `${SHIPS[j.topic as ShipType].name} einsatzbereit.`, 'success');
    }
  } else if (j.kind === 'game_upgrade') {
    const star = ctx.db.star.id.find(j.targetId),
      m = ctx.db.gameSystem.id.find(j.targetId)!;
    if (star?.ownerId !== p.id || !m.colonyJson) status = 'cancelled';
    else {
      const c: Colony = JSON.parse(m.colonyJson);
      const before = maxDefense(systemModel(ctx, m.id));
      completeColonyConstruction(c);
      const after = maxDefense({ ...systemModel(ctx, m.id), colony: c });
      ctx.db.gameSystem.id.update({
        ...m,
        defense: Math.min(after, m.defense + Math.max(0, after - before)),
      });
      updateColony(ctx, m.id, c, p.id);
      event(ctx, p.id, `Kolonieausbau bei ${star.name} abgeschlossen.`, 'success');
    }
  } else {
    const f = ctx.db.fleet.id.find(j.targetId);
    if (!f?.systemId) status = 'cancelled';
    else {
      const system = ctx.db.star.id.find(f.systemId)!,
        m = ctx.db.gameSystem.id.find(system.id)!;
      if (j.kind === 'game_scan') {
        if (!p.surveyed.includes(system.id)) {
          const bonus = m.anomaly && !m.studied ? 90 : 25,
            e = ctx.db.empire.id.find(p.id)!;
          ctx.db.gamePlayer.id.update({ ...p, surveyed: [...p.surveyed, system.id] });
          ctx.db.empire.id.update({ ...e, data: e.data + bonus });
          if (m.anomaly) ctx.db.gameSystem.id.update({ ...m, studied: true });
          event(ctx, p.id, `${system.name} untersucht. +${bonus} Daten.`, 'success');
          surveyedCrisis(ctx, system.id);
          triggerSituation(ctx, p.id, 'survey', `survey:${system.id}`, system.id);
          discoverStellarWeather(ctx, system.id);
        }
      } else if (j.kind === 'game_colonize') {
        if (j.topic) {
          if (completePlanetColony(ctx, p.id, j.topic, f.id, at)) destroyGameFleet(ctx, f.id);
          else {
            const e = ctx.db.empire.id.find(p.id)!;
            ctx.db.empire.id.update({ ...e, energy: e.energy + 80, minerals: e.minerals + 80 });
            status = 'cancelled';
            event(ctx, p.id, 'Planetenkolonisierung abgebrochen; Kosten erstattet.', 'warning');
          }
        } else if (system.ownerId === p.id && !m.colonyJson) {
          ctx.db.gameSystem.id.update({
            ...m,
            defense: m.defense,
            colonyName: `${system.name} Prime`,
            growthAt: at,
          });
          const c = createColony(
              false,
              `${ctx.db.gameSettings.id.find(1)!.code}:${m.externalId}:1`,
              m.planet,
            ),
            instance: EmpireState = JSON.parse(p.empireJson);
          c.populations = [{ speciesId: instance.primarySpeciesId, population: c.population }];
          updateColony(ctx, system.id, c, p.id);
          destroyGameFleet(ctx, f.id);
          event(ctx, 0, `${ctx.db.empireSummary.id.find(p.id)!.name} kolonisiert ${system.name}.`, 'success');
          triggerSituation(ctx, p.id, 'colony', `colony:${system.id}`, system.id);
        } else {
          const e = ctx.db.empire.id.find(p.id)!;
          ctx.db.empire.id.update({ ...e, energy: e.energy + 80, minerals: e.minerals + 80 });
          status = 'cancelled';
          event(ctx, p.id, 'Kolonisierung abgebrochen; Kosten erstattet.', 'warning');
        }
      }
    }
  }
  ctx.db.job.id.update({ ...j, workDone: j.workTotal, updatedAt: at, status, dueTick: NEVER });
  if (j.kind === 'game_build') {
    const next = jobsFor(ctx, p.id).find((q) => q.kind === 'game_build' && q.status === 'queued');
    if (next)
      ctx.db.job.id.update({
        ...next,
        status: 'active',
        updatedAt: at,
        dueTick: tickAt(at + (next.workTotal - next.workDone) / next.rate),
      });
  }
}
