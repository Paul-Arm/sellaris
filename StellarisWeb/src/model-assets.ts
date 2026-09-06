import * as THREE from 'three';
import { GLTFLoader, type GLTF } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { clone } from 'three/examples/jsm/utils/SkeletonUtils.js';
import catalog from './assets/model-catalog.json';
import type { ShipSet } from '../shared/shipSets';
import { ModelSurfaces } from './model-materials';

export interface ModelAsset {
  set: string;
  id: string;
  url: string;
  bytes: number;
  size: number[];
  planetRadius?: number;
  clips: { name: string; duration: number }[];
}
export const MODEL_ASSETS: readonly ModelAsset[] = catalog;
const assetsById = new Map(MODEL_ASSETS.map((asset) => [`${asset.set}/${asset.id}`, asset]));
export function modelAsset(set: ShipSet, id: string): ModelAsset | undefined {
  return assetsById.get(`${set}/${id}`);
}

function releaseScene(scene: THREE.Object3D) {
  const resources = new Set<{ dispose(): void }>();
  const images = new Set<{ close(): void }>();
  scene.traverse((node) => {
    if (!(node instanceof THREE.Mesh)) return;
    resources.add(node.geometry);
    for (const material of Array.isArray(node.material) ? node.material : [node.material]) {
      resources.add(material);
      for (const value of Object.values(material)) {
        if (!(value instanceof THREE.Texture)) continue;
        resources.add(value);
        // GLTFLoader owns ImageBitmap decodes. Texture.dispose only frees GPU
        // storage; close each shared decode once when its library releases it.
        const image = value.source.data;
        if (typeof image?.close === 'function') images.add(image);
      }
    }
  });
  resources.forEach((r) => r.dispose());
  images.forEach((image) => image.close());
}

/** One owner per scene: deduplicates requests and safely releases late loads on navigation. */
export class ModelLibrary {
  private loader = new GLTFLoader();
  private loaded = new Map<string, Promise<GLTF>>();
  private disposed = false;
  private surfaces = new ModelSurfaces();

  setTime(seconds: number) {
    this.surfaces.time.value = seconds;
  }

  load(asset: ModelAsset): Promise<GLTF> {
    if (this.disposed) return Promise.reject(new Error('Model scene was closed.'));
    let promise = this.loaded.get(asset.url);
    if (!promise) {
      promise = this.loader.loadAsync(asset.url).then((gltf) => {
        if (this.disposed) {
          releaseScene(gltf.scene);
          throw new Error('Model scene was closed.');
        }
        try {
          this.surfaces.prepare(gltf.scene, asset.set as ShipSet, Math.max(...asset.size));
        } catch (error) {
          releaseScene(gltf.scene);
          throw error;
        }
        return gltf;
      });
      this.loaded.set(asset.url, promise);
    }
    return promise;
  }

  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this.surfaces.dispose();
    for (const promise of this.loaded.values())
      void promise.then(
        (g) => releaseScene(g.scene),
        () => {},
      );
    this.loaded.clear();
  }
}

export class ModelInstance {
  readonly group = new THREE.Group();
  readonly scene: THREE.Object3D;
  readonly mixer: THREE.AnimationMixer;
  private action?: THREE.AnimationAction;
  private clips: THREE.AnimationClip[];
  private clipName = '';
  constructor(gltf: GLTF, span?: number) {
    this.scene = clone(gltf.scene);
    this.clips = gltf.animations;
    const alignment = new THREE.Group();
    alignment.add(this.scene);
    this.group.add(alignment);
    this.group.updateMatrixWorld(true);
    this.scene.traverse((node) => {
      if (node.name.endsWith('star_center') || node.name.endsWith('planet_center'))
        alignment.position.copy(node.getWorldPosition(new THREE.Vector3())).negate();
    });
    this.mixer = new THREE.AnimationMixer(this.scene);
    if (span) {
      const size = new THREE.Box3().setFromObject(this.scene).getSize(new THREE.Vector3());
      this.group.scale.setScalar(span / Math.max(size.x, size.y, size.z, 0.001));
    }
    this.play(this.clips.find((c) => /idle|loop/i.test(c.name))?.name ?? this.clips[0]?.name);
  }
  play(name?: string) {
    if ((name ?? '') === this.clipName) return;
    this.clipName = name ?? '';
    this.mixer.stopAllAction();
    const clip = this.clips.find((c) => c.name === name);
    this.action = clip ? this.mixer.clipAction(clip).reset().play() : undefined;
  }
  operate(active: boolean) {
    const clip =
      this.clips.find((c) => (active ? /operate/i.test(c.name) : /idle|loop/i.test(c.name))) ?? this.clips[0];
    this.play(clip?.name);
  }
  update(seconds: number) {
    // Absolute simulation time preserves pause/speed and avoids accumulating clock drift.
    if (this.action) this.mixer.setTime(Math.max(0, seconds) % this.action.getClip().duration);
  }
  dispose() {
    this.mixer.stopAllAction();
    this.mixer.uncacheRoot(this.scene);
    this.group.removeFromParent();
  }
}

