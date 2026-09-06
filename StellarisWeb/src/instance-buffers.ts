import * as THREE from 'three';

/** Dirty occupied spans only. Static formations and unchanged affiliations do not upload. */
const dirty = new WeakMap<THREE.BufferAttribute, [number, number]>();
let uploaded = 0;
export function takeInstanceUploadBytes() {
  const bytes = uploaded;
  uploaded = 0;
  return bytes;
}
function write(attribute: THREE.BufferAttribute, offset: number, values: ArrayLike<number>, length: number) {
  let changed = false;
  for (let i = 0; i < length; i++) {
    const value = Math.fround(values[i]);
    if (attribute.array[offset + i] !== value) {
      attribute.array[offset + i] = value;
      changed = true;
    }
  }
  if (changed) {
    const span = dirty.get(attribute);
    dirty.set(attribute, [Math.min(span?.[0] ?? offset, offset), Math.max(span?.[1] ?? 0, offset + length)]);
  }
  return changed;
}
const rgb = new Float32Array(3);
export function instanceMatrix(mesh: THREE.InstancedMesh, index: number, matrix: THREE.Matrix4) {
  if (write(mesh.instanceMatrix, index * 16, matrix.elements, 16)) mesh.boundingSphere = null;
}
export function instanceColor(mesh: THREE.InstancedMesh, index: number, color: THREE.Color) {
  if (!mesh.instanceColor)
    mesh.instanceColor = new THREE.InstancedBufferAttribute(
      new Float32Array(mesh.instanceMatrix.count * 3),
      3,
    ).setUsage(THREE.DynamicDrawUsage);
  rgb[0] = color.r;
  rgb[1] = color.g;
  rgb[2] = color.b;
  write(mesh.instanceColor, index * 3, rgb, 3);
}
export function flushInstances(mesh: THREE.InstancedMesh) {
  let bytes = 0;
  for (const attribute of [mesh.instanceMatrix, mesh.instanceColor]) {
    if (!attribute) continue;
    const span = dirty.get(attribute);
    if (!span) continue;
    attribute.addUpdateRange(span[0], span[1] - span[0]);
    attribute.needsUpdate = true;
    bytes += (span[1] - span[0]) * 4;
    dirty.delete(attribute);
  }
  uploaded += bytes;
  return bytes;
}
