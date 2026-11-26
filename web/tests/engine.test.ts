// The engine's calls over a stand-in worker: a failure rejects only its own
// request, and a broken or unloaded worker settles every call
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { Engine } from '../src/engine/engine.ts';
import type { FromWorker, Loaded, ToWorker } from '../src/engine/messages.ts';

const workerUrl = new URL('https://example.test/worker.js');
const wasmUrl = new URL('https://example.test/engine.wasm');
const loaded: Loaded = { kind: 'loaded', id: 0, fetchMs: 0, compileMs: 0, initMs: 0, bytes: 1 };

class FakeWorker extends EventTarget {
  readonly sent: ToWorker[] = [];
  terminated = false;

  postMessage(message: ToWorker): void {
    this.sent.push(message);
  }

  answer(data: FromWorker): void {
    this.dispatchEvent(new MessageEvent('message', { data }));
  }

  terminate(): void {
    this.terminated = true;
  }
}

function withWorker(): { worker: FakeWorker; restore: () => void } {
  const original = Object.getOwnPropertyDescriptor(globalThis, 'Worker');
  const worker = new FakeWorker();
  Object.defineProperty(globalThis, 'Worker', {
    configurable: true,
    value: function workerConstructor(): FakeWorker {
      return worker;
    },
  });
  return {
    worker,
    restore: () => {
      if (original === undefined) {
        Reflect.deleteProperty(globalThis, 'Worker');
      } else {
        Object.defineProperty(globalThis, 'Worker', original);
      }
    },
  };
}

void test('only the matching request rejects when a worker call fails', async (context) => {
  const { worker, restore } = withWorker();
  context.after(restore);
  const started = Engine.start(workerUrl, wasmUrl);
  worker.answer(loaded);
  const { engine } = await started;
  const first = engine.call('first');
  const second = engine.call('second');
  const firstId = worker.sent[1]?.id;
  const secondId = worker.sent[2]?.id;
  assert.ok(typeof firstId === 'number');
  assert.ok(typeof secondId === 'number');
  const firstRejected = assert.rejects(first, /first failed/u);
  worker.answer({ kind: 'failed', id: firstId, message: 'first failed' });
  worker.answer({ kind: 'reply', id: secondId, reply: '{"result":{"value":2}}', ms: 0 });
  assert.deepEqual(await second, { value: 2 });
  await firstRejected;
});

void test('a broken worker settles all pending requests and refuses future calls', async (context) => {
  const { worker, restore } = withWorker();
  context.after(restore);
  const started = Engine.start(workerUrl, wasmUrl);
  worker.answer(loaded);
  const { engine } = await started;
  const first = engine.call('first');
  const second = engine.call('second');
  worker.dispatchEvent(new MessageEvent('messageerror'));
  await Promise.all([
    assert.rejects(first, /engine worker message/u),
    assert.rejects(second, /engine worker message/u),
  ]);
  await assert.rejects(engine.call('third'), /engine worker message/u);
  assert.equal(worker.terminated, true);
  assert.equal(worker.sent.length, 3);
});

void test('a failed engine load terminates its worker', async (context) => {
  const { worker, restore } = withWorker();
  context.after(restore);
  const started = Engine.start(workerUrl, wasmUrl);
  worker.answer({ kind: 'failed', id: 0, message: 'could not fetch the engine' });
  await assert.rejects(started, /could not fetch the engine/u);
  assert.equal(worker.terminated, true);
});
