// The Output tab of the Publish app's side panel, as the desktop builds it in
// Sloper.Publish.MainForm (BuildSide): what the layout prints on (tiled pages,
// a large format roll, a projector or a material sheet) with its sizes; the
// paper, margin, overlap and alignment marks of tiled pages; and what prints
// (fill, output profile, material). The engine says which settings apply to
// the kind of output (publish_output), and makes each change as the
// desktop's tab does (publish_set_output), refusing one that leaves nothing
// to print on. The machine profile is left out: it is only for Machine DXF,
// which stays a desktop export.
import { EngineError } from '../engine/engine.ts';
import { booleanField, isRecord, numberField, stringField, stringsField, type JsonRecord } from '../engine/replies.ts';
import type { LayoutDocument } from '../document/layoutDocument.ts';
import { LatestOnly } from '../ui/latestOnly.ts';
import type { SideTabContent } from '../ui/sideTabs.ts';
import { STRINGS } from '../ui/strings.ts';

export interface OutputTabEvents {
  // A setting changed, so the pages want fitting again
  changed(): void;
  message(text: string): void;
  export(format: number): void;
  print(): void;
  failed(error: unknown): void;
}

// The engine's names, in the desktop's order, with their captions
const KINDS: [string, string][] = [
  ['tiled', STRINGS.outputTiled],
  ['large', STRINGS.outputLarge],
  ['projector', STRINGS.outputProjector],
  ['material', STRINGS.outputMaterial],
];
const MARKS: [string, string][] = [
  ['diamond', STRINGS.marksDiamond],
  ['none', STRINGS.marksNone],
  ['halfCircle', STRINGS.marksHalfCircle],
];
const FILLS: [string, string][] = [
  ['none', STRINGS.fillNone],
  ['tint', STRINGS.fillTint],
  ['hatch', STRINGS.fillHatch],
];
// The paper whose size is typed in
const CUSTOM_PAPER = 'custom';
// As the desktop's spin edits
const MAX_ROLL_WIDTH = 2000;
const MAX_PAPER_SIDE = 2000;
const MAX_MILLIMETRES = 100;

type NumberKey = 'rollWidth' | 'materialWidth' | 'materialLength' | 'paperWidth' | 'paperHeight' | 'margin' | 'overlap';
type ChoiceKey = 'kind' | 'paper' | 'marks' | 'fill' | 'outputProfile' | 'material';

function group(caption: string): HTMLFieldSetElement {
  const made = document.createElement('fieldset');
  made.className = 'output-group';
  const legend = document.createElement('legend');
  legend.textContent = caption;
  made.append(legend);
  return made;
}

function row(caption: string, control: HTMLElement): HTMLLabelElement {
  const made = document.createElement('label');
  made.className = 'output-row';
  const text = document.createElement('span');
  text.textContent = caption;
  made.append(text, control);
  return made;
}

function fillChoices(select: HTMLSelectElement, choices: [string, string][]): void {
  const key = JSON.stringify(choices);
  if (select.dataset.choices === key) {
    return;
  }
  select.dataset.choices = key;
  select.replaceChildren(
    ...choices.map(([value, caption]) => {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = caption;
      return option;
    }),
  );
}

function enable(element: HTMLInputElement | HTMLSelectElement | undefined, on: boolean): void {
  if (element !== undefined) {
    element.disabled = !on;
  }
}

export class OutputTab implements SideTabContent {
  readonly element: HTMLElement;
  private readonly document: LayoutDocument;
  private readonly events: OutputTabEvents;
  private readonly numbers = new Map<NumberKey, HTMLInputElement>();
  private readonly choices = new Map<ChoiceKey, HTMLSelectElement>();
  private readonly allowTurns: HTMLInputElement;
  private readonly exportButtons: HTMLButtonElement[] = [];
  private readonly reads: LatestOnly<number>;
  private readonly listener = (): void => {
    this.reads.push(0);
  };

  constructor(layoutDocument: LayoutDocument, events: OutputTabEvents) {
    this.document = layoutDocument;
    this.events = events;
    this.element = document.createElement('div');
    this.element.className = 'output';
    this.reads = new LatestOnly(
      async () => this.load(),
      (error) => {
        events.failed(error);
      },
    );
    const output = group(STRINGS.outputGroup);
    output.append(
      this.choice('kind', ''),
      this.number('rollWidth', STRINGS.rollWidth, MAX_ROLL_WIDTH, 1),
      this.number('materialWidth', STRINGS.materialWidth, MAX_ROLL_WIDTH, 1),
      this.number('materialLength', STRINGS.materialLength, MAX_ROLL_WIDTH, 1),
    );
    this.allowTurns = document.createElement('input');
    this.allowTurns.type = 'checkbox';
    this.allowTurns.addEventListener('change', () => {
      this.set({ allowTurns: this.allowTurns.checked });
    });
    const turns = document.createElement('label');
    turns.className = 'output-check';
    turns.append(this.allowTurns, STRINGS.allowTurns);
    output.append(turns);
    const paper = group(STRINGS.paperGroup);
    paper.append(
      this.choice('paper', ''),
      this.number('paperWidth', STRINGS.paperWidth, MAX_PAPER_SIDE, 0.1),
      this.number('paperHeight', STRINGS.paperHeight, MAX_PAPER_SIDE, 0.1),
      this.number('margin', STRINGS.margin, MAX_MILLIMETRES, 0.1),
      this.number('overlap', STRINGS.overlap, MAX_MILLIMETRES, 0.1),
      this.choice('marks', STRINGS.marks),
    );
    const content = group(STRINGS.contentGroup);
    content.append(
      this.choice('fill', STRINGS.fill),
      this.choice('outputProfile', STRINGS.outputProfile),
      this.choice('material', STRINGS.materialLimit),
    );
    const exports = group(STRINGS.exportGroup);
    const print = document.createElement('button');
    print.type = 'button';
    print.textContent = STRINGS.print;
    print.addEventListener('click', () => {
      events.print();
    });
    this.exportButtons.push(print);
    exports.append(print);
    for (const [index, caption] of [STRINGS.exportPdf, STRINGS.exportSvg, STRINGS.exportDxf].entries()) {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = caption;
      button.addEventListener('click', () => {
        events.export(index);
      });
      this.exportButtons.push(button);
      exports.append(button);
    }
    this.element.append(output, paper, content, exports);
    fillChoices(this.select('kind'), KINDS);
    fillChoices(this.select('marks'), MARKS);
    fillChoices(this.select('fill'), FILLS);
    layoutDocument.addListener(this.listener);
  }

