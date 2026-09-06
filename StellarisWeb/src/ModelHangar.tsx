import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { createModelEnvironment } from './model-materials';
import { ArrowLeft, Pause, Play, RotateCcw } from 'lucide-react';
import { MODEL_ASSETS, ModelInstance, ModelLibrary, type ModelAsset } from './model-assets';
import { SHIP_SETS, SHIP_SET_IDS, type ShipSet } from '../shared/shipSets';
import './model-hangar.css';

const MODEL_ORDER = [
  '01_korvette',
  '02_fregatte',
  '03_zerstoerer',
  '04_kreuzer',
  '05_schlachtschiff',
  '06_titan',
  '07_arbeiter',
  '08_forschung',
  '01_aussenposten',
  '02_sternenbasis',
  '03_festung',
  '04_zitadelle',
  '05_abwehrplattform',
  '06_artillerieplattform',
  '01_mining_station',
  '02_mining_ring',
  '03_dyson_swarm',
  '04_mega_shipyard',
  '05_construction_level_0',
  'orbital_ring',
];

export function modelLabel(id: string) {
  const labels: Record<string, string> = {
    orbital_ring: 'Orbitalring',
    '01_mining_station': 'Bergbaustation',
    '02_mining_ring': 'Bergbauring',
    '03_dyson_swarm': 'Dyson-Schwarm',
    '04_mega_shipyard': 'Mega-Werft',
    '05_construction_level_0': 'Baustelle · Stufe 0',
    '01_aussenposten': 'Außenposten',
    '03_zerstoerer': 'Zerstörer',
    '08_forschung': 'Forschungsschiff',
  };
  return (
    labels[id] ??
    id
      .replace(/^\d+_/, '')
      .replaceAll('_', ' ')
      .replace(/^./, (c) => c.toUpperCase())
  );
}

function Preview({ asset }: { asset: ModelAsset }) {
  const parent = useRef<HTMLDivElement>(null);
  const [status, setStatus] = useState('Modell wird geladen …');
  const [playing, setPlaying] = useState(true);
  const [speed, setSpeed] = useState(1);
  const [clip, setClip] = useState(
    asset.clips.find((c) => /idle|loop/i.test(c.name))?.name ?? asset.clips[0]?.name ?? '',
  );
  const settings = useRef({ playing, speed, clip });
  settings.current = { playing, speed, clip };
  const reset = useRef(() => {});
  useEffect(() => {
    const host = parent.current!;
    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
    } catch {
      setStatus('WebGL ist in diesem Browser nicht verfügbar.');
      return;
    }
    renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
    renderer.setClearColor('#080f19');
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1;
    renderer.domElement.setAttribute(
      'aria-label',
      `3D-Vorschau ${asset.set.toUpperCase()} ${modelLabel(asset.id)}`,
    );
    renderer.domElement.dataset.model = `${asset.set}/${asset.id}`;
    host.appendChild(renderer.domElement);
    const scene = new THREE.Scene();
    scene.background = new THREE.Color('#080f19');
    const environment = createModelEnvironment(renderer);
    scene.environment = environment.texture;
    scene.environmentIntensity = 0.4;
    const camera = new THREE.PerspectiveCamera(38, 1, 0.1, 2000);
    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.minDistance = 15;
    controls.maxDistance = 450;
    reset.current = () => {
      camera.position.set(78, 63, 100);
      controls.target.set(0, 0, 0);
      controls.update();
    };
    reset.current();
    scene.add(new THREE.HemisphereLight('#c4dfff', '#162137', 0.35));
    const key = new THREE.DirectionalLight('#fff1df', 2.8);
    key.position.set(50, 70, 90);
    scene.add(key);
    const fill = new THREE.DirectionalLight('#6eb4ff', 1.3);
    fill.position.set(-60, 20, -40);
    scene.add(fill);
    const target = new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, samples: 4 });
    const composer = new EffectComposer(renderer, target);
    const bloomPass = new UnrealBloomPass(new THREE.Vector2(1, 1), 0.28, 0.2, 1.35);
    const renderPass = new RenderPass(scene, camera);
    const outputPass = new OutputPass();
    composer.addPass(renderPass);
    composer.addPass(bloomPass);
    composer.addPass(outputPass);
    const resize = () => {
      renderer.setSize(host.clientWidth, host.clientHeight);
      composer.setSize(host.clientWidth, host.clientHeight);
      camera.aspect = host.clientWidth / Math.max(1, host.clientHeight);
      camera.updateProjectionMatrix();
    };
    const observer = new ResizeObserver(resize);
    observer.observe(host);
    resize();
    const library = new ModelLibrary();
    let instance: ModelInstance | undefined;
    let planet: THREE.Mesh<THREE.SphereGeometry, THREE.MeshStandardMaterial> | undefined;
    let disposed = false;
    void library
      .load(asset)
      .then((gltf) => {
        if (disposed) return;
        instance = new ModelInstance(gltf, 100);
        instance.play(settings.current.clip);
        scene.add(instance.group);
        if (asset.planetRadius) {
          planet = new THREE.Mesh(
            new THREE.SphereGeometry((asset.planetRadius * 100) / Math.max(...asset.size), 48, 32),
            new THREE.MeshStandardMaterial({ color: '#31586b', roughness: 0.9 }),
          );
          scene.add(planet);
        }
        renderer.domElement.dataset.ready = 'true';
        setStatus('');
      })
      .catch(() => {
        if (!disposed) setStatus('Das Modell konnte nicht geladen werden. Bitte die Seite neu laden.');
      });
    let frame = 0,
      previous = performance.now(),
      seconds = 0,
      currentClip = '';
    const animate = (now: number) => {
      frame = requestAnimationFrame(animate);
      const delta = Math.min(0.1, (now - previous) / 1000);
      previous = now;
      if (document.hidden) return;
      if (settings.current.clip !== currentClip) {
        currentClip = settings.current.clip;
        seconds = 0;
        instance?.play(currentClip);
      }
      if (settings.current.playing) seconds += delta * settings.current.speed;
      instance?.update(seconds);
      library.setTime(seconds);
      controls.update();
      composer.render();
    };
    frame = requestAnimationFrame(animate);
    return () => {
      disposed = true;
      cancelAnimationFrame(frame);
      observer.disconnect();
      controls.dispose();
      instance?.dispose();
      library.dispose();
      environment.dispose();
      renderPass.dispose();
      bloomPass.dispose();
      outputPass.dispose();
      composer.dispose();
      planet?.geometry.dispose();
      planet?.material.dispose();
      renderer.dispose();
      renderer.domElement.remove();
    };
  }, [asset]);
  return (
    <>
      <div className="hangar-preview">
        <div className="hangar-canvas" ref={parent} />
        {status && <p role="status">{status}</p>}
      </div>
      <div className="hangar-controls">
        <button
          onClick={() => setPlaying((v) => !v)}
          aria-label={playing ? 'Animation pausieren' : 'Animation abspielen'}
        >
          {playing ? <Pause size={16} /> : <Play size={16} />}
        </button>
        <label>
          Animation
          <select value={clip} onChange={(e) => setClip(e.target.value)} disabled={!asset.clips.length}>
            {asset.clips.length ? (
              asset.clips.map((c) => (
                <option key={c.name} value={c.name}>
                  {c.name} · {c.duration.toFixed(1)} s
                </option>
              ))
            ) : (
              <option value="">Statisches Modell</option>
            )}
          </select>
        </label>
        <label>
          Tempo
          <select value={speed} onChange={(e) => setSpeed(Number(e.target.value))}>
            {[0.25, 1, 4, 12].map((v) => (
              <option value={v} key={v}>
                {v}×
              </option>
            ))}
          </select>
        </label>
        <button onClick={() => reset.current()} aria-label="Kamera zurücksetzen">
          <RotateCcw size={16} />
        </button>
      </div>
    </>
  );
}

