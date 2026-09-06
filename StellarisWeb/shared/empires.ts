import { cloneData } from './clone';
import {
  AUTHORITIES,
  CIVICS,
  EMBLEMS,
  EMPIRE_KINDS,
  ENVIRONMENTS,
  ETHICS,
  ORIGINS,
  PORTRAITS,
  SPECIES_KINDS,
  TRAITS,
  type Authority,
  type EmpireKind,
  type Environment,
  type Ethic,
  type Modifiers,
  type SpeciesKind,
} from './empireCatalog';
import { parseFlag, type FlagDesign } from './flags';
import { governmentRuleModifiers, speciesRuleModifiers } from './empireRules';

export const TEMPLATE_VERSION = 1;
export const MAX_TEMPLATES = 64;
export interface TemplateMeta {
  id: string;
  revision: number;
  version: 1;
}
export interface SpeciesDesign {
  name: string;
  plural: string;
  adjective: string;
  kind: SpeciesKind;
  portrait: keyof typeof PORTRAITS;
  environment: Environment;
  traits: string[];
  description: string;
  lore: string;
}
export interface SpeciesTemplate extends SpeciesDesign, TemplateMeta {}
export interface Government {
  kind: EmpireKind;
  authority: Authority;
  ethics: { id: Ethic; strength: 1 | 2 }[];
  civics: string[];
}
export interface EmpireDesign {
  name: string;
  adjective: string;
  description: string;
  lore: string;
  color: string;
  emblem: keyof typeof EMBLEMS;
  flag?: FlagDesign;
  shipPrefix: string;
  rulerName: string;
  rulerTitle: string;
  homeworldName: string;
  systemName: string;
  government: Government;
  origin: string;
  speciesTemplateId: string;
}
export interface EmpireTemplate extends EmpireDesign, TemplateMeta {}
export interface EmpireLibrary {
  version: 1;
  revision: number;
  empires: EmpireTemplate[];
  species: SpeciesTemplate[];
}
export type LibraryMutation =
  | { type: 'save_empire'; template: EmpireTemplate }
  | { type: 'save_species'; template: SpeciesTemplate }
  | { type: 'delete_empire' | 'delete_species'; id: string; revision: number };
export interface TemplateSnapshot {
  empire: EmpireTemplate;
  species: SpeciesTemplate;
}

