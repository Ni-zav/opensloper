// What the page and the engine's worker send each other

export type ToWorker =
  | { kind: 'load'; url: string }
  | { kind: 'files'; files: Record<string, string> }
  | { kind: 'call'; id: number; request: string };

export type FromWorker =
  | { kind: 'loaded'; fetchMs: number; compileMs: number; initMs: number; bytes: number }
  | { kind: 'reply'; id: number; reply: string; ms: number }
  | { kind: 'failed'; message: string };
