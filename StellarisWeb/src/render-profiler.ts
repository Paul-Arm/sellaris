import * as THREE from 'three';
import type { Pass } from 'three/examples/jsm/postprocessing/Pass.js';

interface TimerExtension {
  TIME_ELAPSED_EXT: number;
  GPU_DISJOINT_EXT: number;
}
/** Nonblocking GPU timestamps. Unsupported/disjoint measurements stay unavailable,
 * never masquerade as zero or as CPU submission time. No gl.finish/readPixels. */
export class RenderProfiler {
  private gl: WebGL2RenderingContext;
  private ext: TimerExtension | null;
  private pending: { query: WebGLQuery; name: string }[] = [];
  private frame = 0;
  private lastReport = 0;
  private samples = new Map<string, { cpuMs: number; gpuMs: number | null; samples: number }>();
  private activeQuery = false;
  constructor(private renderer: THREE.WebGLRenderer) {
    this.gl = renderer.getContext() as WebGL2RenderingContext;
    this.ext = this.gl.getExtension('EXT_disjoint_timer_query_webgl2');
    renderer.info.autoReset = false;
  }
  begin() {
    this.frame++;
    this.renderer.info.reset();
    if (!this.ext) return;
    const disjoint = this.gl.getParameter(this.ext.GPU_DISJOINT_EXT);
    this.pending = this.pending.filter(({ query, name }) => {
      if (!disjoint && !this.gl.getQueryParameter(query, this.gl.QUERY_RESULT_AVAILABLE)) return true;
      if (!disjoint) {
        const sample = this.samples.get(name)!;
        const ms = Number(this.gl.getQueryParameter(query, this.gl.QUERY_RESULT)) / 1e6;
        sample.gpuMs = sample.gpuMs === null ? ms : sample.gpuMs * 0.8 + ms * 0.2;
        sample.samples++;
      }
      this.gl.deleteQuery(query);
      return false;
    });
    if (disjoint)
      for (const sample of this.samples.values()) {
        sample.gpuMs = null;
        sample.samples = 0;
      }
  }
  measure<T>(name: string, run: () => T): T {
    const query =
      this.ext && this.frame % 30 === 0 && this.pending.length < 64 && !this.activeQuery
        ? this.gl.createQuery()
        : null;
    if (query) {
      this.gl.beginQuery(this.ext!.TIME_ELAPSED_EXT, query);
      this.activeQuery = true;
    }
    const start = performance.now();
    try {
      return run();
    } finally {
      const duration = performance.now() - start;
      const sample = this.samples.get(name) ?? { cpuMs: duration, gpuMs: null, samples: 0 };
      sample.cpuMs = sample.cpuMs * 0.9 + duration * 0.1;
      this.samples.set(name, sample);
      if (query) {
        this.gl.endQuery(this.ext!.TIME_ELAPSED_EXT);
        this.activeQuery = false;
        this.pending.push({ name, query });
      }
    }
  }
  pass(name: string, pass: Pass) {
    const render = pass.render.bind(pass);
    pass.render = (...args) => this.measure(name, () => render(...args));
  }
  end(uploadBytes: number, extra: Record<string, number> = {}) {
    const now = performance.now();
    if (now - this.lastReport < 1000) return;
    this.lastReport = now;
    this.renderer.domElement.dataset.renderMetrics = JSON.stringify({
      gpuTimers: !!this.ext,
      passes: Object.fromEntries(this.samples),
      drawCalls: this.renderer.info.render.calls,
      triangles: this.renderer.info.render.triangles,
      matrixUploadBytes: uploadBytes,
      ...extra,
    });
  }
  dispose() {
    for (const p of this.pending) this.gl.deleteQuery(p.query);
    this.pending = [];
  }
}
