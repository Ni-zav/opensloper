// The Info tab of the Publish app's side panel, as the desktop builds it in
// Sloper.Publish.MainForm (BuildInfoTab): whether the information block
// shows, the fields it shows, whether it is on every page, and its corner.
// The engine says which fields there are and whether the corner and every
// page apply to the output (publish_title), and makes each change as the
// desktop's tab does (publish_set_title): a field shown anew prints last.
import type { LayoutDocument } from '../document/layoutDocument.ts';
import { booleanField, stringField, stringsField, type JsonRecord } from '../engine/replies.ts';
import { LatestOnly } from '../ui/latestOnly.ts';
import type { SideTabContent } from '../ui/sideTabs.ts';
import { STRINGS } from '../ui/strings.ts';

export interface InfoTabEvents {
  failed(error: unknown): void;
}

// The engine's field names with the desktop's captions, in the tab's order
const FIELD_CAPTIONS: Record<string, string> = {
  'pattern.name': STRINGS.fieldPattern,
  'measurements.name': STRINGS.fieldMeasurements,
  'layout.name': STRINGS.fieldLayout,
  date: STRINGS.fieldDate,
  cutlist: STRINGS.fieldCutList,
  materials: STRINGS.fieldMaterials,
  materialneeded: STRINGS.fieldMaterialNeeded,
};
const CORNERS: [string, string][] = [
  ['bottomRight', STRINGS.cornerBottomRight],
  ['bottomLeft', STRINGS.cornerBottomLeft],
  ['topRight', STRINGS.cornerTopRight],
];

function check(name: string, changed: (on: boolean) => void): HTMLInputElement {
  const box = document.createElement('input');
  box.type = 'checkbox';
  box.name = name;
  box.addEventListener('change', () => {
    changed(box.checked);
  });
  return box;
}

function checkRow(caption: string, box: HTMLInputElement): HTMLLabelElement {
  const row = document.createElement('label');
  row.className = 'info-check';
  row.append(box, caption);
  return row;
}

export class InfoTab implements SideTabContent {
  readonly element: HTMLElement;
  private readonly document: LayoutDocument;
  private readonly events: InfoTabEvents;
  private readonly shown: HTMLInputElement;
  private readonly fieldList: HTMLElement;
  private readonly fields = new Map<string, HTMLInputElement>();
  private readonly everyPage: HTMLInputElement;
  private readonly corner: HTMLSelectElement;
  private readonly reads: LatestOnly<number>;
  private readonly listener = (): void => {
    this.reads.push(0);
  };

  constructor(layoutDocument: LayoutDocument, events: InfoTabEvents) {
    this.document = layoutDocument;
    this.events = events;
    this.element = document.createElement('div');
    this.element.className = 'info';
    this.reads = new LatestOnly(
      async () => this.load(),
      (error) => {
        events.failed(error);
      },
    );
    this.shown = check('enabled', (on) => {
      this.set({ enabled: on });
    });
    this.fieldList = document.createElement('div');
    this.fieldList.className = 'info-fields';
    this.everyPage = check('everyPage', (on) => {
      this.set({ everyPage: on });
    });
    this.corner = document.createElement('select');
    this.corner.name = 'corner';
    for (const [value, caption] of CORNERS) {
      this.corner.add(new Option(caption, value));
    }
    this.corner.addEventListener('change', () => {
      this.set({ corner: this.corner.value });
    });
    const corner = document.createElement('label');
    corner.className = 'info-row';
    const cornerCaption = document.createElement('span');
    cornerCaption.textContent = STRINGS.corner;
    corner.append(cornerCaption, this.corner);
    this.element.append(
      checkRow(STRINGS.showTitleBlock, this.shown),
      this.fieldList,
      checkRow(STRINGS.everyPage, this.everyPage),
      corner,
    );
    layoutDocument.addListener(this.listener);
  }

  // Filled on every change, shown or not, so it is ready when opened
  setShown(): void {
    // Nothing to catch up on
  }

  dispose(): void {
    this.document.removeListener(this.listener);
  }

  private set(params: Record<string, string | boolean>): void {
    this.document.call('publish_set_title', params).catch((error: unknown) => {
      this.events.failed(error);
    });
  }

  private async load(): Promise<void> {
    this.show(await this.document.read('publish_title'));
  }

  private show(answer: JsonRecord): void {
    const enabled = booleanField(answer, 'enabled') ?? false;
    const placeUsed = booleanField(answer, 'placeUsed') ?? true;
    const shownFields = new Set(stringsField(answer, 'fields') ?? []);
    // The boxes, once, in the engine's order
    for (const name of stringsField(answer, 'available') ?? []) {
      if (!this.fields.has(name)) {
        const caption = FIELD_CAPTIONS[name] ?? name;
        const box = check(`field:${name}`, (on) => {
          this.set({ field: name, shown: on });
        });
        this.fields.set(name, box);
        this.fieldList.append(checkRow(caption, box));
      }
    }
    this.shown.checked = enabled;
    for (const [name, box] of this.fields) {
      box.checked = shownFields.has(name);
      box.disabled = !enabled;
    }
    this.everyPage.checked = booleanField(answer, 'everyPage') ?? false;
    this.everyPage.disabled = !placeUsed;
    this.corner.value = stringField(answer, 'corner') ?? 'bottomRight';
    this.corner.disabled = !placeUsed;
  }
}
