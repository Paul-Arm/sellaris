import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import { ArrowUpRight, Focus, Search, ZoomIn, ZoomOut, Layers, EyeOff } from 'lucide-react';
import {
  RESEARCH_FIELDS,
  TECHS,
  visibleResearch,
  type TechId,
  type ResearchField,
  type ResearchProgram,
} from '../shared/research';
import { layoutResearch, nodesInViewport } from './research-map-model';

const fields = Object.keys(RESEARCH_FIELDS) as ResearchField[];
export function ResearchMap({
  known,
  program,
  selected,
  onSelect,
  focusRequest,
}: {
  known: TechId[];
  program: ResearchProgram;
  selected: TechId;
  onSelect: (id: TechId) => void;
  focusRequest: { id: TechId; revision: number } | null;
}) {
  const [overview, setOverview] = useState(true);
  const [field, setField] = useState<ResearchField | 'all'>('all');
  const [filter, setFilter] = useState<'frontier' | 'program' | 'all'>('frontier');
  const [query, setQuery] = useState('');
  const [zoom, setZoom] = useState(1);
  const [rect, setRect] = useState({ x: 0, y: 0, width: 1000, height: 500 });
  const viewport = useRef<HTMLDivElement>(null);
  const dragging = useRef<{ x: number; y: number; left: number; top: number } | null>(null);
  const lastFocus = useRef<number | null>(null);
  const revealed = useMemo(() => visibleResearch(known), [known]);
  const discovered = new Set(revealed),
    completed = new Set(known);
  const projects = new Map(program.projects.map((p) => [p.tech, p]));
  const matches = revealed.filter((id) =>
    `${TECHS[id].name} ${TECHS[id].description}`
      .toLocaleLowerCase('de')
      .includes(query.trim().toLocaleLowerCase('de')),
  );
  const ids = revealed.filter(
    (id) =>
      (field === 'all' || TECHS[id].field === field) &&
      (filter === 'all' || (filter === 'frontier' ? !completed.has(id) : projects.has(id))),
  );
  const idKey = ids.join(',');
  const layout = useMemo(() => layoutResearch(TECHS, idKey ? idKey.split(',') : []), [idKey]);
  const visibleNodes = nodesInViewport(layout.nodes, {
    x: rect.x / zoom,
    y: rect.y / zoom,
    width: rect.width / zoom,
    height: rect.height / zoom,
  });
  const mounted = new Set(visibleNodes.map((n) => n.id));
  const [center, setCenter] = useState<TechId | null>(null);
  const open = (id: TechId) => {
    if (!discovered.has(id)) return;
    setOverview(false);
    setField(TECHS[id].field);
    setFilter('all');
    setZoom(1);
    setQuery('');
    setCenter(id);
    onSelect(id);
  };
  useEffect(() => {
    if (focusRequest && lastFocus.current !== focusRequest.revision && revealed.includes(focusRequest.id)) {
      lastFocus.current = focusRequest.revision;
      setOverview(false);
      setField(TECHS[focusRequest.id].field);
      setFilter('all');
      setZoom(1);
      setCenter(focusRequest.id);
    }
  }, [focusRequest, revealed]);
  useEffect(() => {
    const v = viewport.current;
    if (!v || overview) return;
    const update = () =>
      setRect({ x: v.scrollLeft, y: v.scrollTop, width: v.clientWidth, height: v.clientHeight });
    const observer = new ResizeObserver(update);
    observer.observe(v);
    update();
    return () => observer.disconnect();
  }, [overview]);
  useEffect(() => {
    const v = viewport.current;
    if (!v || overview) return;
    const node = center && layout.nodes.find((n) => n.id === center);
    v.scrollTo(
      node ? Math.max(0, node.x * zoom - v.clientWidth / 2) : 0,
      node ? Math.max(0, node.y * zoom - v.clientHeight / 2) : 0,
    );
    setRect({ x: v.scrollLeft, y: v.scrollTop, width: v.clientWidth, height: v.clientHeight });
  }, [layout, overview, zoom, center]);
  const detail = (f: ResearchField | 'all') => {
    setField(f);
    setOverview(false);
    setCenter(null);
    setZoom(1);
    const candidates = revealed.filter((id) => f === 'all' || TECHS[id].field === f);
    const target = candidates.find((id) => !completed.has(id)) || candidates[0];
    if (target) onSelect(target);
  };
  const fit = () => {
    const v = viewport.current;
    if (!v) return;
    const scale = Math.min(v.clientWidth / layout.width, v.clientHeight / layout.height, 1.2);
    if (scale < 0.55) setOverview(true);
    else {
      setCenter(null);
      setZoom(scale);
    }
  };
  return (
    <>
      <div className="ra-map-toolbar">
        <label>
          <Search size={15} />
          <input
            aria-label="Entdeckte Technologien durchsuchen"
            placeholder="Entdecktes Wissen suchen …"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </label>
        <div>
          <button
            title="Forschungsgebiete"
            aria-label="Forschungsgebiete anzeigen"
            onClick={() => setOverview(true)}
          >
            <Layers size={16} />
          </button>
          <button
            aria-label="Forschungslandkarte verkleinern"
            disabled={overview}
            onClick={() => (zoom / 1.25 < 0.55 ? setOverview(true) : setZoom(zoom / 1.25))}
          >
            <ZoomOut size={16} />
          </button>
          <button aria-label="Sichtbares Forschungsgebiet einpassen" disabled={overview} onClick={fit}>
            <Focus size={16} />
          </button>
          <button
            aria-label="Forschungslandkarte vergrößern"
            onClick={() => (overview ? detail(field) : setZoom(Math.min(1.6, zoom * 1.25)))}
          >
            <ZoomIn size={16} />
          </button>
        </div>
      </div>
      {query.trim() && (
        <div className="ra-search-results" aria-live="polite">
          {matches.length
            ? matches.slice(0, 12).map((id) => (
                <button key={id} onClick={() => open(id)}>
                  {TECHS[id].name}
                </button>
              ))
            : 'Keine entdeckte Technologie gefunden.'}
          {matches.length > 12 && <span>{matches.length} Treffer · Suche eingrenzen</span>}
        </div>
      )}
      {!overview && (
        <div className="ra-map-filters">
          <select
            aria-label="Forschungsgebiet"
            value={field}
            onChange={(e) => detail(e.target.value as ResearchField | 'all')}
          >
            <option value="all">Alle Gebiete</option>
            {fields.map((f) => (
              <option key={f} value={f}>
                {RESEARCH_FIELDS[f].name}
              </option>
            ))}
          </select>
          <select
            aria-label="Wissensstand filtern"
            value={filter}
            onChange={(e) => {
              setFilter(e.target.value as typeof filter);
              setCenter(null);
            }}
          >
            <option value="frontier">Forschungsfront</option>
            <option value="program">Im Programm</option>
            <option value="all">Mit erforschtem Wissen</option>
          </select>
          <span>{ids.length} aufgedeckte Knoten</span>
          {filter === 'frontier' && known.some((id) => field === 'all' || TECHS[id].field === field) && (
            <button className="ra-archive-toggle" onClick={() => setFilter('all')}>
              Erforschte Grundlagen einblenden
            </button>
          )}
        </div>
      )}
      {overview ? (
        <div className="ra-overview" aria-label="Forschungsgebiete">
          <div className="ra-overview-intro">
            <span className="eyebrow">DEIN WISSENSHORIZONT</span>
            <h3>Wohin führt deine nächste Entdeckung?</h3>
            <p>Öffne ein Gebiet. Neue Verbindungen entstehen, wenn du seine Grundlagen erforschst.</p>
          </div>
          <div className="ra-field-grid">
            {fields.map((f, i) => {
              const members = revealed.filter((id) => TECHS[id].field === f),
                ready = members.filter((id) => !completed.has(id));
              return (
                <button
                  key={f}
                  className="ra-field-card"
                  style={{ '--node-color': RESEARCH_FIELDS[f].color } as CSSProperties}
                  onClick={() => {
                    setFilter('frontier');
                    detail(f);
                  }}
                >
                  <span className="ra-field-number">
                    0{i + 1}
                    <ArrowUpRight size={20} />
                  </span>
                  <strong>{RESEARCH_FIELDS[f].name}</strong>
                  <span>
                    {ready.length} erforschbar · {members.filter((id) => projects.has(id)).length} im Programm
                  </span>
                  <div className="ra-field-frontier">
                    {ready.slice(0, 2).map((id) => (
                      <span key={id}>{TECHS[id].name}</span>
                    ))}
                    {!ready.length && <span>Aktuell kein offenes Projekt</span>}
                  </div>
                  <small>{members.filter((id) => completed.has(id)).length} Erkenntnisse im Archiv</small>
                </button>
              );
            })}
          </div>
          <div className="ra-fog">
            <EyeOff size={17} />
            <span>
              Jenseits des Horizonts bleibt Wissen verborgen. Auch die Suche verrät keine zukünftigen
              Technologien.
            </span>
          </div>
        </div>
      ) : (
        <div
          ref={viewport}
          className="ra-map"
          onScroll={(e) =>
            setRect({
              x: e.currentTarget.scrollLeft,
              y: e.currentTarget.scrollTop,
              width: e.currentTarget.clientWidth,
              height: e.currentTarget.clientHeight,
            })
          }
          onPointerDown={(e) => {
            if (e.button !== 0 || (e.target as Element).closest('[role="button"]')) return;
            dragging.current = {
              x: e.clientX,
              y: e.clientY,
              left: e.currentTarget.scrollLeft,
              top: e.currentTarget.scrollTop,
            };
            e.currentTarget.setPointerCapture(e.pointerId);
          }}
          onPointerMove={(e) => {
            const d = dragging.current;
            if (d) e.currentTarget.scrollTo(d.left + d.x - e.clientX, d.top + d.y - e.clientY);
          }}
          onPointerUp={() => (dragging.current = null)}
          onPointerCancel={() => (dragging.current = null)}
        >
          {!ids.length && (
            <p className="ra-map-empty">
              Keine Projekte in dieser Ansicht. Wechsle das Gebiet oder den Wissensfilter.
            </p>
          )}
          <svg
            width={layout.width * zoom}
            height={layout.height * zoom}
            viewBox={`0 0 ${layout.width} ${layout.height}`}
            role="group"
            aria-label="Aufgedeckte Forschungslandkarte"
          >
            {layout.edges
              .filter(
                (e) =>
                  (e.from.id === selected || e.to.id === selected) &&
                  (mounted.has(e.from.id) || mounted.has(e.to.id)),
              )
              .map(({ from: a, to: b }) => (
                <path
                  key={`${a.id}-${b.id}`}
                  className="ra-link selected"
                  d={`M ${a.x} ${a.y + 40} C ${a.x} ${a.y + 90}, ${b.x} ${b.y - 90}, ${b.x} ${b.y - 40}`}
                />
              ))}
            {visibleNodes.map((node) => {
              const id = node.id as TechId,
                t = TECHS[id],
                p = projects.get(id),
                done = completed.has(id);
              return (
                <g
                  key={id}
                  transform={`translate(${node.x},${node.y})`}
                  role="button"
                  tabIndex={0}
                  aria-label={`${t.name}: ${done ? 'erforscht' : p ? 'im Programm' : 'verfügbar'}`}
                  aria-pressed={selected === id}
                  className={`ra-node ${done ? 'done' : ''} ${selected === id ? 'selected' : ''}`}
                  style={{ '--node-color': RESEARCH_FIELDS[t.field].color } as CSSProperties}
                  onClick={() => onSelect(id)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault();
                      onSelect(id);
                    }
                    if (e.key.startsWith('Arrow')) {
                      e.preventDefault();
                      const horizontal = ['ArrowLeft', 'ArrowRight'].includes(e.key),
                        sign = ['ArrowLeft', 'ArrowUp'].includes(e.key) ? -1 : 1;
                      const next = layout.nodes
                        .filter((n) => (horizontal ? n.x - node.x : n.y - node.y) * sign > 0)
                        .sort(
                          (a, b) =>
                            Math.hypot(a.x - node.x, a.y - node.y) - Math.hypot(b.x - node.x, b.y - node.y),
                        )[0];
                      if (next) {
                        onSelect(next.id as TechId);
                        setCenter(next.id as TechId);
                        requestAnimationFrame(() =>
                          viewport.current?.querySelector<SVGElement>(`[data-tech="${next.id}"]`)?.focus(),
                        );
                      }
                    }
                  }}
                  data-tech={id}
                >
                  <rect x="-110" y="-40" width="220" height="80" rx="11" />
                  <text className="ra-node-status" x="-96" y="-18">
                    {done ? 'ERFORSCHT' : p ? 'IM PROGRAMM' : 'VERFÜGBAR'}
                  </text>
                  <foreignObject x="-98" y="-7" width="196" height="43">
                    <div className="ra-node-label">{t.name}</div>
                  </foreignObject>
                  {p && (
                    <line
                      className="ra-node-progress"
                      x1="-104"
                      y1="34"
                      x2={-104 + (208 * p.done) / t.work}
                      y2="34"
                    />
                  )}
                </g>
              );
            })}
          </svg>
        </div>
      )}
      <div className="ra-map-caption">
        <span>
          {overview
            ? 'Gebiete bündeln dein entdecktes Wissen.'
            : 'Nur Verbindungen der Auswahl · Erforschtes über den Filter einblenden'}
        </span>
        <span>{overview ? 'Neue Grundlagen öffnen weitere Wege.' : 'Ziehen · Zoom · Pfeiltasten'}</span>
      </div>
    </>
  );
}
