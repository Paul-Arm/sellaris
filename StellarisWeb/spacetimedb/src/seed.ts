import { ScheduleAt } from 'spacetimedb';
import { SenderError, t } from 'spacetimedb/server';
import { seededRandom, validateScenario } from '../../backend/domain';
import { db, type Context } from './tables';
import { admin, enterBattle, move, shipTemplate, tickAt, wallNow } from './rules';

export const configure = db.reducer(
  {
    seed: t.u32(),
    systems: t.u32(),
    empires: t.u32(),
    fleetsPerEmpire: t.u32(),
    shipsPerEmpire: t.u32(),
    battleCount: t.u32(),
    battleFleetsPerSide: t.u32(),
    cohortsPerColony: t.u32(),
    popsPerCohort: t.u32(),
  },
  (ctx, s) => {
    admin(ctx);
    if (ctx.db.scenario.id.find(1))
      throw new SenderError(
        'Create a separate database for each scenario; reconfiguration never deletes a world',
      );
    validateScenario(s);
    ctx.db.scenario.insert({ ...s, id: 1, seededShips: 0, phase: 'seeding', schemaVersion: 1 });
    ctx.db.clock.insert({ id: 1, gameTime: 0, wallTime: wallNow(ctx), speed: 1, paused: true });
    const random = seededRandom(s.seed);
    for (let i = 1; i <= s.systems; i++) {
      const sector = (i - 1) % s.empires;
      const angle = ((sector + random() * 0.8) / s.empires) * Math.PI * 2;
      const radius = 500 + Math.sqrt(random()) * 4500;
      ctx.db.star.insert({
        id: i,
        name: `SYS ${String(i).padStart(4, '0')}`,
        x: Math.cos(angle) * radius,
        y: Math.sin(angle) * radius,
        kind: i % 47 === 0 ? 'rift' : i % 71 === 0 ? 'blackhole' : 'star',
        ownerId: sector + 1,
      });
    }
    for (let id = 1; id <= s.empires; id++) {
      ctx.db.empire.insert({
        id,
        energy: 10000,
        minerals: 10000,
        data: 5000,
        productionModifier: 1,
        researchLevel: 0,
        ai: true,
        nextDecisionTick: tickAt(1 + id * 0.2),
        aiCursor: 0,
        seededShips: 0,
      });
      ctx.db.empireSummary.insert({
        id,
        name: `Imperium ${String(id).padStart(2, '0')}`,
        color: Math.floor(random() * 0xffffff),
        ai: true,
      });
      const systems = [...ctx.db.star.ownerId.filter(id)];
      for (const system of systems.slice(0, 10)) {
        let energyRate = 0,
          mineralsRate = 0,
          dataRate = 0;
        for (let c = 0; c < s.cohortsPerColony; c++) {
          const job = ['technician', 'miner', 'researcher'][c % 3];
          ctx.db.cohort.insert({
            id: 0,
            colonyId: system.id,
            empireId: id,
            species: `species-${id % 5}`,
            job,
            count: s.popsPerCohort,
            productivity: 1,
            happiness: 0.75,
          });
          if (job === 'technician') energyRate += s.popsPerCohort * 0.1;
          if (job === 'miner') mineralsRate += s.popsPerCohort * 0.08;
          if (job === 'researcher') dataRate += s.popsPerCohort * 0.05;
        }
        ctx.db.colony.insert({
          id: system.id,
          empireId: id,
          population: s.cohortsPerColony * s.popsPerCohort,
          energyRate,
          mineralsRate,
          dataRate,
          lastProducedAt: 0,
        });
      }
      for (let f = 0; f < s.fleetsPerEmpire; f++) {
        const origin = systems[f % systems.length];
        ctx.db.fleet.insert({
          id: 0,
          empireId: id,
          name: `${id}. Flotte ${f + 1}`,
          systemId: origin.id,
          shipCount: 0,
          formation: 'wedge',
          order: 'idle',
          battleId: 0,
          route: [],
          fromX: origin.x,
          fromY: origin.y,
          toX: origin.x,
          toY: origin.y,
          departedAt: 0,
          arrivesAt: 0,
          speed: 65 + (f % 5) * 5,
          revision: 0,
        });
      }
      ctx.db.job.insert({
        id: 0,
        empireId: id,
        kind: 'research',
        topic: 'extraction',
        targetId: id,
        workDone: 0,
        workTotal: 90 + id,
        rate: 1,
        updatedAt: 0,
        dueTick: tickAt(90 + id),
        status: 'active',
      });
      ctx.db.job.insert({
        id: 0,
        empireId: id,
        kind: 'construction',
        topic: 'corvette',
        targetId: (id - 1) * s.fleetsPerEmpire + s.fleetsPerEmpire,
        workDone: 0,
        workTotal: 60 + id,
        rate: 1,
        updatedAt: 0,
        dueTick: tickAt(60 + id),
        status: 'active',
      });
      ctx.db.decision.insert({
        id: 0,
        empireId: id,
        kind: 'anomaly-response',
        phase: 'pending',
        deadlineAt: 180 + id,
        outcome: '',
      });
      ctx.db.trade.insert({
        id: 0,
        empireId: id,
        fromSystem: systems[0].id,
        toSystem: systems[1].id,
        energyPerCycle: 4,
        deliveredAt: 0,
        status: 'active',
      });
    }
    ctx.db.crisis.insert({ id: 1, systemId: s.systems, phase: 'dormant', nextPhaseAt: 120 });
    ctx.db.treaty.insert({
      id: 0,
      empireA: s.empires - 1,
      empireB: s.empires,
      kind: 'research-exchange',
      status: 'active',
      expiresAt: 240,
    });
  },
);

