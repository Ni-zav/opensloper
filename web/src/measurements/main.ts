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

// File contents and edits go to the same document class the desktop uses.
import { Engine } from '../engine/engine.ts';
import { downloadText } from '../ui/download.ts';

interface Measurement {
  key: string;
  description: string;
  value?: number;
  values?: (number | null)[];
}

interface MeasurementSet {
  name: string;
  notes: string;
  sizes?: string[];
  measurements: Measurement[];
}

function required<T extends HTMLElement>(id: string, kind: new () => T): T {
  const element = document.getElementById(id);
  if (!(element instanceof kind)) throw new Error(`Missing #${id}`);
  return element;
}

const editor = required('editor', HTMLFieldSetElement);
const file = required('file', HTMLInputElement);
const undo = required('undo', HTMLButtonElement);
const redo = required('redo', HTMLButtonElement);
const fileLabel = required('file-name', HTMLSpanElement);
const status = required('status', HTMLParagraphElement);
const nameField = required('name', HTMLInputElement);
const notes = required('notes', HTMLTextAreaElement);
const columns = required('columns', HTMLTableRowElement);
const rows = required('rows', HTMLTableSectionElement);
const empty = required('empty', HTMLParagraphElement);
const sizeName = required('size-name', HTMLInputElement);
const MAX_FILE_BYTES = 8 * 1024 * 1024;
const UNTITLED = 'Untitled.slm';

let engine: Engine;
let text = '';
let savedText = '';
let fileName = UNTITLED;
let pending = Promise.resolve();
let editsPending = 0;
const drafts = new WeakSet<HTMLElement>();

function message(value: string, error = false): void {
  status.textContent = value;
  status.toggleAttribute('data-error', error);
}

function showFileName(): void {
  fileLabel.textContent = fileName + (text === savedText ? '' : ' • Unsaved');
}

async function call(method: string, params: object = {}): Promise<void> {
  const reply = await engine.call(`measure_${method}`, params);
  if (typeof reply.text !== 'string') throw new Error('Invalid measurements engine reply');
  text = reply.text;
  undo.disabled = reply.canUndo !== true;
  redo.disabled = reply.canRedo !== true;
  showFileName();
}

function measurementSet(): MeasurementSet {
  // The engine returned a TMeasurementSet snapshot after validating the file.
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion
  return JSON.parse(text) as MeasurementSet;
}

function queue(edit: () => Promise<void>, restore?: () => void): void {
  editsPending += 1;
  async function run(): Promise<void> {
    try {
      message('');
      await edit();
    } catch (error: unknown) {
      restore?.();
      message(error instanceof Error ? error.message : String(error), true);
    } finally {
      editsPending -= 1;
    }
  }
  pending = pending.then(run);
}

// Text field edits leave the table intact for keyboard navigation. Commands
// that change its structure wait for pending edits before replacing the rows.
function change(method: string, params: object = {}, after?: () => void): void {
  editor.disabled = true;
  queue(async () => {
    try {
      await call(method, params);
      render();
    } finally {
      editor.disabled = false;
    }
    after?.();
  });
}

function editText(
  field: HTMLInputElement | HTMLTextAreaElement,
  method: string,
  params: object,
  current: (set: MeasurementSet) => string,
): void {
  field.addEventListener('input', () => {
    drafts.add(field);
  });
  field.addEventListener('change', () => {
    drafts.delete(field);
    const value = field.value;
    queue(
      () => call(method, { ...params, text: value }),
      () => {
        field.value = current(measurementSet());
      },
    );
  });
}

function textInput(label: string, value: string): HTMLInputElement {
  const field = document.createElement('input');
  field.setAttribute('aria-label', label);
  field.value = value;
  return field;
}

function action(caption: string, label: string, click: () => void, disabled = false): HTMLButtonElement {
  const button = document.createElement('button');
  button.type = 'button';
  button.textContent = caption;
  button.setAttribute('aria-label', label);
  button.disabled = disabled;
  button.addEventListener('click', click);
  return button;
}

function moveAndDelete(
  kind: 'row' | 'size',
  index: number,
  count: number,
  label: string,
  key: 'row' | 'column',
): HTMLDivElement {
  const actions = document.createElement('div');
  actions.className = 'actions';
  const directions = kind === 'row' ? ['up', 'down'] : ['left', 'right'];
  actions.append(
    action(
      kind === 'row' ? '↑' : '←',
      `Move ${label} ${directions[0] ?? ''}`,
      () => {
        change(`move_${kind}`, { [key]: index, target: index - 1 });
      },
      index === 0,
    ),
    action(
      kind === 'row' ? '↓' : '→',
      `Move ${label} ${directions[1] ?? ''}`,
      () => {
        change(`move_${kind}`, { [key]: index, target: index + 1 });
      },
      index === count - 1,
    ),
    action(
      'Remove',
      `Remove ${label}`,
      () => {
        change(`delete_${kind}`, { [key]: index });
      },
      kind === 'size' && count === 1,
    ),
  );
  return actions;
}

function header(label: string): HTMLTableCellElement {
  const cell = document.createElement('th');
  cell.scope = 'col';
  cell.textContent = label;
  return cell;
}

