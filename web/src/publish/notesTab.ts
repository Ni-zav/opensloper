// The Notes tab of the Publish app's side panel, as the desktop builds it in
// Sloper.Publish.MainForm (BuildNotesTab): Add note, then the sheet note
// chosen on the pages, its text with fields, size, lines, white box, font,
// bold and italic, and Delete note. The engine makes each change
// (publish_set_note), joining a run of them on one note into one undo step,
// as typing; a font name it cannot use is refused and said.
import type { LayoutDocument } from '../document/layoutDocument.ts';
import { EngineError } from '../engine/engine.ts';
import { booleanField, numberField, stringField, type JsonRecord } from '../engine/replies.ts';
import { LatestOnly } from '../ui/latestOnly.ts';
import type { SideTabContent } from '../ui/sideTabs.ts';
import { STRINGS } from '../ui/strings.ts';

export interface NotesTabEvents {
  // Add note made this note, to be chosen on the pages
  added(note: number): void;
  deleted(): void;
  message(text: string): void;
  failed(error: unknown): void;
}

// As the desktop's spin edit, in points
const MAX_NOTE_SIZE = 200;
const ALIGNS: [string, string][] = [
  ['left', STRINGS.noteAlignLeft],
  ['centre', STRINGS.noteAlignCentre],
  ['right', STRINGS.noteAlignRight],
];

type Settings = Record<string, string | number | boolean>;

function labelled(caption: string, control: HTMLElement): HTMLLabelElement {
  const made = document.createElement('label');
  made.className = 'notes-row';
  const text = document.createElement('span');
  text.textContent = caption;
  made.append(text, control);
  return made;
}

function check(caption: string, box: HTMLInputElement): HTMLLabelElement {
  box.type = 'checkbox';
  const made = document.createElement('label');
  made.className = 'notes-check';
  made.append(box, caption);
  return made;
}

export class NotesTab implements SideTabContent {
  readonly element: HTMLElement;
  private readonly document: LayoutDocument;
  private readonly events: NotesTabEvents;
  private readonly text: HTMLTextAreaElement;
  private readonly size: HTMLInputElement;
  private readonly align: HTMLSelectElement;
  private readonly boxed = document.createElement('input');
  private readonly font: HTMLInputElement;
  private readonly bold = document.createElement('input');
  private readonly italic = document.createElement('input');
  private readonly deleteButton: HTMLButtonElement;
  private readonly reads: LatestOnly<number>;
  // Typing sends the newest text once the one before is answered
  private readonly typing: LatestOnly<Settings>;
  private readonly listener = (): void => {
    this.reads.push(this.note);
  };
  private note = -1;
  // Add note asked for the text, which can take focus once the note shows
  private focusWhenShown = false;

  constructor(layoutDocument: LayoutDocument, events: NotesTabEvents) {
    this.document = layoutDocument;
    this.events = events;
    this.element = document.createElement('div');
    this.element.className = 'notes';
    const fail = (error: unknown): void => {
      events.failed(error);
    };
    this.reads = new LatestOnly(async (note) => this.load(note), fail);
    this.typing = new LatestOnly(async (settings) => this.send(settings), fail);
    const add = document.createElement('button');
    add.type = 'button';
    add.textContent = STRINGS.addNote;
    add.addEventListener('click', () => {
      this.run(this.add());
    });
    const choose = document.createElement('p');
    choose.className = 'notes-help';
    choose.textContent = STRINGS.chooseNote;
    this.text = document.createElement('textarea');
    this.text.name = 'text';
    this.text.rows = 4;
    this.text.spellcheck = false;
    this.text.addEventListener('input', () => {
      this.typing.push({ text: this.text.value });
    });
    const help = document.createElement('p');
    help.className = 'notes-help';
    help.textContent = STRINGS.noteHelp;
    this.size = document.createElement('input');
    this.size.type = 'number';
    this.size.name = 'size';
    this.size.min = '1';
    this.size.max = String(MAX_NOTE_SIZE);
    this.size.step = '1';
    this.size.addEventListener('change', () => {
      if (!Number.isNaN(this.size.valueAsNumber)) {
        this.set({ size: this.size.valueAsNumber });
      }
    });
    this.align = document.createElement('select');
    this.align.name = 'align';
    for (const [value, caption] of ALIGNS) {
      this.align.add(new Option(caption, value));
    }
    this.align.addEventListener('change', () => {
      this.set({ align: this.align.value });
    });
    this.boxed.name = 'boxed';
    this.boxed.addEventListener('change', () => {
      this.set({ boxed: this.boxed.checked });
    });
    this.font = document.createElement('input');
    this.font.type = 'text';
    this.font.name = 'font';
    this.font.autocomplete = 'off';
    this.font.spellcheck = false;
    this.font.placeholder = STRINGS.noteFontDefault;
    this.font.addEventListener('change', () => {
      this.set({ font: this.font.value });
    });
    this.bold.name = 'bold';
    this.bold.addEventListener('change', () => {
      this.set({ bold: this.bold.checked });
    });
    this.italic.name = 'italic';
    this.italic.addEventListener('change', () => {
      this.set({ italic: this.italic.checked });
    });
    this.deleteButton = document.createElement('button');
    this.deleteButton.type = 'button';
    this.deleteButton.textContent = STRINGS.deleteNote;
    this.deleteButton.addEventListener('click', () => {
      this.run(this.remove());
    });
    this.element.append(
      add,
      choose,
      labelled(STRINGS.sheetNote, this.text),
      help,
      labelled(STRINGS.noteSize, this.size),
      labelled(STRINGS.noteAlign, this.align),
      check(STRINGS.noteBox, this.boxed),
      labelled(STRINGS.noteFont, this.font),
      check(STRINGS.noteBold, this.bold),
      check(STRINGS.noteItalic, this.italic),
      this.deleteButton,
    );
    layoutDocument.addListener(this.listener);
    this.show(undefined);
  }

