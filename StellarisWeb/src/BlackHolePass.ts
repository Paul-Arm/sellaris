import * as THREE from 'three';
import { Pass, FullScreenQuad } from 'three/examples/jsm/postprocessing/Pass.js';
import { CRITICAL_IMPACT, DISK_INNER_RADIUS, DISK_OUTER_RADIUS, geodesicGLSL } from './black-hole-geodesic';

const fragmentShader = `
uniform sampler2D tDiffuse, tDepth, tBackdrop, tBackdropDepth;
uniform mat4 inverseProjection, cameraWorld, viewProjection;
uniform vec3 holeCenter, diskNormal, diskAxis;
uniform float rs, time, quasarStrength, innerRadius, outerRadius;
varying vec2 vUv;
const float PI=3.14159265359;
${geodesicGLSL}

float hash(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float noise(vec3 p){
  vec3 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);
  return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
    mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}

vec4 discLight(vec3 p, vec3 direction, float observerU){
  float r=length(p);
  if(r<=innerRadius || r>=outerRadius) return vec4(0.);
  vec3 er=p/r, orbit=normalize(cross(diskNormal,er));
  float beta=sqrt(.5/max(r-1.,1.));
  // Reverse tracing: the observed photon travels opposite the traced ray.
  float mu=clamp(dot(orbit,-direction),-1.,1.);
  float shift=sqrt((1.-1./r)/max(1.-observerU,.001))*sqrt(1.-beta*beta)/(1.-beta*mu);
  float a=atan(dot(er,cross(diskNormal,diskAxis)),dot(er,diskAxis));
  // Two finite-lifetime flow fields avoid infinitely wound, flickering texture in old games.
  float age=fract(time/36.), age2=fract(time/36.+.5);
  float phase=a-age*28./pow(r,1.5), phase2=a-age2*28./pow(r,1.5);
  vec3 flow=vec3(cos(phase)*r*1.7,sin(phase)*r*1.7,r*.7);
  vec3 flow2=vec3(cos(phase2)*r*1.7,sin(phase2)*r*1.7,r*.7);
  float cloud=mix(noise(flow)*.65+noise(flow*2.8)*.35,
    noise(flow2)*.65+noise(flow2*2.8)*.35,abs(age*2.-1.));
  float threads=.5+.5*sin(r*24.+cloud*7.+sin(a*5.-time*.1)*.7);
  float density=.35+cloud*.65+threads*.12;
  float edge=smoothstep(innerRadius,innerRadius+.35,r)*(1.-smoothstep(outerRadius-2.,outerRadius,r));
  float temperature=pow(innerRadius/r,.72)*shift;
  vec3 warm=mix(vec3(1.,.14,.025),vec3(1.,.55,.2),smoothstep(.25,.6,temperature));
  warm=mix(warm,vec3(1.,.9,.72),smoothstep(.6,1.05,temperature));
  vec3 blue=mix(vec3(.12,.35,.9),vec3(.8,.93,1.),smoothstep(.35,.85,temperature));
  vec3 color=mix(warm,blue,quasarStrength)*density*pow(innerRadius/r,.8);
  color*=clamp(shift*shift*shift,.14,3.5)*.72;
  float opacity=edge*.96;
  return vec4(color*opacity,opacity);
}

vec3 sky(vec3 d){
  float mist=noise(d*7.)*.004;
  return vec3(.003,.004,.007)+vec3(.5,.65,1.)*mist;
}

void main(){
  vec4 original=texture2D(tDiffuse,vUv);
  vec4 cameraRay=inverseProjection*vec4(vUv*2.-1.,1.,1.);
  vec3 direction=normalize((cameraWorld*vec4(cameraRay.xyz,0.)).xyz);
  vec3 ro=(cameraWorld[3].xyz-holeCenter)/rs;
  float observerR=length(ro), observerU=1./max(observerR,1.001);
  vec3 er=ro/max(observerR,.001);
  float radial=clamp(dot(direction,er),-1.,1.);
  float sine=length(cross(er,direction));
  float impact=observerR*sine/sqrt(max(1.-observerU,.001));
  float influence=outerRadius+5.;
  if((radial>=0. && observerR>influence) || impact>influence){gl_FragColor=original;return;}

  // Foreground geometry stays in front. The backdrop is reprojected in screen space.
  // Compare identical scene/background depth samples to separate real objects from the sheet.
  // The sheet can occlude embedded wormhole walls without occluding the lensed black hole.
  float rawDepth=texture2D(tDepth,vUv).x;
  float backdropDepth=texture2D(tBackdropDepth,vUv).x;
  float depth=rawDepth<backdropDepth-.0000002 ? rawDepth : 1.;
  vec4 sceneP=inverseProjection*vec4(vUv*2.-1.,depth*2.-1.,1.);
  float sceneDistance=length(sceneP.xyz/max(sceneP.w,.00001))/rs;
  float front=max(0.,-observerR*radial-outerRadius);
  if(depth<.999999 && sceneDistance<front){gl_FragColor=original;return;}
  if(observerR<=1.001 || sine<.00001){gl_FragColor=vec4(0.,0.,0.,1.);return;}

  vec3 et=normalize(direction-radial*er);
  // The camera direction is in its local orthonormal frame, not coordinate space.
  vec2 q=vec2(observerU,-radial*sqrt(max(1.-observerU,.001))/(observerR*sine));
  float planeA=dot(er,diskNormal), planeB=dot(et,diskNormal);
  float crossing=mod(atan(-planeA,planeB),PI);
  if(crossing<.00001) crossing+=PI;
  float phi=0.;
  vec4 light=vec4(0.);
  bool escaped=false;
  vec3 outgoing=direction;
  for(int i=0;i<144;i++){
    float h=clamp(.06/max(abs(q.y),.2),.025,.075);
    vec2 next=geodesicStep(q,h);
    if(phi+h>=crossing){
      vec2 hit=geodesicStep(q,crossing-phi);
      if(hit.x>0.){
        vec3 hitR=er*cos(crossing)+et*sin(crossing);
        vec3 hitT=-er*sin(crossing)+et*cos(crossing);
        vec3 p=hitR/hit.x;
        vec3 tangent=normalize(-hit.y*hitR+hit.x*sqrt(max(1.-hit.x,.001))*hitT);
        if(length(p-ro)<sceneDistance || depth>=.999999){
          vec4 emission=discLight(p,tangent,observerU);
          light+=emission*(1.-light.a);
        }
      }
      crossing+=PI;
    }
    if(next.x>=1.) break;
    if(next.x<=0.){
      float exitPhi=phi+h*q.x/max(q.x-next.x,.000001);
      outgoing=er*cos(exitPhi)+et*sin(exitPhi);
      escaped=true;break;
    }
    q=next;phi+=h;
    if(light.a>.995) break;
  }
  vec3 background=vec3(0.);
  if(escaped){
    vec4 sampleP=viewProjection*vec4(cameraWorld[3].xyz+outgoing*max(5000.,observerR*rs*4.),1.);
    vec2 uv=sampleP.xy/max(sampleP.w,.001)*.5+.5;
    background=sky(outgoing);
    if(sampleP.w>0. && all(greaterThanEqual(uv,vec2(0.))) && all(lessThanEqual(uv,vec2(1.)))){
      background=texture2D(tBackdrop,uv).rgb;
    }
  }
  // Tactical objects keep their actual projected positions and their picking/label anchors.
  // Their Euclidean depth still determines whether the disk or shadow occludes them.
  bool solid=depth<.999999;
  if(solid && (escaped || sceneDistance<observerR-1.)) background=original.rgb;
  vec3 overlay=vec3(0.);
  if(!solid && escaped) overlay=max(original.rgb-texture2D(tBackdrop,vUv).rgb-.004,vec3(0.));
  vec3 result=light.rgb+(background+overlay)*(1.-light.a);
  float transition=1.-smoothstep(outerRadius+1.,influence,impact);
  gl_FragColor=vec4(mix(original.rgb,result,transition),1.);
}`;

