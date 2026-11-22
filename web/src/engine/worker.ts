// Runs the web engine in a Web Worker, so a slow evaluation never holds up
// the page. Each call is one JSON-RPC request through the engine's
// engine_handle. Files go to the engine as text, so it has no folders; the
// empty /data is its home.
import { ConsoleStdout, File, OpenFile, PreopenDirectory, WASI } from '@bjorn3/browser_wasi_shim';
import type { FromWorker, ToWorker } from './messages.ts';

interface EngineExports {
  memory: WebAssembly.Memory;
  initialize: () => unknown;
  alloc: (size: number) => number;
  free: (pointer: number) => void;
  handle: (request: number, size: number) => number;
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();
let engine: EngineExports | undefined;

function post(message: FromWorker): void {
  self.postMessage(message);
}

// A function the module exports, as the signature the engine gives it. Wasm
// keeps no parameter types JavaScript could check, so once it is known to be a
// function it is taken to be the one engine_lib.lpr declares: T names that
// signature, so it appears only in the result.
// oxlint-disable-next-line typescript/no-unnecessary-type-parameters
function exported<T>(exports: WebAssembly.Exports, name: string): T {
  const value = exports[name];
  if (typeof value !== 'function') {
    throw new Error(`the engine does not export ${name}`);
  }
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion
  return value as T;
}

function engineExports(exports: WebAssembly.Exports): EngineExports {
  const memory = exports.memory;
  if (!(memory instanceof WebAssembly.Memory)) {
    throw new Error('the engine does not export its memory');
  }
  return {
    memory,
    initialize: exported<() => unknown>(exports, '_initialize'),
    alloc: exported<(size: number) => number>(exports, 'engine_alloc'),
    free: exported<(pointer: number) => void>(exports, 'engine_free'),
    handle: exported<(request: number, size: number) => number>(exports, 'engine_handle'),
  };
}

async function load(url: string): Promise<void> {
  const fetchStart = performance.now();
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`could not fetch the engine: ${response.status.toString()}`);
  }
  const bytes = await response.arrayBuffer();
  const compileStart = performance.now();
  const module = await WebAssembly.compile(bytes);
  const initStart = performance.now();
  const wasi = new WASI(
    [],
    ['HOME=/data'],
    [
      new OpenFile(new File([])),
      ConsoleStdout.lineBuffered((line) => {
        console.log(`engine: ${line}`);
      }),
      ConsoleStdout.lineBuffered((line) => {
        console.warn(`engine: ${line}`);
      }),
      new PreopenDirectory('/data', new Map()),
    ],
    { debug: false },
  );
  const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi.wasiImport });
  engine = engineExports(instance.exports);
  wasi.initialize({ exports: { memory: engine.memory, _initialize: engine.initialize } });
  post({
    kind: 'loaded',
    fetchMs: compileStart - fetchStart,
    compileMs: initStart - compileStart,
    initMs: performance.now() - initStart,
    bytes: bytes.byteLength,
  });
}

function call(request: string): string {
  if (engine === undefined) {
    throw new Error('the engine is not loaded');
  }
  const text = encoder.encode(request);
  const pointer = engine.alloc(text.length);
  new Uint8Array(engine.memory.buffer).set(text, pointer);
  const reply = engine.handle(pointer, text.length);
  engine.free(pointer);
  // Memory may have grown during the call, so the buffer is taken afresh
  const length = new DataView(engine.memory.buffer).getUint32(reply, true);
  const result = decoder.decode(new Uint8Array(engine.memory.buffer, reply + 4, length));
  engine.free(reply);
  return result;
}

async function receive(message: ToWorker): Promise<void> {
  switch (message.kind) {
    case 'load':
      await load(message.url);
      break;
    case 'call': {
      const start = performance.now();
      const reply = call(message.request);
      post({ kind: 'reply', id: message.id, reply, ms: performance.now() - start });
      break;
    }
  }
}

self.addEventListener('message', (event: MessageEvent<ToWorker>) => {
  receive(event.data).catch((error: unknown) => {
    post({ kind: 'failed', message: String(error) });
  });
});
