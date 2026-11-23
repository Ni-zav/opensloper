// Files on the user's machine through the browser's File System Access API,
// where the browser has it (Chromium-based ones): a pattern opened from a
// file saves back to it, and its measurement file is found beside it from a
// folder the user grants once, which the browser keeps (IndexedDB holds the
// folder's handle, never the files). Elsewhere the app falls back to
// uploading and downloading. Nothing leaves the machine.
import { STRINGS } from './strings.ts';

// The pickers and permissions, which the DOM library does not declare yet
interface PickerType {
  description: string;
  accept: Record<string, string[]>;
}

interface PickerOptions {
  id?: string;
  startIn?: FileSystemHandle;
  types?: PickerType[];
}

interface FilePickers {
  showOpenFilePicker(options: PickerOptions & { multiple?: boolean }): Promise<FileSystemFileHandle[]>;
  showSaveFilePicker(options: PickerOptions & { suggestedName?: string }): Promise<FileSystemFileHandle>;
  showDirectoryPicker(options: PickerOptions & { mode?: 'read' | 'readwrite' }): Promise<FileSystemDirectoryHandle>;
}

type AccessMode = 'read' | 'readwrite';

interface PermissionMethods {
  queryPermission?(descriptor: { mode: AccessMode }): Promise<PermissionState>;
  requestPermission?(descriptor: { mode: AccessMode }): Promise<PermissionState>;
}

export const PATTERN_EXTENSION = '.sloper';
export const MEASUREMENTS_EXTENSION = '.slm';
const PATTERN_TYPE: PickerType = {
  description: STRINGS.patternFiles,
  accept: { 'application/json': [PATTERN_EXTENSION] },
};
const MEASUREMENTS_TYPE: PickerType = {
  description: STRINGS.measurementFiles,
  accept: { 'application/json': [MEASUREMENTS_EXTENSION] },
};
// The pickers remember the folder last used under these
const PATTERNS_ID = 'patterns';
const MEASUREMENTS_ID = 'measurements';

// Where the granted folders are kept between visits
const DATABASE = 'opensloper-files';
const FOLDERS = 'folders';

function isFilePickers(value: object): value is FilePickers {
  return ['showOpenFilePicker', 'showSaveFilePicker', 'showDirectoryPicker'].every(
    (name) => typeof Reflect.get(value, name) === 'function',
  );
}

function pickers(): FilePickers | undefined {
  return isFilePickers(window) ? window : undefined;
}

// True where files can be opened and saved in place
export function hasFileAccess(): boolean {
  return pickers() !== undefined;
}

// A picker the user closed is no error
function cancelled(error: unknown): boolean {
  return error instanceof DOMException && error.name === 'AbortError';
}

async function permission(handle: FileSystemHandle, mode: AccessMode, ask: boolean): Promise<boolean> {
  const methods = handle as FileSystemHandle & PermissionMethods;
  if (methods.queryPermission === undefined) {
    return true;
  }
  if ((await methods.queryPermission({ mode })) === 'granted') {
    return true;
  }
  if (!ask || methods.requestPermission === undefined) {
    return false;
  }
  try {
    return (await methods.requestPermission({ mode })) === 'granted';
  } catch {
    // Asking needs a click the user has just made
    return false;
  }
}

// The parts of a path recorded with /, from a folder: undefined when it leaves the top
export function walkPath(from: string[], path: string): string[] | undefined {
  const parts = [...from];
  for (const part of path.split('/')) {
    if (part === '..') {
      if (parts.length === 0) {
        return undefined;
      }
      parts.pop();
    } else if (part !== '' && part !== '.') {
      parts.push(part);
    }
  }
  return parts;
}

// The path from one file to another, as a pattern records its measurement file
export function relativePath(fromFile: readonly string[], toFile: readonly string[]): string {
  const fromFolder = fromFile.slice(0, -1);
  let shared = 0;
  while (shared < fromFolder.length && shared < toFile.length - 1 && fromFolder[shared] === toFile[shared]) {
    shared++;
  }
  return [...fromFolder.slice(shared).map(() => '..'), ...toFile.slice(shared)].join('/');
}