/** A changing body facility; a late request cannot replace a newer building. */
export class ModelSlot {
  readonly group = new THREE.Group();
  private key = '';
  private generation = 0;
  private instance?: ModelInstance;
  constructor(private library: ModelLibrary) {}
  set(asset: ModelAsset | undefined, span: number, planetRadius?: number) {
    const key = asset ? `${asset.url}:${span}:${planetRadius ?? ''}` : '';
    if (this.key === key) return;
    this.key = key;
    const generation = ++this.generation;
    this.instance?.dispose();
    this.instance = undefined;
    if (!asset) return;
    void this.library
      .load(asset)
      .then((gltf) => {
        if (generation !== this.generation) return;
        const instance = new ModelInstance(gltf, span);
        if (planetRadius && asset.planetRadius)
          instance.group.scale.setScalar(planetRadius / asset.planetRadius);
        this.instance = instance;
        this.group.add(instance.group);
      })
      .catch((error) => {
        if (generation === this.generation)
          console.warn(`Modell konnte nicht geladen werden: ${asset.url}`, error);
      });
  }
  update(seconds: number, operating = false) {
    this.instance?.operate(operating);
    this.instance?.update(seconds);
  }
  get ready() {
    return !!this.instance;
  }
  dispose() {
    this.generation++;
    this.instance?.dispose();
    this.group.removeFromParent();
  }
}

/** CPU picking uses the same ship × animated-part transform as the vertex shader. */
class PartInstances extends THREE.InstancedMesh {
  readonly partTransform = { value: new THREE.Matrix4() };
  readonly partNormal = { value: new THREE.Matrix3() };
  private pickMesh: THREE.Mesh;
  private pickMatrix = new THREE.Matrix4();
  private hits: THREE.Intersection[] = [];
  constructor(part: THREE.Mesh, shared: THREE.InstancedBufferAttribute) {
    const prepare = (source: THREE.Material) => {
      const material = source.clone();
      const compile = source.onBeforeCompile.bind(source);
      const cacheKey = source.customProgramCacheKey();
      material.onBeforeCompile = (shader, renderer) => {
        compile(shader, renderer);
        shader.uniforms.uPartTransform = this.partTransform;
        shader.uniforms.uPartNormal = this.partNormal;
        shader.vertexShader = shader.vertexShader
          .replace(
            '#include <common>',
            '#include <common>\nuniform mat4 uPartTransform;\nuniform mat3 uPartNormal;',
          )
          .replace(
            '#include <begin_vertex>',
            '#include <begin_vertex>\ntransformed = (uPartTransform * vec4(transformed, 1.0)).xyz;',
          )
          .replace(
            '#include <beginnormal_vertex>',
            `#include <beginnormal_vertex>
            objectNormal = uPartNormal * objectNormal;
            #ifdef USE_TANGENT
              objectTangent = mat3(uPartTransform) * objectTangent;
            #endif`,
          );
      };
      material.customProgramCacheKey = () => cacheKey + '/shared-part-v1';
      return material;
    };
    // Hooks are executed by the renderer, after super() has initialized this instance.
    super(
      part.geometry,
      Array.isArray(part.material) ? part.material.map(prepare) : prepare(part.material),
      shared.count,
    );
    this.instanceMatrix = shared;
    this.frustumCulled = false; // instances are culled by the scene before entering the batch
    this.count = 0;
    this.pickMesh = new THREE.Mesh(part.geometry, part.material);
  }
  override raycast(raycaster: THREE.Raycaster, intersects: THREE.Intersection[]) {
    for (let i = 0; i < this.count; i++) {
      this.getMatrixAt(i, this.pickMatrix);
      this.pickMesh.matrixWorld
        .multiplyMatrices(this.matrixWorld, this.pickMatrix)
        .multiply(this.partTransform.value);
      this.pickMesh.raycast(raycaster, this.hits);
      for (const hit of this.hits) {
        hit.instanceId = i;
        hit.object = this;
        intersects.push(hit);
      }
      this.hits.length = 0;
    }
  }
  override dispose() {
    super.dispose();
    for (const m of Array.isArray(this.material) ? this.material : [this.material]) m.dispose();
    return this;
  }
}

