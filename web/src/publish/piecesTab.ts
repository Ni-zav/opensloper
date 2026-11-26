// The Pieces tab of the Publish app's side panel, as the desktop builds it in
// Sloper.Publish.MainForm (BuildPiecesTab): Turn 90°, Flip and Back to tray
// for the piece selected on the pages; Place new pieces and Pack pieces; and
// the tray, listing the copies waiting to be placed. A double-click on one,
// or Enter, places it. The engine makes every change (publish_ methods), so
// the tab only shows the layout's state and says what was asked.
import type { LayoutState } from '../document/layoutDocument.ts';
import type { SideTabContent } from '../ui/sideTabs.ts';
import { STRINGS } from '../ui/strings.ts';

export interface PiecesTabEvents {
  turn(): void;
  flip(): void;
  unplace(): void;
  placeNew(): void;
  pack(): void;
  // A copy in the tray, by its index there
  placeCopy(index: number): void;
}

function group(caption: string): HTMLFieldSetElement {
  const made = document.createElement('fieldset');
  made.className = 'pieces-group';
  const legend = document.createElement('legend');
  legend.textContent = caption;
  made.append(legend);
  return made;
}

function button(caption: string, hint: string, action: () => void): HTMLButtonElement {
  const made = document.createElement('button');
  made.type = 'button';
  made.textContent = caption;
  made.title = hint;
  made.addEventListener('click', action);
  return made;
}

export class PiecesTab implements SideTabContent {
  readonly element: HTMLElement;
  private readonly turnButton: HTMLButtonElement;
  private readonly flipButton: HTMLButtonElement;
  private readonly unplaceButton: HTMLButtonElement;
  private readonly placeButton: HTMLButtonElement;
  private readonly packButton: HTMLButtonElement;
  private readonly tray: HTMLUListElement;
  private readonly events: PiecesTabEvents;
  // The tray's lines as last shown, so an unchanged tray keeps its choice
  private shownLines = '';
  private chosen = -1;
  private copies = 0;

  constructor(events: PiecesTabEvents) {
    this.events = events;
    this.element = document.createElement('div');
    this.element.className = 'pieces';
    const selected = group(STRINGS.selectedPiece);
    this.turnButton = button(STRINGS.turnPiece, STRINGS.turnPieceHint, () => {
      events.turn();
    });
    this.flipButton = button(STRINGS.flipPiece, STRINGS.flipPieceHint, () => {
      events.flip();
    });
    this.unplaceButton = button(STRINGS.unplacePiece, STRINGS.unplacePieceHint, () => {
      events.unplace();
    });
    selected.append(this.turnButton, this.flipButton, this.unplaceButton);
    const arrange = group(STRINGS.arrange);
    this.placeButton = button(STRINGS.placeNew, STRINGS.placeNewHint, () => {
      events.placeNew();
    });
    this.packButton = button(STRINGS.packPieces, STRINGS.packPiecesHint, () => {
      events.pack();
    });
    arrange.append(this.placeButton, this.packButton);
    const trayGroup = group(STRINGS.trayGroup);
    trayGroup.classList.add('pieces-tray');
    const trayLabel = document.createElement('div');
    trayLabel.textContent = STRINGS.trayHint;
    this.tray = document.createElement('ul');
    this.tray.className = 'tray-list';
    this.tray.setAttribute('role', 'listbox');
    this.tray.setAttribute('aria-label', STRINGS.trayGroup);
    this.tray.tabIndex = 0;
    trayGroup.append(trayLabel, this.tray);
    this.element.append(selected, arrange, trayGroup);
    this.tray.addEventListener('click', (event) => {
      this.choose(this.indexAt(event));
    });
    this.tray.addEventListener('dblclick', (event) => {
      this.place(this.indexAt(event));
    });
    this.tray.addEventListener('keydown', (event) => {
      this.key(event);
    });
  }

  // Filled on every change, shown or not
  setShown(): void {
    // Nothing to catch up on
  }

  // The buttons follow the selection and the output, as the desktop's do
  show(state: Readonly<LayoutState>, selected: number, open: boolean): void {
    const hasSelection = selected >= 0;
    this.turnButton.disabled = !hasSelection;
    this.flipButton.disabled = !hasSelection;
    this.unplaceButton.disabled = !hasSelection;
    this.placeButton.disabled = state.tray.length === 0;
    this.packButton.disabled = !open || state.kind === 'projector' || state.placed + state.tray.length === 0;
    this.showTray(state, open);
  }

  // Rebuilt only when its lines change, as the desktop's tray
  private showTray(state: Readonly<LayoutState>, open: boolean): void {
    const lines = state.tray.map((copy) => copy.caption);
    let note = '';
    if (open && lines.length === 0) {
      note = state.placed === 0 ? STRINGS.trayNoPieces : STRINGS.trayEmpty;
    }
    const key = JSON.stringify([lines, note, state.tray.map((copy) => copy.canPlace)]);
    if (key === this.shownLines) {
      return;
    }
    this.shownLines = key;
    this.copies = lines.length;
    this.chosen = Math.min(this.chosen, this.copies - 1);
    const items = state.tray.map((copy, index) => {
      const item = document.createElement('li');
      item.textContent = copy.caption;
      item.setAttribute('role', 'option');
      item.dataset.index = String(index);
      item.classList.toggle('cannot-place', !copy.canPlace);
      if (!copy.canPlace) {
        item.title = STRINGS.cannotPlace;
      }
      return item;
    });
    if (note !== '') {
      const item = document.createElement('li');
      item.className = 'tray-note';
      item.textContent = note;
      items.push(item);
    }
    this.tray.replaceChildren(...items);
    this.markChosen();
  }

  private indexAt(event: MouseEvent): number {
    const target = event.target instanceof Element ? event.target.closest('li') : null;
    const index = Number(target?.dataset.index ?? '-1');
    return index < this.copies ? index : -1;
  }

  private choose(index: number): void {
    if (index < 0) {
      return;
    }
    this.chosen = index;
    this.markChosen();
  }

  private place(index: number): void {
    if (index >= 0) {
      this.chosen = index;
      this.markChosen();
      this.events.placeCopy(index);
    }
  }

  private markChosen(): void {
    for (const item of this.tray.children) {
      const chosen = item instanceof HTMLElement && item.dataset.index === String(this.chosen);
      item.classList.toggle('chosen', chosen);
      item.setAttribute('aria-selected', String(chosen));
      if (chosen) {
        item.scrollIntoView({ block: 'nearest' });
      }
    }
  }

  private key(event: KeyboardEvent): void {
    if (this.copies === 0) {
      return;
    }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      const step = event.key === 'ArrowDown' ? 1 : -1;
      this.choose(Math.max(0, Math.min(this.copies - 1, this.chosen + step)));
      event.preventDefault();
    } else if (event.key === 'Enter') {
      this.place(this.chosen);
      event.preventDefault();
    }
  }
}
