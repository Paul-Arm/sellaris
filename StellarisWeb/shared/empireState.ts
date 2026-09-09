import { cloneData } from './clone';
import { addEffects, emptyModifiers, type Environment, type Modifiers } from './empireCatalog';
import {
  governmentModifiers,
  habitability,
  parseGovernment,
  parseSpeciesDesign,
  speciesModifiers,
  type EmpireDesign,
  type Government,
  type SpeciesDesign,
  type TemplateSnapshot,
} from './empires';

export const REFORM_COST = { energy: 100, unity: 150 };
export const MODIFICATION_COST = { energy: 0, minerals: 120, data: 300 };
export const REFORM_COOLDOWN = 120;
export const MODIFICATION_COOLDOWN = 240;
export interface LivingSpecies extends SpeciesDesign {
  economyModifiers?: import('./economy').EconomyModifier[];
  id: string;
  sourceTemplateId: string;
  sourceRevision: number;
  parentId: string | null;
  generation: number;
  createdAt: number;
}
export interface EmpireState {
  economyModifiers?: import('./economy').EconomyModifier[];
  version: 1;
  revision: number;
  /** Immutable provenance. Gameplay only reads design/species, never this snapshot. */
  founding: TemplateSnapshot;
  design: EmpireDesign;
  primarySpeciesId: string;
  species: LivingSpecies[];
  nextSpecies: number;
  reformAvailableAt: number;
  modificationAvailableAt: number;
  history: { tick: number; kind: 'founded' | 'reform' | 'species'; text: string }[];
}
export interface PopulationGroup {
  speciesId: string;
  population: number;
}
export function instantiateEmpire(snapshot: TemplateSnapshot, playerId: string, tick: number): EmpireState {
  const founding = cloneData(snapshot);
  const { id: _id, version: _v, revision: _r, ...design } = founding.empire;
  const { id: sourceTemplateId, revision: sourceRevision, version: _sv, ...species } = founding.species;
  const speciesId = `${playerId}:species:1`;
  return {
    version: 1,
    revision: 1,
    founding,
    design: cloneData(design),
    primarySpeciesId: speciesId,
    species: [
      {
        ...cloneData(species),
        id: speciesId,
        sourceTemplateId,
        sourceRevision,
        parentId: null,
        generation: 0,
        createdAt: tick,
      },
    ],
    nextSpecies: 2,
    reformAvailableAt: tick,
    modificationAvailableAt: tick,
    history: [
      {
        tick,
        kind: 'founded',
        text: `${design.name} gegründet.`,
      },
    ],
  };
}
export function empireModifiers(empire?: EmpireState): Modifiers {
  if (!empire) return emptyModifiers();
  const mods = governmentModifiers(empire.design.government, empire.design.origin);
  const primary = empire.species.find((s) => s.id === empire.primarySpeciesId);
  return primary ? addEffects(mods, speciesModifiers(primary)) : mods;
}
export function colonyModifiers(
  empire: EmpireState | undefined,
  groups: PopulationGroup[] | undefined,
  environment: Environment,
): Modifiers {
  if (!empire) return emptyModifiers();
  const government = governmentModifiers(empire.design.government, empire.design.origin);
  const result = { ...government };
  const populations = groups?.length ? groups : [{ speciesId: empire.primarySpeciesId, population: 1 }];
  const total = populations.reduce((sum, group) => sum + group.population, 0);
  if (total <= 0) return result;
  for (const group of populations) {
    const species = empire.species.find((s) => s.id === group.speciesId);
    if (!species) continue;
    addEffects(result, speciesModifiers(species), group.population / total);
    const penalty =
      ((1 - habitability(species, environment, government.habitability)) * 0.5 * group.population) / total;
    result.energy -= penalty;
    result.minerals -= penalty;
    result.data -= penalty;
  }
  return result;
}
export function populationGrowth(
  empire: EmpireState | undefined,
  speciesId: string,
  environment: Environment,
): number {
  if (!empire) return 1;
  const species = empire.species.find((s) => s.id === speciesId);
  if (!species) return 0;
  const govt = governmentModifiers(empire.design.government, empire.design.origin);
  return (
    Math.max(0.1, 1 + govt.growth + speciesModifiers(species).growth) *
    habitability(species, environment, govt.habitability)
  );
}
function expectRevision(empire: EmpireState, expected: number) {
  if (empire.revision !== expected)
    throw new Error('Das Reich hat sich zwischenzeitlich verändert. Öffne die aktuelle Fassung.');
}
export function planReform(
  empire: EmpireState,
  government: Government,
  tick: number,
  expected: number,
): EmpireState {
  expectRevision(empire, expected);
  if (tick < empire.reformAvailableAt)
    throw new Error(
      `Regierungsreform in ${Math.ceil(empire.reformAvailableAt - tick)} Spieltagen verfügbar.`,
    );
  const clean = parseGovernment(government);
  if (clean.kind !== empire.design.government.kind)
    throw new Error('Der grundlegende Reichstyp bleibt bei einer Regierungsreform erhalten.');
  if (JSON.stringify(clean) === JSON.stringify(empire.design.government))
    throw new Error('Wähle eine Änderung für die Regierungsreform.');
  const next = cloneData(empire);
  next.design.government = clean;
  next.revision++;
  next.reformAvailableAt = tick + REFORM_COOLDOWN;
  next.history.push({ tick, kind: 'reform', text: 'Regierung, Ethiken und Staatselemente reformiert.' });
  next.history = next.history.slice(-64);
  return next;
}
export function planSpeciesModification(
  empire: EmpireState,
  sourceId: string,
  design: SpeciesDesign,
  tick: number,
  expected: number,
): { empire: EmpireState; speciesId: string } {
  expectRevision(empire, expected);
  if (tick < empire.modificationAvailableAt)
    throw new Error(
      `Speziesmodifikation in ${Math.ceil(empire.modificationAvailableAt - tick)} Spieltagen verfügbar.`,
    );
  if (empire.species.length >= 32) throw new Error('Höchstens 32 Speziesvarianten je Reich.');
  const source = empire.species.find((s) => s.id === sourceId);
  if (!source) throw new Error('Spezies nicht im eigenen Reich gefunden.');
  const clean = parseSpeciesDesign(design, 4);
  if (clean.kind !== source.kind)
    throw new Error('Die grundlegende Lebensform kann durch diese Modifikation nicht geändert werden.');
  if (
    clean.environment === source.environment &&
    clean.name === source.name &&
    JSON.stringify([...clean.traits].sort()) === JSON.stringify([...source.traits].sort())
  )
    throw new Error('Die Variante braucht einen neuen Namen, ein anderes Klima oder andere Merkmale.');
  const next = cloneData(empire);
  const id = `${empire.primarySpeciesId}:variant:${next.nextSpecies++}`;
  next.species.push({
    ...clean,
    id,
    sourceTemplateId: source.sourceTemplateId,
    sourceRevision: source.sourceRevision,
    parentId: source.id,
    generation: source.generation + 1,
    createdAt: tick,
  });
  next.revision++;
  next.modificationAvailableAt = tick + MODIFICATION_COOLDOWN;
  next.history.push({
    tick,
    kind: 'species',
    text: `${clean.name} als Variante von ${source.name} entstanden.`,
  });
  next.history = next.history.slice(-64);
  return { empire: next, speciesId: id };
}
