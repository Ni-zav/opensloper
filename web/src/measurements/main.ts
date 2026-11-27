// The web Measurements app, as Sloper.Measurements.MainForm: starts the engine
// and opens a measurement set or size table. Its table is edited in the grid,
// with Add, Delete, Up and Down over it, then the size buttons, which act on
// the size whose column the chosen cell is in, and Undo and Redo on the
// toolbar; each change is one undo step. Name and Notes are above the
// table, each committed when Enter is pressed or the field is left, Show in
// chooses the unit of its values, and the status bar has a message. Beside
// the table, the body figure shows where the set's measurements are taken,
// and Add From the Catalogue lists the measurements the set lacks, with the
// details of the one chosen or of the table's row. Nothing leaves the
// machine: the file is read in the browser and given to the engine as text.
import { MeasurementDocument } from '../document/measurementDocument.ts';
import { MEASURE_UNITS, type MeasureUnit } from '../editor/rulerTicks.ts';
import { Engine, EngineError } from '../engine/engine.ts';
import { PATTERN_EXTENSION } from '../ui/fileAccess.ts';
import { STRINGS } from '../ui/strings.ts';
import { BodyFigure } from './bodyFigure.ts';
import { CatalogueBrowser } from './catalogueBrowser.ts';
import { MeasurementGrid } from './measurementGrid.ts';

const MEASUREMENT_EXTENSION = '.slm';

function element<T extends HTMLElement>(id: string, type: new () => T): T {
  const found = document.getElementById(id);
  if (!(found instanceof type)) {
    throw new Error(`the page has no #${id}`);
  }
  return found;
}

const toolbar = element('toolbar', HTMLElement);
const message = element('message', HTMLElement);
const openInput = element('open-input', HTMLInputElement);
const patternInput = element('pattern-input', HTMLInputElement);
const patternCheck = element('pattern-check', HTMLElement);
const patternHeading = element('pattern-heading', HTMLElement);
const patternComplete = element('pattern-complete', HTMLElement);
const missingRows = element('missing-measurements', HTMLUListElement);
const nameBox = element('set-name', HTMLInputElement);
const notesBox = element('set-notes', HTMLInputElement);
const showIn = element('show-in', HTMLSelectElement);
const table = element('table', HTMLElement);
const empty = element('empty', HTMLElement);
const tableButtons = element('table-buttons', HTMLElement);
const side = element('side', HTMLElement);

function showMessage(text: string): void {
  message.textContent = text;
}

function showFailure(error: unknown): void {
  showMessage(STRINGS.failed(error instanceof Error ? error.message : String(error)));
  console.error(error);
}

function plainButton(caption: string, hint: string, action: () => void): HTMLButtonElement {
  const button = document.createElement('button');
  button.type = 'button';
  button.textContent = caption;
  button.title = hint;
  button.addEventListener('click', action);
  return button;
}

function iconButton(icon: string, caption: string, hint: string, action: () => void): HTMLButtonElement {
  const button = document.createElement('button');
  button.type = 'button';
  button.title = hint;
  const image = document.createElement('img');
  image.src = `icons/${icon}.svg`;
  image.alt = '';
  const label = document.createElement('span');
  label.textContent = caption;
  button.append(image, label);
  button.addEventListener('click', action);
  return button;
}

class MeasurementsApp {
  private readonly document: MeasurementDocument;
  private readonly grid: MeasurementGrid;
  private readonly catalogue: CatalogueBrowser;
  private readonly figure: BodyFigure;
  // The entry the catalogue shows, and the table's row under the pointer,
  // which the figure highlights over it, as on the desktop
  private shownKey = '';
  private gridHover = '';
  private readonly undoButton: HTMLButtonElement;
  private readonly redoButton: HTMLButtonElement;
  private readonly checkButton = iconButton(
    'file-search',
    STRINGS.measureCheckPattern,
    STRINGS.measureCheckPatternHint,
    () => {
      patternInput.click();
    },
  );
  private readonly addButton: HTMLButtonElement;
  private readonly deleteButton: HTMLButtonElement;
  private readonly upButton: HTMLButtonElement;
  private readonly downButton: HTMLButtonElement;
  private readonly sizeButtons: HTMLElement;
  // The set whose name and notes the fields show
  private shownGeneration = -1;
  private shownName = '';
  private shownNotes = '';
  private readonly addSizeButton: HTMLButtonElement;
  private readonly renameSizeButton: HTMLButtonElement;
  private readonly deleteSizeButton: HTMLButtonElement;
  private readonly sizeLeftButton: HTMLButtonElement;
  private readonly sizeRightButton: HTMLButtonElement;

