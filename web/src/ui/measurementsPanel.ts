// The measurements tab of the side panel, as Sloper.UI.MeasurementsPanel: the
// measurement file's measurements, searchable, then those the pattern uses
// that the file lacks, in red. Editing values, sizes and the size test come
// later.
import type { PatternDocument } from '../document/patternDocument.ts';
import { booleanField, recordsField, stringField } from '../engine/replies.ts';
import { ListPanel, type ListPanelEvents, type ListPanelRow } from './listPanel.ts';
import { STRINGS } from './strings.ts';

export class MeasurementsPanel extends ListPanel {
  constructor(document: PatternDocument, events: ListPanelEvents) {
    super(document, events, [
      { caption: STRINGS.measurementsKey, width: 120 },
      { caption: STRINGS.measurementsValue, width: 100 },
      { caption: STRINGS.columnDescription, width: 240 },
    ]);
    this.multiSelect = false;
  }

  protected async buildRows(search: string): Promise<ListPanelRow[]> {
    const answer = await this.document.read('editor_list_measurements', { search });
    return recordsField(answer, 'rows').map((row) => {
      const missing = booleanField(row, 'missing') === true;
      return {
        key: stringField(row, 'key') ?? '',
        state: missing ? 'error' : 'valid',
        cells: [
          stringField(row, 'key') ?? '',
          missing ? STRINGS.measurementsMissing : (stringField(row, 'value') ?? ''),
          missing ? '' : (stringField(row, 'description') ?? ''),
        ],
      };
    });
  }
}