function object(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new Error(`${label}: Objekt erwartet.`);
  return value as Record<string, unknown>;
}
function text(value: unknown, label: string, max: number, required = false): string {
  if (typeof value !== 'string') throw new Error(`${label}: Text erwartet.`);
  const clean = value.trim();
  if ((required && !clean) || clean.length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(clean))
    throw new Error(`${label}: ${required ? '1' : '0'} bis ${max} Zeichen erlaubt.`);
  return clean;
}
function choice<T extends Record<string, unknown>>(
  catalog: T,
  value: unknown,
  label: string,
): keyof T & string {
  if (typeof value !== 'string' || !Object.hasOwn(catalog, value))
    throw new Error(`${label}: unbekannter Wert.`);
  return value;
}
function strings(value: unknown, max: number, label: string): string[] {
  if (!Array.isArray(value) || value.length > max || value.some((v) => typeof v !== 'string'))
    throw new Error(`${label}: höchstens ${max} Einträge.`);
  if (new Set(value).size !== value.length)
    throw new Error(`${label}: doppelte Einträge sind nicht erlaubt.`);
  return [...value];
}
export function templateId(value: unknown): string {
  if (typeof value !== 'string' || !/^[a-zA-Z0-9_-]{1,80}$/.test(value))
    throw new Error('Ungültige Vorlagen-ID.');
  return value;
}
function meta(o: Record<string, unknown>): TemplateMeta {
  if (o.version !== TEMPLATE_VERSION) throw new Error('Diese Vorlagenversion wird nicht unterstützt.');
  if (!Number.isSafeInteger(o.revision) || (o.revision as number) < 0)
    throw new Error('Ungültige Vorlagenrevision.');
  return { id: templateId(o.id), version: TEMPLATE_VERSION, revision: o.revision as number };
}
export function traitCost(traits: string[]) {
  return traits.reduce((sum, id) => sum + (TRAITS[id]?.cost ?? 0), 0);
}
export function parseSpeciesDesign(value: unknown, budget = 2): SpeciesDesign {
  const o = object(value, 'Spezies');
  const kind = choice(SPECIES_KINDS, o.kind, 'Lebensform');
  const traits = strings(o.traits, 5, 'Merkmale');
  for (const id of traits) {
    choice(TRAITS, id, 'Merkmal');
    const trait = TRAITS[id];
    if (trait.speciesKinds && !trait.speciesKinds.includes(kind))
      throw new Error(`${trait.name} ist für diese Lebensform nicht verfügbar.`);
    if (trait.excludes?.some((other) => traits.includes(other)))
      throw new Error(`${trait.name} widerspricht einem anderen Merkmal.`);
  }
  if (traitCost(traits) > budget)
    throw new Error(`Merkmalsbudget überschritten: ${traitCost(traits)} von ${budget} Punkten.`);
  return {
    name: text(o.name, 'Speziesname', 48, true),
    plural: text(o.plural, 'Plural', 48, true),
    adjective: text(o.adjective, 'Adjektiv', 48),
    kind,
    portrait: choice(PORTRAITS, o.portrait, 'Erscheinungsbild'),
    environment: choice(ENVIRONMENTS, o.environment, 'Heimatklima'),
    traits,
    description: text(o.description, 'Beschreibung', 240),
    lore: text(o.lore, 'Speziesgeschichte', 4000),
  };
}
export function parseSpeciesTemplate(value: unknown): SpeciesTemplate {
  return { ...meta(object(value, 'Speziesvorlage')), ...parseSpeciesDesign(value) };
}
export function parseGovernment(value: unknown): Government {
  const o = object(value, 'Regierung');
  const kind = choice(EMPIRE_KINDS, o.kind, 'Reichstyp');
  const authority = choice(AUTHORITIES, o.authority, 'Regierungsform');
  if (!(AUTHORITIES[authority].kinds as readonly string[]).includes(kind))
    throw new Error('Regierungsform und Reichstyp passen nicht zusammen.');
  if (!Array.isArray(o.ethics) || o.ethics.length > 3)
    throw new Error('Höchstens drei Ethiken sind erlaubt.');
  const ethics = o.ethics.map((entry) => {
    const e = object(entry, 'Ethik');
    const id = choice(ETHICS, e.id, 'Ethik');
    if (e.strength !== 1 && e.strength !== 2) throw new Error('Ethikstärke muss 1 oder 2 sein.');
    return { id, strength: e.strength as 1 | 2 };
  });
  if (new Set(ethics.map((e) => e.id)).size !== ethics.length)
    throw new Error('Doppelte Ethiken sind nicht erlaubt.');
  const gestalt = kind === 'hive' || kind === 'machine';
  if (gestalt ? ethics.length !== 0 : ethics.reduce((sum, e) => sum + e.strength, 0) !== 3)
    throw new Error(
      gestalt
        ? 'Kollektive haben keine individuellen Ethiken.'
        : 'Verteile genau 3 Ethikpunkte. Fanatische Ethiken kosten 2.',
    );
  for (const ethic of ethics)
    if (ethics.some((e) => e.id === ETHICS[ethic.id].opposite))
      throw new Error('Gegensätzliche Ethiken schließen sich aus.');
  if (authority === 'democratic' && ethics.some((e) => e.id === 'authoritarian'))
    throw new Error('Autoritarismus ist mit Demokratie unvereinbar.');
  if (['dictatorial', 'imperial'].includes(authority) && ethics.some((e) => e.id === 'egalitarian'))
    throw new Error('Egalitarismus ist mit dieser Regierungsform unvereinbar.');
  const civics = strings(o.civics, 2, 'Staatselemente');
  if (civics.length !== 2) throw new Error('Wähle genau zwei Staatselemente.');
  for (const id of civics) {
    choice(CIVICS, id, 'Staatselement');
    const civic = CIVICS[id];
    if (civic.kinds && !civic.kinds.includes(kind))
      throw new Error(`${civic.name} passt nicht zu diesem Reichstyp.`);
    if (civic.requires && !ethics.some((e) => e.id === civic.requires))
      throw new Error(`${civic.name} benötigt ${ETHICS[civic.requires].name}.`);
  }
  return { kind, authority, ethics, civics };
}
export function parseEmpireTemplate(value: unknown, species: SpeciesTemplate[]): EmpireTemplate {
  const o = object(value, 'Reichsvorlage');
  const government = parseGovernment(o.government);
  const speciesTemplateId = templateId(o.speciesTemplateId);
  const primary = species.find((s) => s.id === speciesTemplateId);
  if (!primary) throw new Error('Die zugehörige Spezies fehlt in deiner Bibliothek.');
  parseSpeciesTemplate(primary);
  if ((government.kind === 'machine') !== (primary.kind === 'machine'))
    throw new Error(
      'Maschinenintelligenzen benötigen synthetische Spezies; organische Reiche biologische oder lithoide Spezies.',
    );
  const origin = choice(ORIGINS, o.origin, 'Ursprung');
  if (ORIGINS[origin].kinds && !ORIGINS[origin].kinds!.includes(government.kind))
    throw new Error('Dieser Ursprung passt nicht zum Reichstyp.');
  if (ORIGINS[origin].speciesKinds && !ORIGINS[origin].speciesKinds!.includes(primary.kind))
    throw new Error('Dieser Ursprung passt nicht zur Spezies.');
  if (typeof o.color !== 'string' || !/^#[0-9a-f]{6}$/i.test(o.color))
    throw new Error('Wähle eine gültige Reichsfarbe.');
  const flag = parseFlag(o.flag, { color: o.color, emblem: choice(EMBLEMS, o.emblem, 'Emblem') });
  return {
    ...meta(o),
    name: text(o.name, 'Reichsname', 64, true),
    adjective: text(o.adjective, 'Adjektiv', 48),
    description: text(o.description, 'Beschreibung', 240),
    lore: text(o.lore, 'Reichsgeschichte', 4000),
    color: o.color.toLowerCase(),
    emblem: flag.emblem,
    flag,
    shipPrefix: text(o.shipPrefix, 'Schiffspräfix', 12),
    rulerName: text(o.rulerName, 'Herrschername', 48),
    rulerTitle: text(o.rulerTitle, 'Herrschertitel', 48),
    homeworldName: text(o.homeworldName, 'Heimatwelt', 48, true),
    systemName: text(o.systemName, 'Heimatsystem', 48, true),
    government,
    origin,
    speciesTemplateId,
  };
}
export function governmentFor(kind: EmpireKind): Government {
  return {
    kind,
    authority: kind === 'regular' ? 'democratic' : kind,
    ethics:
      kind === 'hive' || kind === 'machine'
        ? []
        : [
            { id: 'egalitarian', strength: 1 },
            { id: 'xenophile', strength: 1 },
            { id: 'materialist', strength: 1 },
          ],
    civics:
      kind === 'machine'
        ? ['parallel', 'replicators']
        : kind === 'hive'
          ? ['pooled_knowledge', 'budding']
          : kind === 'corporate'
            ? ['free_traders', 'private_labs']
            : ['explorers', 'architects'],
  };
}
export function newSpecies(id: string, kind: SpeciesKind = 'biological'): SpeciesTemplate {
  return {
    version: 1,
    id,
    revision: 0,
    name: kind === 'machine' ? 'Einheit' : 'Mensch',
    plural: kind === 'machine' ? 'Einheiten' : 'Menschen',
    adjective: kind === 'machine' ? 'synthetisch' : 'menschlich',
    kind,
    portrait: kind === 'machine' ? 'synthetic' : kind === 'lithoid' ? 'crystalline' : 'humanoid',
    environment: 'continental',
    traits: [],
    description: '',
    lore: '',
  };
}
export function newEmpire(
  id: string,
  speciesTemplateId: string,
  kind: EmpireKind = 'regular',
): EmpireTemplate {
  return {
    version: 1,
    id,
    revision: 0,
    name: 'Terranische Union',
    adjective: 'terranisch',
    description: 'Eine gemeinsame Zukunft zwischen den Sternen.',
    lore: '',
    color: '#9c91ff',
    emblem: 'orbit',
    shipPrefix: 'ISS',
    rulerName: '',
    rulerTitle: 'Präsidentin',
    homeworldName: 'Erde',
    systemName: 'Sol',
    government: governmentFor(kind),
    origin: 'unification',
    speciesTemplateId,
  };
}
export function starterLibrary(): EmpireLibrary {
  const human = {
    ...newSpecies('species-human'),
    revision: 1,
    traits: ['intelligent', 'swift', 'weak'],
    description: 'Neugierige Reisende einer blauen Welt.',
  };
  const hive = {
    ...newSpecies('species-mycel'),
    revision: 1,
    name: 'Myzel',
    plural: 'Myzeliden',
    adjective: 'myzelidisch',
    portrait: 'fungoid' as const,
    environment: 'tropical' as const,
    traits: ['rapid_growth'],
    description: 'Unzählige Körper. Ein gemeinsames Gedächtnis.',
  };
  const machine = {
    ...newSpecies('species-axiom', 'machine'),
    revision: 1,
    name: 'Axiom',
    plural: 'Axiome',
    traits: ['assembly'],
    description: 'Bewusstsein aus rekursiven Protokollen.',
  };
  return {
    version: 1,
    revision: 1,
    species: [human, hive, machine],
    empires: [
      { ...newEmpire('empire-union', human.id), revision: 1 },
      {
        ...newEmpire('empire-mycel', hive.id, 'hive'),
        revision: 1,
        name: 'Myzelischer Verbund',
        adjective: 'myzelisch',
        color: '#58d9cf',
        emblem: 'nexus',
        homeworldName: 'Keimstatt',
        systemName: 'Viridia',
        origin: 'first_consensus',
        rulerTitle: 'Erste Synapse',
        shipPrefix: 'MYC',
        description: 'Ein Gedanke wächst über seinen Heimatstern hinaus.',
      },
      {
        ...newEmpire('empire-axiom', machine.id, 'machine'),
        revision: 1,
        name: 'Axiom-Kontinuum',
        adjective: 'axiomatisch',
        color: '#f3b36b',
        emblem: 'diamond',
        homeworldName: 'Kern 01',
        systemName: 'Axiom',
        origin: 'awakening',
        rulerTitle: 'Koordinator',
        shipPrefix: 'AX',
        description: 'Die nächste Iteration beginnt.',
      },
    ],
  };
}
export function validateEmpireLibrary(value: unknown): EmpireLibrary {
  const o = object(value, 'Bibliothek');
  if (o.version !== 1 || !Number.isSafeInteger(o.revision) || (o.revision as number) < 0)
    throw new Error('Ungültige Bibliotheksversion oder Revision.');
  if (
    !Array.isArray(o.species) ||
    !Array.isArray(o.empires) ||
    o.species.length > MAX_TEMPLATES ||
    o.empires.length > MAX_TEMPLATES
  )
    throw new Error(`Höchstens ${MAX_TEMPLATES} Vorlagen pro Kategorie.`);
  const species = o.species.map(parseSpeciesTemplate);
  const empires = o.empires.map((e) => parseEmpireTemplate(e, species));
  for (const entries of [species, empires])
    if (new Set(entries.map((e) => e.id)).size !== entries.length) throw new Error('Doppelte Vorlagen-ID.');
  return { version: 1, revision: o.revision as number, species, empires };
}
/** Pure transaction: no writes on validation failure, optimistic concurrency on each template. */
export function mutateLibrary(library: EmpireLibrary, mutation: LibraryMutation): EmpireLibrary {
  const next = cloneData(library);
  if (!mutation || typeof mutation !== 'object') throw new Error('Ungültige Bibliotheksaktion.');
  if (mutation.type === 'save_empire' || mutation.type === 'save_species') {
    const template =
      mutation.type === 'save_empire'
        ? parseEmpireTemplate(mutation.template, next.species)
        : parseSpeciesTemplate(mutation.template);
    const entries: (EmpireTemplate | SpeciesTemplate)[] =
      mutation.type === 'save_empire' ? next.empires : next.species;
    const index = entries.findIndex((e) => e.id === template.id);
    if (template.revision !== (index < 0 ? 0 : entries[index].revision))
      throw new Error('Die Vorlage wurde zwischenzeitlich geändert. Lade die aktuelle Fassung.');
    if (index < 0 && entries.length >= MAX_TEMPLATES)
      throw new Error(`Höchstens ${MAX_TEMPLATES} Vorlagen pro Kategorie.`);
    template.revision++;
    if (index < 0) entries.push(template);
    else entries[index] = template;
  } else if (mutation.type === 'delete_empire' || mutation.type === 'delete_species') {
    const entries = mutation.type === 'delete_empire' ? next.empires : next.species;
    const index = entries.findIndex((e) => e.id === templateId(mutation.id));
    if (index < 0) throw new Error('Vorlage nicht gefunden.');
    if (entries[index].revision !== mutation.revision)
      throw new Error('Die Vorlage wurde zwischenzeitlich geändert.');
    if (mutation.type === 'delete_species' && next.empires.some((e) => e.speciesTemplateId === mutation.id))
      throw new Error('Diese Spezies wird noch von einer Reichsvorlage verwendet.');
    entries.splice(index, 1);
  } else throw new Error('Unbekannte Bibliotheksaktion.');
  next.revision++;
  // Species edits must not silently invalidate referencing empires.
  return validateEmpireLibrary(next);
}
export function snapshotTemplate(library: EmpireLibrary, id: string): TemplateSnapshot {
  const empire = library.empires.find((e) => e.id === templateId(id));
  if (!empire) throw new Error('Reichsvorlage nicht gefunden.');
  const clean = parseEmpireTemplate(empire, library.species);
  return {
    empire: clean,
    species: parseSpeciesTemplate(library.species.find((s) => s.id === clean.speciesTemplateId)),
  };
}
export function governmentModifiers(government: Government, origin: string): Modifiers {
  return governmentRuleModifiers(government, origin);
}
export function speciesModifiers(species: SpeciesDesign): Modifiers {
  return speciesRuleModifiers(species);
}
export function habitability(species: SpeciesDesign, environment: Environment, empireBonus = 0): number {
  const base =
    species.kind === 'machine'
      ? 0.9
      : species.environment === environment
        ? 1
        : ENVIRONMENTS[species.environment].climate === ENVIRONMENTS[environment].climate
          ? 0.8
          : 0.6;
  return Math.max(0.2, Math.min(1, base + speciesModifiers(species).habitability + empireBonus));
}
export function environmentForPlanet(planet: string): Environment {
  return (
    (Object.keys(ENVIRONMENTS) as Environment[]).find((id) => ENVIRONMENTS[id].name === planet) ??
    'continental'
  );
}
