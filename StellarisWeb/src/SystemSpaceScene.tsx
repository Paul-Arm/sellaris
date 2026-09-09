import { colonyBuildingLevel } from '../shared/colonies';
import { gameIndices } from './game-indices';
import { RenderProfiler } from './render-profiler';
import { instanceMatrix, instanceColor, flushInstances, takeInstanceUploadBytes } from './instance-buffers';
import { travelProgress } from '../shared/time';
import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { SMAAPass } from 'three/examples/jsm/postprocessing/SMAAPass.js';
import type { GameView, StarSystem } from '../shared/game';
import { systemHasAsteroidBelt, stableHash, type CelestialBody } from '../shared/celestial';
import { gravitySlots } from '../shared/systemObjects';
import { bodyPosition, fleetAnchor, localPosition, localVelocity, type Point3 } from '../shared/navigation';
import { createBody, lineLoop, shipGeometry, type Disposable } from './system-objects';
import { createAsteroidBelt } from './asteroid-belts';
import { fieldVertex, fieldFragment } from './system-shaders';
import { CanvasHud } from './canvas-hud';
import { HyperlaneLabel } from './hyperlane-label';
import {
  nearbyTarget,
  targetsInBox,
  type ScreenTarget,
  type SpaceTarget,
  type SelectionMode,
} from './space-selection';
import { BlackHolePass } from './BlackHolePass';
import {
  PORTAL_BEND_INNER,
  PORTAL_BEND_OUTER,
  PORTAL_DEPTH,
  PORTAL_DISTANCE,
  PORTAL_LIFT,
  PORTAL_MIN_SEPARATION,
  PORTAL_RADIUS,
  PORTAL_WIDTH,
  bodyGravityWell,
  foldSurfacePoint,
  portalFoldDistance,
  surfaceHeight,
} from './spacetime-surface';
import { createWormhole } from './wormhole-objects';
import { InstancedModel, ModelLibrary, ModelSlot, modelAsset } from './model-assets';
import { createModelEnvironment } from './model-materials';
import { SHIP_MODEL, STATION_MODELS, facilityModel, playerShipSet } from './system-models';

export type SystemTarget =
  { kind: 'body'; slot: number } | { kind: 'fleet'; id: string } | { kind: 'exit'; id: string };
interface Props {
  placement?: Point3;
  previewPoint?: Point3;
  onPoint?: (point: Point3, append: boolean) => void;
  onMove: (point: Point3, append: boolean) => void;
  onContext: (target: SystemTarget, x: number, y: number) => void;
  bodies: CelestialBody[];
  game: GameView;
  system: StarSystem;
  selection: SpaceTarget[];
  onSelection: (targets: SpaceTarget[], mode?: SelectionMode) => void;
  onNavigate: (id: string) => void;
  onZoom: (zoom: number) => void;
  zoomStep: number;
  reset: number;
  focusSelection: number;
  bloom: boolean;
  contours: boolean;
}