/** Bounded, restartable seeding transactions; offsets persist so retries cannot duplicate ships. */
export const seedShips = db.reducer(
  { empireId: t.u32(), expectedOffset: t.u32(), count: t.u32() },
  (ctx, { empireId, expectedOffset, count }) => {
    admin(ctx);
    const config = ctx.db.scenario.id.find(1);
    const e = ctx.db.empire.id.find(empireId);
    if (!config || config.phase !== 'seeding' || !e) throw new SenderError('Not seeding this empire');
    if (e.seededShips !== expectedOffset) throw new SenderError('Seed cursor changed; reload before retry');
    if (!count || count > 1000 || expectedOffset + count > config.shipsPerEmpire)
      throw new SenderError('Seed batch must fit remaining ships, at most 1000');
    const fleetCounts = new Map<number, number>();
    for (let i = expectedOffset; i < expectedOffset + count; i++) {
      const fleetId =
        (empireId - 1) * config.fleetsPerEmpire +
        Math.floor((i * config.fleetsPerEmpire) / config.shipsPerEmpire) +
        1;
      ctx.db.ship.insert(shipTemplate(empireId, fleetId, i));
      fleetCounts.set(fleetId, (fleetCounts.get(fleetId) ?? 0) + 1);
    }
    for (const [id, added] of fleetCounts) {
      const f = ctx.db.fleet.id.find(id)!;
      ctx.db.fleet.id.update({ ...f, shipCount: f.shipCount + added });
    }
    ctx.db.empire.id.update({ ...e, seededShips: expectedOffset + count });
    ctx.db.scenario.id.update({ ...config, seededShips: config.seededShips + count });
  },
);

export function schedule(ctx: Context) {
  ctx.db.strategicSchedule.insert({ id: 0n, scheduledAt: ScheduleAt.interval(250_000n) });
  ctx.db.economySchedule.insert({ id: 0n, scheduledAt: ScheduleAt.interval(1_000_000n) });
  ctx.db.combatSchedule.insert({ id: 0n, scheduledAt: ScheduleAt.interval(100_000n) });
  ctx.db.aiSchedule.insert({ id: 0n, scheduledAt: ScheduleAt.interval(200_000n) });
  for (const name of ['strategic', 'economy', 'combat', 'ai']) {
    ctx.db.runtime.insert({
      name,
      lastWallAt: wallNow(ctx),
      nextGameAt: name === 'economy' ? 4 : 0,
      calls: 0,
      rowsChanged: 0n,
      lastLagMs: 0,
      maxLagMs: 0,
    });
  }
}

export const activate = db.reducer((ctx) => {
  admin(ctx);
  const config = ctx.db.scenario.id.find(1);
  if (!config || config.phase !== 'seeding' || config.seededShips !== config.empires * config.shipsPerEmpire)
    throw new SenderError('Seeding is incomplete or world already activated');
  for (let i = 0; i < config.battleCount; i++) {
    const ids: number[] = [];
    const system = ctx.db.star.id.find(i * 2 + 1)!;
    for (const empireId of [i * 2 + 1, i * 2 + 2]) {
      for (const f of [...ctx.db.fleet.empireId.filter(empireId)]
        .sort((a, b) => a.id - b.id)
        .slice(0, config.battleFleetsPerSide)) {
        ctx.db.fleet.id.update({
          ...f,
          systemId: system.id,
          fromX: system.x,
          fromY: system.y,
          toX: system.x,
          toY: system.y,
        });
        ids.push(f.id);
      }
    }
    enterBattle(ctx, ids, system.id, 0);
  }
  for (const e of ctx.db.empire.iter()) {
    const systems = [...ctx.db.star.ownerId.filter(e.id)];
    let i = 0;
    for (const f of ctx.db.fleet.empireId.filter(e.id)) {
      if (!f.battleId) move(ctx, f, [systems[(++i + 11) % systems.length].id], 0);
    }
  }
  ctx.db.clock.id.update({ id: 1, gameTime: 0, wallTime: wallNow(ctx), speed: 1, paused: false });
  ctx.db.scenario.id.update({ ...config, phase: 'ready' });
  schedule(ctx);
});
