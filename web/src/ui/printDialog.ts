// Print…: the pattern as the publish app's tiled print of a new layout with
// every piece placed (editor_print), on the paper chosen: pages with their
// row and column captions and overlaps, and a cover with the test square and
// the page map. The PDF opens in the browser's own viewer to print at 100%,
// or is downloaded. Nothing is saved, and unsaved edits are included.
import type { PatternDocument } from '../document/patternDocument.ts';
import { booleanField, stringField, stringsField } from '../engine/replies.ts';
import { downloadBlob } from './download.ts';
import { STRINGS } from './strings.ts';

const PAPERS = ['A4', 'A3', 'Letter'] as const;
// Where Letter is the usual paper
const LETTER_REGIONS = new Set(['US', 'CA', 'MX', 'PH', 'CL', 'CO', 'VE']);
// How long an opened PDF's address is kept for the viewer to read it, in ms
const OPENED_PDF_MS = 60000;

// Letter where it is the usual paper, else A4
function usualPaper(): string {
  const region = navigator.language.split('-')[1]?.toUpperCase() ?? '';
  return LETTER_REGIONS.has(region) ? 'Letter' : 'A4';
}

function pdfBlob(base64: string): Blob {
  const text = atob(base64);
  const bytes = new Uint8Array(text.length);
  for (let index = 0; index < text.length; index++) {
    bytes[index] = text.charCodeAt(index);
  }
  return new Blob([bytes], { type: 'application/pdf' });
}

export interface PrintDialogEvents {
  // The pattern's file name, for the PDF's and the layout's
  fileName(): string;
  message(text: string): void;
  failed(error: unknown): void;
}

export class PrintDialog {
  private readonly document: PatternDocument;
  private readonly events: PrintDialogEvents;
  private readonly dialog: HTMLDialogElement;
  private readonly paperBox: HTMLSelectElement;
  private readonly openButton: HTMLButtonElement;
  private readonly downloadButton: HTMLButtonElement;
  private readonly notes: HTMLElement;

  constructor(document: PatternDocument, events: PrintDialogEvents) {
    this.document = document;
    this.events = events;
    const make = window.document.createElement.bind(window.document);
    this.dialog = make('dialog');
    this.dialog.className = 'print-dialog';
    const title = make('h2');
    title.textContent = STRINGS.printTitle;
    const about = make('p');
    about.className = 'print-about';
    about.textContent = STRINGS.printAbout;
    const paperLabel = make('label');
    paperLabel.textContent = STRINGS.printPaper;
    this.paperBox = make('select');
    this.paperBox.id = 'print-paper';
    paperLabel.htmlFor = this.paperBox.id;
    for (const paper of PAPERS) {
      this.paperBox.add(new Option(paper, paper));
    }
    this.paperBox.value = usualPaper();
    const paperRow = make('div');
    paperRow.className = 'print-row';
    paperRow.append(paperLabel, this.paperBox);
    this.notes = make('div');
    this.notes.className = 'print-notes';
    this.openButton = this.button(STRINGS.printOpen, STRINGS.printOpenHint, () => {
      // Opened now, while the click counts, and given the PDF once it is made
      const tab = window.open('', '_blank');
      this.run(this.make(tab));
    });
    this.openButton.classList.add('default');
    this.downloadButton = this.button(STRINGS.printDownload, STRINGS.printDownloadHint, () => {
      this.run(this.make(undefined));
    });
    const close = this.button(STRINGS.printClose, '', () => {
      this.dialog.close();
    });
    const buttons = make('div');
    buttons.className = 'print-buttons';
    buttons.append(this.openButton, this.downloadButton, close);
    this.dialog.append(title, about, paperRow, this.notes, buttons);
    window.document.body.append(this.dialog);
  }

  open(): void {
    this.notes.textContent = '';
    this.notes.classList.remove('refused');
    this.dialog.showModal();
    this.openButton.focus();
  }

  dispose(): void {
    this.dialog.remove();
  }

  private button(caption: string, hint: string, action: () => void): HTMLButtonElement {
    const button = window.document.createElement('button');
    button.type = 'button';
    button.textContent = caption;
    button.title = hint;
    button.addEventListener('click', action);
    return button;
  }

  private run(pending: Promise<void>): void {
    pending.catch((error: unknown) => {
      this.setBusy(false);
      this.notes.textContent = '';
      this.events.failed(error);
    });
  }

  private setBusy(busy: boolean): void {
    this.openButton.disabled = busy;
    this.downloadButton.disabled = busy;
  }

  // Tab is the window opened for the viewer, or undefined to download
  private async make(tab: Window | null | undefined): Promise<void> {
    this.notes.classList.remove('refused');
    this.notes.textContent = STRINGS.printMaking;
    this.setBusy(true);
    const fileName = this.events.fileName();
    const answer = await this.document.read('editor_print', { paper: this.paperBox.value, fileName });
    this.setBusy(false);
    if (booleanField(answer, 'done') !== true) {
      tab?.close();
      this.notes.textContent = stringField(answer, 'reason') ?? '';
      this.notes.classList.add('refused');
      return;
    }
    // What the publish app would warn of, as pieces wider than the paper
    const warnings = stringsField(answer, 'warnings') ?? [];
    this.notes.textContent = warnings.join('\n');
    const blob = pdfBlob(stringField(answer, 'pdf') ?? '');
    const pdfName = `${fileName.replace(/\.[^.]*$/, '')}.pdf`;
    if (tab === undefined) {
      downloadBlob(pdfName, blob);
      this.events.message(STRINGS.printDownloaded(pdfName));
      return;
    }
    if (tab === null) {
      // The browser would not open a window: the PDF is downloaded instead
      downloadBlob(pdfName, blob);
      this.events.message(STRINGS.printBlocked(pdfName));
      return;
    }
    const address = URL.createObjectURL(blob);
    tab.location.href = address;
    setTimeout(() => {
      URL.revokeObjectURL(address);
    }, OPENED_PDF_MS);
    this.events.message(STRINGS.printOpened);
  }
}
