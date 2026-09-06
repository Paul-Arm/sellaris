/** One simulation unit is one in-game day. At 1×, a day lasts one real second.
 * Fractions are display/clock phase only; durable simulation advances in whole days. */
export const gameDay = (time: number) => Math.floor(time + 1e-8);
export const nextGameDay = (time: number) => Math.floor(time + 1e-8) + 1;
export const dueDay = (time: number) => Math.ceil(time - 1e-8);

export interface TravelTiming {
  departedAt: number;
  arrivesAt: number;
}
export function travelProgress(journey: TravelTiming, day: number) {
  return Math.min(
    1,
    Math.max(0, (day - journey.departedAt) / Math.max(0.001, journey.arrivesAt - journey.departedAt)),
  );
}
