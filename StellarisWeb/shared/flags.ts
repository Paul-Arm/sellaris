import { EMBLEMS } from './empireCatalog';

export const FLAG_PATTERNS = {
  solid: 'Einfarbig',
  horizontal: 'Horizontal geteilt',
  vertical: 'Vertikal geteilt',
  diagonal: 'Diagonal geteilt',
  triband: 'Drei Balken',
  cross: 'Kreuz',
  saltire: 'Andreaskreuz',
  chevron: 'Keil',
  canton: 'Eckfeld',
  quarters: 'Geviertelt',
  diamond: 'Raute',
  stripes: 'Streifen',
} as const;
export const FLAG_POSITIONS = { center: 'Zentriert', hoist: 'Am Mast', upper: 'Oben mittig' } as const;
export const FLAG_FRAMES = { none: 'Ohne Rahmen', circle: 'Kreis', hexagon: 'Sechseck' } as const;
export const FLAG_BORDERS = {
  none: 'Ohne Rand',
  single: 'Einfacher Rand',
  double: 'Doppelter Rand',
} as const;
export interface FlagDesign {
  version: 1;
  pattern: keyof typeof FLAG_PATTERNS;
  primary: string;
  secondary: string;
  symbolColor: string;
  emblem: keyof typeof EMBLEMS;
  position: keyof typeof FLAG_POSITIONS;
  size: number;
  rotation: number;
  frame: keyof typeof FLAG_FRAMES;
  border: keyof typeof FLAG_BORDERS;
}
export type FlagSource = { color: string; emblem?: keyof typeof EMBLEMS; flag?: FlagDesign };
export function defaultFlag(color = '#9c91ff', emblem: keyof typeof EMBLEMS = 'orbit'): FlagDesign {
  return {
    version: 1,
    pattern: 'diagonal',
    primary: '#141c30',
    secondary: color,
    symbolColor: '#f1eddf',
    emblem,
    position: 'center',
    size: 40,
    rotation: 0,
    frame: 'none',
    border: 'none',
  };
}
/** Old templates/saves keep their original emblem and map color without mutating the snapshot. */
export function flagForEmpire(empire: FlagSource): FlagDesign {
  return empire.flag ?? defaultFlag(empire.color, empire.emblem);
}
function color(value: unknown): string {
  if (typeof value !== 'string' || !/^#[0-9a-f]{6}$/i.test(value))
    throw new Error('Flaggenfarben benötigen einen sechsstelligen Hex-Farbwert.');
  return value.toLowerCase();
}
function choice<T extends Record<string, string>>(
  catalog: T,
  value: unknown,
  field: string,
): keyof T & string {
  if (typeof value !== 'string' || !Object.hasOwn(catalog, value))
    throw new Error(`Flagge: unbekannte Auswahl für ${field}.`);
  return value;
}
export function parseFlag(value: unknown, fallback: FlagSource): FlagDesign {
  if (value === undefined) return defaultFlag(color(fallback.color), fallback.emblem);
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new Error('Ungültiger Flaggenentwurf.');
  const o = value as Record<string, unknown>;
  if (o.version !== 1) throw new Error('Diese Flaggenversion wird nicht unterstützt.');
  if (typeof o.size !== 'number' || !Number.isFinite(o.size) || o.size < 20 || o.size > 65)
    throw new Error('Die Emblemgröße muss zwischen 20 und 65 Prozent liegen.');
  if (typeof o.rotation !== 'number' || !Number.isFinite(o.rotation) || o.rotation < 0 || o.rotation > 360)
    throw new Error('Die Emblemdrehung muss zwischen 0 und 360 Grad liegen.');
  return {
    version: 1,
    pattern: choice(FLAG_PATTERNS, o.pattern, 'Muster'),
    primary: color(o.primary),
    secondary: color(o.secondary),
    symbolColor: color(o.symbolColor),
    emblem: choice(EMBLEMS, o.emblem, 'Emblem'),
    position: choice(FLAG_POSITIONS, o.position, 'Position'),
    size: o.size,
    rotation: o.rotation,
    frame: choice(FLAG_FRAMES, o.frame, 'Rahmen'),
    border: choice(FLAG_BORDERS, o.border, 'Rand'),
  };
}
export const FLAG_PRESETS: { name: string; flag: FlagDesign }[] = [
  {
    name: 'Sternenbund',
    flag: {
      ...defaultFlag(),
      pattern: 'chevron',
      primary: '#162c46',
      secondary: '#47778b',
      symbolColor: '#f6dfa1',
      emblem: 'star',
      position: 'hoist',
    },
  },
  {
    name: 'Dynastie',
    flag: {
      ...defaultFlag(),
      pattern: 'vertical',
      primary: '#4c2136',
      secondary: '#191d30',
      symbolColor: '#eac888',
      emblem: 'wings',
      frame: 'circle',
      border: 'double',
    },
  },
  {
    name: 'Kollektiv',
    flag: {
      ...defaultFlag(),
      pattern: 'diamond',
      primary: '#103333',
      secondary: '#226d61',
      symbolColor: '#dbefcf',
      emblem: 'nexus',
      frame: 'hexagon',
    },
  },
  {
    name: 'Expedition',
    flag: {
      ...defaultFlag(),
      pattern: 'triband',
      primary: '#d4c8a3',
      secondary: '#233b57',
      symbolColor: '#f6ecce',
      emblem: 'orbit',
      size: 30,
    },
  },
];