async function fileAt(folder: FileSystemDirectoryHandle, parts: string[]): Promise<FileSystemFileHandle | undefined> {
  const name = parts.at(-1);
  if (name === undefined) {
    return undefined;
  }
  try {
    let at = folder;
    for (const part of parts.slice(0, -1)) {
      // One folder after another, as the path goes
      // oxlint-disable-next-line no-await-in-loop
      at = await at.getDirectoryHandle(part);
    }
    return await at.getFileHandle(name);
  } catch {
    return undefined;
  }
}

async function openDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE, 1);
    request.addEventListener('upgradeneeded', () => {
      request.result.createObjectStore(FOLDERS, { autoIncrement: true });
    });
    request.addEventListener('success', () => {
      resolve(request.result);
    });
    request.addEventListener('error', () => {
      reject(request.error ?? new Error(`cannot open ${DATABASE}`));
    });
  });
}

async function storedFolders(): Promise<FileSystemDirectoryHandle[]> {
  const database = await openDatabase();
  try {
    return await new Promise((resolve, reject) => {
      const request = database.transaction(FOLDERS).objectStore(FOLDERS).getAll();
      request.addEventListener('success', () => {
        resolve(
          request.result.filter((item): item is FileSystemDirectoryHandle => item instanceof FileSystemDirectoryHandle),
        );
      });
      request.addEventListener('error', () => {
        reject(request.error ?? new Error(`cannot read ${FOLDERS}`));
      });
    });
  } finally {
    database.close();
  }
}

async function storeFolder(folder: FileSystemDirectoryHandle): Promise<void> {
  const database = await openDatabase();
  try {
    await new Promise<void>((resolve, reject) => {
      const transaction = database.transaction(FOLDERS, 'readwrite');
      transaction.objectStore(FOLDERS).add(folder);
      transaction.addEventListener('complete', () => {
        resolve();
      });
      transaction.addEventListener('error', () => {
        reject(transaction.error ?? new Error(`cannot write ${FOLDERS}`));
      });
    });
  } finally {
    database.close();
  }
}

// What a search beside the pattern found: the file, or a folder that holds
// the pattern but needs the user's leave to be read
export interface Found {
  file: FileSystemFileHandle | undefined;
  needsLeave: FileSystemDirectoryHandle | undefined;
}

export class FileAccess {
  private readonly pickers: FilePickers;
  // Kept here too, should the browser's storage be closed to the page
  private folders: FileSystemDirectoryHandle[] = [];
  private loaded = false;

  private constructor(filePickers: FilePickers) {
    this.pickers = filePickers;
  }

  // Undefined where the browser has no File System Access
  static create(): FileAccess | undefined {
    const found = pickers();
    return found === undefined ? undefined : new FileAccess(found);
  }

  // A pattern, with its measurement file if the user picks that too; empty when cancelled
  async openPattern(startIn: FileSystemHandle | undefined): Promise<FileSystemFileHandle[]> {
    try {
      return await this.pickers.showOpenFilePicker({
        id: PATTERNS_ID,
        multiple: true,
        types: [PATTERN_TYPE, MEASUREMENTS_TYPE],
        ...(startIn === undefined ? {} : { startIn }),
      });
    } catch (error: unknown) {
      if (cancelled(error)) {
        return [];
      }
      throw error;
    }
  }

  // A measurement file, starting beside the pattern
  async openMeasurements(startIn: FileSystemHandle | undefined): Promise<FileSystemFileHandle | undefined> {
    try {
      const [handle] = await this.pickers.showOpenFilePicker({
        id: MEASUREMENTS_ID,
        types: [MEASUREMENTS_TYPE],
        ...(startIn === undefined ? {} : { startIn }),
      });
      return handle;
    } catch (error: unknown) {
      if (cancelled(error)) {
        return undefined;
      }
      throw error;
    }
  }

