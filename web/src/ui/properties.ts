// The properties tab of the side panel, as Sloper.UI.Properties: the selected
// object's name, formulas and other properties, and what it computes to, one
// to a row with the caption on the left and the value on the right. The rows
// come from the engine (editor_properties), which says what each object shows,
// so the panel only draws them. Enter or leaving a field commits it as one
// undo step and Escape puts it back; a refused entry keeps its text, with the
// reason under it in red. Choices, the Locked box and buttons commit at once.
import type { DocumentChange, PatternDocument } from '../document/patternDocument.ts';
import {
  booleanField,
  idField,
  numberField,
  recordsField,
  stringField,
  stringsField,
  type JsonRecord,
} from '../engine/replies.ts';
import { FormulaCompleter } from './formulaCompleter.ts';
import { LatestOnly } from './latestOnly.ts';
import type { SideTabContent } from './sideTabs.ts';

// As TPropertyRowKind
type PropertyRowKind = 'text' | 'name' | 'formula' | 'choice' | 'check' | 'button' | 'problem';
const ROW_KINDS: readonly PropertyRowKind[] = ['text', 'name', 'formula', 'choice', 'check', 'button', 'problem'];
// The row that stays usable on a locked object
const LOCKED_ROW = 'locked';

interface PropertyRow {
  id: string;
  kind: PropertyRowKind;
  caption: string;
  text: string;
  field: string;
  choices: string[];
  choice: number;
  checked: boolean;
  hint: string;
}

interface Properties {
  // The object shown, or undefined with the title to show instead
  id: string | undefined;
  title: string;
  locked: boolean;
  rows: PropertyRow[];
}

// The object as editor_property_set takes it: by ID, or by key for a repeat's point
function targetParams(target: string): Record<string, unknown> {
  return /^\d+$/.test(target) ? { id: Number(target) } : { name: target };
}

function isRowKind(name: string): name is PropertyRowKind {
  return (ROW_KINDS as readonly string[]).includes(name);
}

function parseRow(row: JsonRecord): PropertyRow {
  const kind = stringField(row, 'kind') ?? '';
  return {
    id: stringField(row, 'id') ?? '',
    kind: isRowKind(kind) ? kind : 'text',
    caption: stringField(row, 'caption') ?? '',
    text: stringField(row, 'text') ?? '',
    field: stringField(row, 'field') ?? '',
    choices: stringsField(row, 'choices') ?? [],
    choice: numberField(row, 'choice') ?? -1,
    checked: booleanField(row, 'checked') ?? false,
    hint: stringField(row, 'hint') ?? '',
  };
}

function parseProperties(answer: JsonRecord): Properties {
  return {
    id: idField(answer, 'id'),
    title: stringField(answer, 'title') ?? '',
    locked: booleanField(answer, 'locked') ?? false,
    rows: recordsField(answer, 'rows').map(parseRow),
  };
}

// The rows' controls are built again only when this changes: another object,
// or rows added or taken away, as a marker's size when it stops being plain
function layoutOf(properties: Properties): string {
  return JSON.stringify([
    properties.id ?? properties.title,
    properties.rows.map((row) => [row.id, row.kind, row.choices]),
  ]);
}

// A row's value control and what the panel does with it
interface RowControl {
  row: PropertyRow;
  // The control, for the read-only and disabled states
  control: HTMLInputElement | HTMLSelectElement | HTMLButtonElement | HTMLElement;
  // A text or problem row's text
  text?: HTMLElement;
  // A name or formula field, with the reason it was refused under it
  field?: HTMLInputElement;
  refusal?: HTMLElement;
}

export interface PropertiesEvents {
  // Says why a change was refused
  message(text: string): void;
  failed(error: unknown): void;
}

export class PropertiesPanel implements SideTabContent {
  readonly element: HTMLElement;
  private readonly document: PatternDocument;
  private readonly events: PropertiesEvents;
  private readonly grid: HTMLElement;
  private readonly loads: LatestOnly<boolean>;
  private readonly completer: FormulaCompleter;
  private selection: string[] = [];
  private shown = false;
  // Changes came while the tab was hidden
  private stale = true;
  private layout = '';
  private current: Properties = { id: undefined, title: '', locked: false, rows: [] };
  private controls: RowControl[] = [];
  private readonly listener = (_document: PatternDocument, changes: ReadonlySet<DocumentChange>): void => {
    if (changes.has('pattern') || changes.has('objectsReplaced') || changes.has('measurements')) {
      this.reload(changes.has('objectsReplaced'));
    }
  };

