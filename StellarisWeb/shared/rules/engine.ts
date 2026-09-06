import type {
  Condition,
  ConditionResult,
  Contribution,
  NumericEffect,
  RuleCatalog,
  RuleContext,
  RuleEntity,
  RuleResult,
  RuleSource,
  Scope,
  StatResult,
  Value,
} from './types';
import { ensure, finite, known, parseRuleCatalog, validateCondition, validateContext } from './validation';

class MissingContext extends Error {}
const compare = (a: string | boolean | number, op: string, b: string | boolean | number) => {
  switch (op) {
    case 'eq':
      return a === b;
    case 'ne':
      return a !== b;
    case 'gt':
      return a > b;
    case 'gte':
      return a >= b;
    case 'lt':
      return a < b;
    case 'lte':
      return a <= b;
    default:
      throw new Error('Unbekannter Vergleich.');
  }
};
const lexical = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);
const tie = (a: Contribution, b: Contribution) =>
  b.priority - a.priority ||
  lexical(a.definition, b.definition) ||
  lexical(a.source, b.source) ||
  lexical(a.effect, b.effect);
function freeze<T>(data: T): T {
  if (data && typeof data === 'object') {
    Object.values(data).forEach(freeze);
    Object.freeze(data);
  }
  return data;
}
/** A catalog is validated once, detached from its caller and recursively frozen. */
export function createRuleEngine(input: RuleCatalog) {
  const catalog = freeze(parseRuleCatalog(input));
  function scoped(context: RuleContext, source: string | undefined, scope?: Scope): RuleEntity {
    let current = scope?.root === 'source' ? source : context.target;
    if (!current) throw new MissingContext('Quellenobjekt fehlt.');
    for (const relation of scope?.path ?? []) {
      const targets: string[] | undefined = context.entities[current]?.relations?.[relation];
      if (targets?.length !== 1) throw new MissingContext(`Beziehung ${relation} benötigt genau ein Ziel.`);
      current = targets[0];
    }
    const entity = context.entities[current];
    if (!entity) throw new MissingContext('Bezugsobjekt fehlt.');
    return entity;
  }
  function value(v: Value, context: RuleContext, source?: string, final?: (stat: string) => number): number {
    if (typeof v === 'number') return v;
    let result: number;
    if ('property' in v) {
      const properties = scoped(context, source, v.scope).properties;
      if (!properties || !Object.hasOwn(properties, v.property))
        throw new MissingContext(`Eigenschaft ${v.property} fehlt.`);
      result = properties[v.property] as number;
    } else if ('base' in v) {
      if (
        catalog.stats[v.base].kinds &&
        !catalog.stats[v.base].kinds!.includes(context.entities[context.target].kind)
      )
        throw new MissingContext(`Basiswert ${v.base} gehört zu einem anderen Fachmodell.`);
      result = context.entities[context.target].base?.[v.base] ?? catalog.stats[v.base].default;
    } else if ('stat' in v) {
      if (!final) throw new MissingContext(`Berechneter Wert ${v.stat} fehlt.`);
      result = final(v.stat);
    } else if (v.op === 'divide') {
      const denominator = value(v.right, context, source, final);
      ensure(denominator !== 0, 'Division durch null.');
      result = value(v.left, context, source, final) / denominator;
    } else {
      const values = v.values.map((n) => value(n, context, source, final));
      result =
        v.op === 'sum'
          ? values.reduce((a, b) => a + b, 0)
          : v.op === 'product'
            ? values.reduce((a, b) => a * b, 1)
            : v.op === 'min'
              ? Math.min(...values)
              : Math.max(...values);
    }
    ensure(finite(result), 'Rechenausdruck außerhalb des gültigen Zahlenbereichs.');
    return result;
  }
  function condition(
    c: Condition,
    context: RuleContext,
    source?: string,
    resolved?: RuleResult,
  ): ConditionResult {
    const answer = (met: boolean, reason: string, children?: ConditionResult[]): ConditionResult => ({
      met,
      missing: false,
      reason,
      ...(children ? { children } : {}),
    });
    try {
      if ('all' in c || 'any' in c) {
        const all = 'all' in c;
        const children = (all ? c.all : c.any).map((child) => condition(child, context, source, resolved));
        const met = all ? children.every((child) => child.met) : children.some((child) => child.met);
        return {
          ...answer(met, all ? 'Alle Voraussetzungen' : 'Mindestens eine Voraussetzung', children),
          missing: !met && children.some((child) => child.missing),
        };
      }
      if ('not' in c) {
        const child = condition(c.not, context, source, resolved);
        return {
          met: !child.met && !child.missing,
          missing: child.missing,
          reason: 'Voraussetzung ausgeschlossen',
          children: [child],
        };
      }
      if ('compare' in c) {
        const final =
          resolved && resolved.target === context.target
            ? (stat: string) => {
                if (!Object.hasOwn(resolved.stats, stat))
                  throw new MissingContext(`Berechneter Wert ${stat} fehlt.`);
                return resolved.stats[stat].value;
              }
            : undefined;
        return answer(
          compare(value(c.compare, context, source, final), c.op, value(c.value, context, source, final)),
          'Wertvergleich',
        );
      }
      if ('same' in c)
        return answer(
          scoped(context, source, c.same.left).id === scoped(context, source, c.same.right).id,
          'Identisches Bezugsobjekt',
        );
      const entity = scoped(context, source, c.scope);
      if ('kind' in c) return answer(entity.kind === c.kind, `Objekttyp: ${c.kind}`);
      if ('flag' in c) {
        const flags = resolved?.target === entity.id ? resolved.flags : (entity.flags ?? []);
        return answer(flags.includes(c.flag), `Eigenschaft: ${catalog.flags[c.flag].name}`);
      }
      if ('trait' in c)
        return answer(
          (entity.traits ?? []).includes(c.trait),
          `Merkmal: ${catalog.definitions[c.trait].name}`,
        );
      if ('related' in c) {
        const targets = entity.relations?.[c.related];
        if (!targets) throw new MissingContext(`Beziehung ${c.related} fehlt.`);
        const children = targets.map((target) =>
          condition(c.condition, { ...context, target }, source, resolved),
        );
        // Every requires at least one subject; a missing governor cannot meet "every governor".
        const met =
          targets.length > 0 &&
          (c.quantifier === 'some' ? children.some((r) => r.met) : children.every((r) => r.met));
        return {
          ...answer(met, `Beziehung: ${c.related}`, children),
          missing: !met && children.some((child) => child.missing),
        };
      }
      if (!entity.properties || !Object.hasOwn(entity.properties, c.property))
        throw new MissingContext(`Eigenschaft ${c.property} fehlt.`);
      return answer(
        compare(entity.properties[c.property], c.op, c.value),
        `Eigenschaft: ${catalog.properties[c.property].name}`,
      );
    } catch (error) {
      if (error instanceof MissingContext) return { met: false, missing: true, reason: error.message };
      throw error;
    }
  }
  function evaluate(context: RuleContext, sources: RuleSource[]): RuleResult {
    validateContext(catalog, context, sources);
    const contributions: Contribution[] = [];
    const numeric = new Map<Contribution, NumericEffect>();
    for (const source of [...sources].sort((a, b) => lexical(a.id, b.id))) {
      const definition = catalog.definitions[source.definition];
      const active = context.tick >= (source.startsAt ?? 0) && context.tick < (source.expiresAt ?? Infinity);
      for (const effect of definition.effects) {
        const item: Contribution = {
          source: source.id,
          definition: source.definition,
          effect: effect.id,
          owner: source.owner,
          stacks: source.stacks ?? 1,
          priority: effect.priority ?? 0,
          applied: active,
          reason: active
            ? 'Aktiv'
            : context.tick < (source.startsAt ?? 0)
              ? 'Noch nicht aktiv'
              : 'Abgelaufen',
          ...('stat' in effect
            ? { stat: effect.stat, op: effect.op }
            : { flag: effect.flag, grant: effect.grant }),
        };
        contributions.push(item);
        if (item.applied && effect.when) {
          const check = condition(effect.when, context, source.owner);
          if (!check.met) {
            item.applied = false;
            item.reason = check.missing ? 'Benötigter Kontext fehlt' : 'Bedingung nicht erfüllt';
          }
        }
        if ('stat' in effect) {
          numeric.set(item, effect);
          if (
            item.applied &&
            catalog.stats[effect.stat].kinds &&
            !catalog.stats[effect.stat].kinds!.includes(context.entities[context.target].kind)
          ) {
            item.applied = false;
            item.reason = 'Wert gehört zu einem anderen Fachmodell';
          }
          if (item.applied) {
            try {
              item.value = value(effect.value, context, source.owner);
              ensure(
                effect.op !== 'multiply' || item.value >= 0,
                'Multiplikatoren dürfen nicht negativ sein.',
              );
            } catch (error) {
              if (!(error instanceof MissingContext)) throw error;
              item.applied = false;
              item.reason = error.message;
            }
          }
        }
      }
    }
    const groups = new Map<string, Contribution[]>();
    for (const [item, effect] of numeric) {
      if (!item.applied || !effect.stacking || effect.stacking.policy === 'sum') continue;
      const key = `${effect.stat}/${effect.op}/${effect.stacking.group}`;
      groups.set(key, [...(groups.get(key) ?? []), item]);
    }
    function amount(item: Contribution) {
      return item.op === 'multiply'
        ? item.value! ** item.stacks
        : ['override', 'floor', 'cap'].includes(item.op!)
          ? item.value!
          : item.value! * item.stacks;
    }
    for (const members of groups.values()) {
      const policy = numeric.get(members[0])!.stacking!.policy;
      members.sort(
        (a, b) =>
          (policy === 'highest' ? amount(b) - amount(a) : policy === 'lowest' ? amount(a) - amount(b) : 0) ||
          tie(a, b),
      );
      for (const item of members.slice(1)) {
        item.applied = false;
        item.reason = `Stapelregel ${policy}: ${members[0].source} hat Vorrang`;
      }
    }
    const stats: Record<string, StatResult> = {};
    const visiting = new Set<string>();
    function stat(id: string): number {
      if (Object.hasOwn(stats, id)) return stats[id].value;
      ensure(!visiting.has(id), `Zyklische Berechnung ${id}.`);
      visiting.add(id);
      const definition = catalog.stats[id];
      const base =
        definition.derived !== undefined
          ? value(definition.derived, context, undefined, stat)
          : (context.entities[context.target].base?.[id] ?? definition.default);
      const rows = contributions.filter((c) => c.stat === id);
      const active = rows.filter((c) => c.applied);
      const sum = (op: string) => active.filter((c) => c.op === op).reduce((sum, c) => sum + amount(c), 0);
      const flat = sum('add'),
        percent = sum('percent');
      const multiplier = active
        .filter((c) => c.op === 'multiply')
        .reduce((product, c) => product * amount(c), 1);
      const calculated = (base + flat) * (1 + percent) * multiplier;
      ensure(finite(calculated), `Wertüberlauf bei ${id}.`);
      const overrides = active.filter((c) => c.op === 'override').sort(tie);
      for (const row of overrides.slice(1)) {
        row.applied = false;
        row.reason = `Überschrieben durch ${overrides[0].source}`;
      }
      const floors = active.filter((c) => c.op === 'floor').map((c) => c.value!);
      const caps = active.filter((c) => c.op === 'cap').map((c) => c.value!);
      const min = Math.max(definition.min ?? -Infinity, ...floors);
      const max = Math.min(definition.max ?? Infinity, ...caps);
      ensure(min <= max, `Widersprüchliche Grenzen für ${id}.`);
      const override = overrides[0]?.value;
      const result = Math.min(max, Math.max(min, override ?? calculated));
      stats[id] = {
        base,
        flat,
        percent,
        multiplier,
        calculated,
        value: result,
        contributions: rows,
        ...(override !== undefined ? { override } : {}),
        ...(min !== -Infinity ? { min } : {}),
        ...(max !== Infinity ? { max } : {}),
      };
      visiting.delete(id);
      return result;
    }
    Object.keys(catalog.stats)
      .filter(
        (id) =>
          !catalog.stats[id].kinds ||
          catalog.stats[id].kinds!.includes(context.entities[context.target].kind),
      )
      .sort(lexical)
      .forEach(stat);
    const flags = new Set(context.entities[context.target].flags ?? []);
    for (const flag of Object.keys(catalog.flags).sort(lexical)) {
      const rows = contributions
        .filter((c) => c.flag === flag && c.applied)
        .sort((a, b) => b.priority - a.priority || Number(a.grant) - Number(b.grant) || tie(a, b));
      if (!rows.length) continue;
      if (rows[0].grant) flags.add(flag);
      else flags.delete(flag);
      for (const row of rows.slice(1)) {
        row.applied = false;
        row.reason = `Flag-Priorität: ${rows[0].source} hat Vorrang`;
      }
    }
    return { version: 1, target: context.target, stats, flags: [...flags].sort(lexical), contributions };
  }
  function check(
    conditionInput: Condition,
    context: RuleContext,
    resolved?: RuleResult,
    source?: string,
  ): ConditionResult {
    validateContext(catalog, context);
    validateCondition(conditionInput, catalog, true);
    if (resolved) ensure(resolved.target === context.target, 'Ergebnis gehört zu einem anderen Objekt.');
    if (source) known(context.entities, source);
    return condition(conditionInput, context, source, resolved);
  }
  /** Validates the complete selection together: order-independent prerequisites and exclusions. */
  function validateTraits(
    context: RuleContext,
    traits: string[],
    options: { budget?: number; maxTraits?: number } = {},
  ) {
    validateContext(catalog, context);
    ensure(
      Array.isArray(traits) && traits.length <= (options.maxTraits ?? 32) && traits.length <= 512,
      'Zu viele Merkmale.',
    );
    ensure(new Set(traits).size === traits.length, 'Doppelte Merkmale.');
    if (options.budget !== undefined) ensure(finite(options.budget), 'Ungültiges Merkmalsbudget.');
    const entity = context.entities[context.target];
    const next = {
      ...context,
      entities: { ...context.entities, [entity.id]: { ...entity, traits: [...traits] } },
    };
    let cost = 0;
    const problems: string[] = [];
    for (const id of traits) {
      const definition = known(catalog.definitions, id);
      ensure(definition.category === 'trait', 'Merkmal erwartet.');
      cost += definition.cost ?? 0;
      if (!definition.kinds.includes(entity.kind)) problems.push(`${definition.name}: falscher Objekttyp.`);
      if (definition.excludes?.some((other) => traits.includes(other)))
        problems.push(`${definition.name}: widersprüchliche Merkmale.`);
      if (definition.requires) {
        const result = condition(definition.requires, next, entity.id);
        if (!result.met)
          problems.push(
            `${definition.name}: ${result.missing ? 'benötigter Kontext fehlt' : 'Voraussetzungen nicht erfüllt'}.`,
          );
      }
    }
    if (options.budget !== undefined && cost > options.budget)
      problems.push(`Merkmalsbudget überschritten: ${cost} / ${options.budget}.`);
    return { valid: problems.length === 0, cost, problems };
  }
  return { catalog, evaluate, check, validateTraits };
}
export type RuleEngine = ReturnType<typeof createRuleEngine>;
