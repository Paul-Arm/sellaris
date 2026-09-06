import { gameTimeAt, type ClockAnchor } from './domain';

export interface ClockSample extends ClockAnchor {
  serverTime: number;
}

/** Server wall clock is mapped onto performance.now(), never the user's calendar clock.
 * Low-RTT samples reject queueing spikes. Small corrections slew; pause/speed changes
 * apply immediately. A fresh connection owns a fresh clock (no old timeline leakage). */
export class ClientClock {
  private anchor?: ClockAnchor;
  private offset?: number;
  private receivedAt = 0;
  private bestRtt = Infinity;
  private sampledAt = -Infinity;
  private correction = 0;
  private correctionAt = 0;
  private correctionDuration = 1000;
  private frozen?: number;
  rttMs = 0;
  synced = false;
  constructor(private monotonic = () => performance.now()) {}

  observe(anchor: ClockAnchor, received = this.monotonic()) {
    if (this.anchor && anchor.wallTime < this.anchor.wallTime) return;
    const before = this.now(received);
    const sameRate = this.anchor?.speed === anchor.speed && this.anchor.paused === anchor.paused;
    this.anchor = anchor;
    this.receivedAt = received;
    this.frozen = undefined;
    this.correction = 0;
    if (sameRate && !anchor.paused) {
      this.correction = before - this.raw(received);
      this.correctionAt = received;
      this.correctionDuration = Math.max(
        1000,
        (Math.abs(this.correction) * 2000) / Math.max(0.5, anchor.speed),
      );
    }
  }
  sample(sample: ClockSample, sent: number, received = this.monotonic()) {
    const rtt = Math.max(0, received - sent);
    this.rttMs = rtt;
    // Periodically allow a changed network path to establish a new minimum.
    if (received - this.sampledAt > 30000) this.bestRtt = Infinity;
    if (rtt <= this.bestRtt * 1.25 + 2) {
      const before = this.now(received),
        previous = this.anchor;
      this.bestRtt = Math.min(this.bestRtt, rtt);
      this.offset = sample.serverTime - (sent + received) / 2000;
      this.sampledAt = received;
      const first = !this.synced;
      this.synced = true;
      if (first) this.anchor = undefined;
      this.observe(sample, received);
      if (
        !first &&
        previous &&
        this.anchor &&
        !this.anchor.paused &&
        previous.speed === this.anchor.speed &&
        previous.paused === this.anchor.paused
      ) {
        this.correction = before - this.raw(received);
        this.correctionAt = received;
        this.correctionDuration = Math.max(
          1000,
          (Math.abs(this.correction) * 2000) / Math.max(0.5, this.anchor.speed),
        );
      }
    }
  }
  private raw(at: number) {
    if (!this.anchor) return 0;
    // Before the first probe use arrival-relative time, not an untrusted local epoch.
    const server =
      this.offset === undefined
        ? this.anchor.wallTime + (at - this.receivedAt) / 1000
        : at / 1000 + this.offset;
    return gameTimeAt(this.anchor, server);
  }
  now(at = this.monotonic()) {
    if (this.frozen !== undefined) return this.frozen;
    return (
      this.raw(at) + this.correction * Math.max(0, 1 - (at - this.correctionAt) / this.correctionDuration)
    );
  }
  freeze() {
    this.frozen = this.now();
  }
  get paused() {
    return this.frozen !== undefined || this.anchor?.paused !== false;
  }
  get speed() {
    return this.paused ? 0 : (this.anchor?.speed ?? 0);
  }
  get rate() {
    return this.anchor?.speed ?? 1;
  }
}
