import { memo, useEffect, useRef } from 'react';
import type { ColonySector } from '../shared/colonies';

export type SurfaceSector = Pick<ColonySector, 'id' | 'x' | 'y' | 'z'>;
const colors = (planet: string) =>
  /Wüsten|Trocken|Savannen/.test(planet)
    ? [0.49, 0.35, 0.24]
    : /Ozean/.test(planet)
      ? [0.19, 0.39, 0.5]
      : /Arktis|Tundra|Alpin/.test(planet)
        ? [0.36, 0.44, 0.53]
        : [0.29, 0.4, 0.39];

/** Only geography/selection redraw the surface; population and income updates stay in React. */
export const PlanetSurface = memo(function PlanetSurface({
  geometry,
  planet,
  selected,
}: {
  geometry: string;
  planet: string;
  selected: number;
}) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = ref.current!,
      ctx = canvas.getContext('2d');
    if (!ctx) return;
    const sectors: SurfaceSector[] = JSON.parse(geometry),
      size = 640,
      radius = size / 2;
    canvas.width = size;
    canvas.height = size;
    const pixels = ctx.createImageData(size, size),
      owners = new Int16Array(size * size).fill(-1),
      tint = colors(planet);
    for (let y = 0; y < size; y++)
      for (let x = 0; x < size; x++) {
        const nx = (x + 0.5 - radius) / radius,
          ny = (y + 0.5 - radius) / radius,
          r2 = nx * nx + ny * ny;
        if (r2 > 1) continue;
        const nz = Math.sqrt(1 - r2),
          p = y * size + x;
        let best = -1,
          distance = -Infinity;
        for (const s of sectors) {
          const dot = nx * s.x + ny * s.y + nz * s.z;
          if (dot > distance) {
            distance = dot;
            best = s.id;
          }
        }
        owners[p] = best;
        const light = Math.max(0, -nx * 0.42 - ny * 0.5 + nz * 0.76),
          rim = (1 - nz) ** 2.8,
          lat = ny * 14,
          scan = Math.abs(lat - Math.floor(lat) - 0.5) < 0.019 ? 1 : 0;
        for (let c = 0; c < 3; c++) {
          const base = tint[c] * (0.25 + light * 0.65) + [0.035, 0.05, 0.065][c];
          const edge = (tint[c] * 0.45 + [0.8, 0.94, 1][c] * 0.55) * rim * 0.83;
          pixels.data[p * 4 + c] = Math.min(
            255,
            (base + edge + tint[c] * scan * 0.075 + (best === selected ? [0.035, 0.023, 0.07][c] : 0)) * 255,
          );
        }
        pixels.data[p * 4 + 3] = Math.min(255, (1 - Math.sqrt(r2)) * size * 255);
      }
    for (let y = 1; y < size - 1; y++)
      for (let x = 1; x < size - 1; x++) {
        const p = y * size + x,
          o = owners[p],
          next = owners[p + 1],
          down = owners[p + size];
        if (o >= 0 && ((next >= 0 && next !== o) || (down >= 0 && down !== o))) {
          const active = o === selected || next === selected || down === selected;
          for (let c = 0; c < 3; c++)
            pixels.data[p * 4 + c] = Math.round(
              pixels.data[p * 4 + c] * (active ? 0.4 : 0.8) + [184, 170, 244][c] * (active ? 0.6 : 0.2),
            );
        }
      }
    ctx.putImageData(pixels, 0, 0);
  }, [geometry, planet, selected]);
  return <canvas ref={ref} className="pm-sphere" aria-hidden="true" />;
});
