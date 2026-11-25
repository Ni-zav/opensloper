// The web Publish app, as Sloper.Publish.MainForm: starts the engine and opens
// a layout with its patterns and measurement files, or patterns to start a
// layout, as the desktop's Open does. The preview shows its pages and pieces;
// the toolbar saves, undoes, places and packs, and exports, each file a
// download; the side panel has the Problems tab at its foot. The title names
// the layout, and the status bar has a message and the count of problems,
// which opens the Problems tab. Nothing leaves the
// machine: the files are read in the browser and given to the engine as text.
import { LayoutDocument } from '../document/layoutDocument.ts';
import { Engine } from '../engine/engine.ts';
import { booleanField, numberField, stringField } from '../engine/replies.ts';
import { downloadBlob, downloadText } from '../ui/download.ts';
import { PreviewCanvas } from '../ui/previewCanvas.ts';
import { ProblemsPanel } from '../ui/problemsPanel.ts';
import { SideTabs } from '../ui/sideTabs.ts';
import { STRINGS } from '../ui/strings.ts';

const LAYOUT_EXTENSION = '.slayout';
const PATTERN_EXTENSION = '.sloper';

// The desktop's icons for the toolbar's commands (APP_ICON_NAMES); Place and
// Pack have none there, being buttons on the Pieces tab
const ICONS = {
  open: 'folder-open',
  save: 'device-floppy',
  undo: 'arrow-back-up',
  redo: 'arrow-forward-up',
  zoomIn: 'zoom-in',
  zoomOut: 'zoom-out',
  fit: 'zoom-scan',
  place: 'stack-front',
  pack: 'puzzle',
  exportPdf: 'file-type-pdf',
  exportSvg: 'file-type-svg',
  exportDxf: 'file-vector',
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
  private readonly problems: ProblemsPanel;
  private readonly buttons = new Map<string, HTMLButtonElement>();

  constructor(engine: Engine) {
    this.document = new LayoutDocument(engine);
    this.preview = new PreviewCanvas(previewElement, this.document, {
      selectionChanged: (placement) => {
        document.body.dataset.selected = String(placement);
      },
      failed: showFailure,
    });
    this.side = new SideTabs(sideElement, window.matchMedia('(max-width: 640px)').matches);
    this.problems = new ProblemsPanel({
      // A sheet note is chosen once the preview shows notes
      choose: (key) => {
        if (key.startsWith(PLACEMENT_KEY)) {
          this.preview.selected = Number(key.slice(PLACEMENT_KEY.length));
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
      this.button('place', STRINGS.placeNew, STRINGS.placeNewHint, () => {
        this.run(this.placeNew());
      }),
      this.button('pack', STRINGS.packPieces, STRINGS.packPiecesHint, () => {
        this.run(this.pack());
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
    this.showProblems();
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
      place: state.unplaced > 0,
      pack: state.placed + state.unplaced > 0,
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
