// The list behind the side panel's tabs, as Sloper.UI.ListPanel: a search box
// over a grid of rows, held by key, since undo and redo replace the pattern's
// objects. Each tab says what its rows are. The panel keeps the selection
// itself and paints it; a click asks the engine what it selects
// (editor_list_click), as SelectionAfterClick decides it on the desktop.
// Rows are built again after each change while the tab shows, and once it
// shows again after changes made while it was hidden.
import type { DocumentChange, PatternDocument } from '../document/patternDocument.ts';
import { EngineError } from '../engine/engine.ts';
import { idsField } from '../engine/replies.ts';
import type { EvalState } from '../editor/scene.ts';
import { LatestOnly } from './latestOnly.ts';
import type { SideTabContent } from './sideTabs.ts';
import { STRINGS } from './strings.ts';

export interface ListPanelRow {
  key: string;
  cells: string[];
  state: EvalState;
}

export interface ListColumn {
  caption: string;
  // CSS pixels, as the desktop's widths at 96 pixels per inch
  width: number;
}

export interface ListPanelEvents {
  // The user chose rows in the list
  select(keys: readonly string[]): void;
  // The user double-clicked a row
  zoom(): void;
  // A hint or the reason something could not be done
  message(text: string): void;
  failed(error: unknown): void;
}

export abstract class ListPanel implements SideTabContent {
  readonly element: HTMLElement;
  protected readonly document: PatternDocument;
  protected readonly header: HTMLElement;
  // Several rows can be chosen at once with Ctrl or Shift
  protected multiSelect = true;
  private readonly events: ListPanelEvents;
  private readonly search: HTMLInputElement;
  private readonly body: HTMLTableSectionElement;
  private readonly refreshes: LatestOnly<number>;
  private rows: ListPanelRow[] = [];
  private selected: string[] = [];
  private anchor = '';
  private shown = false;
  // Changes came while the tab was hidden
  private stale = true;
  private readonly listener = (_document: PatternDocument, changes: ReadonlySet<DocumentChange>): void => {
    if (changes.has('pattern') || changes.has('objectsReplaced') || changes.has('measurements')) {
      this.refresh();
    }
  };

  protected constructor(document: PatternDocument, events: ListPanelEvents, columns: readonly ListColumn[]) {
    this.document = document;
    this.events = events;
    this.element = window.document.createElement('div');
    this.element.className = 'list-panel';
    this.header = window.document.createElement('div');
    this.header.className = 'list-header';
    this.search = window.document.createElement('input');
    this.search.type = 'search';
    this.search.placeholder = STRINGS.listSearch;
    this.search.setAttribute('aria-label', STRINGS.listSearch);
    this.search.addEventListener('input', () => {
      this.refresh();
    });
    this.header.append(this.search);
    const scroller = window.document.createElement('div');
    scroller.className = 'list-scroller';
    const table = window.document.createElement('table');
    table.className = 'list-grid';
    const widths = window.document.createElement('colgroup');
    const head = table.createTHead().insertRow();
    for (const column of columns) {
      const col = window.document.createElement('col');
      col.style.width = `${String(column.width)}px`;
      widths.append(col);
      const cell = window.document.createElement('th');
      cell.textContent = column.caption;
      head.append(cell);
    }
    table.prepend(widths);
    this.body = table.createTBody();
    this.body.addEventListener('mousedown', (event) => {
      this.rowPressed(event);
    });
    this.body.addEventListener('dblclick', () => {
      this.events.zoom();
    });
    scroller.append(table);
    this.element.append(this.header, scroller);
    this.refreshes = new LatestOnly(
      async () => this.loadRows(),
      (error) => {
        this.report(error);
      },
    );
    document.addListener(this.listener);
  }

  // What the tab lists, for the search text
  protected abstract buildRows(search: string): Promise<ListPanelRow[]>;

  // Keys of the selected rows
  get selection(): readonly string[] {
    return this.selected;
  }

  // The keys of the rows listed, filter and search applied, in list order
  get visibleKeys(): string[] {
    return this.rows.map((row) => row.key);
  }

  setShown(shown: boolean): void {
    this.shown = shown;
    if (shown && this.stale) {
      this.refresh();
    }
  }

  // Follows a selection made elsewhere, without telling select
  showSelection(keys: readonly string[]): void {
    this.selected = [...keys];
    this.paintSelection();
  }

  // Stops listening to the document, so a closed panel is not kept alive
  dispose(): void {
    this.document.removeListener(this.listener);
  }

  // Builds the rows again, now when the tab shows, else when it next does
  protected refresh(): void {
    if (this.shown) {
      this.stale = false;
      this.refreshes.push(0);
    } else {
      this.stale = true;
    }
  }

  protected report(error: unknown): void {
    if (error instanceof EngineError) {
      this.events.message(error.message);
    } else {
      this.events.failed(error);
    }
  }

  private async loadRows(): Promise<void> {
    this.rows = await this.buildRows(this.search.value);
    const rows = this.rows.map((row) => {
      const line = window.document.createElement('tr');
      line.dataset.key = row.key;
      if (row.state === 'error' || row.state === 'invalid') {
        line.classList.add('failed');
      } else if (row.state === 'blocked') {
        line.classList.add('blocked');
      }
      for (const text of row.cells) {
        const cell = window.document.createElement('td');
        cell.textContent = text;
        cell.title = text;
        line.append(cell);
      }
      return line;
    });
    this.body.replaceChildren(...rows);
    this.paintSelection();
  }

  private paintSelection(): void {
    const chosen = new Set(this.selected);
    for (const line of this.body.rows) {
      line.classList.toggle('selected', chosen.has(line.dataset.key ?? ''));
    }
  }

  private rowPressed(event: MouseEvent): void {
    // The second press of a double-click leaves the selection for the zoom
    if (event.button !== 0 || event.detail > 1 || !(event.target instanceof Element)) {
      return;
    }
    const key = event.target.closest('tr')?.dataset.key;
    if (key === undefined) {
      return;
    }
    event.preventDefault();
    const toggle = this.multiSelect && (event.ctrlKey || event.metaKey);
    const extend = this.multiSelect && event.shiftKey;
    this.chooseRow(key, toggle, extend).catch((error: unknown) => {
      this.report(error);
    });
  }

  private async chooseRow(key: string, toggle: boolean, extend: boolean): Promise<void> {
    const answer = await this.document.read('editor_list_click', {
      visible: this.visibleKeys,
      selected: this.selected,
      anchor: this.anchor,
      clicked: key,
      toggle,
      extend,
    });
    this.selected = idsField(answer, 'selection');
    if (!extend) {
      this.anchor = key;
    }
    this.paintSelection();
    this.events.select(this.selected);
  }
}
