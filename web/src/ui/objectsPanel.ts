// The objects tab of the side panel, as Sloper.UI.ObjectsPanel: every point
// and edge, searchable and filtered by kind, following the canvas selection
// and setting it.
import type { PatternDocument } from '../document/patternDocument.ts';
import { idField, recordsField, stringField } from '../engine/replies.ts';
import { stateField } from '../editor/scene.ts';
import { ListPanel, type ListPanelEvents, type ListPanelRow } from './listPanel.ts';
import { STRINGS } from './strings.ts';

// In the order of TObjectFilter, as editor_list_objects names them
const FILTERS = [
  ['all', STRINGS.objectsAll],
  ['points', STRINGS.objectsPoints],
  ['edges', STRINGS.objectsEdges],
  ['pieces', STRINGS.objectsPieces],
  ['notes', STRINGS.objectsNotes],
  ['problems', STRINGS.objectsProblems],
] as const;

export class ObjectsPanel extends ListPanel {
  private readonly filter: HTMLSelectElement;

  constructor(document: PatternDocument, events: ListPanelEvents) {
    super(document, events, [
      { caption: STRINGS.columnName, width: 110 },
      { caption: STRINGS.columnOperation, width: 150 },
      { caption: STRINGS.columnValue, width: 110 },
      { caption: STRINGS.columnState, width: 60 },
      { caption: STRINGS.columnFormulas, width: 240 },
    ]);
    this.filter = window.document.createElement('select');
    this.filter.setAttribute('aria-label', STRINGS.objectsFilter);
    for (const [name, caption] of FILTERS) {
      this.filter.add(new Option(caption, name));
    }
    this.filter.addEventListener('change', () => {
      this.refresh();
    });
    this.header.append(this.filter);
  }

  protected async buildRows(search: string): Promise<ListPanelRow[]> {
    const answer = await this.document.read('editor_list_objects', { filter: this.filter.value, search });
    return recordsField(answer, 'rows').map((row) => ({
      key: idField(row, 'id') ?? '',
      state: stateField(row),
      cells: ['name', 'operation', 'value', 'stateText', 'formulas'].map((name) => stringField(row, name) ?? ''),
    }));
  }
}
