// The Materials tab of the side panel, as Sloper.UI.MaterialPanel: the
// pattern's materials, read-only, with the cut list they make. Colour and
// fill do not fit in a cell, so materials are edited in the Materials
// dialog, which Edit opens, as does a double-click on a row.
import type { DocumentChange, PatternDocument } from '../document/patternDocument.ts';
import { LatestOnly } from './latestOnly.ts';
import { MaterialGrid, parseMaterials } from './materialGrid.ts';
import type { SideTabContent } from './sideTabs.ts';
import { STRINGS } from './strings.ts';

export interface MaterialsPanelEvents {
  // The user wants the Materials dialog, starting on this row, or -1
  edit(index: number): void;
  failed(error: unknown): void;
}

export class MaterialsPanel implements SideTabContent {
  readonly element: HTMLElement;
  private readonly document: PatternDocument;
  private readonly grid: MaterialGrid;
  private readonly cutList: HTMLElement;
  private readonly loads: LatestOnly<number>;
  private shown = false;
  private stale = true;
  private readonly listener = (_document: PatternDocument, changes: ReadonlySet<DocumentChange>): void => {
    if (changes.has('pattern') || changes.has('objectsReplaced')) {
      this.reload();
    }
  };

  constructor(document: PatternDocument, events: MaterialsPanelEvents) {
    this.document = document;
    const make = window.document.createElement.bind(window.document);
    this.element = make('div');
    this.element.className = 'materials';
    this.grid = new MaterialGrid({
      select: () => undefined,
      activate: (index) => {
        events.edit(index);
      },
    });
    const cutGroup = make('fieldset');
    cutGroup.className = 'material-cut-list';
    const cutTitle = make('legend');
    cutTitle.textContent = STRINGS.materialCutList;
    this.cutList = make('pre');
    cutGroup.append(cutTitle, this.cutList);
    const edit = make('button');
    edit.type = 'button';
    edit.className = 'material-edit';
    edit.textContent = STRINGS.materialEdit;
    edit.title = STRINGS.materialEditHint;
    edit.addEventListener('click', () => {
      events.edit(this.grid.index);
    });
    const buttons = make('div');
    buttons.className = 'list-buttons';
    buttons.append(edit);
    this.element.append(this.grid.element, cutGroup, buttons);
    this.loads = new LatestOnly(
      async () => this.load(),
      (error) => {
        events.failed(error);
      },
    );
    document.addListener(this.listener);
  }

  setShown(shown: boolean): void {
    this.shown = shown;
    if (shown && this.stale) {
      this.reload();
    }
  }

  dispose(): void {
    this.document.removeListener(this.listener);
    this.element.remove();
  }

  private reload(): void {
    if (!this.shown) {
      this.stale = true;
      return;
    }
    this.stale = false;
    this.loads.push(0);
  }

  private async load(): Promise<void> {
    const list = parseMaterials(await this.document.read('editor_materials'));
    this.grid.show(list.rows);
    this.cutList.textContent = list.cutList;
  }
}
