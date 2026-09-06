import * as THREE from 'three';
import type { CelestialBody } from '../shared/celestial';
import { bodyVertex } from './system-shaders';

const surface = `
uniform vec3 tint;
uniform float emission, compact, time, starRadius;
varying vec3 localP, worldP, worldN;
float hash(vec3 p){ return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise(vec3 p){
  vec3 i=floor(p), f=fract(p); f=f*f*(3.-2.*f);
  return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
    mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void main(){
  vec3 p=normalize(localP);
  float facing=clamp(dot(normalize(worldN),normalize(cameraPosition-worldP)),0.,1.);
  vec3 flow=p*8.+vec3(time*.015,0.,time*.01);
  float cells=noise(flow)*.65+noise(flow*3.1)*.35;
  float grain=noise(p*95.+vec3(0.,time*.025,0.));
  float veins=1.-smoothstep(.015,.085,abs(cells-.48));
  float limb=.58+.42*pow(facing,.32);
  vec3 color=mix(tint,vec3(1.),.26)*emission*limb*(.79+cells*.21+grain*.05);
  color+=tint*veins*.07;
  if(compact>.5){
    float poles=pow(abs(p.y),14.);
    color=mix(tint,vec3(1.),.25)*emission*(.65+.3*facing)+tint*poles*.32;
    color+=tint*pow(1.-facing,3.)*.25;
  }
  // Keep a readable photosphere close up; the small overview disc needs more HDR energy.
  float cameraDistance=length(cameraPosition-worldP)/starRadius;
  float glowGain=mix(1.08,1.55,smoothstep(10.,35.,cameraDistance));
  gl_FragColor=vec4(color*glowGain,1.);
}`;

const corona = `
uniform vec3 tint;
uniform float time, strength;
varying vec2 vUv;
void main(){
  vec2 p=(vUv-.5)*2.; float r=length(p), a=atan(p.y,p.x);
  float curl=sin(a*9.+sin(a*4.-time*.08)+time*.1)*.009;
  // The photosphere ends at r=1/2.3; keep the corona attached to that silhouette.
  float rim=exp(-abs(r-.445-curl)*65.);
  float strands=pow(.5+.5*sin(a*27.+sin(a*5.)-r*14.-time*.15),5.);
  float wisps=exp(-abs(r-.51-curl)*20.)*strands;
  float haze=exp(-max(0.,r-.435)*9.)*smoothstep(.38,.45,r);
  float light=(rim*.8+wisps*.3+haze*.26)*strength;
  gl_FragColor=vec4(tint*1.8,light*(1.-smoothstep(.8,1.,r)));
}`;

const jet = `
uniform vec3 tint;
uniform float time;
varying vec2 vUv;
varying vec3 jetP, jetN;
void main(){
  float y=clamp(vUv.y,0.,1.);
  float flow=.87+.13*sin(y*35.-time*1.8);
  float fade=pow(1.-y,1.3)*smoothstep(0.,.07,y);
  float volume=pow(clamp(abs(dot(normalize(jetN),normalize(cameraPosition-jetP))),0.,1.),.7);
  gl_FragColor=vec4(tint*1.25,fade*.26*flow*volume);
}`;
// Camera-facing optical glow, centered on the sphere and still depth-tested against bodies.
const coronaVertex = `
varying vec2 vUv;
void main(){
  vUv=uv;
  vec4 center=modelViewMatrix*vec4(0.,0.,0.,1.);
  center.xy+=position.xy;
  gl_Position=projectionMatrix*center;
}`;

