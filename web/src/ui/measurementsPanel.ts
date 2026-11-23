// The measurements tab of the side panel, as Sloper.UI.MeasurementsPanel: the
// measurement file's measurements, searchable, then those the pattern uses
// that the file lacks, in red. Cells are edited in the grid as unsaved edits,
// shown in bold, which Save makes to the set and downloads as its file, and
// Revert drops; Add starts a new key. A size table's size is chosen above the
// list, and the test size tries the pattern a few percent larger or smaller.
// The edits are kept by the engine (editor_measurement_set), as the
// desktop's TPendingMeasurements.
import type { PatternDocument } from '../document/patternDocument.ts';
import { booleanField, numberField, recordsField, stringField, stringsField } from '../engine/replies.ts';
import { baseName, downloadText } from './download.ts';
import { LatestOnly } from './latestOnly.ts';
import { ListPanel, type CellCommit, type ListPanelEvents, type ListPanelRow } from './listPanel.ts';
import { STRINGS } from './strings.ts';

// As TMeasurementColumn
const COLUMNS = ['key', 'value', 'description'] as const;
const KEY_COLUMN = 0;
const VALUE_COLUMN = 1;
// The test size's reach either way, in percent, and its ticks
const MAX_TEST_PERCENT = 20;
const TEST_TICK_PERCENT = 5;
const MEASUREMENTS_EXTENSION = '.slm';

// Where Save puts the set's file: by default a download
export interface MeasurementsSaver {
  // Readies the file at the path the pattern records, or for a new set the
  // one suggested, before the edits are made; the path to record, or
  // undefined when the user cancels
  prepare(path: string, isNew: boolean): Promise<string | undefined>;
  write(path: string, text: string): Promise<void>;
}

const DOWNLOAD_SAVER: MeasurementsSaver = {
  prepare: async (path) => Promise.resolve(path),
  write: async (path, text) => {
    downloadText(baseName(path), text);
    return Promise.resolve();
  },
};

export class MeasurementsPanel extends ListPanel {
  // The pattern's file name, from which a new set's is made
  patternFileName: () => string = () => '';
  saver: MeasurementsSaver = DOWNLOAD_SAVER;
  // The set's file as the pattern records it, or '' with none
  private setFile = '';
  private readonly fileLabel: HTMLElement;
  private readonly sizeRow: HTMLElement;
  private readonly sizeBox: HTMLSelectElement;
  private readonly testLabel: HTMLElement;
  private readonly testSlider: HTMLInputElement;
  private readonly testReset: HTMLButtonElement;
  private readonly addButton: HTMLButtonElement;
  private readonly saveButton: HTMLButtonElement;
  private readonly revertButton: HTMLButtonElement;
  private readonly tests: LatestOnly<number>;
  // Keys of the rows Add made, whose key can still be changed
  private newKeys = new Set<string>();
  private pendingCount = 0;
  private testPercent = 0;

