// The web Measurements app, as Sloper.Measurements.MainForm: starts the engine
// and opens a measurement set or size table. Its table is edited in the grid,
// with Add, Delete, Up and Down over it, then the size buttons, which act on
// the size whose column the chosen cell is in, and Undo and Redo on the
// toolbar; each change is one undo step. Name and Notes are above the table, read only for
// now, Show in chooses the unit of its values, and the status bar has a
// message. Nothing leaves the machine: the file is read in the browser and
// given to the engine as text.
import { MeasurementDocument } from '../document/measurementDocument.ts';
import { MEASURE_UNITS } from '../editor/rulerTicks.ts';
import { Engine, EngineError } from '../engine/engine.ts';
import { STRINGS } from '../ui/strings.ts';
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
const nameBox = element('set-name', HTMLInputElement);
const notesBox = element('set-notes', HTMLInputElement);
const showIn = element('show-in', HTMLSelectElement);
const table = element('table', HTMLElement);
const empty = element('empty', HTMLElement);
const tableButtons = element('table-buttons', HTMLElement);

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
  private readonly undoButton: HTMLButtonElement;
  private readonly redoButton: HTMLButtonElement;
  private readonly addButton: HTMLButtonElement;
  private readonly deleteButton: HTMLButtonElement;
  private readonly upButton: HTMLButtonElement;
  private readonly downButton: HTMLButtonElement;
  private readonly sizeButtons: HTMLElement;
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
    );
    tableButtons.append(this.addButton, this.deleteButton, this.upButton, this.downButton, this.sizeButtons);
    openInput.addEventListener('change', () => {
      const file = openInput.files?.[0];
      openInput.value = '';
      if (file !== undefined) {
        this.run(this.openFile(file));
      }
    });
    for (const unit of MEASURE_UNITS) {
      showIn.add(new Option(unit, unit, unit === this.document.unit, unit === this.document.unit));
    }
    showIn.addEventListener('change', () => {
      const unit = MEASURE_UNITS.find((each) => each === showIn.value);
      if (unit !== undefined) {
        this.run(this.document.showIn(unit));
      }
    });
    this.document.addListener(() => {
      this.showState();
    });
    this.showState();
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
    nameBox.value = state.name;
    notesBox.value = state.notes;
    // The table once a set is open, else a line saying to open one
    if (fileName === '') {
      table.replaceChildren(empty);
    } else if (!table.contains(this.grid.element)) {
      table.replaceChildren(this.grid.element);
    }
    this.grid.showSet();
    this.refreshButtons();
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
