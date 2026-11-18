// The spike's page: loads the engine in a worker, gives it a regression
// pattern as text, then opens, checks and draws it, and times a run of edits.
// Results go in #results as JSON, and the drawing in #drawing.
import type { FromWorker, ToWorker } from './messages';

const worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
const waiting = new Map<number, (reply: FromWorker) => void>();
let loaded: ((reply: FromWorker) => void) | null = null;
let nextId = 1;

worker.onmessage = (event: MessageEvent<FromWorker>) => {
  const message = event.data;
  if (message.kind === 'reply') {
    waiting.get(message.id)?.(message);
    waiting.delete(message.id);
  } else if (message.kind === 'loaded') {
    loaded?.(message);
  } else {
    show({ failed: message.message });
  }
};

function send(message: ToWorker): void {
  worker.postMessage(message);
}

async function call(method: string, params: object = {}): Promise<{ result?: any; error?: any; ms: number }> {
  const id = nextId++;
  const reply = await new Promise<FromWorker>((resolve) => {
    waiting.set(id, resolve);
    send({ kind: 'call', id, request: JSON.stringify({ jsonrpc: '2.0', id, method, params }) });
  });
  if (reply.kind !== 'reply') {
    throw new Error('no reply');
  }
  return { ...JSON.parse(reply.reply), ms: reply.ms };
}

function show(results: object): void {
  document.querySelector('#results')!.textContent = JSON.stringify(results, null, 2);
  document.title = 'done';
}

async function run(): Promise<void> {
  const query = new URLSearchParams(location.search);
  const pattern = query.get('pattern') ?? 'skirt-pieces.sloper';
  const measurements = query.get('measurements') ?? 'skirt-small.slm';
  const pageStart = performance.now();
  const load = await new Promise<FromWorker>((resolve) => {
    loaded = resolve;
    send({ kind: 'load', url: new URL('./engine_lib.wasm', import.meta.url).href });
  });
  const files: Record<string, string> = {};
  for (const name of [pattern, measurements]) {
    files[name] = await (await fetch(`../../../../tests/patterns/${name}`)).text();
  }
  send({ kind: 'files', files });
  const open = await call('open', { path: `/data/${pattern}`, measurements: `/data/${measurements}` });
  const check = await call('check');
  const render = await call('render', { format: 'svg' });
  document.querySelector('#drawing')!.innerHTML = render.result?.svg ?? '';
  const firstDrawMs = performance.now() - pageStart;
  const edits: number[] = [];
  for (let index = 0; index < 100; index++) {
    edits.push((await call('set_formula', { name: 'A', field: 'x', formula: String((index % 10) / 10) })).ms);
  }
  edits.sort((a, b) => a - b);
  show({
    load,
    // From the page's script starting to the drawing shown: loading the
    // engine, fetching the files, opening, checking and drawing
    firstDrawMs,
    open: { ms: open.ms, objects: open.result?.objects, error: open.error ?? open.result?.measurementError },
    problems: check.result?.problems,
    render: { ms: render.ms, length: render.result?.svg?.length, error: render.error },
    editMs: { median: edits[50], slowest: edits[99] },
    svg: render.result?.svg,
  });
}

run().catch((error) => show({ failed: String(error) }));
