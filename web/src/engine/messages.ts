// What the page and the engine's worker send each other

export type ToWorker = { kind: 'load'; id: 0; url: string } | { kind: 'call'; id: number; request: string };

export interface Loaded {
  kind: 'loaded';
  id: 0;
  fetchMs: number;
  compileMs: number;
  initMs: number;
  bytes: number;
}

export type FromWorker =
  Loaded | { kind: 'reply'; id: number; reply: string; ms: number } | { kind: 'failed'; id: number; message: string };
