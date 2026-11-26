// The layout open in the engine's Publish server, as the desktop's
// TLayoutDocument is to the publish window. The browser has no disk, so a
// layout is opened with the files its sources read, given as text. The engine
// says which files it still needs by their paths from the layout; the files
// the user chose have only their names, so each is matched by name.
import { EngineError, type Engine } from '../engine/engine.ts';
import {
  booleanField,
  isRecord,
  numberField,
  recordsField,
  stringField,
  stringsField,
  type JsonRecord,
} from '../engine/replies.ts';
import { baseName } from '../ui/download.ts';

export interface LayoutProblem {
  text: string;
  // It stops printing and export
  blocking: boolean;
  // The placement or sheet note it names, by index, or -1
  placement: number;
  note: number;
}

// A copy waiting in the tray to be placed
export interface TrayCopy {
  caption: string;
  // False while its piece has a problem in the pattern
  canPlace: boolean;
}

export interface LayoutState {
  name: string;
  // What it is printed or cut on: tiled, large, projector or material
  kind: string;
  placed: number;
  unplaced: number;
  // The copies waiting to be placed, in the order the engine places them
  tray: TrayCopy[];
  // What the status bar says of the pages or sheet
  summary: string;
  problems: LayoutProblem[];
  // The files the sources need and were not given, by their paths from the layout
  missing: string[];
  canUndo: boolean;
  canRedo: boolean;
  // The name of the step undo would take
  undo: string;
  // Changed since it was opened or saved
  modified: boolean;
}

// What to open: a layout file's text, or the pattern among the files to start one for
export type LayoutStart = { layout: string } | { pattern: string };

// Hears that the layout changed; generation grows when another is opened
export type LayoutListener = (document: LayoutDocument) => void;

const EMPTY: LayoutState = {
  name: '',
  kind: 'tiled',
  placed: 0,
  unplaced: 0,
  tray: [],
  summary: '',
  problems: [],
  missing: [],
  canUndo: false,
  canRedo: false,
  undo: '',
  modified: false,
};

function parseState(answer: JsonRecord): LayoutState {
  return {
    name: stringField(answer, 'name') ?? '',
    kind: (isRecord(answer.output) ? stringField(answer.output, 'kind') : undefined) ?? 'tiled',
    placed: numberField(answer, 'placed') ?? 0,
    unplaced: numberField(answer, 'unplaced') ?? 0,
    tray: recordsField(answer, 'tray').map((copy) => ({
      caption: stringField(copy, 'caption') ?? '',
      canPlace: booleanField(copy, 'canPlace') ?? false,
    })),
    summary: stringField(answer, 'summary') ?? '',
    problems: recordsField(answer, 'problems').map((problem) => ({
      text: stringField(problem, 'text') ?? '',
      blocking: booleanField(problem, 'blocking') ?? false,
      placement: numberField(problem, 'placement') ?? -1,
      note: numberField(problem, 'note') ?? -1,
    })),
    missing: stringsField(answer, 'missing') ?? [],
    canUndo: booleanField(answer, 'canUndo') ?? false,
    canRedo: booleanField(answer, 'canRedo') ?? false,
    undo: stringField(answer, 'undo') ?? '',
    modified: booleanField(answer, 'modified') ?? false,
  };
}

function fileList(files: Iterable<[path: string, text: string]>): { path: string; text: string }[] {
  return [...files].map(([path, text]) => ({ path, text }));
}

export class LayoutDocument {
  private readonly engine: Engine;
  private readonly listeners: LayoutListener[] = [];
  private current: LayoutState = EMPTY;
  private opened = 0;

  // The layout file's name as the user chose it, or the one a new layout
  // would be saved as; '' before anything is open
  fileName = '';

  constructor(engine: Engine) {
    this.engine = engine;
  }

  get state(): Readonly<LayoutState> {
    return this.current;
  }

  // Grows when another layout is opened
  get generation(): number {
    return this.opened;
  }

  addListener(listener: LayoutListener): void {
    this.listeners.push(listener);
  }

  removeListener(listener: LayoutListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  // A method that only reads the layout
  async read(method: string, params: object = {}): Promise<JsonRecord> {
    return this.engine.call(method, params);
  }

  // A press or a drag's move: the engine holds or moves something without
  // ending an undo step, so the state is left until the drag ends with call
  async live(method: string, params: object = {}): Promise<JsonRecord> {
    return this.engine.call(method, params);
  }

  // A method that may change the layout; the listeners hear of it whether it
  // succeeded or was refused
  async call(method: string, params: object = {}): Promise<JsonRecord> {
    try {
      return await this.engine.call(method, params);
    } finally {
      this.current = parseState(await this.engine.call('publish_state'));
      this.changed();
    }
  }

  async undo(): Promise<void> {
    await this.ignoreRefusal(this.call('publish_undo'));
  }

  async redo(): Promise<void> {
    await this.ignoreRefusal(this.call('publish_redo'));
  }

  // The layout file's text, to download, counted as saved
  async save(): Promise<string> {
    return stringField(await this.call('publish_save'), 'text') ?? '';
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

  // Opens the layout or starts one, with the files chosen, by name. Files the
  // sources name from other folders are found among them by name too.
  async open(files: ReadonlyMap<string, string>, start: LayoutStart): Promise<void> {
    this.current = parseState(await this.engine.call('publish_open', { ...start, files: fileList(files) }));
    await this.giveMissing(files);
    this.opened += 1;
    this.changed();
  }

  // Adds a pattern among the files chosen, by name, with the others for it
  // to read; how many copies went in the tray
  async addPattern(files: ReadonlyMap<string, string>, name: string): Promise<number> {
    const answer = await this.call('publish_add_pattern', { path: name, files: fileList(files) });
    await this.giveMissing(files);
    this.changed();
    return numberField(answer, 'added') ?? 0;
  }

  // Reads a pattern, by its source id, with the measurement file of this
  // name among the files chosen, or with its own for ''
  async setMeasurements(source: number, files: ReadonlyMap<string, string>, name: string): Promise<void> {
    await this.call('publish_set_measurements', { source, path: name, files: fileList(files) });
    await this.giveMissing(files);
    this.changed();
  }

  // A pattern found may name a measurement file, needed in turn. Each path
  // is given once, so a round always gives something new.
  private async giveMissing(files: ReadonlyMap<string, string>): Promise<void> {
    const given = new Set<string>();
    for (;;) {
      const found = this.current.missing.flatMap((path): [string, string][] => {
        const text = files.get(baseName(path));
        return text === undefined || given.has(path) ? [] : [[path, text]];
      });
      if (found.length === 0) {
        return;
      }
      for (const [path] of found) {
        given.add(path);
      }
      // Each round needs the files the one before found
      // oxlint-disable-next-line no-await-in-loop
      this.current = parseState(await this.engine.call('publish_add_files', { files: fileList(found) }));
    }
  }

  private changed(): void {
    // A copy, as a listener may remove itself
    for (const listener of this.listeners.slice()) {
      listener(this);
    }
  }
}
