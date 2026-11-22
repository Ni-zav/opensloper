// What the page and the engine's worker send each other

export type ToWorker =
  | { kind: 'load'; url: string }
  | { kind: 'files'; files: Record<string, string> }
  | { kind: 'call'; id: number; request: string };

export interface Loaded {
  kind: 'loaded';
  fetchMs: number;
  compileMs: number;
  initMs: number;
  bytes: number;
}

export type FromWorker =
  Loaded | { kind: 'reply'; id: number; reply: string; ms: number } | { kind: 'failed'; message: string };
