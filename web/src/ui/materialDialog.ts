// The Materials dialog, as Sloper.UI.MaterialDialog: the pattern's materials
// on the left, with New and Delete, and the chosen one's name, colour, fill,
// allowance, size and fabric on the right. Each change is its own undo step,
// made at once so the canvas behind follows, so the dialog has only Close. A
// typed field commits on Enter or on leaving it, and Escape puts it back; a
// refused one keeps its text, in red, with the reason under the fields. It is
// modal, so it takes Undo and Redo itself, leaving them to a field that
// holds typing not yet committed.
import type { DocumentChange, PatternDocument } from '../document/patternDocument.ts';
import { booleanField, stringField, type JsonRecord } from '../engine/replies.ts';
import { LatestOnly } from './latestOnly.ts';
import { MaterialGrid, paintSwatch, parseMaterials, type MaterialList } from './materialGrid.ts';
import { STRINGS } from './strings.ts';

// As TMaterialField, the fields typed in
const TYPED_FIELDS = ['name', 'allowance', 'width', 'length'] as const;
type TypedField = (typeof TYPED_FIELDS)[number];
const TRUE_TEXT = 'true';
const FALSE_TEXT = 'false';

export interface MaterialsDialogEvents {
  failed(error: unknown): void;
  // Whether a key press is the app's Undo or Redo shortcut
  historyKey(event: KeyboardEvent): 'undo' | 'redo' | undefined;
}

export class MaterialsDialog {
  private readonly document: PatternDocument;
  private readonly events: MaterialsDialogEvents;
  private readonly dialog: HTMLDialogElement;
  private readonly grid: MaterialGrid;
  private readonly fields: HTMLElement;
  private readonly typed = new Map<TypedField, HTMLInputElement>();
  private readonly unitLabels: HTMLElement[] = [];
  private readonly colorInput: HTMLInputElement;
  private readonly swatch: HTMLElement;
  private readonly fillBox: HTMLSelectElement;
  private readonly turnsBox: HTMLInputElement;
  private readonly fabricBox: HTMLSelectElement;
  private readonly deleteButton: HTMLButtonElement;
  private readonly reason: HTMLElement;
  private readonly loads: LatestOnly<number>;
  // What the chosen material's fields hold in the pattern
  private current: JsonRecord = {};
  private list: MaterialList | undefined;
  private readonly listener = (_document: PatternDocument, changes: ReadonlySet<DocumentChange>): void => {
    if (this.dialog.open && (changes.has('pattern') || changes.has('objectsReplaced'))) {
      this.loads.push(this.grid.index);
    }
  };