  constructor(document: PatternDocument, events: ListPanelEvents) {
    super(document, events, [
      { caption: STRINGS.measurementsKey, width: 120 },
      { caption: STRINGS.measurementsValue, width: 100 },
      { caption: STRINGS.columnDescription, width: 240 },
    ]);
    this.setEditableColumns([true, true, true], [false, false, false]);
    const make = window.document.createElement.bind(window.document);

    const set = make('fieldset');
    set.className = 'measurement-set';
    const setTitle = make('legend');
    setTitle.textContent = STRINGS.measurementsSetTitle;
    this.fileLabel = make('span');
    this.fileLabel.id = 'measurement-file';
    this.fileLabel.textContent = STRINGS.measurementsNoSet;
    this.sizeRow = make('div');
    this.sizeRow.className = 'measurement-row';
    this.sizeRow.hidden = true;
    const sizeLabel = make('label');
    sizeLabel.textContent = STRINGS.measurementsSize;
    this.sizeBox = make('select');
    this.sizeBox.id = 'measurement-size';
    sizeLabel.htmlFor = this.sizeBox.id;
    this.sizeBox.addEventListener('change', () => {
      this.run(this.document.call('editor_measurement_size', { size: this.sizeBox.value }).then(() => undefined));
    });
    this.sizeRow.append(sizeLabel, this.sizeBox);
    set.append(setTitle, this.fileLabel, this.sizeRow);
    this.header.prepend(set);

    const test = make('fieldset');
    test.className = 'measurement-test';
    test.title = STRINGS.measurementsTestHint;
    const testTitle = make('legend');
    testTitle.textContent = STRINGS.measurementsTestTitle;
    const testRow = make('div');
    testRow.className = 'measurement-row';
    this.testLabel = make('span');
    this.testReset = this.button(STRINGS.measurementsTestReset, () => {
      this.testSlider.value = '0';
      this.tests.push(0);
    });
    testRow.append(this.testLabel, this.testReset);
    this.testSlider = make('input');
    this.testSlider.type = 'range';
    this.testSlider.id = 'measurement-test';
    this.testSlider.min = String(-MAX_TEST_PERCENT);
    this.testSlider.max = String(MAX_TEST_PERCENT);
    this.testSlider.step = '1';
    this.testSlider.value = '0';
    this.testSlider.setAttribute('aria-label', STRINGS.measurementsTestTitle);
    const ticks = make('datalist');
    ticks.id = 'measurement-test-ticks';
    for (let percent = -MAX_TEST_PERCENT; percent <= MAX_TEST_PERCENT; percent += TEST_TICK_PERCENT) {
      ticks.append(new Option('', String(percent)));
    }
    this.testSlider.setAttribute('list', ticks.id);
    this.tests = new LatestOnly(
      async (percent) => {
        await this.document.call('editor_measurement_scale', { percent });
      },
      (error) => {
        this.report(error);
      },
    );
    this.testSlider.addEventListener('input', () => {
      this.tests.push(Number(this.testSlider.value));
    });
    test.append(testTitle, testRow, this.testSlider, ticks);

    const buttons = make('div');
    buttons.className = 'list-buttons';
    this.addButton = this.button(STRINGS.measurementsAdd, () => {
      this.run(this.addMeasurement());
    });
    this.saveButton = this.button(STRINGS.measurementsSave, () => {
      this.run(this.save());
    });
    this.saveButton.title = STRINGS.measurementsSaveHint;
    this.revertButton = this.button(STRINGS.measurementsRevert, () => {
      this.run(this.revert());
    });
    this.revertButton.title = STRINGS.measurementsRevertHint;
    buttons.append(this.addButton, this.saveButton, this.revertButton);
    this.element.append(test, buttons);
    this.updateControls();
  }

  // Edits not yet saved, which opening another pattern or set would drop
  get hasPending(): boolean {
    return this.pendingCount > 0;
  }

  protected async buildRows(search: string): Promise<ListPanelRow[]> {
    const answer = await this.document.read('editor_list_measurements', { search });
    this.pendingCount = numberField(answer, 'pendingCount') ?? 0;
    this.testPercent = numberField(answer, 'testPercent') ?? 0;
    const file = stringField(answer, 'file') ?? '';
    this.setFile = file;
    this.fileLabel.textContent = file === '' ? STRINGS.measurementsNoSet : baseName(file);
    this.showSizes(stringsField(answer, 'sizes') ?? [], stringField(answer, 'size') ?? '');
    this.updateControls();
    this.newKeys = new Set();
    return recordsField(answer, 'rows').map((row) => {
      const key = stringField(row, 'key') ?? '';
      const missing = booleanField(row, 'missing') === true;
      const pending = booleanField(row, 'pending') === true;
      if (booleanField(row, 'isNew') === true) {
        this.newKeys.add(key);
      }
      return {
        key,
        state: missing ? 'error' : 'valid',
        marked: pending,
        cells: [
          pending ? STRINGS.measurementsEdited(key) : key,
          missing ? STRINGS.measurementsMissing : (stringField(row, 'value') ?? ''),
          missing ? '' : (stringField(row, 'description') ?? ''),
        ],
      };
    });
  }

