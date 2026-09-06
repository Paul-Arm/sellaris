/** SpacetimeDB 2.x binary message prefix: 0 = plain BSATN, 2 = gzip.
 * Decompression is asynchronous. Keep ALL frames ordered, including small plain
 * transactions immediately following a compressed initial snapshot.
 */
export interface ReceiveStats {
  decodedBytes: number;
  compressedFrames: number;
  decodeMs: number;
  pendingBytes: number;
  peakPendingBytes: number;
}
export const receiveStats = (): ReceiveStats => ({
  decodedBytes: 0,
  compressedFrames: 0,
  decodeMs: 0,
  pendingBytes: 0,
  peakPendingBytes: 0,
});

export class OrderedReceiver {
  private tail = Promise.resolve();
  private closed = false;
  constructor(
    private readonly deliver: (data: Uint8Array<ArrayBuffer>) => void,
    private readonly fail: (error: Error) => void,
    readonly stats = receiveStats(),
    private readonly maxBytes = 64 * 1024 * 1024,
  ) {}

  close() {
    this.closed = true;
  }

  push(bytes: Uint8Array<ArrayBuffer>): Promise<void> {
    if (this.closed) return this.tail;
    this.stats.pendingBytes += bytes.byteLength;
    this.stats.peakPendingBytes = Math.max(this.stats.peakPendingBytes, this.stats.pendingBytes);
    if (this.stats.pendingBytes > this.maxBytes) {
      this.stats.pendingBytes -= bytes.byteLength;
      this.abort(new Error('Receive backlog exceeded; reconnect for a fresh snapshot'));
      return this.tail;
    }
    this.tail = this.tail.then(async () => {
      try {
        if (this.closed) return;
        const started = performance.now();
        let data: Uint8Array<ArrayBuffer>;
        if (bytes[0] === 0) data = bytes.subarray(1);
        else if (bytes[0] === 2) {
          this.stats.compressedFrames++;
          const stream = new Blob([bytes.subarray(1)]).stream().pipeThrough(new DecompressionStream('gzip'));
          const reader = stream.getReader();
          const chunks: Uint8Array<ArrayBuffer>[] = [];
          let size = 0;
          try {
            for (;;) {
              const { value, done } = await reader.read();
              if (done) break;
              size += value.byteLength;
              if (size > this.maxBytes) throw new Error('Decoded frame exceeded receive limit');
              chunks.push(value);
            }
          } catch (error) {
            await reader.cancel().catch(() => {});
            throw error;
          } finally {
            reader.releaseLock();
          }
          data = new Uint8Array(size);
          let offset = 0;
          for (const chunk of chunks) {
            data.set(chunk, offset);
            offset += chunk.byteLength;
          }
        } else throw new Error('Unsupported or empty SpacetimeDB compression frame');
        this.stats.decodeMs += performance.now() - started;
        this.stats.decodedBytes += data.byteLength;
        if (!this.closed) this.deliver(data);
      } catch (error) {
        this.abort(error instanceof Error ? error : new Error(String(error)));
      } finally {
        this.stats.pendingBytes -= bytes.byteLength;
      }
    });
    return this.tail;
  }

  private abort(error: Error) {
    if (this.closed) return;
    this.closed = true;
    this.fail(error);
  }
}
