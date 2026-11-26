// The Patterns tab of the Publish app's side panel, as the desktop builds it
// in Sloper.Publish.MainForm (BuildPatternsTab): the patterns in the layout,
// with Add pattern… and Remove pattern; and for the one chosen, its
// measurement file, Choose measurements…, Use the pattern's own, and its
// size. The browser has no disk, so the files are chosen with the browser's
// file picker and given to the engine as text, found by name as Open finds
// them. The engine makes each change (publish_ methods), one undo step.
import type { LayoutDocument } from '../document/layoutDocument.ts';
import { booleanField, numberField, recordsField, stringField, stringsField } from '../engine/replies.ts';
import { LatestOnly } from '../ui/latestOnly.ts';
import type { SideTabContent } from '../ui/sideTabs.ts';
import { STRINGS } from '../ui/strings.ts';

export interface PatternsTabEvents {
  message(text: string): void;
  failed(error: unknown): void;
}

interface ListedPattern {
  id: number;
  caption: string;
  // The measurement file in use, '' for none
  measurements: string;
  // The layout chose the file, rather than the pattern naming it
  ownSet: boolean;
  size: string;
  sizes: string[];
  problem: string;
}

const PATTERN_FILES = '.sloper,.slm';
const MEASUREMENT_FILES = '.slm';

function group(caption: string): HTMLFieldSetElement {
  const made = document.createElement('fieldset');
  made.className = 'patterns-group';
  const legend = document.createElement('legend');
  legend.textContent = caption;
  made.append(legend);
  return made;
}

function button(caption: string, action: () => void): HTMLButtonElement {
  const made = document.createElement('button');
  made.type = 'button';
  made.textContent = caption;
  made.addEventListener('click', action);
  return made;
}

// A hidden picker, which a button opens
function picker(accept: string, multiple: boolean, chosen: (files: File[]) => void): HTMLInputElement {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = accept;
  input.multiple = multiple;
  input.hidden = true;
  input.addEventListener('change', () => {
    chosen([...(input.files ?? [])]);
    input.value = '';
  });
  return input;
}

async function texts(files: File[]): Promise<Map<string, string>> {
  const read = await Promise.all(files.map(async (file): Promise<[string, string]> => [file.name, await file.text()]));
  return new Map(read);
}

export class PatternsTab implements SideTabContent {
  readonly element: HTMLElement;
  private readonly document: LayoutDocument;
  private readonly events: PatternsTabEvents;
  private readonly list: HTMLUListElement;
  private readonly removeButton: HTMLButtonElement;
  private readonly setName: HTMLElement;
  private readonly chooseSetButton: HTMLButtonElement;
  private readonly ownSetButton: HTMLButtonElement;
  private readonly sizeBox: HTMLSelectElement;
  private readonly addPicker: HTMLInputElement;
  private readonly setPicker: HTMLInputElement;
  private readonly reads: LatestOnly<number>;
  private readonly listener = (): void => {
    this.reads.push(0);
  };
  private patterns: ListedPattern[] = [];
  private chosen = 0;

