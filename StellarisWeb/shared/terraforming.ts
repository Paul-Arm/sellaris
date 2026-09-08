import { ENVIRONMENTS, type Environment } from './empireCatalog';
import type { Resources } from './game';

export const PLANET_COLORS: Record<Environment, string> = {
  continental: '#70a2af',
  ocean: '#447fc2',
  tropical: '#54a88a',
  desert: '#cb995f',
  savanna: '#b0a769',
  arid: '#bc7958',
  alpine: '#9aaeb9',
  tundra: '#839da6',
  arctic: '#b4d4e5',
};
export const isEnvironment = (value: string): value is Environment => Object.hasOwn(ENVIRONMENTS, value);
export function terraformingSpec(from: Environment, to: Environment): { cost: Resources; days: number } {
  const crossClimate = ENVIRONMENTS[from].climate !== ENVIRONMENTS[to].climate;
  return {
    cost: { energy: crossClimate ? 600 : 400, minerals: crossClimate ? 375 : 250, data: 100 },
    days: crossClimate ? 120 : 80,
  };
}
export interface TerraformProject {
  id: string;
  systemId: number;
  empireId: number;
  from: string;
  target: string;
  startedAt: number;
  finishAt: number;
  workTotal: number;
  workDone: number;
  updatedAt: number;
  rate: number;
  paidEnergy: number;
  paidMinerals: number;
  paidData: number;
}
/** Budget is shared equally; 10 Compute per project gives +50% speed, approaching +100%. */
export function terraformingRate(compute: number, projects: number) {
  const share = projects > 0 ? compute / projects : 0;
  return 1 + share / (10 + share);
}
export function terraformWork(
  project: Pick<TerraformProject, 'workTotal' | 'workDone' | 'updatedAt' | 'rate'>,
  at: number,
) {
  return Math.min(project.workTotal, project.workDone + Math.max(0, at - project.updatedAt) * project.rate);
}
export function retimeTerraforming<T extends TerraformProject>(project: T, at: number, rate: number): T {
  const workDone = terraformWork(project, at);
  return { ...project, workDone, updatedAt: at, rate, finishAt: at + (project.workTotal - workDone) / rate };
}
