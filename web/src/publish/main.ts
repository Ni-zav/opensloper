// The web Publish app, as Sloper.Publish.MainForm: starts the engine and opens
// a layout with its patterns and measurement files, or patterns to start a
// layout, as the desktop's Open does. The preview shows its pages and pieces;
// the toolbar saves, undoes and exports, each file a download. The side
// panel has the Pieces tab, which turns, flips and unplaces the selected
// piece, places and packs, and holds the tray, and the Problems tab at its
// foot. The title names the layout, and the status bar has a message and the
// count of problems, which opens the Problems tab. Nothing leaves the
// machine: the files are read in the browser and given to the engine as text.
import { LayoutDocument } from '../document/layoutDocument.ts';
import type { Vec2 } from '../editor/view.ts';
import { Engine } from '../engine/engine.ts';
import { booleanField, numberField, stringField } from '../engine/replies.ts';
import { downloadBlob, downloadText } from '../ui/download.ts';
import { PreviewCanvas } from '../ui/previewCanvas.ts';
import { ProblemsPanel } from '../ui/problemsPanel.ts';
import { SideTabs } from '../ui/sideTabs.ts';
import { STRINGS } from '../ui/strings.ts';
import { InfoTab } from './infoTab.ts';
import { NotesTab } from './notesTab.ts';
import { OutputTab } from './outputTab.ts';
import { PatternsTab } from './patternsTab.ts';
import { PiecesTab } from './piecesTab.ts';

const LAYOUT_EXTENSION = '.slayout';
const PATTERN_EXTENSION = '.sloper';

// The desktop's icons for the toolbar's commands and the side panel's tabs
// (APP_ICON_NAMES)
const ICONS = {
  open: 'folder-open',
  save: 'device-floppy',
  undo: 'arrow-back-up',
  redo: 'arrow-forward-up',
  zoomIn: 'zoom-in',
  zoomOut: 'zoom-out',
  fit: 'zoom-scan',
  exportPdf: 'file-type-pdf',
  exportSvg: 'file-type-svg',
  exportDxf: 'file-vector',
  patternsTab: 'files',
  piecesTab: 'puzzle',
  infoTab: 'id-badge',
  notesTab: 'notes',
  outputTab: 'printer',
  problemsTab: 'alert-triangle',
} as const;

// The Problems tab's keys, as the desktop's: what a problem names
const PLACEMENT_KEY = 'placement:';
const NOTE_KEY = 'note:';

// The layout's exports, as the engine names them, with their files' types
const EXPORTS = [
  { format: 'pdf', extension: '.pdf', type: 'application/pdf' },
  { format: 'svg', extension: '.svg', type: 'image/svg+xml' },
  { format: 'dxf', extension: '.dxf', type: 'application/dxf' },
] as const;

function element<T extends HTMLElement>(id: string, type: new () => T): T {
  const found = document.getElementById(id);
  if (!(found instanceof type)) {
    throw new Error(`the page has no #${id}`);
  }
  return found;
}

const toolbar = element('toolbar', HTMLElement);
const message = element('message', HTMLElement);
const problemCount = element('problem-count', HTMLElement);
const openInput = element('open-input', HTMLInputElement);
const previewElement = element('preview', HTMLCanvasElement);
const sideElement = element('side', HTMLElement);

function showMessage(text: string): void {
  message.textContent = text;
}

function showFailure(error: unknown): void {
  showMessage(STRINGS.failed(error instanceof Error ? error.message : String(error)));
  console.error(error);
}

function iconButton(icon: string, caption: string, hint: string, action: () => void): HTMLButtonElement {
  const button = document.createElement('button');
  button.type = 'button';
  button.title = hint;
  const image = document.createElement('img');
  image.src = `icons/${icon}.svg`;
  image.alt = '';
  const label = document.createElement('span');
  label.textContent = caption;
  button.append(image, label);
  button.addEventListener('click', action);
  return button;
}

function hasExtension(file: File, extension: string): boolean {
  return file.name.toLowerCase().endsWith(extension);
}

function divider(): HTMLElement {
  const line = document.createElement('span');
  line.className = 'divider';
  return line;
}

function bytesOf(base64: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}

