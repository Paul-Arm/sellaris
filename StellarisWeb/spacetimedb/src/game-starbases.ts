import { triggerSituation } from './game-situations';
import { SenderError } from 'spacetimedb/server';
import { applyStarbaseCommand, completeStarbase, type StarbaseCommand } from '../../shared/starbases';
import { maxDefense } from '../../shared/colonies';
import type { Context } from './tables';
import { now, NEVER } from './rules';
import { addJob, commandModel, event, jobsFor, settleEconomy, systemModel } from './game-model';
import { contested } from './game-jobs';

export function applyNativeStarbase(ctx: Context, owner: number, cmd: StarbaseCommand) {
  const meta = ctx.db.gameSystem.externalId.find(cmd.systemId);
  if (!meta) throw new SenderError('System nicht gefunden.');
  if (contested(ctx, meta.id, owner)) throw new SenderError('Feindliche Flotten verhindern den Basisbau.');
  settleEconomy(ctx, owner);
  const game = commandModel(ctx, owner),
    player = game.players[0];
  try {
    applyStarbaseCommand(game, player, cmd);
  } catch (e) {
    if (e instanceof Error && e.constructor === Error) throw new SenderError(e.message);
    throw e;
  }
  const system = game.systems.find((s) => s.id === cmd.systemId)!;
  ctx.db.empire.id.update({ ...ctx.db.empire.id.find(owner)!, ...player.resources });
  ctx.db.gameSystem.id.update({
    ...ctx.db.gameSystem.id.find(meta.id)!,
    starbaseJson: system.starbase ? JSON.stringify(system.starbase) : '',
    starbaseRevision: system.starbaseRevision ?? 0,
    defense: Math.min(system.defense, maxDefense(system)),
  });
  if (cmd.type === 'starbase_cancel') {
    for (const j of jobsFor(ctx, owner).filter((j) => j.kind === 'game_starbase' && j.targetId === meta.id))
      ctx.db.job.id.update({ ...j, status: 'cancelled', dueTick: NEVER });
    event(ctx, owner, 'Basisbau abgebrochen. 50 % der Kosten erstattet.');
  } else if (system.starbase?.project) {
    const p = system.starbase.project;
    addJob(ctx, owner, 'game_starbase', '', meta.id, p.finishAt - p.startedAt);
    event(ctx, owner, `Sternenbasis bei ${system.name}: Bauauftrag gestartet.`);
  }
}
export function completeNativeStarbase(ctx: Context, owner: number, id: number, at: number) {
  const system = systemModel(ctx, id);
  if (system.starbase?.owner !== ctx.db.gamePlayer.id.find(owner)!.externalId) return 'cancelled';
  settleEconomy(ctx, owner, at);
  const previousOwner = system.owner;
  if (!completeStarbase(system, at)) return 'cancelled';
  ctx.db.star.id.update({ ...ctx.db.star.id.find(id)!, ownerId: owner });
  ctx.db.gameSystem.id.update({
    ...ctx.db.gameSystem.id.find(id)!,
    starbaseJson: JSON.stringify(system.starbase),
    starbaseRevision: system.starbaseRevision ?? 0,
    defense: system.defense,
  });
  event(
    ctx,
    owner,
    `Sternenbasis bei ${system.name} einsatzbereit. Das System gehört deinem Reich.`,
    'success',
  );
  if (previousOwner !== system.owner) triggerSituation(ctx, owner, 'ownership', `claim:${id}:${system.starbaseRevision}`, id);
  return 'complete';
}
