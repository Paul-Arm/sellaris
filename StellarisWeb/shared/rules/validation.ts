import { cloneData } from '../clone';
import type { Condition, RuleCatalog, RuleContext, RuleSource, Scope, Value } from './types';

export function ensure(ok: unknown, message: string): asserts ok {
  if (!ok) throw new Error(`Regeln: ${message}`);
}
export function finite(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && Math.abs(value) <= 1e12;
}
export function known<T>(map: Record<string, T>, id: string): T {
  ensure(typeof id === 'string' && Object.hasOwn(map, id), `Unbekannte ID ${String(id)}.`);
  return map[id];
}
function record(value: unknown): asserts value is Record<string, any> {
  ensure(value !== null && typeof value === 'object' && !Array.isArray(value), 'Objekt erwartet.');
  ensure(
    Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null,
    'Nur JSON-Objekte erlaubt.',
  );
}
function list(value: unknown): asserts value is any[] {
  ensure(Array.isArray(value) && value.length <= 512, 'Liste mit höchstens 512 Einträgen erwartet.');
}
function id(value: unknown): asserts value is string {
  ensure(
    typeof value === 'string' && /^[a-z][a-z0-9_.:-]{0,95}$/.test(value),
    'Stabile, kleingeschriebene ID erwartet.',
  );
  ensure(!['constructor', 'prototype'].includes(value), 'Reservierte ID.');
}
function ids(value: unknown): asserts value is string[] {
  list(value);
  value.forEach(id);
  ensure(new Set(value).size === value.length, 'Doppelte IDs.');
}
function text(value: unknown) {
  ensure(typeof value === 'string' && value.length <= 4000, 'Text erwartet.');
}
function scope(value: Scope | undefined, catalog: RuleCatalog) {
  if (value === undefined) return;
  record(value);
  ensure(value.root === 'target' || value.root === 'source', 'Ungültiger Bezug.');
  if (value.path !== undefined) {
    list(value.path);
    ensure(value.path.length <= 8, 'Bezugspfad zu lang.');
    value.path.forEach((r) => ensure(catalog.relations.includes(r), `Unbekannte Beziehung ${r}.`));
  }
}
export function validateValue(value: Value, catalog: RuleCatalog, allowFinal = false, depth = 0) {
  ensure(depth <= 16, 'Ausdruck zu tief.');
  if (typeof value === 'number') {
    ensure(finite(value), 'Endliche Zahl erwartet.');
    return;
  }
  record(value);
  ensure(
    ['property', 'base', 'stat', 'op'].filter((k) => Object.hasOwn(value, k)).length === 1,
    'Mehrdeutiger Ausdruck.',
  );
  if ('property' in value) {
    ensure(known(catalog.properties, value.property).type === 'number', 'Numerische Eigenschaft erwartet.');
    scope(value.scope, catalog);
  } else if ('base' in value) known(catalog.stats, value.base);
  else if ('stat' in value) {
    ensure(
      allowFinal,
      'Effekte und Voraussetzungen lesen Basiswerte; Endwerte sind nur in abgeleiteten Werten und Abfragen erlaubt.',
    );
    known(catalog.stats, value.stat);
  } else if (value.op === 'divide') {
    validateValue(value.left, catalog, allowFinal, depth + 1);
    validateValue(value.right, catalog, allowFinal, depth + 1);
  } else {
    ensure(['sum', 'product', 'min', 'max'].includes(value.op), 'Unbekannter Rechenoperator.');
    list(value.values);
    ensure(value.values.length > 0 && value.values.length <= 32, 'Ein bis 32 Operanden erwartet.');
    value.values.forEach((v) => validateValue(v, catalog, allowFinal, depth + 1));
  }
}
export function validateCondition(c: Condition, catalog: RuleCatalog, allowFinal = false, depth = 0) {
  ensure(depth <= 16, 'Voraussetzung zu tief.');
  record(c);
  ensure(
    ['all', 'any', 'not', 'kind', 'flag', 'trait', 'same', 'property', 'compare', 'related'].filter((k) =>
      Object.hasOwn(c, k),
    ).length === 1,
    'Mehrdeutige Voraussetzung.',
  );
  if ('all' in c || 'any' in c) {
    const children = 'all' in c ? c.all : c.any;
    list(children);
    children.forEach((child) => validateCondition(child, catalog, allowFinal, depth + 1));
  } else if ('not' in c) validateCondition(c.not, catalog, allowFinal, depth + 1);
  else if ('same' in c) {
    record(c.same);
    ensure(c.same.left && c.same.right, 'Zwei Bezüge erwartet.');
    scope(c.same.left, catalog);
    scope(c.same.right, catalog);
  } else if ('compare' in c) {
    ensure(['eq', 'ne', 'gt', 'gte', 'lt', 'lte'].includes(c.op), 'Ungültiger Vergleich.');
    validateValue(c.compare, catalog, allowFinal);
    validateValue(c.value, catalog, allowFinal);
  } else {
    scope(c.scope, catalog);
    if ('kind' in c) ensure(catalog.kinds.includes(c.kind), `Unbekannter Objekttyp ${c.kind}.`);
    else if ('flag' in c) known(catalog.flags, c.flag);
    else if ('trait' in c)
      ensure(known(catalog.definitions, c.trait).category === 'trait', 'Merkmal erwartet.');
    else if ('related' in c) {
      ensure(catalog.relations.includes(c.related), 'Unbekannte Beziehung.');
      ensure(c.quantifier === 'some' || c.quantifier === 'every', 'Ungültiger Beziehungsoperator.');
      validateCondition(c.condition, catalog, allowFinal, depth + 1);
    } else {
      const prop = known(catalog.properties, c.property);
      validateProperty(c.value, prop);
      ensure(
        ['eq', 'ne', ...(prop.type === 'number' ? ['gt', 'gte', 'lt', 'lte'] : [])].includes(c.op),
        'Ungültiger Eigenschaftsvergleich.',
      );
    }
  }
}
function validateProperty(value: unknown, prop: RuleCatalog['properties'][string]) {
  ensure(typeof value === prop.type, 'Falscher Eigenschaftstyp.');
  if (prop.type === 'number') ensure(finite(value), 'Ungültiger Eigenschaftswert.');
  if (prop.type === 'string') {
    text(value);
    if (prop.values) ensure(prop.values.includes(value as string), 'Unbekannte Eigenschaftsausprägung.');
  }
}
/** Validate content once at load time, including dependency cycles and contradictory stack policies. */
export function parseRuleCatalog(input: unknown): RuleCatalog {
  // Reject functions, accessors, cycles and oversized payloads before making a detached JSON copy.
  let nodes = 0;
  const ancestors = new Set<object>();
  function json(value: unknown, depth = 0) {
    ensure(++nodes <= 40000 && depth <= 48, 'Katalog zu groß.');
    if (value === null || typeof value === 'boolean' || typeof value === 'string') return;
    if (typeof value === 'number') {
      ensure(finite(value), 'Ungültige Zahl.');
      return;
    }
    ensure(typeof value === 'object', 'Nur JSON-Daten erlaubt.');
    ensure(!ancestors.has(value), 'Zyklische Daten.');
    ancestors.add(value);
    if (Array.isArray(value)) value.forEach((v) => json(v, depth + 1));
    else {
      record(value);
      for (const descriptor of Object.values(Object.getOwnPropertyDescriptors(value))) {
        ensure(!descriptor.get && !descriptor.set, 'Keine Accessors erlaubt.');
        json(descriptor.value, depth + 1);
      }
    }
    ancestors.delete(value);
  }
  json(input);
  record(input);
  ensure(input.version === 1, 'Nicht unterstützte Katalogversion.');
  const c = cloneData(input) as RuleCatalog;
  ids(c.kinds);
  ids(c.relations);
  for (const map of [c.stats, c.properties, c.flags, c.definitions]) {
    record(map);
    ensure(Object.keys(map).length <= 2048, 'Katalogbereich zu groß.');
    for (const [key, entry] of Object.entries(map)) {
      id(key);
      record(entry);
      text(entry.name);
    }
  }
  for (const p of Object.values(c.properties)) {
    ensure(['number', 'string', 'boolean'].includes(p.type), 'Ungültiger Eigenschaftstyp.');
    if (p.values) {
      ensure(p.type === 'string', 'Ausprägungen benötigen Text.');
      list(p.values);
      p.values.forEach(text);
    }
  }
  for (const f of Object.values(c.flags)) text(f.description);
  for (const s of Object.values(c.stats)) {
    text(s.unit);
    if (s.kinds) {
      ids(s.kinds);
      ensure(
        s.kinds.every((k) => c.kinds.includes(k)),
        'Unbekannter Wert-Objekttyp.',
      );
    }
    ensure(finite(s.default), 'Ungültiger Basiswert.');
    ensure(['higher', 'lower', 'neutral'].includes(s.better), 'Ungültige Bewertungsrichtung.');
    if (s.min !== undefined) ensure(finite(s.min), 'Ungültiges Minimum.');
    if (s.max !== undefined) ensure(finite(s.max), 'Ungültiges Maximum.');
    ensure((s.min ?? -Infinity) <= (s.max ?? Infinity), 'Widersprüchliche Wertgrenzen.');
    if (s.derived !== undefined) validateValue(s.derived, c, true);
  }
  const stackPolicies = new Map<string, string>();
  for (const d of Object.values(c.definitions)) {
    text(d.description);
    ids(d.kinds);
    ensure(
      d.kinds.every((k) => c.kinds.includes(k)),
      'Unbekannter Quellentyp.',
    );
    ensure(
      ['trait', 'government', 'technology', 'building', 'status', 'event', 'policy'].includes(d.category),
      'Unbekannte Quellenkategorie.',
    );
    if (d.cost !== undefined)
      ensure(Number.isSafeInteger(d.cost) && Math.abs(d.cost) <= 100, 'Ungültige Merkmalskosten.');
    if (d.maxStacks !== undefined)
      ensure(
        Number.isSafeInteger(d.maxStacks) && d.maxStacks >= 1 && d.maxStacks <= 100,
        'Ungültige Stapelgrenze.',
      );
    if (d.requires) validateCondition(d.requires, c);
    if (d.excludes) {
      ids(d.excludes);
      d.excludes.forEach((ex) => known(c.definitions, ex));
    }
    list(d.effects);
    ensure(new Set(d.effects.map((e) => e.id)).size === d.effects.length, 'Doppelte Effekt-ID.');
    for (const e of d.effects) {
      record(e);
      id(e.id);
      if (e.when) validateCondition(e.when, c);
      if (e.priority !== undefined)
        ensure(Number.isSafeInteger(e.priority) && Math.abs(e.priority) <= 10000, 'Ungültige Priorität.');
      ensure(Number('stat' in e) + Number('flag' in e) === 1, 'Mehrdeutiger Effekt.');
      if ('flag' in e) {
        known(c.flags, e.flag);
        ensure(typeof e.grant === 'boolean', 'Flag-Zustand erwartet.');
      } else {
        known(c.stats, e.stat);
        ensure(
          ['add', 'percent', 'multiply', 'override', 'floor', 'cap'].includes(e.op),
          'Unbekannter Modifikator.',
        );
        validateValue(e.value, c);
        if (e.stacking) {
          record(e.stacking);
          id(e.stacking.group);
          ensure(
            ['sum', 'highest', 'lowest', 'unique'].includes(e.stacking.policy),
            'Ungültige Stapelregel.',
          );
          const key = `${e.stat}/${e.op}/${e.stacking.group}`;
          ensure(
            !stackPolicies.has(key) || stackPolicies.get(key) === e.stacking.policy,
            'Widersprüchliche Stapelregeln.',
          );
          stackPolicies.set(key, e.stacking.policy);
        }
      }
    }
  }
  const visited = new Set<string>(),
    visiting = new Set<string>();
  function dependencies(v: Value): string[] {
    if (typeof v === 'number') return [];
    if ('stat' in v) return [v.stat];
    if (!('op' in v)) return [];
    return (v.op === 'divide' ? [v.left, v.right] : v.values).flatMap(dependencies);
  }
  function visit(key: string) {
    ensure(!visiting.has(key), `Zyklische Wertabhängigkeit bei ${key}.`);
    if (visited.has(key)) return;
    visiting.add(key);
    const derived = c.stats[key].derived;
    if (derived !== undefined)
      dependencies(derived).forEach((dependency) => {
        const kinds = c.stats[key].kinds ?? c.kinds;
        ensure(
          kinds.every((kind) => !c.stats[dependency].kinds || c.stats[dependency].kinds!.includes(kind)),
          'Abgeleiteter Wert hängt von einem fremden Fachmodell ab.',
        );
        visit(dependency);
      });
    visiting.delete(key);
    visited.add(key);
  }
  Object.keys(c.stats).forEach(visit);
  return c;
}
export function validateContext(catalog: RuleCatalog, context: RuleContext, sources: RuleSource[] = []) {
  record(context);
  record(context.entities);
  ensure(finite(context.tick) && context.tick >= 0, 'Ungültiger Spielzeitpunkt.');
  known(context.entities, context.target);
  ensure(Object.keys(context.entities).length <= 4096, 'Kontext zu groß; nur benötigte Objekte übergeben.');
  for (const [key, e] of Object.entries(context.entities)) {
    record(e);
    ensure(key === e.id && key.length > 0 && key.length <= 160, 'Ungültige Objekt-ID.');
    ensure(catalog.kinds.includes(e.kind), `Unbekannter Objekttyp ${e.kind}.`);
    if (e.base) {
      record(e.base);
      for (const [stat, value] of Object.entries(e.base)) {
        const spec = known(catalog.stats, stat);
        ensure(!spec.kinds || spec.kinds.includes(e.kind), 'Wert gehört zu einem anderen Fachmodell.');
        ensure(finite(value), 'Ungültiger Basiswert.');
        ensure(spec.derived === undefined, 'Abgeleiteter Wert kann keinen Basiswert überschreiben.');
      }
    }
    if (e.properties) {
      record(e.properties);
      for (const [prop, value] of Object.entries(e.properties))
        validateProperty(value, known(catalog.properties, prop));
    }
    if (e.flags) {
      ids(e.flags);
      e.flags.forEach((f) => known(catalog.flags, f));
    }
    if (e.traits) {
      ids(e.traits);
      e.traits.forEach((t) =>
        ensure(known(catalog.definitions, t).category === 'trait', 'Merkmal erwartet.'),
      );
    }
    if (e.relations) {
      record(e.relations);
      for (const [relation, targets] of Object.entries(e.relations)) {
        ensure(catalog.relations.includes(relation), 'Unbekannte Beziehung.');
        list(targets);
        ensure(new Set(targets).size === targets.length, 'Doppelte Beziehungsziele.');
        targets.forEach((t) => known(context.entities, t));
      }
    }
  }
  list(sources);
  ensure(new Set(sources.map((s) => s.id)).size === sources.length, 'Doppelte Quelleninstanz.');
  for (const s of sources) {
    record(s);
    ensure(typeof s.id === 'string' && s.id.length > 0 && s.id.length <= 200, 'Ungültige Quelleninstanz.');
    const definition = known(catalog.definitions, s.definition);
    ensure(
      definition.kinds.includes(known(context.entities, s.owner).kind),
      'Quelle passt nicht zum Besitzer.',
    );
    ensure(
      Number.isSafeInteger(s.stacks ?? 1) &&
        (s.stacks ?? 1) >= 1 &&
        (s.stacks ?? 1) <= (definition.maxStacks ?? 1),
      'Stapelgrenze überschritten.',
    );
    if (s.startsAt !== undefined) ensure(finite(s.startsAt) && s.startsAt >= 0, 'Ungültiger Beginn.');
    if (s.expiresAt !== undefined)
      ensure(finite(s.expiresAt) && s.expiresAt > (s.startsAt ?? 0), 'Ungültiges Ablaufdatum.');
  }
}
