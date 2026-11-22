// The spike's page: loads the engine in a worker, gives it a regression
// pattern as text, then opens, checks and draws it, and times a run of edits.
// Results go in #results as JSON, and the drawing in #drawing.
import type { FromWorker, Loaded, ToWorker } from './messages';
import { numberField, parseReply, stringField, stringsField, type Reply } from './replies';

const EDIT_COUNT = 100;

const worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
const waiting = new Map<number, (message: FromWorker) => void>();
let loaded: ((message: Loaded) => void) | undefined;
let nextId = 1;

function element(id: string): HTMLElement {
  const found = document.getElementById(id);
  if (found === null) {
    throw new Error(`the page has no #${id}`);
  }
  return found;
}

function show(results: object): void {
  element('results').textContent = JSON.stringify(results, null, 2);
  document.title = 'done';
}

worker.addEventListener('message', (event: MessageEvent<FromWorker>) => {
  const message = event.data;
  switch (message.kind) {
    case 'reply':
      waiting.get(message.id)?.(message);
      waiting.delete(message.id);
      break;
    case 'loaded':
      loaded?.(message);
      break;
    case 'failed':
      show({ failed: message.message });
      break;
  }
});

function send(message: ToWorker): void {
  worker.postMessage(message);
}

async function call(method: string, params: object = {}): Promise<Reply> {
  const id = nextId++;
  const message = await new Promise<FromWorker>((resolve) => {
    waiting.set(id, resolve);
    send({ kind: 'call', id, request: JSON.stringify({ jsonrpc: '2.0', id, method, params }) });
  });
  if (message.kind !== 'reply') {
    throw new Error(`no reply to ${method}`);
  }
  return parseReply(message.reply, message.ms);
}

async function fetchText(name: string): Promise<[string, string]> {
  const response = await fetch(`../../../../tests/patterns/${name}`);
  if (!response.ok) {
    throw new Error(`could not fetch ${name}: ${response.status.toString()}`);
  }
  return [name, await response.text()];
}

async function run(): Promise<void> {
  const query = new URLSearchParams(location.search);
  const pattern = query.get('pattern') ?? 'skirt-pieces.sloper';
  const measurements = query.get('measurements') ?? 'skirt-small.slm';
  const pageStart = performance.now();
  const load = await new Promise<Loaded>((resolve) => {
    loaded = resolve;
    send({ kind: 'load', url: new URL('./engine_lib.wasm', import.meta.url).href });
  });
  send({ kind: 'files', files: Object.fromEntries(await Promise.all([fetchText(pattern), fetchText(measurements)])) });
  const open = await call('open', { path: `/data/${pattern}`, measurements: `/data/${measurements}` });
  const check = await call('check');
  const render = await call('render', { format: 'svg' });
  const svg = stringField(render.result, 'svg') ?? '';
  element('drawing').innerHTML = svg;
  const firstDrawMs = performance.now() - pageStart;
  const edits: number[] = [];
  for (let index = 0; index < EDIT_COUNT; index++) {
    const formula = String((index % 10) / 10);
    // One after another, as a drag sends them: each is timed on its own
    // oxlint-disable-next-line no-await-in-loop
    edits.push((await call('set_formula', { name: 'A', field: 'x', formula })).ms);
  }
  edits.sort((a, b) => a - b);
  show({
    load,
    // From the page's script starting to the drawing shown: loading the
    // engine, fetching the files, opening, checking and drawing
    firstDrawMs,
    open: {
      ms: open.ms,
      objects: numberField(open.result, 'objects'),
      error: open.error?.message ?? stringField(open.result, 'measurementError'),
    },
    problems: stringsField(check.result, 'problems'),
    render: { ms: render.ms, length: svg.length, error: render.error?.message },
    editMs: { median: edits[EDIT_COUNT / 2], slowest: edits[EDIT_COUNT - 1] },
    svg,
  });
}

run().catch((error: unknown) => {
  show({ failed: String(error) });
});
