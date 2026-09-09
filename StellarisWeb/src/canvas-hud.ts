import * as THREE from 'three';
import { CSS2DObject, CSS2DRenderer } from 'three/examples/jsm/renderers/CSS2DRenderer.js';
import { HudFrame } from './hud-frame';

// WICG HTML-in-Canvas (September 2026) and the earlier Chromium origin-trial return value.
// https://wicg.github.io/html-in-canvas/ — local types until these experimental APIs reach lib.dom.
type HtmlCanvas = HTMLCanvasElement & {
  requestPaint?: () => void;
  updateElementGeometry?: (element: Element, options?: { canvasTransform?: DOMMatrixInit }) => void;
  clearElementGeometry?: (element: Element) => void;
};
type HtmlContext = CanvasRenderingContext2D & {
  drawElementImage?: (element: Element, x: number, y: number, w: number, h: number) => DOMMatrix | void;
};
type State = { selected: boolean; built: boolean };

export class HudLabel {
  readonly element: HTMLButtonElement;
  readonly object: CSS2DObject;
  readonly state: State = { selected: false, built: false };
  width = 1;
  height = 26;
  x = 0;
  y = 0;
  visible = false;

  constructor(
    readonly hud: CanvasHud,
    readonly text: string,
    activate: (event: MouseEvent) => void,
  ) {
    this.element = document.createElement('button');
    this.element.type = 'button';
    this.element.hidden = true;
    this.element.className = 'orbital-label';
    this.element.setAttribute('aria-label', `${text} auswählen`);
    this.element.onclick = activate;
    this.element.textContent = text;
    this.object = new CSS2DObject(this.element);
    this.object.center.set(0.5, 0);
    this.object.visible = false;
    this.measure();
  }

  update(next: Partial<State>) {
    let changed = false;
    for (const key of Object.keys(next) as (keyof State)[]) {
      if (this.state[key] !== next[key]) {
        this.state[key] = next[key]!;
        changed = true;
      }
    }
    if (!changed) return;
    this.element.classList.toggle('selected', this.state.selected);
    this.element.classList.toggle('built', this.state.built);
    this.element.setAttribute('aria-pressed', String(this.state.selected));
    this.measure();
  }

  measure() {
    const ctx = this.hud.context;
    if (ctx) {
      ctx.font = '10px "Segoe UI", sans-serif';
      ctx.letterSpacing = '.6px';
    }
    this.width = Math.ceil(
      (ctx?.measureText(this.text).width ?? this.text.length * 7) + 20 + (this.state.built ? 12 : 0),
    );
    this.element.style.width = `${this.width}px`;
    this.element.style.height = `${this.height}px`;
  }

  place(x: number, y: number, visible = true) {
    this.x = x;
    this.y = y;
    this.object.visible = visible;
    if (this.visible !== visible) {
      this.visible = visible;
      this.element.hidden = !visible;
      if (!visible && this.hud.native) this.hud.canvas.clearElementGeometry?.(this.element);
    }
  }
}

/** Three.js label anchors; native HTML-in-Canvas painting, with CSS2DRenderer compatibility. */
export class CanvasHud {
  readonly canvas = document.createElement('canvas') as HtmlCanvas;
  readonly context = this.canvas.getContext('2d') as HtmlContext | null;
  private readonly targets = document.createElement('div');
  private readonly css: CSS2DRenderer;
  private readonly labels: HudLabel[] = [];
  private readonly frame: HudFrame;
  private pixelRatio = 1;
  private disposed = false;
  private readonly paint = () => this.frame.paint();
  private readonly fontsChanged = () => {
    if (!this.disposed) this.labels.forEach((l) => l.measure());
  };

  get native() {
    return this.frame.native;
  }

  constructor(root: HTMLDivElement, scene: THREE.Scene, camera: THREE.Camera) {
    this.canvas.className = 'system-hud';
    this.canvas.setAttribute('aria-label', 'Systembeschriftungen');
    this.targets.className = 'system-hud-targets';
    this.css = new CSS2DRenderer({ element: this.targets });
    const supported =
      !!this.context?.drawElementImage &&
      typeof this.canvas.requestPaint === 'function' &&
      'layoutSubtree' in this.canvas;
    if (supported) this.canvas.setAttribute('layoutsubtree', '');
    this.frame = new HudFrame({
      requestPaint: supported ? () => this.canvas.requestPaint!() : undefined,
      nativePaint: () => this.drawNative(),
      fallbackPaint: () => this.css.render(scene, camera),
      onFallback: () => this.useFallback(),
    });
    root.append(this.canvas, this.targets);
    this.canvas.addEventListener('paint', this.paint);
    if (!supported) this.useFallback();
    else this.canvas.dataset.hudRenderer = 'html-in-canvas';
    document.fonts?.ready.then(this.fontsChanged);
    document.fonts?.addEventListener('loadingdone', this.fontsChanged);
  }

  add(text: string, activate: (event: MouseEvent) => void) {
    const label = new HudLabel(this, text, activate);
    label.element.setAttribute('drawable', '');
    if (this.native) label.element.style.position = 'static';
    (this.native ? this.canvas : this.targets).append(label.element);
    this.labels.push(label);
    return label;
  }

  resize(width: number, height: number) {
    this.pixelRatio = Math.min(window.devicePixelRatio || 1, 2);
    this.canvas.width = Math.round(width * this.pixelRatio);
    this.canvas.height = Math.round(height * this.pixelRatio);
    this.canvas.style.width = `${width}px`;
    this.canvas.style.height = `${height}px`;
    this.css.setSize(width, height);
    this.labels.forEach((l) => l.measure());
  }

  present(scene: () => void) {
    this.frame.present(scene);
  }

  private useFallback() {
    this.canvas.removeAttribute('layoutsubtree');
    this.canvas.dataset.hudRenderer = 'three-css2d';
    this.canvas.style.display = 'none';
    this.labels.forEach((l) => {
      l.element.style.position = 'absolute';
      this.targets.append(l.element);
    });
  }

  private drawNative() {
    const ctx = this.context!;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    ctx.setTransform(this.pixelRatio, 0, 0, this.pixelRatio, 0, 0);
    for (const l of this.labels) {
      if (!l.visible) continue;
      const transform = ctx.drawElementImage!(l.element, l.x, l.y, l.width, l.height);
      // The May origin trial returns a DOMMatrix; the newer API updates geometry automatically.
      if (!this.canvas.updateElementGeometry && transform) l.element.style.transform = transform.toString();
    }
  }

  dispose() {
    this.disposed = true;
    this.frame.dispose();
    this.canvas.removeEventListener('paint', this.paint);
    document.fonts?.removeEventListener('loadingdone', this.fontsChanged);
    this.labels.forEach((l) => l.object.removeFromParent());
    this.labels.length = 0;
    this.canvas.remove();
    this.targets.remove();
  }
}
