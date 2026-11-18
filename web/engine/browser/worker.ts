// Runs the web engine in a Web Worker, so a slow evaluation never holds up
// the page. Files the page sends are put in /data, an in-memory folder; each
// call is one JSON-RPC request through the engine's engine_handle.
import { ConsoleStdout, File, OpenFile, PreopenDirectory, WASI, type Inode } from '@bjorn3/browser_wasi_shim';
import type { FromWorker, ToWorker } from './messages';

interface EngineExports {
  memory: WebAssembly.Memory;
  _initialize: () => void;
  engine_alloc: (size: number) => number;
  engine_free: (pointer: number) => void;
  engine_handle: (request: number, size: number) => number;
}

const data = new Map<string, Inode>();
const encoder = new TextEncoder();
const decoder = new TextDecoder();
let engine: EngineExports | null = null;

function post(message: FromWorker): void {
  self.postMessage(message);
}

async function load(url: string): Promise<void> {
  const fetchStart = performance.now();
  const bytes = await (await fetch(url)).arrayBuffer();
  const compileStart = performance.now();
  const module = await WebAssembly.compile(bytes);
  const initStart = performance.now();
  const wasi = new WASI([], ['HOME=/data'], [
    new OpenFile(new File([])),
    ConsoleStdout.lineBuffered((line) => console.log(`engine: ${line}`)),
    ConsoleStdout.lineBuffered((line) => console.warn(`engine: ${line}`)),
    new PreopenDirectory('/data', data),
  ], { debug: false });
  const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi.wasiImport });
  engine = instance.exports as unknown as EngineExports;
  wasi.initialize(instance as unknown as { exports: { memory: WebAssembly.Memory; _initialize?: () => unknown } });
  post({
    kind: 'loaded',
    fetchMs: compileStart - fetchStart,
    compileMs: initStart - compileStart,
    initMs: performance.now() - initStart,
    bytes: bytes.byteLength,
  });
}

function call(request: string): string {
  const exports = engine!;
  const text = encoder.encode(request);
  const pointer = exports.engine_alloc(text.length);
  new Uint8Array(exports.memory.buffer).set(text, pointer);
  const reply = exports.engine_handle(pointer, text.length);
  exports.engine_free(pointer);
  // Memory may have grown during the call, so the buffer is taken afresh
  const length = new DataView(exports.memory.buffer).getUint32(reply, true);
  const result = decoder.decode(new Uint8Array(exports.memory.buffer, reply + 4, length));
  exports.engine_free(reply);
  return result;
}

self.onmessage = async (event: MessageEvent<ToWorker>) => {
  const message = event.data;
  try {
    if (message.kind === 'load') {
      await load(message.url);
    } else if (message.kind === 'files') {
      for (const [name, text] of Object.entries(message.files)) {
        data.set(name, new File(encoder.encode(text)));
      }
    } else {
      const start = performance.now();
      const reply = call(message.request);
      post({ kind: 'reply', id: message.id, reply, ms: performance.now() - start });
    }
  } catch (error) {
    post({ kind: 'failed', message: String(error) });
  }
};
