// The web Measurements app, as Sloper.Measurements.MainForm: starts the engine
// and opens a measurement set or size table, shown read only for now. Name and
// Notes are above the table, Show in chooses the unit of its values, and the
// status bar has a message. Nothing leaves the machine: the file is read in
// the browser and given to the engine as text.
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

function showMessage(text: string): void {
  message.textContent = text;
}

function showFailure(error: unknown): void {
  showMessage(STRINGS.failed(error instanceof Error ? error.message : String(error)));
  console.error(error);
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

  constructor(engine: Engine) {
    this.document = new MeasurementDocument(engine);
    this.grid = new MeasurementGrid(this.document, {
      select: () => undefined,
      zoom: () => undefined,
      message: showMessage,
      failed: showFailure,
    });
  }

  start(): void {
    element('set-name-label', HTMLElement).textContent = STRINGS.measureSetName;
    element('set-notes-label', HTMLElement).textContent = STRINGS.measureNotes;
    element('show-in-label', HTMLElement).textContent = STRINGS.measureShowIn;
    empty.textContent = STRINGS.measureEmpty;
    toolbar.append(
      iconButton('folder-open', STRINGS.open, STRINGS.measureOpenHint, () => {
        openInput.click();
      }),
    );
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

  // A file that cannot be read keeps the set open, and says why
  private async openFile(file: File): Promise<void> {
    if (!file.name.toLowerCase().endsWith(MEASUREMENT_EXTENSION)) {
      showMessage(STRINGS.measureNotASet(file.name));
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

  private showState(): void {
    const state = this.document.state;
    const fileName = this.document.fileName;
    document.title = fileName === '' ? STRINGS.measureApp : `${fileName} — ${STRINGS.measureApp}`;
    nameBox.value = state.name;
    notesBox.value = state.notes;
    // The table once a set is open, else a line saying to open one
    if (fileName === '') {
      table.replaceChildren(empty);
    } else if (!table.contains(this.grid.element)) {
      table.replaceChildren(this.grid.element);
    }
    this.grid.showSet();
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
