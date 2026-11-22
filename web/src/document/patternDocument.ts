// The pattern open in the engine, as the desktop's TPatternDocument is to its
// panels: calls go to the engine, and after each one the changes it made come
// back from editor_changes and go to every listener, as AddListener's do.
import { EngineError, type Engine } from '../engine/engine.ts';
import { booleanField, numberField, stringField, stringsField, type JsonRecord } from '../engine/replies.ts';

// As TDocumentChange: definitions or results, every object new (undo, open),
// another measurement set, what undo and redo do, the file name or modified
// flag, and view state outside undo
export type DocumentChange = 'pattern' | 'objectsReplaced' | 'measurements' | 'history' | 'file' | 'view';

const DOCUMENT_CHANGES: readonly DocumentChange[] = [
  'pattern',
  'objectsReplaced',
  'measurements',
  'history',
  'file',
  'view',
];

export interface DocumentState {
  // Grows when another pattern is opened
  generation: number;
  canUndo: boolean;
  canRedo: boolean;
  // The names of the steps undo and redo would take
  undo: string;
  redo: string;
  modified: boolean;
}

export type DocumentListener = (document: PatternDocument, changes: ReadonlySet<DocumentChange>) => void;

function isDocumentChange(name: string): name is DocumentChange {
  return (DOCUMENT_CHANGES as readonly string[]).includes(name);
}

export class PatternDocument {
  private readonly engine: Engine;
  private readonly listeners: DocumentListener[] = [];
  private current: DocumentState = {
    generation: 0,
    canUndo: false,
    canRedo: false,
    undo: '',
    redo: '',
    modified: false,
  };

  // The file's name as the user chose it, for saving and the title; '' for a new pattern
  fileName = '';

  constructor(engine: Engine) {
    this.engine = engine;
  }

  get state(): Readonly<DocumentState> {
    return this.current;
  }

  addListener(listener: DocumentListener): void {
    this.listeners.push(listener);
  }

  // A panel that goes removes its listener, so the document does not keep it alive
  removeListener(listener: DocumentListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  // A method that only reads: nothing can have changed
  async read(method: string, params: object = {}): Promise<JsonRecord> {
    return this.engine.call(method, params);
  }

  // A method that may change the pattern; the listeners hear what changed
  // whether it succeeded or was refused
  async call(method: string, params: object = {}): Promise<JsonRecord> {
    try {
      return await this.engine.call(method, params);
    } finally {
      await this.refresh();
    }
  }

  // Asks the engine what changed and tells the listeners, when anything did
  async refresh(): Promise<void> {
    const answer = await this.engine.call('editor_changes');
    this.current = {
      generation: numberField(answer, 'generation') ?? this.current.generation,
      canUndo: booleanField(answer, 'canUndo') ?? false,
      canRedo: booleanField(answer, 'canRedo') ?? false,
      undo: stringField(answer, 'undo') ?? '',
      redo: stringField(answer, 'redo') ?? '',
      modified: booleanField(answer, 'modified') ?? false,
    };
    const changes = new Set((stringsField(answer, 'changes') ?? []).filter(isDocumentChange));
    if (changes.size > 0) {
      // A copy, as a listener may remove itself
      for (const listener of this.listeners.slice()) {
        listener(this, changes);
      }
    }
  }

  async undo(): Promise<void> {
    await this.ignoreRefusal(this.call('undo'));
  }

  async redo(): Promise<void> {
    await this.ignoreRefusal(this.call('redo'));
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
}
