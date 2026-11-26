// Print… in the Publish app, as Sloper.Publish.PrintDialog: the layout's PDF,
// the one Export PDF writes (publish_export), opened in the browser's own
// viewer to print at 100%, or downloaded. The browser's print dialog chooses
// the printer, the copies and the pages, so this one says which pages to
// print first: the cover with the test square, to measure before the rest.
// A layout a problem stops printing is refused, with the reason.
import type { LayoutDocument } from '../document/layoutDocument.ts';
import { EngineError } from '../engine/engine.ts';
import { stringField } from '../engine/replies.ts';
import { deliverPdf, pdfBlob } from '../ui/download.ts';
import { STRINGS } from '../ui/strings.ts';

export interface PrintDialogEvents {
  // The layout's base name, for the PDF's
  baseName(): string;
  message(text: string): void;
  failed(error: unknown): void;
}

export class PrintDialog {
  private readonly document: LayoutDocument;
  private readonly events: PrintDialogEvents;
  private readonly dialog: HTMLDialogElement;
  private readonly pages: HTMLElement;
  private readonly openButton: HTMLButtonElement;
  private readonly downloadButton: HTMLButtonElement;
  private readonly notes: HTMLElement;

  constructor(layoutDocument: LayoutDocument, events: PrintDialogEvents) {
    this.document = layoutDocument;
    this.events = events;
    const make = window.document.createElement.bind(window.document);
    this.dialog = make('dialog');
    this.dialog.className = 'print-dialog';
    const title = make('h2');
    title.textContent = STRINGS.printTitle;
    const about = make('p');
    about.className = 'print-about';
    about.textContent = STRINGS.layoutPrintAbout;
    this.pages = make('p');
    this.pages.className = 'print-pages';
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
    this.dialog.append(title, about, this.pages, this.notes, buttons);
    window.document.body.append(this.dialog);
  }

  // Which pages to print first, as the desktop's dialog offers the cover alone
  open(): void {
    const state = this.document.state;
    this.pages.textContent =
      state.kind === 'tiled' && state.pages > 1 ? STRINGS.layoutPrintPages(state.pages) : STRINGS.layoutPrintOneSheet;
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
    let base64: string;
    try {
      base64 = stringField(await this.document.read('publish_export', { format: 'pdf' }), 'base64') ?? '';
    } catch (error: unknown) {
      // Refused, as while a problem stops printing: said here
      if (!(error instanceof EngineError)) {
        throw error;
      }
      tab?.close();
      this.setBusy(false);
      this.notes.textContent = error.message;
      this.notes.classList.add('refused');
      return;
    }
    this.setBusy(false);
    this.notes.textContent = '';
    const pdfName = `${this.events.baseName()}.pdf`;
    const done = deliverPdf(tab, pdfName, pdfBlob(base64));
    if (done === 'opened') {
      this.events.message(STRINGS.printOpened);
    } else if (done === 'blocked') {
      this.events.message(STRINGS.printBlocked(pdfName));
    } else {
      this.events.message(STRINGS.printDownloaded(pdfName));
    }
  }
}