  constructor(engine: Engine) {
    this.document = new MeasurementDocument(engine);
    this.grid = new MeasurementGrid(this.document, {
      select: () => {
        this.refreshButtons();
        this.catalogue.showTableKey(this.grid.chosenKey);
      },
      zoom: () => undefined,
      delete: () => {
        this.run(this.deleteChosen());
      },
      column: () => {
        this.refreshButtons();
      },
      message: showMessage,
      failed: showFailure,
    });
    this.catalogue = new CatalogueBrowser(this.document, {
      added: (key) => {
        this.run(this.grid.chooseValue(key));
      },
      shown: (key) => {
        this.shownKey = key;
        this.showHighlight();
      },
      message: showMessage,
      failed: showFailure,
    });
    this.figure = new BodyFigure(this.document, {
      hover: (key) => {
        this.catalogue.showHover(key === '' ? undefined : key);
      },
      pick: (key) => {
        this.run(this.grid.chooseValue(key));
      },
      failed: showFailure,
    });
    this.undoButton = iconButton('arrow-back-up', STRINGS.undo, STRINGS.undoHint, () => {
      this.run(this.document.undo());
    });
    this.redoButton = iconButton('arrow-forward-up', STRINGS.redo, STRINGS.redoHint, () => {
      this.run(this.document.redo());
    });
    this.addButton = plainButton(STRINGS.measureAdd, STRINGS.measureAddHint, () => {
      this.run(this.addMeasurement());
    });
    this.deleteButton = plainButton(STRINGS.measureDelete, STRINGS.measureDeleteHint, () => {
      this.run(this.deleteChosen());
    });
    this.upButton = plainButton(STRINGS.measureUp, STRINGS.measureUpHint, () => {
      this.run(this.moveChosen(-1));
    });
    this.downButton = plainButton(STRINGS.measureDown, STRINGS.measureDownHint, () => {
      this.run(this.moveChosen(1));
    });
    this.renameSizeButton = plainButton(STRINGS.measureRenameSize, STRINGS.measureRenameSizeHint, () => {
      this.run(this.renameSize());
    });
    this.deleteSizeButton = plainButton(STRINGS.measureDeleteSize, STRINGS.measureDeleteSizeHint, () => {
      this.run(this.deleteSize());
    });
    this.sizeLeftButton = plainButton(STRINGS.measureSizeLeft, STRINGS.measureSizeLeftHint, () => {
      this.run(this.moveSize(-1));
    });
    this.sizeRightButton = plainButton(STRINGS.measureSizeRight, STRINGS.measureSizeRightHint, () => {
      this.run(this.moveSize(1));
    });
    // Apart from the measurement buttons, as the desktop's three gaps
    this.sizeButtons = document.createElement('div');
    this.sizeButtons.className = 'size-buttons';
    this.addSizeButton = plainButton(STRINGS.measureAddSize, STRINGS.measureAddSizeHint, () => {
      this.run(this.addSize());
    });
    this.sizeButtons.append(
      this.addSizeButton,
      this.renameSizeButton,
      this.deleteSizeButton,
      this.sizeLeftButton,
      this.sizeRightButton,
    );
  }

