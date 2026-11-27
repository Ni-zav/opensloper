// The measurements page's table, as the desktop measurements window's grid:
// a row a measurement, with its key, a value column a size (or one Value
// column for a set without sizes) and its description. It is read only for
// now. The rows come from the document's state, which the engine gives with
// the values already in the unit chosen; the page tells the grid to build
// them again when the set or the unit changes.
import type { MeasurementDocument } from '../document/measurementDocument.ts';
import { ListPanel, type ListColumn, type ListPanelEvents, type ListPanelRow } from '../ui/listPanel.ts';
import { STRINGS } from '../ui/strings.ts';

// CSS pixels, as the desktop's column widths
const KEY_WIDTH = 190;
const VALUE_WIDTH = 80;
const DESCRIPTION_WIDTH = 320;

export class MeasurementGrid extends ListPanel<MeasurementDocument> {
  private sizes: readonly string[] = [];

  constructor(document: MeasurementDocument, events: ListPanelEvents) {
    super(document, events, MeasurementGrid.columns([]));
    // One row at a time, as the desktop's grid; there is no search
    this.multiSelect = false;
    this.header.hidden = true;
    this.setShown(true);
  }

  private static columns(sizes: readonly string[]): ListColumn[] {
    const values = sizes.length === 0 ? [STRINGS.measureColumnValue] : sizes;
    return [
      { caption: STRINGS.measureColumnKey, width: KEY_WIDTH },
      ...values.map((caption) => ({ caption, width: VALUE_WIDTH })),
      { caption: STRINGS.measureColumnDescription, width: DESCRIPTION_WIDTH },
    ];
  }

  // The set or the unit changed: the columns follow its sizes
  showSet(): void {
    const sizes = this.document.state.sizes;
    if (sizes.join('\n') !== this.sizes.join('\n') || this.sizes.length !== sizes.length) {
      this.sizes = [...sizes];
      this.setColumns(MeasurementGrid.columns(sizes));
    }
    this.refresh();
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
}