function readValue(item: Measurement | undefined, column: number): string {
  const value = item?.values === undefined ? item?.value : item.values[column];
  return value === null || value === undefined ? '' : String(value);
}

function valueInput(item: Measurement, row: number, column: number, size: string | undefined): HTMLInputElement {
  const field = textInput(
    size === undefined ? `${item.key} (mm)` : `${item.key}, ${size} (mm)`,
    readValue(item, column),
  );
  field.type = 'number';
  field.step = 'any';
  field.addEventListener('input', () => {
    drafts.add(field);
  });
  field.addEventListener('change', () => {
    drafts.delete(field);
    const invalid = field.validity.badInput;
    const value = field.valueAsNumber;
    queue(
      async () => {
        if (invalid) throw new Error('Enter a number in millimetres');
        await call('set_value', Number.isFinite(value) ? { row, column, value } : { row, column });
      },
      () => {
        field.value = readValue(measurementSet().measurements[row], column);
      },
    );
  });
  return field;
}

function render(): void {
  const set = measurementSet();
  const sizes = set.sizes ?? [];
  nameField.value = set.name;
  notes.value = set.notes;
  columns.replaceChildren(header('Key'), header('Description'));
  if (sizes.length === 0) columns.append(header('Value (mm)'));
  sizes.forEach((size, column) => {
    const field = textInput(`Size ${size}`, size);
    editText(field, 'rename_size', { column }, (current) => current.sizes?.[column] ?? '');
    const cell = header('');
    cell.append(field, moveAndDelete('size', column, sizes.length, size, 'column'));
    columns.append(cell);
  });
  columns.append(header('Actions'));
  rows.replaceChildren();
  set.measurements.forEach((item, row) => {
    const line = rows.insertRow();
    const key = textInput(`Key for ${item.key}`, item.key);
    const description = textInput(`Description for ${item.key}`, item.description);
    editText(key, 'rename_row', { row }, (current) => current.measurements[row]?.key ?? '');
    editText(description, 'describe_row', { row }, (current) => current.measurements[row]?.description ?? '');
    line.insertCell().append(key);
    const descriptionCell = line.insertCell();
    descriptionCell.className = 'description';
    descriptionCell.append(description);
    for (let column = 0; column < Math.max(sizes.length, 1); column += 1) {
      line.insertCell().append(valueInput(item, row, column, sizes[column]));
    }
    line.insertCell().append(moveAndDelete('row', row, set.measurements.length, item.key, 'row'));
  });
  empty.hidden = set.measurements.length > 0;
}

function replace(read: () => Promise<{ name: string; contents?: string }>): void {
  editor.disabled = true;
  queue(async () => {
    try {
      if (text !== savedText && !window.confirm('Discard unsaved changes?')) return;
      const incoming = await read();
      if (incoming.contents === undefined) {
        await call('new');
      } else {
        await call('open', { text: incoming.contents });
      }
      fileName = incoming.name;
      savedText = text;
      showFileName();
      render();
    } finally {
      editor.disabled = false;
    }
  });
}

required('new', HTMLButtonElement).addEventListener('click', () => {
  replace(() => Promise.resolve({ name: UNTITLED }));
});
required('open', HTMLButtonElement).addEventListener('click', () => {
  file.click();
});
file.addEventListener('change', () => {
  const selected = file.files?.[0];
  file.value = '';
  if (selected === undefined) return;
  replace(async () => {
    if (selected.size > MAX_FILE_BYTES) throw new Error('The measurement file exceeds 8 MB');
    return { name: selected.name, contents: await selected.text() };
  });
});
required('save', HTMLButtonElement).addEventListener('click', () => {
  queue(() => {
    downloadText(fileName, text);
    savedText = text;
    showFileName();
    message(`Download requested for ${fileName}`);
    return Promise.resolve();
  });
});
undo.addEventListener('click', () => {
  change('undo');
});
redo.addEventListener('click', () => {
  change('redo');
});
editText(nameField, 'name', {}, (set) => set.name);
editText(notes, 'notes', {}, (set) => set.notes);
required('add-row', HTMLButtonElement).addEventListener('click', () => {
  change('add_row', {}, () => rows.lastElementChild?.querySelector('input')?.focus());
});
required('add-size', HTMLFormElement).addEventListener('submit', (event) => {
  event.preventDefault();
  change('add_size', { text: sizeName.value }, () => {
    sizeName.value = '';
    sizeName.focus();
  });
});
window.addEventListener('beforeunload', (event) => {
  const active = document.activeElement;
  if (text !== savedText || editsPending > 0 || (active instanceof HTMLElement && drafts.has(active)))
    event.preventDefault();
});

async function start(): Promise<void> {
  const loaded = await Engine.start(
    new URL('./worker.js', import.meta.url),
    new URL('./engine_lib.wasm', import.meta.url),
  );
  engine = loaded.engine;
  await call('state');
  savedText = text;
  showFileName();
  render();
  message('');
  editor.disabled = false;
}

start().catch((error: unknown) => {
  message(String(error), true);
});
