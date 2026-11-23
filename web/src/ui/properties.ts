// The properties tab of the side panel, as Sloper.UI.Properties: the selected
// object's name, formulas and other properties, and what it computes to, one
// to a row with the caption on the left and the value on the right. The rows
// come from the engine (editor_properties), which says what each object shows,
// so the panel only draws them. Enter or leaving a field commits it as one
// undo step and Escape puts it back; a refused entry keeps its text, with the
// reason under it in red; a note's text takes several lines, so Enter adds
// one and Ctrl+Enter commits it. Choices, boxes, numbers, colours and buttons
// commit at once. A formula holding a number or a formula that works out has
// a wand for formulas that give about its value (FormulaSuggestList), which
// opens under the row; while it is open, dragging the point changes only
// that field, and hovering a suggestion shows on the canvas what it would do.
import type { DocumentChange, PatternDocument } from '../document/patternDocument.ts';
import { EngineError } from '../engine/engine.ts';
import {
  booleanField,
  idField,
  numberField,
  recordsField,
  stringField,
  stringsField,
  isRecord,
  type JsonRecord,
} from '../engine/replies.ts';
import { FormulaCompleter } from './formulaCompleter.ts';
import { FormulaSuggestList, type Suggestion } from './formulaSuggest.ts';
import { LatestOnly } from './latestOnly.ts';
import type { GradeGhost, SuggestPreview } from './patternPainter.ts';
import { STRINGS } from './strings.ts';
import type { SideTabContent } from './sideTabs.ts';

// As TPropertyRowKind
type PropertyRowKind =
  'text' | 'name' | 'formula' | 'choice' | 'check' | 'button' | 'problem' | 'number' | 'longText' | 'font' | 'color';
const ROW_KINDS: readonly PropertyRowKind[] = [
  'text',
  'name',
  'formula',
  'choice',
  'check',
  'button',
  'problem',
  'number',
  'longText',
  'font',
  'color',
];
// The row that stays usable on a locked object
const LOCKED_ROW = 'locked';
// A grainline between two points takes effect once both are chosen: the
// choice that asks for them, and the rows they are chosen in
const GRAIN_ROW = 'grain';
const GRAIN_POINTS = 2;
const GRAIN_FROM_ROW = 'grainFrom';
const GRAIN_TO_ROW = 'grainTo';
// The choice that gives an edge its own allowance, whose new row then takes the cursor
const OWN_ALLOWANCE_ROW = 'ownAllowance';
// The wand's icon, as the desktop's
const WAND_ICON = 'icons/wand.svg';

interface PropertyRow {
  id: string;
  kind: PropertyRowKind;
  caption: string;
  text: string;
  field: string;
  // A formula row's wand shows
  suggest: boolean;
  choices: string[];
  choice: number;
  checked: boolean;
  hint: string;
  // False when it cannot be changed now
  enabled: boolean;
  // A number row's value and range
  value: number;
  min: number;
  max: number;
  step: number;
  decimals: number;
  // A colour row's colour as drawn
  color: string;
}

interface Properties {
  // The object shown, or undefined with the title to show instead
  id: string | undefined;
  title: string;
  locked: boolean;
  rows: PropertyRow[];
}

// A colour for a colour input, which takes only #rrggbb
function colorValue(color: string): string {
  return /^#[0-9a-f]{6}$/i.test(color) ? color.toLowerCase() : '#000000';
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
    suggest: booleanField(row, 'suggest') ?? false,
    choices: stringsField(row, 'choices') ?? [],
    choice: numberField(row, 'choice') ?? -1,
    checked: booleanField(row, 'checked') ?? false,
    hint: stringField(row, 'hint') ?? '',
    enabled: booleanField(row, 'enabled') ?? true,
    value: numberField(row, 'value') ?? 0,
    min: numberField(row, 'min') ?? 0,
    max: numberField(row, 'max') ?? 0,
    step: numberField(row, 'step') ?? 1,
    decimals: numberField(row, 'decimals') ?? 0,
    color: stringField(row, 'color') ?? '',
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
  // A name, formula, long text or font field, with the reason it was refused under it
  field?: HTMLInputElement | HTMLTextAreaElement;
  refusal?: HTMLElement;
  // A colour row's colour, beside its choice
  swatch?: HTMLInputElement;
  // The row's value cell, which its suggestions open under, and a formula's wand
  cell?: HTMLElement;
  wand?: HTMLButtonElement;
}