  constructor(document: PatternDocument, events: PropertiesEvents) {
    this.document = document;
    this.events = events;
    this.element = window.document.createElement('div');
    this.element.className = 'properties';
    this.grid = window.document.createElement('div');
    this.grid.className = 'property-grid';
    this.element.append(this.grid);
    const failed = (error: unknown): void => {
      events.failed(error);
    };
    this.loads = new LatestOnly(async (replaced) => this.load(replaced), failed);
    this.completer = new FormulaCompleter(document, failed);
    document.addListener(this.listener);
  }

  setShown(shown: boolean): void {
    this.shown = shown;
    if (shown && this.stale) {
      this.reload(false);
    }
    if (!shown) {
      this.completer.hide();
    }
  }

  // Shows the object when one is selected, else what the selection is
  showSelection(ids: readonly string[]): void {
    if (ids.join(' ') === this.selection.join(' ')) {
      return;
    }
    this.selection = [...ids];
    this.reload(false);
  }

  dispose(): void {
    this.document.removeListener(this.listener);
    this.completer.dispose();
    this.element.remove();
  }

  // Replaced says undo, redo or opening replaced the objects, so even the
  // field being typed in follows the pattern
  private reload(replaced: boolean): void {
    if (!this.shown) {
      this.stale = true;
      return;
    }
    this.stale = false;
    this.loads.push(replaced);
  }

  private async load(replaced: boolean): Promise<void> {
    const selection = this.selection.map((id) => (/^\d+$/.test(id) ? Number(id) : id));
    const properties = parseProperties(await this.document.read('editor_properties', { selection }));
    const layout = layoutOf(properties);
    this.current = properties;
    if (layout !== this.layout) {
      this.layout = layout;
      this.build();
    }
    this.fill(replaced);
  }

  private build(): void {
    this.completer.hide();
    this.controls = [];
    this.grid.replaceChildren();
    const { id, title, rows } = this.current;
    if (id === undefined) {
      const empty = window.document.createElement('div');
      empty.className = 'property-title';
      empty.textContent = title;
      this.grid.append(empty);
      return;
    }
    for (const row of rows) {
      this.controls.push(this.addRow(id, row));
    }
  }

  private addRow(target: string, row: PropertyRow): RowControl {
    if (row.kind === 'problem') {
      const problem = window.document.createElement('div');
      problem.className = 'property-problem';
      problem.dataset.row = row.id;
      this.grid.append(problem);
      return { row, control: problem, text: problem };
    }
    const caption = window.document.createElement('label');
    caption.className = 'property-caption';
    caption.textContent = row.caption;
    caption.title = row.caption;
    const value = window.document.createElement('div');
    value.className = 'property-value';
    value.dataset.row = row.id;
    this.grid.append(caption, value);
    const control = this.makeControl(target, row, value);
    if (row.hint !== '') {
      control.control.title = row.hint;
    }
    if (control.control !== value) {
      const controlId = `property-${row.id}`;
      control.control.id = controlId;
      caption.htmlFor = controlId;
    }
    return control;
  }

  private makeControl(target: string, row: PropertyRow, value: HTMLElement): RowControl {
    switch (row.kind) {
      case 'name':
      case 'formula':
        return this.makeField(target, row, value);
      case 'choice': {
        const box = window.document.createElement('select');
        row.choices.forEach((choice, index) => {
          box.add(new Option(choice, String(index)));
        });
        box.addEventListener('change', () => {
          this.commitRow(target, row.id, Number(box.value));
        });
        value.append(box);
        return { row, control: box };
      }
      case 'check': {
        const box = window.document.createElement('input');
        box.type = 'checkbox';
        box.addEventListener('change', () => {
          this.commitRow(target, row.id, box.checked ? 1 : 0);
        });
        value.append(box);
        return { row, control: box };
      }
      case 'button': {
        const button = window.document.createElement('button');
        button.type = 'button';
        button.addEventListener('click', () => {
          this.commitRow(target, row.id, 0);
        });
        value.append(button);
        return { row, control: button };
      }
      case 'text':
      case 'problem':
        break;
    }
    const text = window.document.createElement('span');
    text.className = 'property-text';
    value.append(text);
    return { row, control: value, text };
  }

