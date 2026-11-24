/*
  OpenSloper - parametric sewing pattern drafting
  Copyright (C) 2026 The OpenSloper authors

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

// The browser provides files and displays the desktop layout engine's results.
import { Engine } from '../engine/engine.ts';
import { downloadBlob, downloadText } from '../ui/download.ts';

interface Output {
  kind: string;
  paper: string;
  rollWidth: number;
  materialWidth: number;
}

interface State {
  name: string;
  output: Output;
  placed: number;
  unplaced: number;
  pages: number;
  problems: { text: string; blocking: boolean }[];
  canUndo: boolean;
  canRedo: boolean;
  text: string;
}

interface Piece {
  index: number;
  caption: string;
  x: number;
  y: number;
  rotation: number;
  flipped: boolean;
}

function required<T extends HTMLElement>(id: string, kind: new () => T): T {
  const element = document.getElementById(id);
  if (!(element instanceof kind)) throw new Error(`Missing #${id}`);
  return element;
}

const tools = required('tools', HTMLFieldSetElement);
const fileInput = required('files', HTMLInputElement);
const undo = required('undo', HTMLButtonElement);
const redo = required('redo', HTMLButtonElement);
const save = required('save', HTMLButtonElement);
const pdf = required('pdf', HTMLButtonElement);
const svg = required('svg', HTMLButtonElement);
const place = required('place', HTMLButtonElement);
const pack = required('pack', HTMLButtonElement);
const status = required('status', HTMLParagraphElement);
const kind = required('kind', HTMLSelectElement);
const paper = required('paper', HTMLSelectElement);
const width = required('width', HTMLInputElement);
const piece = required('piece', HTMLSelectElement);
const placement = required('placement', HTMLFormElement);
const x = required('x', HTMLInputElement);
const y = required('y', HTMLInputElement);
const rotation = required('rotation', HTMLSelectElement);
const flipped = required('flipped', HTMLInputElement);
const preview = required('preview', HTMLImageElement);
const FILE_LIMIT = 32 * 1024 * 1024;

let engine: Engine;
let state: State | undefined;
let pieces: Piece[] = [];
let savedText = '';
let previewUrl = '';

function message(value: string, error = false): void {
  status.textContent = value;
  status.toggleAttribute('data-error', error);
}

function call(method: string, params: object = {}): ReturnType<Engine['call']> {
  return engine.call(`publish_${method}`, params);
}

function label(): string {
  return state?.name === undefined || state.name === '' ? 'Layout' : state.name;
}

function showName(): void {
  required('name', HTMLSpanElement).textContent = label() + (state?.text === savedText ? '' : ' • Unsaved');
}

function showOutput(): void {
  const output = state?.output;
  const tiled = kind.value === 'tiled';
  const hasWidth = kind.value === 'large' || kind.value === 'material';
  required('tiled-options', HTMLLabelElement).hidden = !tiled;
  required('width-options', HTMLLabelElement).hidden = !hasWidth;
  width.disabled = !hasWidth;
  width.value = String(kind.value === 'large' ? (output?.rollWidth ?? 900) : (output?.materialWidth ?? 1500));
}

function selectedPiece(): Piece | undefined {
  return pieces.find((item) => String(item.index) === piece.value);
}

function showPlacement(): void {
  const item = selectedPiece();
  placement.hidden = item === undefined;
  if (item === undefined) return;
  x.value = String(item.x);
  y.value = String(item.y);
  rotation.value = String(item.rotation);
  flipped.checked = item.flipped;
}

function render(result: State, placed: Piece[], image: string): void {
  state = result;
  pieces = placed;
  required('workspace', HTMLDivElement).hidden = false;
  showName();
  save.disabled = false;
  undo.disabled = !state.canUndo;
  redo.disabled = !state.canRedo;
  place.disabled = state.unplaced === 0;
  pack.disabled = state.placed === 0;
  const exportDisabled = state.placed === 0 || state.problems.some((problem) => problem.blocking);
  pdf.disabled = exportDisabled;
  svg.disabled = exportDisabled;
  kind.value = state.output.kind;
  paper.replaceChildren(
    ...[...new Set([state.output.paper, 'A4', 'A3', 'Letter'])].map((name) => new Option(name, name)),
  );
  paper.value = state.output.paper;
  showOutput();
  const selection = piece.value;
  piece.replaceChildren(...pieces.map((item) => new Option(item.caption, String(item.index))));
  if (pieces.some((item) => String(item.index) === selection)) piece.value = selection;
  showPlacement();
  const list = required('problems', HTMLUListElement);
  list.replaceChildren(
    ...state.problems.map((problem) => {
      const row = document.createElement('li');
      row.textContent = problem.text;
      return row;
    }),
  );
  required('problem-panel', HTMLElement).hidden = state.problems.length === 0;
  const pages = state.pages === 1 ? '1 page' : `${String(state.pages)} pages`;
  required('summary', HTMLElement).textContent =
    `${String(state.placed)} placed · ${String(state.unplaced)} waiting · ${pages}`;
  const nextUrl = URL.createObjectURL(new Blob([image], { type: 'image/svg+xml' }));
  preview.src = nextUrl;
  if (previewUrl !== '') URL.revokeObjectURL(previewUrl);
  previewUrl = nextUrl;
}

async function refresh(incoming?: Awaited<ReturnType<Engine['call']>>): Promise<void> {
  const snapshot = incoming ?? (await call('state'));
  const listing = await call('list_pieces');
  const drawing = await call('preview');
  if (typeof snapshot.text !== 'string' || !Array.isArray(listing.placed) || typeof drawing.svg !== 'string') {
    throw new Error('Invalid layout engine reply');
  }
  // These are the fields serialized by the layout API.
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion
  render(snapshot as unknown as State, listing.placed as Piece[], drawing.svg);
}

function run(task: () => Promise<void>): void {
  tools.disabled = true;
  message('');
  async function perform(): Promise<void> {
    try {
      await task();
    } catch (error: unknown) {
      message(error instanceof Error ? error.message : String(error), true);
    } finally {
      tools.disabled = false;
    }
  }
  void perform();
}

function edit(method: string, params: object = {}): void {
  run(async () => {
    const result = await call(method, params);
    if (result.done === false) throw new Error(String(result.reason));
    await refresh();
  });
}

async function readFiles(selected: File[]): Promise<Record<string, string>> {
  if (selected.reduce((total, file) => total + file.size, 0) > FILE_LIMIT) {
    throw new Error('The selected files exceed 32 MB');
  }
  if (new Set(selected.map((file) => file.name)).size !== selected.length) {
    throw new Error('Choose files with distinct names');
  }
  const entries = await Promise.all(selected.map(async (file) => [file.name, await file.text()] as const));
  return Object.fromEntries(entries);
}

required('open', HTMLButtonElement).addEventListener('click', () => {
  fileInput.click();
});
fileInput.addEventListener('change', () => {
  const selected = Array.from(fileInput.files ?? []);
  fileInput.value = '';
  if (selected.length === 0) return;
  if (state !== undefined && state.text !== savedText && !window.confirm('Discard unsaved changes?')) return;
  run(async () => {
    const files = await readFiles(selected);
    const result = await call('open', { files });
    await refresh(result);
    savedText = selected.some((file) => file.name.toLowerCase().endsWith('.slayout')) ? (state?.text ?? '') : '';
    showName();
  });
});
save.addEventListener('click', () => {
  if (state === undefined) return;
  downloadText(`${label()}.slayout`, state.text);
  savedText = state.text;
  showName();
});
undo.addEventListener('click', () => {
  edit('undo');
});
redo.addEventListener('click', () => {
  edit('redo');
});
place.addEventListener('click', () => {
  edit('place_pieces');
});
pack.addEventListener('click', () => {
  edit('pack');
});
kind.addEventListener('change', showOutput);
piece.addEventListener('change', showPlacement);
required('output', HTMLFormElement).addEventListener('submit', (event) => {
  event.preventDefault();
  const params = { kind: kind.value };
  switch (kind.value) {
    case 'tiled':
      edit('set_output', { ...params, paper: paper.value });
      break;
    case 'large':
      edit('set_output', { ...params, rollWidth: width.valueAsNumber });
      break;
    case 'material':
      edit('set_output', { ...params, materialWidth: width.valueAsNumber });
      break;
    default:
      edit('set_output', params);
  }
});
placement.addEventListener('submit', (event) => {
  event.preventDefault();
  const item = selectedPiece();
  if (item !== undefined) {
    edit('set_placement', {
      index: item.index,
      x: x.valueAsNumber,
      y: y.valueAsNumber,
      rotation: Number(rotation.value),
      flipped: flipped.checked,
    });
  }
});
required('remove', HTMLButtonElement).addEventListener('click', () => {
  const item = selectedPiece();
  if (item !== undefined) edit('remove_piece', { index: item.index });
});
pdf.addEventListener('click', () => {
  run(async () => {
    const reply = await call('export_pdf');
    if (typeof reply.pdf !== 'string') throw new Error('Invalid PDF reply');
    const bytes = Uint8Array.from(atob(reply.pdf), (character) => character.charCodeAt(0));
    downloadBlob(`${label()}.pdf`, new Blob([bytes], { type: 'application/pdf' }));
  });
});
svg.addEventListener('click', () => {
  run(async () => {
    const reply = await call('export_svg');
    if (typeof reply.svg !== 'string') throw new Error('Invalid SVG reply');
    downloadText(`${label()}.svg`, reply.svg, 'image/svg+xml');
  });
});
window.addEventListener('beforeunload', (event) => {
  if (state !== undefined && state.text !== savedText) event.preventDefault();
});

async function start(): Promise<void> {
  const loaded = await Engine.start(
    new URL('./worker.js', import.meta.url),
    new URL('./engine_lib.wasm', import.meta.url),
  );
  engine = loaded.engine;
  message('');
  tools.disabled = false;
}
start().catch((error: unknown) => {
  message(String(error), true);
});
