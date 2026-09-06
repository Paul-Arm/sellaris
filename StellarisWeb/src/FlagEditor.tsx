import { useRef, useState } from 'react';
import { Download, RotateCcw, Shuffle } from 'lucide-react';
import { EMBLEMS } from '../shared/empireCatalog';
import {
  FLAG_BORDERS,
  FLAG_FRAMES,
  FLAG_PATTERNS,
  FLAG_POSITIONS,
  FLAG_PRESETS,
  type FlagDesign,
} from '../shared/flags';
import { EmpireFlag } from './EmpireFlag';
import { SelectField } from './EmpireFields';

function ColorField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="flag-color-field">
      <span>{label}</span>
      <span className="flag-color-input">
        <input type="color" aria-label={label} value={value} onChange={(e) => onChange(e.target.value)} />
        <code>{value.toUpperCase()}</code>
      </span>
    </label>
  );
}
const options = (catalog: Record<string, string>) =>
  Object.fromEntries(Object.entries(catalog).map(([id, name]) => [id, { name }]));
export function FlagEditor({
  value,
  onChange,
  name,
}: {
  value: FlagDesign;
  onChange: (flag: FlagDesign) => void;
  name: string;
}) {
  const initial = useRef(structuredClone(value));
  const artwork = useRef<SVGSVGElement>(null);
  const [notice, setNotice] = useState('');
  function change(patch: Partial<FlagDesign>) {
    onChange({ ...value, ...patch });
    setNotice('');
  }
  function randomize() {
    const pick = <T,>(values: readonly T[]) => values[Math.floor(Math.random() * values.length)];
    const palette = pick(FLAG_PRESETS).flag;
    change({
      pattern: pick(Object.keys(FLAG_PATTERNS) as FlagDesign['pattern'][]),
      primary: palette.primary,
      secondary: palette.secondary,
      symbolColor: palette.symbolColor,
      emblem: pick(Object.keys(EMBLEMS) as FlagDesign['emblem'][]),
      frame: pick(Object.keys(FLAG_FRAMES) as FlagDesign['frame'][]),
      position: 'center',
      size: 40,
      rotation: 0,
    });
  }
  function download() {
    if (!artwork.current) return;
    const svg = artwork.current.cloneNode(true) as SVGSVGElement;
    svg.setAttribute('width', '1500');
    svg.setAttribute('height', '1000');
    svg.removeAttribute('class');
    const url = URL.createObjectURL(
      new Blob([new XMLSerializer().serializeToString(svg)], { type: 'image/svg+xml;charset=utf-8' }),
    );
    const link = document.createElement('a');
    link.href = url;
    link.download = `${
      name
        .replace(/[^\p{L}\p{N} _-]/gu, '')
        .trim()
        .slice(0, 80) || 'Reich'
    }-Flagge.svg`;
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    setNotice('SVG exportiert. Mit „Vorlage speichern“ übernimmst du den Entwurf in dein Reich.');
  }
  return (
    <div className="flag-editor">
      <div className="flag-preview-stage">
        <span className="eyebrow">DEIN ZEICHEN ZWISCHEN DEN STERNEN</span>
        <EmpireFlag
          flag={value}
          width={450}
          title={`Flagge von ${name || 'deinem Reich'}`}
          svgRef={artwork}
        />
        <div className="flag-preview-caption">
          <span>3 : 2 / REICHSBANNER</span>
          <span>{FLAG_PATTERNS[value.pattern]}</span>
        </div>
      </div>
      <div className="flag-toolbar">
        <button type="button" className="secondary-button" onClick={randomize}>
          <Shuffle size={14} />
          Zufälliger Entwurf
        </button>
        <button
          type="button"
          className="secondary-button"
          onClick={() => {
            onChange(structuredClone(initial.current));
            setNotice('');
          }}
        >
          <RotateCcw size={14} />
          Zurücksetzen
        </button>
        <button type="button" className="secondary-button" onClick={download}>
          <Download size={14} />
          SVG exportieren
        </button>
      </div>
      <fieldset className="flag-presets">
        <legend>Eine Idee als Ausgangspunkt</legend>
        {FLAG_PRESETS.map((preset) => (
          <button
            type="button"
            key={preset.name}
            onClick={() => change(preset.flag)}
            aria-label={`Flaggenvorlage ${preset.name}`}
          >
            <EmpireFlag flag={preset.flag} width={90} />
            <span>{preset.name}</span>
          </button>
        ))}
      </fieldset>
      <fieldset className="flag-patterns">
        <legend>Flächenmuster</legend>
        {Object.entries(FLAG_PATTERNS).map(([id, label]) => (
          <button
            type="button"
            key={id}
            aria-label={`Flaggenmuster ${label}`}
            aria-pressed={value.pattern === id}
            className={value.pattern === id ? 'selected' : ''}
            onClick={() => change({ pattern: id as FlagDesign['pattern'] })}
          >
            <EmpireFlag flag={{ ...value, pattern: id as FlagDesign['pattern'] }} width={70} />
            <span>{label}</span>
          </button>
        ))}
      </fieldset>
      <div className="flag-colors">
        <ColorField label="Grundfarbe" value={value.primary} onChange={(primary) => change({ primary })} />
        <ColorField
          label="Zweitfarbe"
          value={value.secondary}
          onChange={(secondary) => change({ secondary })}
        />
        <ColorField
          label="Emblemfarbe"
          value={value.symbolColor}
          onChange={(symbolColor) => change({ symbolColor })}
        />
      </div>
      <fieldset className="flag-symbols">
        <legend>Reichsemblem</legend>
        {Object.entries(EMBLEMS).map(([id, label]) => (
          <button
            type="button"
            key={id}
            aria-label={`Flaggenemblem ${label}`}
            aria-pressed={value.emblem === id}
            className={value.emblem === id ? 'selected' : ''}
            onClick={() => change({ emblem: id as FlagDesign['emblem'] })}
          >
            <EmpireFlag
              flag={{
                ...value,
                pattern: 'solid',
                emblem: id as FlagDesign['emblem'],
                position: 'center',
                size: 50,
                rotation: 0,
                frame: 'none',
                border: 'none',
              }}
              width={64}
            />
            <span>{label}</span>
          </button>
        ))}
      </fieldset>
      <div className="archive-row">
        <SelectField
          label="Emblemposition"
          value={value.position}
          options={options(FLAG_POSITIONS)}
          onChange={(position) => change({ position: position as FlagDesign['position'] })}
        />
        <SelectField
          label="Emblemrahmen"
          value={value.frame}
          options={options(FLAG_FRAMES)}
          onChange={(frame) => change({ frame: frame as FlagDesign['frame'] })}
        />
      </div>
      <div className="archive-row">
        <label className="flag-range">
          <span>
            Emblemgröße <output>{value.size} %</output>
          </span>
          <input
            type="range"
            min={20}
            max={65}
            step={1}
            aria-label="Emblemgröße"
            value={value.size}
            onChange={(e) => change({ size: Number(e.target.value) })}
          />
        </label>
        <label className="flag-range">
          <span>
            Emblemdrehung <output>{value.rotation}°</output>
          </span>
          <input
            type="range"
            min={0}
            max={360}
            step={15}
            aria-label="Emblemdrehung"
            value={value.rotation}
            onChange={(e) => change({ rotation: Number(e.target.value) })}
          />
        </label>
      </div>
      <SelectField
        label="Flaggenrand"
        value={value.border}
        options={options(FLAG_BORDERS)}
        onChange={(border) => change({ border: border as FlagDesign['border'] })}
      />
      <div className="flag-scale-preview">
        <div>
          <EmpireFlag flag={value} width={60} />
          <span>IM SPIEL</span>
        </div>
        <div>
          <EmpireFlag flag={value} width={30} />
          <span>SPIELERLISTE</span>
        </div>
        <p>
          Die Flagge ist kosmetisch. Die Reichsfarbe für die Galaxiekarte stellst du unter „Identität“ ein.
        </p>
      </div>
      {notice && (
        <p className="archive-success" role="status">
          {notice}
        </p>
      )}
    </div>
  );
}
