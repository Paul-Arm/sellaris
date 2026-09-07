import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import type { CelestialBody } from '../shared/celestial';
import { bodyVertex, bodyFragment, coronaFragment } from './system-shaders';
import { createStellarBody } from './stellar-objects';

export type Disposable = { dispose(): void };
export function shipGeometry(kind: string) {
  const hull = new THREE.BoxGeometry(3, 2, 17),
    nose = new THREE.ConeGeometry(2.2, 7, 4);
  nose.rotateX(-Math.PI / 2);
  nose.translate(0, 0, -11);
  const wing = new THREE.BoxGeometry(kind === 'colony' ? 10 : 12, 1, kind === 'colony' ? 11 : 4);
  wing.translate(0, 0, 4);
  const deck = new THREE.BoxGeometry(2, 2, 5);
  deck.translate(0, 1.5, 0);
  const parts: THREE.BufferGeometry[] = [hull, nose, wing, deck];
  if (kind === 'scout') {
    const dish = new THREE.TorusGeometry(3, 0.5, 4, 12);
    dish.rotateX(Math.PI / 2);
    dish.translate(0, 3, 1);
    parts.push(dish);
  }
  const result = mergeGeometries(parts)!;
  parts.forEach((p) => p.dispose());
  return result;
}

export function createBody(body: CelestialBody, resources: Disposable[], time: { value: number }) {
  if (body.megastructure) {
    const group = new THREE.Group(),
      tint = new THREE.Color(body.color);
    const geo = new THREE.TorusGeometry(body.radius * 2, 0.7, 6, 80);
    const material = new THREE.MeshBasicMaterial({ color: tint, transparent: true, opacity: 0.55 });
    const core = new THREE.Mesh(geo, material);
    core.rotation.x = Math.PI / 2;
    core.userData.slot = body.slot;
    group.add(core);
    resources.push(geo, material);
    if (body.megastructure === 'decompressor') {
      // Twin polar collectors leave the accretion disk and event horizon visible.
      const beamGeo = new THREE.CylinderGeometry(
          body.radius * 0.055,
          body.radius * 0.13,
          body.radius * 3.4,
          12,
        ),
        beamMat = new THREE.MeshBasicMaterial({
          color: tint,
          transparent: true,
          opacity: 0.22,
          depthWrite: false,
          blending: THREE.AdditiveBlending,
        });
      resources.push(beamGeo, beamMat);
      for (const sign of [-1, 1]) {
        const beam = new THREE.Mesh(beamGeo, beamMat);
        beam.position.y = sign * body.radius * 2.3;
        beam.userData.slot = body.slot;
        group.add(beam);
      }
      core.rotation.x = 0;
      core.position.y = body.radius * 2.6;
      return {
        group,
        core,
        tint,
        animate: (t: number) => {
          core.rotation.z = t * 0.07;
          beamMat.opacity = 0.2 + Math.sin(t * 1.4) * 0.035;
        },
      };
    }
    return { group, core, tint, animate: (_t: number) => {} };
  }
  if (body.stellar && body.kind !== 'rift') return createStellarBody(body, resources, time);
  const group = new THREE.Group();
  const tint = new THREE.Color(body.kind === 'rift' ? '#ffb65f' : body.color);
  const geo =
    body.kind === 'ruin'
      ? new THREE.TorusGeometry(body.radius, 1.6, 5, 48, Math.PI * 1.65)
      : body.kind === 'asteroid'
        ? new THREE.SphereGeometry(body.radius * 0.55, 24, 16)
        : new THREE.SphereGeometry(body.radius, 48, 32);
  const material = new THREE.ShaderMaterial({
    vertexShader: bodyVertex,
    fragmentShader: bodyFragment,
    uniforms: {
      tint: { value: tint },
      time,
      style: { value: body.kind === 'rift' ? 3 : body.kind === 'gas' ? 2 : 0 },
    },
  });
  resources.push(geo, material);
  const core = new THREE.Mesh(geo, material);
  core.userData.slot = body.slot;
  if (body.kind === 'rift') core.scale.set(2.4, 0.1, 0.18);
  if (body.kind === 'asteroid') core.scale.set(1, 0.72, 1.2);
  if (body.kind === 'ruin') core.rotation.set(0.5, 0.2, -0.7);
  group.add(core);
  if (body.kind === 'ruin' || body.kind === 'asteroid') {
    const shardGeo =
      body.kind === 'asteroid' ? new THREE.SphereGeometry(1.8, 12, 8) : new THREE.OctahedronGeometry(3, 0);
    resources.push(shardGeo);
    for (let i = 0; i < 7; i++) {
      const shard = new THREE.Mesh(shardGeo, material),
        a = i * 2.4;
      shard.position.set(
        Math.cos(a) * (body.radius + 8),
        Math.sin(a * 2) * 8,
        Math.sin(a) * (body.radius + 8),
      );
      shard.rotation.set(i, 0.2 * i, i * 0.7);
      group.add(shard);
    }
  }
  if (body.kind === 'rift') {
    const coronaGeo = new THREE.PlaneGeometry(body.radius * 6, body.radius * 6);
    const coronaMat = new THREE.ShaderMaterial({
      vertexShader:
        'varying vec2 vUv; void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}',
      fragmentShader: coronaFragment,
      uniforms: {
        tint: { value: tint.clone().multiplyScalar(2) },
        time,
        rift: { value: 1 },
      },
      side: THREE.DoubleSide,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });
    resources.push(coronaGeo, coronaMat);
    const corona = new THREE.Mesh(coronaGeo, coronaMat);
    corona.rotation.x = -Math.PI / 2;
    corona.position.y = -body.radius * 0.4;
    corona.scale.set(1.7, 1, 1);
    group.add(corona);
  }
  if (body.kind === 'gas') {
    const ringGeo = new THREE.RingGeometry(body.radius * 1.4, body.radius * 1.9, 100);
    const ringMat = new THREE.MeshBasicMaterial({
      color: tint,
      side: THREE.DoubleSide,
      transparent: true,
      opacity: 0.3,
    });
    resources.push(ringGeo, ringMat);
    const ring = new THREE.Mesh(ringGeo, ringMat);
    ring.rotation.x = -Math.PI / 2 + 0.16;
    group.add(ring);
  }
  return { group, core, tint, animate: (_t: number) => {} };
}

export function lineLoop(
  radius: number,
  resources: Disposable[],
  color: string,
  opacity: number,
  start = 0,
  arc = Math.PI * 2,
) {
  const points = Array.from({ length: 161 }, (_, i) => {
    const a = start + (i / 160) * arc;
    return new THREE.Vector3(Math.cos(a) * radius, 0, Math.sin(a) * radius);
  });
  const geo = new THREE.BufferGeometry().setFromPoints(points);
  const mat = new THREE.LineBasicMaterial({ color, transparent: true, opacity });
  resources.push(geo, mat);
  return new THREE.Line(geo, mat);
}
