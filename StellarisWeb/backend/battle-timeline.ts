export interface Motion {
  shipId: number;
  x: number;
  y: number;
  vx: number;
  vy: number;
}
interface Snapshot {
  day: number;
  received: number;
  rows: Map<number, Motion>;
}
export class BattleTimeline {
  private snapshots: Snapshot[] = [];
  private intervalMs = 0;
  private jitterMs = 0;
  private lastTarget = -Infinity;
  private speed = 0;
  delayMs = 0;
  capture(day: number, rows: Iterable<Motion>, received: number) {
    const last = this.snapshots.at(-1);
    if (last && day < last.day) this.reset();
    if (last && day > last.day) {
      const interval = received - last.received;
      if (interval > 0 && interval < 5000) {
        const old = this.intervalMs || interval;
        this.intervalMs = old * 0.8 + interval * 0.2;
        this.jitterMs = this.jitterMs * 0.8 + Math.abs(interval - old) * 0.2;
      }
    }
    const snapshot = {
      day,
      received: last?.day === day ? last.received : received,
      rows: new Map([...rows].map((r) => [r.shipId, r])),
    };
    if (last?.day === day) this.snapshots[this.snapshots.length - 1] = snapshot;
    else this.snapshots.push(snapshot);
    if (this.snapshots.length > 8) this.snapshots.shift();
  }
  reset() {
    this.snapshots = [];
    this.intervalMs = this.jitterMs = 0;
    this.lastTarget = -Infinity;
  }
  frame(day: number, speed: number, paused: boolean, ended = false) {
    const newest = this.snapshots.at(-1);
    if (!newest) return 0;
    if (speed !== this.speed) {
      this.speed = speed;
      this.intervalMs = 0;
      this.jitterMs = 0;
    }
    // Delay and extrapolation limits are REAL milliseconds, at every game speed.
    this.delayMs = Math.min(
      1600,
      Math.max(80, this.intervalMs || 1000 / Math.max(0.5, speed)) + this.jitterMs * 2 + 30,
    );
    if (paused || ended) {
      this.lastTarget = newest.day;
      return newest.day;
    }
    const target = Math.min(newest.day + 0.15 * speed, day - (this.delayMs / 1000) * speed);
    this.lastTarget = Math.max(this.lastTarget, target);
    return this.lastTarget;
  }
  sample(id: number, target: number, out: Motion) {
    const newest = this.snapshots.at(-1);
    const current = newest?.rows.get(id);
    if (!current) return false; // deaths/deletions must never reappear from an old snapshot
    let a = this.snapshots[0],
      b = newest!;
    for (const snap of this.snapshots) {
      if (snap.day <= target) a = snap;
      if (snap.day >= target) {
        b = snap;
        break;
      }
    }
    const before = a.rows.get(id) ?? current,
      after = b.rows.get(id) ?? current;
    const mix = b.day > a.day ? Math.min(1, Math.max(0, (target - a.day) / (b.day - a.day))) : 0;
    const extra = Math.max(0, Math.min(0.15 * this.speed, target - newest!.day));
    out.shipId = id;
    out.x = before.x + (after.x - before.x) * mix + current.vx * extra;
    out.y = before.y + (after.y - before.y) * mix + current.vy * extra;
    out.vx = before.vx + (after.vx - before.vx) * mix;
    out.vy = before.vy + (after.vy - before.vy) * mix;
    return true;
  }
}
