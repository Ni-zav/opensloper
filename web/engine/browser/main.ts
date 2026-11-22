// The spike's page: loads the engine in a worker, gives it a regression
// pattern as text, then opens, checks and draws it, and times a run of edits.
// Results go in #results as JSON, and the drawing in #drawing.
import { Engine } from '../../src/engine/engine.ts';
import { numberField, stringField, stringsField } from '../../src/engine/replies.ts';

const EDIT_COUNT = 100;

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

async function fetchText(name: string): Promise<string> {
  const response = await fetch(`../../../../tests/patterns/${name}`);
  if (!response.ok) {
    throw new Error(`could not fetch ${name}: ${response.status.toString()}`);
  }
  return response.text();
}

async function run(): Promise<void> {
  const query = new URLSearchParams(location.search);
  const pattern = query.get('pattern') ?? 'skirt-pieces.sloper';
  const measurements = query.get('measurements') ?? 'skirt-small.slm';
  const pageStart = performance.now();
  const { engine, loaded: load } = await Engine.start(
    new URL('./worker.js', import.meta.url),
    new URL('./engine_lib.wasm', import.meta.url),
  );
  const [patternText, measurementText] = await Promise.all([fetchText(pattern), fetchText(measurements)]);
  const open = await engine.callTimed('open', { text: patternText });
  await engine.call('use_measurements', { text: measurementText });
  const check = await engine.callTimed('check');
  const render = await engine.callTimed('render', { format: 'svg' });
  const svg = stringField(render.result, 'svg') ?? '';
  element('drawing').innerHTML = svg;
  const firstDrawMs = performance.now() - pageStart;
  const edits: number[] = [];
  for (let index = 0; index < EDIT_COUNT; index++) {
    const formula = String((index % 10) / 10);
    // One after another, as a drag sends them: each is timed on its own
    // oxlint-disable-next-line no-await-in-loop
    edits.push((await engine.callTimed('set_formula', { name: 'A', field: 'x', formula })).ms);
  }
  edits.sort((a, b) => a - b);
  show({
    load,
    // From the page's script starting to the drawing shown: loading the
    // engine, fetching the files, opening, checking and drawing
    firstDrawMs,
    open: { ms: open.ms, objects: numberField(open.result, 'objects') },
    problems: stringsField(check.result, 'problems'),
    render: { ms: render.ms, length: svg.length },
    editMs: { median: edits[EDIT_COUNT / 2], slowest: edits[EDIT_COUNT - 1] },
    svg,
  });
}

run().catch((error: unknown) => {
  show({ failed: String(error) });
});