export function ModelHangar() {
  const [set, setSet] = useState<ShipSet>('prisma');
  const [id, setId] = useState('01_korvette');
  const assets = MODEL_ASSETS.filter((a) => a.set === set).sort(
    (a, b) => MODEL_ORDER.indexOf(a.id) - MODEL_ORDER.indexOf(b.id),
  );
  const asset = assets.find((a) => a.id === id) ?? assets[0];
  return (
    <main className="model-hangar">
      <header>
        <a href="/">
          <ArrowLeft size={16} /> Zum Spiel
        </a>
        <span className="eyebrow">SINGULARITY / DESIGNARCHIV</span>
        <h1>Designhangar</h1>
        <p>{MODEL_ASSETS.length} Modelle · Sechs Architekturen · Animationsvorschau</p>
      </header>
      <nav aria-label="Designset">
        {SHIP_SET_IDS.map((s) => (
          <button key={s} aria-pressed={s === set} onClick={() => setSet(s)}>
            {SHIP_SETS[s].name}
          </button>
        ))}
      </nav>
      <section className="hangar-workbench">
        <aside>
          <h2>{SHIP_SETS[set].name}</h2>
          <p>{SHIP_SETS[set].description}</p>
          <label className="hangar-mobile-label">
            Modell
            <select value={asset?.id} onChange={(e) => setId(e.target.value)}>
              {assets.map((a) => (
                <option key={a.id} value={a.id}>
                  {modelLabel(a.id)}
                </option>
              ))}
            </select>
          </label>
          <div className="hangar-models">
            {assets.map((a) => (
              <button key={a.id} aria-pressed={a.id === asset?.id} onClick={() => setId(a.id)}>
                {modelLabel(a.id)}
                <span>
                  {a.clips.length
                    ? `${a.clips.length} ${a.clips.length === 1 ? 'Clip' : 'Clips'}`
                    : 'Statisch'}
                </span>
              </button>
            ))}
          </div>
        </aside>
        <section className="hangar-stage" aria-label="Modellvorschau">
          {asset && (
            <>
              <div className="hangar-caption">
                <h2>{modelLabel(asset.id)}</h2>
                <span>{(asset.bytes / 1024).toFixed(0)} KB · GLB</span>
              </div>
              <Preview key={`${set}/${asset.id}`} asset={asset} />
              <p className="hangar-hint">
                Ziehen zum Drehen · Mausrad zum Zoomen · Rechte Maustaste zum Verschieben
              </p>
            </>
          )}
        </section>
      </section>
    </main>
  );
}
