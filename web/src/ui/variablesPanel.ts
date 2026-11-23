// The variables tab of the side panel, as Sloper.UI.VariablesPanel: the
// pattern's variables with their formulas, values and descriptions,
// searchable. Editing them in the grid comes with the list panel's cells.
import type { PatternDocument } from '../document/patternDocument.ts';
import { idField, recordsField, stringField } from '../engine/replies.ts';
import { stateField } from '../editor/scene.ts';
import { ListPanel, type ListPanelEvents, type ListPanelRow } from './listPanel.ts';
import { STRINGS } from './strings.ts';

export class VariablesPanel extends ListPanel {
  constructor(document: PatternDocument, events: ListPanelEvents) {
    super(document, events, [
      { caption: STRINGS.columnName, width: 110 },
      { caption: STRINGS.columnFormula, width: 150 },
      { caption: STRINGS.columnValue, width: 70 },
      { caption: STRINGS.columnDescription, width: 200 },
    ]);
    // Editable panels select one row at a time
    this.multiSelect = false;
  }

  protected async buildRows(search: string): Promise<ListPanelRow[]> {
    const answer = await this.document.read('editor_list_variables', { search });
    return recordsField(answer, 'rows').map((row) => ({
      key: idField(row, 'id') ?? '',
      state: stateField(row),
      cells: ['name', 'formula', 'value', 'description'].map((name) => stringField(row, name) ?? ''),
    }));
  }
}
