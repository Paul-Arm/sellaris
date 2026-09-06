import * as THREE from 'three';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';
import type { ShipSet } from '../shared/shipSets';

/** Reflection light only; the room itself is never added to the game scene. */
export function createModelEnvironment(renderer: THREE.WebGLRenderer) {
  const room = new RoomEnvironment();
  const generator = new THREE.PMREMGenerator(renderer);
  const target = generator.fromScene(room, 0.04);
  room.dispose();
  generator.dispose();
  return target;
}

/** Finishes and the shader clock are shared per scene, not allocated per ship. */
export class ModelSurfaces {
  readonly time = { value: 0 };
  private prepared = new WeakSet<THREE.Object3D>();
  private disposed = false;

  prepare(scene: THREE.Object3D, _set: ShipSet, span: number) {
    if (this.disposed || this.prepared.has(scene)) return;
    this.prepared.add(scene);
    const materials = new Set<THREE.MeshStandardMaterial>();
    const replacedMaterials = new Set<THREE.MeshStandardMaterial>();
    const effects = new Map<THREE.MeshStandardMaterial, THREE.Box3>();
    scene.traverse((node) => {
      if (!(node instanceof THREE.Mesh)) return;
      // Effect meshes share an emissive material with solid engine apertures in the
      // source GLBs. Give only the exhaust/weapon flashes a soft, additive finish.
      const copy = (material: THREE.Material) => {
        if (!(material instanceof THREE.MeshStandardMaterial)) return material;
        if (!/^FX_/i.test(node.name) && material.userData.conceptRole !== 'plume') return material;
        const clone = material.clone();
        replacedMaterials.add(material);
        node.geometry.computeBoundingBox();
        effects.set(clone, node.geometry.boundingBox!.clone());
        return clone;
      };
      node.material = Array.isArray(node.material) ? node.material.map(copy) : copy(node.material);
      const list = Array.isArray(node.material) ? node.material : [node.material];
      for (const material of list)
        if (material instanceof THREE.MeshStandardMaterial) materials.add(material);
    });
    for (const old of replacedMaterials) if (!materials.has(old)) old.dispose();
    for (const material of materials) {
      this.conceptFinish(material, span, effects.get(material));
      material.needsUpdate = true;
    }
  }

  /** Blender owns the palette and finish. Only light fields and exhaust animate here. */
  private conceptFinish(material: THREE.MeshStandardMaterial, span: number, effect?: THREE.Box3) {
    const role = material.userData.conceptRole;
    material.envMapIntensity = role === 'plasma' ? 0.03 : role === 'energy' || effect ? 0.18 : 0.7;
    if (effect) {
      material.transparent = true;
      material.depthWrite = false;
      material.forceSinglePass = true;
      material.blending = THREE.AdditiveBlending;
      material.opacity *= 0.72;
    } else if (material.transparent) {
      material.depthWrite = false;
    }
    if (role === 'plasma') this.plasmaShader(material, span);
    else if (role === 'energy' || role === 'plume' || role === 'field' || effect)
      this.energyShader(material, span, effect);
  }

