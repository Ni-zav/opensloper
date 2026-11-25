// The layout open in the engine's Publish server, as the desktop's
// TLayoutDocument is to the publish window. The browser has no disk, so a
// layout is opened with the files its sources read, given as text. The engine
// says which files it still needs by their paths from the layout; the files
// the user chose have only their names, so each is matched by name.
import type { Engine } from '../engine/engine.ts';
import {
  booleanField,
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
}

export interface LayoutState {
  name: string;
  placed: number;
  unplaced: number;
  problems: LayoutProblem[];
  // The files the sources need and were not given, by their paths from the layout
  missing: string[];
}

// What to open: a layout file's text, or the pattern among the files to start one for
export type LayoutStart = { layout: string } | { pattern: string };

const EMPTY: LayoutState = { name: '', placed: 0, unplaced: 0, problems: [], missing: [] };

function parseState(answer: JsonRecord): LayoutState {
  return {
    name: stringField(answer, 'name') ?? '',
    placed: numberField(answer, 'placed') ?? 0,
    unplaced: numberField(answer, 'unplaced') ?? 0,
    problems: recordsField(answer, 'problems').map((problem) => ({
      text: stringField(problem, 'text') ?? '',
      blocking: booleanField(problem, 'blocking') ?? false,
    })),
    missing: stringsField(answer, 'missing') ?? [],
  };
}

function fileList(files: Iterable<[path: string, text: string]>): { path: string; text: string }[] {
  return [...files].map(([path, text]) => ({ path, text }));
}

export class LayoutDocument {
  private readonly engine: Engine;
  private current: LayoutState = EMPTY;

  // The layout file's name as the user chose it, or the one a new layout
  // would be saved as; '' before anything is open
  fileName = '';

  constructor(engine: Engine) {
    this.engine = engine;
  }

  get state(): Readonly<LayoutState> {
    return this.current;
  }

  // Opens the layout or starts one, with the files chosen, by name. Files the
  // sources name from other folders are found among them by name too.
  async open(files: ReadonlyMap<string, string>, start: LayoutStart): Promise<void> {
    this.current = parseState(await this.engine.call('publish_open', { ...start, files: fileList(files) }));
    // A pattern found may name a measurement file, needed in turn. Each path
    // is given once, so a round always gives something new.
    const given = new Set<string>();
    for (;;) {
      const found = this.current.missing.flatMap((path): [string, string][] => {
        const text = files.get(baseName(path));
        return text === undefined || given.has(path) ? [] : [[path, text]];
      });
      if (found.length === 0) {
        break;
      }
      for (const [path] of found) {
        given.add(path);
      }
      // Each round needs the files the one before found
      // oxlint-disable-next-line no-await-in-loop
      this.current = parseState(await this.engine.call('publish_add_files', { files: fileList(found) }));
    }
  }
}
