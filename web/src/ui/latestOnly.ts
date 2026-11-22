// Runs an asynchronous job for the newest value only: while one runs, values
// pushed meanwhile replace each other, and only the last runs next. Mouse
// moves go through it, so the engine never falls behind the pointer.

export class LatestOnly<T> {
  private readonly job: (value: T) => Promise<void>;
  private readonly onError: (error: unknown) => void;
  private running: Promise<void> | undefined;
  private pending: { value: T } | undefined;

  constructor(job: (value: T) => Promise<void>, onError: (error: unknown) => void) {
    this.job = job;
    this.onError = onError;
  }

  push(value: T): void {
    if (this.running !== undefined) {
      this.pending = { value };
      return;
    }
    this.running = this.drain(value);
  }

  // Drops a value waiting to run
  clear(): void {
    this.pending = undefined;
  }

  // Resolves once nothing runs or waits, as before ending a drag
  async idle(): Promise<void> {
    while (this.running !== undefined) {
      // oxlint-disable-next-line no-await-in-loop
      await this.running;
    }
  }

  private async drain(first: T): Promise<void> {
    let next: { value: T } | undefined = { value: first };
    while (next !== undefined) {
      try {
        // One after another on purpose: each waits for the engine's answer
        // oxlint-disable-next-line no-await-in-loop
        await this.job(next.value);
      } catch (error: unknown) {
        this.onError(error);
      }
      next = this.pending;
      this.pending = undefined;
    }
    this.running = undefined;
  }
}