  // Nothing is edited while trying sizes, since the values shown are scaled;
  // a key is only edited on a row made by Add
  protected override cellEditable(key: string, column: number): boolean {
    if (this.testPercent !== 0) {
      return false;
    }
    return column === KEY_COLUMN ? this.newKeys.has(key) : super.cellEditable(key, column);
  }

  protected override cellEditText(key: string, column: number, shown: string): string {
    if (column === KEY_COLUMN) {
      return key;
    }
    return column === VALUE_COLUMN && shown === STRINGS.measurementsMissing ? '' : shown;
  }

  protected override async commitCell(key: string, column: number, text: string): Promise<CellCommit> {
    const answer = await this.document.read('editor_measurement_set', { key, column: COLUMNS[column], text });
    return {
      done: booleanField(answer, 'done') === true,
      reason: stringField(answer, 'reason') ?? '',
      key: stringField(answer, 'key') ?? key,
    };
  }

  private button(caption: string, action: () => void): HTMLButtonElement {
    const button = window.document.createElement('button');
    button.type = 'button';
    button.textContent = caption;
    button.addEventListener('click', action);
    return button;
  }

  private run(pending: Promise<void>): void {
    pending.catch((error: unknown) => {
      this.report(error);
    });
  }

  // The list is put back only when it differs, so a choice being made is not lost
  private showSizes(sizes: readonly string[], size: string): void {
    this.sizeRow.hidden = sizes.length === 0;
    const shown = [...this.sizeBox.options].map((option) => option.value);
    if (shown.join('\n') !== sizes.join('\n')) {
      this.sizeBox.replaceChildren(...sizes.map((each) => new Option(each, each)));
    }
    this.sizeBox.value = size;
  }

  private updateControls(): void {
    const testing = this.testPercent !== 0;
    const pending = this.hasPending;
    this.addButton.disabled = testing;
    this.saveButton.disabled = !pending;
    this.revertButton.disabled = !pending;
    // Another size or a test shows other values, so the edits are settled first
    this.sizeBox.disabled = pending;
    this.sizeBox.title = pending ? STRINGS.measurementsTestPaused : '';
    this.testSlider.disabled = pending;
    this.testReset.disabled = !testing;
    if (this.testSlider !== window.document.activeElement) {
      this.testSlider.value = String(this.testPercent);
    }
    if (testing) {
      const signed = this.testPercent > 0 ? `+${String(this.testPercent)}` : String(this.testPercent);
      this.testLabel.textContent = STRINGS.measurementsTest(STRINGS.measurementsTestOn(signed));
    } else if (pending) {
      this.testLabel.textContent = STRINGS.measurementsTestPaused;
    } else {
      this.testLabel.textContent = STRINGS.measurementsTest(STRINGS.measurementsTestOff);
    }
  }

  // The new row is there once the rows come back, and its key is opened to type
  private async addMeasurement(): Promise<void> {
    const answer = await this.document.read('editor_measurement_add');
    this.refresh();
    await this.rowsLoaded();
    const key = stringField(answer, 'key');
    if (key !== undefined) {
      this.focusCell(key, KEY_COLUMN, true);
    }
  }

  // Makes the edits to the set and downloads its file; with no set, a new
  // one is named after the pattern and recorded beside it
  private async save(): Promise<void> {
    const pattern = this.patternFileName();
    const stem = pattern === '' ? STRINGS.measurementsNewFile : pattern.replace(/\.[^.]*$/, '');
    const isNew = this.setFile === '';
    // The file is chosen first, so cancelling leaves the edits waiting
    const path = await this.saver.prepare(isNew ? stem + MEASUREMENTS_EXTENSION : this.setFile, isNew);
    if (path === undefined) {
      return;
    }
    const answer = await this.document.call('editor_measurements_save', { file: path });
    if (booleanField(answer, 'done') !== true) {
      this.events.message(stringField(answer, 'reason') ?? '');
      return;
    }
    await this.saver.write(stringField(answer, 'file') ?? path, stringField(answer, 'text') ?? '');
    this.events.message(stringField(answer, 'message') ?? '');
    this.refresh();
  }

  private async revert(): Promise<void> {
    await this.document.read('editor_measurements_revert');
    this.clearRefusals();
    this.events.message('');
    this.refresh();
  }
}
