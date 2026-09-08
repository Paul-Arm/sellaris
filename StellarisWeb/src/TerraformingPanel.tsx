import { useEffect, useState } from 'react';
import type { Client } from '../backend/client';
import { watchTables } from '../backend/projection-cache';
import type { GameView, StarSystem } from '../shared/game';
import type { StoredBody } from '../shared/systemObjects';
import { ENVIRONMENTS, type Environment } from '../shared/empireCatalog';
import { habitability, governmentModifiers } from '../shared/empires';
import { colonyProduction } from '../shared/colonies';
import {
  terraformingSpec,
  terraformWork,
  terraformingRate,
  type TerraformProject,
} from '../shared/terraforming';
import { empireCompute } from '../shared/empireEconomy';
import './terraforming.css';
import { planetWorld } from '../shared/planetColonies';

export function TerraformingPanel({
  body,
  client,
  game,
  system,
  disabled,
}: {
  body: StoredBody;
  client: Client;
  game: GameView;
  system: StarSystem;
  disabled: boolean;
}) {
  const [project, setProject] = useState<TerraformProject | null>(null);
  const [targetChoice, setTarget] = useState<Environment>('continental');
  const [busy, setBusy] = useState(false),
    [error, setError] = useState('');
  useEffect(() => {
    const table = client.conn.db.myTerraformProjects;
    const update = () => setProject([...table.iter()].find((p) => p.id === body.objectId) ?? null);
    const unwatch = watchTables([table], update);
    update();
    return unwatch;
  }, [client, body.objectId]);
  if (!body.environment) return null;
  const environments = Object.keys(ENVIRONMENTS) as Environment[];
  const target =
    targetChoice === body.environment ? environments.find((e) => e !== body.environment)! : targetChoice;
  const spec = terraformingSpec(body.environment, target);
  const compute = ((game.me.compute ?? empireCompute(game, game.me)) * game.me.research.terraforming) / 100;
  const rate =
    project?.rate ?? terraformingRate(compute, Number(client.conn.db.myTerraformProjects.count()) + 1);
  const unlocked = game.me.techs.includes('terraforming');
  const surveyed = game.me.surveyed.includes(system.id);
  const affordable = Object.entries(spec.cost).every(
    ([key, amount]) => game.me.resources[key as keyof typeof spec.cost] >= amount,
  );
  const empire = game.me.empire,
    species = empire?.species.find((s) => s.id === empire.primarySpeciesId);
  const bonus = empire ? governmentModifiers(empire.design.government, empire.design.origin).habitability : 0;
  const colony = game.planetColonies?.find((c) => c.objectId === body.objectId);
  const world = colony ? planetWorld(system, colony) : system;
  const currentRate = colonyProduction(world, game.me);
  const targetRate = colonyProduction({ ...world, planet: ENVIRONMENTS[target].name }, game.me);
  const submit = (action: () => Promise<unknown>) => {
    if (busy) return;
    setBusy(true);
    setError('');
    void action()
      .catch((e) => setError(String(e)))
      .finally(() => setBusy(false));
  };
  return (
    <section className="terraforming-panel" aria-label="Terraforming">
      <h3>Klimagestaltung</h3>
      <p className="terraforming-climate">
        Aktuell: <strong>{ENVIRONMENTS[body.environment].name}</strong>
      </p>
      {project ? (
        <>
          <p>
            Ziel: <strong>{ENVIRONMENTS[project.target as Environment].name}</strong>
          </p>
          <progress
            aria-label="Terraforming-Fortschritt"
            max={1}
            value={terraformWork(project, game.tick) / project.workTotal}
          />
          <p role="status">
            {game.paused ? 'Terraforming pausiert' : 'Terraforming läuft'} ·{' '}
            {Math.max(0, Math.ceil(project.finishAt - game.tick))} Tage verbleibend
          </p>
          <button
            disabled={disabled || busy}
            onClick={() => submit(() => client.conn.reducers.cancelTerraforming({ objectId: body.objectId }))}
          >
            Terraforming abbrechen
          </button>
          <small>
            Erstattet 50 %: {project.paidEnergy / 2} Energie, {project.paidMinerals / 2} Mineralien,{' '}
            {project.paidData / 2} Daten.
          </small>
        </>
      ) : (
        <>
          {!unlocked && (
            <p>
              Erforsche zuerst <strong>Klimagestaltung</strong> im Forschungsmenü.
            </p>
          )}
          <label>
            Zielklima
            <select
              value={target}
              onChange={(e) => setTarget(e.target.value as Environment)}
              disabled={disabled || busy}
            >
              {environments
                .filter((e) => e !== body.environment)
                .map((e) => (
                  <option key={e} value={e}>
                    {ENVIRONMENTS[e].name}
                  </option>
                ))}
            </select>
          </label>
          {species && (
            <p>
              Bewohnbarkeit der Hauptspezies:{' '}
              <strong>
                {Math.round(habitability(species, body.environment, bonus) * 100)} % →{' '}
                {Math.round(habitability(species, target, bonus) * 100)} %
              </strong>
            </p>
          )}
          {body.main || colony ? (
            <>
              <table>
                <caption>Kolonieertrag pro Monat</caption>
                <thead>
                  <tr>
                    <th>Rohstoff</th>
                    <th>Heute</th>
                    <th>Danach</th>
                  </tr>
                </thead>
                <tbody>
                  {(['energy', 'minerals', 'data'] as const).map((key) => (
                    <tr key={key}>
                      <th>{{ energy: 'Energie', minerals: 'Mineralien', data: 'Daten' }[key]}</th>
                      <td>{currentRate[key].toFixed(1)}</td>
                      <td>{targetRate[key].toFixed(1)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <small>
                Das neue Klima beeinflusst Bewohnbarkeit, Wachstum und Kolonieerträge. Bevölkerung und
                Ausbauten bleiben erhalten.
              </small>
            </>
          ) : (
            <small>
              Diese Nebenwelt hat noch keine eigene Bevölkerung. Terraforming ändert ihr Klima und Aussehen;
              bestehende Außenanlagen behalten ihre Erträge.
            </small>
          )}
          <p>
            {spec.cost.energy} Energie · {spec.cost.minerals} Mineralien · {spec.cost.data} Daten ·{' '}
            {Math.ceil(spec.days / rate)} Tage bei aktuellem Budget
          </p>
          {!surveyed && <p>Untersuche zuerst das System.</p>}
          {!affordable && <p>Nicht genug Rohstoffe.</p>}
          <button
            disabled={disabled || busy || !unlocked || !surveyed || !affordable}
            onClick={() =>
              submit(() =>
                client.conn.reducers.startTerraforming({
                  objectId: body.objectId,
                  revision: body.revision,
                  target,
                }),
              )
            }
          >
            Terraforming starten
          </button>
          <small>Ein Projekt je Planet. Bei Systemverlust endet das Projekt ohne Erstattung.</small>
        </>
      )}
      <p>
        Compute-Klimasimulation: +{((rate - 1) * 100).toFixed(1)} % Tempo. Das Budget im Forschungsmenü wird
        auf alle laufenden Projekte verteilt.
      </p>
      {error && <p role="alert">{error}</p>}
    </section>
  );
}