  start(): void {
    element('set-name-label', HTMLElement).textContent = STRINGS.measureSetName;
    element('set-notes-label', HTMLElement).textContent = STRINGS.measureNotes;
    element('show-in-label', HTMLElement).textContent = STRINGS.measureShowIn;
    empty.textContent = STRINGS.measureEmpty;
    const divider = document.createElement('span');
    divider.className = 'divider';
    toolbar.append(
      iconButton('folder-open', STRINGS.open, STRINGS.measureOpenHint, () => {
        openInput.click();
      }),
      divider,
      this.undoButton,
      this.redoButton,
      this.checkButton,
    );
    for (const box of [nameBox, notesBox]) {
      // Enter, or leaving the field, commits it, as the desktop's EditingDone
      box.addEventListener('change', () => {
        this.run(this.commitHeader());
      });
      box.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') {
          box.value = box === nameBox ? this.document.state.name : this.document.state.notes;
        }
      });
    }
    tableButtons.append(this.addButton, this.deleteButton, this.upButton, this.downButton, this.sizeButtons);
    openInput.addEventListener('change', () => {
      const file = openInput.files?.[0];
      openInput.value = '';
      if (file !== undefined) {
        this.run(this.openFile(file));
      }
    });
    patternInput.addEventListener('change', () => {
      const file = patternInput.files?.[0];
      patternInput.value = '';
      if (file !== undefined) {
        this.run(this.checkPattern(file));
      }
    });
    patternHeading.after(
      plainButton(STRINGS.measureStopCheck, STRINGS.measureStopCheck, () => {
        this.run(this.document.clearPattern());
      }),
    );
    patternComplete.textContent = STRINGS.measureCheckComplete;
    for (const unit of MEASURE_UNITS) {
      showIn.add(new Option(unit, unit, unit === this.document.unit, unit === this.document.unit));
    }
    showIn.addEventListener('change', () => {
      const unit = MEASURE_UNITS.find((each) => each === showIn.value);
      if (unit !== undefined) {
        this.run(this.showIn(unit));
      }
    });
    side.append(this.figure.element, this.catalogue.element);
    this.grid.element.addEventListener('mouseover', (event) => {
      const row = event.target instanceof Element ? event.target.closest('tr') : null;
      this.gridHover = row?.dataset.key ?? '';
      this.showHighlight();
    });
    this.grid.element.addEventListener('mouseleave', () => {
      this.gridHover = '';
      this.showHighlight();
    });
    this.document.addListener(() => {
      this.showState();
    });
    this.showState();
    this.run(this.loadCatalogue());
  }

  // Nothing depends on the catalogue, so without it the table still works
  private async loadCatalogue(): Promise<void> {
    const response = await fetch(new URL('./measurement-catalogue.json', import.meta.url));
    if (!response.ok) {
      showMessage(STRINGS.catalogueFailed(`${String(response.status)} ${response.statusText}`));
      return;
    }
    try {
      await this.document.loadCatalogue(await response.text());
    } catch (error: unknown) {
      if (error instanceof EngineError) {
        showMessage(STRINGS.catalogueFailed(error.message));
        return;
      }
      throw error;
    }
  }

  private showHighlight(): void {
    this.figure.highlight = this.gridHover === '' ? this.shownKey : this.gridHover;
  }

  private async showIn(unit: MeasureUnit): Promise<void> {
    await this.document.showIn(unit);
    this.catalogue.showUnit();
  }

  private run(pending: Promise<void>): void {
    pending.catch(showFailure);
  }

  // A file that cannot be read keeps the set open, and says why. Changes not
  // saved are dropped only when the user agrees.
  private async openFile(file: File): Promise<void> {
    if (!file.name.toLowerCase().endsWith(MEASUREMENT_EXTENSION)) {
      showMessage(STRINGS.measureNotASet(file.name));
      return;
    }
    await this.commitHeader();
    if (this.document.state.modified && !window.confirm(STRINGS.measureDiscardChanges)) {
      return;
    }
    try {
      await this.document.open(await file.text(), file.name);
    } catch (error: unknown) {
      if (error instanceof EngineError) {
        showMessage(STRINGS.measureOpenFailed(file.name, error.message));
        return;
      }
      throw error;
    }
    showMessage(STRINGS.measureOpened(file.name));
  }

  private async checkPattern(file: File): Promise<void> {
    if (!file.name.toLowerCase().endsWith(PATTERN_EXTENSION)) {
      showMessage(STRINGS.measureNotAPattern(file.name));
      return;
    }
    try {
      await this.document.checkPattern(await file.text(), file.name);
      showMessage('');
    } catch (error: unknown) {
      if (error instanceof EngineError) {
        showMessage(STRINGS.measureCheckFailed(file.name, error.message));
        return;
      }
      throw error;
    }
  }

  private showPatternCheck(): void {
    const { pattern, missing } = this.document.state;
    patternCheck.hidden = pattern === '';
    patternHeading.textContent = STRINGS.measureCheckedAgainst(pattern);
    patternComplete.hidden = missing.length > 0;
    missingRows.replaceChildren(
      ...missing.map(({ key, sizes }) => {
        const row = document.createElement('li');
        row.textContent = sizes.length === 0 ? key : `${key} (${sizes.join(', ')})`;
        return row;
      }),
    );
  }

  // The fields' text, where it differs from the set's, as the desktop's
  // HeaderDone; each change one undo step
  private async commitHeader(): Promise<void> {
    if (this.document.fileName === '') {
      return;
    }
    if (nameBox.value !== this.document.state.name) {
      await this.document.setName(nameBox.value);
    }
    if (notesBox.value !== this.document.state.notes) {
      await this.document.setNotes(notesBox.value);
    }
  }

  // A new measurement at the end, its key open to type, as on the desktop
  private async addMeasurement(): Promise<void> {
    await this.grid.editKey(await this.document.add());
  }

  // Asked first, as on the desktop, since patterns name it by its key
  private async deleteChosen(): Promise<void> {
    const key = this.grid.chosenKey;
    if (key === undefined || !window.confirm(STRINGS.measureDeleteQuestion(key))) {
      return;
    }
    await this.document.delete(key);
    this.grid.showSelection([]);
    this.refreshButtons();
  }

  // One place up (-1) or down (1); it stays chosen
  private async moveChosen(step: number): Promise<void> {
    const key = this.grid.chosenKey;
    const index = this.chosenIndex();
    if (key !== undefined && index >= 0) {
      await this.document.move(key, index + step);
    }
  }

  // A name refused, or the last size, says why in the status bar, as the
  // desktop's message does
  private async sizeEdit(edit: Promise<void>): Promise<void> {
    try {
      await edit;
    } catch (error: unknown) {
      if (error instanceof EngineError) {
        showMessage(error.message);
        return;
      }
      throw error;
    }
  }

  private async addSize(): Promise<void> {
    const name = window.prompt(STRINGS.measureSizePrompt, '');
    if (name !== null) {
      await this.sizeEdit(this.document.addSize(name));
    }
  }

  private async renameSize(): Promise<void> {
    const size = this.grid.chosenSize;
    const old = this.document.state.sizes[size];
    if (old === undefined) {
      return;
    }
    const name = window.prompt(`${STRINGS.measureRenameSizePrompt(old)}\n${STRINGS.measureSizePrompt}`, old);
    if (name !== null && name !== old) {
      await this.sizeEdit(this.document.renameSize(size, name));
    }
  }

  // Asked first, as on the desktop
  private async deleteSize(): Promise<void> {
    const size = this.grid.chosenSize;
    const name = this.document.state.sizes[size];
    if (name !== undefined && window.confirm(STRINGS.measureDeleteSizeQuestion(name))) {
      await this.sizeEdit(this.document.deleteSize(size));
      this.refreshButtons();
    }
  }

  // One column left (-1) or right (1); the chosen cell goes with it
  private async moveSize(step: number): Promise<void> {
    const size = this.grid.chosenSize;
    const index = size + step;
    if (size >= 0 && index >= 0 && index < this.document.state.sizes.length) {
      await this.document.moveSize(size, index);
      this.grid.chooseSize(index);
    }
  }

  // The chosen measurement's row, or -1
  private chosenIndex(): number {
    return this.document.state.rows.findIndex((row) => row.key === this.grid.chosenKey);
  }

  private refreshButtons(): void {
    const state = this.document.state;
    const index = this.chosenIndex();
    this.undoButton.disabled = !state.canUndo;
    this.undoButton.title = state.canUndo ? STRINGS.undoStep(state.undo) : STRINGS.undoHint;
    this.redoButton.disabled = !state.canRedo;
    this.addButton.disabled = this.document.fileName === '';
    this.deleteButton.disabled = index < 0;
    this.upButton.disabled = index <= 0;
    this.downButton.disabled = index < 0 || index >= state.rows.length - 1;
    const size = this.grid.chosenSize;
    this.addSizeButton.disabled = this.document.fileName === '';
    this.renameSizeButton.disabled = size < 0;
    this.deleteSizeButton.disabled = size < 0;
    this.sizeLeftButton.disabled = size <= 0;
    this.sizeRightButton.disabled = size < 0 || size >= state.sizes.length - 1;
    document.body.dataset.undo = state.canUndo ? state.undo : '';
  }

  private showState(): void {
    const state = this.document.state;
    const fileName = this.document.fileName;
    const shown = state.modified ? `${STRINGS.modifiedMark} ${fileName}` : fileName;
    document.title = fileName === '' ? STRINGS.measureApp : `${shown} — ${STRINGS.measureApp}`;
    // A field with text not yet committed keeps it, as the desktop's field
    // being typed in, unless another set was opened
    const opened = this.document.generation !== this.shownGeneration;
    this.shownGeneration = this.document.generation;
    for (const [box, text, before] of [
      [nameBox, state.name, this.shownName],
      [notesBox, state.notes, this.shownNotes],
    ] as const) {
      if (opened || box.value === before) {
        box.value = text;
      }
      box.disabled = fileName === '';
    }
    this.shownName = state.name;
    this.shownNotes = state.notes;
    // The table once a set is open, else a line saying to open one
    if (fileName === '') {
      table.replaceChildren(empty);
    } else if (!table.contains(this.grid.element)) {
      table.replaceChildren(this.grid.element);
    }
    this.grid.showSet();
    this.catalogue.refresh();
    this.figure.refresh();
    this.refreshButtons();
    this.checkButton.disabled = fileName === '';
    this.showPatternCheck();
  }
}

async function main(): Promise<void> {
  showMessage(STRINGS.loading);
  const { engine } = await Engine.start(
    new URL('./worker.js', import.meta.url),
    new URL('./engine_lib.wasm', import.meta.url),
  );
  new MeasurementsApp(engine).start();
  showMessage('');
  document.body.dataset.ready = 'true';
}

main().catch(showFailure);
