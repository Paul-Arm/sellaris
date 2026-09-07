/** Stable, transport-independent rules. All bonuses are additive fractions, never client supplied. */
export type EmpireKind = 'regular' | 'corporate' | 'hive' | 'machine';
export type SpeciesKind = 'biological' | 'lithoid' | 'machine';
export type Modifier =
  | 'energy'
  | 'minerals'
  | 'data'
  | 'growth'
  | 'research'
  | 'construction'
  | 'speed'
  | 'damage'
  | 'habitability';
export type Modifiers = Record<Modifier, number>;
export interface Choice {
  name: string;
  description: string;
  effects?: Partial<Modifiers>;
  kinds?: readonly EmpireKind[];
}
export const MODIFIER_NAMES: Record<Modifier, string> = {
  energy: 'Energieproduktion',
  minerals: 'Mineralienproduktion',
  data: 'Datenproduktion',
  growth: 'Bevölkerungswachstum',
  research: 'Forschungstempo',
  construction: 'Bautempo',
  speed: 'Reisetempo',
  damage: 'Waffenschaden',
  habitability: 'Bewohnbarkeit',
};
export const EMPIRE_KINDS: Record<EmpireKind, Choice> = {
  regular: {
    name: 'Souveränes Reich',
    description: 'Individuen, politische Strömungen und eine frei wählbare Regierung.',
  },
  corporate: {
    name: 'Megakorporation',
    description: 'Ein interstellares Unternehmen. +15 % Energie, −5 % Mineralien.',
    effects: { energy: 0.15, minerals: -0.05 },
  },
  hive: {
    name: 'Schwarmbewusstsein',
    description: 'Ein gemeinsamer Wille. +15 % Wachstum, −5 % Forschungstempo.',
    effects: { growth: 0.15, research: -0.05 },
  },
  machine: {
    name: 'Maschinenintelligenz',
    description: 'Vernetzte Einheiten. +15 % Bautempo, −10 % Wachstum.',
    effects: { construction: 0.15, growth: -0.1 },
  },
};
export const AUTHORITIES = {
  democratic: {
    name: 'Demokratie',
    description: 'Gewählte Vertretung fördert wissenschaftliche Zusammenarbeit.',
    kinds: ['regular'],
    effects: { data: 0.05 },
  },
  oligarchic: {
    name: 'Oligarchie',
    description: 'Ein Rat lenkt die großen Infrastrukturprojekte.',
    kinds: ['regular'],
    effects: { construction: 0.05 },
  },
  dictatorial: {
    name: 'Diktatur',
    description: 'Zentralisierte industrielle Planung.',
    kinds: ['regular'],
    effects: { minerals: 0.05 },
  },
  imperial: {
    name: 'Erbmonarchie',
    description: 'Dynastische Flottenakademien.',
    kinds: ['regular'],
    effects: { damage: 0.05 },
  },
  corporate: {
    name: 'Konzernvorstand',
    description: 'Ein Vorstand koordiniert Produktion und Investitionen.',
    kinds: ['corporate'],
    effects: { energy: 0.05 },
  },
  hive: {
    name: 'Synaptischer Nexus',
    description: 'Alle Glieder lernen durch denselben Geist.',
    kinds: ['hive'],
    effects: { research: 0.05 },
  },
  machine: {
    name: 'Zentrales Netzwerk',
    description: 'Rechenkapazität wird dynamisch verteilt.',
    kinds: ['machine'],
    effects: { data: 0.05 },
  },
} as const satisfies Record<string, Choice>;
export type Authority = keyof typeof AUTHORITIES;
export const ETHICS = {
  egalitarian: {
    name: 'Egalitär',
    description: 'Chancengleichheit stärkt die Wissenschaft.',
    opposite: 'authoritarian',
    effects: { data: 0.05 },
  },
  authoritarian: {
    name: 'Autoritär',
    description: 'Hierarchien bündeln industrielle Arbeit.',
    opposite: 'egalitarian',
    effects: { minerals: 0.05 },
  },
  xenophile: {
    name: 'Xenophil',
    description: 'Offenheit erleichtert die Anpassung an fremde Welten.',
    opposite: 'xenophobe',
    effects: { habitability: 0.05 },
  },
  xenophobe: {
    name: 'Xenophob',
    description: 'Autarke Gemeinschaften investieren in ihre Bevölkerung.',
    opposite: 'xenophile',
    effects: { growth: 0.05 },
  },
  militarist: {
    name: 'Militaristisch',
    description: 'Militärische Ausbildung verbessert den Waffeneinsatz.',
    opposite: 'pacifist',
    effects: { damage: 0.05 },
  },
  pacifist: {
    name: 'Pazifistisch',
    description: 'Zivile Investitionen beschleunigen den Ausbau.',
    opposite: 'militarist',
    effects: { construction: 0.05 },
  },
  materialist: {
    name: 'Materialistisch',
    description: 'Empirische Forschung hat Vorrang.',
    opposite: 'spiritualist',
    effects: { research: 0.05 },
  },
  spiritualist: {
    name: 'Spiritualistisch',
    description: 'Gemeinsame Rituale stärken die Gemeinschaft.',
    opposite: 'materialist',
    effects: { growth: 0.05 },
  },
} as const;
export type Ethic = keyof typeof ETHICS;
export interface CivicChoice extends Choice {
  requires?: Ethic;
  excludes?: readonly string[];
}
export const CIVICS: Record<string, CivicChoice> = {
  technocracy: {
    name: 'Technokratie',
    description: '+10 % Forschungstempo. Benötigt Materialismus.',
    kinds: ['regular', 'corporate'],
    requires: 'materialist',
    effects: { research: 0.1 },
  },
  parliamentary: {
    name: 'Parlamentarische Tradition',
    description: '+10 % Datenproduktion. Benötigt Egalitarismus.',
    kinds: ['regular'],
    requires: 'egalitarian',
    effects: { data: 0.1 },
  },
  warrior: {
    name: 'Kriegerkultur',
    description: '+10 % Waffenschaden. Benötigt Militarismus.',
    kinds: ['regular'],
    requires: 'militarist',
    effects: { damage: 0.1 },
  },
  architects: { name: 'Sternenarchitekten', description: '+10 % Bautempo.', effects: { construction: 0.1 } },
  explorers: { name: 'Entdeckertradition', description: '+10 % Reisetempo.', effects: { speed: 0.1 } },
  conservation: {
    name: 'Kreislaufwirtschaft',
    description: '+10 % Energieproduktion.',
    effects: { energy: 0.1 },
  },
  mining: {
    name: 'Bergbaugilden',
    description: '+10 % Mineralienproduktion.',
    kinds: ['regular', 'corporate'],
    effects: { minerals: 0.1 },
  },
  free_traders: {
    name: 'Freie Händler',
    description: '+10 % Energie und +5 % Reisetempo.',
    kinds: ['corporate'],
    effects: { energy: 0.1, speed: 0.05 },
  },
  private_labs: {
    name: 'Private Forschungslabore',
    description: '+10 % Datenproduktion.',
    kinds: ['corporate'],
    effects: { data: 0.1 },
  },
  pooled_knowledge: {
    name: 'Geteiltes Gedächtnis',
    description: '+10 % Forschungstempo.',
    kinds: ['hive'],
    effects: { research: 0.1 },
  },
  budding: {
    name: 'Brutkammern',
    description: '+15 % Bevölkerungswachstum.',
    kinds: ['hive'],
    effects: { growth: 0.15 },
  },
  parallel: {
    name: 'Parallele Prozessoren',
    description: '+10 % Datenproduktion.',
    kinds: ['machine'],
    effects: { data: 0.1 },
  },
  replicators: {
    name: 'Replikatorprotokolle',
    description: '+15 % Bevölkerungswachstum.',
    kinds: ['machine'],
    effects: { growth: 0.15 },
  },
};
export interface OriginChoice extends Choice {
  population: number;
  resources: { energy: number; minerals: number; data: number };
  speciesKinds?: SpeciesKind[];
}
export const ORIGINS: Record<string, OriginChoice> = {
  unification: {
    name: 'Planetare Einigung',
    description: 'Ein vereinter Heimatplanet. +2 Startbevölkerung, +80 Energie.',
    population: 2,
    resources: { energy: 80, minerals: 0, data: 0 },
  },
  lost_colony: {
    name: 'Verlorene Kolonie',
    description: 'Eine neue Heimat jenseits vergessener Routen. +10 % Reisetempo, +60 Mineralien.',
    population: 0,
    resources: { energy: 0, minerals: 60, data: 0 },
    effects: { speed: 0.1 },
  },
  survivors: {
    name: 'Überlebende',
    description:
      'Eine Zivilisation nach der Katastrophe. −1 Startbevölkerung, +15 Prozentpunkte Bewohnbarkeit.',
    population: -1,
    resources: { energy: 0, minerals: 0, data: 0 },
    effects: { habitability: 0.15 },
  },
  relic_seekers: {
    name: 'Erben der Ruinen',
    description: 'Alte Archive inspirieren eine neue Ära. +80 Daten, +5 % Forschungstempo.',
    population: 0,
    resources: { energy: 0, minerals: 0, data: 80 },
    effects: { research: 0.05 },
  },
  industrial: {
    name: 'Industrieller Aufbruch',
    description: '+120 Mineralien, −40 Energie, +5 % Bautempo.',
    population: 0,
    resources: { energy: -40, minerals: 120, data: 0 },
    effects: { construction: 0.05 },
  },
  first_consensus: {
    name: 'Erster Konsens',
    description: 'Das junge Kollektiv erwacht. +1 Startbevölkerung und +10 % Wachstum.',
    kinds: ['hive'],
    population: 1,
    resources: { energy: 0, minerals: 0, data: 0 },
    effects: { growth: 0.1 },
  },
  awakening: {
    name: 'Autonomes Erwachen',
    description: 'Die Maschinen übernehmen ihre Fertigung. +100 Energie und +5 % Bautempo.',
    kinds: ['machine'],
    speciesKinds: ['machine'],
    population: 0,
    resources: { energy: 100, minerals: 0, data: 0 },
    effects: { construction: 0.05 },
  },
};
export const SPECIES_KINDS: Record<SpeciesKind, Choice> = {
  biological: { name: 'Biologisch', description: 'Organisches Leben mit natürlichem Wachstum.' },
  lithoid: {
    name: 'Lithoid',
    description: '+15 Prozentpunkte Bewohnbarkeit, −15 % Wachstum.',
    effects: { habitability: 0.15, growth: -0.15 },
  },
  machine: {
    name: 'Synthetisch',
    description: '90 % Basisbewohnbarkeit auf allen Planeten, −10 % Wachstum.',
    effects: { growth: -0.1 },
  },
};
export const ENVIRONMENTS = {
  continental: { name: 'Kontinentalwelt', climate: 'wet' },
  ocean: { name: 'Ozeanwelt', climate: 'wet' },
  tropical: { name: 'Tropenwelt', climate: 'wet' },
  desert: { name: 'Wüstenwelt', climate: 'dry' },
  savanna: { name: 'Savannenwelt', climate: 'dry' },
  arid: { name: 'Aridwelt', climate: 'dry' },
  alpine: { name: 'Alpine Welt', climate: 'cold' },
  tundra: { name: 'Tundrawelt', climate: 'cold' },
  arctic: { name: 'Arktische Welt', climate: 'cold' },
} as const;
export type Environment = keyof typeof ENVIRONMENTS;
export const PORTRAITS = {
  humanoid: 'Humanoid',
  avian: 'Avian',
  reptilian: 'Reptiloid',
  arthropoid: 'Arthropoid',
  fungoid: 'Fungoid',
  plantoid: 'Plantoid',
  crystalline: 'Kristallin',
  synthetic: 'Synthetisch',
} as const;
export interface TraitChoice extends Choice {
  cost: number;
  speciesKinds?: readonly SpeciesKind[];
  excludes?: readonly string[];
}
export const TRAITS: Record<string, TraitChoice> = {
  intelligent: {
    name: 'Intelligent',
    description: '+10 % Datenproduktion.',
    cost: 2,
    effects: { data: 0.1 },
  },
  industrious: {
    name: 'Fleißig',
    description: '+15 % Mineralienproduktion.',
    cost: 2,
    effects: { minerals: 0.15 },
  },
  ingenious: {
    name: 'Erfinderisch',
    description: '+15 % Energieproduktion.',
    cost: 2,
    effects: { energy: 0.15 },
  },
  rapid_growth: {
    name: 'Schnelle Vermehrung',
    description: '+15 % Wachstum.',
    cost: 2,
    speciesKinds: ['biological', 'lithoid'],
    excludes: ['slow_growth'],
    effects: { growth: 0.15 },
  },
  adaptive: {
    name: 'Anpassungsfähig',
    description: '+10 Prozentpunkte Bewohnbarkeit.',
    cost: 2,
    speciesKinds: ['biological', 'lithoid'],
    excludes: ['delicate'],
    effects: { habitability: 0.1 },
  },
  strong: {
    name: 'Stark',
    description: '+5 % Waffenschaden.',
    cost: 1,
    excludes: ['weak'],
    effects: { damage: 0.05 },
  },
  curious: { name: 'Neugierig', description: '+5 % Forschungstempo.', cost: 1, effects: { research: 0.05 } },
  swift: { name: 'Raumfahrer', description: '+5 % Reisetempo.', cost: 1, effects: { speed: 0.05 } },
  assembly: {
    name: 'Modulare Fertigung',
    description: '+15 % Wachstum.',
    cost: 2,
    speciesKinds: ['machine'],
    excludes: ['slow_assembly'],
    effects: { growth: 0.15 },
  },
  efficient: {
    name: 'Effiziente Schaltkreise',
    description: '+10 % Energieproduktion.',
    cost: 1,
    speciesKinds: ['machine'],
    effects: { energy: 0.1 },
  },
  slow_growth: {
    name: 'Langsame Vermehrung',
    description: '−15 % Wachstum.',
    cost: -1,
    speciesKinds: ['biological', 'lithoid'],
    excludes: ['rapid_growth'],
    effects: { growth: -0.15 },
  },
  slow_assembly: {
    name: 'Komplexe Montage',
    description: '−15 % Wachstum.',
    cost: -1,
    speciesKinds: ['machine'],
    excludes: ['assembly'],
    effects: { growth: -0.15 },
  },
  wasteful: {
    name: 'Verschwenderisch',
    description: '−10 % Energieproduktion.',
    cost: -1,
    effects: { energy: -0.1 },
  },
  delicate: {
    name: 'Empfindlich',
    description: '−10 Prozentpunkte Bewohnbarkeit.',
    cost: -1,
    speciesKinds: ['biological', 'lithoid'],
    excludes: ['adaptive'],
    effects: { habitability: -0.1 },
  },
  weak: {
    name: 'Schwach',
    description: '−5 % Waffenschaden.',
    cost: -1,
    excludes: ['strong'],
    effects: { damage: -0.05 },
  },
};
export const EMBLEMS = {
  orbit: 'Orbit',
  star: 'Stern',
  hexagon: 'Hexagon',
  diamond: 'Diamant',
  wings: 'Schwingen',
  nexus: 'Nexus',
} as const;
export function emptyModifiers(): Modifiers {
  return {
    energy: 0,
    minerals: 0,
    data: 0,
    growth: 0,
    research: 0,
    construction: 0,
    speed: 0,
    damage: 0,
    habitability: 0,
  };
}
export function addEffects(target: Modifiers, effects?: Partial<Modifiers>, weight = 1) {
  if (effects) for (const key of Object.keys(effects) as Modifier[]) target[key] += effects[key]! * weight;
  return target;
}
