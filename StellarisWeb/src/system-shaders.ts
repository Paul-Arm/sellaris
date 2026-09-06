import { PORTAL_APERTURE, SPACETIME_FADE_START, SPACETIME_RADIUS, surfaceGLSL } from './spacetime-surface';

// These materials visualize a stylized gravitational potential, not a physical spacetime simulation.
export const fieldVertex = `
${surfaceGLSL}
varying vec3 fieldP;
varying vec3 fieldN;
varying vec2 fieldDomain;
void main() {
  vec2 p = position.xy;
  vec3 surface=spacetimeSurface(p);
  fieldP = vec3(p.x, surface.x, p.y);
  fieldN = normalize(vec3(-surface.y, 1., -surface.z));
  fieldDomain=p;
  foldSpacetime(fieldP,fieldN,p);
  gl_Position = projectionMatrix * modelViewMatrix * vec4(fieldP, 1.);
}`;

export const fieldFragment = `
uniform vec4 wells[10];
uniform vec4 mouths[PORTAL_COUNT];
uniform vec3 colors[10];
uniform float time;
uniform float contours;
varying vec3 fieldP;
varying vec3 fieldN;
varying vec2 fieldDomain;
void main() {
  vec3 spill = vec3(0.);
  float potential = 18.;
  for (int i = 0; i < 10; i++) {
    if(wells[i].w<=0.) continue;
    float r = length(fieldDomain - wells[i].xy) / max(wells[i].z, 1.);
    float power = step(.1, wells[i].w);
    float core = exp(-r*r*2.5) * power;
    float halo = exp(-r*r*.38) * power;
    float pulse = .93 + .07*sin(r*8. - time*.65 + float(i));
    spill += colors[i] * (halo*.11 + core*.8) * pulse;
    potential += wells[i].w / sqrt(1.+r*r);
  }
  for(int i=0;i<PORTAL_COUNT;i++) {
    vec2 offset=fieldDomain-mouths[i].xy;
    float width=max(1.,mouths[i].z), distance2=dot(offset,offset);
    if(distance2>9.*width*width) continue;
    float r=sqrt(distance2);
    if(mouths[i].w>.1 && r<${PORTAL_APERTURE.toFixed(1)}) discard;
    float lift=mouths[i].w*exp(-2.*distance2/(width*width));
    // Steer the galaxy contours outward onto the upper fold of the upright throat.
    // This contour field is stylized independently of the surface's physical height.
    potential+=lift;
    spill+=vec3(.2,.86,.7)*lift*.006;
  }
  // Evaluate contours per pixel so close-ups do not reveal the displacement mesh tessellation.
  float level = potential / 3.2;
  float aa = max(fwidth(level), .012);
  float line = 1. - smoothstep(0., aa*.72, abs(fract(level)-.5));
  line *= 1. - smoothstep(.65, 1.8, aa);
  float light = .65 + .35 * dot(normalize(fieldN), normalize(vec3(-.4, 1., .5)));
  vec3 base = vec3(.014, .017, .025) * light;
  vec3 color = base + spill*.65;
  color += line * contours * (vec3(.032,.037,.052) + spill*1.35);
  // A few wider contour bands make the depth readable at overview distance.
  float major = 1.-smoothstep(0.,aa*.72,abs(mod(level,5.)-2.5));
  color += major*contours*vec3(.011,.013,.017);
  float edge = 1.-smoothstep(${SPACETIME_FADE_START.toFixed(1)}, ${SPACETIME_RADIUS.toFixed(1)}, length(fieldDomain));
  color = mix(vec3(.003,.004,.007), color, edge);
  gl_FragColor = vec4(color, 1.);
}`;

export const bodyVertex = `
varying vec3 localP;
varying vec3 worldP;
varying vec3 worldN;
void main() {
  localP = position;
  worldP = (modelMatrix * vec4(position,1.)).xyz;
  worldN = normalize(mat3(modelMatrix)*normal);
  gl_Position = projectionMatrix * viewMatrix * vec4(worldP,1.);
}`;

export const bodyFragment = `
uniform vec3 tint;
uniform float style;
uniform float time;
varying vec3 localP;
varying vec3 worldP;
varying vec3 worldN;
void main() {
  vec3 p = normalize(localP);
  float facing = clamp(dot(normalize(worldN), normalize(cameraPosition-worldP)), 0., 1.);
  float rim = pow(1.-facing, 2.8);
  float bands = sin(p.y*36.+sin(p.x*12.+time*.12)*.7);
  if (style > 2.5) {
    float flow = sin(p.x*19.+sin(p.y*22.-time*.2))*sin(p.z*27.+time*.17);
    gl_FragColor = vec4(vec3(3.5,2.8,3.2) + tint*(.6+flow*.16), 1.);
  } else {
    float lit = max(0., dot(normalize(worldN), normalize(vec3(-.5,.6,.9))));
    vec3 color = tint*(.25+lit*.65) + vec3(.035,.05,.065);
    if (style > 1.5) color *= .85+bands*.12;
    // Sparse luminous latitude contours, rather than photographic terrain.
    float scan = 1.-smoothstep(.05,.05+fwidth(p.y*14.),abs(fract(p.y*14.)-.5));
    color += tint*scan*.09;
    color += mix(tint,vec3(.8,.94,1.),.55)*rim*1.5;
    gl_FragColor = vec4(color,1.);
  }
}`;

export const coronaFragment = `
uniform vec3 tint;
uniform float time;
uniform float rift;
varying vec2 vUv;
void main() {
  vec2 p = (vUv-.5)*2.;
  float r = length(p);
  float a = atan(p.y,p.x);
  float curl = sin(a*7.+time*.18+sin(a*3.-time*.14))*0.025;
  float ring = exp(-abs(r-.46-curl)*95.);
  float outer = exp(-abs(r-.56-curl*1.8)*28.);
  float wisps = pow(.5+.5*sin(a*19.+r*15.-time*.24),4.);
  float flare = ring*1.3 + outer*wisps*.36;
  if (rift > .5) {
    float taper = exp(-p.x*p.x*3.);
    float bend = sin(p.x*11.+time*.3)*.09*taper;
    flare = exp(-abs(p.y-bend)/(0.012+.035*taper))*taper*3.;
    flare += exp(-abs(p.y-bend-.1*sin(p.x*21.-time*.5)*taper)*70.)*taper*.8;
  }
  float halo = exp(-r*r*5.)*.17;
  gl_FragColor = vec4(tint*(flare*2.+halo), clamp(flare+halo,0.,1.));
}`;
