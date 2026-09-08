import type { Resources } from './game';
export const TRADE_RESOURCES = ['energy', 'minerals', 'data'] as const;

export const OFFER_LIFETIME = 60;
export const TRUCE_DURATION = 120;
export const DIPLOMACY_TYPES = ['declare_war', 'offer_treaty', 'respond_treaty', 'cancel_treaty'] as const;
export type DiplomacyCommand =
  | { type: 'declare_war'; empireId: string }
  | { type: 'offer_treaty'; empireId: string; kind: 'peace' | 'trade'; give?: Resources; receive?: Resources }
  | { type: 'respond_treaty'; treatyId: number; accept: boolean }
  | { type: 'cancel_treaty'; treatyId: number };
export interface Relation {
  id: string;
  empireA: string;
  empireB: string;
  state: 'peace' | 'war';
  truceUntil: number;
  changedAt: number;
}
export interface TreatyOffer {
  id: number;
  empireA: string;
  empireB: string;
  kind: 'peace' | 'trade';
  status: 'pending' | 'accepted' | 'rejected' | 'cancelled' | 'expired';
  expiresAt: number;
  give: Resources;
  receive: Resources;
}
export function relationBetween(relations: Relation[], a: string, b: string) {
  return relations.find((r) => (r.empireA === a && r.empireB === b) || (r.empireA === b && r.empireB === a));
}