  constructor(document: PatternDocument, events: MaterialsDialogEvents) {
    this.document = document;
    this.events = events;
    const make = window.document.createElement.bind(window.document);
    this.dialog = make('dialog');
    this.dialog.className = 'materials-dialog';
    const title = make('h2');
    title.textContent = STRINGS.materialsTitle;
    this.grid = new MaterialGrid({
      select: (index) => {
        // A refused value belonged to the material that was chosen
        this.clearRefused();
        this.loads.push(index);
      },
      activate: () => {
        this.typed.get('name')?.focus();
      },
    });
    const newButton = this.button(STRINGS.materialsNew, STRINGS.materialsNewHint, () => {
      this.run(this.addMaterial());
    });
    this.deleteButton = this.button(STRINGS.materialsDelete, STRINGS.materialsDeleteHint, () => {
      this.run(this.deleteMaterial());
    });
    const leftButtons = make('div');
    leftButtons.className = 'list-buttons';
    leftButtons.append(newButton, this.deleteButton);
    const left = make('div');
    left.className = 'materials-left';
    left.append(this.grid.element, leftButtons);

    this.fields = make('div');
    this.fields.className = 'materials-fields';
    this.addTyped('name', STRINGS.materialsName, '', false);
    this.colorInput = make('input');
    this.colorInput.type = 'color';
    this.colorInput.id = 'material-color';
    this.colorInput.addEventListener('change', () => {
      this.run(this.commit('color', this.colorInput.value.toUpperCase(), undefined));
    });
    this.swatch = make('span');
    this.swatch.className = 'material-swatch large';
    const colorRow = make('div');
    colorRow.className = 'materials-row';
    colorRow.append(this.swatch, this.colorInput);
    this.fields.append(this.caption(STRINGS.materialsColour, this.colorInput.id), colorRow);
    this.fillBox = this.choiceBox('material-fill', STRINGS.materialsFill, '', (value) => {
      this.run(this.commit('fill', value, undefined));
    });
    this.addTyped('allowance', STRINGS.materialsAllowance, STRINGS.materialsAllowanceHint, true);
    this.addTyped('width', STRINGS.materialsWidth, STRINGS.materialsWidthHint, true);
    this.addTyped('length', STRINGS.materialsLength, STRINGS.materialsLengthHint, true);
    this.turnsBox = make('input');
    this.turnsBox.type = 'checkbox';
    this.turnsBox.addEventListener('change', () => {
      this.run(this.commit('allowTurns', this.turnsBox.checked ? TRUE_TEXT : FALSE_TEXT, undefined));
    });
    const turns = make('label');
    turns.className = 'materials-check';
    turns.title = STRINGS.materialsTurnsHint;
    turns.append(this.turnsBox, STRINGS.materialsTurns);
    this.fields.append(turns);
    this.fabricBox = this.choiceBox(
      'material-fabric',
      STRINGS.materialsFabric,
      STRINGS.materialsFabricHint,
      (value) => {
        this.run(this.commit('fabric', value, undefined));
      },
    );
    this.reason = make('div');
    this.reason.className = 'materials-reason';
    this.fields.append(this.reason);

    const body = make('div');
    body.className = 'materials-body';
    body.append(left, this.fields);
    const close = this.button(STRINGS.materialsClose, '', () => {
      this.dialog.close();
    });
    const bottom = make('div');
    bottom.className = 'materials-bottom';
    bottom.append(close);
    this.dialog.append(title, body, bottom);
    this.dialog.addEventListener('keydown', (event) => {
      this.keyDown(event);
    });
    window.document.body.append(this.dialog);
    this.loads = new LatestOnly(
      async (index) => this.load(index),
      (error) => {
        events.failed(error);
      },
    );
    document.addListener(this.listener);
  }

  // Opens on the material at the place given, or the first
  open(index: number): void {
    this.clearRefused();
    this.reason.textContent = '';
    this.grid.paintChosen(Math.max(index, 0));
    this.loads.push(Math.max(index, 0));
    this.dialog.showModal();
    this.grid.element.focus();
  }

  dispose(): void {
    this.document.removeListener(this.listener);
    this.dialog.remove();
  }

  private button(caption: string, hint: string, action: () => void): HTMLButtonElement {
    const button = window.document.createElement('button');
    button.type = 'button';
    button.textContent = caption;
    button.title = hint;
    button.addEventListener('click', action);
    return button;
  }

  private caption(text: string, forId: string): HTMLLabelElement {
    const label = window.document.createElement('label');
    label.textContent = text;
    label.htmlFor = forId;
    return label;
  }

  private choiceBox(id: string, caption: string, hint: string, commit: (value: string) => void): HTMLSelectElement {
    const box = window.document.createElement('select');
    box.id = id;
    box.title = hint;
    box.addEventListener('change', () => {
      commit(box.value);
    });
    this.fields.append(this.caption(caption, id), box);
    return box;
  }

