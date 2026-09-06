import * as THREE from 'three';
import { stableHash, type CelestialBody } from '../shared/celestial';
import type { Disposable } from './system-objects';

const fragmentVertex = `
varying vec3 fragmentTint;
varying vec3 fragmentPosition;
varying vec3 fragmentNormal;
void main() {
  fragmentTint = instanceColor;
  vec4 world = modelMatrix * instanceMatrix * vec4(position, 1.);
  fragmentPosition = world.xyz;
  vec3 scaleSquared = vec3(dot(instanceMatrix[0].xyz, instanceMatrix[0].xyz),
    dot(instanceMatrix[1].xyz, instanceMatrix[1].xyz), dot(instanceMatrix[2].xyz, instanceMatrix[2].xyz));
  fragmentNormal = normalize(mat3(modelMatrix) * mat3(instanceMatrix) * (normal / scaleSquared));
  gl_Position = projectionMatrix * viewMatrix * world;
}`;

// Smooth abstract bodies with restrained luminous rims, matching the planet markers.
const fragmentShader = `
varying vec3 fragmentTint;
varying vec3 fragmentPosition;
varying vec3 fragmentNormal;
void main() {
  vec3 normal = normalize(fragmentNormal);
  float light = max(0., dot(normal, normalize(vec3(-.4, .7, .6))));
  float facing = max(0., dot(normal, normalize(cameraPosition - fragmentPosition)));
  float rim = pow(1. - facing, 2.8);
  vec3 color = fragmentTint * (.3 + light * .5);
  color += mix(fragmentTint, vec3(.9, .97, 1.), .6) * rim * 1.35;
  gl_FragColor = vec4(color, 1.);
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
  const count = 96 + (stableHash(seed) % 65);
  const width = 96 + (stableHash(`${seed}:width`) % 25);
  const span = 340 + (stableHash(`${seed}:span`) % 81);
  const geometry = new THREE.SphereGeometry(1, 16, 12);
  const material = new THREE.ShaderMaterial({
    vertexShader: fragmentVertex,
    fragmentShader,
  });
  const mesh = new THREE.InstancedMesh(geometry, material, count);
  mesh.name = `asteroid-belt-fragments-${body.slot}`;
  const group = new THREE.Group();
  group.name = `asteroid-belt-${body.slot}`;
  group.add(mesh);
  const transform = new THREE.Object3D();
  const pearl = new THREE.Color('#c6dce7');
  const lavender = new THREE.Color('#b9aecf');
  const color = new THREE.Color();
  for (let i = 0; i < count; i++) {
    // A loose local cloud around the resource anchor, with tapered edges and real height.
    const angle = ((random(i, 'angle-a') + random(i, 'angle-b') - 1) * span * 0.5) / body.orbit;
    let radialOffset = (random(i, 'radius-a') + random(i, 'radius-b') - 1) * width * 0.5;
    if (Math.hypot(radialOffset, angle * body.orbit) < body.radius + 20)
      radialOffset = (radialOffset < 0 ? -1 : 1) * (body.radius + 20);
    const radius = body.orbit + radialOffset;
    transform.position.set(
      Math.cos(angle) * radius,
      -2 + (random(i, 'height-a') + random(i, 'height-b') - 1) * 18,
      Math.sin(angle) * radius,
    );
    transform.rotation.set(random(i, 'rx') * Math.PI, random(i, 'ry') * Math.PI, random(i, 'rz') * Math.PI);
    const size = 0.85 + random(i, 'size') ** 2 * 3;
    transform.scale.set(
      size,
      size * (0.7 + random(i, 'shape-y') * 0.35),
      size * (0.9 + random(i, 'shape-z') * 0.4),
    );
    transform.updateMatrix();
    mesh.setMatrixAt(i, transform.matrix);
    mesh.setColorAt(
      i,
      color
        .copy(pearl)
        .lerp(lavender, random(i, 'tint') * 0.65)
        .multiplyScalar(0.65 + random(i, 'light') * 0.45),
    );
  }
  mesh.instanceMatrix.needsUpdate = true;
  mesh.instanceColor!.needsUpdate = true;
  mesh.computeBoundingSphere();

  resources.push(geometry, material, mesh);
  return {
    group,
    mesh,
    animate(t: number) {
      // Three.js rotation about Y has the opposite sign to the orbital X/Z angle.
      group.rotation.y = -(body.phase + (t / body.period) * Math.PI * 2);
    },
  };
}
