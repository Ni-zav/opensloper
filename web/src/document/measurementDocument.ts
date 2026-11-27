// The measurement set open in the engine's Measurements server, as the
// desktop's TMeasurementDocument is to the measurements window. The browser
// has no disk, so a set is opened from its file's text. The engine keeps the
// set and its undo history, and says how the table shows it, values as text
// in the unit chosen. Every edit is one undo step, and its answer is the
// state, which the listeners hear of.
import { EngineError, type Engine } from '../engine/engine.ts';
import { booleanField, isRecord, recordsField, stringField, stringsField, type JsonRecord } from '../engine/replies.ts';
import type { MeasureUnit } from '../editor/rulerTicks.ts';

// A measurement as the table shows it: one value a size, or the one value
// of a set without sizes, '' where it has none
export interface MeasurementRow {
  key: string;
  values: string[];
  description: string;
}

export interface MeasurementState {
  name: string;
  notes: string;
  // None for a set without sizes
  sizes: string[];
  rows: MeasurementRow[];
  // Changed since it was opened
  modified: boolean;
  canUndo: boolean;
  canRedo: boolean;
  // The name of the step undo would take
  undo: string;
}

// Which cell of a row an edit is to
export type MeasurementColumn = 'key' | 'value' | 'description';

// What setting a cell did: refused, with the reason, or done; key is the
// measurement's afterwards, as a rename changes it
export interface CellResult {
  done: boolean;
  reason: string;
  key: string;
}

// Hears that the set changed; generation grows when another is opened
export type MeasurementListener = (document: MeasurementDocument) => void;

const EMPTY: MeasurementState = {
  name: '',
  notes: '',
  sizes: [],
  rows: [],
  modified: false,
  canUndo: false,
  canRedo: false,
  undo: '',
};

function parseState(answer: JsonRecord): MeasurementState {
  const set = isRecord(answer.set) ? answer.set : {};
  return {
    name: stringField(set, 'name') ?? '',
    notes: stringField(set, 'notes') ?? '',
    sizes: stringsField(answer, 'sizes') ?? [],
    rows: recordsField(answer, 'rows').map((row) => ({
      key: stringField(row, 'key') ?? '',
      values: stringsField(row, 'values') ?? [],
      description: stringField(row, 'description') ?? '',
    })),
    modified: booleanField(answer, 'modified') ?? false,
    canUndo: booleanField(answer, 'canUndo') ?? false,
    canRedo: booleanField(answer, 'canRedo') ?? false,
    undo: stringField(answer, 'undo') ?? '',
  };
}

export class MeasurementDocument {
  private readonly engine: Engine;
  private readonly listeners: MeasurementListener[] = [];
  private current: MeasurementState = EMPTY;
  private opened = 0;
  private shownIn: MeasureUnit = 'mm';

  // The file's name as the user chose it; '' before anything is open
  fileName = '';

  constructor(engine: Engine) {
    this.engine = engine;
  }

  get state(): Readonly<MeasurementState> {
    return this.current;
  }

  // Grows when another set is opened
  get generation(): number {
    return this.opened;
  }

  // The unit the table shows values in
  get unit(): MeasureUnit {
    return this.shownIn;
  }

  addListener(listener: MeasurementListener): void {
    this.listeners.push(listener);
  }

  removeListener(listener: MeasurementListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  // A method that only reads the set
  async read(method: string, params: object = {}): Promise<JsonRecord> {
    return this.engine.call(method, params);
  }

  // Opens a set from its file's text; a file that cannot be read is refused
  // with the engine's reason, and the set open stays
  async open(text: string, fileName: string): Promise<void> {
    this.current = parseState(await this.engine.call('measurements_open', { text, unit: this.shownIn }));
    this.fileName = fileName;
    this.opened += 1;
    this.changed();
  }

  // Shows the values in another unit; the set is unchanged
  async showIn(unit: MeasureUnit): Promise<void> {
    this.current = parseState(await this.engine.call('measurements_state', { unit }));
    this.shownIn = unit;
    this.changed();
  }

  // A cell as typed: a key, a value in the unit shown (size by its index, 0
  // without sizes) or a description
  async setCell(key: string, column: MeasurementColumn, size: number, text: string): Promise<CellResult> {
    const answer = await this.call('measurements_set', { key, column, size, text });
    return {
      done: booleanField(answer, 'done') === true,
      reason: stringField(answer, 'reason') ?? '',
      key: stringField(answer, 'key') ?? key,
    };
  }

  // A new measurement at the end, with a free key to type over; its key
  async add(): Promise<string> {
    return stringField(await this.call('measurements_add'), 'key') ?? '';
  }

  async delete(key: string): Promise<void> {
    await this.call('measurements_delete', { key });
  }

  // To its place in the table afterwards, from 0
  async move(key: string, index: number): Promise<void> {
    await this.call('measurements_move', { key, index });
  }

  async undo(): Promise<void> {
    await this.ignoreRefusal(this.call('measurements_undo'));
  }

  async redo(): Promise<void> {
    await this.ignoreRefusal(this.call('measurements_redo'));
  }

  // An edit, in the unit shown; its answer is the state
  private async call(method: string, params: object = {}): Promise<JsonRecord> {
    const answer = await this.engine.call(method, { ...params, unit: this.shownIn });
    this.current = parseState(answer);
    this.changed();
    return answer;
  }

  // Nothing to undo or redo is no error to the user
  private async ignoreRefusal(pending: Promise<JsonRecord>): Promise<void> {
    try {
      await pending;
    } catch (error: unknown) {
      if (!(error instanceof EngineError)) {
        throw error;
      }
    }
  }

  private changed(): void {
    for (const listener of this.listeners.slice()) {
      listener(this);
    }
  }
}