class PublishApp {
  private readonly document: LayoutDocument;
  private readonly preview: PreviewCanvas;
  private readonly side: SideTabs;
  private readonly patterns: PatternsTab;
  private readonly pieces: PiecesTab;
  private readonly info: InfoTab;
  private readonly notes: NotesTab;
  private readonly output: OutputTab;
  private readonly problems: ProblemsPanel;
  private readonly buttons = new Map<string, HTMLButtonElement>();

  constructor(engine: Engine) {
    this.document = new LayoutDocument(engine);
    this.preview = new PreviewCanvas(previewElement, this.document, {
      selectionChanged: (placement) => {
        document.body.dataset.selected = String(placement);
        this.showPieces();
      },
      // A note picked on the pages opens its details, as on the desktop
      noteChanged: (note) => {
        document.body.dataset.note = String(note);
        this.notes.choose(note);
        if (note >= 0) {
          this.side.open('notes');
        }
      },
      dropCopy: (index, at) => {
        this.run(this.placeCopy(index, at));
      },
      failed: showFailure,
    });
    this.side = new SideTabs(sideElement, window.matchMedia('(max-width: 640px)').matches);
    // In the desktop's order: patterns in, pieces placed, then output
    this.patterns = new PatternsTab(this.document, { message: showMessage, failed: showFailure });
    this.side.addSection('patterns', STRINGS.tabPatterns, ICONS.patternsTab, this.patterns);
    this.pieces = new PiecesTab({
      turn: () => {
        this.run(this.editSelected('publish_turn'));
      },
      flip: () => {
        this.run(this.editSelected('publish_flip'));
      },
      unplace: () => {
        this.run(this.unplace());
      },
      placeNew: () => {
        this.run(this.placeNew());
      },
      pack: () => {
        this.run(this.pack());
      },
      placeCopy: (index) => {
        this.run(this.placeCopy(index));
      },
    });
    this.side.addSection('pieces', STRINGS.tabPieces, ICONS.piecesTab, this.pieces);
    this.info = new InfoTab(this.document, { failed: showFailure });
    this.side.addSection('info', STRINGS.tabInfo, ICONS.infoTab, this.info);
    this.notes = new NotesTab(this.document, {
      added: (note) => {
        this.preview.selectedNote = note;
        this.notes.focusText();
      },
      deleted: () => {
        this.preview.selectedNote = -1;
      },
      message: showMessage,
      failed: showFailure,
    });
    this.side.addSection('notes', STRINGS.tabNotes, ICONS.notesTab, this.notes);
    this.output = new OutputTab(this.document, {
      changed: () => {
        this.preview.zoomToFit();
      },
      message: showMessage,
      export: (format) => {
        this.run(this.export(format));
      },
      failed: showFailure,
    });
    // Last of the tabs, as on the desktop, where it sits just above Problems
    this.side.addSection('output', STRINGS.tabOutput, ICONS.outputTab, this.output);
    this.problems = new ProblemsPanel({
      choose: (key) => {
        if (key.startsWith(PLACEMENT_KEY)) {
          this.preview.selected = Number(key.slice(PLACEMENT_KEY.length));
        } else if (key.startsWith(NOTE_KEY)) {
          this.preview.selectedNote = Number(key.slice(NOTE_KEY.length));
        }
      },
      hover: () => undefined,
      zoom: () => undefined,
    });
    // At the foot of the column, as in every app
    this.side.addSection('problems', STRINGS.tabProblems, ICONS.problemsTab, this.problems, true);
  }

  // A toolbar button, kept by name to enable and disable
  private button(name: keyof typeof ICONS, caption: string, hint: string, action: () => void): HTMLButtonElement {
    const made = iconButton(ICONS[name], caption, hint, action);
    this.buttons.set(name, made);
    return made;
  }

