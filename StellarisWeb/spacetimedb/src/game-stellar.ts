import { SenderError } from 'spacetimedb/server';
import type { Context } from './tables';
import { NEVER } from './rules';
import { addJob, jobsFor, event, settleEconomy } from './game-model';
import { dysonHost } from '../../shared/megastructures';
import { STELLAR_COLLAPSE as COST, type StellarCommand } from '../../shared/stellarProjects';
import type { CelestialBody } from '../../shared/celestial';
import { collapseSystemStar } from './game-stellar-effects';
import { cancelStellarWeather } from './game-stellar-weather';

function collapseTarget(ctx: Context, owner: number, objectId: string, revision: number) {
  if (typeof objectId !== 'string' || !Number.isSafeInteger(revision) || revision < 1)
    throw new SenderError('Ungültiges Sternziel.');
  const object = ctx.db.gameObject.id.find(objectId);
  if (
    !object ||
    object.state !== 'active' ||
    object.revision !== revision ||
    ctx.db.star.id.find(object.systemId)?.ownerId !== owner
  )
    throw new SenderError('Eigenen unveränderten Stern auswählen.');
  const body: CelestialBody = JSON.parse(object.bodyJson);
  if (object.slot !== 0 || !dysonHost(body))
    throw new SenderError('Ein Hauptreihenstern oder Riese wird benötigt.');
  const player = ctx.db.gamePlayer.id.find(owner)!;
  if (!player.techs.includes('megastructures') || !player.surveyed.includes(object.systemId))
    throw new SenderError('Megakonstruktion und ein untersuchtes System werden benötigt.');
  const dyson = [...ctx.db.gameObject.systemId.filter(object.systemId)].find(
    (r) =>
      r.state === 'active' && r.parentId === objectId && JSON.parse(r.bodyJson).megastructure === 'dyson',
  );
  const site = dyson && ctx.db.gameSite.id.find(dyson.id);
  if (!site || site.empireId !== owner || site.level !== 3 || site.building)
    throw new SenderError(
      'Ein vollständiger eigener Dyson-Schwarm wird benötigt und beim Kollaps verbraucht.',
    );
  return { object, body, dyson: dyson! };
}

export function applyStellarCommand(ctx: Context, owner: number, cmd: StellarCommand) {
  if (cmd.type === 'stellar_cancel') {
    if (!Number.isSafeInteger(cmd.jobId) || cmd.jobId <= 0) throw new SenderError('Ungültiges Sternprojekt.');
    const job = ctx.db.job.id.find(cmd.jobId);
    if (
      !job ||
      job.empireId !== owner ||
      job.kind !== 'game_stellar' ||
      job.status !== 'active' ||
      ctx.db.star.id.find(job.targetId)?.ownerId !== owner
    )
      throw new SenderError('Kein eigenes laufendes Sternprojekt.');
    settleEconomy(ctx, owner);
    const e = ctx.db.empire.id.find(owner)!;
    ctx.db.empire.id.update({
      ...e,
      energy: e.energy + COST.energy / 2,
      minerals: e.minerals + COST.minerals / 2,
      data: e.data + COST.data / 2,
    });
    ctx.db.job.id.update({ ...job, status: 'cancelled', dueTick: NEVER });
    event(ctx, owner, 'Sternkollaps abgebrochen. 50 % der Projektkosten erstattet.');
    return;
  }
  const target = collapseTarget(ctx, owner, cmd.objectId, cmd.revision);
  if (ctx.db.gameSystem.id.find(target.object.systemId)!.externalId !== cmd.systemId)
    throw new SenderError('Stern gehört nicht zum gewählten System.');
  if (jobsFor(ctx, owner).some((j) => j.kind === 'game_stellar' && j.targetId === target.object.systemId))
    throw new SenderError('Sternprojekt läuft bereits.');
  settleEconomy(ctx, owner);
  const e = ctx.db.empire.id.find(owner)!;
  if (e.energy < COST.energy || e.minerals < COST.minerals || e.data < COST.data)
    throw new SenderError('Nicht genug Rohstoffe.');
  ctx.db.empire.id.update({
    ...e,
    energy: e.energy - COST.energy,
    minerals: e.minerals - COST.minerals,
    data: e.data - COST.data,
  });
  addJob(
    ctx,
    owner,
    'game_stellar',
    JSON.stringify({ objectId: cmd.objectId, revision: cmd.revision }),
    target.object.systemId,
    COST.days,
  );
  event(
    ctx,
    owner,
    `${target.body.name}: Kontrollierter Sternkollaps vorbereitet. Dyson-Anlage und Sonnenkollektoren werden verbraucht; Planeten vereisen.`,
    'warning',
  );
}

export function completeStellarProject(ctx: Context, job: ReturnType<typeof jobsFor>[number], at: number) {
  let target: ReturnType<typeof collapseTarget>;
  const { objectId, revision } = JSON.parse(job.topic);
  try {
    target = collapseTarget(ctx, job.empireId, objectId, revision);
  } catch (error) {
    if (!(error instanceof SenderError)) throw error;
    event(
      ctx,
      job.empireId,
      'Sternprojekt durch Verlust oder Veränderung des Ziels beendet; Kosten verloren.',
      'warning',
    );
    return 'cancelled';
  }
  const { object, body } = target;
  collapseSystemStar(ctx, object.id, at);
  cancelStellarWeather(ctx, object.systemId, at);
  const e = ctx.db.empire.id.find(job.empireId)!;
  ctx.db.empire.id.update({ ...e, data: e.data + COST.reward });
  event(
    ctx,
    0,
    `${body.name} ist zum Neutronenstern kollabiert. Dyson-Anlage und Sonnenkollektoren verloren; Planeten vereist.`,
    'warning',
  );
  event(
    ctx,
    job.empireId,
    `Sternkollaps ausgewertet: +${COST.reward} Daten. Laufendes Terraforming auf betroffenen Planeten wurde ohne Erstattung beendet.`,
    'success',
  );
  return 'complete';
}
