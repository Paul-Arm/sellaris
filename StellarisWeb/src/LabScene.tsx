import { RenderProfiler } from './render-profiler';
import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { positionAt } from '../backend/domain';
import type { Client } from '../backend/client';
import type { BattleRosterProjection as BattleRoster } from '../backend/module_bindings/types';
import { InstancedModel, ModelLibrary, modelAsset } from './model-assets';
import { BattleTimeline, type Motion } from '../backend/battle-timeline';
import { watchTables } from '../backend/projection-cache';
import { instanceMatrix, instanceColor, flushInstances, takeInstanceUploadBytes } from './instance-buffers';
import { isShipSet } from '../shared/shipSets';
import { createModelEnvironment } from './model-materials';

type GalaxyFleet =
  ReturnType<Client['conn']['db']['galaxyFleets']['iter']> extends Iterable<infer R> ? R : never;

export interface FrameStats {
  fps: number;
  frameP95Ms: number;
  samples: number;
  drawCalls: number;
  objects: number;
  renderer: string;
  mode: string;
}

/** Lab renderer reads the SDK cache directly. React does not render per-ship simulation updates. */
export function LabScene({
  client,
  mode,
  battleId,
  onStats,
}: {
  client: Client;
  mode: 'galaxy' | 'battle';
  battleId: number;
  onStats: (stats: FrameStats) => void;
}) {
  const container = useRef<HTMLDivElement>(null);
  const statsCallback = useRef(onStats);
  statsCallback.current = onStats;
  useEffect(() => {
    const parent = container.current!;
    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
    } catch {
      parent.textContent = 'WebGL ist für die Darstellungsprobe erforderlich.';
      return;
    }
    renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
    renderer.setClearColor(0x070b12);
    parent.appendChild(renderer.domElement);
    renderer.domElement.setAttribute(
      'aria-label',
      mode === 'galaxy' ? 'Instanzierte Galaxiekarte' : 'Live-Gefechtsansicht',
    );
    const scene = new THREE.Scene();
    const extent = mode === 'galaxy' ? 5400 : 230;
    const camera = new THREE.OrthographicCamera(-extent, extent, extent, -extent, 1, 50000);
    camera.position.z = 10000;
    let zoom = 1;
    const resize = () => {
      const { width, height } = parent.getBoundingClientRect();
      renderer.setSize(width, height);
      const aspect = width / Math.max(height, 1);
      camera.left = -extent * aspect;
      camera.right = extent * aspect;
      camera.top = extent;
      camera.bottom = -extent;
      camera.zoom = zoom;
      camera.updateProjectionMatrix();
    };
    const observer = new ResizeObserver(resize);
    observer.observe(parent);
    resize();
    const resources: { dispose(): void }[] = [];
    const modelLibrary = new ModelLibrary();
    const profiler = new RenderProfiler(renderer);
    resources.push(profiler);
    const shipBatches = new Map<string, InstancedModel>();
    resources.push(modelLibrary);
    if (mode === 'battle') {
      renderer.toneMapping = THREE.ACESFilmicToneMapping;
      renderer.toneMappingExposure = 1.05;
      const environment = createModelEnvironment(renderer);
      scene.environment = environment.texture;
      scene.environmentIntensity = 0.35;
      resources.push(environment);
      scene.add(new THREE.HemisphereLight('#e4f1ff', '#27374c', 0.6));
      const light = new THREE.DirectionalLight('#ffffff', 3);
      light.position.set(100, 80, 200);
      scene.add(light);
    }
    const stars = [...client.conn.db.star.iter()];
    if (mode === 'galaxy') {
      const positions = new Float32Array(stars.length * 3),
        colors = new Float32Array(stars.length * 3);
      stars.forEach((s, i) => {
        positions.set([s.x, s.y, 5], i * 3);
        const color = new THREE.Color(
          s.kind === 'rift' ? 0xffba6d : s.kind === 'blackhole' ? 0xc998ff : 0xa6c8df,
        );
        colors.set([color.r, color.g, color.b], i * 3);
      });
      const geometry = new THREE.BufferGeometry();
      geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
      geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
      const material = new THREE.PointsMaterial({
        size: 3.5,
        sizeAttenuation: false,
        vertexColors: true,
        transparent: true,
        opacity: 0.9,
      });
      scene.add(new THREE.Points(geometry, material));
      resources.push(geometry, material);
      // Prepare the field once on the CPU. Fragment shaders perform a single texture lookup,
      // independent of the number of systems (no 1000-star fragment loop).
      const size = 96,
        field = new Float32Array(size * size);
      for (let y = 0; y < size; y++)
        for (let x = 0; x < size; x++) {
          const px = (x / (size - 1) - 0.5) * 11000,
            py = (y / (size - 1) - 0.5) * 11000;
          let potential = 0;
          for (const s of stars)
            potential +=
              (s.kind === 'blackhole' ? 20000 : 2500) / (20000 + (px - s.x) ** 2 + (py - s.y) ** 2);
          field[y * size + x] = potential;
        }
      const texture = new THREE.DataTexture(field, size, size, THREE.RedFormat, THREE.FloatType);
      texture.minFilter = THREE.LinearFilter;
      texture.magFilter = THREE.LinearFilter;
      texture.needsUpdate = true;
      const fieldMaterial = new THREE.ShaderMaterial({
        uniforms: { field: { value: texture } },
        transparent: true,
        depthWrite: false,
        vertexShader:
          'varying vec2 vUv; void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}',
        fragmentShader:
          'uniform sampler2D field; varying vec2 vUv; void main(){float v=texture2D(field,vUv).r*32.;float line=1.-smoothstep(0.025,0.07,abs(fract(v)-0.5)); float mask=smoothstep(0.,0.12,vUv.x)*smoothstep(0.,0.12,vUv.y)*smoothstep(0.,0.12,1.-vUv.x)*smoothstep(0.,0.12,1.-vUv.y);gl_FragColor=vec4(.24,.53,.57,line*.22*mask);}',
      });
      const plane = new THREE.PlaneGeometry(11000, 11000);
      scene.add(new THREE.Mesh(plane, fieldMaterial));
      resources.push(texture, fieldMaterial, plane);
    } else {
      const grid = new THREE.GridHelper(500, 20, 0x243845, 0x11222c);
      grid.rotation.x = Math.PI / 2;
      grid.position.z = -1;
      scene.add(grid);
      resources.push(grid.geometry, ...(Array.isArray(grid.material) ? grid.material : [grid.material]));
    }
    const geometry = new THREE.ConeGeometry(mode === 'galaxy' ? 22 : 1.2, mode === 'galaxy' ? 70 : 4, 3);
    const material = new THREE.MeshBasicMaterial({ color: 0xffffff });
    let capacity = 256;
    const teamGeometry = new THREE.RingGeometry(3, 3.2, 16);
    const teamMaterial = new THREE.MeshBasicMaterial({ transparent: true, opacity: 0.75, depthWrite: false });
    let teamMesh = new THREE.InstancedMesh(teamGeometry, teamMaterial, capacity);
    teamMesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    teamMesh.frustumCulled = false;
    teamMesh.count = 0;
    if (mode === 'battle') scene.add(teamMesh);
    let mesh = new THREE.InstancedMesh(geometry, material, capacity);
    mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    mesh.frustumCulled = false;
    scene.add(mesh);
    const dummy = new THREE.Object3D(),
      color = new THREE.Color();
    let animation = 0,
      previous = performance.now(),
      lastReport = previous,
      frames: number[] = [];
    const allFrames: number[] = [];
    const gl = renderer.getContext(),
      extension = gl.getExtension('WEBGL_debug_renderer_info');
    const rendererName = extension
      ? String(gl.getParameter(extension.UNMASKED_RENDERER_WEBGL))
      : String(gl.getParameter(gl.RENDERER));
    // SDK 2.10 index.find scans its cache. Keep affiliation indexed locally;
    // update it only on subscription changes, never via a nested per-frame scan.
    const rosterById = new Map([...client.conn.db.battleRoster.iter()].map((p) => [p.shipId, p]));
    const rosterInsert = (_ctx: unknown, p: BattleRoster) => {
      rosterById.set(p.shipId, p);
    };
    const rosterUpdate = (_ctx: unknown, _old: BattleRoster, p: BattleRoster) => {
      rosterById.set(p.shipId, p);
    };
    const rosterDelete = (_ctx: unknown, p: BattleRoster) => {
      rosterById.delete(p.shipId);
    };
    client.conn.db.battleRoster.onInsert(rosterInsert);
    client.conn.db.battleRoster.onUpdate(rosterUpdate);
    client.conn.db.battleRoster.onDelete(rosterDelete);
    const timeline = new BattleTimeline();
    let entities: (GalaxyFleet | Motion)[] = [...client.conn.db.galaxyFleets.iter()];
    let appearances = new Map([...client.conn.db.gamePlayers.iter()].map((p) => [p.id, p.shipSet]));
    let battle = client.conn.db.focusedBattle.id.find(battleId);
    let ownerId = [...client.conn.db.myEmpire.iter()][0]?.id;
    const capture = () => {
      battle = client.conn.db.focusedBattle.id.find(battleId);
      entities =
        mode === 'galaxy'
          ? [...client.conn.db.galaxyFleets.iter()]
          : [...client.conn.db.battleMotion.iter()].filter(
              (p) => rosterById.get(p.shipId)?.battleId === battleId,
            );
      if (mode === 'battle') {
        if (battle) timeline.capture(battle.simulatedAt, entities as Motion[], performance.now());
        else timeline.reset();
      }
      appearances = new Map([...client.conn.db.gamePlayers.iter()].map((p) => [p.id, p.shipSet]));
      ownerId = [...client.conn.db.myEmpire.iter()][0]?.id;
    };
    const unwatch = watchTables(
      [
        client.conn.db.focusedBattle,
        client.conn.db.battleMotion,
        client.conn.db.battleRoster,
        client.conn.db.galaxyFleets,
        client.conn.db.gamePlayers,
        client.conn.db.myEmpire,
      ],
      capture,
    );
    capture();
    const motion: Motion = { shipId: 0, x: 0, y: 0, vx: 0, vy: 0 };
    const turn = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1, 0, 0), Math.PI / 2);
    const frustum = new THREE.Frustum(),
      viewProjection = new THREE.Matrix4();
    const bounds = new THREE.Sphere(new THREE.Vector3(), mode === 'battle' ? 5 : 75);
    const animate = () => {
      animation = requestAnimationFrame(animate);
      const time = performance.now(),
        dt = time - previous;
      previous = time;
      if (!document.hidden && dt < 1000) {
        frames.push(dt);
        if (allFrames.length < 18000) allFrames.push(dt);
      }
      if (document.hidden) return;
      const at = client.clock.now(time);
      const target = timeline.frame(at, client.clock.speed, client.clock.paused, battle?.state !== 'active');
      camera.updateMatrixWorld();
      frustum.setFromProjectionMatrix(
        viewProjection.multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse),
      );
      if (entities.length > capacity) {
        scene.remove(mesh);
        mesh.dispose();
        capacity = Math.max(entities.length, capacity * 2);
        mesh = new THREE.InstancedMesh(geometry, material, capacity);
        mesh.frustumCulled = false;
        mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
        scene.add(mesh);
        teamMesh.removeFromParent();
        teamMesh.dispose();
        teamMesh = new THREE.InstancedMesh(teamGeometry, teamMaterial, capacity);
        teamMesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
        teamMesh.frustumCulled = false;
        if (mode === 'battle') scene.add(teamMesh);
      }
      for (const batch of shipBatches.values()) batch.begin();
      let fallbackCount = 0,
        visibleCount = 0;
      entities.forEach((entity) => {
        if ('fromX' in entity) {
          const p = positionAt(entity, at);
          dummy.position.set(p.x, p.y, 10);
          dummy.rotation.set(
            0,
            0,
            Math.atan2(entity.toY - entity.fromY, entity.toX - entity.fromX) - Math.PI / 2,
          );
        } else {
          if (!timeline.sample(entity.shipId, target, motion)) return;
          dummy.position.set(motion.x, motion.y, 10);
          dummy.rotation.set(0, 0, Math.atan2(motion.vy, motion.vx) - Math.PI / 2);
        }
        bounds.center.copy(dummy.position);
        if (!frustum.intersectsSphere(bounds)) return;
        const entityIndex = visibleCount++;
        const own =
          ('empireId' in entity ? entity.empireId : rosterById.get(entity.shipId)?.empireId) === ownerId;
        if (mode === 'battle') {
          dummy.position.z = 9.5;
          dummy.updateMatrix();
          instanceMatrix(teamMesh, entityIndex, dummy.matrix);
          instanceColor(teamMesh, entityIndex, color.set(own ? 0x70efd0 : 0xff9c72));
          dummy.position.z = 10;
        }
        if (mode === 'battle' && 'shipId' in entity) {
          const empireId = rosterById.get(entity.shipId)?.empireId;
          const appearance = empireId === undefined ? undefined : appearances.get(empireId);
          const set = isShipSet(appearance) ? appearance : 'prisma';
          let batch = shipBatches.get(set);
          const asset = modelAsset(set, '01_korvette');
          if (!batch && asset) {
            batch = new InstancedModel(modelLibrary, asset, 5);
            shipBatches.set(set, batch);
            scene.add(batch.group);
            resources.push(batch);
          }
          if (batch?.ready) {
            dummy.quaternion.multiply(turn);
            dummy.updateMatrix();
            batch.add(dummy.matrix);
            return;
          }
        }
        const i = fallbackCount++;
        dummy.updateMatrix();
        instanceMatrix(mesh, i, dummy.matrix);
        instanceColor(mesh, i, color.set(own ? 0x70efd0 : 0xff9c72));
      });
      modelLibrary.setTime(at);
      for (const batch of shipBatches.values()) batch.end(at);
      mesh.count = fallbackCount;
      flushInstances(mesh);
      teamMesh.count = mode === 'battle' ? visibleCount : 0;
      flushInstances(teamMesh);
      profiler.begin();
      profiler.measure('battle-scene', () => renderer.render(scene, camera));
      profiler.end(
        takeInstanceUploadBytes() + [...shipBatches.values()].reduce((n, b) => n + b.uploadBytes, 0),
        { visibleShips: visibleCount, interpolationDelayMs: timeline.delayMs },
      );
      if (time - lastReport >= 1000 && frames.length) {
        const sorted = [...allFrames].sort((a, b) => a - b);
        const stats = {
          fps: 1000 / (frames.reduce((sum, n) => sum + n, 0) / frames.length),
          frameP95Ms: sorted[Math.floor(sorted.length * 0.95)] ?? 0,
          samples: allFrames.length,
          drawCalls: renderer.info.render.calls,
          objects: entities.length,
          renderer: rendererName,
          mode,
        };
        statsCallback.current(stats);
        frames = [];
        lastReport = time;
      }
    };
    let drag: { x: number; y: number } | null = null;
    const down = (event: PointerEvent) => {
      drag = { x: event.clientX, y: event.clientY };
      renderer.domElement.setPointerCapture(event.pointerId);
    };
    const up = () => {
      drag = null;
    };
    const pointer = (event: PointerEvent) => {
      if (!drag) return;
      const scale = (extent * 2) / parent.clientHeight / zoom;
      camera.position.x -= (event.clientX - drag.x) * scale;
      camera.position.y += (event.clientY - drag.y) * scale;
      drag = { x: event.clientX, y: event.clientY };
    };
    const wheel = (event: WheelEvent) => {
      event.preventDefault();
      zoom = Math.max(0.5, Math.min(8, zoom * Math.exp(-event.deltaY * 0.001)));
      resize();
    };
    renderer.domElement.addEventListener('pointerdown', down);
    renderer.domElement.addEventListener('pointermove', pointer);
    renderer.domElement.addEventListener('pointerup', up);
    renderer.domElement.addEventListener('wheel', wheel, { passive: false });
    animate();
    return () => {
      cancelAnimationFrame(animation);
      client.conn.db.battleRoster.removeOnInsert(rosterInsert);
      client.conn.db.battleRoster.removeOnUpdate(rosterUpdate);
      client.conn.db.battleRoster.removeOnDelete(rosterDelete);
      unwatch();
      timeline.reset();
      observer.disconnect();
      mesh.dispose();
      teamMesh.dispose();
      teamGeometry.dispose();
      teamMaterial.dispose();
      geometry.dispose();
      material.dispose();
      resources.forEach((r) => r.dispose());
      renderer.dispose();
      renderer.domElement.remove();
    };
  }, [client, mode, battleId]);
  return <div className="lab-scene" ref={container} />;
}