  start(): void {
    // In the desktop's order
    toolbar.append(
      this.button('open', STRINGS.open, STRINGS.publishOpenHint, () => {
        if (!this.document.state.modified || window.confirm(STRINGS.layoutDiscardChanges)) {
          openInput.click();
        }
      }),
      this.button('save', STRINGS.save, STRINGS.layoutSaveHint, () => {
        this.run(this.save());
      }),
      divider(),
      this.button('undo', STRINGS.undo, STRINGS.undoHint, () => {
        this.run(this.document.undo());
      }),
      this.button('redo', STRINGS.redo, STRINGS.redoHint, () => {
        this.run(this.document.redo());
      }),
      divider(),
      this.button('zoomIn', STRINGS.zoomIn, STRINGS.zoomInHint, () => {
        this.preview.zoomIn();
      }),
      this.button('zoomOut', STRINGS.zoomOut, STRINGS.zoomOutHint, () => {
        this.preview.zoomOut();
      }),
      this.button('fit', STRINGS.fitPages, STRINGS.fitPagesHint, () => {
        this.preview.zoomToFit();
      }),
      divider(),
      this.button('exportPdf', STRINGS.exportPdf, STRINGS.exportPdfHint, () => {
        this.run(this.export(0));
      }),
      this.button('exportSvg', STRINGS.exportSvg, STRINGS.exportSvgHint, () => {
        this.run(this.export(1));
      }),
      this.button('exportDxf', STRINGS.exportDxf, STRINGS.exportDxfHint, () => {
        this.run(this.export(2));
      }),
    );
    openInput.addEventListener('change', () => {
      this.run(this.openFiles([...(openInput.files ?? [])]));
      openInput.value = '';
    });
    problemCount.addEventListener('click', () => {
      if (this.problems.count > 0) {
        this.side.open('problems');
      }
    });
    this.document.addListener(() => {
      this.showState();
    });
    window.addEventListener('beforeunload', (event) => {
      if (this.document.state.modified) {
        event.preventDefault();
      }
    });
    this.showState();
  }

  // The layout's base name, for the files it is saved and exported as
  private baseName(): string {
    return this.document.fileName.replace(/\.[^.]*$/, '');
  }

  private async save(): Promise<void> {
    const name = `${this.baseName()}${LAYOUT_EXTENSION}`;
    downloadText(name, await this.document.save());
    showMessage(STRINGS.downloaded(name));
  }

  // Turn or Flip, for the piece selected on the pages
  private async editSelected(method: string): Promise<void> {
    const placement = this.preview.selected;
    if (placement >= 0) {
      await this.document.call(method, { placement });
    }
  }

  // Back to the tray, so nothing stays selected, as on the desktop
  private async unplace(): Promise<void> {
    const placement = this.preview.selected;
    if (placement >= 0) {
      this.preview.selected = -1;
      await this.document.call('publish_unplace', { placement });
    }
  }

  // One copy from the tray, selected once placed: dropped at a point of the
  // pages, or else in the rows below the others
  private async placeCopy(index: number, at?: Vec2): Promise<void> {
    if (this.document.state.tray[index]?.canPlace !== true) {
      showMessage(STRINGS.cannotPlace);
      return;
    }
    const answer =
      at === undefined
        ? await this.document.call('publish_place_copy', { index })
        : await this.document.call('publish_drop_copy', { index, x: at.x, y: at.y });
    this.preview.selected = numberField(answer, 'placed') ?? -1;
  }

  private async placeNew(): Promise<void> {
    const answer = await this.document.call('publish_place_pieces');
    showMessage(STRINGS.placedNew(numberField(answer, 'placed') ?? 0));
  }

  // As the desktop's Pack: fitted afterwards, with what it did in the status bar
  private async pack(): Promise<void> {
    const answer = await this.document.call('publish_pack');
    if (booleanField(answer, 'done') !== true) {
      showMessage(stringField(answer, 'reason') ?? '');
      return;
    }
    this.preview.zoomToFit();
    const count = numberField(answer, 'count') ?? 0;
    const pages = numberField(answer, 'pages') ?? 0;
    const leftOut = numberField(answer, 'leftOut') ?? 0;
    const summary = pages > 1 ? STRINGS.packedPages(count, pages) : STRINGS.packed(count);
    showMessage(leftOut > 0 ? STRINGS.packLeftOut(summary, leftOut) : summary);
  }

  private async export(which: number): Promise<void> {
    const kind = EXPORTS[which];
    if (kind === undefined) {
      return;
    }
    const answer = await this.document.read('publish_export', { format: kind.format });
    const name = `${this.baseName()}${kind.extension}`;
    downloadBlob(name, new Blob([bytesOf(stringField(answer, 'base64') ?? '')], { type: kind.type }));
    showMessage(STRINGS.downloaded(name));
  }

  private run(pending: Promise<void>): void {
    pending.catch(showFailure);
  }

