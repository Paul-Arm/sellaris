import { memo, useMemo } from 'react';
import { createGalaxy } from '../shared/galaxy';
import {
  GALAXY_TYPES,
  GALAXY_SIZES,
  HYPERLANE_DENSITIES,
  type GalaxySettings,
} from '../shared/galaxySettings';
import './galaxy-setup.css';

export const GalaxySetup = memo(function GalaxySetup({
  value,
  onChange,
  disabled,
}: {
  value: GalaxySettings;
  onChange: (value: GalaxySettings) => void;
  disabled: boolean;
}) {
  const preview = useMemo(() => {
    const game = createGalaxy('A1B2C3', 42, value);
    const index = new Map(game.systems.map((s) => [s.id, s]));
    return { stars: game.systems, lanes: game.links.map(([a, b]) => [index.get(a)!, index.get(b)!]) };
  }, [value]);
  return (
    <fieldset className="galaxy-setup" disabled={disabled}>
      <legend>DEINE NEUE GALAXIE</legend>
      <div className="galaxy-setup-preview">
        <svg viewBox="0 0 1600 1050" role="img" aria-label={`Formvorschau: ${GALAXY_TYPES[value.type].name}`}>
          <g stroke="#a69de9" strokeOpacity=".19" strokeWidth="2">
            {preview.lanes.map(([a, b]) => (
              <path key={`${a.id}:${b.id}`} d={`M${a.x},${a.y}L${b.x},${b.y}`} />
            ))}
          </g>
          {preview.stars.map((s) => (
            <circle key={s.id} cx={s.x} cy={s.y} r={s.kind === 'star' ? 3 : 5} fill={s.color} />
          ))}
        </svg>
        <span>FORMVORSCHAU</span>
      </div>
      <div className="galaxy-setup-fields">
        <label htmlFor="galaxy-type">GALAXIETYP</label>
        <select
          id="galaxy-type"
          value={value.type}
          onChange={(e) => onChange({ ...value, type: e.target.value as GalaxySettings['type'] })}
        >
          {Object.entries(GALAXY_TYPES).map(([id, type]) => (
            <option key={id} value={id}>
              {type.name}
            </option>
          ))}
        </select>
        <p>{GALAXY_TYPES[value.type].description}</p>
        <span id="galaxy-size-label">STERNSYSTEME</span>
        <div className="galaxy-options" role="group" aria-labelledby="galaxy-size-label">
          {GALAXY_SIZES.map((systems) => (
            <button
              type="button"
              key={systems}
              aria-pressed={value.systems === systems}
              onClick={() => onChange({ ...value, systems })}
            >
              {systems.toLocaleString('de-DE')}
            </button>
          ))}
        </div>
        <span id="galaxy-lanes-label">HYPERLANE-DICHTE</span>
        <div className="galaxy-options" role="group" aria-labelledby="galaxy-lanes-label">
          {Object.entries(HYPERLANE_DENSITIES).map(([id, density]) => (
            <button
              type="button"
              key={id}
              aria-pressed={value.hyperlaneDensity === id}
              onClick={() =>
                onChange({ ...value, hyperlaneDensity: id as GalaxySettings['hyperlaneDensity'] })
              }
            >
              {density.name}
            </button>
          ))}
        </div>
        <p>{HYPERLANE_DENSITIES[value.hyperlaneDensity].description}</p>
      </div>
    </fieldset>
  );
});
