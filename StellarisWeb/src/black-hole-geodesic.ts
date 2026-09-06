/** Units: Schwarzschild radius rs = 1. Photon sphere r = 1.5; critical impact b = sqrt(27)/2. */
export const CRITICAL_IMPACT = Math.sqrt(27) / 2;
export const DISK_INNER_RADIUS = 3;
export const DISK_OUTER_RADIUS = 11;

// Null geodesics are planar: u = rs/r, u'' = 1.5u² - u (Schwarzschild, not Kerr).
// Equation 8: https://ebruneton.github.io/black_hole_shader/paper.pdf
export const geodesicGLSL = `
vec2 geodesicDerivative(vec2 q) { return vec2(q.y, 1.5*q.x*q.x-q.x); }
vec2 geodesicStep(vec2 q, float h) {
  vec2 a=geodesicDerivative(q);
  vec2 b=geodesicDerivative(q+a*h*.5);
  vec2 c=geodesicDerivative(q+b*h*.5);
  vec2 d=geodesicDerivative(q+c*h);
  return q+h*(a+2.*b+2.*c+d)/6.;
}`;

/** Float64 reference for checking the shader's ray equation against known physical limits. */
export function traceSchwarzschild(impact: number, step = 0.075) {
  let u = 0,
    v = 1 / impact,
    phi = 0,
    minRadius = Infinity;
  const f = (x: number) => 1.5 * x * x - x;
  for (let i = 0; i < 20000; i++) {
    const h = Math.min(step, 0.06 / Math.max(Math.abs(v), 0.2));
    const a = f(u),
      b = f(u + (v * h) / 2),
      c = f(u + ((v + (a * h) / 2) * h) / 2),
      d = f(u + (v + (b * h) / 2) * h);
    const nextU = u + (h * (v + 2 * (v + (a * h) / 2) + 2 * (v + (b * h) / 2) + (v + c * h))) / 6;
    const nextV = v + (h * (a + 2 * b + 2 * c + d)) / 6;
    if (nextU <= 0 && phi > 0) return { captured: false, angle: phi + (h * u) / (u - nextU), minRadius };
    phi += h;
    u = nextU;
    v = nextV;
    minRadius = Math.min(minRadius, 1 / u);
    if (u >= 1) return { captured: true, angle: phi, minRadius };
    if (phi > 12 * Math.PI) break;
  }
  return { captured: true, angle: phi, minRadius };
}