/** Orbital visuals use strategic rows. Only the separate battle view subscribes to combat positions. */
export function SystemScene(props: Props) {
  const parent = useRef<HTMLDivElement>(null),
    latest = useRef(props);
  const sample = useRef({ at: performance.now(), tick: props.game.tick });
  latest.current = props;
  if (sample.current.tick !== props.game.tick)
    sample.current = { at: performance.now(), tick: props.game.tick };
  const [fallback, setFallback] = useState(false);
  useEffect(() => {
    const root = parent.current!,
      initial = latest.current,
      bodies = initial.bodies;
    const gravity = gravitySlots(bodies);
    let renderer: THREE.WebGLRenderer;
    try {
      // AA belongs to the composer's HDR target; default-framebuffer MSAA cannot smooth it.
      renderer = new THREE.WebGLRenderer({ antialias: false, powerPreference: 'high-performance' });
    } catch {
      setFallback(true);
      return;
    }
    setFallback(false);
    renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
    renderer.setClearColor('#080b12');
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1;
    renderer.domElement.setAttribute(
      'aria-label',
      'Dreidimensionale Raumzeitkarte. Links ziehen: Auswahl. Rechts ziehen: drehen. Mitteltaste: verschieben. Mausrad: zoomen.',
    );
    renderer.domElement.tabIndex = 0;
    root.prepend(renderer.domElement);
    const resources: Disposable[] = [];
    const modelLibrary = new ModelLibrary();
    const profiler = new RenderProfiler(renderer);
    resources.push(profiler);
    resources.push(modelLibrary);
    const scene = new THREE.Scene(),
      camera = new THREE.PerspectiveCamera(44, 1, 1, 7000);
    scene.background = new THREE.Color(0.003, 0.004, 0.007);
    const environment = createModelEnvironment(renderer);
    scene.environment = environment.texture;
    scene.environmentIntensity = 0.32;
    resources.push(environment);
    const hud = new CanvasHud(root, scene, camera);
    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.085;
    controls.rotateSpeed = 0.55;
    controls.panSpeed = 0.65;
    controls.zoomSpeed = 0.7;
    controls.minDistance = 110;
    controls.maxDistance = 4800;
    controls.minPolarAngle = 0.12;
    controls.maxPolarAngle = Math.PI * 0.47;
    controls.screenSpacePanning = false;
    controls.mouseButtons = { LEFT: null, MIDDLE: THREE.MOUSE.PAN, RIGHT: THREE.MOUSE.ROTATE };
    const baseDirection = new THREE.Vector3(0.34, 0.65, 0.8).normalize();
    const homeDistance = Math.max(
      1950,
      ...bodies.filter((b) => b.parent === undefined).map((b) => (b.orbit + b.radius) * 3.4),
    );
    let baseDistance = homeDistance;
    const homeCamera = () => {
      controls.target.set(0, -65, 0);
      camera.position.copy(controls.target).addScaledVector(baseDirection, baseDistance);
      controls.update();
      controls.saveState();
    };
    homeCamera();
    scene.add(new THREE.HemisphereLight('#d7e4ff', '#3d2945', 0.4));
    const keyLight = new THREE.DirectionalLight('#fff3e4', 2.4);
    keyLight.position.set(-400, 700, 500);
    scene.add(keyLight);
    // Keep nearby ceramic hulls below the bloom range so their relief remains visible.
    const sunLight = new THREE.PointLight('#ffb9cc', 11000, 1100, 2);
    scene.add(sunLight);
    const gl = renderer.getContext() as WebGL2RenderingContext;
    const colorSamples = Array.from(
      gl.getInternalformatParameter(gl.RENDERBUFFER, gl.RGBA16F, gl.SAMPLES) as Int32Array,
    );
    const depthSamples = Array.from(
      gl.getInternalformatParameter(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, gl.SAMPLES) as Int32Array,
    );
    const samples = Math.max(0, ...colorSamples.filter((n) => n <= 4 && depthSamples.includes(n)));
    const target = new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, samples });
    const coreBody = bodies.find((b) => b.slot === 0);
    const hasBlackHole = coreBody?.kind === 'blackhole';
    if (hasBlackHole) {
      target.depthTexture = new THREE.DepthTexture(1, 1, THREE.UnsignedIntType);
    }
    const composer = new EffectComposer(renderer, target);
    const renderPass = new RenderPass(scene, camera);
    const bloomPass = new UnrealBloomPass(new THREE.Vector2(1, 1), 0.75, 0.4, 1.35);
    const aaPass = new SMAAPass();
    const outputPass = new OutputPass();
    composer.addPass(renderPass);
    composer.addPass(bloomPass);
    // SMAA also smooths shader detail after bloom; this Three.js version expects linear color.
    composer.addPass(aaPass);
    composer.addPass(outputPass);
    profiler.pass('scene', renderPass);
    profiler.pass('bloom', bloomPass);
    profiler.pass('smaa', aaPass);
    profiler.pass('output', outputPass);
    renderer.domElement.dataset.antialiasing = samples ? `msaa-${samples}+smaa` : 'smaa';
    const time = { value: 0 };
    const wells = Array.from({ length: 10 }, () => new THREE.Vector4(0, 0, 1, 0));
    const colors = Array.from({ length: 10 }, () => new THREE.Color());
    // Keep galactic bearings. Stagger adjacent mouths radially so their throats do not overlap.
    const neighborIds = [
      ...new Set(
        initial.game.links.flatMap(([a, b]) =>
          a === initial.system.id ? [b] : b === initial.system.id ? [a] : [],
        ),
      ),
    ];
    const mouths: THREE.Vector4[] = [];
    const connections = neighborIds.flatMap((id) => {
      const destination = initial.game.systems.find((s) => s.id === id);
      if (!destination) return [];
      const direction = new THREE.Vector3(
        destination.x - initial.system.x,
        0,
        destination.y - initial.system.y,
      ).normalize();
      if (!direction.lengthSq()) return [];
      const position = direction.clone().multiplyScalar(PORTAL_DISTANCE);
      let radius = PORTAL_DISTANCE,
        placementAttempt = 0;
      // Reserve the longer outward tail as well as the upright core of each neighbour.
      while (
        mouths.some(
          (m) =>
            Math.hypot(m.x - position.x, m.y - position.z) < PORTAL_MIN_SEPARATION ||
            portalFoldDistance(position.x, position.z, m) < PORTAL_BEND_OUTER + PORTAL_BEND_INNER ||
            portalFoldDistance(m.x, m.y, { x: position.x, y: position.z }) <
              PORTAL_BEND_OUTER + PORTAL_BEND_INNER,
        )
      ) {
        // Try the inner perimeter first, so crowded exits stay on the visible sheet.
        // Keep the original outward fallback for unusually many collinear connections.
        placementAttempt++;
        radius =
          PORTAL_DISTANCE + (placementAttempt <= 3 ? -250 * placementAttempt : 250 * (placementAttempt - 3));
        position.copy(direction).multiplyScalar(radius);
      }
      const mouth = new THREE.Vector4(position.x, position.z, PORTAL_WIDTH, PORTAL_LIFT);
      mouths.push(mouth);
      return [{ id, destination, direction, position, mouth }];
    });
    // GLSL requires a nonzero array size even for an isolated system.
    if (!mouths.length) mouths.push(new THREE.Vector4(0, 0, 1, 0));
    const mouthHeights = new Float32Array(mouths.length);
    const fieldMat = new THREE.ShaderMaterial({
      defines: { PORTAL_COUNT: mouths.length },
      vertexShader: fieldVertex,
      fragmentShader: fieldFragment,
      uniforms: {
        wells: { value: wells },
        mouths: { value: mouths },
        mouthHeights: { value: mouthHeights },
        colors: { value: colors },
        time,
        contours: { value: 1 },
      },
      side: THREE.DoubleSide,
      // Sheet depth hides the outside of embedded tunnels. BlackHolePass distinguishes it
      // from tactical objects using the separately rendered background depth.
      depthWrite: true,
    });
    const fieldGeo = new THREE.PlaneGeometry(4200, 4200, 400, 400);
    const field = new THREE.Mesh(fieldGeo, fieldMat);
    field.layers.enable(1);
    if (hasBlackHole) field.renderOrder = -1;
    field.frustumCulled = false; // Vertex shader displaces the plane beyond its source bounds.
    scene.add(field);
    resources.push(fieldGeo, fieldMat);
    const selectable: THREE.Object3D[] = [];
    const bodyObjects = new Map(
      bodies.map((b) => {
        const visual = createBody(b, resources, time);
        scene.add(visual.group);
        selectable.push(visual.core);
        const i = gravity.get(b.slot);
        if (i !== undefined) {
          colors[i].copy(visual.tint);
          const well = bodyGravityWell(b);
          wells[i].set(well.x, well.y, well.z, well.w);
        }
        const label = hud.add(b.name, (event) =>
          latest.current.onSelection([{ kind: 'body', slot: b.slot }], event.shiftKey ? 'toggle' : 'replace'),
        );
        label.element.oncontextmenu = (e) => {
          e.preventDefault();
          latest.current.onContext({ kind: 'body', slot: b.slot }, e.clientX, e.clientY);
        };
        label.object.position.y = -(b.megastructure ? b.radius * 3 : b.radius) - 10;
        visual.group.add(label.object);
        const orbit =
          b.orbit && b.kind !== 'asteroid'
            ? lineLoop(b.orbit, resources, '#a5bccc', b.parent === undefined ? 0.13 : 0.22)
            : null;
        if (orbit) scene.add(orbit);
        return [b.slot, { ...visual, label, orbit }] as const;
      }),
    );
    const asteroidBelts = bodies
      .filter((b) => b.kind === 'asteroid' && systemHasAsteroidBelt(initial.system))
      .map((body) => {
        const belt = createAsteroidBelt(initial.system.id, body, resources);
        scene.add(belt.group);
        return belt;
      });
    const blackHolePass = hasBlackHole
      ? new BlackHolePass(
          scene,
          camera,
          bodyObjects.get(0)!.group,
          coreBody!.radius,
          coreBody!.stellar?.family === 'quasar',
          time,
          samples,
        )
      : null;
    if (blackHolePass) {
      composer.insertPass(blackHolePass, 1);
      profiler.pass('black-hole', blackHolePass);
    }
    renderer.domElement.dataset.blackHoleRenderer = blackHolePass ? 'schwarzschild-rk4' : 'none';
    const stationGeo = new THREE.OctahedronGeometry(4),
      panelGeo = new THREE.BoxGeometry(18, 1, 5);
    const stationMat = new THREE.MeshStandardMaterial({
      color: '#d8ffeb',
      emissive: '#73bfa6',
      emissiveIntensity: 0.6,
      metalness: 0.6,
      roughness: 0.4,
    });
    resources.push(stationGeo, panelGeo, stationMat);
    const stations = new Map(
      bodies.map((b) => {
        const g = new THREE.Group();
        g.add(new THREE.Mesh(stationGeo, stationMat), new THREE.Mesh(panelGeo, stationMat));
        g.position.set(b.radius + 13, b.radius * 0.5, 0);
        bodyObjects.get(b.slot)!.group.add(g);
        return [b.slot, g] as const;
      }),
    );
    const facilityModels = new Map(
      bodies.map((body) => {
        const slot = new ModelSlot(modelLibrary);
        bodyObjects.get(body.slot)!.group.add(slot.group);
        resources.push(slot);
        return [body.slot, slot] as const;
      }),
    );
    const colonyStation = new ModelSlot(modelLibrary);
    const colonyYard = new ModelSlot(modelLibrary);
    const colonyRing = new ModelSlot(modelLibrary);
    const defenses = [new ModelSlot(modelLibrary), new ModelSlot(modelLibrary)];
    for (const slot of [colonyStation, colonyYard, colonyRing, ...defenses]) {
      (bodyObjects.get(bodies.find((b) => b.main)?.slot ?? 0)?.group ?? scene).add(slot.group);
      resources.push(slot);
    }
    (bodyObjects.get(0)?.group ?? scene).add(colonyStation.group);
    colonyStation.group.position.set((bodies[0]?.radius ?? 30) + 65, 40, 0);
    (bodyObjects.get(0)?.group ?? scene).add(colonyYard.group);
    colonyYard.group.position.set((bodies[0]?.radius ?? 30) + 110, 30, -35);
    defenses[0].group.position.set(22, 12, 55);
    defenses[1].group.position.set(-22, 12, 55);
    const selectionRings = new Map(
      bodies.map((body) => {
        const ring = lineLoop(1, resources, '#e8f4db', 0.9);
        scene.add(ring);
        return [body.slot, ring] as const;
      }),
    );
    const exits = connections.map(({ id, destination, direction, position, mouth }) => {
      const { portal, route } = createWormhole(
        mouth,
        direction,
        wells,
        mouths,
        mouthHeights,
        time,
        resources,
      );
      scene.add(portal, route);
      const pickGeo = new THREE.SphereGeometry(PORTAL_RADIUS + 9, 16, 12),
        pickMat = new THREE.MeshBasicMaterial({ visible: false });
      const pick = new THREE.Mesh(pickGeo, pickMat);
      pick.position.copy(position);
      pick.userData.destination = id;
      scene.add(pick);
      selectable.push(pick);
      resources.push(pickGeo, pickMat);
      const label = new HyperlaneLabel(root, id, destination.name, mouth, () =>
        latest.current.onNavigate(id),
      );
      label.button.onfocus = () => {
        const offset = camera.position.clone().sub(controls.target).setLength(900);
        controls.target.copy(label.anchor);
        camera.position.copy(label.anchor).add(offset);
      };
      label.button.oncontextmenu = (e) => {
        e.preventDefault();
        const point = label.anchor.clone().project(camera),
          bounds = root.getBoundingClientRect();
        latest.current.onContext(
          { kind: 'exit', id },
          bounds.left + ((point.x + 1) * bounds.width) / 2,
          bounds.top + ((1 - point.y) * bounds.height) / 2,
        );
      };
      scene.add(label.mesh);
      selectable.push(label.mesh);
      resources.push(label);
      return { id, position, mouth, portal, pick, label, direction };
    });
    renderer.domElement.dataset.hyperlaneStyle = 'upright-wormholes-compact-wide-approach';
    renderer.domElement.dataset.hyperlaneLabels = 'surface-arcs';
    const shipMeshes = new Map(
      ['scout', 'colony', 'corvette'].map((kind) => {
        const geo = shipGeometry(kind),
          mat = new THREE.MeshStandardMaterial({
            roughness: 0.35,
            metalness: 0.45,
            emissive: '#4a7780',
            emissiveIntensity: 0.32,
          });
        const mesh = new THREE.InstancedMesh(geo, mat, 4096);
        mesh.count = 0;
        mesh.frustumCulled = false;
        mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
        mesh.userData.fleets = [] as string[];
        scene.add(mesh);
        selectable.push(mesh);
        resources.push(geo, mat, mesh);
        return [kind, mesh] as const;
      }),
    );
    const modelBatches = new Map<string, { model: InstancedModel; operating: boolean }>();
    const markerGeo = new THREE.RingGeometry(17, 18, 40);
    markerGeo.rotateX(-Math.PI / 2);
    const markerMat = new THREE.MeshBasicMaterial({
      side: THREE.DoubleSide,
      transparent: true,
      opacity: 0.8,
      depthWrite: false,
    });
    const fleetMarkers = new THREE.InstancedMesh(markerGeo, markerMat, 4096);
    fleetMarkers.frustumCulled = false;
    fleetMarkers.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    fleetMarkers.userData.fleets = [] as string[];
    scene.add(fleetMarkers);
    selectable.push(fleetMarkers);
    resources.push(markerGeo, markerMat, fleetMarkers);
    const engineGeo = new THREE.SphereGeometry(1.5, 5, 4);
    const engineMat = new THREE.MeshBasicMaterial({ color: new THREE.Color('#9ae8ff').multiplyScalar(4) });
    const engines = new THREE.InstancedMesh(engineGeo, engineMat, 12288);
    engines.count = 0;
    engines.frustumCulled = false;
    scene.add(engines);
    resources.push(engineGeo, engineMat, engines);
    const starsGeo = new THREE.BufferGeometry(),
      coords = new Float32Array(500 * 3);
    for (let i = 0; i < 500; i++)
      coords.set(
        [
          (stableHash(`sx${i}`) % 5000) - 2500,
          300 + (stableHash(`sy${i}`) % 1600),
          (stableHash(`sz${i}`) % 5000) - 2500,
        ],
        i * 3,
      );
    starsGeo.setAttribute('position', new THREE.BufferAttribute(coords, 3));
    const starsMat = new THREE.PointsMaterial({
      color: '#8290a7',
      size: 1,
      transparent: true,
      opacity: 0.38,
      sizeAttenuation: false,
    });
    starsMat.depthWrite = !hasBlackHole;
    const backgroundStars = new THREE.Points(starsGeo, starsMat);
    backgroundStars.layers.enable(1);
    scene.add(backgroundStars);
    resources.push(starsGeo, starsMat);
    let width = 1,
      height = 1,
      initialized = false;
    const resize = () => {
      width = Math.max(1, root.clientWidth);
      height = Math.max(1, root.clientHeight);
      renderer.setSize(width, height);
      composer.setSize(width, height);
      hud.resize(width, height);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      baseDistance = homeDistance * Math.max(1, 0.85 / camera.aspect);
      if (!initialized) {
        homeCamera();
        initialized = true;
      }
    };
    const observer = new ResizeObserver(resize);
    observer.observe(root);
    resize();
    const ray = new THREE.Raycaster(),
      pointer = new THREE.Vector2();
    const screenTargets: ScreenTarget[] = [];
    const fleetPickPoints: { id: string; x: number; y: number; z: number }[] = [];
    const marquee = document.createElement('div');
    marquee.className = 'system-selection-box';
    marquee.hidden = true;
    root.append(marquee);
    const previewGeo = new THREE.OctahedronGeometry(18),
      previewMat = new THREE.MeshBasicMaterial({ color: '#9ee9d4', wireframe: true });
    const preview = new THREE.Mesh(previewGeo, previewMat);
    scene.add(preview);
    resources.push(previewGeo, previewMat);
    const pathGeo = new THREE.BufferGeometry(),
      pathMat = new THREE.LineBasicMaterial({ color: '#a7d9ce', transparent: true, opacity: 0.65 });
    const pathPositions = new Float32Array(65 * 3);
    pathGeo.setAttribute('position', new THREE.BufferAttribute(pathPositions, 3));
    const pathLine = new THREE.Line(pathGeo, pathMat);
    pathLine.frustumCulled = false;
    scene.add(pathLine);
    resources.push(pathGeo, pathMat);
    const drag = { x: 0, y: 0, moved: 0, valid: false, button: 0, box: false, pointerId: -1, append: false };
    let hoveredExit: string | undefined;
    const down = (e: PointerEvent) => {
      if (!e.isPrimary || drag.valid) return;
      drag.x = e.clientX;
      drag.y = e.clientY;
      drag.moved = 0;
      drag.button = e.button;
      drag.valid = (e.button === 0 || e.button === 2) && e.isPrimary;
      drag.box = e.button === 0 && e.pointerType !== 'touch';
      drag.append = e.shiftKey;
      drag.pointerId = e.pointerId;
      if (drag.box) {
        e.stopImmediatePropagation();
        renderer.domElement.focus({ preventScroll: true });
        renderer.domElement.setPointerCapture(e.pointerId);
      }
    };
    const hitTarget = (e: PointerEvent): SystemTarget | undefined => {
      const bounds = renderer.domElement.getBoundingClientRect();
      const x = e.clientX - bounds.left,
        y = e.clientY - bounds.top;
      pointer.set((x / width) * 2 - 1, 1 - (y / height) * 2);
      ray.setFromCamera(pointer, camera);
      const hit = ray.intersectObjects(selectable, true)[0];
      const data = hit?.object.userData;
      if (data?.destination) return { kind: 'exit', id: data.destination };
      const id = hit?.instanceId === undefined ? undefined : data?.fleets?.[hit.instanceId];
      if (id) return { kind: 'fleet', id };
      // Prefer a nearby small ship over the broad silhouette of a star beneath it.
      const near = nearbyTarget(screenTargets, x, y);
      if (near) return near;
      if (data?.slot !== undefined) return { kind: 'body', slot: data.slot };
    };
    const move = (e: PointerEvent) => {
      drag.moved = Math.max(drag.moved, Math.hypot(e.clientX - drag.x, e.clientY - drag.y));
      if (drag.valid && drag.box && drag.moved >= 5 && !latest.current.placement) {
        const bounds = renderer.domElement.getBoundingClientRect();
        marquee.hidden = false;
        marquee.style.left = `${Math.max(0, Math.min(drag.x, e.clientX) - bounds.left)}px`;
        marquee.style.top = `${Math.max(0, Math.min(drag.y, e.clientY) - bounds.top)}px`;
        marquee.style.width = `${Math.min(width, Math.max(drag.x, e.clientX) - bounds.left) - parseFloat(marquee.style.left)}px`;
        marquee.style.height = `${Math.min(height, Math.max(drag.y, e.clientY) - bounds.top) - parseFloat(marquee.style.top)}px`;
        return;
      }
      const target = hitTarget(e);
      hoveredExit = target?.kind === 'exit' ? target.id : undefined;
      renderer.domElement.style.cursor = target ? 'pointer' : '';
    };
    const cancel = () => {
      drag.valid = false;
      marquee.hidden = true;
      if (renderer.domElement.hasPointerCapture(drag.pointerId))
        renderer.domElement.releasePointerCapture(drag.pointerId);
      hoveredExit = undefined;
      renderer.domElement.style.cursor = '';
    };
    const up = (e: PointerEvent) => {
      if (e.pointerId !== drag.pointerId) return;
      drag.moved = Math.max(drag.moved, Math.hypot(e.clientX - drag.x, e.clientY - drag.y));
      if (drag.valid && drag.box && drag.moved >= 5 && !latest.current.placement) {
        const bounds = renderer.domElement.getBoundingClientRect();
        latest.current.onSelection(
          targetsInBox(
            screenTargets,
            drag.x - bounds.left,
            drag.y - bounds.top,
            e.clientX - bounds.left,
            e.clientY - bounds.top,
          ),
          drag.append ? 'add' : 'replace',
        );
        cancel();
        return;
      }
      if (drag.valid && drag.moved < 5) {
        const r = renderer.domElement.getBoundingClientRect();
        pointer.set(((e.clientX - r.left) / width) * 2 - 1, 1 - ((e.clientY - r.top) / height) * 2);
        ray.setFromCamera(pointer, camera);
        if (drag.button === 0 && latest.current.placement) {
          const point = new THREE.Vector3();
          if (
            ray.ray.intersectPlane(
              new THREE.Plane(new THREE.Vector3(0, 1, 0), -latest.current.placement.y),
              point,
            )
          )
            latest.current.onPoint?.(
              { x: Math.round(point.x), y: point.y, z: Math.round(point.z) },
              e.shiftKey,
            );
          cancel();
          return;
        }
        const target = hitTarget(e);
        if (drag.button === 2) {
          if (target) latest.current.onContext(target, e.clientX, e.clientY);
          else {
            const p = latest.current;
            const fleetIds = p.selection.filter((t) => t.kind === 'fleet').map((t) => t.id);
            const fleet = p.game.fleets.find((f) => fleetIds.includes(f.id) && f.owner === p.game.me.id);
            const y = fleet?.navigation ? localPosition(fleet.navigation.motion, p.game.tick).y : 24;
            const point = new THREE.Vector3();
            if (ray.ray.intersectPlane(new THREE.Plane(new THREE.Vector3(0, 1, 0), -y), point))
              p.onMove({ x: Math.round(point.x), y, z: Math.round(point.z) }, e.shiftKey);
          }
          cancel();
          return;
        }
        if (target?.kind === 'exit') latest.current.onNavigate(target.id);
        else latest.current.onSelection(target ? [target] : [], e.shiftKey ? 'toggle' : 'replace');
      }
      cancel();
    };
    const escape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') cancel();
    };
    renderer.domElement.addEventListener('pointerdown', down, true);
    renderer.domElement.addEventListener('pointermove', move);
    renderer.domElement.addEventListener('pointerup', up);
    renderer.domElement.addEventListener('pointercancel', cancel);
    renderer.domElement.addEventListener('lostpointercapture', cancel);
    window.addEventListener('blur', cancel);
    window.addEventListener('keydown', escape);
    const dummy = new THREE.Object3D(),
      color = new THREE.Color(),
      projection = new THREE.Vector3(),
      offset = new THREE.Vector3();
    const fleetPositions = new Map<string, THREE.Vector3>();
    const fleetHeadings = new Map<string, number>();
    let lastStep = initial.zoomStep,
      lastReset = initial.reset,
      lastFocus = initial.focusSelection;
    let animation = 0,
      previous = 0,
      zoomReported = 0,
      lastZoomReadout = 0;
    const animate = (at: number) => {
      animation = requestAnimationFrame(animate);
      if (document.hidden) return;
      const delta = previous ? Math.min(0.05, (at - previous) / 1000) : 1 / 60;
      previous = at;
      const p = latest.current,
        t =
          p.game.displayClock?.now(at) ??
          p.game.tick + (p.game.paused ? 0 : Math.min(1, (at - sample.current.at) / 1000) * p.game.speed);
      const indices = gameIndices(p.game);
      const selectedBodies = new Set(p.selection.filter((t) => t.kind === 'body').map((t) => t.slot));
      const selectedFleets = new Set(p.selection.filter((t) => t.kind === 'fleet').map((t) => t.id));
      const primary = p.selection.at(-1);
      const primaryFleetId = primary?.kind === 'fleet' ? primary.id : null;
      time.value = t;
      for (const belt of asteroidBelts) belt.animate(t);
      fieldMat.uniforms.contours.value = p.contours ? 1 : 0;
      bloomPass.enabled = p.bloom;
      for (const b of bodies) {
        const visual = bodyObjects.get(b.slot)!,
          pos = bodyPosition(b, bodies, t);
        visual.animate(t);
        visual.group.position.set(pos.x, pos.y, pos.z);
        const i = gravity.get(b.slot);
        if (i !== undefined) {
          wells[i].x = visual.group.position.x;
          wells[i].y = visual.group.position.z;
        }
      }
      for (const [i, mouth] of mouths.entries())
        mouthHeights[i] = surfaceHeight(mouth.x, mouth.y, wells, mouths);
      for (const [i, exit] of exits.entries()) {
        const folded = foldSurfacePoint(
          { x: exit.mouth.x, y: mouthHeights[i] - PORTAL_DEPTH * 0.3, z: exit.mouth.y },
          mouths,
          mouthHeights,
        );
        exit.position.set(folded.x, folded.y, folded.z);
        exit.pick.position.copy(exit.position);
      }
      for (const b of bodies) {
        const v = bodyObjects.get(b.slot)!,
          pos = v.group.position;
        // Bodies float above their potential well so they remain readable at low viewing angles.
        pos.y = b.position?.y ?? b.radius * 0.45 - 12;
        if (b.kind === 'station')
          v.group.children[0].visible = !indices.sites.get(`${p.system.id}:${b.slot}`)?.level;
        if (v.orbit) {
          v.orbit.visible = selectedBodies.has(b.slot);
          if (b.parent !== undefined) v.orbit.position.copy(bodyObjects.get(b.parent)!.group.position);
          else v.orbit.position.y = -8;
        }
        const site = indices.sites.get(`${p.system.id}:${b.slot}`),
          station = stations.get(b.slot)!;
        const facility = facilityModels.get(b.slot)!;
        const spec = site ? facilityModel(site, b) : undefined;
        facility.set(
          spec ? modelAsset(playerShipSet(p.game, site!.owner), spec.id) : undefined,
          spec?.span ?? 1,
          spec?.planetRadius,
        );
        facility.group.position.set(
          spec?.centered ? 0 : b.radius + 22,
          spec?.height ?? (spec?.centered ? 0 : b.radius * 0.5),
          0,
        );
        facility.update(t, !!site && !site.suspended);
        station.visible = !!site && !facility.ready;
        station.scale.setScalar(site?.building ? 0.85 + Math.sin(t * 2) * 0.15 : 1);
        station.rotation.y = t * 0.08;
        v.label.update({ selected: selectedBodies.has(b.slot), built: !!site?.level });
      }
      const colony = p.system.colony;
      const ownerSet = playerShipSet(p.game, p.system.owner);
      const bastion = colonyBuildingLevel(colony, 'bastion');
      colonyStation.set(
        p.system.starbase || p.system.starbaseLevel
          ? modelAsset(
              ownerSet,
              (p.system.starbase?.level ?? p.system.starbaseLevel ?? 0) === 0
                ? '05_construction_level_0'
                : STATION_MODELS[
                    Math.max(0, Math.min(3, (p.system.starbase?.level ?? p.system.starbaseLevel ?? 1) - 1))
                  ],
            )
          : undefined,
        38 + (p.system.starbase?.level ?? p.system.starbaseLevel ?? 0) * 10,
      );
      colonyStation.update(t);
      colonyYard.set(
        p.system.starbase?.modules.some((m) => m.type === 'shipyard')
          ? modelAsset(ownerSet, '04_mega_shipyard')
          : undefined,
        65,
      );
      colonyYard.update(
        t,
        p.game.me.queue.some((j) => j.systemId === p.system.id),
      );
      const mainBody = bodies.find((b) => b.main);
      const hasHabitatRing = p.game.sites?.some(
        (s) =>
          s.systemId === p.system.id &&
          s.bodySlot === mainBody?.slot &&
          s.facility === 'habitat' &&
          s.level >= 3,
      );
      colonyRing.set(
        p.system.owner && mainBody && !hasHabitatRing && colonyBuildingLevel(colony, 'foundry') >= 3
          ? modelAsset(ownerSet, 'orbital_ring')
          : undefined,
        80,
        mainBody ? mainBody.radius * 1.05 : undefined,
      );
      colonyRing.update(t);
      defenses.forEach((slot, i) => {
        slot.set(
          p.system.owner && bastion > i
            ? modelAsset(ownerSet, i ? '06_artillerieplattform' : '05_abwehrplattform')
            : undefined,
          21 + i * 6,
        );
        slot.update(t);
      });
      sunLight.position.copy(bodyObjects.get(0)!.group.position);
      sunLight.position.y += 50;
      const chosen = primary?.kind === 'body' ? bodies.find((b) => b.slot === primary.slot) : undefined;
      for (const body of bodies) {
        const ring = selectionRings.get(body.slot)!;
        ring.visible = selectedBodies.has(body.slot);
        ring.position.copy(bodyObjects.get(body.slot)!.group.position);
        ring.scale.setScalar(body.radius + 12);
      }
      const counts: Record<string, number> = { scout: 0, colony: 0, corvette: 0 };
      for (const { model } of modelBatches.values()) model.begin();
      let engineCount = 0;
      let markerCount = 0;
      const fleets = (indices.fleetsBySystem.get(p.system.id) ?? []).filter(
        (f) =>
          !f.route.length ||
          ((f.journey ? travelProgress(f.journey, t) : f.progress) < 0.15 &&
            (!f.journey || Math.hypot(f.journey.fromX - p.system.x, f.journey.fromY - p.system.y) < 0.01)),
      );
      const perKind = new Map<string, number>();
      for (const f of fleets) perKind.set(f.type, (perKind.get(f.type) || 0) + 1);
      fleetPositions.clear();
      fleetPickPoints.length = 0;
      for (const [k, f] of fleets.entries()) {
        const mesh = shipMeshes.get(f.type);
        if (!mesh) continue;
        const set = playerShipSet(p.game, f.owner);
        const operating = !!f.task && !f.task.blocked;
        const key = `${set}/${f.type}/${operating}`;
        let batch = modelBatches.get(key);
        const asset = modelAsset(set, SHIP_MODEL[f.type]);
        if (!batch && asset) {
          const model = new InstancedModel(modelLibrary, asset, f.type === 'corvette' ? 25 : 28);
          batch = { model, operating };
          modelBatches.set(key, batch);
          scene.add(model.group);
          selectable.push(model.group);
          resources.push(model);
        }
        const nShips = Math.min(f.shipCount ?? 1, 120, Math.max(1, Math.floor(4096 / perKind.get(f.type)!)));
        const a = (stableHash(f.id) / 0xffffffff) * Math.PI * 2 + (f.task ? t * 0.002 : 0),
          orbit = 100 + (k % 3) * 32;
        const loc = f.navigation ? localPosition(f.navigation.motion, t) : fleetAnchor(f.id);
        const velocity = f.navigation ? localVelocity(f.navigation.motion, t) : { x: 0, y: 0, z: 0 };
        const speed = Math.hypot(velocity.x, velocity.z);
        const heading = fleetHeadings.get(f.id) ?? -a;
        const motion = f.navigation?.motion;
        const targetHeading =
          speed > 0.05
            ? Math.atan2(velocity.x, velocity.z)
            : motion && motion.finishAt > t && !motion.paused
              ? Math.atan2(motion.to.x - loc.x, motion.to.z - loc.z)
              : heading;
        const turn = Math.atan2(Math.sin(targetHeading - heading), Math.cos(targetHeading - heading));
        const maxTurn = p.game.paused ? 0 : delta * p.game.speed * 0.65;
        const yaw = heading + Math.max(-maxTurn, Math.min(maxTurn, turn));
        fleetHeadings.set(f.id, yaw);
        const center = new THREE.Vector3(loc.x, loc.y, loc.z);
        const exit = f.route.length ? exits.find((e) => e.id === f.route[0]) : undefined;
        if (exit)
          center.lerp(
            exit.position,
            Math.min(1, (f.journey ? travelProgress(f.journey, t) : f.progress) / 0.15),
          );
        fleetPositions.set(f.id, center);
        color.set(selectedFleets.has(f.id) ? '#e9e8ae' : indices.players.get(f.owner)?.color || '#c8d9e6');
        if (markerCount < 4096) {
          dummy.position.copy(center).add(offset.set(0, -7, 0));
          dummy.rotation.set(0, 0, 0);
          dummy.scale.setScalar(selectedFleets.has(f.id) ? 1.4 : 1);
          dummy.updateMatrix();
          instanceMatrix(fleetMarkers, markerCount, dummy.matrix);
          instanceColor(fleetMarkers, markerCount, color);
          fleetMarkers.userData.fleets[markerCount++] = f.id;
        }
        for (let i = 0; i < nShips && counts[f.type] < 4096; i++) {
          const n = counts[f.type],
            row = Math.floor(Math.sqrt(i)),
            col = i - row * row;
          dummy.position.copy(center).add(offset.set((col - row) * 20, 0, row * 28));
          fleetPickPoints.push({ id: f.id, x: dummy.position.x, y: dummy.position.y, z: dummy.position.z });
          dummy.rotation.set(
            0,
            exit ? Math.atan2(-exit.direction.x, -exit.direction.z) : yaw,
            Math.max(-0.22, Math.min(0.22, (-turn * speed) / 160)),
          );
          const scale = selectedFleets.has(f.id) ? 1.45 : 1.2;
          dummy.scale.setScalar(scale);
          dummy.updateMatrix();
          if (batch?.model.ready) batch.model.add(dummy.matrix, f.id);
          else {
            counts[f.type]++;
            instanceMatrix(mesh, n, dummy.matrix);
            instanceColor(mesh, n, color);
            mesh.userData.fleets[n] = f.id;
            dummy.translateZ(9 * scale);
            dummy.scale.set(1, 1, 3);
            dummy.updateMatrix();
            instanceMatrix(engines, engineCount++, dummy.matrix);
          }
        }
      }
      for (const [kind, mesh] of shipMeshes) {
        mesh.count = counts[kind];
        mesh.boundingSphere = null; // Recompute picking bounds lazily after formations move or grow.
        flushInstances(mesh);
      }
      modelLibrary.setTime(t);
      for (const { model, operating } of modelBatches.values()) model.end(t, operating);
      fleetMarkers.count = markerCount;
      preview.visible = !!p.previewPoint;
      if (p.previewPoint) preview.position.set(p.previewPoint.x, p.previewPoint.y, p.previewPoint.z);
      const navigatingFleet = p.game.fleets.find(
        (f) => f.id === primaryFleetId && f.owner === p.game.me.id && f.systemId === p.system.id,
      );
      const nav = navigatingFleet?.navigation;
      let pathCount = 0;
      const addPoint = (q: Point3) => {
        if (pathCount < 65) {
          pathPositions.set([q.x, q.y, q.z], pathCount * 3);
          pathCount++;
        }
      };
      if (nav && (nav.orders.length || nav.phase === 'braking')) {
        for (let i = 0; i <= 24; i++)
          addPoint(localPosition(nav.motion, t + (Math.max(0, nav.motion.finishAt - t) * i) / 24));
        for (const order of nav.orders.slice(1)) {
          if (order.type === 'move') break;
          if (order.type === 'local_move' && order.systemId === p.system.id) addPoint(order.point);
        }
      }
      pathGeo.setDrawRange(0, pathCount);
      pathGeo.attributes.position.needsUpdate = true;
      pathLine.visible = pathCount > 1;
      fleetMarkers.boundingSphere = null;
      flushInstances(fleetMarkers);
      engines.count = engineCount;
      flushInstances(engines);
      if (lastReset !== p.reset) {
        lastReset = p.reset;
        controls.reset();
        homeCamera();
      }
      if (lastFocus !== p.focusSelection) {
        lastFocus = p.focusSelection;
        const groupBounds = new THREE.Box3();
        for (const selected of p.selection) {
          const position =
            selected.kind === 'body'
              ? bodyObjects.get(selected.slot)?.group.position
              : fleetPositions.get(selected.id);
          if (!position) continue;
          const radius =
            selected.kind === 'body' ? (bodies.find((b) => b.slot === selected.slot)?.radius ?? 0) : 50;
          groupBounds.expandByPoint(position.clone().addScalar(radius));
          groupBounds.expandByPoint(position.clone().addScalar(-radius));
        }
        for (const point of fleetPickPoints) {
          if (!selectedFleets.has(point.id)) continue;
          groupBounds.expandByPoint(new THREE.Vector3(point.x - 50, point.y - 50, point.z - 50));
          groupBounds.expandByPoint(new THREE.Vector3(point.x + 50, point.y + 50, point.z + 50));
        }
        const group =
          p.selection.length > 1 && !groupBounds.isEmpty()
            ? groupBounds.getBoundingSphere(new THREE.Sphere())
            : undefined;
        const target = chosen
          ? bodyObjects.get(chosen.slot)!.group.position
          : fleetPositions.get(primaryFleetId || '');
        if (group || target) {
          const center = group?.center ?? target!;
          offset.copy(camera.position).sub(controls.target).normalize();
          controls.target.copy(center);
          camera.position
            .copy(center)
            .addScaledVector(
              offset,
              group
                ? Math.min(
                    controls.maxDistance,
                    Math.max(
                      800,
                      (group.radius * 1.4) /
                        Math.sin(
                          Math.min(
                            THREE.MathUtils.degToRad(camera.fov) / 2,
                            Math.atan(Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2) * camera.aspect),
                          ),
                        ),
                    ),
                  )
                : chosen
                  ? Math.max(
                      160,
                      chosen.radius * (chosen.kind === 'blackhole' ? 16 : 9),
                      chosen.kind === 'asteroid' && systemHasAsteroidBelt(p.system) ? 650 : 0,
                    )
                  : 250,
            );
        }
      }
      if (lastStep !== p.zoomStep) {
        offset.copy(camera.position).sub(controls.target);
        offset.setLength(
          THREE.MathUtils.clamp(
            offset.length() / Math.pow(1.25, p.zoomStep - lastStep),
            controls.minDistance,
            controls.maxDistance,
          ),
        );
        camera.position.copy(controls.target).add(offset);
        lastStep = p.zoomStep;
      }
      if (!(drag.valid && drag.box)) controls.update(delta);
      camera.updateMatrixWorld();
      screenTargets.length = 0;
      const projectTarget = (target: SpaceTarget, position: THREE.Vector3, radius: number) => {
        projection.copy(position).project(camera);
        if (projection.z < -1 || projection.z > 1 || Math.abs(projection.x) > 1 || Math.abs(projection.y) > 1)
          return;
        const depth = position.distanceTo(camera.position);
        screenTargets.push({
          target,
          x: ((projection.x + 1) * width) / 2,
          y: ((1 - projection.y) * height) / 2,
          radius: (radius * height) / (2 * Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2) * depth),
          depth,
        });
      };
      for (const body of bodies)
        projectTarget(
          { kind: 'body', slot: body.slot },
          bodyObjects.get(body.slot)!.group.position,
          body.radius,
        );
      for (const point of fleetPickPoints)
        projectTarget({ kind: 'fleet', id: point.id }, offset.set(point.x, point.y, point.z), 12);
      for (const exit of exits)
        exit.label.update(wells, mouths, mouthHeights, camera, exit.id === hoveredExit);
      scene.updateMatrixWorld();
      bloomPass.strength = 0.75 * THREE.MathUtils.clamp(controls.getDistance() / 700, 0.24, 1);
      const zoom = Math.round((baseDistance / controls.getDistance()) * 100) / 100;
      // Only the numeric React readout is throttled. Scene labels follow every camera frame.
      if (at - lastZoomReadout > 70) {
        lastZoomReadout = at;
        if (zoom !== zoomReported) {
          zoomReported = zoom;
          p.onZoom(zoom);
        }
      }
      {
        const occupied: { x: number; y: number; w: number }[] = [];
        const ordered = [...bodies].sort(
          (a, b) => Number(selectedBodies.has(b.slot)) - Number(selectedBodies.has(a.slot)),
        );
        for (const b of ordered) {
          const v = bodyObjects.get(b.slot)!;
          v.label.object.getWorldPosition(projection);
          projection.project(camera);
          const x = ((projection.x + 1) * width) / 2,
            y = ((1 - projection.y) * height) / 2,
            w = v.label.width;
          const visible =
            projection.z < 1 &&
            projection.z > -1 &&
            x > 10 &&
            x < width - 10 &&
            y > 160 &&
            y < height - 120 &&
            (b.parent === undefined || selectedBodies.has(b.slot) || zoom > 2) &&
            !occupied.some((o) => Math.abs(x - o.x) < (w + o.w) / 2 + 6 && Math.abs(y - o.y) < 26);
          v.label.place(x - w / 2, y, visible);
          if (visible) occupied.push({ x, y, w });
        }
      }
      profiler.begin();
      hud.present(() => composer.render(delta));
      profiler.end(
        takeInstanceUploadBytes() + [...modelBatches.values()].reduce((n, b) => n + b.model.uploadBytes, 0),
      );
    };
    animation = requestAnimationFrame(animate);
    return () => {
      cancelAnimationFrame(animation);
      observer.disconnect();
      controls.dispose();
      hud.dispose();
      renderer.domElement.removeEventListener('pointerdown', down, true);
      renderer.domElement.removeEventListener('pointermove', move);
      renderer.domElement.removeEventListener('pointerup', up);
      renderer.domElement.removeEventListener('pointercancel', cancel);
      renderer.domElement.removeEventListener('lostpointercapture', cancel);
      window.removeEventListener('blur', cancel);
      window.removeEventListener('keydown', escape);
      marquee.remove();
      resources.forEach((r) => r.dispose());
      renderPass.dispose();
      blackHolePass?.dispose();
      bloomPass.dispose();
      aaPass.dispose();
      outputPass.dispose();
      composer.dispose();
      renderer.dispose();
      renderer.domElement.remove();
    };
  }, [
    props.bodies,
    props.system.id,
    props.system.name,
    props.system.colonyName,
    props.system.planet,
    props.system.kind,
    props.system.class,
    props.system.color,
  ]);
  return (
    <div ref={parent} className="system-scene">
      {fallback && (
        <div className="system-scene-fallback">
          3D ist hier nicht verfügbar. Himmelskörper und Bauverwaltung bleiben über die Objektliste bedienbar.
        </div>
      )}
    </div>
  );
}
