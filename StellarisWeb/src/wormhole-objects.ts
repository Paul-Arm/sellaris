import * as THREE from 'three';
import { PORTAL_DEPTH, PORTAL_RADIUS, PORTAL_TAIL_END, surfaceGLSL } from './spacetime-surface';
import { hyperlanePath } from './hyperlane-path';
import type { Disposable } from './system-objects';

/** The sheet folds into the throat; the route passes through its axis, beneath the outer wall. */
export function createWormhole(
  mouth: THREE.Vector4,
  direction: THREE.Vector3,
  wells: THREE.Vector4[],
  mouths: THREE.Vector4[],
  mouthHeights: Float32Array,
  time: { value: number },
  resources: Disposable[],
) {
  const uniforms = {
    wells: { value: wells },
    mouths: { value: mouths },
    mouthHeights: { value: mouthHeights },
    time,
    mouth: { value: mouth },
  };
  const defines = { PORTAL_COUNT: mouths.length };
  const geometry = new THREE.RingGeometry(0, PORTAL_RADIUS, 96, 28);
  const material = new THREE.ShaderMaterial({
    defines,
    uniforms,
    transparent: true,
    depthWrite: true,
    side: THREE.DoubleSide,
    vertexShader: `${surfaceGLSL}
      uniform vec4 mouth;
      varying vec2 localP;
      varying vec3 throatN;
      void main(){
        localP=position.xy;
        vec2 p=localP+mouth.xy;
        vec3 surface=spacetimeSurface(p);
        float r=length(localP), s=clamp(r/${PORTAL_RADIUS.toFixed(1)},0.,1.);
        float descent=${PORTAL_DEPTH.toFixed(1)}*(1.-s*s*(3.-2.*s));
        vec2 slope=surface.yz+${((6 * PORTAL_DEPTH) / PORTAL_RADIUS).toFixed(6)}*s*(1.-s)*localP/max(r,.001);
        throatN=normalize(vec3(-slope.x,1.,-slope.y));
        vec3 point=vec3(p.x,surface.x-descent+.45,p.y);
        foldSpacetime(point,throatN,p);
        gl_Position=projectionMatrix*viewMatrix*vec4(point,1.);
      }`,
    fragmentShader: `
      uniform float time;
      varying vec2 localP;
      varying vec3 throatN;
      void main(){
        float r=length(localP)/${PORTAL_RADIUS.toFixed(1)}, a=atan(localP.y,localP.x);
        float rim=exp(-pow((r-.91)/.021,2.));
        float phase=a*3.-log(max(r,.035))*5.+time*.6;
        float current=pow(.5+.5*sin(phase),10.)*smoothstep(.07,.3,r)*(1.-smoothstep(.7,.91,r));
        float rings=pow(.5+.5*sin(r*70.+time*.55),12.)*r*(1.-r);
        float lit=.7+.3*max(0.,dot(normalize(throatN),normalize(vec3(-.4,1.,.5))));
        vec3 color=mix(vec3(.001,.004,.012),vec3(.018,.08,.092),r*r)*lit;
        color+=vec3(.32,1.,.84)*(rim*1.35+current*.32+rings*.3);
        color+=vec3(.3,.55,1.)*exp(-r*r*700.)*.48;
        float alpha=1.-smoothstep(.93,1.,r);
        if(alpha<.01) discard;
        gl_FragColor=vec4(color,alpha);
      }`,
  });
  const portal = new THREE.Mesh(geometry, material);
  portal.frustumCulled = false; // The shader positions the local mesh on the changing global sheet.

  const distance = Math.hypot(mouth.x, mouth.y);
  // Bow away from the closest neighbouring route while preserving the destination bearing.
  let nearest = Infinity,
    turn = 1;
  for (const other of mouths) {
    if (other === mouth || other.w < 0.1) continue;
    const x = other.x - mouth.x,
      z = other.y - mouth.y;
    const separation = Math.hypot(x, z),
      side = -direction.z * x + direction.x * z;
    if (separation < nearest && Math.abs(side) > 1) {
      nearest = separation;
      turn = side > 0 ? -1 : 1;
    }
  }
  const path = hyperlanePath(distance, direction, turn);
  // Start at the aperture centre. There is no route geometry on the system-facing side.
  const segments = path.points.length - 1;
  // A camera-facing ribbon gives the light thread a soft cross-section at every zoom.
  const points = path.points.flatMap(({ x, z }) => {
    const point = new THREE.Vector3(x, 0, z);
    return [point, point.clone()];
  });
  const routeGeometry = new THREE.BufferGeometry().setFromPoints(points);
  routeGeometry.setAttribute(
    'along',
    new THREE.Float32BufferAttribute(
      path.points.flatMap(({ along }) => [along, along]),
      1,
    ),
  );
  routeGeometry.setAttribute(
    'travel',
    new THREE.Float32BufferAttribute(
      path.points.flatMap((p) => [p.travel, p.travel]),
      1,
    ),
  );
  routeGeometry.setAttribute(
    'pathTangent',
    new THREE.Float32BufferAttribute(
      path.points.flatMap((p) => [p.tx, 0, p.tz, p.tx, 0, p.tz]),
      3,
    ),
  );
  routeGeometry.setAttribute(
    'laneSide',
    new THREE.Float32BufferAttribute(
      path.points.flatMap(() => [-1, 1]),
      1,
    ),
  );
  const indices: number[] = [];
  for (let i = 0; i < segments; i++) {
    const a = i * 2;
    indices.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
  }
  routeGeometry.setIndex(indices);
  const routeMaterial = new THREE.ShaderMaterial({
    defines,
    uniforms: { ...uniforms, routeLength: { value: path.length } },
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    side: THREE.DoubleSide,
    vertexShader: `${surfaceGLSL}
      uniform vec4 mouth;
      uniform float routeLength;
      attribute float along;
      attribute float travel;
      attribute float laneSide;
      attribute vec3 pathTangent;
      varying float distanceToMouth;
      varying float acrossLane;
      void main(){
        distanceToMouth=travel;
        acrossLane=laneSide;
        vec3 centre=vec3(mouth.x,spacetimeSurface(mouth.xy).x,mouth.y);
        vec3 normal=vec3(0.,1.,0.);
        foldSpacetime(centre,normal,mouth.xy);
        // Follow the throat's central axis, not the deformed roof above it.
        vec3 point=centre-normal*along;
        vec2 p=position.xz,delta=p-mouth.xy;
        float ownLift=mouth.w*exp(-2.*dot(delta,delta)/(mouth.z*mouth.z));
        float baseHeight=spacetimeSurface(p).x-ownLift+1.;
        // Far outside the throat, rejoin the local sheet without a height discontinuity.
        float blend=smoothstep(${PORTAL_DEPTH.toFixed(1)},${(PORTAL_TAIL_END + 40).toFixed(1)},along);
        point=mix(point,vec3(p.x,baseHeight,p.y),blend);
        vec4 viewPoint=viewMatrix*vec4(point,1.);
        vec2 tangent=(viewMatrix*vec4(pathTangent,0.)).xy;
        vec2 perpendicular=length(tangent)>.0001 ? normalize(vec2(-tangent.y,tangent.x)) : vec2(1.,0.);
        float progress=clamp(travel/routeLength,0.,1.);
        float taper=1.-smoothstep(0.,1.,progress);
        float halfWidth=clamp(-viewPoint.z*.0027,3.,12.)*1.35*taper;
        viewPoint.xy+=perpendicular*laneSide*halfWidth;
        gl_Position=projectionMatrix*viewPoint;
      }`,
    fragmentShader: `
      uniform float time;
      uniform vec4 mouth;
      uniform float routeLength;
      varying float distanceToMouth;
      varying float acrossLane;
      void main(){
        float d=distanceToMouth;
        float progress=clamp(d/routeLength,0.,1.);
        float fade=smoothstep(0.,40.,d)*(1.-smoothstep(.64,1.,progress));
        fade*=mix(1.,.48,progress);
        float x=abs(acrossLane),aa=max(fwidth(acrossLane),.015);
        float thread=1.-smoothstep(.12-aa,.12+aa,x);
        float halo=exp(-x*x*5.5)*(1.-smoothstep(.75,1.,x));
        // Spaced pulses travel outward, each leaving a short, soft wake.
        float phase=mod(d-time*72.+dot(mouth.xy,vec2(.19,.27)),360.);
        float head=exp(-pow((phase-300.)/11.,2.));
        float wake=exp(-max(300.-phase,0.)/58.)*smoothstep(0.,35.,phase)*(1.-smoothstep(300.,315.,phase));
        vec3 color=vec3(.16,.53,.43)*thread;
        color+=vec3(.55,1.18,.96)*thread*(head*.95+wake*.28);
        color+=vec3(.17,.72,.57)*halo*(.055+wake*.12+head*.1);
        if(fade<.001) discard;
        gl_FragColor=vec4(color,fade);
      }`,
  });
  const route = new THREE.Mesh(routeGeometry, routeMaterial);
  route.frustumCulled = false;
  resources.push(geometry, material, routeGeometry, routeMaterial);
  return { portal, route };
}
