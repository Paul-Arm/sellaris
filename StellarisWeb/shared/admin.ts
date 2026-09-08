import { RESOURCE_IDS, type Resource, type Resources } from './resources';
import type { GalaxySettings } from './galaxySettings';
import type { EmpireDesign, SpeciesDesign } from './empires';

export interface AdminServer {
  code: string;
  database: string;
  galaxy: GalaxySettings;
  status: 'provisioning' | 'running' | 'paused' | 'finished' | 'unavailable';
  day?: number;
  speed?: number;
  capacity?: number;
  players?: { id: number; name: string; ai: boolean; online: boolean; host: boolean }[];
  error?: string;
}
export interface AdminOverview {
  servers: AdminServer[];
  updatedAt: string;
  uptime: number;
}
export type AdminAction =
  | { action: 'clock'; paused: boolean; speed: number }
  | { action: 'delete'; confirmation: string }
  | AdminEmpireAction;

export type AdminEmpireAction =
  | { action: 'add_ai' }
  | { action: 'host'; empireId: number }
  | { action: 'resources'; empireId: number; resource: Resource; amount: number };

export function validAdminEmpireAction(value: unknown): value is AdminEmpireAction {
  if (!value || typeof value !== 'object') return false;
  const v = value as Record<string, unknown>;
  if (v.action === 'add_ai') return true;
  if (!Number.isInteger(v.empireId) || Number(v.empireId) < 1) return false;
  return (
    v.action === 'host' ||
    (v.action === 'resources' &&
      RESOURCE_IDS.includes(v.resource as Resource) &&
      typeof v.amount === 'number' &&
      Number.isInteger(v.amount) &&
      v.amount !== 0 &&
      Math.abs(v.amount) <= 100000)
  );
}

export interface AdminEmpire {
  id: number;
  name: string;
  color: string;
  ai: boolean;
  online: boolean;
  host: boolean;
  homeId: number;
  resources: Resources;
  techs: string[];
  surveyed: number;
  design: EmpireDesign;
  species: SpeciesDesign[];
  colonies: {
    id: number;
    name: string;
    population: number;
    monthlyProduction: Resources;
  }[];
}
export interface AdminMatch {
  code: string;
  updatedAt: string;
  empires: AdminEmpire[];
  systems: {
    id: number;
    name: string;
    x: number;
    y: number;
    kind: string;
    ownerId: number;
    planet: string;
    colonyName: string;
  }[];
  lanes: { a: number; b: number }[];
  fleets: {
    id: number;
    empireId: number;
    name: string;
    systemId: number;
    ships: number;
    order: string;
    battleId: number;
    x: number;
    y: number;
  }[];
  relations: { a: number; b: number; state: string }[];
}
