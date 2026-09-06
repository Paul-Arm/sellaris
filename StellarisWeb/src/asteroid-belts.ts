import * as THREE from 'three';
import { stableHash, type CelestialBody } from '../shared/celestial';
import type { Disposable } from './system-objects';

const fragmentVertex = `
varying vec2 fragmentUv;
varying vec3 fragmentTint;
void main() {
  fragmentUv = uv;
  fragmentTint = instanceColor;
  gl_Position = projectionMatrix * modelViewMatrix * instanceMatrix * vec4(position, 1.);
}`;

// Soft, luminous capsules use the restrained line language of the gravity contours.
const fragmentShader = `
varying vec2 fragmentUv;
varying vec3 fragmentTint;
void main() {
  vec2 p = fragmentUv * 2. - 1.;
  float distance = length(vec2(max(abs(p.x) - .62, 0.), p.y));
  float aa = max(fwidth(distance), .015);
  float core = 1. - smoothstep(.22 - aa, .22 + aa, distance);
  float glow = exp(-distance * distance * 7.);
  float alpha = core * .65 + glow * .24;
  gl_FragColor = vec4(fragmentTint * (1.1 + core * .5), alpha);
}`;

/** Rare decorative scenery. The mineable anchor keeps its durable slot and has no gravity. */
export function createAsteroidBelt(systemId: string, body: CelestialBody, resources: Disposable[]) {
  const seed = `${systemId}:belt:${body.slot}`;
  // Avalanche adjacent hashes so fragments scatter naturally instead of lining up in tracks.
  const random = (index: number, property: string) => {
    let value = stableHash(`${seed}:${property}:${index}`);
    value = Math.imul(value ^ (value >>> 16), 0x7feb352d);
    value = Math.imul(value ^ (value >>> 15), 0x846ca68b);
    return ((value ^ (value >>> 16)) >>> 0) / 0x100000000;
  };
  const count = 280 + (stableHash(seed) % 120);
  const width = 44 + (stableHash(`${seed}:width`) % 13);
  const geometry = new THREE.PlaneGeometry(2, 2);
  const material = new THREE.ShaderMaterial({
    vertexShader: fragmentVertex,
    fragmentShader,
    transparent: true,
    depthWrite: false,
    side: THREE.DoubleSide,
    blending: THREE.AdditiveBlending,
  });
  const mesh = new THREE.InstancedMesh(geometry, material, count);
  mesh.name = `asteroid-belt-fragments-${body.slot}`;
  const group = new THREE.Group();
  group.name = `asteroid-belt-${body.slot}`;
  group.add(mesh);
  const transform = new THREE.Object3D();
  const axis = new THREE.Vector3(0, 1, 0);
  const pearl = new THREE.Color('#c6dce7');
  const lavender = new THREE.Color('#b9aecf');
  const color = new THREE.Color();
  for (let i = 0; i < count; i++) {
    const angle = ((i + random(i, 'angle')) / count) * Math.PI * 2;
    const radius = body.orbit + (random(i, 'radius-a') + random(i, 'radius-b') - 1) * width * 0.5;
    transform.position.set(
      Math.cos(angle) * radius,
      -4 + (random(i, 'height') - 0.5) * 5,
      Math.sin(angle) * radius,
    );
    transform.rotation.set(-Math.PI / 2, 0, 0);
    transform.rotateOnWorldAxis(axis, -angle - Math.PI / 2);
    transform.scale.set(3 + random(i, 'length') * 5.5, 1.1 + random(i, 'width'), 1);
    transform.updateMatrix();
    mesh.setMatrixAt(i, transform.matrix);
    mesh.setColorAt(
      i,
      color
        .copy(pearl)
        .lerp(lavender, random(i, 'tint') * 0.65)
        .multiplyScalar(0.7 + random(i, 'light') * 0.8),
    );
  }
  mesh.instanceMatrix.needsUpdate = true;
  mesh.instanceColor!.needsUpdate = true;
  mesh.computeBoundingSphere();

  // Broken, hairline arcs tie the fragments together without a solid ring or dusty fill.
  const points: THREE.Vector3[] = [];
  for (let band = 0; band < 2; band++) {
    const radius = body.orbit + (band === 0 ? -1 : 1) * width * 0.42;
    for (let i = 0; i < 360; i++) {
      if (random(Math.floor(i / 30), `arc-${band}`) < 0.5) continue;
      for (const step of [i, i + 1]) {
        const angle = (step / 360) * Math.PI * 2;
        points.push(new THREE.Vector3(Math.cos(angle) * radius, -5, Math.sin(angle) * radius));
      }
    }
  }
  const arcGeometry = new THREE.BufferGeometry().setFromPoints(points);
  const arcMaterial = new THREE.LineBasicMaterial({
    color: '#adc3d8',
    transparent: true,
    opacity: 0.12,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  });
  group.add(new THREE.LineSegments(arcGeometry, arcMaterial));
  resources.push(geometry, material, mesh, arcGeometry, arcMaterial);
  return {
    group,
    mesh,
    animate(t: number) {
      // Three.js rotation about Y has the opposite sign to the orbital X/Z angle.
      group.rotation.y = -(body.phase + (t / body.period) * Math.PI * 2);
    },
  };
}
