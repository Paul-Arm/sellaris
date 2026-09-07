import { SenderError } from 'spacetimedb/server';
import type { Resources } from '../../shared/game';
import { OFFER_LIFETIME, TRUCE_DURATION, type DiplomacyCommand } from '../../shared/diplomacy';
import { db, type Context } from './tables';
import { admin, finishBattle, now } from './rules';
import { event, settleEconomy } from './game-model';
import { atWar, pairKey } from './game-relations';

const zero = (): Resources => ({ energy: 0, minerals: 0, data: 0 });
const keys = ['energy', 'minerals', 'data'] as const;
const sum = (r: Resources) => r.energy + r.minerals + r.data;
function amounts(value: unknown): Resources {
  if (!value || typeof value !== 'object') throw new SenderError('Rohstoffmengen fehlen.');
  const r = value as Resources;
  if (keys.some((k) => !Number.isSafeInteger(r[k]) || r[k] < 0 || r[k] > 10000))
    throw new SenderError('Je Rohstoff sind ganze Mengen von 0 bis 10.000 erlaubt.');
  return { energy: r.energy, minerals: r.minerals, data: r.data };
}
function transfer(ctx: Context, owner: number, debit: Resources, credit: Resources) {
  const e = ctx.db.empire.id.find(owner)!;
  if (keys.some((k) => e[k] < debit[k])) throw new SenderError('Nicht genug verfügbare Rohstoffe.');
  ctx.db.empire.id.update({ ...e, ...Object.fromEntries(keys.map((k) => [k, e[k] - debit[k] + credit[k]])) });
}
function relation(ctx: Context, a: number, b: number, state: string, truceUntil = 0) {
  const id = pairKey(a, b),
    row = {
      id,
      empireA: Math.min(a, b),
      empireB: Math.max(a, b),
      state,
      truceUntil,
      changedAt: now(ctx),
    };
  if (ctx.db.gameRelation.id.find(id)) ctx.db.gameRelation.id.update(row);
  else ctx.db.gameRelation.insert(row);
}
type Treaty = NonNullable<ReturnType<Context['db']['treaty']['id']['find']>>;
function close(ctx: Context, t: Treaty, status: string) {
  if (t.status !== 'pending') return;
  const offer = ctx.db.gameOffer.id.find(t.id)!;
  transfer(ctx, t.empireA, zero(), offer.give);
  ctx.db.treaty.id.update({ ...t, status });
}
function notifyPair(ctx: Context, a: number, b: number, text: string, tone = 'info') {
  event(ctx, a, text, tone);
  event(ctx, b, text, tone);
}
const between = (t: Treaty, a: number, b: number) => pairKey(t.empireA, t.empireB) === pairKey(a, b);
export function expireDiplomacy(ctx: Context, at: number) {
  for (const offer of ctx.db.gameOffer.iter()) {
    const t = ctx.db.treaty.id.find(offer.id)!;
    if (t.status === 'pending' && t.expiresAt <= at) {
      close(ctx, t, 'expired');
      notifyPair(
        ctx,
        t.empireA,
        t.empireB,
        'Diplomatisches Angebot abgelaufen. Reservierte Rohstoffe zurückgebucht.',
      );
    }
  }
  // Bound retained history; active offers are never pruned.
  const history = [...ctx.db.gameOffer.iter()]
    .filter((o) => ctx.db.treaty.id.find(o.id)!.status !== 'pending')
    .sort((a, b) => b.id - a.id);
  for (const o of history.slice(200)) {
    ctx.db.gameOffer.id.delete(o.id);
    ctx.db.treaty.id.delete(o.id);
  }
}
export function applyDiplomacy(ctx: Context, owner: number, cmd: DiplomacyCommand) {
  const at = now(ctx);
  expireDiplomacy(ctx, at);
  if (cmd.type === 'declare_war' || cmd.type === 'offer_treaty') {
    if (typeof cmd.empireId !== 'string') throw new SenderError('Ungültiges Reich.');
    const target = ctx.db.gamePlayer.externalId.find(cmd.empireId)?.id;
    if (!target || target === owner) throw new SenderError('Wähle ein anderes Reich.');
    const war = atWar(ctx, owner, target),
      r = ctx.db.gameRelation.id.find(pairKey(owner, target));
    if (cmd.type === 'declare_war') {
      if (war) throw new SenderError('Ihr befindet euch bereits im Krieg.');
      if (r && r.truceUntil > at) throw new SenderError('Der Waffenstillstand gilt noch.');
      relation(ctx, owner, target, 'war');
      for (const t of [...ctx.db.treaty.empireA.filter(owner), ...ctx.db.treaty.empireB.filter(owner)])
        if (between(t, owner, target) && ctx.db.gameOffer.id.find(t.id)) close(ctx, t, 'cancelled');
      event(
        ctx,
        0,
        `${ctx.db.empireSummary.id.find(owner)!.name} erklärt ${ctx.db.empireSummary.id.find(target)!.name} den Krieg.`,
        'warning',
      );
      return;
    }
    if (!['peace', 'trade'].includes(cmd.kind)) throw new SenderError('Unbekannter Vertrag.');
    if (cmd.kind === 'peace' && !war) throw new SenderError('Ihr lebt bereits in Frieden.');
    if (cmd.kind === 'trade' && war) throw new SenderError('Handel erfordert Frieden.');
    const existing = [...ctx.db.treaty.empireA.filter(owner), ...ctx.db.treaty.empireB.filter(owner)].filter(
      (t) => t.status === 'pending',
    );
    if (existing.some((t) => between(t, owner, target) && t.kind === cmd.kind))
      throw new SenderError('Zwischen diesen Reichen liegt bereits ein solches Angebot vor.');
    if (existing.filter((t) => t.empireA === owner).length >= 8)
      throw new SenderError('Höchstens acht offene Angebote.');
    const give = cmd.kind === 'trade' ? amounts(cmd.give) : zero(),
      receive = cmd.kind === 'trade' ? amounts(cmd.receive) : zero();
    if (cmd.kind === 'trade' && sum(give) + sum(receive) === 0)
      throw new SenderError('Wähle Rohstoffe zum Tausch.');
    settleEconomy(ctx, owner, at);
    transfer(ctx, owner, give, zero());
    const t = ctx.db.treaty.insert({
      id: 0,
      empireA: owner,
      empireB: target,
      kind: cmd.kind,
      status: 'pending',
      expiresAt: at + OFFER_LIFETIME,
    });
    ctx.db.gameOffer.insert({ id: t.id, give, receive, createdAt: at });
    notifyPair(
      ctx,
      owner,
      target,
      `${ctx.db.empireSummary.id.find(owner)!.name} bietet ${cmd.kind === 'peace' ? 'Frieden' : 'einen Rohstofftausch'} an.`,
    );
    return;
  }
  if (!Number.isSafeInteger(cmd.treatyId) || cmd.treatyId <= 0) throw new SenderError('Ungültiges Angebot.');
  const t = ctx.db.treaty.id.find(cmd.treatyId),
    offer = ctx.db.gameOffer.id.find(cmd.treatyId);
  if (!t || !offer || (owner !== t.empireA && owner !== t.empireB))
    throw new SenderError('Angebot nicht verfügbar.');
  if (t.status !== 'pending' || t.expiresAt <= at)
    throw new SenderError('Dieses Angebot ist nicht mehr offen.');
  if (cmd.type === 'cancel_treaty') {
    if (owner !== t.empireA) throw new SenderError('Nur der Absender kann ein Angebot zurückziehen.');
    close(ctx, t, 'cancelled');
    notifyPair(ctx, t.empireA, t.empireB, 'Diplomatisches Angebot zurückgezogen.');
    return;
  }
  if (owner !== t.empireB || typeof cmd.accept !== 'boolean')
    throw new SenderError('Nur der Empfänger kann antworten.');
  if (!cmd.accept) {
    close(ctx, t, 'rejected');
    notifyPair(ctx, t.empireA, t.empireB, 'Diplomatisches Angebot abgelehnt.');
    return;
  }
  if (t.kind === 'peace') {
    if (!atWar(ctx, t.empireA, t.empireB)) throw new SenderError('Ihr lebt bereits in Frieden.');
    relation(ctx, t.empireA, t.empireB, 'peace', at + TRUCE_DURATION);
    for (const b of ctx.db.battle.state.filter('active'))
      if (pairKey(b.attackers, b.defenders) === pairKey(t.empireA, t.empireB))
        finishBattle(ctx, b.id, at, true);
    event(
      ctx,
      0,
      `${ctx.db.empireSummary.id.find(t.empireA)!.name} und ${ctx.db.empireSummary.id.find(t.empireB)!.name} schließen Frieden.`,
      'success',
    );
  } else {
    if (atWar(ctx, t.empireA, t.empireB)) throw new SenderError('Handel erfordert Frieden.');
    settleEconomy(ctx, t.empireA, at);
    settleEconomy(ctx, t.empireB, at);
    transfer(ctx, t.empireB, offer.receive, offer.give);
    transfer(ctx, t.empireA, zero(), offer.receive);
    notifyPair(ctx, t.empireA, t.empireB, 'Rohstofftausch abgeschlossen.', 'success');
  }
  ctx.db.treaty.id.update({ ...t, status: 'accepted' });
}
/** Additive upgrade: keep existing battles at war, leave all other pairs peaceful. */
export const initializeDiplomacy = db.reducer((ctx) => {
  admin(ctx);
  for (const b of ctx.db.battle.state.filter('active'))
    if (!ctx.db.gameRelation.id.find(pairKey(b.attackers, b.defenders)))
      relation(ctx, b.attackers, b.defenders, 'war');
});
export function diplomacyAI(ctx: Context, owner: number) {
  for (const t of ctx.db.treaty.empireB.filter(owner)) {
    const o = ctx.db.gameOffer.id.find(t.id);
    if (!o || t.status !== 'pending' || t.expiresAt <= now(ctx)) continue;
    const value = (r: Resources) => r.energy + r.minerals * 1.2 + r.data * 2;
    const e = ctx.db.empire.id.find(owner)!;
    const accept =
      t.kind === 'peace' || (value(o.give) >= value(o.receive) && keys.every((k) => e[k] >= o.receive[k]));
    applyDiplomacy(ctx, owner, { type: 'respond_treaty', treatyId: t.id, accept });
  }
}
