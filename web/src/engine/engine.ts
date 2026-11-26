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

type Answer = Exclude<FromWorker, { kind: 'failed' }>;

interface Pending {
  resolve: (answer: Answer) => void;
  reject: (reason: Error) => void;
}

export class Engine {
  private readonly worker: Worker;
  private readonly waiting = new Map<number, Pending>();
  private nextId = 1;
  private failure: Error | undefined;

  private constructor(worker: Worker) {
    this.worker = worker;
    worker.addEventListener('message', (event: MessageEvent<FromWorker>) => {
      this.receive(event.data);
    });
    worker.addEventListener('error', (event) => {
      this.stop(new Error(event.message === '' ? 'The engine worker stopped' : event.message));
    });
    worker.addEventListener('messageerror', () => {
      this.stop(new Error('Could not read an engine worker message'));
    });
  }

  // Starts the worker at workerUrl and loads the module at wasmUrl into it
  static async start(workerUrl: URL, wasmUrl: URL): Promise<{ engine: Engine; loaded: Loaded }> {
    const engine = new Engine(new Worker(workerUrl, { type: 'module' }));
    try {
      const loaded = await engine.send({ kind: 'load', id: 0, url: wasmUrl.href });
      if (loaded.kind !== 'loaded') {
        throw new Error('The engine did not load');
      }
      return { engine, loaded };
    } catch (error: unknown) {
      engine.stop(error instanceof Error ? error : new Error(String(error)));
      throw error;
    }
  }

  // The method's result; an EngineError when the engine refuses it
  async call(method: string, params: object = {}): Promise<JsonRecord> {
    return (await this.callTimed(method, params)).result;
  }

  // The same, with how long the engine took, as the worker measured it, in ms
  async callTimed(method: string, params: object = {}): Promise<{ result: JsonRecord; ms: number }> {
    const id = this.nextId++;
    const message = await this.send({
      kind: 'call',
      id,
      request: JSON.stringify({ jsonrpc: '2.0', id, method, params }),
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

  private async send(message: ToWorker): Promise<Answer> {
    if (this.failure !== undefined) {
      throw this.failure;
    }
    return new Promise<Answer>((resolve, reject) => {
      this.waiting.set(message.id, { resolve, reject });
      try {
        this.worker.postMessage(message);
      } catch (error: unknown) {
        this.waiting.delete(message.id);
        throw error;
      }
    });
  }

  private receive(message: FromWorker): void {
    const pending = this.waiting.get(message.id);
    if (pending === undefined) return;
    this.waiting.delete(message.id);
    if (message.kind === 'failed') {
      pending.reject(new Error(message.message));
    } else {
      pending.resolve(message);
    }
  }

  private stop(error: Error): void {
    if (this.failure !== undefined) return;
    this.failure = error;
    this.worker.terminate();
    for (const request of this.waiting.values()) {
      request.reject(error);
    }
    this.waiting.clear();
  }
}