  // A layout among the files is opened with the rest as its sources' files;
  // otherwise the first pattern starts a layout, as on the desktop
  private async openFiles(chosen: File[]): Promise<void> {
    const layout = chosen.find((file) => hasExtension(file, LAYOUT_EXTENSION));
    const pattern = chosen.find((file) => hasExtension(file, PATTERN_EXTENSION));
    if (layout === undefined && pattern === undefined) {
      if (chosen[0] !== undefined) {
        showMessage(STRINGS.notALayout(chosen[0].name));
      }
      return;
    }
    const files = new Map<string, string>();
    for (const file of chosen) {
      if (file !== layout) {
        // oxlint-disable-next-line no-await-in-loop
        files.set(file.name, await file.text());
      }
    }
    if (layout === undefined) {
      // Only a pattern was chosen, so there is one
      const name = pattern?.name ?? '';
      await this.document.open(files, { pattern: name });
      this.document.fileName = name.replace(/\.[^.]*$/, LAYOUT_EXTENSION);
      this.showState(STRINGS.layoutStarted(name));
    } else {
      await this.document.open(files, { layout: await layout.text() });
      this.document.fileName = layout.name;
      this.showState(STRINGS.layoutOpened(layout.name));
    }
  }

  private showState(opened?: string): void {
    const state = this.document.state;
    const name = state.name || this.document.fileName;
    const mark = state.modified ? `${STRINGS.modifiedMark} ` : '';
    document.title = name === '' ? STRINGS.publishName : `${mark}${name} — ${STRINGS.publishName}`;
    this.enableCommands();
    if (state.missing.length > 0) {
      showMessage(STRINGS.layoutNeedsFiles(state.missing));
    } else if (opened !== undefined) {
      showMessage(opened);
    } else if (this.document.fileName !== '') {
      // As the desktop's, after every change; a command's own message follows
      showMessage(state.summary);
    }
    const blocking = state.problems.filter((problem) => problem.blocking).length;
    if (this.document.fileName === '') {
      problemCount.textContent = '';
    } else if (state.problems.length === 0) {
      problemCount.textContent = STRINGS.noProblems;
    } else if (blocking === 0) {
      problemCount.textContent = STRINGS.problemCount(state.problems.length);
    } else {
      problemCount.textContent = STRINGS.problemCountBlocking(state.problems.length, blocking);
    }
    problemCount.title = state.problems.length > 0 ? STRINGS.problemsHint : '';
    this.showPieces();
    this.showProblems();
  }

  private showPieces(): void {
    this.pieces.show(this.document.state, this.preview.selected, this.document.fileName !== '');
  }

  // The Problems tab, each keyed by the placement or note it names
  private showProblems(): void {
    const problems = this.document.state.problems;
    this.problems.setProblems(
      problems.map((problem) => ({
        key:
          problem.placement >= 0
            ? `${PLACEMENT_KEY}${String(problem.placement)}`
            : problem.note >= 0
              ? `${NOTE_KEY}${String(problem.note)}`
              : '',
        text: problem.text,
        blocking: problem.blocking,
      })),
    );
    this.side.setCount('problems', problems.length);
    this.side.setCaption(
      'problems',
      problems.length === 0 ? STRINGS.tabProblems : STRINGS.tabProblemsCount(problems.length),
    );
  }

  private enableCommands(): void {
    const state = this.document.state;
    const open = this.document.fileName !== '';
    const blocked = state.problems.some((problem) => problem.blocking);
    const enabled: Record<string, boolean> = {
      save: open,
      undo: state.canUndo,
      redo: state.canRedo,
      exportPdf: open && !blocked,
      exportSvg: open && !blocked,
      exportDxf: open && !blocked,
    };
    for (const [name, on] of Object.entries(enabled)) {
      const button = this.buttons.get(name);
      if (button !== undefined) {
        button.disabled = !on;
      }
    }
    this.output.setExportsEnabled(open && !blocked);
    const undo = this.buttons.get('undo');
    if (undo !== undefined) {
      undo.title = state.canUndo ? STRINGS.undoStep(state.undo) : STRINGS.undoHint;
    }
  }
}

async function main(): Promise<void> {
  showMessage(STRINGS.loading);
  const { engine } = await Engine.start(
    new URL('./worker.js', import.meta.url),
    new URL('./engine_lib.wasm', import.meta.url),
  );
  new PublishApp(engine).start();
  showMessage('');
  document.body.dataset.ready = 'true';
}

main().catch(showFailure);
