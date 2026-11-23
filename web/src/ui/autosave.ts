// Work in progress kept in the browser, so a closed tab or a crash loses
// nothing: a second after each change, while the pattern is not saved, the
// engine's copy of it (editor_snapshot: the pattern file's text and its
// measurement set's) is written to the page's private file system (OPFS)
// under the tab's own id, with a record in IndexedDB of when, the file
// names, and the handles of the files it came from, so a pattern opened
// again still saves to its file. Saving removes it. Each tab holds a Web
// Lock while it is open, so work whose lock is free is left over from a
// tab that closed, which the app offers to open again. Where the page
// cannot write OPFS files the texts go in the record. Nothing leaves the
// machine.
import type { PatternDocument } from '../document/patternDocument.ts';
import { EngineError } from '../engine/engine.ts';
import { isRecord, stringField } from '../engine/replies.ts';
import { allRecords, deleteRecord, putRecord, WORK_STORE } from './browserStore.ts';

const WORK_FOLDER = 'work';
const PATTERN_FILE = 'pattern.sloper';
const MEASUREMENTS_FILE = 'measurements.slm';
// How long after a change the work is kept, in ms, so a run of edits is written once
const DELAY_MS = 1000;
const LOCK_PREFIX = 'opensloper-work-';
// The engine's code for a call it refuses, as while a drag is open (RPC_REFUSED)
const REFUSED = -32000;

// What the app knows of the pattern besides its text
export interface WorkFiles {
  fileName: string;
  patternHandle: FileSystemFileHandle | undefined;
  measurementsHandle: FileSystemFileHandle | undefined;
}

// A tab's work as kept: its texts are read with Autosave.texts
export interface Work extends WorkFiles {
  id: string;
  // When it was kept, in ms since 1970
  time: number;
  hasMeasurements: boolean;
  // The texts, here only where OPFS files cannot be written
  text?: string;
  measurementsText?: string;
}

export interface WorkTexts {
  text: string;
  // Undefined when the pattern had no set given as text
  measurementsText: string | undefined;
}

function isWork(value: unknown): value is Work {
  return isRecord(value) && typeof value.id === 'string' && typeof value.time === 'number';
}

// OPFS files written from the page, which some browsers allow only in workers
function canWriteFiles(): boolean {
  return (
    typeof navigator.storage.getDirectory === 'function' &&
    typeof FileSystemFileHandle.prototype.createWritable === 'function'
  );
}

async function workFolder(id: string, create: boolean): Promise<FileSystemDirectoryHandle> {
  const root = await navigator.storage.getDirectory();
  const work = await root.getDirectoryHandle(WORK_FOLDER, { create });
  return work.getDirectoryHandle(id, { create });
}

async function writeFile(folder: FileSystemDirectoryHandle, name: string, text: string): Promise<void> {
  const stream = await (await folder.getFileHandle(name, { create: true })).createWritable();
  await stream.write(text);
  await stream.close();
}

async function readFile(folder: FileSystemDirectoryHandle, name: string): Promise<string> {
  return (await (await folder.getFileHandle(name)).getFile()).text();
}

// True when no open tab holds the work's lock; without Web Locks, every
// other tab's work counts as left over
async function lockFree(id: string): Promise<boolean> {
  if (typeof navigator.locks === 'undefined') {
    return true;
  }
  return navigator.locks.request(LOCK_PREFIX + id, { ifAvailable: true }, (lock) => lock !== null);
}

export class Autosave {
  private readonly id = crypto.randomUUID();
  private readonly document: PatternDocument;
  private readonly files: () => WorkFiles;
  private readonly kept: (kept: boolean) => void;
  private timer: ReturnType<typeof setTimeout> | undefined;
  // One write or removal at a time, in order
  private queue: Promise<void> = Promise.resolve();
  private hasWork = false;
  // Writes waiting or under way, which a save must follow with a removal
  private writes = 0;

  // Files says what the app knows of the pattern's files; kept hears when
  // the tab's work is written or removed
  constructor(document: PatternDocument, files: () => WorkFiles, kept: (kept: boolean) => void) {
    this.document = document;
    this.files = files;
    this.kept = kept;
  }