  // A name or formula: typing marks it, so a refresh keeps the text until it is committed or put back
  private makeField(target: string, row: PropertyRow, value: HTMLElement): RowControl {
    const field = window.document.createElement('input');
    field.type = 'text';
    field.spellcheck = false;
    field.autocomplete = 'off';
    const refusal = window.document.createElement('div');
    refusal.className = 'property-refusal';
    refusal.hidden = true;
    value.append(field, refusal);
    const control: RowControl = { row, control: field, field, refusal };
    const formula = row.kind === 'formula';
    const complete = (explicit: boolean): void => {
      if (formula && !field.readOnly) {
        this.completer.update(field, /^\d+$/.test(target) ? Number(target) : undefined, explicit);
      }
    };
    field.addEventListener('input', () => {
      field.dataset.typed = 'true';
      complete(false);
    });
    field.addEventListener('keydown', (event) => {
      if (formula && this.completer.handleKey(event)) {
        return;
      }
      if (formula && event.key === ' ' && event.ctrlKey) {
        complete(true);
        event.preventDefault();
      } else if (event.key === 'Enter') {
        this.commitField(target, control);
        event.preventDefault();
      } else if (event.key === 'Escape') {
        this.putBack(control);
        event.preventDefault();
      }
    });
    field.addEventListener('blur', () => {
      this.completer.hide();
      this.commitField(target, control);
    });
    return control;
  }

  // Shows the values in the rows built; a field typed in keeps its text
  private fill(replaced: boolean): void {
    const locked = this.current.locked;
    for (const [index, control] of this.controls.entries()) {
      const row = this.current.rows[index];
      if (row === undefined) {
        continue;
      }
      control.row = row;
      const { field, text } = control;
      if (field !== undefined) {
        if (replaced || field.dataset.typed !== 'true') {
          this.setFieldText(control, row.text);
        }
        field.readOnly = locked;
      } else if (text !== undefined) {
        text.textContent = row.text;
        text.title = row.text;
        if (row.kind === 'problem') {
          text.hidden = row.text === '';
        }
      } else if (control.control instanceof HTMLSelectElement) {
        control.control.value = String(row.choice);
      } else if (control.control instanceof HTMLInputElement) {
        control.control.checked = row.checked;
      } else if (control.control instanceof HTMLButtonElement) {
        control.control.textContent = row.text;
      }
      if (
        (control.control instanceof HTMLSelectElement ||
          control.control instanceof HTMLButtonElement ||
          (control.control instanceof HTMLInputElement && control.field === undefined)) &&
        row.id !== LOCKED_ROW
      ) {
        control.control.disabled = locked;
      }
    }
  }

  private setFieldText(control: RowControl, text: string): void {
    if (control.field === undefined) {
      return;
    }
    control.field.value = text;
    delete control.field.dataset.typed;
    this.showRefusal(control, '');
  }

  private showRefusal(control: RowControl, reason: string): void {
    if (control.refusal === undefined || control.field === undefined) {
      return;
    }
    control.refusal.textContent = reason;
    control.refusal.hidden = reason === '';
    control.field.classList.toggle('refused', reason !== '');
  }

  private putBack(control: RowControl): void {
    this.completer.hide();
    this.setFieldText(control, control.row.text);
    control.field?.select();
  }

  private commitField(target: string, control: RowControl): void {
    const field = control.field;
    if (field === undefined || field.dataset.typed !== 'true' || field.readOnly) {
      return;
    }
    // Typed back to what it was: nothing to commit
    if (field.value === control.row.text) {
      this.setFieldText(control, field.value);
      return;
    }
    const text = field.value;
    const params: Record<string, unknown> = { ...targetParams(target), text };
    if (control.row.kind === 'formula') {
      params.field = control.row.field;
    } else {
      params.row = control.row.id;
    }
    this.document
      .call('editor_property_set', params)
      .then((answer) => {
        if (booleanField(answer, 'done') === true) {
          // The next refresh shows the formula as the pattern keeps it
          if (field.value === text) {
            delete field.dataset.typed;
          }
          this.showRefusal(control, '');
          this.reload(false);
        } else {
          this.refused(control, text, answer);
        }
        return undefined;
      })
      .catch((error: unknown) => {
        this.events.failed(error);
      });
  }

  // The text stays to be fixed, with the caret where the problem is
  private refused(control: RowControl, text: string, answer: JsonRecord): void {
    const field = control.field;
    if (field === undefined || !field.isConnected) {
      this.events.message(stringField(answer, 'reason') ?? '');
      return;
    }
    field.value = text;
    field.dataset.typed = 'true';
    this.showRefusal(control, stringField(answer, 'reason') ?? '');
    const at = numberField(answer, 'errorPos') ?? 0;
    if (at > 0 && window.document.activeElement === field) {
      field.setSelectionRange(at - 1, at - 1);
    }
  }

  // A choice, box or button: refused, the row goes back to what the object has
  private commitRow(target: string, row: string, value: number): void {
    this.document
      .call('editor_property_set', { ...targetParams(target), row, value })
      .then((answer) => {
        if (booleanField(answer, 'done') !== true) {
          this.events.message(stringField(answer, 'reason') ?? '');
          this.fill(false);
        }
        return undefined;
      })
      .catch((error: unknown) => {
        this.events.failed(error);
      });
  }
}
