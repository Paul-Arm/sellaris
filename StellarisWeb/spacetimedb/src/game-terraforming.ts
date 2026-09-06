import { SenderError, t } from 'spacetimedb/server';
import { db, type Context } from './tables';
import { gameTerraform } from './game-tables';
import { member, now } from './rules';
import { tickAt } from './rules';
import { dueJobs, event, refreshColonyRate, settleEconomy, settlePopulation } from './game-model';
import { isEnvironment, PLANET_COLORS, terraformingSpec } from '../../shared/terraforming';
import { ENVIRONMENTS } from '../../shared/empireCatalog';
import type { CelestialBody } from '../../shared/celestial';

export const startTerraforming = db.reducer(
  { objectId: t.string(), revision: t.u32(), target: t.string() },
  (ctx, { objectId, revision, target }) => {
    const owner = member(ctx),
      object = ctx.db.gameObject.id.find(objectId);
    if (!ctx.db.gameSettings.id.find(1) || ctx.db.gameSettings.id.find(1)!.winnerId)
      throw new SenderError('Partie nicht verfügbar.');
    if (!object || object.state !== 'active' || ctx.db.star.id.find(object.systemId)?.ownerId !== owner)
      throw new SenderError('Terraforming ist nur auf eigenen Planeten möglich.');
    if (object.revision !== revision) throw new SenderError('Der Planet wurde zwischenzeitlich verändert.');
    const player = ctx.db.gamePlayer.id.find(owner)!;
    if (!player.techs.includes('terraforming')) throw new SenderError('Erforsche zuerst Klimagestaltung.');
    if (!player.surveyed.includes(object.systemId)) throw new SenderError('Untersuche zuerst das System.');
    const body: CelestialBody = JSON.parse(object.bodyJson);
    if (body.kind !== 'planet' || !body.environment || !isEnvironment(target))
      throw new SenderError('Ungültiges Terraforming-Ziel.');
    if (body.environment === target) throw new SenderError('Der Planet besitzt bereits dieses Klima.');
    if (ctx.db.gameTerraform.id.find(objectId)) throw new SenderError('Terraforming läuft bereits.');
    settleEconomy(ctx, owner);
    const spec = terraformingSpec(body.environment, target),
      empire = ctx.db.empire.id.find(owner)!;
    if (
      empire.energy < spec.cost.energy ||
      empire.minerals < spec.cost.minerals ||
      empire.science < spec.cost.science
    )
      throw new SenderError('Nicht genug Rohstoffe für Terraforming.');
    const at = now(ctx);
    ctx.db.empire.id.update({
      ...empire,
      energy: empire.energy - spec.cost.energy,
      minerals: empire.minerals - spec.cost.minerals,
      science: empire.science - spec.cost.science,
    });
    ctx.db.gameTerraform.insert({
      id: objectId,
      systemId: object.systemId,
      empireId: owner,
      from: body.environment,
      target,
      startedAt: at,
      finishAt: at + spec.days,
      finishTick: tickAt(at + spec.days),
      paidEnergy: spec.cost.energy,
      paidMinerals: spec.cost.minerals,
      paidScience: spec.cost.science,
    });
    event(ctx, owner, `Terraforming bei ${body.name}: Ziel ${ENVIRONMENTS[target].name}.`);
  },
);
export const cancelTerraforming = db.reducer({ objectId: t.string() }, (ctx, { objectId }) => {
  const owner = member(ctx),
    project = ctx.db.gameTerraform.id.find(objectId);
  if (!project || project.empireId !== owner) throw new SenderError('Kein eigenes Terraforming-Projekt.');
  if (ctx.db.gameSettings.id.find(1)?.winnerId) throw new SenderError('Die Partie ist beendet.');
  if (ctx.db.star.id.find(project.systemId)?.ownerId !== owner)
    throw new SenderError('Das System wurde verloren.');
  settleEconomy(ctx, owner);
  const empire = ctx.db.empire.id.find(owner)!;
  ctx.db.empire.id.update({
    ...empire,
    energy: empire.energy + project.paidEnergy / 2,
    minerals: empire.minerals + project.paidMinerals / 2,
    science: empire.science + project.paidScience / 2,
  });
  ctx.db.gameTerraform.id.delete(objectId);
  event(ctx, owner, 'Terraforming abgebrochen. 50 % aller Projektkosten erstattet.');
});
export function completeTerraforming(ctx: Context) {
  const at = now(ctx);
  for (const project of [...ctx.db.gameTerraform.finishTick.filter(dueJobs(at))]) {
    const object = ctx.db.gameObject.id.find(project.id);
    const body: CelestialBody | undefined = object ? JSON.parse(object.bodyJson) : undefined;
    if (
      !object ||
      object.state !== 'active' ||
      body?.kind !== 'planet' ||
      body.environment !== project.from ||
      ctx.db.star.id.find(project.systemId)?.ownerId !== project.empireId ||
      !isEnvironment(project.target)
    ) {
      ctx.db.gameTerraform.id.delete(project.id);
      event(
        ctx,
        project.empireId,
        'Terraforming durch Verlust oder Veränderung des Planeten beendet; Kosten verloren.',
        'warning',
      );
      continue;
    }
    settleEconomy(ctx, project.empireId, at);
    if (body.main) {
      settlePopulation(ctx, project.systemId, at, true);
      const meta = ctx.db.gameSystem.id.find(project.systemId)!;
      ctx.db.gameSystem.id.update({ ...meta, planet: ENVIRONMENTS[project.target].name });
      refreshColonyRate(ctx, project.systemId, project.empireId);
    }
    // Reread after population settlement, which may synchronize the primary body.
    const latest = ctx.db.gameObject.id.find(project.id)!;
    ctx.db.gameObject.id.update({
      ...latest,
      revision: latest.revision + 1,
      changedAt: at,
      bodyJson: JSON.stringify({
        ...JSON.parse(latest.bodyJson),
        environment: project.target,
        color: PLANET_COLORS[project.target],
        description: `${ENVIRONMENTS[project.target].name}.${body.main ? ' Die Hauptwelt des Systems.' : ' Ein Planet mit veränderbarem Klima.'}`,
      }),
    });
    ctx.db.gameTerraform.id.delete(project.id);
    event(
      ctx,
      project.empireId,
      `${body.name} wurde zur ${ENVIRONMENTS[project.target].name} terraformt.`,
      'success',
    );
  }
}
export const myTerraformProjects = db.view(
  { name: 'my_terraform_projects', public: true },
  t.array(gameTerraform.rowType),
  (ctx) => {
    const owner = ctx.db.membership.identity.find(ctx.sender)?.empireId;
    return owner ? [...ctx.db.gameTerraform.empireId.filter(owner)] : [];
  },
);
