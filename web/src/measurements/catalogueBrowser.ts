// The measurements page's Add From the Catalogue, as the desktop measurements
// window's side panel: a group, a search, the catalogue's measurements the set
// does not have yet, the details of the one chosen (or of the table's row),
// and Add to the file, which a double-click does too. The engine holds the
// catalogue and searches it; this draws the panel and hands on the choices.
import type { CatalogueEntry, CatalogueItem, MeasurementDocument } from '../document/measurementDocument.ts';
import { EngineError } from '../engine/engine.ts';
import { STRINGS } from '../ui/strings.ts';

// The catalogue's groups, as CATALOGUE_GROUPS in Sloper.Core.Catalogue
const GROUPS = ['heights', 'circumferences', 'widths', 'arm', 'leg', 'crotch', 'head', 'hand', 'foot'] as const;

export interface CatalogueBrowserEvents {
  // A catalogue measurement was added to the set, by its key
  added(key: string): void;
  // A hint or the reason something could not be done
  message(text: string): void;
  failed(error: unknown): void;
}

export class CatalogueBrowser {
  readonly element: HTMLFieldSetElement;
  private readonly document: MeasurementDocument;
  private readonly events: CatalogueBrowserEvents;
  private readonly group: HTMLSelectElement;
  private readonly search: HTMLInputElement;
  private readonly list: HTMLSelectElement;
  private readonly info: HTMLElement;
  private readonly addButton: HTMLButtonElement;
  private listed: CatalogueItem[] = [];
  // Only the latest list and entry asked for are shown
  private listRequest = 0;
  private entryRequest = 0;
  // The entry shown when nothing in the list is chosen: the table's row
  private tableKey: string | undefined;

  constructor(document: MeasurementDocument, events: CatalogueBrowserEvents) {
    this.document = document;
    this.events = events;
    this.element = window.document.createElement('fieldset');
    this.element.className = 'catalogue';
    const legend = window.document.createElement('legend');
    legend.textContent = STRINGS.catalogueTitle;
    this.group = window.document.createElement('select');
    this.group.setAttribute('aria-label', STRINGS.catalogueGroup);
    this.group.add(new Option(STRINGS.catalogueAllGroups, ''));
    for (const group of GROUPS) {
      this.group.add(new Option(STRINGS.catalogueGroups[group], group));
    }
    this.search = window.document.createElement('input');
    this.search.type = 'search';
    this.search.placeholder = STRINGS.listSearch;
    this.search.setAttribute('aria-label', STRINGS.listSearch);
    this.list = window.document.createElement('select');
    this.list.size = 10;
    this.list.setAttribute('aria-label', STRINGS.catalogueTitle);
    this.info = window.document.createElement('div');
    this.info.className = 'catalogue-info';
    this.addButton = window.document.createElement('button');
    this.addButton.type = 'button';
    this.addButton.textContent = STRINGS.catalogueAdd;
    this.addButton.title = STRINGS.catalogueAddHint;
    this.addButton.disabled = true;
    this.element.append(legend, this.group, this.search, this.list, this.info, this.addButton);
    this.group.addEventListener('change', () => {
      this.refresh();
    });
    this.search.addEventListener('input', () => {
      this.refresh();
    });
    this.list.addEventListener('change', () => {
      this.listChanged();
    });
    this.list.addEventListener('dblclick', () => {
      this.run(this.addChosen());
    });
    this.list.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        this.run(this.addChosen());
      }
    });
    this.addButton.addEventListener('click', () => {
      this.run(this.addChosen());
    });
  }

  // The set changed: what it lacks is listed again
  refresh(): void {
    this.run(this.loadList());
  }

  // The table's chosen row, whose entry shows while nothing here is chosen
  showTableKey(key: string | undefined): void {
    this.tableKey = key;
    if (this.chosen === undefined) {
      this.run(this.showEntry(key));
    }
  }

  // The unit changed: the entry's range is shown in it
  showUnit(): void {
    this.run(this.showEntry(this.chosen?.key ?? this.tableKey));
  }

  private get chosen(): CatalogueItem | undefined {
    return this.list.selectedIndex < 0 ? undefined : this.listed[this.list.selectedIndex];
  }

  private run(pending: Promise<void>): void {
    pending.catch((error: unknown) => {
      this.events.failed(error);
    });
  }

  private async loadList(): Promise<void> {
    const request = ++this.listRequest;
    const items = await this.document.catalogueList(this.group.value, this.search.value);
    if (request !== this.listRequest) {
      return;
    }
    const chosen = this.chosen?.key;
    this.listed = items;
    this.list.replaceChildren(...items.map((item) => new Option(item.name, item.key, false, item.key === chosen)));
    this.addButton.disabled = this.chosen === undefined || this.document.fileName === '';
  }

  private listChanged(): void {
    this.addButton.disabled = this.chosen === undefined || this.document.fileName === '';
    this.run(this.showEntry(this.chosen?.key ?? this.tableKey));
  }

  // As the desktop's: its name, description, how to take it and its typical range
  private async showEntry(key: string | undefined): Promise<void> {
    const request = ++this.entryRequest;
    const entry: CatalogueEntry | undefined = key === undefined ? undefined : await this.document.catalogueEntry(key);
    if (request !== this.entryRequest) {
      return;
    }
    const lines =
      entry === undefined
        ? []
        : [
            entry.name,
            entry.description,
            entry.howTo,
            STRINGS.catalogueRange(entry.rangeMin, entry.rangeMax, entry.unit),
          ];
    this.info.replaceChildren(
      ...lines.map((line) => {
        const paragraph = window.document.createElement('p');
        paragraph.textContent = line;
        return paragraph;
      }),
    );
    this.info.dataset.key = entry?.key ?? '';
  }

  // The list's choice is cleared, or the next line slides under the mouse,
  // ready to be added by mistake, as the desktop says
  private async addChosen(): Promise<void> {
    const item = this.chosen;
    if (item === undefined || this.document.fileName === '') {
      return;
    }
    try {
      await this.document.addKnown(item.key);
    } catch (error: unknown) {
      if (error instanceof EngineError) {
        this.events.message(error.message);
        return;
      }
      throw error;
    }
    this.list.selectedIndex = -1;
    this.addButton.disabled = true;
    this.events.added(item.key);
  }
}
