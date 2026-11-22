// The engine as the page sees it: a Web Worker running the Wasm module, and
// calls to its Automation API that resolve with the result or reject with the
// engine's reason. Calls run one at a time in the order sent.
import type { FromWorker, Loaded, ToWorker } from './messages.ts';
import { parseReply, type JsonRecord } from './replies.ts';

// A call the engine refused, with the JSON-RPC error code and its reason
export class EngineError extends Error {
  readonly code: number;

  constructor(code: number, message: string) {
    super(message);
    this.name = 'EngineError';
    this.code = code;
  }
}

export class Engine {
  private readonly worker: Worker;
  private readonly waiting = new Map<number, (message: FromWorker) => void>();
  private nextId = 1;
  private failure: ((reason: Error) => void) | undefined;

  private constructor(worker: Worker) {
    this.worker = worker;
    worker.addEventListener('message', (event: MessageEvent<FromWorker>) => {
      this.receive(event.data);
    });
  }

  // Starts the worker at workerUrl and loads the module at wasmUrl into it
  static async start(workerUrl: URL, wasmUrl: URL): Promise<{ engine: Engine; loaded: Loaded }> {
    const engine = new Engine(new Worker(workerUrl, { type: 'module' }));
    const loaded = await new Promise<Loaded>((resolve, reject) => {
      engine.failure = reject;
      engine.waiting.set(0, (message) => {
        if (message.kind === 'loaded') {
          resolve(message);
        }
      });
      engine.send({ kind: 'load', url: wasmUrl.href });
    });
    engine.waiting.delete(0);
    return { engine, loaded };
  }

  // The method's result; an EngineError when the engine refuses it
  async call(method: string, params: object = {}): Promise<JsonRecord> {
    return (await this.callTimed(method, params)).result;
  }

  // The same, with how long the engine took, as the worker measured it, in ms
  async callTimed(method: string, params: object = {}): Promise<{ result: JsonRecord; ms: number }> {
    const id = this.nextId++;
    const message = await new Promise<FromWorker>((resolve, reject) => {
      this.failure = reject;
      this.waiting.set(id, resolve);
      this.send({ kind: 'call', id, request: JSON.stringify({ jsonrpc: '2.0', id, method, params }) });
    });
    if (message.kind !== 'reply') {
      throw new Error(`no reply to ${method}`);
    }
    const reply = parseReply(message.reply, message.ms);
    if (reply.error !== undefined) {
      throw new EngineError(reply.error.code, reply.error.message);
    }
    return { result: reply.result ?? {}, ms: reply.ms };
  }

  private send(message: ToWorker): void {
    this.worker.postMessage(message);
  }

  private receive(message: FromWorker): void {
    switch (message.kind) {
      case 'loaded':
        this.waiting.get(0)?.(message);
        break;
      case 'reply':
        this.waiting.get(message.id)?.(message);
        this.waiting.delete(message.id);
        break;
      case 'failed':
        this.failure?.(new Error(message.message));
        break;
    }
  }
}