  // Filled on every change, shown or not, so it is ready when opened
  setShown(): void {
    // Nothing to catch up on
  }

  dispose(): void {
    this.document.removeListener(this.listener);
  }

  // Print and the exports are refused while a problem stops printing, as on the toolbar
  setExportsEnabled(enabled: boolean): void {
    for (const button of this.exportButtons) {
      button.disabled = !enabled;
    }
  }

  private select(key: ChoiceKey): HTMLSelectElement {
    const found = this.choices.get(key);
    if (found === undefined) {
      throw new Error(`no ${key} choice`);
    }
    return found;
  }

  private number(key: NumberKey, caption: string, max: number, step: number): HTMLLabelElement {
    const input = document.createElement('input');
    input.type = 'number';
    input.name = key;
    input.min = '0';
    input.max = String(max);
    input.step = String(step);
    // Sent once typed or stepped, so 400 does not pass through 4
    input.addEventListener('change', () => {
      const value = input.valueAsNumber;
      if (Number.isNaN(value)) {
        this.reads.push(0);
        return;
      }
      if (key === 'paperWidth' || key === 'paperHeight') {
        this.set({ paper: CUSTOM_PAPER, [key]: value });
      } else {
        this.set({ [key]: value });
      }
    });
    this.numbers.set(key, input);
    return row(caption, input);
  }

  private choice(key: ChoiceKey, caption: string): HTMLElement {
    const select = document.createElement('select');
    select.name = key;
    select.addEventListener('change', () => {
      this.set({ [key]: select.value });
    });
    this.choices.set(key, select);
    if (caption === '') {
      select.setAttribute('aria-label', key === 'kind' ? STRINGS.outputGroup : STRINGS.paperGroup);
      select.className = 'output-wide';
      return select;
    }
    return row(caption, select);
  }

  private set(params: Record<string, string | number | boolean>): void {
    const change = async (): Promise<void> => {
      try {
        await this.document.call('publish_set_output', params);
        this.events.changed();
      } catch (error: unknown) {
        // Refused, as when nothing is left to print on: said, and put back
        if (!(error instanceof EngineError)) {
          throw error;
        }
        this.events.message(error.message);
        this.reads.push(0);
      }
    };
    change().catch((error: unknown) => {
      this.events.failed(error);
    });
  }

  private async load(): Promise<void> {
    this.show(await this.document.read('publish_output'));
  }

  // A control being typed in keeps what is typed
  private show(answer: JsonRecord): void {
    const typing = document.activeElement;
    const used = isRecord(answer.used) ? answer.used : {};
    const isUsed = (name: string): boolean => booleanField(used, name) ?? true;
    for (const [key, input] of this.numbers) {
      if (input !== typing) {
        input.value = String(numberField(answer, key) ?? 0);
      }
    }
    fillChoices(
      this.select('paper'),
      (stringsField(answer, 'papers') ?? []).map((name) => [name, name === CUSTOM_PAPER ? STRINGS.paperCustom : name]),
    );
    fillChoices(this.select('outputProfile'), [
      ['', STRINGS.outputProfileAll],
      ...(stringsField(answer, 'outputProfiles') ?? []).map((name): [string, string] => [name, name]),
    ]);
    fillChoices(this.select('material'), [
      ['', STRINGS.materialAll],
      ...(stringsField(answer, 'materials') ?? []).map((name): [string, string] => [name, name]),
    ]);
    for (const [key, select] of this.choices) {
      select.value = stringField(answer, key) ?? '';
    }
    this.allowTurns.checked = booleanField(answer, 'allowTurns') ?? false;
    enable(this.numbers.get('rollWidth'), isUsed('rollWidth'));
    enable(this.numbers.get('materialWidth'), isUsed('materialSize'));
    enable(this.numbers.get('materialLength'), isUsed('materialSize'));
    enable(this.allowTurns, isUsed('allowTurns'));
    enable(this.choices.get('paper'), isUsed('paper'));
    enable(this.numbers.get('paperWidth'), isUsed('paperSize'));
    enable(this.numbers.get('paperHeight'), isUsed('paperSize'));
    enable(this.numbers.get('overlap'), isUsed('overlap'));
    enable(this.choices.get('marks'), isUsed('marks'));
    enable(this.choices.get('fill'), isUsed('fill'));
  }
}
