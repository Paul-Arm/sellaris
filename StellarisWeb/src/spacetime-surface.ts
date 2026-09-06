import type { CelestialBody } from '../shared/celestial';

export const PORTAL_WIDTH = 90;
export const PORTAL_LIFT = 40;
export const PORTAL_RADIUS = 55;
export const PORTAL_DEPTH = 87.5;
export const PORTAL_APERTURE = 50;
// Experiment: set the tilt to 0 to compare the previous recessed orientation.
export const PORTAL_TILT = Math.PI / 2;
// Cancel the mouth's own mound when upright: the aperture centre sits on the local sheet.
export const PORTAL_ELEVATION = -PORTAL_LIFT * Math.sin(PORTAL_TILT);
export const PORTAL_BEND_INNER = 65;
export const PORTAL_BEND_OUTER = 190;
export const PORTAL_TAIL_STRETCH = 2.5;
export const PORTAL_FRONT_STRETCH = 1.95;
export const PORTAL_SIDE_STRETCH = 1.35;
const PORTAL_FOLD_BLEND = 24;
export const PORTAL_FRONT_END =
  PORTAL_BEND_INNER +
  (PORTAL_BEND_OUTER - PORTAL_BEND_INNER) * PORTAL_FRONT_STRETCH -
  ((PORTAL_FRONT_STRETCH - 1) * PORTAL_FOLD_BLEND) / 2;
export const PORTAL_TAIL_END =
  PORTAL_BEND_INNER +
  (PORTAL_BEND_OUTER - PORTAL_BEND_INNER) * PORTAL_TAIL_STRETCH -
  ((PORTAL_TAIL_STRETCH - 1) * PORTAL_FOLD_BLEND) / 2;
export const PORTAL_SIDE_END =
  PORTAL_BEND_INNER +
  (PORTAL_BEND_OUTER - PORTAL_BEND_INNER) * PORTAL_SIDE_STRETCH -
  ((PORTAL_SIDE_STRETCH - 1) * PORTAL_FOLD_BLEND) / 2;
// Leave some room between the larger mouth and the sheet's fade at radius 2050.
export const PORTAL_DISTANCE = 1550;
export const PORTAL_MIN_SEPARATION = 400;
export const SPACETIME_FADE_START = 1480;
export const SPACETIME_RADIUS = 2050;

type Well = { x: number; y: number; z: number; w: number };

/** Asteroid fields and their decorative belts never deform or illuminate the sheet. */
export function bodyGravityWell(body: CelestialBody): Well {
  if (body.kind === 'asteroid' || body.kind === 'station') return { x: 0, y: 0, z: 1, w: 0 };
  return {
    x: 0,
    y: 0,
    z: body.kind === 'star' || body.kind === 'blackhole' ? 88 : body.radius * 2,
    w: body.kind === 'blackhole' ? 310 : body.kind === 'star' ? 205 : body.radius * 3.3,
  };
}

/** Stretch the surrounding fold independently along each axis; the circular mouth stays rigid. */
function foldCoordinate(coordinate: number, stretch: number) {
  const distance = Math.abs(coordinate);
  const excess = Math.max(0, distance - PORTAL_BEND_INNER);
  const t = Math.min(1, excess / PORTAL_FOLD_BLEND);
  // Integral of smoothstep: C2 joins to both the unchanged mouth and linear tail.
  const eased =
    excess < PORTAL_FOLD_BLEND ? PORTAL_FOLD_BLEND * (t ** 3 - 0.5 * t ** 4) : excess - PORTAL_FOLD_BLEND / 2;
  return Math.sign(coordinate) * (distance - (1 - 1 / stretch) * eased);
}

function foldDomain(along: number) {
  return foldCoordinate(along, along < 0 ? PORTAL_FRONT_STRETCH : PORTAL_TAIL_STRETCH);
}

export function portalFoldDistance(x: number, z: number, mouth: { x: number; y: number }) {
  const bearing = Math.max(1, Math.hypot(mouth.x, mouth.y));
  const dx = mouth.x / bearing,
    dz = mouth.y / bearing;
  const along = (x - mouth.x) * dx + (z - mouth.y) * dz;
  const across = -(x - mouth.x) * dz + (z - mouth.y) * dx;
  return Math.hypot(foldDomain(along), foldCoordinate(across, PORTAL_SIDE_STRETCH));
}

/** Canonical sheet coordinates stay fixed, so contours and geometry share the same fold. */
export function foldSurfacePoint(
  point: { x: number; y: number; z: number },
  mouths: readonly Well[],
  heights: ArrayLike<number>,
) {
  let { x, y, z } = point;
  for (let i = 0; i < mouths.length; i++) {
    const mouth = mouths[i];
    const distance = portalFoldDistance(point.x, point.z, mouth);
    if (!mouth.w || distance >= PORTAL_BEND_OUTER) continue;
    const t = Math.max(
      0,
      Math.min(1, (distance - PORTAL_BEND_INNER) / (PORTAL_BEND_OUTER - PORTAL_BEND_INNER)),
    );
    const weight = 1 - t * t * t * (10 + t * (-15 + 6 * t));
    const bearing = Math.hypot(mouth.x, mouth.y),
      dx = mouth.x / bearing,
      dz = mouth.y / bearing;
    const along = (x - mouth.x) * dx + (z - mouth.y) * dz,
      side = -(x - mouth.x) * dz + (z - mouth.y) * dx;
    const foldedAlong = foldDomain((point.x - mouth.x) * dx + (point.z - mouth.y) * dz);
    const vertical = y - heights[i],
      angle = PORTAL_TILT * weight;
    const radial = along + (Math.cos(angle) - 1) * foldedAlong - Math.sin(angle) * vertical;
    x = mouth.x + dx * radial - dz * side;
    z = mouth.y + dz * radial + dx * side;
    y = heights[i] + Math.sin(angle) * foldedAlong + Math.cos(angle) * vertical + PORTAL_ELEVATION * weight;
  }
  return { x, y, z };
}

