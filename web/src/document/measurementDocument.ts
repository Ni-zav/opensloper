// The measurement set open in the engine's Measurements server, as the
// desktop's TMeasurementDocument is to the measurements window. The browser
// has no disk, so a set is opened from its file's text. The engine keeps the
// set and says how the table shows it, values as text in the unit chosen.
import type { Engine } from '../engine/engine.ts';
import { isRecord, recordsField, stringField, stringsField, type JsonRecord } from '../engine/replies.ts';
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
}

// Hears that the set changed; generation grows when another is opened
export type MeasurementListener = (document: MeasurementDocument) => void;

const EMPTY: MeasurementState = { name: '', notes: '', sizes: [], rows: [] };

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

  private changed(): void {
    for (const listener of this.listeners.slice()) {
      listener(this);
    }
  }
}
