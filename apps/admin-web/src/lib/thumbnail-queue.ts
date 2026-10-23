type Job = {
  assetId: string;
  controller: AbortController;
  signal?: AbortSignal;
  onAbort: () => void;
  resolve: (blob: Blob) => void;
  reject: (cause: unknown) => void;
  started: boolean;
  settled: boolean;
};

/** One query owns one queue. Disposing it never leaves another login waiting on old work. */
export class ThumbnailQueue {
  private readonly load: (assetId: string, signal: AbortSignal) => Promise<Blob>;
  private readonly isCurrent: () => boolean;
  private readonly jobs = new Set<Job>();
  private running = 0;
  private disposed = false;

  constructor(load: (assetId: string, signal: AbortSignal) => Promise<Blob>, isCurrent: () => boolean) {
    this.load = load;
    this.isCurrent = isCurrent;
  }

  enqueue(assetId: string, signal?: AbortSignal): Promise<Blob> {
    return new Promise((resolve, reject) => {
      if (this.disposed || !this.isCurrent() || signal?.aborted) {
        reject(this.cancelled()); return;
      }
      const job: Job = {
        assetId, signal, controller: new AbortController(), resolve, reject,
        started: false, settled: false, onAbort: () => this.cancel(job),
      };
      this.jobs.add(job);
      signal?.addEventListener("abort", job.onAbort, { once: true });
      this.pump();
    });
  }

  dispose(): void {
    this.disposed = true;
    for (const job of this.jobs) this.cancel(job);
  }

  private pump(): void {
    if (this.disposed) return;
    if (!this.isCurrent()) { this.dispose(); return; }
    for (const job of this.jobs) {
      if (this.running >= 2) break;
      if (job.started || job.settled) continue;
      // Recheck immediately before dispatch, including work released by another image finishing.
      if (!this.isCurrent()) { this.dispose(); return; }
      job.started = true; this.running++;
      void this.run(job);
    }
  }

  private async run(job: Job): Promise<void> {
    try {
      const blob = await this.load(job.assetId, job.controller.signal);
      if (this.disposed || !this.isCurrent() || job.signal?.aborted) this.cancel(job);
      else if (!job.settled) { job.settled = true; job.resolve(blob); }
    } catch (cause) {
      if (!job.settled) { job.settled = true; job.reject(cause); }
    } finally {
      job.signal?.removeEventListener("abort", job.onAbort);
      this.jobs.delete(job); this.running--;
      this.pump();
    }
  }

  private cancel(job: Job): void {
    if (job.settled) return;
    job.settled = true;
    job.signal?.removeEventListener("abort", job.onAbort);
    job.controller.abort();
    job.reject(this.cancelled());
    // Running work keeps its slot until fetch settles; pending work can be removed immediately.
    if (!job.started) this.jobs.delete(job);
  }

  private cancelled(): DOMException { return new DOMException("Thumbnail query was cancelled", "AbortError"); }
}
