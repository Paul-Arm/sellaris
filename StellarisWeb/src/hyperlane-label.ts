import * as THREE from 'three';
import { PORTAL_FRONT_END, foldSurfacePoint, surfaceHeight } from './spacetime-surface';

const ARC_SEGMENTS = 64;
const RADIAL_SEGMENTS = 4;

/** Text follows an arc on the same moving sheet as the portal, including its picking geometry. */
export class HyperlaneLabel {
  readonly mesh: THREE.Mesh<THREE.PlaneGeometry, THREE.MeshBasicMaterial>;
  readonly button = document.createElement('button');
  readonly anchor = new THREE.Vector3();
  private readonly texture: THREE.CanvasTexture;
  private readonly domain: Float32Array;
  private readonly radius: number;
  private readonly bearing: number;
  private readonly left = new THREE.Vector3();
  private readonly right = new THREE.Vector3();
  private reversed = false;

  constructor(root: HTMLElement, id: string, name: string, mouth: THREE.Vector4, activate: () => void) {
    const canvas = document.createElement('canvas');
    const context = canvas.getContext('2d')!;
    const font = '500 64px "Segoe UI", sans-serif';
    context.font = font;
    const textWidth = context.measureText(name).width;
    canvas.width = Math.ceil(textWidth + 48);
    canvas.height = 112;
    context.font = font;
    context.fillStyle = '#ffffff';
    context.textAlign = 'center';
    context.textBaseline = 'middle';
    context.fillText(name, canvas.width / 2, canvas.height / 2);
    this.texture = new THREE.CanvasTexture(canvas);
    this.texture.colorSpace = THREE.SRGBColorSpace;
    this.texture.anisotropy = 8;
    this.texture.center.set(0.5, 0.5);
    this.radius = Math.max(280, Math.hypot(mouth.x, mouth.y) - PORTAL_FRONT_END - 55);
    this.bearing = Math.atan2(mouth.y, mouth.x);
    const width = Math.min(780, Math.max(240, canvas.width * 1.35), this.radius * 0.82);
    const height = (width * canvas.height) / canvas.width;
    const geometry = new THREE.PlaneGeometry(width, height, ARC_SEGMENTS, RADIAL_SEGMENTS);
    const positions = geometry.attributes.position as THREE.BufferAttribute;
    this.domain = new Float32Array(positions.count * 2);
    for (let i = 0; i < positions.count; i++) {
      const angle = this.bearing + positions.getX(i) / this.radius;
      const radius = this.radius + positions.getY(i);
      this.domain[i * 2] = Math.cos(angle) * radius;
      this.domain[i * 2 + 1] = Math.sin(angle) * radius;
    }
    positions.setUsage(THREE.DynamicDrawUsage);
    const material = new THREE.MeshBasicMaterial({
      map: this.texture,
      color: '#b3dcd5',
      transparent: true,
      depthWrite: false,
      side: THREE.DoubleSide,
      toneMapped: false,
    });
    this.mesh = new THREE.Mesh(geometry, material);
    this.mesh.userData.destination = id;
    this.mesh.name = `Hyperlane nach ${name}`;
    this.button.type = 'button';
    this.button.className = 'surface-exit-target';
    this.button.textContent = `Hyperlane nach ${name}: System ansehen`;
    this.button.onclick = activate;
    root.append(this.button);
  }

  update(
    wells: THREE.Vector4[],
    mouths: THREE.Vector4[],
    heights: Float32Array,
    camera: THREE.Camera,
    hover: boolean,
  ) {
    const positions = this.mesh.geometry.attributes.position;
    for (let i = 0; i < positions.count; i++) {
      const x = this.domain[i * 2],
        z = this.domain[i * 2 + 1];
      const point = foldSurfacePoint({ x, y: surfaceHeight(x, z, wells, mouths) + 2, z }, mouths, heights);
      positions.setXYZ(i, point.x, point.y, point.z);
    }
    positions.needsUpdate = true;
    this.mesh.geometry.computeBoundingSphere();
    const x = Math.cos(this.bearing) * this.radius,
      z = Math.sin(this.bearing) * this.radius;
    const center = foldSurfacePoint({ x, y: surfaceHeight(x, z, wells, mouths) + 2, z }, mouths, heights);
    this.anchor.set(center.x, center.y, center.z);
    // Rotate the texture by half a turn when viewing from the other side. Geometry stays on the sheet.
    const middleRow = (RADIAL_SEGMENTS / 2) * (ARC_SEGMENTS + 1);
    this.left.fromBufferAttribute(positions, middleRow).project(camera);
    this.right.fromBufferAttribute(positions, middleRow + ARC_SEGMENTS).project(camera);
    const horizontal = this.right.x - this.left.x;
    if (Math.abs(horizontal) > 0.015) this.reversed = horizontal < 0;
    this.texture.rotation = this.reversed ? Math.PI : 0;
    this.mesh.material.color.set(hover || document.activeElement === this.button ? '#ffffff' : '#b3dcd5');
  }

  dispose() {
    this.button.remove();
    this.mesh.removeFromParent();
    this.mesh.geometry.dispose();
    this.mesh.material.dispose();
    this.texture.dispose();
  }
}
