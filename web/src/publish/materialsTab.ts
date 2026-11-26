// The Materials tab of the Publish app's side panel, as the desktop builds it
// in Sloper.Publish.MainForm (BuildMaterialsTab): how much of each material
// the layout's patterns need, a row each, with the notes under it and how
// the estimate is made. Nothing here changes the layout; the engine works it
// out (publish_materials) as the desktop's tab does.
import type { LayoutDocument } from '../document/layoutDocument.ts';
import { numberField, recordsField, stringField, stringsField } from '../engine/replies.ts';
import { LatestOnly } from '../ui/latestOnly.ts';
import type { SideTabContent } from '../ui/sideTabs.ts';
import { STRINGS } from '../ui/strings.ts';

export interface MaterialsTabEvents {
  failed(error: unknown): void;
}

function cell(tag: 'td' | 'th', text: string): HTMLTableCellElement {
  const made = document.createElement(tag);
  made.textContent = text;
  return made;
}

export class MaterialsTab implements SideTabContent {
  readonly element: HTMLElement;
  private readonly document: LayoutDocument;
  private readonly rows: HTMLTableSectionElement;
  private readonly notes: HTMLElement;
  private readonly reads: LatestOnly<number>;
  private readonly listener = (): void => {
    this.reads.push(0);
  };

  constructor(layoutDocument: LayoutDocument, events: MaterialsTabEvents) {
    this.document = layoutDocument;
    this.element = document.createElement('div');
    this.element.className = 'materials';
    this.reads = new LatestOnly(
      async () => this.load(),
      (error) => {
        events.failed(error);
      },
    );
    const table = document.createElement('table');
    table.className = 'needs-table';
    const head = table.createTHead().insertRow();
    head.append(
      cell('th', STRINGS.needMaterial),
      cell('th', STRINGS.needSize),
      cell('th', STRINGS.needCopies),
      cell('th', STRINGS.needNeeded),
    );
    this.rows = table.createTBody();
    const notesCaption = document.createElement('div');
    notesCaption.className = 'needs-caption';
    notesCaption.textContent = STRINGS.needNotes;
    this.notes = document.createElement('div');
    this.notes.className = 'needs-notes';
    this.element.append(table, notesCaption, this.notes);
    layoutDocument.addListener(this.listener);
    this.show([]);
  }

  // Filled on every change, shown or not, so it is ready when opened
  setShown(): void {
    // Nothing to catch up on
  }

  dispose(): void {
    this.document.removeListener(this.listener);
  }

  private async load(): Promise<void> {
    const answer = await this.document.read('publish_materials');
    this.show(
      recordsField(answer, 'needs').map((need) => ({
        material: stringField(need, 'material') ?? '',
        size: stringField(need, 'size') ?? '',
        copies: numberField(need, 'copies') ?? 0,
        needed: stringField(need, 'needed') ?? '',
        notes: stringsField(need, 'notes') ?? [],
      })),
    );
  }

  private show(needs: { material: string; size: string; copies: number; needed: string; notes: string[] }[]): void {
    if (needs.length === 0) {
      const row = document.createElement('tr');
      row.append(cell('td', STRINGS.needNothing), cell('td', ''), cell('td', ''), cell('td', ''));
      this.rows.replaceChildren(row);
    } else {
      this.rows.replaceChildren(
        ...needs.map((need) => {
          const row = document.createElement('tr');
          row.append(
            cell('td', need.material),
            cell('td', need.size),
            cell('td', String(need.copies)),
            cell('td', need.needed),
          );
          return row;
        }),
      );
    }
    // Each material's notes, then how the estimate is made
    const lines = needs.flatMap((need) => need.notes);
    this.notes.replaceChildren(
      ...[...lines, STRINGS.needHow].map((line) => {
        const paragraph = document.createElement('p');
        paragraph.textContent = line;
        return paragraph;
      }),
    );
  }
}
