import { t } from 'spacetimedb/server';
import { db, type Context } from './tables';
import { gameStellarWeather } from './game-tables';
import { now, tickAt, NEVER } from './rules';
import { dueJobs, event } from './game-model';
import { hasStellarStorm, STELLAR_STORM } from '../../shared/stellarWeather';

function announce(ctx: Context, systemId: number, message: string, tone = 'warning') {
  const star = ctx.db.star.id.find(systemId)!;
  for (const p of ctx.db.gamePlayer.iter())
    if (p.surveyed.includes(systemId) || star.ownerId === p.id)
      event(ctx, p.id, `${star.name}: ${message}`, tone);
}

export function discoverStellarWeather(ctx: Context, systemId: number) {
  if (ctx.db.gameStellarWeather.id.find(systemId)) return;
  const object = ctx.db.gameObject.id.find(`${systemId}:0`);
  const meta = ctx.db.gameSystem.id.find(systemId)!;
  if (!object || object.state !== 'active' || !hasStellarStorm(JSON.parse(object.bodyJson), meta.externalId))
    return;
  const at = now(ctx),
    startsAt = at + STELLAR_STORM.warningDays;
  ctx.db.gameStellarWeather.insert({
    id: systemId,
    objectId: object.id,
    phase: 'warning',
    discoveredAt: at,
    startsAt,
    endsAt: startsAt + STELLAR_STORM.activeDays,
    nextTick: tickAt(startsAt),
  });
  announce(
    ctx,
    systemId,
    `Sternensturm vorhergesagt. In ${STELLAR_STORM.warningDays} Tagen sinkt die Energieproduktion von Sonnenkollektoren und Dyson-Anlagen für ${STELLAR_STORM.activeDays} Tage um 75 %.`,
  );
}

/** A transformed or destroyed star cannot sustain its original eruption. Keep payout history. */
export function cancelStellarWeather(ctx: Context, systemId: number, at: number) {
  const row = ctx.db.gameStellarWeather.id.find(systemId);
  if (!row || !['warning', 'active'].includes(row.phase)) return;
  ctx.db.gameStellarWeather.id.update({
    ...row,
    phase: 'cancelled',
    endsAt: Math.min(row.endsAt, at),
    nextTick: NEVER,
  });
  announce(ctx, systemId, 'Sternveränderung beendet den vorhergesagten Sturm.', 'info');
}

export function stellarWeatherTick(ctx: Context) {
  const at = now(ctx);
  for (const row of [...ctx.db.gameStellarWeather.nextTick.filter(dueJobs(at))]) {
    const object = ctx.db.gameObject.id.find(row.objectId);
    if (!object || object.state !== 'active' || JSON.parse(object.bodyJson).stellar?.family !== 'giant') {
      cancelStellarWeather(ctx, row.id, at);
      continue;
    }
    // A delayed reducer may cross both boundaries. Deadlines never shift with wall-clock delay.
    if (at >= row.endsAt) {
      ctx.db.gameStellarWeather.id.update({ ...row, phase: 'resolved', nextTick: NEVER });
      announce(ctx, row.id, 'Sternensturm abgeklungen. Solare Anlagen produzieren wieder normal.', 'success');
    } else {
      ctx.db.gameStellarWeather.id.update({ ...row, phase: 'active', nextTick: tickAt(row.endsAt) });
      announce(
        ctx,
        row.id,
        'Sternensturm aktiv. Solare Anlagen liefern vorübergehend nur 25 % ihrer Energie.',
      );
    }
  }
}

export const visibleStellarWeather = db.view(
  { name: 'visible_stellar_weather', public: true },
  t.array(gameStellarWeather.rowType),
  (ctx) => {
    const member = ctx.db.membership.identity.find(ctx.sender);
    if (!member) return [];
    const player = ctx.db.gamePlayer.id.find(member.empireId);
    if (!player) return [];
    return [...ctx.db.gameStellarWeather.iter()].filter(
      (w) => player.surveyed.includes(w.id) || ctx.db.star.id.find(w.id)?.ownerId === player.id,
    );
  },
);
