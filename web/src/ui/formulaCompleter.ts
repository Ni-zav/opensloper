// The list of suggestions under a formula field, as Sloper.UI.FormulaCompleter:
// the engine says what matches the word at the caret (editor_complete), and
// the list floats over the panels without taking the keyboard from the field,
// which passes it the keys while it shows.
import type { PatternDocument } from '../document/patternDocument.ts';
import { numberField, recordsField, stringField } from '../engine/replies.ts';
import { LatestOnly } from './latestOnly.ts';

const MAX_ROWS = 8;
const MIN_WIDTH = 220;

interface CompletionItem {
  name: string;
  insert: string;
  detail: string;
}

export class FormulaCompleter {
  private readonly document: PatternDocument;
  private readonly list: HTMLUListElement;
  private readonly updates: LatestOnly<boolean>;
  private field: HTMLInputElement | undefined;
  // The object or variable whose formula it is, by ID
  private target: number | undefined;
  private items: CompletionItem[] = [];
  private from = 0;
  private upto = 0;
  private chosen = 0;

  constructor(document: PatternDocument, fail: (error: unknown) => void) {
    this.document = document;
    this.list = window.document.createElement('ul');
    this.list.className = 'completer';
    this.list.hidden = true;
    this.list.setAttribute('role', 'listbox');
    // A press on an item must leave the focus in the field
    this.list.addEventListener('mousedown', (event) => {
      event.preventDefault();
      const item = event.target instanceof Element ? event.target.closest('li') : null;
      if (item !== null) {
        this.chosen = Number(item.dataset.index);
        this.accept();
      }
    });
    window.document.body.append(this.list);
    this.updates = new LatestOnly(async (explicit) => this.load(explicit), fail);
  }

  get visible(): boolean {
    return this.list.hidden !== true;
  }

  // Looks again at the text round the field's caret; hides when there is nothing to offer
  update(field: HTMLInputElement, target: number | undefined, explicit: boolean): void {
    this.field = field;
    this.target = target;
    this.updates.push(explicit);
  }

  hide(): void {
    this.updates.clear();
    this.list.hidden = true;
  }

  // True when the list used the key
  handleKey(event: KeyboardEvent): boolean {
    if (!this.visible) {
      return false;
    }
    switch (event.key) {
      case 'ArrowUp':
        this.choose(Math.max(this.chosen - 1, 0));
        break;
      case 'ArrowDown':
        this.choose(Math.min(this.chosen + 1, this.items.length - 1));
        break;
      case 'Enter':
      case 'Tab':
        this.accept();
        break;
      case 'Escape':
        this.hide();
        break;
      default:
        return false;
    }
    event.preventDefault();
    return true;
  }

  dispose(): void {
    this.list.remove();
  }

  private async load(explicit: boolean): Promise<void> {
    const field = this.field;
    if (field === undefined || !field.isConnected) {
      this.hide();
      return;
    }
    const params: Record<string, unknown> = {
      text: field.value,
      caret: field.selectionStart ?? field.value.length,
      explicit,
    };
    if (this.target !== undefined) {
      params.id = this.target;
    }
    const answer = await this.document.read('editor_complete', params);
    // The field may have closed while the engine worked
    if (!field.isConnected || field !== this.field) {
      return;
    }
    this.items = recordsField(answer, 'items').map((item) => ({
      name: stringField(item, 'name') ?? '',
      insert: stringField(item, 'insert') ?? '',
      detail: stringField(item, 'detail') ?? '',
    }));
    this.from = numberField(answer, 'from') ?? 0;
    this.upto = numberField(answer, 'upto') ?? 0;
    if (this.items.length === 0) {
      this.list.hidden = true;
      return;
    }
    this.list.replaceChildren(
      ...this.items.map((item, index) => {
        const line = window.document.createElement('li');
        line.dataset.index = String(index);
        line.setAttribute('role', 'option');
        line.textContent = item.name;
        if (item.detail !== '') {
          const detail = window.document.createElement('span');
          detail.textContent = item.detail;
          line.append(detail);
        }
        return line;
      }),
    );
    this.choose(0);
    this.place(field);
    this.list.hidden = false;
  }

  private choose(index: number): void {
    this.chosen = index;
    for (const [at, line] of [...this.list.children].entries()) {
      line.classList.toggle('chosen', at === index);
      line.setAttribute('aria-selected', String(at === index));
    }
    this.list.children[index]?.scrollIntoView({ block: 'nearest' });
  }

  // Under the field, or over it when the window has no room below
  private place(field: HTMLInputElement): void {
    const bounds = field.getBoundingClientRect();
    const width = Math.max(bounds.width, MIN_WIDTH);
    this.list.style.width = `${String(width)}px`;
    this.list.style.maxHeight = `${String(MAX_ROWS * 1.6)}em`;
    this.list.style.left = `${String(Math.max(0, Math.min(bounds.left, window.innerWidth - width)))}px`;
    this.list.style.top = `${String(bounds.bottom)}px`;
    this.list.hidden = false;
    const height = this.list.getBoundingClientRect().height;
    if (bounds.bottom + height > window.innerHeight) {
      this.list.style.top = `${String(Math.max(0, bounds.top - height))}px`;
    }
  }

  // Puts the chosen item in place of the word, as ApplyCompletion does
  private accept(): void {
    const field = this.field;
    const item = this.items[this.chosen];
    if (field === undefined || item === undefined) {
      return;
    }
    const text = field.value.slice(0, this.from) + item.insert + field.value.slice(this.upto);
    const caret = this.from + item.insert.length;
    this.hide();
    field.value = text;
    field.setSelectionRange(caret, caret);
    // After an object's dot its properties are next
    if (text[caret - 1] === '.') {
      this.update(field, this.target, false);
    }
  }
}