// The suggestions open under a formula row
interface OpenSuggestions {
  target: string;
  field: string;
  list: FormulaSuggestList;
}

function vec2Of(value: unknown): { x: number; y: number } | undefined {
  if (Array.isArray(value)) {
    const x: unknown = value[0];
    const y: unknown = value[1];
    return typeof x === 'number' && typeof y === 'number' ? { x, y } : undefined;
  }
  if (isRecord(value)) {
    const x = numberField(value, 'x');
    const y = numberField(value, 'y');
    return x === undefined || y === undefined ? undefined : { x, y };
  }
  return undefined;
}

function parsePreview(answer: JsonRecord): SuggestPreview {
  const ghosts: GradeGhost[] = recordsField(answer, 'ghosts').map((ghost) => ({
    lines: Array.isArray(ghost.lines)
      ? ghost.lines.filter((line): line is number[] => Array.isArray(line) && line.every((n) => typeof n === 'number'))
      : [],
    point: vec2Of(ghost.point),
  }));
  return { position: vec2Of(answer.position), ghosts };
}

export interface PropertiesEvents {
  // Says why a change was refused
  message(text: string): void;
  failed(error: unknown): void;
  // The field whose formula suggestions are open, or empty strings when none are
  suggestChanged(id: string, field: string): void;
  // Where the suggestion hovered would put things, or undefined
  suggestPreview(preview: SuggestPreview | undefined): void;
  // A note's text as typed in the tab, for the canvas to show; undefined when typing ends
  noteText(id: string | undefined, text: string): void;
}

