import { useState, type CSSProperties } from 'react';
import { ArrowRight, Check, Copy, Dna, Flag, LoaderCircle, Plus, Save, Search, Trash2 } from 'lucide-react';
import {
  EMPIRE_KINDS,
  ENVIRONMENTS,
  ORIGINS,
  SPECIES_KINDS,
  PORTRAITS,
  addEffects,
} from '../shared/empireCatalog';
import {
  governmentModifiers,
  habitability,
  newEmpire,
  newSpecies,
  parseEmpireTemplate,
  parseSpeciesTemplate,
  speciesModifiers,
  type EmpireLibrary as Library,
  type EmpireTemplate,
  type LibraryMutation,
  type SpeciesTemplate,
} from '../shared/empires';
import {
  EffectList,
  Emblem,
  Field,
  GovernmentFields,
  SectionHeading,
  SelectField,
  SpeciesFields,
} from './EmpireFields';
import './empires.css';
import { flagForEmpire } from '../shared/flags';
import { EmpireFlag } from './EmpireFlag';
import { FlagEditor } from './FlagEditor';

type Draft = { kind: 'empires'; value: EmpireTemplate } | { kind: 'species'; value: SpeciesTemplate };
type Step = 'identity' | 'flag' | 'government' | 'origin' | 'species' | 'lore';
const STEPS: [Step, string][] = [
  ['identity', 'Identität'],
  ['flag', 'Flagge'],
  ['government', 'Gesellschaft'],
  ['origin', 'Ursprung'],
  ['species', 'Spezies'],
  ['lore', 'Geschichte'],
];
export function EmpireLibrary({
  library,
  connected,
  mutate,
  onUse,
}: {
  library: Library | null;
  connected: boolean;
  mutate: (mutation: LibraryMutation) => Promise<Library>;
  onUse: (id: string) => void;
}) {
  const [kind, setKind] = useState<'empires' | 'species'>('empires');
  const [draft, setDraft] = useState<Draft | null>(null);
  const [step, setStep] = useState<Step>('identity');
  const [search, setSearch] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [deleting, setDeleting] = useState(false);
  if (!library)
    return (
      <div className="archive-loading">
        <LoaderCircle className="spin" />
        <h2 id="dialog-title">Deine Sternenarchive</h2>
        <p>
          {connected
            ? 'Die persönliche Bibliothek wird geladen …'
            : 'Verbindung zum Server wird hergestellt …'}
        </p>
      </div>
    );
  const saved = draft ? library[draft.kind].find((t) => t.id === draft.value.id) : undefined;
  const dirty = !!draft && JSON.stringify(draft.value) !== JSON.stringify(saved);
  const empire = draft?.kind === 'empires' ? draft.value : null;
  const species =
    draft?.kind === 'species'
      ? draft.value
      : empire
        ? library.species.find((s) => s.id === empire.speciesTemplateId)
        : null;
  let validation = '';
  if (draft)
    try {
      draft.kind === 'empires'
        ? parseEmpireTemplate(draft.value, library.species)
        : parseSpeciesTemplate(draft.value);
    } catch (e) {
      validation = (e as Error).message;
    }
  function select(next: Draft | null, category = next?.kind || kind) {
    if (dirty && !window.confirm('Ungespeicherte Änderungen verwerfen?')) return;
    setKind(category);
    setDraft(next ? structuredClone(next) : null);
    setError('');
    setMessage('');
    setDeleting(false);
    setStep('identity');
  }
  function editEmpire(value: EmpireTemplate) {
    setDraft({ kind: 'empires', value });
    setMessage('');
    setError('');
  }
  async function save() {
    if (!draft) return;
    setBusy(true);
    setError('');
    try {
      const next = await mutate(
        draft.kind === 'empires'
          ? { type: 'save_empire', template: draft.value }
          : { type: 'save_species', template: draft.value },
      );
      const value = next[draft.kind].find((t) => t.id === draft.value.id)!;
      setDraft({ kind: draft.kind, value } as Draft);
      setMessage('Vorlage gespeichert. Laufende Partien bleiben eigenständig.');
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function remove() {
    if (!draft || !saved) return;
    setBusy(true);
    setError('');
    try {
      await mutate({
        type: draft.kind === 'empires' ? 'delete_empire' : 'delete_species',
        id: saved.id,
        revision: saved.revision,
      });
      setDraft(null);
      setDeleting(false);
      setMessage('Vorlage gelöscht. Bereits gegründete Reiche bleiben erhalten.');
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  function create() {
    if (kind === 'species')
      select({
        kind,
        value: { ...newSpecies(crypto.randomUUID()), name: 'Neue Spezies', plural: 'Neue Spezies' },
      });
    else if (library!.species.length) {
      const primary = library!.species[0];
      select({
        kind,
        value: {
          ...newEmpire(crypto.randomUUID(), primary.id, primary.kind === 'machine' ? 'machine' : 'regular'),
          name: 'Neues Reich',
        },
      });
    } else {
      setError('Lege zuerst eine Speziesvorlage an.');
      setKind('species');
    }
  }
  function duplicate() {
    if (!draft) return;
    select({
      kind: draft.kind,
      value: {
        ...structuredClone(draft.value),
        id: crypto.randomUUID(),
        revision: 0,
        name: `${draft.value.name.slice(0, draft.kind === 'species' ? 40 : 56)} · Kopie`,
      },
    } as Draft);
  }
  const entries = library[kind].filter((t) =>
    `${t.name} ${t.description}`.toLocaleLowerCase('de').includes(search.toLocaleLowerCase('de')),
  );
  return (
    <div className="empire-archive">
      <header className="archive-header">
        <div>
          <span className="eyebrow">SINGULARITY / ZIVILISATIONSARCHIV</span>
          <h2 id="dialog-title">Geschichten beginnen hier.</h2>
          <p>Entwirf Reiche und Spezies für deine nächsten Expeditionen.</p>
        </div>
        <span className="archive-count">
          {library.empires.length}
          <small>REICHE</small>
        </span>
      </header>
      <div className="archive-layout">
        <aside className="archive-library">
          <div className="archive-tabs" aria-label="Vorlagenkategorie">
            <button
              type="button"
              className={kind === 'empires' ? 'active' : ''}
              onClick={() => select(null, 'empires')}
              disabled={busy}
            >
              <Flag size={14} /> Reiche <small>{library.empires.length}</small>
            </button>
            <button
              type="button"
              className={kind === 'species' ? 'active' : ''}
              onClick={() => select(null, 'species')}
              disabled={busy}
            >
              <Dna size={14} /> Spezies <small>{library.species.length}</small>
            </button>
          </div>
          <label className="archive-search">
            <Search size={14} />
            <input
              aria-label="Vorlagen durchsuchen"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Archiv durchsuchen …"
            />
          </label>
          <button
            className="archive-new"
            type="button"
            onClick={create}
            disabled={busy || library[kind].length >= 64}
          >
            <Plus size={15} />
            {kind === 'empires' ? 'Neues Reich' : 'Neue Spezies'}
          </button>
          <div className="archive-entries">
            {entries.map((entry) => (
              <button
                type="button"
                key={entry.id}
                className={`archive-entry ${draft?.value.id === entry.id ? 'selected' : ''}`}
                disabled={busy}
                onClick={() => select({ kind, value: entry } as Draft)}
              >
                <span
                  className="archive-mini-emblem"
                  style={{ color: 'color' in entry ? entry.color : '#58d9cf' }}
                >
                  {'emblem' in entry ? (
                    <EmpireFlag flag={flagForEmpire(entry)} width={33} />
                  ) : (
                    <Emblem name="nexus" size={23} />
                  )}
                </span>
                <span>
                  <strong>{entry.name}</strong>
                  <small>
                    {'government' in entry
                      ? EMPIRE_KINDS[entry.government.kind].name
                      : SPECIES_KINDS[entry.kind].name}
                  </small>
                </span>
                <small>r{entry.revision}</small>
              </button>
            ))}
            {!entries.length && (
              <p className="archive-muted">
                {search ? 'Keine passenden Vorlagen.' : 'Dein Archiv wartet auf die erste Vorlage.'}
              </p>
            )}
          </div>
          <p className="archive-storage-note">
            Persönlich auf diesem Server gespeichert. Dieser Browser bewahrt deinen Zugangsschlüssel auf.
            Speziesvorlagen können von mehreren Reichen verwendet werden.
          </p>
        </aside>
        <main className="archive-editor">
          {!draft ? (
            <div className="archive-welcome">
              <div className="archive-orbit">
                <Emblem name="orbit" size={76} />
              </div>
              <span className="eyebrow">UNENDLICH VIELE MÖGLICHKEITEN</span>
              <h3>
                Ein Ursprung.
                <br />
                Deine Zivilisation.
              </h3>
              <p>
                Wähle eine Vorlage im Archiv oder erschaffe etwas Eigenes. Beim Aufbruch entsteht daraus ein
                unabhängiges Reich, das sich in der Partie weiterentwickelt.
              </p>
              <button type="button" className="primary-button" onClick={create}>
                <Plus size={15} />
                {kind === 'empires' ? 'Reich entwerfen' : 'Spezies entwerfen'}
              </button>
            </div>
          ) : (
            <>
              <div className="archive-editor-title">
                <div>
                  <span className="eyebrow">
                    {draft.kind === 'empires' ? 'REICHSVORLAGE' : 'SPEZIESVORLAGE'} /{' '}
                    {saved ? `REVISION ${saved.revision}` : 'NEUER ENTWURF'}
                  </span>
                  <h3>{draft.value.name || 'Unbenannter Entwurf'}</h3>
                </div>
                <span className={`archive-dirty ${dirty ? '' : 'saved'}`}>
                  {dirty ? 'Ungespeichert' : 'Gespeichert'}
                </span>
              </div>
              {empire && (
                <nav className="archive-steps" aria-label="Reichseditor">
                  {STEPS.map(([id, title], index) => (
                    <button
                      type="button"
                      key={id}
                      className={step === id ? 'active' : ''}
                      onClick={() => setStep(id)}
                    >
                      <small>0{index + 1}</small>
                      {title}
                    </button>
                  ))}
                </nav>
              )}
              <fieldset className="archive-edit-body" disabled={busy}>
                {empire && step === 'identity' && (
                  <>
                    <SectionHeading eyebrow="01 / IDENTITÄT">Ein Name zwischen den Sternen</SectionHeading>
                    <div className="archive-form">
                      <Field
                        label="Reichsname"
                        value={empire.name}
                        maxLength={64}
                        onChange={(name) => editEmpire({ ...empire, name })}
                      />
                      <div className="archive-row">
                        <Field
                          label="Reichsadjektiv"
                          value={empire.adjective}
                          onChange={(adjective) => editEmpire({ ...empire, adjective })}
                        />
                        <Field
                          label="Schiffspräfix"
                          value={empire.shipPrefix}
                          maxLength={12}
                          onChange={(shipPrefix) => editEmpire({ ...empire, shipPrefix })}
                        />
                      </div>
                      <div className="archive-row">
                        <Field
                          label="Heimatwelt"
                          value={empire.homeworldName}
                          onChange={(homeworldName) => editEmpire({ ...empire, homeworldName })}
                        />
                        <Field
                          label="Heimatsystem"
                          value={empire.systemName}
                          onChange={(systemName) => editEmpire({ ...empire, systemName })}
                        />
                      </div>
                      <div className="archive-row">
                        <Field
                          label="Herrschername"
                          value={empire.rulerName}
                          onChange={(rulerName) => editEmpire({ ...empire, rulerName })}
                        />
                        <Field
                          label="Herrschertitel"
                          value={empire.rulerTitle}
                          onChange={(rulerTitle) => editEmpire({ ...empire, rulerTitle })}
                        />
                      </div>
                      <div className="archive-row">
                        <label className="archive-field">
                          <span>Reichsfarbe</span>
                          <input
                            aria-label="Reichsfarbe"
                            type="color"
                            value={empire.color}
                            onChange={(e) => editEmpire({ ...empire, color: e.target.value })}
                          />
                        </label>
                        <button type="button" className="secondary-button" onClick={() => setStep('flag')}>
                          <Flag size={16} />
                          Flagge gestalten
                        </button>
                      </div>
                    </div>
                  </>
                )}
                {empire && step === 'flag' && (
                  <>
                    <SectionHeading eyebrow="02 / FLAGGE">Ein Zeichen für eure Zukunft</SectionHeading>
                    <FlagEditor
                      key={empire.id}
                      name={empire.name}
                      value={flagForEmpire(empire)}
                      onChange={(flag) => editEmpire({ ...empire, flag, emblem: flag.emblem })}
                    />
                  </>
                )}
                {empire && step === 'government' && (
                  <>
                    <SectionHeading eyebrow="03 / GESELLSCHAFT">Was hält euch zusammen?</SectionHeading>
                    <GovernmentFields
                      value={empire.government}
                      onChange={(government) => {
                        const primary = library.species.find(
                          (s) => (government.kind === 'machine') === (s.kind === 'machine'),
                        );
                        editEmpire({
                          ...empire,
                          government,
                          origin:
                            ORIGINS[empire.origin].kinds &&
                            !ORIGINS[empire.origin].kinds!.includes(government.kind)
                              ? 'unification'
                              : empire.origin,
                          speciesTemplateId:
                            (government.kind === 'machine') !== (species?.kind === 'machine') && primary
                              ? primary.id
                              : empire.speciesTemplateId,
                        });
                      }}
                    />
                  </>
                )}
                {empire && step === 'origin' && (
                  <>
                    <SectionHeading eyebrow="04 / URSPRUNG">Vor dem ersten Sprung</SectionHeading>
                    <p className="archive-note">
                      Der Ursprung prägt den Start und bleibt Teil eurer Herkunft. Startressourcen und
                      Bevölkerung werden einmalig bei der Gründung vergeben.
                    </p>
                    <div className="archive-choice-grid origin-grid">
                      {Object.entries(ORIGINS)
                        .filter(
                          ([, origin]) => !origin.kinds || origin.kinds.includes(empire.government.kind),
                        )
                        .map(([id, origin]) => (
                          <button
                            type="button"
                            key={id}
                            className={empire.origin === id ? 'chosen' : ''}
                            aria-pressed={empire.origin === id}
                            onClick={() => editEmpire({ ...empire, origin: id })}
                          >
                            <span className="origin-symbol">
                              <Emblem
                                name={
                                  id === 'awakening' ? 'nexus' : id === 'relic_seekers' ? 'diamond' : 'star'
                                }
                                size={25}
                              />
                            </span>
                            <strong>{origin.name}</strong>
                            <span>{origin.description}</span>
                          </button>
                        ))}
                    </div>
                  </>
                )}
                {empire && step === 'species' && (
                  <>
                    <SectionHeading eyebrow="05 / SPEZIES">Wer blickt zu den Sternen?</SectionHeading>
                    <p className="archive-note">
                      Eine Speziesvorlage kann zu mehreren Reichen gehören. Änderungen daran gelten für
                      zukünftige Gründungen dieser Reiche.
                    </p>
                    <SelectField
                      label="Gründungsspezies"
                      value={empire.speciesTemplateId}
                      options={Object.fromEntries(
                        library.species.map((s) => [
                          s.id,
                          { name: `${s.name} · ${SPECIES_KINDS[s.kind].name}` },
                        ]),
                      )}
                      onChange={(speciesTemplateId) => editEmpire({ ...empire, speciesTemplateId })}
                    />
                    {species && (
                      <div className="archive-species-summary">
                        <Dna size={32} />
                        <h3>{species.name}</h3>
                        <p>
                          {species.description ||
                            'Die Geschichte dieser Spezies wartet darauf, erzählt zu werden.'}
                        </p>
                        <span>
                          {ENVIRONMENTS[species.environment].name} · {SPECIES_KINDS[species.kind].name}
                        </span>
                        <EffectList effects={speciesModifiers(species)} />
                        <button
                          className="secondary-button"
                          type="button"
                          onClick={() => select({ kind: 'species', value: species })}
                        >
                          Speziesvorlage bearbeiten <ArrowRight size={14} />
                        </button>
                      </div>
                    )}
                  </>
                )}
                {empire && step === 'lore' && (
                  <>
                    <SectionHeading eyebrow="06 / GESCHICHTE">Mehr als Koordinaten</SectionHeading>
                    <p className="archive-note">
                      Beschreibung, Namen und Lore geben eurem Reich eine Identität. Sie verändern keine
                      Spielwerte.
                    </p>
                    <Field
                      label="Reichsbeschreibung"
                      value={empire.description}
                      maxLength={240}
                      multiline
                      onChange={(description) => editEmpire({ ...empire, description })}
                    />
                    <Field
                      label="Reichsgeschichte / Lore"
                      value={empire.lore}
                      maxLength={4000}
                      multiline
                      onChange={(lore) => editEmpire({ ...empire, lore })}
                    />
                  </>
                )}
                {draft.kind === 'species' && (
                  <>
                    <SectionHeading eyebrow="BIOLOGIE / KULTUR / HERKUNFT">
                      Ein Bauplan für Leben
                    </SectionHeading>
                    <SpeciesFields
                      value={draft.value}
                      onChange={(value) => {
                        setDraft({ kind: 'species', value: { ...draft.value, ...value } });
                        setMessage('');
                      }}
                    />
                  </>
                )}
              </fieldset>
              <footer className="archive-editor-footer">
                {validation && (
                  <p className="archive-validation" role="status">
                    {validation}
                  </p>
                )}
                {saved && saved.revision !== draft.value.revision && (
                  <p className="archive-validation">
                    Eine andere Sitzung hat diese Vorlage geändert.{' '}
                    <button
                      type="button"
                      onClick={() => {
                        setDraft({ kind: draft.kind, value: structuredClone(saved) } as Draft);
                        setError('');
                      }}
                    >
                      Aktuelle Fassung laden
                    </button>
                  </p>
                )}
                <div className="archive-actions">
                  <button
                    type="button"
                    className="primary-button"
                    disabled={!connected || busy || !dirty || !!validation}
                    onClick={save}
                  >
                    {busy ? <LoaderCircle className="spin" size={15} /> : <Save size={15} />}Vorlage speichern
                  </button>
                  <button type="button" className="secondary-button" onClick={duplicate} disabled={busy}>
                    <Copy size={14} />
                    Duplizieren
                  </button>
                  {saved && (
                    <button
                      type="button"
                      className="archive-delete"
                      disabled={busy}
                      onClick={() => setDeleting(!deleting)}
                      aria-label="Vorlage löschen"
                    >
                      <Trash2 size={15} />
                    </button>
                  )}
                </div>
                {deleting && (
                  <div className="archive-delete-confirm">
                    <span>„{saved?.name}“ aus deiner Bibliothek löschen?</span>
                    <button type="button" disabled={busy} onClick={remove}>
                      Vorlage endgültig löschen
                    </button>
                    <button type="button" onClick={() => setDeleting(false)}>
                      Abbrechen
                    </button>
                  </div>
                )}
              </footer>
            </>
          )}
          {error && (
            <p className="archive-validation" role="alert">
              {error}
            </p>
          )}
          {message && (
            <p className="archive-success" role="status">
              <Check size={15} />
              {message}
            </p>
          )}
        </main>
        <aside
          className="archive-preview"
          style={{ '--empire-color': empire?.color || '#58d9cf' } as CSSProperties}
        >
          <span className="eyebrow">{empire ? 'GRÜNDUNGSPROFIL' : 'SPEZIESPROFIL'}</span>
          {empire ? (
            <div className="archive-flag-preview">
              <EmpireFlag flag={flagForEmpire(empire)} width={220} title={`Flagge von ${empire.name}`} />
            </div>
          ) : (
            <div className="archive-portrait">
              <div className="portrait-ring" />
              <Emblem name="nexus" size={66} />
              <span>{species ? SPECIES_KINDS[species.kind].name : 'UNBEKANNT'}</span>
            </div>
          )}
          <h3>{empire?.name || species?.name || 'Deine nächste Geschichte'}</h3>
          <p>{empire?.description || species?.description || 'Wähle einen Eintrag aus dem Archiv.'}</p>
          {empire && (
            <dl>
              <div>
                <dt>Reichstyp</dt>
                <dd>{EMPIRE_KINDS[empire.government.kind].name}</dd>
              </div>
              <div>
                <dt>Ursprung</dt>
                <dd>{ORIGINS[empire.origin].name}</dd>
              </div>
              <div>
                <dt>Heimat</dt>
                <dd>{empire.homeworldName}</dd>
              </div>
              <div>
                <dt>Bevölkerung</dt>
                <dd>{6 + ORIGINS[empire.origin].population} Pops</dd>
              </div>
            </dl>
          )}
          {species && (
            <>
              <p className="archive-muted">Erscheinungsbild: {PORTRAITS[species.portrait]}</p>
              <h4>Aktive Modifikatoren</h4>
              <EffectList
                effects={
                  empire
                    ? addEffects(
                        governmentModifiers(empire.government, empire.origin),
                        speciesModifiers(species),
                      )
                    : speciesModifiers(species)
                }
              />
              <h4>Bewohnbarkeit</h4>
              <div className="archive-habitability">
                {Object.entries(ENVIRONMENTS).map(([id, environment]) => {
                  const value = habitability(
                    species,
                    id as SpeciesTemplate['environment'],
                    empire ? governmentModifiers(empire.government, empire.origin).habitability : 0,
                  );
                  return (
                    <div key={id}>
                      <span>{environment.name}</span>
                      <meter min={0} max={1} value={value} aria-label={`Bewohnbarkeit ${environment.name}`} />
                      <b>{Math.round(value * 100)} %</b>
                    </div>
                  );
                })}
              </div>
              <p className="archive-muted">
                Ungeeignetes Klima senkt Wachstum und Kolonieerträge. Modifikatoren werden addiert.
              </p>
            </>
          )}
          {empire && (
            <button
              type="button"
              className="primary-button archive-use"
              disabled={dirty || !!validation || !connected || busy}
              onClick={() => onUse(empire.id)}
            >
              Für Expedition wählen <ArrowRight size={15} />
            </button>
          )}
          <p className="archive-storage-note">
            Vorlage → Gründung → lebendes Reich.
            <br />
            Eine spätere Reform verändert die Partie, deine Vorlage bleibt erhalten.
          </p>
        </aside>
      </div>
    </div>
  );
}
