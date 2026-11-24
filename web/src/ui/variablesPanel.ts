// The variables tab of the side panel, as Sloper.UI.VariablesPanel: the
// pattern's variables with their formulas, values and descriptions,
// searchable, edited in the grid (name, formula with completion, and
// description), each edit one undo step, with Add, Delete and Import below.
// Import asks the app, which chooses the file.
import type { PatternDocument } from '../document/patternDocument.ts';
import { booleanField, idField, recordsField, stringField } from '../engine/replies.ts';
import { stateField } from '../editor/scene.ts';
import { ListPanel, type CellCommit, type ListPanelEvents, type ListPanelRow } from './listPanel.ts';

export interface VariablesPanelEvents extends ListPanelEvents {
  // Import… was clicked: import the variables of another pattern file
  import(): void;
}
import { STRINGS } from './strings.ts';

// As TVariableColumn; the value is worked out, so has no name to commit
const COLUMNS = ['name', 'formula', 'value', 'description'] as const;
const NAME_COLUMN = 0;

export class VariablesPanel extends ListPanel {
  constructor(document: PatternDocument, events: VariablesPanelEvents) {
    super(document, events, [
      { caption: STRINGS.columnName, width: 110 },
      { caption: STRINGS.columnFormula, width: 150 },
      { caption: STRINGS.columnValue, width: 70 },
      { caption: STRINGS.columnDescription, width: 200 },
    ]);
    this.setEditableColumns([true, true, false, true], [false, true, false, false]);
    const buttons = window.document.createElement('div');
    buttons.className = 'list-buttons';
    const add = window.document.createElement('button');
    add.type = 'button';
    add.textContent = STRINGS.variablesAdd;
    add.addEventListener('click', () => {
      this.addVariable().catch((error: unknown) => {
        this.report(error);
      });
    });
    const remove = window.document.createElement('button');
    remove.type = 'button';
    remove.textContent = STRINGS.variablesDelete;
    remove.addEventListener('click', () => {
      this.deleteRequested();
    });
    const importButton = window.document.createElement('button');
    importButton.type = 'button';
    importButton.textContent = STRINGS.variablesImport;
    importButton.title = STRINGS.variablesImportHint;
    importButton.addEventListener('click', () => {
      events.import();
    });
    buttons.append(add, remove, importButton);
    this.element.append(buttons);
  }

  protected async buildRows(search: string): Promise<ListPanelRow[]> {
    const answer = await this.document.read('editor_list_variables', { search });
    return recordsField(answer, 'rows').map((row) => ({
      key: idField(row, 'id') ?? '',
      state: stateField(row),
      cells: ['name', 'formula', 'value', 'description'].map((name) => stringField(row, name) ?? ''),
    }));
  }

  protected override async commitCell(key: string, column: number, text: string): Promise<CellCommit> {
    const answer = await this.document.call('editor_variable_set', {
      id: Number(key),
      column: COLUMNS[column],
      text,
    });
    return { done: booleanField(answer, 'done') === true, reason: stringField(answer, 'reason') ?? '' };
  }

  protected override deleteRequested(): void {
    const key = this.selection[0];
    if (key === undefined) {
      return;
    }
    this.document
      .call('editor_variable_delete', { id: Number(key) })
      .then(() => {
        this.showSelection([]);
        this.events.select([]);
        return undefined;
      })
      .catch((error: unknown) => {
        this.report(error);
      });
  }

  // The new row is there once the rows come back after the change, and its name is opened to type
  private async addVariable(): Promise<void> {
    const answer = await this.document.call('editor_variable_add');
    const key = idField(answer, 'id');
    await this.rowsLoaded();
    if (key !== undefined) {
      this.focusCell(key, NAME_COLUMN, true);
    }
  }
}