  // A field typed in, with the pattern's unit after it for a length
  private addTyped(field: TypedField, caption: string, hint: string, length: boolean): void {
    const make = window.document.createElement.bind(window.document);
    const input = make('input');
    input.type = 'text';
    input.id = `material-${field}`;
    input.title = hint;
    input.autocomplete = 'off';
    input.spellcheck = false;
    input.addEventListener('input', () => {
      input.dataset.typed = 'true';
    });
    input.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') {
        this.run(this.commit(field, input.value, input));
        event.preventDefault();
      } else if (event.key === 'Escape' && this.holdsChange(field, input)) {
        // Escape closes the dialog only once the field holds no change
        this.putBack(field, input);
        event.preventDefault();
      }
    });
    input.addEventListener('blur', () => {
      if (input.dataset.typed === 'true') {
        this.run(this.commit(field, input.value, input));
      }
    });
    this.typed.set(field, input);
    if (length) {
      const unit = make('span');
      unit.className = 'materials-unit';
      this.unitLabels.push(unit);
      const row = make('div');
      row.className = 'materials-row';
      row.append(input, unit);
      this.fields.append(this.caption(caption, input.id), row);
    } else {
      this.fields.append(this.caption(caption, input.id), input);
    }
  }

  private holdsChange(field: TypedField, input: HTMLInputElement): boolean {
    return input.classList.contains('refused') || input.value !== (stringField(this.current, field) ?? '');
  }

  private putBack(field: TypedField, input: HTMLInputElement): void {
    input.value = stringField(this.current, field) ?? '';
    input.classList.remove('refused');
    delete input.dataset.typed;
    this.reason.textContent = '';
  }

  private clearRefused(): void {
    for (const input of this.typed.values()) {
      input.classList.remove('refused');
      delete input.dataset.typed;
    }
  }

  private run(pending: Promise<void>): void {
    pending.catch((error: unknown) => {
      this.events.failed(error);
    });
  }

  private async load(index: number): Promise<void> {
    const list = parseMaterials(await this.document.read('editor_materials'));
    this.list = list;
    const chosen = Math.max(0, Math.min(index, list.rows.length - 1));
    this.grid.show(list.rows);
    this.grid.paintChosen(chosen);
    for (const unit of this.unitLabels) {
      unit.textContent = list.unit;
    }
    this.fillChoices(
      this.fillBox,
      list.fills.map((fill) => [fill.name, fill.caption]),
    );
    this.fillChoices(
      this.fabricBox,
      list.fabrics.map((fabric) => [fabric.name, fabric.caption]),
    );
    if (list.rows.length === 0) {
      return;
    }
    this.current = await this.document.read('editor_material', { index: chosen });
    this.showFields();
  }

  private fillChoices(box: HTMLSelectElement, choices: [string, string][]): void {
    if (box.options.length === choices.length) {
      return;
    }
    box.replaceChildren(...choices.map(([value, caption]) => new Option(caption, value)));
  }

  // A field holding a refused value, or typing not yet committed, keeps it
  private showFields(): void {
    const current = this.current;
    for (const [field, input] of this.typed) {
      if (!input.classList.contains('refused') && input.dataset.typed !== 'true') {
        input.value = stringField(current, field) ?? '';
      }
    }
    const color = stringField(current, 'color') ?? '#000000';
    this.colorInput.value = color.toLowerCase();
    const fill = stringField(current, 'fill') ?? 'tint';
    const row = this.list?.rows[this.grid.index];
    paintSwatch(this.swatch, color, fill, row?.hatchAngle ?? 0);
    this.fillBox.value = fill;
    this.turnsBox.checked = stringField(current, 'allowTurns') === TRUE_TEXT;
    this.fabricBox.value = stringField(current, 'fabric') ?? '';
    this.deleteButton.disabled = booleanField(current, 'canDelete') !== true;
  }

  // Input is the field the text came from, to mark a refusal on
  private async commit(field: string, text: string, input: HTMLInputElement | undefined): Promise<void> {
    const index = this.grid.index;
    if (index < 0) {
      return;
    }
    const answer = await this.document.call('editor_material_set', { index, field, text });
    const done = booleanField(answer, 'done') === true;
    if (input !== undefined) {
      input.classList.toggle('refused', !done);
      if (done) {
        delete input.dataset.typed;
      }
    }
    this.reason.textContent = done ? '' : (stringField(answer, 'reason') ?? '');
    if (!done) {
      // Choices and boxes go back to what the material has
      this.showFields();
    }
  }

  private async addMaterial(): Promise<void> {
    const answer = await this.document.call('editor_material_add');
    const index = Number(answer.index ?? -1);
    if (index < 0) {
      return;
    }
    this.clearRefused();
    this.grid.paintChosen(index);
    await this.load(index);
    const name = this.typed.get('name');
    name?.focus();
    name?.select();
  }

  private async deleteMaterial(): Promise<void> {
    const answer = await this.document.call('editor_material_delete', { index: this.grid.index });
    this.reason.textContent = booleanField(answer, 'done') === true ? '' : (stringField(answer, 'reason') ?? '');
  }

  // Undo and Redo, as in the main window, unless a field holds typing not committed
  private keyDown(event: KeyboardEvent): void {
    const step = this.events.historyKey(event);
    if (step === undefined) {
      return;
    }
    const focused = window.document.activeElement;
    for (const [field, input] of this.typed) {
      if (input === focused && this.holdsChange(field, input)) {
        return;
      }
    }
    this.clearRefused();
    this.reason.textContent = '';
    this.run(step === 'redo' ? this.document.redo() : this.document.undo());
    event.preventDefault();
    event.stopPropagation();
  }
}