/** A single ship-transform attribute is shared by every rigid GLB part. Part animation
 * is a uniform, so neither CPU multiplication nor matrix uploads scale with part count. */
export class InstancedModel {
  readonly group = new THREE.Group();
  readonly meshes: PartInstances[] = [];
  private prototype?: ModelInstance;
  private parts: THREE.Mesh[] = [];
  private fleetIds: string[] = [];
  private disposed = false;
  private capacity = 0;
  private count = 0;
  private shared = new THREE.InstancedBufferAttribute(new Float32Array(0), 16);
  private dirtyStart = Infinity;
  private dirtyEnd = 0;
  uploadBytes = 0;
  constructor(library: ModelLibrary, asset: ModelAsset, span: number) {
    void library
      .load(asset)
      .then((gltf) => {
        if (this.disposed) return;
        this.prototype = new ModelInstance(gltf, span);
        this.prototype.scene.traverse((node) => {
          if (node instanceof THREE.Mesh) this.parts.push(node);
        });
        this.resize(128);
      })
      .catch((error) => {
        if (!this.disposed) console.warn(`Schiffsmodell konnte nicht geladen werden: ${asset.url}`, error);
      });
  }
  private resize(capacity: number) {
    const previous = this.shared;
    for (const mesh of this.meshes) {
      mesh.removeFromParent();
      mesh.dispose();
    }
    this.meshes.length = 0;
    this.capacity = capacity;
    this.shared = new THREE.InstancedBufferAttribute(new Float32Array(capacity * 16), 16).setUsage(
      THREE.DynamicDrawUsage,
    );
    this.shared.array.set(previous.array);
    this.dirtyStart = 0;
    this.dirtyEnd = this.count * 16;
    for (const part of this.parts) {
      const mesh = new PartInstances(part, this.shared);
      mesh.userData.fleets = this.fleetIds;
      this.meshes.push(mesh);
      this.group.add(mesh);
    }
  }
  get ready() {
    return !!this.prototype;
  }
  begin() {
    this.count = 0;
    this.uploadBytes = 0;
  }
  add(matrix: THREE.Matrix4, fleetId = '') {
    if (!this.prototype) return;
    if (this.count >= this.capacity) this.resize(this.capacity * 2);
    const index = this.count++,
      offset = index * 16;
    let changed = false;
    for (let i = 0; i < 16; i++) {
      const value = Math.fround(matrix.elements[i]);
      if (this.shared.array[offset + i] !== value) {
        this.shared.array[offset + i] = value;
        changed = true;
      }
    }
    if (changed) {
      this.dirtyStart = Math.min(this.dirtyStart, offset);
      this.dirtyEnd = Math.max(this.dirtyEnd, offset + 16);
    }
    this.fleetIds[index] = fleetId;
  }
  end(days: number, operating = false) {
    if (!this.prototype) return;
    this.group.visible = this.count > 0;
    for (const mesh of this.meshes) mesh.count = this.count;
    if (!this.count) return;
    this.prototype.operate(operating);
    this.prototype.update(days);
    this.prototype.group.updateMatrixWorld(true);
    for (let p = 0; p < this.meshes.length; p++) {
      this.meshes[p].partTransform.value.copy(this.parts[p].matrixWorld);
      this.meshes[p].partNormal.value.getNormalMatrix(this.parts[p].matrixWorld);
    }
    if (this.dirtyEnd > this.dirtyStart) {
      const count = this.dirtyEnd - this.dirtyStart;
      this.shared.addUpdateRange(this.dirtyStart, count);
      this.shared.needsUpdate = true;
      this.uploadBytes = count * 4;
    }
    this.dirtyStart = Infinity;
    this.dirtyEnd = 0;
  }
  dispose() {
    this.disposed = true;
    this.prototype?.dispose();
    this.meshes.forEach((m) => m.dispose());
    this.group.removeFromParent();
  }
}
