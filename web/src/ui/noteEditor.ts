// Typing a note's text on the canvas, over the note, as the desktop does in
// its properties' note text: opened when the Text or Callout tool adds a note
// or a note is double-clicked. Its text is as the user edits it, each draft
// value as {=formula} with names. Ctrl+Enter (Cmd+Enter on macOS) or leaving
// it keeps the text, as one undo step; Escape drops what was typed.
import type { PatternDocument } from '../document/patternDocument.ts';
import { EngineError } from '../engine/engine.ts';
import { stringField } from '../engine/replies.ts';
import type { Vec2 } from '../editor/view.ts';
import { isMac } from './shortcuts.ts';

// The smallest the text is typed at, in pixels, however far out the view is
const MIN_FONT_PIXELS = 12;

export class NoteEditor {
  private readonly host: HTMLElement;
  private readonly document: PatternDocument;
  private readonly showMessage: (text: string) => void;
  private field: HTMLTextAreaElement | undefined;
  private noteId = '';
  private original = '';

  // Host is the element the field is placed in, over the canvas
  constructor(host: HTMLElement, document: PatternDocument, showMessage: (text: string) => void) {
    this.host = host;
    this.document = document;
    this.showMessage = showMessage;
  }

  get editing(): boolean {
    return this.field !== undefined;
  }

  // Opens the note's text at a screen place, with its text at fontPixels
  async open(noteId: string, at: Vec2, fontPixels: number): Promise<void> {
    this.close();
    const answer = await this.document.read('get_object', { id: Number(noteId) });
    this.original = stringField(answer, 'text') ?? '';
    this.noteId = noteId;
    const field = document.createElement('textarea');
    field.className = 'note-editor';
    field.value = this.original;
    field.style.left = `${String(at.x)}px`;
    field.style.top = `${String(at.y)}px`;
    field.style.fontSize = `${String(Math.max(fontPixels, MIN_FONT_PIXELS))}px`;
    field.rows = Math.max(2, this.original.split('\n').length + 1);
    field.addEventListener('keydown', (event) => {
      this.keyDown(event);
    });
    field.addEventListener('blur', () => {
      this.commit().catch((error: unknown) => {
        this.report(error);
      });
    });
    this.field = field;
    this.host.append(field);
    field.focus();
    field.select();
  }

  // Drops the field without keeping what was typed
  close(): void {
    const field = this.field;
    this.field = undefined;
    field?.remove();
  }

  private keyDown(event: KeyboardEvent): void {
    // Keys typed here are the field's, not the canvas's
    event.stopPropagation();
    if (event.key === 'Escape') {
      event.preventDefault();
      this.close();
    } else if (event.key === 'Enter' && (isMac() ? event.metaKey : event.ctrlKey)) {
      event.preventDefault();
      this.field?.blur();
    }
  }

  // Keeps the text when it changed; a refusal leaves the field open, saying why
  private async commit(): Promise<void> {
    const field = this.field;
    if (field === undefined) {
      return;
    }
    if (field.value === this.original) {
      this.close();
      return;
    }
    try {
      await this.document.call('set_text', { id: Number(this.noteId), text: field.value });
      this.close();
    } catch (error: unknown) {
      if (!(error instanceof EngineError)) {
        throw error;
      }
      this.showMessage(error.message);
      field.focus();
    }
  }

  private report(error: unknown): void {
    this.showMessage(error instanceof Error ? error.message : String(error));
  }
}