export class PropertiesPanel implements SideTabContent {
  readonly element: HTMLElement;
  private readonly document: PatternDocument;
  private readonly events: PropertiesEvents;
  private readonly grid: HTMLElement;
  private readonly loads: LatestOnly<boolean>;
  private readonly completer: FormulaCompleter;
  private readonly suggestions: LatestOnly<number>;
  private readonly previews: LatestOnly<Suggestion | undefined>;
  private suggest: OpenSuggestions | undefined;
  // The formula fields shown before an edge was given its own allowance: the
  // row added for it is the one not among them
  private fieldsBeforeAllowance: Set<string> | undefined;
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
    this.suggestions = new LatestOnly(async () => this.loadSuggestions(), failed);
    this.previews = new LatestOnly(async (suggestion) => this.loadPreview(suggestion), failed);
    document.addListener(this.listener);
  }

  setShown(shown: boolean): void {
    this.shown = shown;
    if (shown && this.stale) {
      this.reload(false);
    }
    if (!shown) {
      this.completer.hide();
      this.closeSuggestions();
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
    this.closeSuggestions();
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
    this.followSuggestions();
    this.focusNewAllowance();
  }

  private focusNewAllowance(): void {
    const before = this.fieldsBeforeAllowance;
    if (before === undefined) {
      return;
    }
    const added = this.controls.find((each) => each.row.kind === 'formula' && !before.has(each.row.field));
    if (added?.field !== undefined) {
      this.fieldsBeforeAllowance = undefined;
      added.field.focus();
      added.field.select();
    }
  }

  private build(): void {
    this.completer.hide();
    // Its list goes with the rows; reopened under the new ones when they show the same field
    this.suggest?.list.element.remove();
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
    control.cell = value;
    if (row.hint !== '') {
      control.control.title = row.hint;
      if (control.field !== undefined) {
        control.field.title = row.hint;
      }
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
      case 'longText':
      case 'font':
        return this.makeField(target, row, value);
      case 'choice': {
        const box = window.document.createElement('select');
        row.choices.forEach((choice, index) => {
          box.add(new Option(choice, String(index)));
        });
        box.addEventListener('change', () => {
          this.choose(target, row.id, Number(box.value));
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
        // The caption beside the box, as "Print and export it"
        const label = window.document.createElement('label');
        label.className = 'property-check';
        label.append(box, row.text);
        value.append(label);
        return { row, control: box };
      }
      case 'number':
        return this.makeNumber(target, row, value);
      case 'color':
        return this.makeColor(target, row, value);
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
    const lines = row.kind === 'longText';
    let field: HTMLInputElement | HTMLTextAreaElement;
    if (lines) {
      field = window.document.createElement('textarea');
      field.rows = 3;
      field.wrap = 'off';
    } else {
      const input = window.document.createElement('input');
      input.type = 'text';
      input.autocomplete = 'off';
      // A font row's first choice names the default font, shown while it is empty
      if (row.kind === 'font') {
        input.placeholder = row.choices[0] ?? '';
      }
      field = input;
    }
    field.spellcheck = false;
    const refusal = window.document.createElement('div');
    refusal.className = 'property-refusal';
    refusal.hidden = true;
    const control: RowControl = { row, control: field, field, refusal };
    const formula = row.kind === 'formula';
    if (formula) {
      // At the right of the field, shown while suggestions can be made
      const wand = window.document.createElement('button');
      wand.type = 'button';
      wand.className = 'property-wand';
      wand.title = STRINGS.suggestHint;
      wand.hidden = true;
      const icon = window.document.createElement('img');
      icon.src = WAND_ICON;
      icon.alt = STRINGS.suggestHint;
      wand.append(icon);
      wand.addEventListener('click', () => {
        if (this.suggest?.field === control.row.field && this.suggest.target === target) {
          this.closeSuggestions();
        } else {
          this.openSuggestions(target, control);
        }
      });
      const pair = window.document.createElement('div');
      pair.className = 'property-formula';
      pair.append(field, wand);
      value.append(pair, refusal);
      control.wand = wand;
    } else {
      value.append(field, refusal);
    }
    const complete = (explicit: boolean): void => {
      if (formula && field instanceof HTMLInputElement && !field.readOnly) {
        this.completer.update(field, /^\d+$/.test(target) ? Number(target) : undefined, explicit);
      }
    };
    field.addEventListener('input', () => {
      field.dataset.typed = 'true';
      complete(false);
      // The canvas shows a note's text as it is typed
      if (lines) {
        this.events.noteText(target, field.value);
      }
    });
    field.addEventListener('keydown', (event) => {
      if (!(event instanceof KeyboardEvent)) {
        return;
      }
      if (formula && this.completer.handleKey(event)) {
        return;
      }
      if (formula && event.key === 'ArrowDown' && event.altKey) {
        this.openSuggestions(target, control);
        event.preventDefault();
        return;
      }
      // The open list takes Up, Down, Escape, and Enter once a row is chosen
      const suggest = this.suggest;
      if (formula && suggest?.field === row.field && suggest.target === target) {
        if (event.key === 'Escape') {
          this.closeSuggestions();
          event.preventDefault();
          return;
        }
        if (suggest.list.handleKey(event)) {
          return;
        }
      }
      if (formula && event.key === ' ' && event.ctrlKey) {
        complete(true);
        event.preventDefault();
      } else if (event.key === 'Enter' && (!lines || event.ctrlKey)) {
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
      if (lines) {
        this.events.noteText(undefined, '');
      }
    });
    return control;
  }

  // Each change commits, a run of them on one row being one undo step
  private makeNumber(target: string, row: PropertyRow, value: HTMLElement): RowControl {
    const box = window.document.createElement('input');
    box.type = 'number';
    box.min = String(row.min);
    box.max = String(row.max);
    box.step = String(row.step);
    box.addEventListener('change', () => {
      const number = box.valueAsNumber;
      if (Number.isNaN(number)) {
        this.fill(false);
        return;
      }
      this.commit(target, { row: row.id, number });
    });
    value.append(box);
    return { row, control: box };
  }

  // From the material, or its own colour, chosen beside the box
  private makeColor(target: string, row: PropertyRow, value: HTMLElement): RowControl {
    const box = window.document.createElement('select');
    row.choices.forEach((choice, index) => {
      box.add(new Option(choice, String(index)));
    });
    const swatch = window.document.createElement('input');
    swatch.type = 'color';
    swatch.className = 'property-swatch';
    box.addEventListener('change', () => {
      this.commit(target, { row: row.id, text: box.value === '0' ? '' : swatch.value });
    });
    swatch.addEventListener('change', () => {
      this.commit(target, { row: row.id, text: swatch.value });
    });
    const pair = window.document.createElement('div');
    pair.className = 'property-color';
    pair.append(box, swatch);
    value.append(pair);
    return { row, control: box, swatch };
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
        if (control.wand !== undefined) {
          control.wand.hidden = !row.suggest || locked;
        }
      } else if (text !== undefined) {
        text.textContent = row.text;
        text.title = row.text;
        if (row.kind === 'problem') {
          text.hidden = row.text === '';
        }
      } else if (control.swatch !== undefined && control.control instanceof HTMLSelectElement) {
        control.control.value = row.text === '' ? '0' : '1';
        control.swatch.value = colorValue(row.color);
        control.swatch.disabled = locked;
      } else if (control.control instanceof HTMLSelectElement) {
        control.control.value = String(row.choice);
      } else if (control.control instanceof HTMLInputElement && row.kind === 'number') {
        if (window.document.activeElement !== control.control) {
          control.control.value = row.value.toFixed(row.decimals);
        }
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
        control.control.disabled = locked || !row.enabled;
      }
    }
  }

  private openSuggestions(target: string, control: RowControl): void {
    if (!control.row.suggest || this.current.locked || control.cell === undefined) {
      return;
    }
    this.closeSuggestions();
    this.completer.hide();
    const field = control.row.field;
    const list = new FormulaSuggestList({
      choose: (suggestion) => {
        this.takeSuggestion(target, field, suggestion);
      },
      hover: (suggestion) => {
        this.previews.push(suggestion);
      },
    });
    this.suggest = { target, field, list };
    this.placeSuggestions();
    this.events.suggestChanged(target, field);
    this.suggestions.push(0);
  }

  closeSuggestions(): void {
    if (this.suggest === undefined) {
      return;
    }
    this.suggest.list.element.remove();
    this.suggest = undefined;
    this.suggestions.clear();
    this.previews.clear();
    this.events.suggestPreview(undefined);
    this.events.suggestChanged('', '');
  }

  // Under the row and its refusal, across both columns
  private placeSuggestions(): boolean {
    const suggest = this.suggest;
    const control = this.controls.find((each) => each.row.kind === 'formula' && each.row.field === suggest?.field);
    if (suggest === undefined || control?.cell === undefined || !control.row.suggest || this.current.locked) {
      return false;
    }
    if (suggest.list.element.previousElementSibling !== control.cell) {
      control.cell.after(suggest.list.element);
    }
    return true;
  }

  // After the rows are shown again: the list stays under its row, with its
  // formulas worked out again, or closes when the row has gone
  private followSuggestions(): void {
    if (this.suggest === undefined) {
      return;
    }
    if (this.suggest.target !== this.current.id || !this.placeSuggestions()) {
      this.closeSuggestions();
      return;
    }
    this.suggestions.push(0);
  }

  private async loadSuggestions(): Promise<void> {
    const suggest = this.suggest;
    if (suggest === undefined) {
      return;
    }
    let answer: JsonRecord;
    try {
      answer = await this.document.read('editor_suggest', { ...targetParams(suggest.target), field: suggest.field });
    } catch (error: unknown) {
      // The field no longer holds a value that can be matched
      if (error instanceof EngineError && this.suggest === suggest) {
        this.closeSuggestions();
        return;
      }
      throw error;
    }
    if (this.suggest === suggest) {
      suggest.list.show(answer);
    }
  }

  private async loadPreview(suggestion: Suggestion | undefined): Promise<void> {
    const suggest = this.suggest;
    if (suggest === undefined || suggestion === undefined) {
      this.events.suggestPreview(undefined);
      return;
    }
    const answer = await this.document.read('editor_suggest_preview', {
      ...targetParams(suggest.target),
      field: suggest.field,
      text: suggestion.text,
      value: suggestion.value,
    });
    if (this.suggest === suggest) {
      this.events.suggestPreview(parsePreview(answer));
    }
  }

  // Closed before the commit, which makes the field a formula
  private takeSuggestion(target: string, field: string, suggestion: Suggestion): void {
    this.closeSuggestions();
    const control = this.controls.find((each) => each.row.kind === 'formula' && each.row.field === field);
    this.document
      .call('editor_property_set', { ...targetParams(target), field, text: suggestion.text })
      .then((answer) => {
        if (booleanField(answer, 'done') !== true) {
          this.events.message(stringField(answer, 'reason') ?? '');
        } else if (control !== undefined) {
          // The next refresh shows the formula taken
          this.setFieldText(control, suggestion.text);
        }
        return undefined;
      })
      .catch((error: unknown) => {
        this.events.failed(error);
      });
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
    if (control.row.kind === 'longText') {
      this.events.noteText(undefined, '');
    }
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
          // The next refresh shows the formula as the pattern keeps it, and the scene the note's text
          if (field.value === text) {
            delete field.dataset.typed;
            if (control.row.kind === 'longText') {
              this.events.noteText(undefined, '');
            }
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

  // A choice. The grainline between two points waits for both points: until
  // then the rows to choose them in are only enabled here.
  private choose(target: string, row: string, value: number): void {
    const grainPoints = (): [number, number] => [this.choiceOf(GRAIN_FROM_ROW), this.choiceOf(GRAIN_TO_ROW)];
    const onPoints = this.rowOf(GRAIN_ROW)?.choice === GRAIN_POINTS;
    if (row === GRAIN_ROW && value === GRAIN_POINTS && !onPoints) {
      this.enable(GRAIN_FROM_ROW);
      this.enable(GRAIN_TO_ROW);
      const [from, to] = grainPoints();
      if (from > 0 && to > 0) {
        this.commit(target, { row, value, from, to });
      }
      return;
    }
    if ((row === GRAIN_FROM_ROW || row === GRAIN_TO_ROW) && !onPoints) {
      const [from, to] = grainPoints();
      if (this.choiceOf(GRAIN_ROW) === GRAIN_POINTS && from > 0 && to > 0) {
        this.commit(target, { row: GRAIN_ROW, value: GRAIN_POINTS, from, to });
      }
      return;
    }
    this.commitRow(target, row, value);
  }

  private rowOf(id: string): PropertyRow | undefined {
    return this.current.rows.find((row) => row.id === id);
  }

  // What a choice row's box shows, which may not be committed yet
  private choiceOf(id: string): number {
    const control = this.controls.find((each) => each.row.id === id)?.control;
    return control instanceof HTMLSelectElement ? Number(control.value) : -1;
  }

  private enable(id: string): void {
    const control = this.controls.find((each) => each.row.id === id)?.control;
    if (control instanceof HTMLSelectElement && !this.current.locked) {
      control.disabled = false;
    }
  }

  // A choice, box or button
  private commitRow(target: string, row: string, value: number): void {
    if (row === OWN_ALLOWANCE_ROW) {
      this.fieldsBeforeAllowance = new Set(
        this.controls.filter((each) => each.row.kind === 'formula').map((each) => each.row.field),
      );
    }
    this.commit(target, { row, value });
  }

  // Refused, the rows go back to what the object has, and the reason is said
  private commit(target: string, params: Record<string, unknown>): void {
    this.document
      .call('editor_property_set', { ...targetParams(target), ...params })
      .then((answer) => {
        if (booleanField(answer, 'done') !== true) {
          this.fieldsBeforeAllowance = undefined;
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
