/** Couples the 3D scene and its HUD to one browser presentation, including native paint events. */
export class HudFrame {
  private pending: (() => void) | null = null;
  private missedPaints = 0;
  private disposed = false;
  native: boolean;

  constructor(
    private driver: {
      requestPaint?: () => void;
      nativePaint: () => void;
      fallbackPaint: () => void;
      onFallback: () => void;
    },
  ) {
    this.native = !!driver.requestPaint;
  }

  present(scene: () => void) {
    if (this.disposed) return;
    this.pending = scene;
    if (this.native && ++this.missedPaints <= 4) {
      try {
        this.driver.requestPaint!();
        return;
      } catch {
        /* A partial or disabled implementation must not leave an invisible HUD. */
      }
    }
    if (this.native) this.useFallback();
    this.flush();
  }

  paint() {
    if (this.disposed || !this.native) return;
    this.missedPaints = 0;
    this.flush();
  }

  private useFallback() {
    this.native = false;
    this.driver.onFallback();
  }

  private flush() {
    const scene = this.pending;
    this.pending = null;
    scene?.();
    if (this.native) {
      try {
        this.driver.nativePaint();
        return;
      } catch {
        this.useFallback();
      }
    }
    this.driver.fallbackPaint();
  }

  dispose() {
    this.disposed = true;
    this.pending = null;
  }
}
