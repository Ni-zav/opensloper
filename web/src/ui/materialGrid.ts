// The pattern's materials in a table, as Sloper.UI.MaterialGrid: each one's
// colour as a swatch (a tint, or hatching at its angle), name, fill,
// allowance and size, one row selected. The Materials tab and the Materials
// dialog both show it.
import { numberField, recordsField, stringField, type JsonRecord } from '../engine/replies.ts';
import { STRINGS } from './strings.ts';

// Between a swatch's hatching lines, in pixels
const HATCH_GAP = 6;

export interface MaterialRow {
  name: string;
  color: string;
  fill: string;
  fillCaption: string;
  allowance: string;
  size: string;
  hatchAngle: number;
}

export interface MaterialChoice {
  name: string;
  caption: string;
}

// The list as editor_materials gives it
export interface MaterialList {
  rows: MaterialRow[];
  cutList: string;
  unit: string;
  fills: MaterialChoice[];
  fabrics: MaterialChoice[];
}

function parseChoices(answer: JsonRecord, name: string): MaterialChoice[] {
  return recordsField(answer, name).map((choice) => ({
    name: stringField(choice, 'name') ?? '',
    caption: stringField(choice, 'caption') ?? '',
  }));
}

export function parseMaterials(answer: JsonRecord): MaterialList {
  return {
    rows: recordsField(answer, 'rows').map((row) => ({
      name: stringField(row, 'name') ?? '',
      color: stringField(row, 'color') ?? '#000000',
      fill: stringField(row, 'fill') ?? 'tint',
      fillCaption: stringField(row, 'fillCaption') ?? '',
      allowance: stringField(row, 'allowance') ?? '',
      size: stringField(row, 'size') ?? '',
      hatchAngle: numberField(row, 'hatchAngle') ?? 0,
    })),
    cutList: stringField(answer, 'cutList') ?? '',
    unit: stringField(answer, 'unit') ?? '',
    fills: parseChoices(answer, 'fills'),
    fabrics: parseChoices(answer, 'fabrics'),
  };
}

// A swatch's look: the colour, or hatching in it on white. The angle is
// anticlockwise from the right, as the model's are; CSS turns clockwise from
// the top and runs its stripes square to the gradient, so -angle lays them along it.
export function paintSwatch(swatch: HTMLElement, color: string, fill: string, hatchAngle: number): void {
  swatch.style.background =
    fill === 'hatch'
      ? `repeating-linear-gradient(${String(-hatchAngle)}deg, ${color} 0 1.5px, #fff 1.5px ${String(HATCH_GAP)}px)`
      : color;
}

export interface MaterialGridEvents {
  // Another row was chosen
  select(index: number): void;
  // A row was double-clicked or Enter pressed on it
  activate(index: number): void;
}

export class MaterialGrid {
  readonly element: HTMLElement;
  private readonly body: HTMLTableSectionElement;
  private readonly events: MaterialGridEvents;
  private chosen = -1;
  private count = 0;

  constructor(events: MaterialGridEvents) {
    this.events = events;
    const make = window.document.createElement.bind(window.document);
    this.element = make('div');
    this.element.className = 'material-grid';
    this.element.tabIndex = 0;
    const table = make('table');
    const head = table.createTHead().insertRow();
    for (const caption of [
      STRINGS.materialColour,
      STRINGS.materialName,
      STRINGS.materialFill,
      STRINGS.materialAllowance,
      STRINGS.materialSize,
    ]) {
      const cell = make('th');
      cell.textContent = caption;
      head.append(cell);
    }
    this.body = table.createTBody();
    this.body.addEventListener('mousedown', (event) => {
      const index = this.rowAt(event.target);
      if (index !== undefined) {
        this.choose(index);
      }
    });
    this.body.addEventListener('dblclick', (event) => {
      const index = this.rowAt(event.target);
      if (index !== undefined) {
        this.events.activate(index);
      }
    });
    this.element.addEventListener('keydown', (event) => {
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        this.choose(Math.max(0, Math.min(this.count - 1, this.chosen + (event.key === 'ArrowDown' ? 1 : -1))));
        event.preventDefault();
      } else if (event.key === 'Enter' && this.chosen >= 0) {
        this.events.activate(this.chosen);
        event.preventDefault();
      }
    });
    this.element.append(table);
  }

  get index(): number {
    return this.chosen;
  }

  // The rows again, keeping the one chosen where it still is
  show(rows: readonly MaterialRow[]): void {
    const make = window.document.createElement.bind(window.document);
    this.count = rows.length;
    this.body.replaceChildren(
      ...rows.map((row, index) => {
        const line = make('tr');
        line.dataset.index = String(index);
        line.dataset.name = row.name;
        const swatchCell = make('td');
        const swatch = make('span');
        swatch.className = 'material-swatch';
        paintSwatch(swatch, row.color, row.fill, row.hatchAngle);
        swatchCell.append(swatch);
        line.append(swatchCell);
        for (const text of [row.name, row.fillCaption, row.allowance, row.size]) {
          const cell = make('td');
          cell.textContent = text;
          line.append(cell);
        }
        return line;
      }),
    );
    this.paintChosen(Math.min(this.chosen, rows.length - 1));
  }

  // Chooses the row as the user would, telling the events
  choose(index: number): void {
    if (index === this.chosen) {
      return;
    }
    this.paintChosen(index);
    this.events.select(index);
  }

  // Marks the row without telling the events, as when the list is refilled
  paintChosen(index: number): void {
    this.chosen = index;
    for (const [at, line] of [...this.body.rows].entries()) {
      line.classList.toggle('selected', at === index);
    }
    this.body.rows[index]?.scrollIntoView({ block: 'nearest' });
  }

  private rowAt(target: EventTarget | null): number | undefined {
    const line = target instanceof Element ? target.closest('tr') : null;
    return line === null ? undefined : Number(line.dataset.index);
  }
}
