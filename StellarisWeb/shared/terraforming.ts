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
    cost: { energy: crossClimate ? 600 : 400, minerals: crossClimate ? 375 : 250, science: 100 },
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
  paidEnergy: number;
  paidMinerals: number;
  paidScience: number;
}
