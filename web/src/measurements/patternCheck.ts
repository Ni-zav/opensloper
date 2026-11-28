// The measurements page's Pattern Check, as the desktop measurements window's:
// under the table while the set is checked against a pattern, it says whether
// the pattern has everything it needs, and lists what the set cannot give it:
// a key the set lacks, or a size with no value. Add or go to it, or a
// double-click, adds the key, or goes to the empty value.
import type { MeasurementDocument, MissingMeasurement } from '../document/measurementDocument.ts';
import { STRINGS } from '../ui/strings.ts';

export interface PatternCheckEvents {
  // A missing measurement was chosen in the list, for its details to show
  chosen(key: string): void;
  // Add or go to it, for the page to do
  fix(item: MissingMeasurement): void;
}

export class PatternCheck {
  readonly element: HTMLFieldSetElement;
  private readonly document: MeasurementDocument;
  private readonly events: PatternCheckEvents;
  private readonly summary: HTMLElement;
  private readonly list: HTMLSelectElement;
  private readonly fixButton: HTMLButtonElement;
  private listed: MissingMeasurement[] = [];

  constructor(document: MeasurementDocument, events: PatternCheckEvents) {
    this.document = document;
    this.events = events;
    this.element = window.document.createElement('fieldset');
    this.element.className = 'pattern-check';
    this.element.hidden = true;
    const legend = window.document.createElement('legend');
    legend.textContent = STRINGS.missingTitle;
    this.summary = window.document.createElement('div');
    this.summary.className = 'pattern-check-summary';
    this.list = window.document.createElement('select');
    this.list.size = 5;
    this.list.setAttribute('aria-label', STRINGS.missingTitle);
    this.fixButton = window.document.createElement('button');
    this.fixButton.type = 'button';
    this.fixButton.textContent = STRINGS.missingFix;
    this.fixButton.title = STRINGS.missingFixHint;
    this.fixButton.disabled = true;
    const body = window.document.createElement('div');
    body.className = 'pattern-check-body';
    body.append(this.list, this.fixButton);
    this.element.append(legend, this.summary, body);
    this.list.addEventListener('change', () => {
      this.fixButton.disabled = this.chosen === undefined;
      const item = this.chosen;
      if (item !== undefined) {
        this.events.chosen(item.key);
      }
    });
    this.list.addEventListener('dblclick', () => {
      this.fixChosen();
    });
    this.list.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        this.fixChosen();
      }
    });
    this.fixButton.addEventListener('click', () => {
      this.fixChosen();
    });
  }

  // Shows only while the set is checked against a pattern
  refresh(): void {
    const { pattern, missing } = this.document.state;
    this.element.hidden = pattern === '';
    if (pattern === '') {
      return;
    }
    this.summary.textContent = missing.length === 0 ? STRINGS.missingNone(pattern) : STRINGS.missingSome(pattern);
    const chosen = this.chosen;
    this.listed = missing;
    this.list.replaceChildren(
      ...missing.map(
        (item) =>
          new Option(
            item.sizes.length === 0 ? STRINGS.missingKey(item.key) : STRINGS.missingSizes(item.key, item.sizes),
            item.key,
            false,
            item.key === chosen?.key && item.sizes.join() === chosen.sizes.join(),
          ),
      ),
    );
    this.fixButton.disabled = this.chosen === undefined;
  }

  private get chosen(): MissingMeasurement | undefined {
    return this.list.selectedIndex < 0 ? undefined : this.listed[this.list.selectedIndex];
  }

  private fixChosen(): void {
    const item = this.chosen;
    if (item !== undefined) {
      this.events.fix(item);
    }
  }
}
