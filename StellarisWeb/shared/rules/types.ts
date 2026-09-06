/** JSON-only rules. IDs are stable, namespaced strings; no executable scripts in saved content. */
export type PropertyValue = string | number | boolean;
export type Scope = { root: 'target' | 'source'; path?: string[] };
export type Value =
  | number
  | { property: string; scope?: Scope }
  | { base: string }
  | { stat: string }
  | { op: 'sum' | 'product' | 'min' | 'max'; values: Value[] }
  | { op: 'divide'; left: Value; right: Value };
export type Condition =
  | { all: Condition[] }
  | { any: Condition[] }
  | { not: Condition }
  | { kind: string; scope?: Scope }
  | { flag: string; scope?: Scope }
  | { trait: string; scope?: Scope }
  | { same: { left: Scope; right: Scope } }
  | { property: string; op: 'eq' | 'ne' | 'gt' | 'gte' | 'lt' | 'lte'; value: PropertyValue; scope?: Scope }
  | { compare: Value; op: 'eq' | 'ne' | 'gt' | 'gte' | 'lt' | 'lte'; value: Value }
  | { related: string; quantifier: 'some' | 'every'; condition: Condition; scope?: Scope };
export type ModifierOperation = 'add' | 'percent' | 'multiply' | 'override' | 'floor' | 'cap';
export interface NumericEffect {
  id: string;
  stat: string;
  op: ModifierOperation;
  value: Value;
  when?: Condition;
  /** A named group is local to a target, stat and operation. */
  stacking?: { group: string; policy: 'sum' | 'highest' | 'lowest' | 'unique' };
  priority?: number;
}
export interface FlagEffect {
  id: string;
  flag: string;
  grant: boolean;
  when?: Condition;
  priority?: number;
}
export type Effect = NumericEffect | FlagEffect;
export interface RuleDefinition {
  name: string;
  description: string;
  category: 'trait' | 'government' | 'technology' | 'building' | 'status' | 'event' | 'policy';
  /** Which entities may own this source. This does not imply an aura or inheritance. */
  kinds: string[];
  /** Checked when acquiring a trait; ongoing effects use their own `when`. */
  requires?: Condition;
  excludes?: string[];
  cost?: number;
  maxStacks?: number;
  effects: Effect[];
}
export interface StatDefinition {
  name: string;
  unit: string;
  /** Omit for genuinely shared values. Domain-specific stats never appear on unrelated objects. */
  kinds?: string[];
  default: number;
  min?: number;
  max?: number;
  /** Evaluated after its dependencies, including their modifiers. */
  derived?: Value;
  better: 'higher' | 'lower' | 'neutral';
}
export interface PropertyDefinition {
  name: string;
  type: 'number' | 'boolean' | 'string';
  values?: string[];
}
export interface RuleCatalog {
  version: 1;
  kinds: string[];
  relations: string[];
  properties: Record<string, PropertyDefinition>;
  flags: Record<string, { name: string; description: string }>;
  stats: Record<string, StatDefinition>;
  definitions: Record<string, RuleDefinition>;
}
export interface RuleEntity {
  id: string;
  kind: string;
  properties?: Record<string, PropertyValue>;
  base?: Record<string, number>;
  flags?: string[];
  traits?: string[];
  relations?: Record<string, string[]>;
}
/** Instances come from authoritative game state. Clients select definitions, never supply effects. */
export interface RuleSource {
  id: string;
  definition: string;
  owner: string;
  stacks?: number;
  startsAt?: number;
  expiresAt?: number;
}
export interface RuleContext {
  target: string;
  entities: Record<string, RuleEntity>;
  tick: number;
}
export interface ConditionResult {
  met: boolean;
  missing: boolean;
  reason: string;
  children?: ConditionResult[];
}
export interface Contribution {
  source: string;
  definition: string;
  effect: string;
  owner: string;
  stat?: string;
  flag?: string;
  op?: ModifierOperation;
  value?: number;
  grant?: boolean;
  stacks: number;
  priority: number;
  applied: boolean;
  reason: string;
}
export interface StatResult {
  base: number;
  flat: number;
  percent: number;
  multiplier: number;
  calculated: number;
  override?: number;
  min?: number;
  max?: number;
  value: number;
  contributions: Contribution[];
}
export interface RuleResult {
  version: 1;
  target: string;
  stats: Record<string, StatResult>;
  flags: string[];
  contributions: Contribution[];
}
