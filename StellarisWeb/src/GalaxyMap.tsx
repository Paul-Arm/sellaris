import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { Crosshair, Layers3, Minus, Plus, Orbit, Scan, Search, X, Hexagon } from 'lucide-react';
import type { Fleet, GameView, StarSystem } from '../shared/game';
import { stellarProfile } from '../shared/stellar';
import {
  blackHoleRadius,
  buildTerritories,
  galaxyFrame,
  isLandmark,
  layoutGalaxyLabels,
  type Territory,
  type LabelPlacement,
} from './galaxy-cartography';

const vertexShader = `varying vec2 vUv; void main(){vUv=uv;gl_Position=vec4(position.xy,0.0,1.0);}`;
const fragmentShader = `
precision highp float;
varying vec2 vUv;
uniform vec2 resolution;
uniform vec2 center;
uniform float zoom;
uniform float time;
uniform float contours;
uniform float systemMode;
uniform vec2 riftPosition;
uniform vec2 singularityPosition;
uniform vec2 wells[5];
uniform sampler2D galaxyDust;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
float fbm(vec2 p){float v=0.,a=.5;for(int i=0;i<4;i++){v+=a*noise(p);p=p*2.04+17.3;a*=.5;}return v;}
float well(vec2 p,vec2 c,float mass){vec2 d=p-c;d.y*=1.23;return mass/sqrt(dot(d,d)+1700.);}
void main(){
 vec2 screen=vec2(vUv.x,1.-vUv.y)*resolution;
 vec2 p=(screen-resolution*.5)/zoom+center;
 vec3 col=vec3(.019,.026,.043);
 float cloud=fbm(p*.003+vec2(time*.001,0.));
 float cloud2=fbm(p*.006-vec2(0.,time*.002));
 col+=vec3(.047,.036,.086)*pow(cloud,2.)*.7;
 col+=vec3(.015,.03,.05)*cloud2;
 float dust=texture2D(galaxyDust,vec2(p.x/1600.,1.-p.y/1050.)).r;
 float inMap=step(0.,p.x)*step(p.x,1600.)*step(0.,p.y)*step(p.y,1050.);
 col+=vec3(.11,.105,.18)*dust*(.55+cloud*.6)*inMap;
 float field=well(p,singularityPosition,130.)+well(p,riftPosition,100.);
 for(int i=0;i<5;i++){field+=well(p,wells[i],60.);}
 float level=field*31.;
 float line=1.-smoothstep(.025,.025+fwidth(level)*1.15,abs(fract(level)-.5));
 col+=vec3(.23,.20,.35)*line*.085*contours*(1.-systemMode);
 vec2 q=p-riftPosition;q=mat2(.86,-.51,.51,.86)*q;
 float taper=exp(-q.x*q.x/9500.);
 float bend=sin(q.x*.032+time*.28)*12.*taper+(fbm(vec2(q.x*.023,time*.18))-.5)*24.*taper;
 float y=q.y-bend;
 float plasma=exp(-abs(y)/(1.5+11.*taper))*taper;
 float filament=exp(-abs(y-sin(q.x*.08-time)*13.*taper)/1.4)*taper;
 float halo=exp(-q.x*q.x/26000.-q.y*q.y/5200.);
 vec3 fire=vec3(1.,.33,.07)*halo*.62+vec3(1.,.6,.2)*plasma*1.8+vec3(1.,.85,.58)*filament*.65;
 col+=fire*(1.-systemMode);
 vec2 b=p-singularityPosition;vec2 disk=mat2(.971,-.238,.238,.971)*b;float r=length(disk*vec2(1.,2.3));
 col+=vec3(.22,.10,.5)*exp(-dot(b,b)/10000.)*(1.-systemMode);
 col+=vec3(.48,.32,.83)*exp(-abs(r-37.)/3.5)*(1.-systemMode);
 float vignette=1.-.28*length(vUv-.5);
 gl_FragColor=vec4(col*vignette,1.);
}`;

