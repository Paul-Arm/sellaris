import { planColonyDevelopment } from '../../shared/colonies';
import { systemModel } from './game-model';
import { TECHS, type ShipType, type TechId } from '../../shared/game';
import { type Context } from './tables';
import { now, tickAt } from './rules';
import { dueJobs, jobsFor } from './game-model';
import { applyGameCommand } from './game-commands';
import { atWar } from './game-relations';
import { diplomacyAI } from './game-diplomacy';
import { storyAI } from './game-stories';

export function gameAI(ctx: Context) {
  const at = now(ctx);
  let processed = 0;
  for (const candidate of ctx.db.empire.nextDecisionTick.filter(dueJobs(at))) {
    if (processed++ >= 4) break;
    if (!candidate.ai) continue;
    diplomacyAI(ctx, candidate.id);
    storyAI(ctx, candidate.id);
    const owner = candidate.id,
      p = ctx.db.gamePlayer.id.find(owner)!,
      fleets = [...ctx.db.fleet.empireId.filter(owner)],
      jobs = jobsFor(ctx, owner);
    const idle = fleets.filter(
      (f) =>
        f.systemId &&
        !f.battleId &&
        (!ctx.db.gameNavigation.id.find(f.id) || ctx.db.gameNavigation.id.find(f.id)!.ordersJson === '[]') &&
        !jobs.some((j) => ['game_scan', 'game_colonize'].includes(j.kind) && j.targetId === f.id),
    );
    // Rotate fleet priority so a busy scout cannot starve colony ships or military orders.
    const offset = idle.length ? candidate.aiCursor % idle.length : 0;
    const ordered = [...idle.slice(offset), ...idle.slice(0, offset)];
    const act = (cmd: Parameters<typeof applyGameCommand>[2]) => {
      try {
        applyGameCommand(ctx, owner, cmd);
        return true;
      } catch {
        return false;
      }
    };
    let acted = false;
    for (const f of ordered) {
      const meta = ctx.db.gameFleet.id.find(f.id)!,
        system = ctx.db.star.id.find(f.systemId)!,
        m = ctx.db.gameSystem.id.find(f.systemId)!;
      if (meta.kind === 'scout' && !p.surveyed.includes(system.id) && m.defense === 0)
        acted = act({ type: 'scan', fleetId: meta.externalId });
      if (
        meta.kind === 'colony' &&
        p.surveyed.includes(system.id) &&
        !system.ownerId &&
        m.defense === 0 &&
        system.kind === 'star'
      )
        acted = act({ type: 'colonize', fleetId: meta.externalId });
      if (acted) break;
      const targets = [...ctx.db.star.iter()].filter(
        (s) =>
          s.id !== system.id &&
          (meta.kind === 'scout'
            ? !p.surveyed.includes(s.id) && ctx.db.gameSystem.id.find(s.id)!.defense === 0
            : meta.kind === 'colony'
              ? p.surveyed.includes(s.id) &&
                !s.ownerId &&
                s.kind === 'star' &&
                ctx.db.gameSystem.id.find(s.id)!.defense === 0
              : s.ownerId > 0 && atWar(ctx, owner, s.ownerId)),
      );
      targets.sort(
        (a, b) =>
          (a.x - system.x) ** 2 + (a.y - system.y) ** 2 - ((b.x - system.x) ** 2 + (b.y - system.y) ** 2),
      );
      for (const target of targets.slice(0, 3))
        if (
          act({
            type: 'move',
            fleetId: meta.externalId,
            systemId: ctx.db.gameSystem.id.find(target.id)!.externalId,
          })
        ) {
          acted = true;
          break;
        }
      if (acted) break;
    }
    const capital =
      ctx.db.star.id.find(p.homeId)?.ownerId === owner
        ? p.homeId
        : [...ctx.db.colony.empireId.filter(owner)][0]?.id;
    const home = capital ? ctx.db.gameSystem.id.find(capital)!.externalId : '';
    // One independent economic decision per visit, fairly shared between research, ships and colonies.
    acted = false;
    if (candidate.aiCursor % 3 === 0 && !jobs.some((j) => j.kind === 'game_research'))
      for (const tech of Object.keys(TECHS) as TechId[])
        if (!p.techs.includes(tech) && act({ type: 'research', tech })) {
          acted = true;
          break;
        }
    if (
      !acted &&
      home &&
      candidate.aiCursor % 3 !== 2 &&
      jobs.filter((j) => j.kind === 'game_build').length < 2
    ) {
      const kinds = fleets.map((f) => ctx.db.gameFleet.id.find(f.id)?.kind);
      const ship: ShipType = !kinds.includes('scout')
        ? 'scout'
        : !kinds.includes('colony')
          ? 'colony'
          : 'corvette';
      acted = act({ type: 'build', ship, systemId: home });
    }
    if (!acted && home) {
      for (const owned of ctx.db.colony.empireId.filter(owner)) {
        const choice = planColonyDevelopment(systemModel(ctx, owned.id));
        if (choice && act(choice)) break;
      }
    }
    const current = ctx.db.empire.id.find(owner)!;
    ctx.db.empire.id.update({ ...current, nextDecisionTick: tickAt(at + 5), aiCursor: current.aiCursor + 1 });
  }
}