/** Stellar geometry and picking anchors. Black holes are rendered by BlackHolePass. */
export function createStellarBody(
  body: CelestialBody,
  resources: { dispose(): void }[],
  time: { value: number },
) {
  const profile = body.stellar!;
  const group = new THREE.Group(),
    axis = new THREE.Group();
  const tint = new THREE.Color(profile.spill),
    surfaceTint = new THREE.Color(profile.color);
  const hole = profile.family === 'blackhole' || profile.family === 'quasar';
  const compact = profile.family === 'neutron' || profile.family === 'pulsar';
  const shader = (
    fragmentShader: string,
    uniforms: Record<string, THREE.IUniform>,
    transparent = false,
    vertexShader = bodyVertex,
  ) => {
    const m = new THREE.ShaderMaterial({
      vertexShader,
      fragmentShader,
      uniforms,
      transparent,
      depthWrite: !transparent,
      side: transparent ? THREE.DoubleSide : THREE.FrontSide,
      blending: transparent ? THREE.AdditiveBlending : THREE.NormalBlending,
    });
    resources.push(m);
    return m;
  };
  const mesh = (geometry: THREE.BufferGeometry, material: THREE.Material, parent: THREE.Object3D = group) => {
    resources.push(geometry);
    const m = new THREE.Mesh(geometry, material);
    parent.add(m);
    return m;
  };
  // Keep the strategic selection volume, but do not draw a sphere over the ray-traced image.
  const coreMaterial = hole
    ? new THREE.MeshBasicMaterial({ visible: false })
    : shader(surface, {
        tint: { value: surfaceTint },
        emission: { value: profile.emission },
        starRadius: { value: body.radius },
        compact: { value: compact ? 1 : 0 },
        time,
      });
  if (hole) resources.push(coreMaterial);
  const core = mesh(new THREE.SphereGeometry(body.radius, 64, 48), coreMaterial);
  core.userData.slot = body.slot;
  group.add(axis);
  axis.rotation.z = hole ? 0.28 : 0.42;

  if (!hole) {
    mesh(
      new THREE.PlaneGeometry(body.radius * 4.6, body.radius * 4.6),
      shader(
        corona,
        { tint: { value: surfaceTint }, strength: { value: profile.corona }, time },
        true,
        coronaVertex,
      ),
    );
  }
  if (compact) {
    const magneticMat = new THREE.LineBasicMaterial({
      color: surfaceTint,
      transparent: true,
      opacity: 0.16,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });
    resources.push(magneticMat);
    for (let j = 0; j < 8; j++) {
      const az = (j * Math.PI) / 4;
      const points = Array.from({ length: 97 }, (_, i) => {
        const a = (i / 96) * Math.PI * 2,
          r = body.radius * (1.4 + 2.8 * Math.sin(a) ** 2);
        return new THREE.Vector3(
          Math.sin(a) * Math.cos(az) * r,
          Math.cos(a) * r,
          Math.sin(a) * Math.sin(az) * r,
        );
      });
      const geo = new THREE.BufferGeometry().setFromPoints(points);
      resources.push(geo);
      axis.add(new THREE.Line(geo, magneticMat));
    }
  }
  if (profile.family === 'pulsar' || profile.family === 'quasar') {
    const length = profile.family === 'quasar' ? 340 : 220;
    const jets = new THREE.Group();
    if (!hole) jets.rotation.z = 0.35;
    axis.add(jets);
    const material = shader(
      jet,
      { tint: { value: new THREE.Color('#a7dfff') }, time },
      true,
      'varying vec2 vUv; varying vec3 jetP,jetN; void main(){vUv=uv;jetP=(modelMatrix*vec4(position,1.)).xyz;jetN=normalize(mat3(modelMatrix)*normal);gl_Position=projectionMatrix*viewMatrix*vec4(jetP,1.);}',
    );
    for (const sign of [-1, 1]) {
      const beam = mesh(
        new THREE.CylinderGeometry(hole ? 25 : 17, 1.2, length, 32, 24, true),
        material,
        jets,
      );
      beam.position.y = sign * (length / 2 + body.radius * 0.6);
      if (sign < 0) beam.rotation.z = Math.PI;
      const spine = mesh(new THREE.CylinderGeometry(2.5, 0.7, length * 0.9, 16, 1, true), material, jets);
      spine.position.y = sign * (length * 0.45 + body.radius * 0.6);
      if (sign < 0) spine.rotation.z = Math.PI;
    }
  }
  return {
    group,
    core,
    tint,
    animate: (t: number) => {
      core.rotation.y = t * (compact ? 0.08 : 0.006);
      if (profile.family === 'pulsar') axis.rotation.y = t * 0.5;
    },
  };
}
