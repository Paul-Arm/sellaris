import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { SMAAPass } from 'three/examples/jsm/postprocessing/SMAAPass.js';
import type { GameView, StarSystem } from '../shared/game';
import { systemBodies, systemHasAsteroidBelt, stableHash } from '../shared/celestial';
import { createBody, lineLoop, shipGeometry, type Disposable } from './system-objects';
import { createAsteroidBelt } from './asteroid-belts';
import { fieldVertex, fieldFragment } from './system-shaders';
import { CanvasHud } from './canvas-hud';
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

interface Props {
  game: GameView;
  system: StarSystem;
  selectedBody: number;
  fleetId: string | null;
  onBody: (slot: number) => void;
  onFleet: (id: string) => void;
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
      bodies = systemBodies(initial.system);
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
    renderer.toneMappingExposure = 1.12;
    renderer.domElement.setAttribute(
      'aria-label',
      'Dreidimensionale Raumzeitkarte. Ziehen zum Drehen, Mausrad zum Zoomen.',
    );
    renderer.domElement.tabIndex = 0;
    root.prepend(renderer.domElement);
    const resources: Disposable[] = [];
    const scene = new THREE.Scene(),
      camera = new THREE.PerspectiveCamera(44, 1, 1, 7000);
    scene.background = new THREE.Color(0.003, 0.004, 0.007);
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
    scene.add(new THREE.HemisphereLight('#d7e4ff', '#6c466c', 2.4));
    const keyLight = new THREE.DirectionalLight('#fff3e4', 3);
    keyLight.position.set(-400, 700, 500);
    scene.add(keyLight);
    const sunLight = new THREE.PointLight('#ff86be', 55000, 1100, 2);
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
    const hasBlackHole = initial.system.kind === 'blackhole';
    if (hasBlackHole) {
      target.depthTexture = new THREE.DepthTexture(1, 1, THREE.UnsignedIntType);
    }
    const composer = new EffectComposer(renderer, target);
    const renderPass = new RenderPass(scene, camera);
    const bloomPass = new UnrealBloomPass(new THREE.Vector2(1, 1), 0.75, 0.55, 0.85);
    const aaPass = new SMAAPass();
    const outputPass = new OutputPass();
    composer.addPass(renderPass);
    composer.addPass(bloomPass);
    // SMAA also smooths shader detail after bloom; this Three.js version expects linear color.
    composer.addPass(aaPass);
    composer.addPass(outputPass);
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
      bodies.map((b, i) => {
        const visual = createBody(b, resources, time);
        scene.add(visual.group);
        selectable.push(visual.core);
        colors[i].copy(visual.tint);
        const well = bodyGravityWell(b);
        wells[i].set(well.x, well.y, well.z, well.w);
        const label = hud.add('body', b.name, () => latest.current.onBody(b.slot));
        label.object.position.y = -b.radius - 10;
        visual.group.add(label.object);
        const orbit = b.orbit
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
          bodies[0].radius,
          bodies[0].stellar?.family === 'quasar',
          time,
          samples,
        )
      : null;
    if (blackHolePass) composer.insertPass(blackHolePass, 1);
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
    const selection = lineLoop(1, resources, '#e8f4db', 0.9);
    scene.add(selection);
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
      const label = hud.add('exit', destination.name, () => latest.current.onNavigate(id));
      scene.add(label.object);
      return { id, position, mouth, portal, pick, label, direction };
    });
    renderer.domElement.dataset.hyperlaneStyle = 'upright-wormholes-compact-wide-approach';
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
    const drag = { x: 0, y: 0, moved: 0, valid: false };
    const down = (e: PointerEvent) => {
      drag.x = e.clientX;
      drag.y = e.clientY;
      drag.moved = 0;
      drag.valid = e.button === 0 && e.isPrimary;
    };
    const move = (e: PointerEvent) => {
      drag.moved = Math.max(drag.moved, Math.hypot(e.clientX - drag.x, e.clientY - drag.y));
    };
    const cancel = () => {
      drag.valid = false;
    };
    const up = (e: PointerEvent) => {
      if (drag.valid && drag.moved < 5) {
        const r = renderer.domElement.getBoundingClientRect();
        pointer.set(((e.clientX - r.left) / width) * 2 - 1, 1 - ((e.clientY - r.top) / height) * 2);
        ray.setFromCamera(pointer, camera);
        const hit = ray.intersectObjects(selectable, false)[0];
        if (hit?.object.userData.destination) latest.current.onNavigate(hit.object.userData.destination);
        else if (hit?.instanceId !== undefined) {
          const id = hit.object.userData.fleets?.[hit.instanceId];
          if (id) latest.current.onFleet(id);
        } else if (hit?.object.userData.slot !== undefined) latest.current.onBody(hit.object.userData.slot);
      }
      drag.valid = false;
    };
    renderer.domElement.addEventListener('pointerdown', down);
    renderer.domElement.addEventListener('pointermove', move);
    renderer.domElement.addEventListener('pointerup', up);
    renderer.domElement.addEventListener('pointercancel', cancel);
    const dummy = new THREE.Object3D(),
      color = new THREE.Color(),
      projection = new THREE.Vector3(),
      offset = new THREE.Vector3();
    const fleetPositions = new Map<string, THREE.Vector3>();
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
        t = p.game.tick + (p.game.paused ? 0 : Math.min(1, (at - sample.current.at) / 1000) * p.game.speed);
      time.value = t;
      for (const belt of asteroidBelts) belt.animate(t);
      fieldMat.uniforms.contours.value = p.contours ? 1 : 0;
      bloomPass.enabled = p.bloom;
      for (const [i, b] of bodies.entries()) {
        const visual = bodyObjects.get(b.slot)!,
          angle = b.phase + (t / b.period) * Math.PI * 2;
        visual.animate(t);
        visual.group.position.set(Math.cos(angle) * b.orbit, 0, Math.sin(angle) * b.orbit);
        if (b.parent !== undefined) visual.group.position.add(bodyObjects.get(b.parent)!.group.position);
        wells[i].x = visual.group.position.x;
        wells[i].y = visual.group.position.z;
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
        pos.y = b.radius * 0.45 - 12;
        if (v.orbit) {
          v.orbit.visible = b.slot === p.selectedBody;
          if (b.parent !== undefined) v.orbit.position.copy(bodyObjects.get(b.parent)!.group.position);
          else v.orbit.position.y = -8;
        }
        const site = p.game.sites?.find((s) => s.systemId === p.system.id && s.bodySlot === b.slot),
          station = stations.get(b.slot)!;
        station.visible = !!site;
        station.scale.setScalar(site?.building ? 0.85 + Math.sin(t * 2) * 0.15 : 1);
        station.rotation.y = t * 0.08;
        v.label.update({ selected: p.selectedBody === b.slot, built: !!site?.level });
      }
      sunLight.position.copy(bodyObjects.get(0)!.group.position);
      sunLight.position.y += 50;
      const chosen = bodies.find((b) => b.slot === p.selectedBody);
      selection.visible = !!chosen && chosen.kind !== 'blackhole';
      if (chosen) {
        selection.position.copy(bodyObjects.get(chosen.slot)!.group.position);
        selection.scale.setScalar(chosen.radius + 12);
      }
      const counts: Record<string, number> = { scout: 0, colony: 0, corvette: 0 };
      let engineCount = 0;
      const fleets = p.game.fleets.filter(
        (f) => f.systemId === p.system.id && (!f.route.length || f.progress < 0.15),
      );
      const perKind = new Map<string, number>();
      for (const f of fleets) perKind.set(f.type, (perKind.get(f.type) || 0) + 1);
      fleetPositions.clear();
      for (const [k, f] of fleets.entries()) {
        const mesh = shipMeshes.get(f.type);
        if (!mesh) continue;
        const nShips = Math.min(f.shipCount ?? 1, 120, Math.max(1, Math.floor(4096 / perKind.get(f.type)!)));
        const a = (stableHash(f.id) / 0xffffffff) * Math.PI * 2 + (f.task ? t * 0.002 : 0),
          orbit = 100 + (k % 3) * 32;
        const center = new THREE.Vector3(Math.cos(a) * orbit, 16 + (k % 2) * 8, Math.sin(a) * orbit);
        const exit = f.route.length ? exits.find((e) => e.id === f.route[0]) : undefined;
        if (exit) center.lerp(exit.position, Math.min(1, f.progress / 0.15));
        fleetPositions.set(f.id, center);
        color.set(
          f.id === p.fleetId ? '#e9e8ae' : p.game.players.find((v) => v.id === f.owner)?.color || '#c8d9e6',
        );
        for (let i = 0; i < nShips && counts[f.type] < 4096; i++) {
          const n = counts[f.type]++,
            row = Math.floor(Math.sqrt(i)),
            col = i - row * row;
          dummy.position.copy(center).add(offset.set((col - row) * 20, 0, row * 28));
          dummy.rotation.set(0, exit ? Math.atan2(-exit.direction.x, -exit.direction.z) : -a, 0);
          const scale = f.id === p.fleetId ? 1.45 : 1.2;
          dummy.scale.setScalar(scale);
          dummy.updateMatrix();
          mesh.setMatrixAt(n, dummy.matrix);
          mesh.setColorAt(n, color);
          mesh.userData.fleets[n] = f.id;
          dummy.translateZ(9 * scale);
          dummy.scale.set(1, 1, 3);
          dummy.updateMatrix();
          engines.setMatrixAt(engineCount++, dummy.matrix);
        }
      }
      for (const [kind, mesh] of shipMeshes) {
        mesh.count = counts[kind];
        mesh.boundingSphere = null; // Recompute picking bounds lazily after formations move or grow.
        mesh.instanceMatrix.needsUpdate = true;
        if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
      }
      engines.count = engineCount;
      engines.instanceMatrix.needsUpdate = true;
      if (lastReset !== p.reset) {
        lastReset = p.reset;
        controls.reset();
        homeCamera();
      }
      if (lastFocus !== p.focusSelection) {
        lastFocus = p.focusSelection;
        const target = chosen
          ? bodyObjects.get(chosen.slot)!.group.position
          : fleetPositions.get(p.fleetId || '');
        if (target) {
          offset.copy(camera.position).sub(controls.target).normalize();
          controls.target.copy(target);
          camera.position
            .copy(target)
            .addScaledVector(
              offset,
              chosen ? Math.max(160, chosen.radius * (chosen.kind === 'blackhole' ? 16 : 9)) : 250,
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
      controls.update(delta);
      camera.updateMatrixWorld();
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
          (a, b) => Number(b.slot === p.selectedBody) - Number(a.slot === p.selectedBody),
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
            (b.parent === undefined || b.slot === p.selectedBody || zoom > 2) &&
            !occupied.some((o) => Math.abs(x - o.x) < (w + o.w) / 2 + 6 && Math.abs(y - o.y) < 26);
          v.label.place(x - w / 2, y, visible);
          if (visible) occupied.push({ x, y, w });
        }
        const edgePoints = exits.map((exit) => {
          projection.copy(exit.position).project(camera);
          let dx = (projection.x * width) / 2,
            dy = (-projection.y * height) / 2;
          if (projection.z > 1) {
            dx = -dx;
            dy = -dy;
          }
          exit.label.bearing(Math.atan2(dy, dx) + Math.PI / 4);
          return { exit, side: dx < 0 ? -1 : 1, y: height / 2 + dy };
        });
        for (const side of [-1, 1]) {
          const points = edgePoints.filter((e) => e.side === side).sort((a, b) => a.y - b.y);
          const top = Math.min(195, height * 0.36),
            bottom = Math.max(top + 50, height - 195);
          const gap = Math.min(49, (bottom - top) / Math.max(1, points.length - 1));
          let previousY = top - gap;
          for (const [i, point] of points.entries()) {
            const upper = bottom - (points.length - i - 1) * gap;
            const y = THREE.MathUtils.clamp(point.y, Math.max(top, previousY + gap), upper);
            const label = point.exit.label,
              x = side < 0 ? 92 : width - 92;
            label.update({ compact: gap < 39 });
            label.place(x - label.width / 2, y - label.height / 2);
            // Keep edge-pinned destinations in the same Three.js label scene as body anchors.
            label.object.position.set((x / width) * 2 - 1, 1 - (y / height) * 2, 0).unproject(camera);
            previousY = y;
          }
        }
      }
      hud.present(() => composer.render(delta));
    };
    animation = requestAnimationFrame(animate);
    return () => {
      cancelAnimationFrame(animation);
      observer.disconnect();
      controls.dispose();
      hud.dispose();
      renderer.domElement.removeEventListener('pointerdown', down);
      renderer.domElement.removeEventListener('pointermove', move);
      renderer.domElement.removeEventListener('pointerup', up);
      renderer.domElement.removeEventListener('pointercancel', cancel);
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