  // Filled on every change, shown or not, so it is ready when opened
  setShown(): void {
    // Nothing to catch up on
  }

  dispose(): void {
    this.document.removeListener(this.listener);
  }

  // The note chosen on the pages, or -1 for none
  choose(note: number): void {
    if (note !== this.note) {
      this.typing.clear();
      this.note = note;
      this.reads.push(note);
    }
  }

  // Ready to type over the new note's text, as on the desktop, once it shows
  focusText(): void {
    this.focusWhenShown = true;
  }

  private run(pending: Promise<void>): void {
    pending.catch((error: unknown) => {
      this.events.failed(error);
    });
  }

  private async add(): Promise<void> {
    const answer = await this.document.call('publish_add_note');
    this.events.added(numberField(answer, 'note') ?? -1);
  }

  private async remove(): Promise<void> {
    const note = this.note;
    if (note >= 0) {
      this.events.deleted();
      await this.document.call('publish_delete_note', { note });
    }
  }

  private set(settings: Settings): void {
    this.run(this.send(settings));
  }

  private async send(settings: Settings): Promise<void> {
    if (this.note < 0) {
      return;
    }
    try {
      await this.document.call('publish_set_note', { note: this.note, ...settings });
    } catch (error: unknown) {
      // Refused, as a font name that cannot be used: said, and put back
      if (!(error instanceof EngineError)) {
        throw error;
      }
      this.events.message(error.message);
      this.reads.push(this.note);
    }
  }

  private async load(note: number): Promise<void> {
    if (note < 0) {
      this.show(undefined);
      return;
    }
    const answer = await this.document.read('publish_note', { note }).catch(() => undefined);
    // Chosen again meanwhile, or gone, as after an undo
    if (note === this.note) {
      this.show(answer);
    }
  }

  // A control being typed in keeps what is typed
  private show(answer: JsonRecord | undefined): void {
    const chosen = answer !== undefined;
    for (const control of [this.text, this.size, this.align, this.boxed, this.font, this.bold, this.italic]) {
      control.disabled = !chosen;
    }
    this.deleteButton.disabled = !chosen;
    const typing = document.activeElement;
    if (answer === undefined) {
      this.text.value = '';
      return;
    }
    if (this.text !== typing) {
      this.text.value = stringField(answer, 'text') ?? '';
    }
    if (this.size !== typing) {
      this.size.value = String(numberField(answer, 'size') ?? 0);
    }
    if (this.font !== typing) {
      this.font.value = stringField(answer, 'font') ?? '';
    }
    this.align.value = stringField(answer, 'align') ?? 'left';
    this.boxed.checked = booleanField(answer, 'boxed') ?? false;
    this.bold.checked = booleanField(answer, 'bold') ?? false;
    this.italic.checked = booleanField(answer, 'italic') ?? false;
    if (this.focusWhenShown) {
      this.focusWhenShown = false;
      this.text.focus();
      this.text.select();
    }
  }
}