/** Curved null rays and disk intersections are integrated per pixel before bloom and tone mapping. */
export class BlackHolePass extends Pass {
  private readonly frustum = new THREE.Frustum();
  private readonly influence = new THREE.Sphere();
  private readonly projection = new THREE.Matrix4();
  private readonly material: THREE.ShaderMaterial;
  private readonly quad: FullScreenQuad;
  private readonly backdrop = new THREE.WebGLRenderTarget(1, 1, {
    type: THREE.HalfFloatType,
    depthBuffer: true,
    depthTexture: new THREE.DepthTexture(1, 1, THREE.UnsignedIntType),
    minFilter: THREE.LinearMipmapLinearFilter,
    generateMipmaps: true,
  });
  constructor(
    private scene: THREE.Scene,
    private camera: THREE.PerspectiveCamera,
    private anchor: THREE.Object3D,
    radius: number,
    quasar: boolean,
    time: { value: number },
    samples: number,
  ) {
    super();
    this.backdrop.samples = samples;
    this.material = new THREE.ShaderMaterial({
      name: 'Schwarzschild null geodesics',
      vertexShader: 'varying vec2 vUv; void main(){vUv=uv;gl_Position=vec4(position.xy,0.,1.);}',
      fragmentShader,
      depthTest: false,
      depthWrite: false,
      uniforms: {
        tDiffuse: { value: null },
        tDepth: { value: null },
        tBackdrop: { value: this.backdrop.texture },
        tBackdropDepth: { value: this.backdrop.depthTexture },
        inverseProjection: { value: new THREE.Matrix4() },
        cameraWorld: { value: new THREE.Matrix4() },
        viewProjection: { value: new THREE.Matrix4() },
        holeCenter: { value: new THREE.Vector3() },
        diskNormal: { value: new THREE.Vector3(-Math.sin(0.28), Math.cos(0.28), 0) },
        diskAxis: { value: new THREE.Vector3(Math.cos(0.28), Math.sin(0.28), 0) },
        rs: { value: radius / CRITICAL_IMPACT },
        time,
        quasarStrength: { value: quasar ? 1 : 0 },
        innerRadius: { value: DISK_INNER_RADIUS },
        outerRadius: { value: DISK_OUTER_RADIUS },
      },
    });
    this.quad = new FullScreenQuad(this.material);
  }
  override setSize(width: number, height: number) {
    this.backdrop.setSize(width, height);
  }
  override render(
    renderer: THREE.WebGLRenderer,
    writeBuffer: THREE.WebGLRenderTarget,
    readBuffer: THREE.WebGLRenderTarget,
  ) {
    const uniforms = this.material.uniforms;
    this.anchor.getWorldPosition(this.influence.center);
    // The fragment shader's impact cutoff is bounded by this conservative world sphere.
    this.influence.radius = uniforms.rs.value * (DISK_OUTER_RADIUS + 5);
    this.frustum.setFromProjectionMatrix(
      this.projection.multiplyMatrices(this.camera.projectionMatrix, this.camera.matrixWorldInverse),
    );
    this.needsSwap = this.frustum.intersectsSphere(this.influence);
    if (!this.needsSwap) return; // Keep the composer's input; no backdrop render, resolve or ray pass.
    // Layer 1 contains only the coordinate sheet and distant stars. No fleet, body or HUD
    // can be duplicated by lensing this texture. Restore the camera even on a render error.
    const mask = this.camera.layers.mask;
    try {
      this.camera.layers.set(1);
      renderer.setRenderTarget(this.backdrop);
      renderer.render(this.scene, this.camera);
    } finally {
      this.camera.layers.mask = mask;
    }
    const u = this.material.uniforms;
    u.tDiffuse.value = readBuffer.texture;
    u.tDepth.value = readBuffer.depthTexture;
    u.inverseProjection.value.copy(this.camera.projectionMatrixInverse);
    u.cameraWorld.value.copy(this.camera.matrixWorld);
    u.viewProjection.value.multiplyMatrices(this.camera.projectionMatrix, this.camera.matrixWorldInverse);
    this.anchor.getWorldPosition(u.holeCenter.value);
    renderer.setRenderTarget(this.renderToScreen ? null : writeBuffer);
    this.quad.render(renderer);
  }
  override dispose() {
    this.backdrop.dispose();
    this.material.dispose();
    this.quad.dispose();
  }
}
