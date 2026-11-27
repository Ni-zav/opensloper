// The measurements page's table, as the desktop measurements window's grid:
// a row a measurement, with its key, a value column a size (or one Value
// column for a set without sizes) and its description. Every cell is edited
// in the grid, each edit one undo step; a refused one stays red with the
// reason, as on the desktop. The rows come from the document's state, which
// the engine gives with the values already in the unit chosen; the page
// tells the grid to build them again when the set or the unit changes.
import type { MeasurementColumn, MeasurementDocument } from '../document/measurementDocument.ts';
import {
  ListPanel,
  type CellCommit,
  type ListColumn,
  type ListPanelEvents,
  type ListPanelRow,
} from '../ui/listPanel.ts';
import { STRINGS } from '../ui/strings.ts';

// CSS pixels, as the desktop's column widths
const KEY_WIDTH = 190;
const VALUE_WIDTH = 80;
const DESCRIPTION_WIDTH = 320;
const KEY_COLUMN = 0;

export interface MeasurementGridEvents extends ListPanelEvents {
  // Delete was pressed in the grid, for the page to ask and delete
  delete(): void;
}

export class MeasurementGrid extends ListPanel<MeasurementDocument> {
  private readonly gridEvents: MeasurementGridEvents;
  private sizes: readonly string[] = [];
  private columnCount = 0;

  constructor(document: MeasurementDocument, events: MeasurementGridEvents) {
    super(document, events, []);
    this.gridEvents = events;
    // There is no search, as on the desktop
    this.header.hidden = true;
    this.useColumns([]);
    this.setShown(true);
  }

  // The measurement chosen, or undefined
  get chosenKey(): string | undefined {
    return this.selection[0];
  }

  // The set or the unit changed: the columns follow its sizes
  showSet(): void {
    const sizes = this.document.state.sizes;
    if (
      this.columnCount === 0 ||
      sizes.length !== this.sizes.length ||
      sizes.some((size, i) => size !== this.sizes[i])
    ) {
      this.useColumns(sizes);
    }
    this.refresh();
  }

  // Chooses the measurement and opens its key to type, as after Add
  async editKey(key: string): Promise<void> {
    await this.rowsLoaded();
    this.focusCell(key, KEY_COLUMN, true);
  }

  protected async buildRows(): Promise<ListPanelRow[]> {
    return Promise.resolve(
      this.document.state.rows.map((row) => ({
        key: row.key,
        cells: [row.key, ...row.values, row.description],
        state: 'valid',
      })),
    );
  }

  protected override async commitCell(key: string, column: number, text: string): Promise<CellCommit> {
    const [kind, size] = this.cellOf(column);
    const result = await this.document.setCell(key, kind, size, text);
    // As the desktop says, since patterns name measurements by their keys
    if (result.done && result.key !== key) {
      this.events.message(STRINGS.measureRenamed(result.key, key));
    }
    return result;
  }

  protected override deleteRequested(): void {
    this.gridEvents.delete();
  }

  private useColumns(sizes: readonly string[]): void {
    this.sizes = [...sizes];
    const values = sizes.length === 0 ? [STRINGS.measureColumnValue] : sizes;
    const columns: ListColumn[] = [
      { caption: STRINGS.measureColumnKey, width: KEY_WIDTH },
      ...values.map((caption) => ({ caption, width: VALUE_WIDTH })),
      { caption: STRINGS.measureColumnDescription, width: DESCRIPTION_WIDTH },
    ];
    this.columnCount = columns.length;
    this.setColumns(columns);
    this.setEditableColumns(
      columns.map(() => true),
      columns.map(() => false),
    );
  }

  // The cell a column holds: the key, a size's value or the description
  private cellOf(column: number): [MeasurementColumn, number] {
    if (column === KEY_COLUMN) {
      return ['key', 0];
    }
    if (column === this.columnCount - 1) {
      return ['description', 0];
    }
    return ['value', column - 1];
  }
}
