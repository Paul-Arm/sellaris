import type { Condition, EventDefinition, EventEffect, EventStage } from './types';
import { validateEventPool } from './engine';
const has = (fact: string, value: string): Condition => ({ fact, op: 'has', value });
const atLeast = (fact: string, value: number): Condition => ({ fact, op: 'gte', value });
const reward = (data = 0, energy = 0, minerals = 0): EventEffect[] => [
  { type: 'resources', amounts: { data, energy, minerals } },
];
const map = { type: 'map', caption: 'Fundort und benachbarte Systeme' } as const;
const report = (text: string): EventStage['blocks'] => [
  { type: 'dialogue', speaker: 'Expeditionsleitung', role: 'Verschlüsselter Bericht', text },
  map,
];
function project(
  id: string,
  title: string,
  summary: string,
  theme: EventDefinition['theme'],
  triggers: string[],
  when?: Condition,
): EventDefinition {
  return {
    id,
    kind: 'project',
    title,
    subtitle: 'Spezialprojekt',
    summary,
    theme,
    artwork: `/events/${theme}.svg`,
    triggers,
    when,
    chance: 0.75,
    weight: 2,
    repeat: 'once',
    cooldownDays: 180,
    startCost: { energy: 50, data: 30 },
    progress: {
      target: 100,
      rate: 0.65,
      volatility: 1.6,
      rates: [
        { when: has('techs', 'automation'), add: 0.35 },
        { when: atLeast('ownedSystems', 3), add: 0.2 },
      ],
    },
    stages: [
      { id: 'analysis', title: 'Spuren sichern', blocks: report(summary), threshold: 35 },
      {
        id: 'method',
        title: 'Eine Richtung wählen',
        blocks: [
          {
            type: 'text',
            text: 'Die ersten Messreihen sind vollständig. Zusätzliche Ressourcen beschleunigen die zweite Phase; ein vorsichtiger Ansatz benötigt mehr Zeit.',
          },
        ],
        choices: [
          {
            id: 'fund',
            title: 'Forschung verstärken',
            description: '+0,5 Fortschritt pro Tag.',
            cost: { energy: 60 },
            rate: 0.5,
          },
          {
            id: 'careful',
            title: 'Mit bestehenden Mitteln fortfahren',
            description: 'Keine zusätzlichen Kosten.',
          },
        ],
      },
      {
        id: 'implementation',
        title: 'Erkenntnisse anwenden',
        blocks: [
          { type: 'image', src: `/events/${theme}.svg`, alt: title },
          {
            type: 'text',
            text: 'Die Arbeitsgruppen gleichen Modelle und Beobachtungen ab. Gute Messreihen bringen uns voran; widersprüchliche Befunde werfen die Untersuchung zurück.',
          },
        ],
        threshold: 100,
        effects: reward(160, 20),
      },
    ],
  };
}
function encounter(
  id: string,
  title: string,
  summary: string,
  theme: EventDefinition['theme'],
  triggers: string[],
  when?: Condition,
  follow?: string,
): EventDefinition {
  return {
    id,
    kind: 'event',
    title,
    subtitle: 'Übertragung eingegangen',
    summary,
    theme,
    artwork: `/events/${theme}.svg`,
    triggers,
    when,
    chance: 0.55,
    weight: 1,
    repeat: 'repeat',
    cooldownDays: 240,
    stages: [
      {
        id: 'contact',
        title: 'Erstkontakt mit dem Fund',
        blocks: report(summary),
        timeoutDays: 120,
        fallback: 'record',
        choices: [
          {
            id: 'investigate',
            title: follow ? 'Spezialprojekt vormerken' : 'Genauer untersuchen',
            description: follow
              ? 'Ein eigenständiges Projekt wird im Lagezentrum verfügbar.'
              : 'Energie für eine vollständige Auswertung bereitstellen.',
            cost: { energy: 25 },
            effects: follow ? [{ type: 'project', definition: follow }] : reward(65),
            finish: 'completed',
          },
          {
            id: 'salvage',
            title: 'Verwertbare Funde sichern',
            description: 'Materialien bergen und die Untersuchung beenden.',
            effects: reward(0, 0, 45),
            finish: 'completed',
          },
          {
            id: 'record',
            title: 'Dokumentieren und weiterziehen',
            description: 'Messdaten archivieren, ohne Ressourcen zu binden.',
            effects: reward(15),
            finish: 'completed',
          },
        ],
      },
    ],
  };
}
const cartography = project(
  'cartography',
  'Das unsichtbare Netz',
  'Unsere Karten zeigen nur die hellsten Routen. Ein langfristiger Abgleich von Gravitationsmessungen könnte schwache Verbindungen zwischen den Systemen sichtbar machen.',
  'signal',
  ['founded'],
);
cartography.chance = 1;
const evolution = project(
  'species-evolution',
  'Die nächste Generation',
  'In mehreren Populationen treten dieselben Anpassungen auf. Es könnte sich um den Beginn einer stabilen evolutionären Entwicklung handeln.',
  'biology',
  ['time', 'species'],
  { all: [atLeast('day', 90), has('speciesKinds', 'biological')] },
);
evolution.repeat = 'once';
evolution.progress = {
  target: 100,
  initial: 12,
  rate: 0.35,
  volatility: 1.4,
  rates: [{ when: has('techs', 'terraforming'), add: 0.35 }],
};
evolution.stages = [
  {
    id: 'variation',
    title: 'Variation',
    blocks: report(
      'Die Veränderung ist messbar, aber noch nicht stabil. Wir beobachten mehrere voneinander unabhängige Populationen.',
    ),
    threshold: 30,
  },
  {
    id: 'selection',
    title: 'Selektion',
    blocks: [
      {
        type: 'dialogue',
        speaker: 'Rat der Lebenswissenschaften',
        role: 'Zwischenbericht',
        text: 'Wir können die Anpassung begleiten oder ihren natürlichen Verlauf weiter beobachten. Die Entwicklung betrifft unsere erfasste Ausgangsspezies.',
      },
    ],
    choices: [
      {
        id: 'support',
        title: 'Anpassung begleiten',
        description: '+0,4 Fortschritt pro Tag; 10 % höheres Wachstum der Spezies.',
        cost: { data: 90 },
        rate: 0.4,
        effects: [
          {
            type: 'species_modifier',
            modifier: {
              id: 'adaptive-growth',
              name: 'Begleitete Anpassung',
              category: 'growth',
              percent: 0.1,
            },
          },
        ],
      },
      {
        id: 'observe',
        title: 'Natürliche Entwicklung beobachten',
        description: 'Ohne zusätzliche Kosten fortfahren.',
      },
    ],
  },
  {
    id: 'stabilization',
    title: 'Stabilisierung',
    blocks: report(
      'Die neuen Merkmale werden zwischen Generationen weitergegeben. Schwankungen in der Umwelt können die Stabilisierung noch verzögern.',
    ),
    threshold: 70,
  },
  {
    id: 'integration',
    title: 'Neue Generation',
    blocks: [
      { type: 'image', src: '/events/biology.svg', alt: 'Verzweigte biologische Entwicklung' },
      {
        type: 'text',
        text: 'Die Anpassung etabliert sich in der Spezies. Nach Abschluss steigt ihre Generation; die neue Arbeitsproduktivität bleibt Teil ihres lebenden Speziesmodells.',
      },
    ],
    threshold: 100,
    effects: [
      {
        type: 'species_modifier',
        evolve: true,
        modifier: { id: 'evolved-productivity', name: 'Stabile Anpassung', category: 'jobs', percent: 0.08 },
      },
      ...reward(80),
    ],
  },
];
const archive = encounter(
  'lost-archive',
  'Eine Stimme aus der Leere',
  'Eine uralte Sonde wiederholt ein künstliches Signal. Zwischen beschädigten Speichersektoren liegen Hinweise auf eine verschwundene Expedition.',
  'signal',
  ['survey'],
  { fact: 'anomaly', op: 'is', value: true },
  'archive-decoding',
);
archive.chance = 1;
archive.repeat = 'system';
archive.weight = 5;
const crisis = encounter(
  'resonance-response',
  'Ein Riss im Sternennetz',
  'Eine Resonanzfront stört die planetaren Energienetze. Mehrere Reiche melden denselben Ursprung.',
  'crisis',
  ['crisis'],
);
crisis.chance = 1;
crisis.repeat = 'once';
crisis.priority = 'critical';
crisis.stages = [
  {
    id: 'response',
    title: 'Erste Reaktion',
    blocks: report(crisis.summary),
    choices: [
      {
        id: 'shield',
        when: {
          all: [
            { fact: 'sourceCrisisActive', op: 'is', value: true },
            { fact: 'sourceCrisisShielded', op: 'is', value: false },
          ],
        },
        title: 'Kolonien abschirmen',
        description: '120 Energie. Eigene Kolonien bleiben vor dieser Krise geschützt.',
        effects: [{ type: 'crisis', action: 'shield' }],
        finish: 'completed',
      },
      {
        id: 'contribute',
        when: { fact: 'sourceCrisisActive', op: 'is', value: true },
        title: 'Gemeinsame Stabilisierung finanzieren',
        description: '60 Energie und 30 Daten. Nach Eindämmung: 40 Daten je Beitrag.',
        effects: [{ type: 'crisis', action: 'contribute' }],
        finish: 'completed',
      },
      {
        id: 'study',
        title: 'Resonanzfront untersuchen',
        description: 'Ein Spezialprojekt zur Auswertung der Resonanz wird verfügbar.',
        effects: [{ type: 'project', definition: 'resonance-study' }],
        finish: 'completed',
      },
      {
        id: 'observe',
        title: 'Lage beobachten',
        description: 'Spätere Eingriffe bleiben in der Krisenansicht möglich.',
        finish: 'completed',
      },
    ],
  },
];
export const EVENT_POOL: readonly EventDefinition[] = [
  cartography,
  evolution,
  archive,
  crisis,
  project(
    'archive-decoding',
    'Das gebrochene Archiv',
    'Rekonstruiere die beschädigten Erinnerungen einer fremden Sonde.',
    'signal',
    [],
  ),
  project(
    'resonance-study',
    'Jenseits der Resonanz',
    'Vermesse die Störfront und entwickle ein Modell für künftige Raumanker.',
    'crisis',
    [],
  ),
  project(
    'living-ocean',
    'Ein Ozean, der antwortet',
    'Die Strömungen eines Ozeans reagieren auf unsere Messimpulse. Die Antwortzeiten folgen keinem bekannten Organismus.',
    'biology',
    [],
  ),
  project(
    'ancient-foundry',
    'Die verlassene Gießerei',
    'In einer stillgelegten Anlage arbeiten autonome Werkzeuge an einem unvollständigen Bauteil.',
    'industry',
    [],
  ),
  project(
    'shared-language',
    'Ein gemeinsamer Wortschatz',
    'Mehrere Spezies entwickeln eine gemeinsame Zeichensprache. Eine systematische Sammlung könnte Missverständnisse im Reich verringern.',
    'society',
    ['time'],
    atLeast('speciesCount', 2),
  ),
  project(
    'machine-dreams',
    'Träume im Prozessorkern',
    'Unabhängige Rechenkerne erzeugen dieselben unaufgeforderten Simulationen.',
    'industry',
    ['time'],
    has('speciesKinds', 'machine'),
  ),
  encounter(
    'ocean-echo',
    'Echo aus der Tiefe',
    'Ein besiedelter Planet meldet regelmäßig wiederkehrende Signale aus seinem Ozean.',
    'biology',
    ['colony', 'survey'],
    undefined,
    'living-ocean',
  ),
  encounter(
    'silent-factory',
    'Die lautlose Fabrik',
    'Eine orbitale Ruine ist dunkel. Im Inneren verändern sich jedoch die Wärmebilder.',
    'industry',
    ['survey'],
    undefined,
    'ancient-foundry',
  ),
  encounter(
    'frontier-lights',
    'Lichter am Horizont',
    'Unter der neuen Kolonie liegen verlassene Speicher. Der Kolonierat bittet um eine erste Untersuchung.',
    'society',
    ['colony'],
  ),
  encounter(
    'dust-memory',
    'Erinnerung im Staub',
    'Elektrostatischer Staub bildet geometrische Muster auf den Sensorplatten.',
    'signal',
    ['survey'],
  ),
  encounter(
    'mineral-lattice',
    'Das singende Gitter',
    'Eine ungewöhnliche Mineralstruktur schwingt im Takt unserer Kommunikationssignale.',
    'industry',
    ['survey'],
    undefined,
    'ancient-foundry',
  ),
  encounter(
    'gravity-lens',
    'Eine zweite Silhouette',
    'Hinter einer Gravitationslinse erscheint für Sekunden die Silhouette einer Station.',
    'signal',
    ['survey'],
  ),
  encounter(
    'pilgrim-route',
    'Die Route der Pilger',
    'Zivile Schiffe folgen einer alten Wegmarkierung zwischen unseren Systemen.',
    'society',
    ['time', 'ownership'],
    atLeast('ownedSystems', 3),
  ),
  encounter(
    'supply-incident',
    'Eine fehlende Lieferung',
    'Eine Versorgungslieferung erreicht ihr Ziel ohne Besatzung. Das Logbuch endet mitten in einem Satz.',
    'industry',
    ['time'],
    atLeast('ownedSystems', 2),
  ),
  encounter(
    'new-material',
    'Werkstoff ohne Bauplan',
    'Die neue Fördertechnik legt ein Material frei, das unter Spannung seine innere Struktur verändert.',
    'industry',
    ['technology', 'time'],
    has('techs', 'extraction'),
  ),
  encounter(
    'autonomous-error',
    'Der hilfreiche Fehler',
    'Ein automatisiertes System löst eine Aufgabe außerhalb seines ursprünglichen Auftrags.',
    'industry',
    ['technology', 'time'],
    has('techs', 'automation'),
  ),
  encounter(
    'climate-memory',
    'Ein gespeichertes Klima',
    'Unsere Klimamodelle enthalten eine wiederkehrende Wettersignatur ohne offensichtliche Quelle.',
    'biology',
    ['technology', 'time'],
    has('techs', 'terraforming'),
  ),
  encounter(
    'genetic-echo',
    'Ein Echo im Erbgut',
    'Nach einer Speziesmodifikation werden bislang stille Sequenzen aktiv.',
    'biology',
    ['species'],
    undefined,
    'species-evolution',
  ),
  encounter(
    'lithoid-resonance',
    'Die lange Schwingung',
    'Lithoide Bevölkerungen nehmen ein Signal wahr, das unsere Instrumente erst nach mehreren Tagen auflösen.',
    'biology',
    ['time'],
    has('speciesKinds', 'lithoid'),
  ),
  encounter(
    'machine-poem',
    'Eine unerwartete Zeile',
    'Ein Wartungsprozess übermittelt einen Text, der weder Fehlerbericht noch Arbeitsauftrag ist.',
    'society',
    ['time'],
    has('speciesKinds', 'machine'),
    'machine-dreams',
  ),
  encounter(
    'border-beacon',
    'Ein Licht an der Grenze',
    'Ein neu beanspruchtes System enthält ein wartendes Navigationsfeuer.',
    'signal',
    ['ownership'],
  ),
  encounter(
    'storm-remnant',
    'Nach dem Sternensturm',
    'Die Sensoren zeichnen während eines Sternensturms eine schmale, geordnete Frequenz auf.',
    'signal',
    ['stellar-weather'],
    undefined,
    'resonance-study',
  ),
  encounter(
    'modified-economy',
    'Unerwartete Synergien',
    'Eine bestehende Anpassung unserer Wirtschaft verändert die Abläufe in mehreren Kolonien.',
    'industry',
    ['time'],
    atLeast('modifierCount', 1),
  ),
  encounter(
    'distant-anniversary',
    'Ein Tag auf fernen Welten',
    'Zum Jahrestag der Expedition erreichen uns sehr unterschiedliche Berichte aus den besiedelten Systemen.',
    'society',
    ['time'],
    atLeast('day', 360),
  ),
];
validateEventPool(EVENT_POOL);
export const EVENT_DEFINITIONS = Object.fromEntries(EVENT_POOL.map((d) => [d.id, d])) as Record<
  string,
  EventDefinition
>;