/** The same height function drives the sheet, approach routes and CPU picking anchors. */
export function surfaceHeight(x: number, z: number, wells: readonly Well[], mouths: readonly Well[]) {
  let height = -18;
  for (const well of wells) {
    const distance2 = (x - well.x) ** 2 + (z - well.y) ** 2;
    height -= well.w / Math.sqrt(1 + distance2 / Math.max(1, well.z) ** 2);
  }
  for (const mouth of mouths) {
    const distance2 = (x - mouth.x) ** 2 + (z - mouth.y) ** 2;
    if (distance2 > 9 * Math.max(1, mouth.z) ** 2) continue;
    height += mouth.w * Math.exp((-2 * distance2) / Math.max(1, mouth.z) ** 2);
  }
  return height;
}

// xyz = height, derivative along x, derivative along z. Positive mouth deformation
// lifts the existing sheet; its gradient also bends the sheet's lighting and contour flow.
export const surfaceGLSL = `
#ifndef PORTAL_COUNT
#define PORTAL_COUNT 1
#endif
uniform vec4 wells[10];
uniform vec4 mouths[PORTAL_COUNT];
uniform float mouthHeights[PORTAL_COUNT];
vec3 spacetimeSurface(vec2 p) {
  vec3 result=vec3(-18.,0.,0.);
  for(int i=0;i<10;i++) {
    if(wells[i].w<=0.) continue;
    vec2 d=p-wells[i].xy;
    float width=max(1.,wells[i].z), q=1.+dot(d,d)/(width*width);
    result.x-=wells[i].w/sqrt(q);
    result.yz+=wells[i].w*d/(width*width*pow(q,1.5));
  }
  for(int i=0;i<PORTAL_COUNT;i++) {
    vec2 d=p-mouths[i].xy;
    float width=max(1.,mouths[i].z);
    if(dot(d,d)>9.*width*width) continue;
    float lift=mouths[i].w*exp(-2.*dot(d,d)/(width*width));
    result.x+=lift;
    result.yz-=4.*lift*d/(width*width);
  }
  return result;
}

float portalFoldCoordinate(float coordinate,float compression) {
  float distance=abs(coordinate);
  float excess=max(0.,distance-${PORTAL_BEND_INNER.toFixed(1)});
  float t=min(1.,excess/${PORTAL_FOLD_BLEND.toFixed(1)});
  float eased=excess<${PORTAL_FOLD_BLEND.toFixed(1)}
    ? ${PORTAL_FOLD_BLEND.toFixed(1)}*(t*t*t-.5*t*t*t*t)
    : excess-${(PORTAL_FOLD_BLEND / 2).toFixed(1)};
  return sign(coordinate)*(distance-compression*eased);
}

float portalFoldDomain(float along) {
  float compression=along<0. ? ${(1 - 1 / PORTAL_FRONT_STRETCH).toFixed(9)} : ${(1 - 1 / PORTAL_TAIL_STRETCH).toFixed(9)};
  return portalFoldCoordinate(along,compression);
}

void foldSpacetime(inout vec3 point,inout vec3 normal,vec2 domain) {
  for(int i=0;i<PORTAL_COUNT;i++) {
    if(mouths[i].w<.1) continue;
    vec2 delta=domain-mouths[i].xy;
    vec2 outward=normalize(mouths[i].xy),side=vec2(-outward.y,outward.x);
    float foldedAlong=portalFoldDomain(dot(delta,outward));
    float foldedAcross=portalFoldCoordinate(dot(delta,side),${(1 - 1 / PORTAL_SIDE_STRETCH).toFixed(9)});
    vec2 foldedDomain=vec2(foldedAlong,foldedAcross);
    if(dot(foldedDomain,foldedDomain)>${(PORTAL_BEND_OUTER ** 2).toFixed(1)}) continue;
    float t=clamp((length(foldedDomain)-${PORTAL_BEND_INNER.toFixed(1)})/${(PORTAL_BEND_OUTER - PORTAL_BEND_INNER).toFixed(1)},0.,1.);
    // Quintic falloff has zero first and second derivatives at both joins.
    float weight=1.-t*t*t*(10.+t*(-15.+6.*t));
    float angle=${PORTAL_TILT.toFixed(9)}*weight,c=cos(angle),s=sin(angle);
    vec2 relative=point.xz-mouths[i].xy;
    float along=dot(relative,outward),across=dot(relative,side),h=point.y-mouthHeights[i];
    point.xz=mouths[i].xy+outward*(along+(c-1.)*foldedAlong-s*h)+side*across;
    point.y=mouthHeights[i]+s*foldedAlong+c*h+${PORTAL_ELEVATION.toFixed(6)}*weight;
    float nAlong=dot(normal.xz,outward),nAcross=dot(normal.xz,side),nHeight=normal.y;
    normal.xz=outward*(c*nAlong-s*nHeight)+side*nAcross;
    normal.y=s*nAlong+c*nHeight;
  }
}
`;