interface Props {
  game: GameView;
  selected: string;
  fleetId: string | null;
  onSelect: (id: string) => void;
  onFleet: (id: string) => void;
  onMove: (id: string) => void;
  mode: 'galaxy' | 'system';
  setMode: (mode: 'galaxy' | 'system') => void;
  moving: boolean;
  focus: number;
}
const initialCamera = { x: 765, y: 545, zoom: 1 };
export function GalaxyMap(props: Props) {
  const container = useRef<HTMLDivElement>(null);
  const background = useRef<HTMLCanvasElement>(null);
  const foreground = useRef<HTMLCanvasElement>(null);
  const latest = useRef(props);
  latest.current = props;
  const sample = useRef({ game: props.game, at: performance.now() });
  if (sample.current.game !== props.game) sample.current = { game: props.game, at: performance.now() };
  const [size, setSize] = useState({ width: 1000, height: 800 });
  const [camera, setCamera] = useState(initialCamera);
  const cameraRef = useRef(camera);
  cameraRef.current = camera;
  const [contours, setContours] = useState(true);
  const contourRef = useRef(contours);
  contourRef.current = contours;
  const [hover, setHover] = useState<string | null>(null);
  const hoverRef = useRef(hover);
  hoverRef.current = hover;
  const [borders, setBorders] = useState(true);
  const borderRef = useRef(borders);
  borderRef.current = borders;
  const geometryKey = props.game.systems.map((s) => [s.id, s.x, s.y].join(':')).join('|');
  const [search, setSearch] = useState('');
  const [webgl, setWebgl] = useState(true);
  const drag = useRef<{ x: number; y: number; cx: number; cy: number; moved: boolean } | null>(null);
  const sized = useRef(false);
  useEffect(() => {
    const observer = new ResizeObserver(([entry]) => {
      const { width, height } = entry.contentRect;
      setSize({ width, height });
      if (!sized.current && width > 100) {
        sized.current = true;
        setCamera(galaxyFrame(latest.current.game.systems, width, height));
      }
    });
    observer.observe(container.current!);
    return () => observer.disconnect();
  }, []);
  useEffect(() => {
    setCamera(
      props.mode === 'system' ? initialCamera : galaxyFrame(props.game.systems, size.width, size.height),
    );
  }, [props.mode, props.game.code]);
  useEffect(() => {
    if (!props.focus) return;
    if (props.mode === 'system') {
      setCamera(initialCamera);
      return;
    }
    const selected = props.game.systems.find((s) => s.id === props.selected)!;
    setCamera((c) => ({ ...c, x: selected.x, y: selected.y }));
  }, [props.focus]);
  useEffect(() => {
    const el = container.current!;
    const wheel = (e: WheelEvent) => {
      e.preventDefault();
      const rect = el.getBoundingClientRect();
      const dx = e.clientX - rect.left - rect.width / 2,
        dy = e.clientY - rect.top - rect.height / 2;
      setCamera((c) => {
        const z = Math.min(3.8, Math.max(0.25, c.zoom * Math.exp(-e.deltaY * 0.001)));
        return { x: c.x + dx / c.zoom - dx / z, y: c.y + dy / c.zoom - dy / z, zoom: z };
      });
    };
    el.addEventListener('wheel', wheel, { passive: false });
    return () => el.removeEventListener('wheel', wheel);
  }, []);
  useEffect(() => {
    const canvas = background.current!;
    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'low-power' });
    } catch {
      setWebgl(false);
      return;
    }
    const scene = new THREE.Scene();
    const cam = new THREE.Camera();
    const systems = latest.current.game.systems;
    const rift = systems.find((s) => s.kind === 'rift');
    const erebus = systems.find((s) => s.id === 'void');
    const dust = createGalaxyDust(systems);
    const uniforms = {
      resolution: { value: new THREE.Vector2(size.width, size.height) },
      center: { value: new THREE.Vector2() },
      zoom: { value: 1 },
      time: { value: 0 },
      contours: { value: 1 },
      systemMode: { value: 0 },
      riftPosition: { value: new THREE.Vector2(rift?.x ?? -10000, rift?.y ?? -10000) },
      singularityPosition: { value: new THREE.Vector2(erebus?.x ?? -10000, erebus?.y ?? -10000) },
      wells: {
        value: Array.from({ length: 5 }, (_, i) => {
          const s = systems[Math.floor((i * systems.length) / 5)];
          return new THREE.Vector2(s.x, s.y);
        }),
      },
      galaxyDust: { value: dust },
    };
    const geometry = new THREE.PlaneGeometry(2, 2);
    const material = new THREE.ShaderMaterial({ vertexShader, fragmentShader, uniforms });
    scene.add(new THREE.Mesh(geometry, material));
    renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
    renderer.setSize(size.width, size.height, false);
    let frame = 0;
    let last = 0;
    const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
    function render(now: number) {
      frame = requestAnimationFrame(render);
      if (document.hidden || now - last < 33) return;
      last = now;
      const c = cameraRef.current;
      uniforms.center.value.set(c.x, c.y);
      uniforms.zoom.value = c.zoom;
      uniforms.time.value = reduced ? 0 : now / 1000;
      uniforms.contours.value = contourRef.current ? 1 : 0;
      uniforms.systemMode.value = latest.current.mode === 'system' ? 1 : 0;
      renderer.render(scene, cam);
    }
    frame = requestAnimationFrame(render);
    return () => {
      cancelAnimationFrame(frame);
      geometry.dispose();
      material.dispose();
      renderer.dispose();
      dust.dispose();
    };
  }, [size.width, size.height, geometryKey]);
  useEffect(() => {
    const canvas = foreground.current!;
    const ctx = canvas.getContext('2d')!;
    const dpr = Math.min(devicePixelRatio, 2);
    canvas.width = size.width * dpr;
    canvas.height = size.height * dpr;
    const starfield = Array.from({ length: 600 }, (_, i) => ({
      x: random(i * 7) * 2400 - 400,
      y: random(i * 7 + 1) * 1700 - 300,
      r: random(i * 7 + 2) * 1.1 + 0.2,
      a: random(i * 7 + 3) * 0.6 + 0.1,
    }));
    let frame = 0;
    let last = 0;
    let territoryKey = '',
      territories: Territory[] = [];
    let labelKey = '',
      labels: LabelPlacement[] = [];
    function render(now: number) {
      frame = requestAnimationFrame(render);
      if (document.hidden || now - last < 33) return;
      last = now;
      const { game, selected, fleetId, mode } = latest.current;
      const systemIndex = new Map(game.systems.map((s) => [s.id, s]));
      const playerIndex = new Map(game.players.map((p) => [p.id, p]));
      const dense = game.systems.length > 100;
      const c = cameraRef.current;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, size.width, size.height);
      ctx.save();
      ctx.translate(size.width / 2, size.height / 2);
      ctx.scale(c.zoom, c.zoom);
      ctx.translate(-c.x, -c.y);
      for (const star of starfield) {
        ctx.fillStyle = `rgba(191,202,232,${star.a})`;
        ctx.beginPath();
        ctx.arc(star.x, star.y, star.r / c.zoom, 0, Math.PI * 2);
        ctx.fill();
      }
      if (mode === 'system') {
        ctx.restore();
        drawSystem(
          ctx,
          game.systems.find((s) => s.id === selected)!,
          size,
          now,
          c,
        );
        return;
      }
      if (!webgl) drawFallback(ctx, game.systems, now, contourRef.current);
      const ownership = game.systems.map((s) => [s.id, s.x, s.y, s.owner].join(':')).join('|');
      if (ownership !== territoryKey) {
        territories = buildTerritories(game.systems);
        territoryKey = ownership;
      }
      if (borderRef.current) drawTerritories(ctx, territories, playerIndex, c.zoom);
      const mapRect = canvas.getBoundingClientRect();
      const exclusions = Array.from(
        container.current!.parentElement!.querySelectorAll(
          '.left-panel,.right-panel,.time-control,.fleet-command,.map-toolbar,.system-search,.paused-label',
        ),
      )
        .map((el) => el.getBoundingClientRect())
        .filter((r) => r.width && r.height)
        .map((r) => ({ x: r.left - mapRect.left, y: r.top - mapRect.top, width: r.width, height: r.height }));
      const nextLabelKey = [
        ownership,
        JSON.stringify(exclusions),
        c.x,
        c.y,
        c.zoom,
        selected,
        hoverRef.current,
        game.me.surveyed.length,
      ].join('/');
      if (labelKey !== nextLabelKey) {
        ctx.font = '11px "Segoe UI",sans-serif';
        labels = layoutGalaxyLabels(
          game.systems,
          c,
          size,
          selected,
          hoverRef.current,
          game.me.home,
          new Set(game.me.surveyed),
          (name) => ctx.measureText(name).width + 4,
          exclusions,
        );
        labelKey = nextLabelKey;
      }
      for (const [a, b] of game.links) {
        const s = systemIndex.get(a)!,
          t = systemIndex.get(b)!;
        const active = a === selected || b === selected;
        ctx.strokeStyle = active
          ? '#b9aaeb90'
          : c.zoom < 0.65
            ? '#8493b013'
            : c.zoom < 1.2
              ? '#8493b027'
              : '#8493b038';
        ctx.lineWidth = (active ? 1.1 : 0.7) / c.zoom;
        ctx.beginPath();
        ctx.moveTo(s.x, s.y);
        ctx.lineTo(t.x, t.y);
        ctx.stroke();
      }
      for (const s of game.systems) {
        const active = s.id === selected;
        if (
          Math.abs((s.x - c.x) * c.zoom) > size.width / 2 + 60 ||
          Math.abs((s.y - c.y) * c.zoom) > size.height / 2 + 60
        )
          continue;
        const owner = s.owner ? playerIndex.get(s.owner) : undefined;
        if (s.kind === 'star') {
          if (!dense || active || (s.owner && c.zoom > 0.8) || c.zoom > 2.2) {
            const grad = ctx.createRadialGradient(s.x, s.y, 0, s.x, s.y, 27 / c.zoom);
            grad.addColorStop(0, s.color + '80');
            grad.addColorStop(0.14, s.color + '35');
            grad.addColorStop(1, s.color + '00');
            ctx.fillStyle = grad;
            ctx.fillRect(s.x - 27 / c.zoom, s.y - 27 / c.zoom, 54 / c.zoom, 54 / c.zoom);
          }
          ctx.shadowColor = s.color;
          ctx.shadowBlur = dense && !active ? 0 : 12;
          ctx.fillStyle = s.color;
          ctx.beginPath();
          ctx.arc(
            s.x,
            s.y,
            (s.owner ? (c.zoom < 0.75 ? 2 : 3.5) : dense ? (c.zoom < 0.65 ? 1.1 : 1.7) : 2.7) / c.zoom,
            0,
            Math.PI * 2,
          );
          ctx.fill();
          ctx.shadowBlur = 0;
          if (s.owner) {
            ctx.strokeStyle = owner?.color || '#ab9dfb';
            ctx.lineWidth = 1 / c.zoom;
            ctx.beginPath();
            ctx.arc(s.x, s.y, (c.zoom < 0.7 ? 4.5 : c.zoom < 1.2 ? 7 : 11) / c.zoom, 0, Math.PI * 2);
            ctx.stroke();
          }
          if (active) {
            ctx.strokeStyle = '#c5bfff';
            ctx.lineWidth = 1 / c.zoom;
            ctx.beginPath();
            ctx.arc(s.x, s.y, 21 / c.zoom, 0, Math.PI * 2);
            ctx.stroke();
            for (let i = 0; i < 4; i++) {
              const a = (i * Math.PI) / 2;
              ctx.beginPath();
              ctx.moveTo(s.x + (Math.cos(a) * 25) / c.zoom, s.y + (Math.sin(a) * 25) / c.zoom);
              ctx.lineTo(s.x + (Math.cos(a) * 29) / c.zoom, s.y + (Math.sin(a) * 29) / c.zoom);
              ctx.stroke();
            }
          }
        } else if (s.kind === 'blackhole') {
          drawBlackHole(ctx, s, c.zoom, active);
        }
        if (s.anomaly && s.kind === 'star' && !s.studied && (!dense || c.zoom > 1.05 || active)) {
          ctx.strokeStyle = '#d6b072';
          ctx.lineWidth = 1 / c.zoom;
          ctx.strokeRect(s.x + 11 / c.zoom, s.y - 13 / c.zoom, 5 / c.zoom, 5 / c.zoom);
        }
        if (s.defense > 0 && !s.owner && (!dense || c.zoom > 1.05 || active)) {
          ctx.fillStyle = '#e18782';
          ctx.font = `${10 / c.zoom}px sans-serif`;
          ctx.fillText('⌁', s.x - 13 / c.zoom, s.y - 10 / c.zoom);
        }
      }
      ctx.save();
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.textAlign = 'center';
      ctx.textBaseline = 'top';
      for (const label of labels) {
        const s = label.system,
          active = s.id === selected || s.id === hoverRef.current;
        ctx.font = (active ? '600 ' : '400 ') + '11px "Segoe UI",sans-serif';
        ctx.shadowColor = '#050811';
        ctx.shadowBlur = 5;
        ctx.fillStyle = active
          ? '#f3eeff'
          : s.owner
            ? playerIndex.get(s.owner)?.color || '#bdafe8'
            : isLandmark(s)
              ? '#d5bfdc'
              : '#a0abc1';
        ctx.fillText(s.name, label.x, label.y);
        if (label.detail) {
          ctx.font = '7px "Segoe UI",sans-serif';
          ctx.fillStyle = '#929bb1';
          ctx.fillText(
            s.id === game.me.home
              ? 'HAUPTSTADT'
              : s.kind === 'rift'
                ? 'INSTABILE RAUMZEIT'
                : s.id === 'void'
                  ? 'SINGULARITÄT'
                  : 'KOLONIE',
            label.x,
            label.y + 15,
          );
        }
      }
      ctx.restore();
      const stationaryCounts = new Map<string, number>();
      for (const f of game.fleets) {
        const offset = stationaryCounts.get(f.systemId) || 0;
        if (!f.route.length) stationaryCounts.set(f.systemId, offset + 1);
        const elapsed = game.paused ? 0 : Math.max(0, (now - sample.current.at) / 1000) * game.speed;
        drawFleet(ctx, f, offset, systemIndex, playerIndex, c.zoom, f.id === fleetId, elapsed);
      }
      ctx.restore();
    }
    frame = requestAnimationFrame(render);
    return () => cancelAnimationFrame(frame);
  }, [size, webgl]);
  function screen(s: StarSystem) {
    return {
      left: (s.x - camera.x) * camera.zoom + size.width / 2,
      top: (s.y - camera.y) * camera.zoom + size.height / 2,
    };
  }
  const hovered = props.game.systems.find((s) => s.id === hover);
  const query = search.trim().toLocaleLowerCase('de').replaceAll('-', ' ');
  const results = query
    ? props.game.systems
        .filter((s) =>
          `${s.name} ${s.class} ${stellarProfile(s).label}`
            .toLocaleLowerCase('de')
            .replaceAll('-', ' ')
            .includes(query),
        )
        .slice(0, 8)
    : [];
  function locate(s: StarSystem) {
    props.onSelect(s.id);
    setCamera((c) => ({ ...c, x: s.x, y: s.y, zoom: Math.max(1, c.zoom) }));
    setSearch('');
  }
  return (
    <div
      ref={container}
      className={`galaxy-map ${props.moving ? 'move-mode' : ''}`}
      aria-label="Interaktive Sternenkarte"
      onPointerDown={(e) => {
        if (e.button !== 0 || (e.target as HTMLElement).closest('button')) return;
        drag.current = { x: e.clientX, y: e.clientY, cx: camera.x, cy: camera.y, moved: false };
        e.currentTarget.setPointerCapture(e.pointerId);
      }}
      onPointerMove={(e) => {
        const d = drag.current;
        if (!d) return;
        d.moved = true;
        setCamera((c) => ({
          ...c,
          x: Math.max(-100, Math.min(1750, d.cx - (e.clientX - d.x) / c.zoom)),
          y: Math.max(-100, Math.min(1200, d.cy - (e.clientY - d.y) / c.zoom)),
        }));
      }}
      onPointerUp={() => {
        drag.current = null;
      }}
      onPointerCancel={() => {
        drag.current = null;
      }}
    >
      <canvas ref={background} className="space-canvas" aria-hidden="true" />
      <canvas ref={foreground} className="space-canvas" aria-hidden="true" />
      {props.mode === 'galaxy' && (
        <div className="system-search" onPointerDown={(e) => e.stopPropagation()}>
          <label>
            <Search size={14} />
            <input
              aria-label="Sternsystem suchen"
              placeholder="System oder Sternklasse suchen …"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Escape') {
                  setSearch('');
                  e.currentTarget.blur();
                }
                if (e.key === 'Enter' && results[0]) {
                  locate(results[0]);
                  e.currentTarget.blur();
                }
              }}
            />
          </label>
          {search && (
            <button aria-label="Systemsuche leeren" onClick={() => setSearch('')}>
              <X size={13} />
            </button>
          )}
          {search.trim() && (
            <div className="system-results" aria-label="Gefundene Systeme">
              {results.length ? (
                results.map((s) => (
                  <button key={s.id} onClick={() => locate(s)}>
                    <strong>{s.name}</strong>
                    <span>
                      {s.owner === props.game.me.id
                        ? 'Eigene Kolonie'
                        : props.game.me.surveyed.includes(s.id)
                          ? 'Untersucht'
                          : 'Unerforscht'}{' '}
                      · {s.class}
                    </span>
                  </button>
                ))
              ) : (
                <p>Kein System gefunden.</p>
              )}
            </div>
          )}
        </div>
      )}
      {props.mode === 'galaxy' &&
        props.game.systems
          .filter(
            (s) =>
              Math.abs((s.x - camera.x) * camera.zoom) < size.width / 2 + 30 &&
              Math.abs((s.y - camera.y) * camera.zoom) < size.height / 2 + 30,
          )
          .map((s) => (
            <button
              key={s.id}
              className={`star-hit ${isLandmark(s) ? 'anomaly-hit' : ''}`}
              style={{
                ...screen(s),
                ...(!isLandmark(s) && props.game.systems.length > 100 ? { width: 18, height: 18 } : {}),
              }}
              aria-label={`System ${s.name}`}
              title={s.name}
              onMouseEnter={() => setHover(s.id)}
              onMouseLeave={() => setHover(null)}
              onClick={() => props.onSelect(s.id)}
              onDoubleClick={() => {
                props.onSelect(s.id);
                props.setMode('system');
              }}
              onContextMenu={(e) => {
                e.preventDefault();
                props.onMove(s.id);
              }}
            />
          ))}
      {hovered && props.mode === 'galaxy' && (
        <div
          className="star-tooltip"
          style={{
            left: Math.min(size.width - 190, Math.max(10, screen(hovered).left + 25)),
            top: Math.max(30, screen(hovered).top - 65),
          }}
        >
          <strong>{hovered.name}</strong>
          <span>
            {hovered.class} · {props.game.me.surveyed.includes(hovered.id) ? 'Untersucht' : 'Unbekannt'}
          </span>
        </div>
      )}
      <div className="map-scale">
        <span className="scale-line" />
        {Math.round(100 / camera.zoom)} LY <span>Raumzeitprojektion</span>
      </div>
      <div className="map-toolbar">
        <button
          className={`icon-button ${borders ? 'on' : ''}`}
          onClick={() => setBorders(!borders)}
          aria-pressed={borders}
          aria-label="Reichsgrenzen umschalten"
          title="Reichsgrenzen umschalten"
        >
          <Hexagon size={15} />
        </button>
        <button className={props.mode === 'galaxy' ? 'active' : ''} onClick={() => props.setMode('galaxy')}>
          <Layers3 size={15} />
          Galaxie
        </button>
        <button className={props.mode === 'system' ? 'active' : ''} onClick={() => props.setMode('system')}>
          <Orbit size={16} />
          System
        </button>
        <span className="toolbar-divider" />
        <button
          className={`icon-button ${contours ? 'on' : ''}`}
          onClick={() => setContours(!contours)}
          title="Gravitationslinien umschalten"
          aria-label="Gravitationslinien umschalten"
        >
          <Scan size={16} />
        </button>
        <button
          className="icon-button"
          onClick={() =>
            setCamera(
              props.mode === 'system'
                ? initialCamera
                : galaxyFrame(props.game.systems, size.width, size.height),
            )
          }
          title="Karte zentrieren"
          aria-label="Karte zentrieren"
        >
          <Crosshair size={16} />
        </button>
        <span className="toolbar-divider" />
        <button
          className="icon-button"
          onClick={() => setCamera((c) => ({ ...c, zoom: Math.max(0.25, c.zoom / 1.2) }))}
          aria-label="Herauszoomen"
        >
          <Minus size={15} />
        </button>
        <span className="zoom-label">{Math.round(camera.zoom * 100)}%</span>
        <button
          className="icon-button"
          onClick={() => setCamera((c) => ({ ...c, zoom: Math.min(3.8, c.zoom * 1.2) }))}
          aria-label="Hineinzoomen"
        >
          <Plus size={15} />
        </button>
      </div>
    </div>
  );
}
function random(i: number) {
  const n = Math.sin(i * 127.1 + 311.7) * 43758.5453;
  return n - Math.floor(n);
}
function createGalaxyDust(systems: StarSystem[]) {
  const canvas = document.createElement('canvas');
  canvas.width = 800;
  canvas.height = 525;
  const ctx = canvas.getContext('2d')!;
  ctx.fillStyle = '#000';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.globalCompositeOperation = 'lighter';
  for (const s of systems) {
    const x = s.x / 2,
      y = s.y / 2,
      radius = systems.length > 100 ? 23 : 38;
    const glow = ctx.createRadialGradient(x, y, 0, x, y, radius);
    glow.addColorStop(0, '#ffffff10');
    glow.addColorStop(0.35, '#ffffff06');
    glow.addColorStop(1, '#ffffff00');
    ctx.fillStyle = glow;
    ctx.fillRect(x - radius, y - radius, radius * 2, radius * 2);
  }
  return new THREE.CanvasTexture(canvas);
}

