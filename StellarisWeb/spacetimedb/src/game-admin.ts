import { SenderError, t } from 'spacetimedb/server';
import { db } from './tables';
import { admin, now } from './rules';
import { event, settleEconomy } from './game-model';
import { foundEmpire } from './game-world';
import { starterLibrary, snapshotTemplate } from '../../shared/empires';
import { validAdminEmpireAction } from '../../shared/admin';

export const administerGame = db.reducer({ actionJson: t.string() }, (ctx, { actionJson }) => {
  admin(ctx);
  let action: unknown;
  try {
    action = JSON.parse(actionJson);
  } catch {
    throw new SenderError('Ungültige Admin-Aktion.');
  }
  if (!validAdminEmpireAction(action)) throw new SenderError('Ungültige Admin-Aktion.');
  const config = ctx.db.gameSettings.id.find(1);
  if (!config || config.winnerId) throw new SenderError('Partie nicht verfügbar oder beendet.');
  if (action.action === 'add_ai') {
    const library = starterLibrary();
    const n = Number(ctx.db.empire.count()) + 1;
    const snapshot = snapshotTemplate(library, library.empires[n % library.empires.length].id);
    snapshot.empire.name += ` ${n}`;
    foundEmpire(ctx, `ai-${n}`, snapshot, true);
    event(ctx, 0, `Administration: KI-Reich ${snapshot.empire.name} hinzugefügt.`);
    return;
  }
  const empire = ctx.db.empire.id.find(action.empireId);
  if (!empire || !ctx.db.gamePlayer.id.find(action.empireId)) throw new SenderError('Reich nicht gefunden.');
  if (action.action === 'host') {
    if (empire.ai || !ctx.db.gamePresence.id.find(empire.id)?.online)
      throw new SenderError('Der neue Host muss ein verbundener Mensch sein.');
    ctx.db.gameSettings.id.update({ ...config, hostId: empire.id });
    event(
      ctx,
      0,
      `Administration: ${ctx.db.empireSummary.id.find(empire.id)!.name} übernimmt die Zeitsteuerung.`,
    );
  } else {
    settleEconomy(ctx, empire.id, now(ctx));
    const settled = ctx.db.empire.id.find(empire.id)!;
    const amount = settled[action.resource] + action.amount;
    if (amount < 0 || amount > 1000000000)
      throw new SenderError('Ressourcenbestand außerhalb des erlaubten Bereichs.');
    ctx.db.empire.id.update({ ...settled, [action.resource]: amount });
    const resource = { energy: 'Energie', minerals: 'Mineralien', data: 'Daten' }[action.resource];
    event(
      ctx,
      empire.id,
      `Administration: ${action.amount > 0 ? '+' : ''}${action.amount} ${resource} gebucht.`,
    );
  }
});
