import { useEffect, useMemo, useRef, useState } from 'react';
import { Crosshair, Minus, Plus } from 'lucide-react';
import type { AdminMatch } from '../shared/admin';

export function AdminGalaxyMap({
  match,
  empireId,
  systemId,
  onSystem,
  focus,
}: {
  match: AdminMatch;
  empireId: number;
  systemId: number;
  onSystem: (id: number) => void;
  focus: { x: number; y: number; serial: number } | null;
}) {
  const bounds = useMemo(() => {
    const xs = match.systems.map((s) => s.x),
      ys = match.systems.map((s) => s.y);
    const x = (xs.length ? Math.min(...xs) : 0) - 45,
      y = (ys.length ? Math.min(...ys) : 0) - 45;
    return {
      x,
      y,
      w: (xs.length ? Math.max(...xs) : 1600) - x + 45,
      h: (ys.length ? Math.max(...ys) : 1050) - y + 45,
    };
  }, [match.systems]);
  const [view, setView] = useState(bounds);
  const [showLanes, setShowLanes] = useState(true);
  const [showFleets, setShowFleets] = useState(true);
  const drag = useRef<{ x: number; y: number; view: typeof view } | null>(null);
  const systems = useMemo(() => new Map(match.systems.map((s) => [s.id, s])), [match.systems]);
  const colors = useMemo(() => new Map(match.empires.map((e) => [e.id, e.color])), [match.empires]);
  useEffect(() => {
    if (focus)
      setView({ x: focus.x - bounds.w / 6, y: focus.y - bounds.h / 6, w: bounds.w / 3, h: bounds.h / 3 });
  }, [focus, bounds.w, bounds.h]);
  const zoom = (factor: number) =>
    setView((v) => {
      const w = Math.max(bounds.w / 12, Math.min(bounds.w * 1.5, v.w * factor));
      const h = (w * bounds.h) / bounds.w;
      return { x: v.x + (v.w - w) / 2, y: v.y + (v.h - h) / 2, w, h };
    });
  return (
    <section className="admin-map" aria-label="Galaxiekarte">
      <div className="admin-map-tools">
        <span>
          {match.systems.length} Systeme · {match.lanes.length} Hyperlanes
        </span>
        <label>
          <input type="checkbox" checked={showLanes} onChange={(e) => setShowLanes(e.target.checked)} />{' '}
          Hyperlanes
        </label>
        <label>
          <input type="checkbox" checked={showFleets} onChange={(e) => setShowFleets(e.target.checked)} />{' '}
          Flotten
        </label>
        <button aria-label="Karte vergrößern" onClick={() => zoom(0.7)}>
          <Plus size={15} />
        </button>
        <button aria-label="Karte verkleinern" onClick={() => zoom(1.4)}>
          <Minus size={15} />
        </button>
        <button aria-label="Gesamte Galaxie anzeigen" onClick={() => setView(bounds)}>
          <Crosshair size={15} />
        </button>
      </div>
      <svg
        viewBox={`${view.x} ${view.y} ${view.w} ${view.h}`}
        aria-label="Sternsysteme und Reichsgebiete"
        onPointerDown={(e) => {
          if ((e.target as Element).closest('[data-system]')) return;
          drag.current = { x: e.clientX, y: e.clientY, view };
          e.currentTarget.setPointerCapture(e.pointerId);
        }}
        onPointerMove={(e) => {
          if (!drag.current) return;
          const r = e.currentTarget.getBoundingClientRect();
          const scale = Math.max(drag.current.view.w / r.width, drag.current.view.h / r.height);
          setView({
            ...drag.current.view,
            x: drag.current.view.x - (e.clientX - drag.current.x) * scale,
            y: drag.current.view.y - (e.clientY - drag.current.y) * scale,
          });
        }}
        onPointerUp={() => {
          drag.current = null;
        }}
        onPointerCancel={() => {
          drag.current = null;
        }}
      >
        {showLanes && (
          <g stroke="#263746" strokeWidth={0.8}>
            {match.lanes.map((l) => {
              const a = systems.get(l.a),
                b = systems.get(l.b);
              return a && b ? <line key={`${l.a}-${l.b}`} x1={a.x} y1={a.y} x2={b.x} y2={b.y} /> : null;
            })}
          </g>
        )}
        {match.systems.map((s) => (
          <g
            key={s.id}
            data-system={s.id}
            role="button"
            tabIndex={s.id === (systemId || match.systems[0]?.id) ? 0 : -1}
            aria-label={`${s.name}${s.ownerId ? `, ${match.empires.find((e) => e.id === s.ownerId)?.name ?? 'Besetzt'}` : ', unbesetzt'}`}
            onClick={() => onSystem(s.id)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                onSystem(s.id);
              }
            }}
            opacity={empireId && s.ownerId && s.ownerId !== empireId ? 0.3 : 1}
          >
            <title>
              {s.name}
              {s.ownerId ? ` · ${match.empires.find((e) => e.id === s.ownerId)?.name}` : ''}
            </title>
            {s.ownerId > 0 && (
              <circle
                cx={s.x}
                cy={s.y}
                r={17}
                fill={colors.get(s.ownerId)}
                fillOpacity={0.13}
                stroke={colors.get(s.ownerId)}
                strokeOpacity={0.45}
                strokeWidth={0.8}
              />
            )}
            {systemId === s.id && (
              <circle cx={s.x} cy={s.y} r={11} fill="none" stroke="#fff" strokeWidth={1.5} />
            )}
            <circle
              cx={s.x}
              cy={s.y}
              r={s.ownerId ? 4 : s.kind === 'blackhole' ? 3 : 2}
              fill={colors.get(s.ownerId) ?? '#8294a9'}
            />
            <circle cx={s.x} cy={s.y} r={8} fill="transparent" />
            {(s.ownerId > 0 || systemId === s.id || view.w < bounds.w / 2) && (
              <text
                x={s.x + 10}
                y={s.y - 8}
                fontSize={view.w < bounds.w / 2 ? 6 : 12}
                fill={colors.get(s.ownerId) ?? '#bdc9d6'}
              >
                {s.name}
              </text>
            )}
          </g>
        ))}
        {showFleets && (
          <g pointerEvents="none">
            {match.fleets.map((f) => (
              <path
                key={f.id}
                d={`M${f.x + 6} ${f.y + 5}l6 10h-12Z`}
                fill={colors.get(f.empireId) ?? '#ccc'}
                opacity={!empireId || f.empireId === empireId ? 0.9 : 0.15}
              >
                <title>
                  {f.name} · {f.ships} Schiffe
                </title>
              </path>
            ))}
          </g>
        )}
      </svg>
      <div className="admin-map-legend">
        <span>● System</span>
        <span>◯ Kolonie / Besitz</span>
        <span>▲ Flotte</span>
        <span>Ziehen zum Verschieben · System anklicken für Details</span>
      </div>
    </section>
  );
}
