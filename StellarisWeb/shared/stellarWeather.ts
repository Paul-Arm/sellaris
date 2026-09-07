import type { CelestialBody, Facility } from './celestial';
import { stableHash } from './celestial';

export const STELLAR_STORM = { warningDays: 120, activeDays: 60, solarFactor: 0.25 } as const;
export interface StellarWeather {
  id: number;
  objectId: string;
  phase: string;
  discoveredAt: number;
  startsAt: number;
  endsAt: number;
}

/** A reproducible subset of giant stars has one discoverable eruption cycle. */
export function hasStellarStorm(body: CelestialBody, systemId: string) {
  return (
    body.slot === 0 &&
    body.kind === 'star' &&
    body.stellar?.family === 'giant' &&
    stableHash(`${systemId}:stellar-storm`) % 4 === 0
  );
}
export function stellarWeatherFactor(
  facility: Facility,
  weather: StellarWeather | null | undefined,
  at: number,
) {
  return (facility === 'solar' || facility === 'dyson') &&
    weather &&
    at >= weather.startsAt &&
    at < weather.endsAt
    ? STELLAR_STORM.solarFactor
    : 1;
}

/** Count affected four-day payouts exactly, including a settlement across both boundaries. */
export function stellarWeatherCycles(
  facility: Facility,
  weather: StellarWeather | null | undefined,
  lastProducedAt: number,
  cycles: number,
) {
  if (!weather || (facility !== 'solar' && facility !== 'dyson')) return cycles;
  const first = Math.max(1, Math.ceil((weather.startsAt - lastProducedAt) / 4));
  const last = Math.min(cycles, Math.ceil((weather.endsAt - lastProducedAt) / 4) - 1);
  const affected = Math.max(0, last - first + 1);
  return cycles - affected * (1 - STELLAR_STORM.solarFactor);
}
