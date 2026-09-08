import { useState } from 'react';
import { Dna, GitBranch, Landmark } from 'lucide-react';
import { AUTHORITIES, EMPIRE_KINDS, ORIGINS, ENVIRONMENTS, TRAITS } from '../shared/empireCatalog';
import { parseGovernment, parseSpeciesDesign, type SpeciesDesign } from '../shared/empires';
import { empireModifiers, MODIFICATION_COST, REFORM_COST } from '../shared/empireState';
import type { GameCommand, GameView } from '../shared/game';
import { EffectList, GovernmentFields, SpeciesFields, SelectField } from './EmpireFields';
import { SHIP_SETS, isShipSet } from '../shared/shipSets';
import { EmpireFlag } from './EmpireFlag';
import './empires.css';
import { ownedColonyWorlds } from '../shared/planetColonies';

export function LiveEmpire({ game, command }: { game: GameView; command: (command: GameCommand) => void }) {
  const empire = game.me.empire!;
  const [tab, setTab] = useState<'overview' | 'reform' | 'species'>('overview');
  const [government, setGovernment] = useState(() => structuredClone(empire.design.government));
  const [sourceId, setSourceId] = useState(empire.primarySpeciesId);
  const [variant, setVariant] = useState<SpeciesDesign | null>(null);
  const [colonyIds, setColonyIds] = useState<string[]>([]);
  const colonies = ownedColonyWorlds(game);
  const source = empire.species.find((s) => s.id === sourceId)!;
  const reformWait = Math.max(0, Math.ceil(empire.reformAvailableAt - game.tick));
  const modificationWait = Math.max(0, Math.ceil(empire.modificationAvailableAt - game.tick));
  const unlocked = game.me.techs.includes('extraction');
  const affordReform =
    game.me.resources.energy >= REFORM_COST.energy && game.me.resources.unity >= REFORM_COST.unity;
  const affordModification =
    game.me.resources.minerals >= MODIFICATION_COST.minerals &&
    game.me.resources.data >= MODIFICATION_COST.data;
  let validation = '';
  try {
    if (tab === 'reform') parseGovernment(government);
    if (tab === 'species' && variant) parseSpeciesDesign(variant, 4);
  } catch (e) {
    validation = (e as Error).message;
  }
  return (
    <section className="living-empire">
      <div className="living-header">
        <EmpireFlag flag={empire.design.flag} width={78} title={`Flagge von ${empire.design.name}`} />
        <div>
          <span className="eyebrow">LEBENDES REICH / REVISION {empire.revision}</span>
          <h3>{empire.design.name}</h3>
          <p>
            {EMPIRE_KINDS[empire.design.government.kind].name} ·{' '}
            {AUTHORITIES[empire.design.government.authority].name}
          </p>
        </div>
      </div>
      <div className="archive-tabs">
        <button
          type="button"
          className={tab === 'overview' ? 'active' : ''}
          onClick={() => setTab('overview')}
        >
          Identität & Herkunft
        </button>
        <button type="button" className={tab === 'reform' ? 'active' : ''} onClick={() => setTab('reform')}>
          <Landmark size={14} />
          Regierungsreform
        </button>
        <button type="button" className={tab === 'species' ? 'active' : ''} onClick={() => setTab('species')}>
          <Dna size={14} />
          Spezies
        </button>
      </div>
      {tab === 'overview' && (
        <>
          <div className="living-facts">
            <div>
              <span>URSPRUNG</span>
              <strong>{ORIGINS[empire.design.origin].name}</strong>
            </div>
            <div>
              <span>HEIMATWELT</span>
              <strong>{empire.design.homeworldName}</strong>
            </div>
            <div>
              <span>{empire.design.rulerTitle || 'FÜHRUNG'}</span>
              <strong>{empire.design.rulerName || 'Unbenannt'}</strong>
            </div>
          </div>
          {empire.design.description && <p className="archive-note">{empire.design.description}</p>}
          <fieldset disabled={!!game.winner} style={{ border: 0, padding: 0 }}>
            <SelectField
              label="Schiffs- und Stationsdesign"
              value={empire.design.shipSet}
              options={SHIP_SETS}
              onChange={(shipSet) => {
                if (isShipSet(shipSet))
                  command({ type: 'empire_ship_set', shipSet, revision: empire.revision });
              }}
            />
          </fieldset>
          <p className="archive-note">
            {SHIP_SETS[empire.design.shipSet].description} Der Wechsel ist kostenlos und verändert keine
            Spielwerte.{' '}
            <a href="/models" target="_blank" rel="noreferrer">
              Designhangar öffnen ↗
            </a>
          </p>
          {empire.design.lore && <p className="living-lore">{empire.design.lore}</p>}
          <EffectList effects={empireModifiers(empire)} />
          <p className="archive-note">
            Gründung aus „{empire.founding.empire.name}“, Revision {empire.founding.empire.revision}. Die
            Gründungskopie bleibt erhalten, auch wenn du ihre Vorlage änderst oder löschst. Kolonieerträge und
            Wachstum berücksichtigen die dort lebenden Spezies; reichsweite Werte verwenden die
            Gründungsspezies.
          </p>
          <details className="living-history">
            <summary>Reichschronik · {empire.history.length} Ereignisse</summary>
            {empire.history
              .slice()
              .reverse()
              .map((entry, index) => (
                <div key={`${entry.tick}-${index}`}>
                  <time>+{Math.floor(entry.tick)} s</time>
                  <span>{entry.text}</span>
                </div>
              ))}
          </details>
        </>
      )}
      {tab === 'reform' && (
        <>
          <p className="archive-note">
            Passe Regierung, Ethiken und Staatselemente dieser Partie an. Ursprung und grundlegender Reichstyp
            bleiben erhalten. Kosten: 100 Energie + 150 Einigkeit. Danach 120 Spieltage Wartezeit.
          </p>
          <GovernmentFields value={government} onChange={setGovernment} lockKind />
          {validation && (
            <p className="archive-validation" role="status">
              {validation}
            </p>
          )}
          <button
            type="button"
            className="primary-button"
            disabled={
              !!validation ||
              reformWait > 0 ||
              !affordReform ||
              JSON.stringify(government) === JSON.stringify(empire.design.government) ||
              !!game.winner
            }
            onClick={() => command({ type: 'empire_reform', government, revision: empire.revision })}
          >
            <Landmark size={15} />
            {reformWait ? `Reform in ${reformWait} s` : 'Regierung reformieren'}
          </button>
          {!affordReform && <p className="archive-muted">Benötigt 100 Energie und 150 Einigkeit.</p>}
        </>
      )}
      {tab === 'species' && (
        <>
          <div className="living-species-list">
            {empire.species.map((species) => {
              const pops = colonies.reduce(
                (sum, system) =>
                  sum +
                  (system.colony?.populations
                    ?.filter((p) => p.speciesId === species.id)
                    .reduce((count, p) => count + p.population, 0) || 0),
                0,
              );
              return (
                <button
                  type="button"
                  className={sourceId === species.id ? 'selected' : ''}
                  key={species.id}
                  onClick={() => {
                    setSourceId(species.id);
                    setVariant(null);
                    setColonyIds([]);
                  }}
                >
                  <GitBranch size={17} />
                  <span>
                    <strong>{species.name}</strong>
                    <small>
                      {species.generation
                        ? `Variante · Generation ${species.generation}`
                        : 'Gründungsspezies'}{' '}
                      · {ENVIRONMENTS[species.environment].name}
                    </small>
                  </span>
                  <b>{pops.toLocaleString('de-DE', { maximumFractionDigits: 1 })} Pops</b>
                </button>
              );
            })}
          </div>
          <p className="archive-note">
            {source.name}:{' '}
            {source.traits.length ? source.traits.map((id) => TRAITS[id].name).join(' · ') : 'Keine Merkmale'}
            .{' '}
            {source.parentId
              ? `Abstammung: ${empire.species.find((s) => s.id === source.parentId)?.name}.`
              : `Aus Speziesvorlage Revision ${source.sourceRevision}.`}
          </p>
          {!variant ? (
            <button
              type="button"
              className="secondary-button"
              disabled={!unlocked || modificationWait > 0 || !!game.winner}
              onClick={() =>
                setVariant({ ...structuredClone(source), name: `${source.name.slice(0, 37)} Nova` })
              }
            >
              <Dna size={15} />
              {modificationWait ? `Modifikation in ${modificationWait} s` : 'Speziesvariante entwerfen'}
            </button>
          ) : (
            <div className="living-modification">
              <p className="archive-note">
                Die Variante erhält ein Budget von 4 Merkmalspunkten. Nur die gewählten Kolonien wechseln zur
                neuen Abstammungslinie. Kosten: 120 Mineralien + 300 Daten. Wartezeit danach: 240 Spieltage.
              </p>
              <SpeciesFields value={variant} onChange={setVariant} budget={4} lockKind showLore={false} />
              <fieldset className="variant-colonies">
                <legend>Bevölkerung in diesen Kolonien anpassen</legend>
                {colonies
                  .filter((s) =>
                    s.colony?.populations?.some((p) => p.speciesId === sourceId && p.population > 0),
                  )
                  .map((system) => (
                    <label key={system.worldId}>
                      <input
                        type="checkbox"
                        checked={colonyIds.includes(system.worldId)}
                        onChange={(e) =>
                          setColonyIds(
                            e.target.checked
                              ? [...colonyIds, system.worldId]
                              : colonyIds.filter((id) => id !== system.worldId),
                          )
                        }
                      />
                      <span>{system.colonyName || system.name}</span>
                    </label>
                  ))}
              </fieldset>
              {validation && <p className="archive-validation">{validation}</p>}
              <button
                type="button"
                className="primary-button"
                disabled={
                  !unlocked ||
                  !affordModification ||
                  !!validation ||
                  !colonyIds.length ||
                  modificationWait > 0 ||
                  !!game.winner
                }
                onClick={() =>
                  command({
                    type: 'species_modify',
                    sourceId,
                    design: variant,
                    colonyIds,
                    revision: empire.revision,
                  })
                }
              >
                Variante anwenden · 120 Mineralien / 300 Daten
              </button>
              {!affordModification && (
                <p className="archive-muted">Nicht genügend Ressourcen für die Speziesmodifikation.</p>
              )}
            </div>
          )}
          {!unlocked && (
            <p className="archive-note">Erforsche Quantenextraktion, um Speziesvarianten freizuschalten.</p>
          )}
        </>
      )}
    </section>
  );
}
