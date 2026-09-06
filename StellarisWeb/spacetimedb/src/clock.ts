import { t } from 'spacetimedb/server';
import { db } from './tables';

/** Read-only probe: timestamp and anchor come from the simulation host in one transaction. */
export const sampleClock = db.procedure(
  {},
  t.object('ClockSample', {
    gameTime: t.f64(),
    wallTime: t.f64(),
    speed: t.f64(),
    paused: t.bool(),
    serverTime: t.f64(),
  }),
  (ctx) =>
    ctx.withTx((tx) => {
      const clock = tx.db.clock.id.find(1);
      return {
        gameTime: clock?.gameTime ?? 0,
        wallTime: clock?.wallTime ?? 0,
        speed: clock?.speed ?? 1,
        paused: clock?.paused ?? true,
        serverTime: Number(tx.timestamp.microsSinceUnixEpoch) / 1e6,
      };
    }),
);
