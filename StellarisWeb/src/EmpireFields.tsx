import { useId, type ReactNode } from 'react';
import { Atom, Diamond, Hexagon, Orbit, Sparkles, Workflow } from 'lucide-react';
import {
  AUTHORITIES,
  CIVICS,
  EMPIRE_KINDS,
  ENVIRONMENTS,
  ETHICS,
  MODIFIER_NAMES,
  PORTRAITS,
  SPECIES_KINDS,
  TRAITS,
  type EmpireKind,
  type Modifier,
  type Modifiers,
} from '../shared/empireCatalog';
import { governmentFor, traitCost, type Government, type SpeciesDesign } from '../shared/empires';

export function Field({
  label,
  value,
  onChange,
  maxLength = 48,
  multiline = false,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  maxLength?: number;
  multiline?: boolean;
}) {
  const id = useId();
  return (
    <label className="archive-field" htmlFor={id}>
      <span>{label}</span>
      {multiline ? (
        <textarea
          id={id}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          maxLength={maxLength}
          rows={maxLength > 240 ? 8 : 3}
        />
      ) : (
        <input id={id} value={value} onChange={(e) => onChange(e.target.value)} maxLength={maxLength} />
      )}
    </label>
  );
}
export function SelectField({
  label,
  value,
  onChange,
  options,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  options: Record<string, { name: string }>;
}) {
  const id = useId();
  return (
    <label className="archive-field" htmlFor={id}>
      <span>{label}</span>
      <select id={id} value={value} onChange={(e) => onChange(e.target.value)}>
        {Object.entries(options).map(([key, option]) => (
          <option value={key} key={key}>
            {option.name}
          </option>
        ))}
      </select>
    </label>
  );
}
export function Emblem({ name, size = 30 }: { name: string; size?: number }) {
  const Icon =
    name === 'star'
      ? Sparkles
      : name === 'hexagon'
        ? Hexagon
        : name === 'diamond'
          ? Diamond
          : name === 'nexus'
            ? Workflow
            : name === 'wings'
              ? Atom
              : Orbit;
  return <Icon size={size} strokeWidth={1.15} aria-hidden="true" />;
}
export function EffectList({
  effects,
  empty = 'Keine zusätzlichen Modifikatoren.',
}: {
  effects: Modifiers;
  empty?: string;
}) {
  const entries = (Object.entries(effects) as [Modifier, number][]).filter(
    ([, value]) => Math.abs(value) > 0.00001,
  );
  return (
    <div className="archive-effects">
      {entries.length ? (
        entries.map(([key, value]) => (
          <div key={key}>
            <span>{MODIFIER_NAMES[key]}</span>
            <strong className={(key === 'upkeep' ? value < 0 : value > 0) ? 'positive' : 'negative'}>
              {value > 0 ? '+' : '−'}
              {Math.abs(value * 100).toLocaleString('de-DE', { maximumFractionDigits: 1 })}
              {key === 'habitability' ? ' Pp.' : ' %'}
            </strong>
          </div>
        ))
      ) : (
        <p className="archive-muted">{empty}</p>
      )}
    </div>
  );
}
export function SectionHeading({ eyebrow, children }: { eyebrow: string; children: ReactNode }) {
  return (
    <div className="archive-section-heading">
      <span className="eyebrow">{eyebrow}</span>
      <h3>{children}</h3>
    </div>
  );
}
export function GovernmentFields({
  value,
  onChange,
  lockKind = false,
}: {
  value: Government;
  onChange: (government: Government) => void;
  lockKind?: boolean;
}) {
  const gestalt = value.kind === 'hive' || value.kind === 'machine';
  const authorityOptions = Object.fromEntries(
    Object.entries(AUTHORITIES).filter(([, option]) =>
      (option.kinds as readonly string[]).includes(value.kind),
    ),
  );
  return (
    <div className="archive-form">
      {!lockKind && (
        <fieldset className="archive-choice-grid">
          <legend>Reichstyp</legend>
          {Object.entries(EMPIRE_KINDS).map(([id, option]) => (
            <button
              key={id}
              type="button"
              className={value.kind === id ? 'chosen' : ''}
              aria-pressed={value.kind === id}
              onClick={() => onChange(governmentFor(id as EmpireKind))}
            >
              <strong>{option.name}</strong>
              <span>{option.description}</span>
            </button>
          ))}
        </fieldset>
      )}
      <SelectField
        label="Regierungsform"
        value={value.authority}
        onChange={(authority) => onChange({ ...value, authority: authority as Government['authority'] })}
        options={authorityOptions}
      />
      {gestalt ? (
        <p className="archive-note">
          Das Kollektiv folgt einem gemeinsamen Bewusstsein. Individuelle Ethiken entfallen.
        </p>
      ) : (
        <fieldset className="ethic-grid">
          <legend>
            Ethiken <span>{value.ethics.reduce((sum, e) => sum + e.strength, 0)} / 3 Punkte</span>
          </legend>
          {Object.entries(ETHICS).map(([id, option]) => (
            <label key={id}>
              <span>
                <strong>{option.name}</strong>
                <small>{option.description}</small>
              </span>
              <select
                aria-label={`Ethik ${option.name}`}
                value={value.ethics.find((e) => e.id === id)?.strength || 0}
                onChange={(e) =>
                  onChange({
                    ...value,
                    ethics: [
                      ...value.ethics.filter((ethic) => ethic.id !== id),
                      ...(Number(e.target.value)
                        ? [
                            {
                              id: id as Government['ethics'][number]['id'],
                              strength: Number(e.target.value) as 1 | 2,
                            },
                          ]
                        : []),
                    ],
                  })
                }
              >
                <option value={0}>Neutral</option>
                <option value={1}>Moderat · 1</option>
                <option value={2}>Fanatisch · 2</option>
              </select>
            </label>
          ))}
        </fieldset>
      )}
      <fieldset className="archive-choice-grid">
        <legend>
          Staatselemente <span>{value.civics.length} / 2</span>
        </legend>
        {Object.entries(CIVICS)
          .filter(([, option]) => !option.kinds || option.kinds.includes(value.kind))
          .map(([id, option]) => {
            const selected = value.civics.includes(id);
            const missing = option.requires && !value.ethics.some((e) => e.id === option.requires);
            return (
              <button
                key={id}
                type="button"
                className={selected ? 'chosen' : ''}
                aria-pressed={selected}
                disabled={!selected && (!!missing || value.civics.length >= 2)}
                onClick={() =>
                  onChange({
                    ...value,
                    civics: selected ? value.civics.filter((c) => c !== id) : [...value.civics, id],
                  })
                }
              >
                <strong>{option.name}</strong>
                <span>{option.description}</span>
                {missing && <small>Benötigt {ETHICS[option.requires!].name}</small>}
              </button>
            );
          })}
      </fieldset>
    </div>
  );
}
export function SpeciesFields({
  value,
  onChange,
  budget = 2,
  lockKind = false,
  showLore = true,
}: {
  value: SpeciesDesign;
  onChange: (species: SpeciesDesign) => void;
  budget?: number;
  lockKind?: boolean;
  showLore?: boolean;
}) {
  return (
    <div className="archive-form">
      <div className="archive-row">
        <Field label="Speziesname" value={value.name} onChange={(name) => onChange({ ...value, name })} />
        <Field label="Plural" value={value.plural} onChange={(plural) => onChange({ ...value, plural })} />
      </div>
      <div className="archive-row">
        <Field
          label="Speziesadjektiv"
          value={value.adjective}
          onChange={(adjective) => onChange({ ...value, adjective })}
        />
        {!lockKind && (
          <SelectField
            label="Lebensform"
            value={value.kind}
            options={SPECIES_KINDS}
            onChange={(kind) =>
              onChange({
                ...value,
                kind: kind as SpeciesDesign['kind'],
                traits: value.traits.filter(
                  (id) =>
                    !TRAITS[id].speciesKinds ||
                    TRAITS[id].speciesKinds!.includes(kind as SpeciesDesign['kind']),
                ),
              })
            }
          />
        )}
      </div>
      <div className="archive-row">
        <SelectField
          label="Erscheinungsbild"
          value={value.portrait}
          options={Object.fromEntries(Object.entries(PORTRAITS).map(([id, name]) => [id, { name }]))}
          onChange={(portrait) => onChange({ ...value, portrait: portrait as SpeciesDesign['portrait'] })}
        />
        <SelectField
          label="Bevorzugtes Klima"
          value={value.environment}
          options={ENVIRONMENTS}
          onChange={(environment) =>
            onChange({ ...value, environment: environment as SpeciesDesign['environment'] })
          }
        />
      </div>
      <p className="archive-note">
        {SPECIES_KINDS[value.kind].description} Das Erscheinungsbild ist kosmetisch. Klima und Merkmale
        beeinflussen Wachstum und Produktion.
      </p>
      <fieldset className="archive-choice-grid traits-grid">
        <legend>
          Merkmale{' '}
          <span className={traitCost(value.traits) > budget ? 'negative' : ''}>
            {traitCost(value.traits)} / {budget} Punkte · {value.traits.length} / 5 Merkmale
          </span>
        </legend>
        {Object.entries(TRAITS)
          .filter(([, option]) => !option.speciesKinds || option.speciesKinds.includes(value.kind))
          .map(([id, option]) => {
            const selected = value.traits.includes(id);
            const conflict = option.excludes?.some((other) => value.traits.includes(other));
            return (
              <button
                key={id}
                type="button"
                aria-pressed={selected}
                className={selected ? 'chosen' : ''}
                disabled={!selected && (value.traits.length >= 5 || conflict)}
                onClick={() =>
                  onChange({
                    ...value,
                    traits: selected ? value.traits.filter((t) => t !== id) : [...value.traits, id],
                  })
                }
              >
                <strong>
                  {option.name}
                  <b className={option.cost < 0 ? 'negative' : ''}>
                    {option.cost > 0 ? '+' : ''}
                    {option.cost}
                  </b>
                </strong>
                <span>{option.description}</span>
              </button>
            );
          })}
      </fieldset>
      {showLore && (
        <>
          <Field
            label="Speziesbeschreibung"
            value={value.description}
            maxLength={240}
            multiline
            onChange={(description) => onChange({ ...value, description })}
          />
          <Field
            label="Speziesgeschichte / Lore"
            value={value.lore}
            maxLength={4000}
            multiline
            onChange={(lore) => onChange({ ...value, lore })}
          />
        </>
      )}
    </div>
  );
}