  // Where to save a new file; undefined when cancelled
  async chooseSave(
    suggestedName: string,
    kind: 'pattern' | 'measurements',
    startIn: FileSystemHandle | undefined,
  ): Promise<FileSystemFileHandle | undefined> {
    try {
      return await this.pickers.showSaveFilePicker({
        id: kind === 'pattern' ? PATTERNS_ID : MEASUREMENTS_ID,
        suggestedName,
        types: [kind === 'pattern' ? PATTERN_TYPE : MEASUREMENTS_TYPE],
        ...(startIn === undefined ? {} : { startIn }),
      });
    } catch (error: unknown) {
      if (cancelled(error)) {
        return undefined;
      }
      throw error;
    }
  }

  // Asks for a folder that holds the pattern and its measurements, which is
  // remembered; undefined when cancelled
  async grantFolder(startIn: FileSystemHandle | undefined): Promise<FileSystemDirectoryHandle | undefined> {
    let folder: FileSystemDirectoryHandle;
    try {
      folder = await this.pickers.showDirectoryPicker({
        id: PATTERNS_ID,
        mode: 'readwrite',
        ...(startIn === undefined ? {} : { startIn }),
      });
    } catch (error: unknown) {
      if (cancelled(error)) {
        return undefined;
      }
      throw error;
    }
    await this.loadFolders();
    if (!(await this.isKnown(folder))) {
      this.folders.push(folder);
      try {
        await storeFolder(folder);
      } catch {
        // Kept for this visit only
      }
    }
    return folder;
  }

  // The file a pattern records, by its path from the pattern, in a granted
  // folder that holds the pattern. Ask lets it ask for leave to read a
  // folder, which needs a click the user has just made.
  async findBeside(pattern: FileSystemFileHandle, path: string, ask: boolean): Promise<Found> {
    await this.loadFolders();
    let needsLeave: FileSystemDirectoryHandle | undefined;
    for (const folder of this.folders) {
      // One folder after another: each may ask the user
      // oxlint-disable-next-line no-await-in-loop
      const place = await this.placeIn(folder, pattern);
      if (place === undefined) {
        continue;
      }
      // oxlint-disable-next-line no-await-in-loop
      if (!(await permission(folder, 'readwrite', ask))) {
        needsLeave ??= folder;
        continue;
      }
      const parts = walkPath(place.slice(0, -1), path);
      // oxlint-disable-next-line no-await-in-loop
      const file = parts === undefined ? undefined : await fileAt(folder, parts);
      if (file !== undefined) {
        return { file, needsLeave: undefined };
      }
    }
    return { file: undefined, needsLeave };
  }

  // The path from the pattern to a file, when a granted folder holds both
  async pathBetween(pattern: FileSystemFileHandle, file: FileSystemFileHandle): Promise<string | undefined> {
    await this.loadFolders();
    for (const folder of this.folders) {
      // oxlint-disable-next-line no-await-in-loop
      const [from, to] = await Promise.all([this.placeIn(folder, pattern), this.placeIn(folder, file)]);
      if (from !== undefined && to !== undefined) {
        return relativePath(from, to);
      }
    }
    return undefined;
  }

  // Writes the file, asking for leave first: call it while the user's click counts
  async write(handle: FileSystemFileHandle, text: string): Promise<boolean> {
    if (!(await permission(handle, 'readwrite', true))) {
      return false;
    }
    const stream = await handle.createWritable();
    await stream.write(text);
    await stream.close();
    return true;
  }

  // Asks for leave to write the file while the user's click counts; false when refused
  async mayWrite(handle: FileSystemFileHandle): Promise<boolean> {
    return permission(handle, 'readwrite', true);
  }

  private async placeIn(folder: FileSystemDirectoryHandle, handle: FileSystemHandle): Promise<string[] | undefined> {
    try {
      return (await folder.resolve(handle)) ?? undefined;
    } catch {
      return undefined;
    }
  }

  private async isKnown(folder: FileSystemDirectoryHandle): Promise<boolean> {
    for (const known of this.folders) {
      // oxlint-disable-next-line no-await-in-loop
      if (await known.isSameEntry(folder)) {
        return true;
      }
    }
    return false;
  }

  private async loadFolders(): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    try {
      this.folders = [...(await storedFolders()), ...this.folders];
    } catch {
      // Browser storage closed to the page: folders last for this visit
    }
  }
}