function drawTerritories(
  ctx: CanvasRenderingContext2D,
  territories: Territory[],
  players: Map<string, GameView['players'][number]>,
  zoom: number,
) {
  for (const territory of territories) {
    const color = players.get(territory.owner)?.color || '#b4a5ed';
    ctx.fillStyle = color + '12';
    ctx.beginPath();
    for (const cell of territory.cells) {
      cell.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
      ctx.closePath();
    }
    ctx.fill();
    ctx.beginPath();
    for (const [a, b] of territory.edges) {
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(b.x, b.y);
    }
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = color + '15';
    ctx.lineWidth = 7 / zoom;
    ctx.stroke();
    ctx.strokeStyle = color + '35';
    ctx.lineWidth = 3 / zoom;
    ctx.stroke();
    ctx.strokeStyle = color + 'b0';
    ctx.lineWidth = 0.9 / zoom;
    ctx.stroke();
  }
}

function drawBlackHole(ctx: CanvasRenderingContext2D, s: StarSystem, zoom: number, active: boolean) {
  const landmark = s.id === 'void',
    radius = blackHoleRadius(s, zoom);
  ctx.save();
  ctx.translate(s.x, s.y);
  ctx.scale(1 / zoom, 1 / zoom);
  ctx.rotate(-0.24);
  const color = landmark ? '#b498ff' : s.class === 'Quasar' ? '#a6dafa' : '#b5a5e5';
  const halo = ctx.createRadialGradient(0, 0, 0, 0, 0, radius * 2);
  halo.addColorStop(0, color + '38');
  halo.addColorStop(1, color + '00');
  ctx.fillStyle = halo;
  ctx.fillRect(-radius * 2, -radius * 2, radius * 4, radius * 4);
  // A complete inclined accretion disk and a round horizon replace the oversized half-moon.
  ctx.strokeStyle = color + '65';
  ctx.lineWidth = landmark ? 2 : 1.2;
  ctx.beginPath();
  ctx.ellipse(0, 0, radius, radius * 0.42, 0, 0, Math.PI * 2);
  ctx.stroke();
  ctx.fillStyle = '#05070e';
  ctx.beginPath();
  ctx.ellipse(0, 0, radius * (landmark ? 0.8 : 0.48), radius * 0.36, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.strokeStyle = color;
  ctx.shadowColor = color;
  ctx.shadowBlur = landmark ? 13 : 4;
  ctx.lineWidth = landmark ? 1.8 : 1;
  ctx.beginPath();
  ctx.ellipse(0, 0, radius, radius * 0.42, 0, 0.12, Math.PI + 0.35);
  ctx.stroke();
  if (!landmark) {
    ctx.beginPath();
    ctx.arc(0, 0, radius * 0.48, Math.PI, Math.PI * 2);
    ctx.stroke();
  }
  ctx.shadowBlur = 0;
  if (active) {
    ctx.strokeStyle = '#e7dfff';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.arc(0, 0, radius + 6, 0, Math.PI * 2);
    ctx.stroke();
  }
  ctx.restore();
}

function drawFleet(
  ctx: CanvasRenderingContext2D,
  f: Fleet,
  offset: number,
  systems: Map<string, StarSystem>,
  players: Map<string, GameView['players'][number]>,
  zoom: number,
  selected: boolean,
  elapsed: number,
) {
  const a = systems.get(f.systemId);
  if (!a) return;
  const b = systems.get(f.route[0]);
  let x = a.x + ((offset % 3) * 13 - 13) / zoom,
    y = a.y - 35 / zoom - (Math.floor(offset / 3) * 14) / zoom,
    angle = -Math.PI / 2;
  if (b) {
    const progress = Math.min(1, f.progress + elapsed / Math.max(0.001, f.duration));
    x = a.x + (b.x - a.x) * progress;
    y = a.y + (b.y - a.y) * progress;
    angle = Math.atan2(b.y - a.y, b.x - a.x);
    ctx.strokeStyle = selected ? '#c4b9fb88' : '#ab9cff33';
    ctx.setLineDash([4 / zoom, 6 / zoom]);
    ctx.lineWidth = 1 / zoom;
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    for (const id of f.route) {
      const t = systems.get(id)!;
      ctx.lineTo(t.x, t.y);
    }
    ctx.stroke();
    ctx.setLineDash([]);
  }
  const color = players.get(f.owner)?.color || '#ddd';
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(angle);
  ctx.scale(1 / zoom, 1 / zoom);
  ctx.fillStyle = selected ? '#f0ebff' : color;
  ctx.shadowColor = color;
  ctx.shadowBlur = selected ? 10 : 3;
  ctx.beginPath();
  ctx.moveTo(6, 0);
  ctx.lineTo(-4, -3.5);
  ctx.lineTo(-2, 0);
  ctx.lineTo(-4, 3.5);
  ctx.closePath();
  ctx.fill();
  ctx.shadowBlur = 0;
  if (selected) {
    ctx.strokeStyle = color + '88';
    ctx.lineWidth = 0.7;
    ctx.beginPath();
    ctx.arc(0, 0, 9, 0, Math.PI * 2);
    ctx.stroke();
  }
  if (f.task) {
    ctx.strokeStyle = '#8cd5c7';
    ctx.beginPath();
    ctx.arc(0, 0, 11, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * (1 - f.task.remaining / f.task.total));
    ctx.stroke();
  }
  ctx.restore();
}
function drawFallback(ctx: CanvasRenderingContext2D, systems: StarSystem[], now: number, contours: boolean) {
  if (contours)
    for (const s of systems.filter((s) => s.owner || s.kind !== 'star')) {
      ctx.strokeStyle = '#8d7ca420';
      ctx.lineWidth = 0.8;
      for (let i = 1; i < 28; i++) {
        ctx.beginPath();
        ctx.ellipse(s.x, s.y, 25 + i * i * 0.7, 14 + i * i * 0.36, -0.2, 0, Math.PI * 2);
        ctx.stroke();
      }
    }
  const rift = systems.find((s) => s.kind === 'rift');
  if (!rift) return;
  ctx.save();
  ctx.translate(rift.x, rift.y);
  ctx.rotate(0.5);
  const glow = ctx.createRadialGradient(0, 0, 0, 0, 0, 150);
  glow.addColorStop(0, '#ffb95b80');
  glow.addColorStop(0.3, '#ff7e3033');
  glow.addColorStop(1, '#ff7e3000');
  ctx.fillStyle = glow;
  ctx.fillRect(-150, -150, 300, 300);
  for (let j = 0; j < 5; j++) {
    ctx.strokeStyle = j === 0 ? '#fff7d9' : '#ffd17e66';
    ctx.lineWidth = j === 0 ? 4 : 1.5;
    ctx.shadowBlur = 25;
    ctx.shadowColor = '#ff9d43';
    ctx.beginPath();
    for (let i = -100; i <= 100; i += 3) {
      const y = Math.sin(i * 0.07 + now * 0.0005 + j) * Math.max(0, 1 - Math.abs(i) / 100) * 12;
      i === -100 ? ctx.moveTo(i, y) : ctx.lineTo(i, y);
    }
    ctx.stroke();
  }
  ctx.restore();
}
function drawSystem(
  ctx: CanvasRenderingContext2D,
  s: StarSystem,
  size: { width: number; height: number },
  now: number,
  camera: typeof initialCamera,
) {
  const x = size.width * 0.5 + (initialCamera.x - camera.x) * camera.zoom,
    y = size.height * 0.5 + (initialCamera.y - camera.y) * camera.zoom;
  const scale = Math.min(size.width / 900, size.height / 800) * camera.zoom;
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(scale, scale);
  for (let i = 0; i < 4; i++) {
    ctx.strokeStyle = '#b5b7d51b';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.ellipse(0, 0, 125 + i * 65, (125 + i * 65) * 0.55, -0.25, 0, Math.PI * 2);
    ctx.stroke();
  }
  const glow = ctx.createRadialGradient(0, 0, 10, 0, 0, 125);
  glow.addColorStop(0, s.color + 'aa');
  glow.addColorStop(0.3, s.color + '33');
  glow.addColorStop(1, s.color + '00');
  ctx.fillStyle = glow;
  ctx.fillRect(-125, -125, 250, 250);
  ctx.shadowColor = s.color;
  ctx.shadowBlur = 25;
  ctx.fillStyle = s.color;
  ctx.beginPath();
  ctx.arc(0, 0, s.kind === 'star' ? 29 : 18, 0, Math.PI * 2);
  ctx.fill();
  ctx.shadowBlur = 0;
  if (s.kind === 'star')
    for (let i = 0; i < 4; i++) {
      const a = i * 1.8 + 0.6 + (now * 0.000002) / (i + 1),
        r = 125 + i * 65,
        ox = Math.cos(a) * r,
        oy = Math.sin(a) * r * 0.55,
        px = ox * Math.cos(-0.25) - oy * Math.sin(-0.25),
        py = ox * Math.sin(-0.25) + oy * Math.cos(-0.25);
      const gradient = ctx.createRadialGradient(px - 4, py - 4, 1, px + 3, py + 3, 12 + i);
      gradient.addColorStop(0, ['#b8a491', '#679b9e', '#be8267', '#92a1b1'][i]);
      gradient.addColorStop(1, '#111723');
      ctx.fillStyle = gradient;
      ctx.beginPath();
      ctx.arc(px, py, 8 + i * 2, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#929cb3';
      ctx.font = '11px "Segoe UI",sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(`${s.name} ${['I', 'II', 'III', 'IV'][i]}`, px, py + 29);
    }
  ctx.fillStyle = '#e8e2d8';
  ctx.font = '16px "Segoe UI",sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText(s.name, 0, 65);
  ctx.fillStyle = '#646f89';
  ctx.font = '10px "Segoe UI",sans-serif';
  ctx.fillText(s.class, 0, 85);
  ctx.restore();
}