  // Holds the tab's lock and keeps its work from now on
  start(): void {
    if (typeof navigator.locks !== 'undefined') {
      // Held until the tab closes
      void navigator.locks.request(LOCK_PREFIX + this.id, async () => new Promise<void>(() => undefined));
    }
    this.document.addListener(() => {
      this.changed();
    });
    window.addEventListener('pagehide', () => {
      if (this.timer !== undefined) {
        void this.flush();
      }
    });
  }

  // Work left by tabs that have closed, the newest first
  async leftOver(): Promise<Work[]> {
    let records: unknown[];
    try {
      records = await allRecords(WORK_STORE);
    } catch {
      return [];
    }
    const others = records.filter(isWork).filter((work) => work.id !== this.id);
    const free = await Promise.all(others.map(async (work) => lockFree(work.id)));
    // A new array from filter, so sorting it in place changes nothing else
    // oxlint-disable-next-line unicorn/no-array-sort
    return others.filter((_work, index) => free[index] === true).sort((one, other) => other.time - one.time);
  }

  async texts(work: Work): Promise<WorkTexts> {
    if (work.text !== undefined) {
      return { text: work.text, measurementsText: work.measurementsText };
    }
    const folder = await workFolder(work.id, false);
    return {
      text: await readFile(folder, PATTERN_FILE),
      measurementsText: work.hasMeasurements ? await readFile(folder, MEASUREMENTS_FILE) : undefined,
    };
  }

  // Removes work left over, once opened again or dropped
  async discard(work: Work): Promise<void> {
    await this.removeWork(work.id);
  }

  // Writes the work now, as the tab closes, rather than after the delay;
  // resolves once it is written
  async flush(): Promise<void> {
    if (this.timer !== undefined) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
    this.enqueueWrite();
    await this.queue;
  }

  private changed(): void {
    const waited = this.timer !== undefined;
    if (this.timer !== undefined) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
    if (!this.document.state.modified) {
      // Saved, or nothing done: nothing to lose, once any write under way has finished
      if (this.hasWork || waited || this.writes > 0) {
        this.enqueue(async () => this.removeOwn());
      }
      return;
    }
    this.timer = setTimeout(() => {
      this.timer = undefined;
      this.enqueueWrite();
    }, DELAY_MS);
  }

  private enqueueWrite(): void {
    this.writes++;
    this.enqueue(async () => {
      try {
        await this.keep();
      } finally {
        this.writes--;
      }
    });
  }

  private enqueue(job: () => Promise<void>): void {
    this.queue = this.queue.then(job).catch((error: unknown) => {
      // Storage full or closed to the page: the work is only in the tab
      console.warn('work in progress not kept', error);
    });
  }

  private async keep(): Promise<void> {
    if (!this.document.state.modified) {
      return;
    }
    let snapshot;
    try {
      snapshot = await this.document.read('editor_snapshot');
    } catch (error: unknown) {
      // A drag is open: kept once it ends, which changes the pattern
      if (error instanceof EngineError && error.code === REFUSED) {
        return;
      }
      throw error;
    }
    const text = stringField(snapshot, 'text') ?? '';
    const measurementsText = stringField(snapshot, 'measurementsText');
    const work: Work = {
      id: this.id,
      time: Date.now(),
      hasMeasurements: measurementsText !== undefined,
      ...this.files(),
    };
    if (canWriteFiles()) {
      const folder = await workFolder(this.id, true);
      await writeFile(folder, PATTERN_FILE, text);
      if (measurementsText !== undefined) {
        await writeFile(folder, MEASUREMENTS_FILE, measurementsText);
      }
    } else {
      work.text = text;
      if (measurementsText !== undefined) {
        work.measurementsText = measurementsText;
      }
    }
    await putRecord(WORK_STORE, work, this.id);
    this.hasWork = true;
    this.kept(true);
  }

  private async removeOwn(): Promise<void> {
    // Changed again while waiting its turn
    if (this.document.state.modified) {
      return;
    }
    await this.removeWork(this.id);
    this.hasWork = false;
    this.kept(false);
  }

  private async removeWork(id: string): Promise<void> {
    await deleteRecord(WORK_STORE, id);
    if (canWriteFiles()) {
      try {
        const root = await navigator.storage.getDirectory();
        await (await root.getDirectoryHandle(WORK_FOLDER)).removeEntry(id, { recursive: true });
      } catch {
        // Never written, or kept in the record
      }
    }
  }
}