  constructor(layoutDocument: LayoutDocument, events: PatternsTabEvents) {
    this.document = layoutDocument;
    this.events = events;
    this.element = document.createElement('div');
    this.element.className = 'patterns';
    this.reads = new LatestOnly(
      async () => this.load(),
      (error) => {
        events.failed(error);
      },
    );
    this.addPicker = picker(PATTERN_FILES, true, (files) => {
      this.run(this.add(files));
    });
    this.setPicker = picker(MEASUREMENT_FILES, false, (files) => {
      this.run(this.chooseSet(files));
    });
    const patterns = group(STRINGS.patternsGroup);
    this.list = document.createElement('ul');
    this.list.className = 'patterns-list';
    this.list.setAttribute('role', 'listbox');
    this.list.setAttribute('aria-label', STRINGS.patternsGroup);
    this.list.tabIndex = 0;
    this.list.addEventListener('click', (event) => {
      const item = event.target instanceof Element ? event.target.closest('li') : null;
      if (item?.dataset.index !== undefined) {
        this.choose(Number(item.dataset.index));
      }
    });
    this.list.addEventListener('keydown', (event) => {
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        this.choose(this.chosen + (event.key === 'ArrowDown' ? 1 : -1));
        event.preventDefault();
      }
    });
    this.removeButton = button(STRINGS.removePattern, () => {
      this.run(this.remove());
    });
    const buttons = document.createElement('div');
    buttons.className = 'patterns-buttons';
    buttons.append(
      button(STRINGS.addPattern, () => {
        this.addPicker.click();
      }),
      this.removeButton,
    );
    patterns.append(this.list, buttons, this.addPicker);
    const set = group(STRINGS.sourceSet);
    this.setName = document.createElement('div');
    this.setName.className = 'patterns-set';
    this.chooseSetButton = button(STRINGS.chooseSet, () => {
      this.setPicker.click();
    });
    this.ownSetButton = button(STRINGS.patternSet, () => {
      this.run(this.useOwnSet());
    });
    const setButtons = document.createElement('div');
    setButtons.className = 'patterns-buttons';
    setButtons.append(this.chooseSetButton, this.ownSetButton);
    this.sizeBox = document.createElement('select');
    this.sizeBox.name = 'size';
    this.sizeBox.addEventListener('change', () => {
      this.run(this.setSize(this.sizeBox.value));
    });
    const size = document.createElement('label');
    size.className = 'patterns-size';
    const sizeCaption = document.createElement('span');
    sizeCaption.textContent = STRINGS.sourceSize;
    size.append(sizeCaption, this.sizeBox);
    set.append(this.setName, setButtons, size, this.setPicker);
    this.element.append(patterns, set);
    layoutDocument.addListener(this.listener);
    this.show();
  }

  // Filled on every change, shown or not, so it is ready when opened
  setShown(): void {
    // Nothing to catch up on
  }

  dispose(): void {
    this.document.removeListener(this.listener);
  }

  private get current(): ListedPattern | undefined {
    return this.patterns[this.chosen];
  }

  private run(pending: Promise<void>): void {
    pending.catch((error: unknown) => {
      this.events.failed(error);
    });
  }

  private choose(index: number): void {
    if (index >= 0 && index < this.patterns.length) {
      this.chosen = index;
      this.show();
    }
  }

  // The patterns among the files chosen, each added with the others to read;
  // the new one is chosen, as on the desktop
  private async add(files: File[]): Promise<void> {
    const read = await texts(files);
    let added = 0;
    for (const file of files.filter((each) => each.name.toLowerCase().endsWith('.sloper'))) {
      // One step each, in the order chosen
      // oxlint-disable-next-line no-await-in-loop
      added += await this.document.addPattern(read, file.name);
    }
    this.chosen = Number.MAX_SAFE_INTEGER;
    this.show();
    this.events.message(STRINGS.sourceAdded(added));
  }

  private async remove(): Promise<void> {
    const pattern = this.current;
    if (pattern !== undefined) {
      await this.document.call('publish_remove_pattern', { source: pattern.id });
    }
  }

  private async chooseSet(files: File[]): Promise<void> {
    const pattern = this.current;
    const file = files[0];
    if (pattern !== undefined && file !== undefined) {
      await this.document.setMeasurements(pattern.id, await texts([file]), file.name);
    }
  }

  private async useOwnSet(): Promise<void> {
    const pattern = this.current;
    if (pattern !== undefined) {
      await this.document.setMeasurements(pattern.id, new Map(), '');
    }
  }

  private async setSize(size: string): Promise<void> {
    const pattern = this.current;
    if (pattern !== undefined && size !== '') {
      await this.document.call('publish_set_size', { source: pattern.id, size });
    }
  }

  private async load(): Promise<void> {
    const answer = await this.document.read('publish_patterns');
    this.patterns = recordsField(answer, 'patterns').map((item) => ({
      id: numberField(item, 'id') ?? 0,
      caption: stringField(item, 'caption') ?? '',
      measurements: stringField(item, 'measurements') ?? '',
      ownSet: booleanField(item, 'ownSet') ?? false,
      size: stringField(item, 'size') ?? '',
      sizes: stringsField(item, 'sizes') ?? [],
      problem: stringField(item, 'problem') ?? '',
    }));
    this.show();
  }

  private show(): void {
    this.chosen = Math.max(0, Math.min(this.chosen, this.patterns.length - 1));
    this.list.replaceChildren(
      ...this.patterns.map((pattern, index) => {
        const item = document.createElement('li');
        item.textContent = pattern.caption;
        item.setAttribute('role', 'option');
        item.dataset.index = String(index);
        const chosen = index === this.chosen;
        item.classList.toggle('chosen', chosen);
        item.setAttribute('aria-selected', String(chosen));
        if (pattern.problem !== '') {
          item.classList.add('has-problem');
          item.title = pattern.problem;
        }
        return item;
      }),
    );
    const pattern = this.current;
    this.removeButton.disabled = pattern === undefined;
    this.chooseSetButton.disabled = pattern === undefined;
    this.ownSetButton.disabled = pattern?.ownSet !== true;
    this.setName.textContent =
      pattern === undefined || pattern.measurements === '' ? STRINGS.noSet : pattern.measurements;
    const sizes = pattern?.sizes ?? [];
    this.sizeBox.replaceChildren(
      ...sizes.map((size) => {
        const option = document.createElement('option');
        option.value = size;
        option.textContent = size;
        return option;
      }),
    );
    this.sizeBox.value = pattern?.size ?? '';
    this.sizeBox.disabled = sizes.length === 0;
  }
}
