// The formula suggestions under a Properties row, as Sloper.UI.FormulaSuggest:
// formulas that give about the field's value (editor_suggest), the best
// first, each with its value and how far off it is, and with a size table
// its values at the first and last sizes on a second line. When none is
// close, a line says so above the nearest. The field keeps the keyboard and
// passes the list Up, Down and Enter while it shows. The objects the rows in
// view read are passed on, for the canvas to label.
import {
  idsField,
  isRecord,
  numberField,
  recordsField,
  stringField,
  stringsField,
  type JsonRecord,
} from '../engine/replies.ts';
import { STRINGS } from './strings.ts';

export interface Suggestion {
  text: string;
  // As the field takes it: mm, degrees or a ratio
  value: number;
  valueText: string;
  deltaText: string;
  // Its values at the first and last sizes, and at every size, in words
  range: string;
  sizeValues: string;
  // The IDs of the objects it reads
  objects: string[];
}

export interface FormulaSuggestEvents {
  choose(suggestion: Suggestion): void;
  // The row under the pointer or chosen by key, or undefined for none
  hover(suggestion: Suggestion | undefined): void;
  // The IDs of the objects the rows in view read, as they are shown or scrolled
  view(ids: string[]): void;
}

function parseSuggestion(item: JsonRecord): Suggestion {
  return {
    text: stringField(item, 'text') ?? '',
    value: numberField(item, 'value') ?? 0,
    valueText: stringField(item, 'valueText') ?? '',
    deltaText: stringField(item, 'deltaText') ?? '',
    range: stringField(item, 'range') ?? '',
    sizeValues: stringField(item, 'sizeValues') ?? '',
    objects: idsField(item, 'objects'),
  };
}

export class FormulaSuggestList {
  readonly element: HTMLElement;
  private readonly events: FormulaSuggestEvents;
  // The rows' suggestions; undefined for the line saying nothing is close
  private rows: (Suggestion | undefined)[] = [];
  private chosen = -1;
  private hovered: Suggestion | undefined;
  private viewIds = '';

  constructor(events: FormulaSuggestEvents) {
    this.events = events;
    this.element = window.document.createElement('ul');
    this.element.className = 'suggest-list';
    this.element.setAttribute('role', 'listbox');
    // A press on a row must leave the focus in the field
    this.element.addEventListener('mousedown', (event) => {
      event.preventDefault();
      const suggestion = this.rowAt(event.target);
      if (suggestion !== undefined) {
        this.events.choose(suggestion);
      }
    });
    this.element.addEventListener('mousemove', (event) => {
      this.setHover(this.rowAt(event.target));
    });
    this.element.addEventListener('mouseleave', () => {
      this.setHover(this.chosenRow());
    });
    this.element.addEventListener('scroll', () => {
      this.checkView();
    });
  }

  // Shows editor_suggest's answer; the row chosen stays chosen while its formula is still there
  show(answer: JsonRecord): void {
    const wasChosen = this.chosenRow()?.text;
    const items = recordsField(answer, 'items').map(parseSuggestion);
    const nearest = answer.nearest;
    const sizes = stringsField(answer, 'sizes') ?? [];
    this.rows = items;
    if (items.length === 0 && isRecord(nearest)) {
      this.rows = [undefined, parseSuggestion(nearest)];
    }
    const tolerance = stringField(answer, 'tolerance') ?? '';
    this.element.replaceChildren(
      ...this.rows.map((suggestion, index) => this.makeRow(suggestion, index, tolerance, sizes)),
    );
    const again = this.rows.findIndex((row) => row !== undefined && row.text === wasChosen);
    this.choose(again);
    this.checkView();
  }

  // The rows at least partly in view; a list not on the page has none
  private checkView(): void {
    const box = this.element.getBoundingClientRect();
    const ids = new Set<string>();
    for (const [index, line] of [...this.element.children].entries()) {
      const rect = line.getBoundingClientRect();
      if (rect.bottom > box.top && rect.top < box.bottom) {
        for (const id of this.rows[index]?.objects ?? []) {
          ids.add(id);
        }
      }
    }
    const key = [...ids].join(' ');
    if (key !== this.viewIds) {
      this.viewIds = key;
      this.events.view([...ids]);
    }
  }

  chosenRow(): Suggestion | undefined {
    return this.rows[this.chosen];
  }

  // True when the list used the key: Up and Down choose a row, Enter takes the one chosen
  handleKey(event: KeyboardEvent): boolean {
    switch (event.key) {
      case 'ArrowUp':
        this.step(-1);
        break;
      case 'ArrowDown':
        this.step(1);
        break;
      case 'Enter': {
        const suggestion = this.chosenRow();
        if (suggestion === undefined || event.ctrlKey) {
          return false;
        }
        this.events.choose(suggestion);
        break;
      }
      default:
        return false;
    }
    event.preventDefault();
    return true;
  }

  private makeRow(suggestion: Suggestion | undefined, index: number, tolerance: string, sizes: string[]): HTMLElement {
    const line = window.document.createElement('li');
    line.dataset.index = String(index);
    if (suggestion === undefined) {
      line.className = 'suggest-none';
      line.textContent = STRINGS.suggestNone(tolerance);
      return line;
    }
    line.setAttribute('role', 'option');
    const formula = window.document.createElement('span');
    formula.className = 'suggest-formula';
    formula.textContent = suggestion.text;
    const value = window.document.createElement('span');
    value.className = 'suggest-value';
    value.textContent = suggestion.valueText;
    const delta = window.document.createElement('span');
    delta.className = 'suggest-delta';
    delta.textContent = suggestion.deltaText;
    line.append(formula, value, delta);
    // The tooltip gives the formula in full, and the row's value at every size
    line.title = [suggestion.text, suggestion.sizeValues].filter((part) => part !== '').join('\n');
    const [first, last] = [sizes[0], sizes.at(-1)];
    if (first !== undefined && last !== undefined) {
      const range = window.document.createElement('span');
      range.className = 'suggest-range';
      range.textContent = STRINGS.suggestSizeRange(
        first,
        last,
        suggestion.range === '' ? STRINGS.suggestNoValue : suggestion.range,
      );
      line.append(range);
    }
    return line;
  }

  private rowAt(target: EventTarget | null): Suggestion | undefined {
    const line = target instanceof Element ? target.closest('li') : null;
    return line === null ? undefined : this.rows[Number(line.dataset.index)];
  }

  // Skips the line saying nothing is close
  private step(by: number): void {
    let index = this.chosen;
    do {
      index += by;
    } while (index >= 0 && index < this.rows.length && this.rows[index] === undefined);
    if (index >= 0 && index < this.rows.length) {
      this.choose(index);
      this.setHover(this.chosenRow());
    }
  }

  private choose(index: number): void {
    this.chosen = index;
    for (const [at, line] of [...this.element.children].entries()) {
      line.classList.toggle('chosen', at === index);
      line.setAttribute('aria-selected', String(at === index));
    }
    this.element.children[index]?.scrollIntoView({ block: 'nearest' });
  }

  private setHover(suggestion: Suggestion | undefined): void {
    if (suggestion === this.hovered) {
      return;
    }
    this.hovered = suggestion;
    this.events.hover(suggestion);
  }
}