  private plasmaShader(material: THREE.MeshStandardMaterial, span: number) {
    material.metalness = 0;
    material.roughness = 0.85;
    if (material instanceof THREE.MeshPhysicalMaterial) {
      material.clearcoat = 0;
      material.specularIntensity = 0.05;
    }
    material.onBeforeCompile = (shader) => {
      shader.uniforms.uSurfaceTime = this.time;
      shader.uniforms.uPlasmaScale = { value: 16 / Math.max(span, 0.001) };
      // The standard emissive-map chunk already includes authored intensity.
      shader.uniforms.uPlasmaStrength = {
        value: material.emissiveMap ? 1 : Number(material.userData.conceptPlasmaStrength ?? 1.65),
      };
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', '#include <common>\nvarying vec3 vPlasmaPosition;')
        .replace('#include <begin_vertex>', '#include <begin_vertex>\nvPlasmaPosition = position;');
      shader.fragmentShader = shader.fragmentShader
        .replace(
          '#include <common>',
          `#include <common>
          varying vec3 vPlasmaPosition;
          uniform float uSurfaceTime;
          uniform float uPlasmaScale;
          uniform float uPlasmaStrength;`,
        )
        .replace('#include <color_fragment>', '#include <color_fragment>\ndiffuseColor.rgb *= 0.08;')
        .replace(
          '#include <emissivemap_fragment>',
          `#include <emissivemap_fragment>
          // Detailed clouds can be baked onto low-poly lenses. The standard
          // chunk above has already sampled and decoded the emissive texture.
          vec3 plasmaColor = emissive;
          #if defined(USE_EMISSIVEMAP)
            plasmaColor = totalEmissiveRadiance;
          #elif defined(USE_COLOR) || defined(USE_COLOR_ALPHA)
            plasmaColor = vColor.rgb;
          #endif
          vec3 p = vPlasmaPosition * uPlasmaScale;
          float drift = sin(p.x * 2.2 + sin(p.y * 2.8 + uSurfaceTime * 0.18)
            + p.z * 1.7 - uSurfaceTime * 0.27);
          float rim = pow(1.0 - abs(dot(normal, normalize(vViewPosition))), 3.0);
          totalEmissiveRadiance = plasmaColor * uPlasmaStrength * (0.94 + 0.06 * drift)
            + vec3(0.005, 0.20, 0.55) * rim;
        `,
        );
    };
    material.customProgramCacheKey = () => 'concept-plasma-v3';
  }

  private energyShader(material: THREE.MeshStandardMaterial, span: number, effect?: THREE.Box3) {
    const vertexEmission = material.userData.conceptVertexEmission === true;
    material.onBeforeCompile = (shader) => {
      shader.uniforms.uSurfaceTime = this.time;
      shader.uniforms.uSurfaceScale = { value: 12 / Math.max(span, 0.001) };
      if (effect)
        shader.uniforms.uEffectBounds = {
          value: new THREE.Vector2(effect.min.z, Math.max(effect.max.z - effect.min.z, 0.001)),
        };
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', '#include <common>\nvarying vec3 vEnergyPosition;')
        .replace('#include <begin_vertex>', '#include <begin_vertex>\nvEnergyPosition = position;');
      shader.fragmentShader = shader.fragmentShader
        .replace(
          '#include <common>',
          '#include <common>\nvarying vec3 vEnergyPosition;\nuniform float uSurfaceTime;\nuniform float uSurfaceScale;\nuniform vec2 uEffectBounds;',
        )
        .replace(
          '#include <emissivemap_fragment>',
          `#include <emissivemap_fragment>
          ${
            vertexEmission
              ? `#if defined(USE_COLOR) || defined(USE_COLOR_ALPHA)
            totalEmissiveRadiance *= vColor.rgb;
          #endif`
              : ''
          }
          float energyFlow = sin(vEnergyPosition.z * uSurfaceScale * 3.0 - uSurfaceTime * 2.4);
          float energyRim = pow(1.0 - abs(dot(normal, normalize(vViewPosition))), 2.0);
          totalEmissiveRadiance *= 0.9 + 0.06 * energyFlow + 0.1 * energyRim;
        `,
        );
      if (effect)
        shader.fragmentShader = shader.fragmentShader.replace(
          '#include <opaque_fragment>',
          `
        float alongPlume = clamp((vEnergyPosition.z - uEffectBounds.x) / uEffectBounds.y, 0.0, 1.0);
        diffuseColor.a *= (1.0 - smoothstep(0.15, 1.0, alongPlume)) * (0.35 + 0.65 * abs(dot(normal, normalize(vViewPosition))));
        #include <opaque_fragment>
      `,
        );
    };
    material.customProgramCacheKey = () => `concept-${effect ? 'plume' : 'energy'}-${vertexEmission}-v3`;
  }

  dispose() {
    this.disposed = true;
  }
}
