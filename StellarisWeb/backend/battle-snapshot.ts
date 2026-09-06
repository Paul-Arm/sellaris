import type { Client } from './client';

/** Validate the cache only after onApplied/transaction callbacks. No async reads
 * between tables: all parts must describe the same committed battle state.
 */
export function checkCompactBattle(client: Client, battleId: number, compareLegacy = false) {
  const { db } = client.conn;
  const roster = [...db.battleRoster.iter()];
  if (db.battleMotion.count() !== BigInt(roster.length) || db.battleVitals.count() !== BigInt(roster.length))
    throw new Error('Incomplete compact battle snapshot');
  const ids = new Set(roster.map((p) => p.shipId));
  // SDK 2.10's generated index.find currently scans the local table. Build maps
  // once, so this integrity check remains linear and is not a load bottleneck.
  const motions = new Map([...db.battleMotion.iter()].map((p) => [p.shipId, p]));
  const statuses = new Map([...db.battleVitals.iter()].map((p) => [p.shipId, p]));
  const legacy = compareLegacy ? new Map([...db.battleParticipants.iter()].map((p) => [p.shipId, p])) : null;
  for (const row of roster) {
    const motion = motions.get(row.shipId);
    const vitals = statuses.get(row.shipId);
    if (row.battleId !== battleId || !motion || !vitals || (vitals.targetId && !ids.has(vitals.targetId)))
      throw new Error('Mixed battle snapshot or dangling target');
    if (compareLegacy) {
      const full = legacy!.get(row.shipId);
      const projected = { ...row, ...motion, ...vitals };
      if (!full || Object.entries(projected).some(([key, value]) => full[key as keyof typeof full] !== value))
        throw new Error('Compact snapshot diverged from durable participant');
    }
  }
  if (compareLegacy && db.battleParticipants.count() !== BigInt(roster.length))
    throw new Error('Compact and legacy participant counts differ');
  return roster.length;
}
