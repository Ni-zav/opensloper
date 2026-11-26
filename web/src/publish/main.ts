// The web Publish app, as Sloper.Publish.MainForm: starts the engine and opens
// a layout with its patterns and measurement files, or patterns to start a
// layout, as the desktop's Open does. The preview shows its pages and pieces;
// the toolbar saves, undoes, prints (the PDF in the browser's viewer) and
// exports, each file a download; Machine DXF stays a desktop export. The side
// panel has the Pieces tab, which turns, flips and unplaces the selected
// piece, places and packs, and holds the tray, and the Problems tab at its
// foot. The title names the layout, and the status bar has a message and the
// count of problems, which opens the Problems tab. Nothing leaves the
// machine: the files are read in the browser and given to the engine as text.
import { LayoutDocument } from '../document/layoutDocument.ts';
import { Autosave, type Work } from '../ui/autosave.ts';
import { FileAccess, LAYOUT_EXTENSION, PATTERN_EXTENSION } from '../ui/fileAccess.ts';
import { keepOffline } from '../ui/offline.ts';
import type { Vec2 } from '../editor/view.ts';
import { Engine } from '../engine/engine.ts';
import { booleanField, numberField, recordsField, stringField } from '../engine/replies.ts';
import { baseName, downloadBlob, downloadText } from '../ui/download.ts';
import { PreviewCanvas } from '../ui/previewCanvas.ts';
import { ProblemsPanel } from '../ui/problemsPanel.ts';
import { SideTabs } from '../ui/sideTabs.ts';
import { matchesShortcut, parseShortcut, shortcutText } from '../ui/shortcuts.ts';
import { STRINGS } from '../ui/strings.ts';
import { InfoTab } from './infoTab.ts';
import { MaterialsTab } from './materialsTab.ts';
import { NotesTab } from './notesTab.ts';
import { OutputTab } from './outputTab.ts';
import { PatternsTab } from './patternsTab.ts';
import { PrintDialog } from './printDialog.ts';
import { PiecesTab } from './piecesTab.ts';

// The desktop's icons for the toolbar's commands and the side panel's tabs
// (APP_ICON_NAMES)
const ICONS = {
  open: 'folder-open',
  save: 'device-floppy',
  saveAs: 'file-pencil',
  undo: 'arrow-back-up',
  redo: 'arrow-forward-up',
  zoomIn: 'zoom-in',
  zoomOut: 'zoom-out',
  fit: 'zoom-scan',
  zoomArea: 'zoom-in-area',
  print: 'printer',
  exportPdf: 'file-type-pdf',
  exportSvg: 'file-type-svg',
  exportDxf: 'file-vector',
  patternsTab: 'files',
  piecesTab: 'puzzle',
  materialsTab: 'texture',
  infoTab: 'id-badge',
  notesTab: 'notes',
  outputTab: 'printer',
  problemsTab: 'alert-triangle',
} as const;

// The names of the texts kept as work in progress: the layout's, and each
// file its sources were given, by its path
const WORK_LAYOUT = 'layout';
const WORK_FILE = 'file:';
// And of the files it came from
const WORK_LAYOUT_HANDLE = 'layout';
const WORK_SOURCES_HANDLE = 'sources';

// The Problems tab's keys, as the desktop's: what a problem names
const PLACEMENT_KEY = 'placement:';
const NOTE_KEY = 'note:';

// The layout's exports, as the engine names them, with their files' types
const EXPORTS = [
  { format: 'pdf', extension: '.pdf', type: 'application/pdf' },
  { format: 'svg', extension: '.svg', type: 'image/svg+xml' },
  { format: 'dxf', extension: '.dxf', type: 'application/dxf' },
] as const;

// The toolbar's buttons that keys work, by the engine's names for the
// commands (publish_tables); the keys click the button, so they do nothing
// while it is disabled.
const KEY_BUTTONS: [command: string, button: string][] = [
  ['open', 'open'],
  ['save', 'save'],
  ['saveAs', 'saveAs'],
  ['print', 'print'],
  ['exportPDF', 'exportPdf'],
  ['undo', 'undo'],
  ['redo', 'redo'],
  ['zoomIn', 'zoomIn'],
  ['zoomOut', 'zoomOut'],
  ['fit', 'fit'],
  ['toolZoom', 'zoomArea'],
];
// Commands left to a field being typed in, which has its own
const FIELD_COMMANDS = new Set(['undo', 'redo', 'toolZoom']);

// Whether keys go to what has the focus: a field, a list or a choice
function typingIn(target: EventTarget | null): boolean {
  return (
    target instanceof HTMLInputElement ||
    target instanceof HTMLTextAreaElement ||
    target instanceof HTMLSelectElement ||
    (target instanceof HTMLElement && target.isContentEditable)
  );
}

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

// A message with buttons after it, as the design page's
function showActions(text: string, actions: [caption: string, action: () => void][]): void {
  message.replaceChildren(text);
  for (const [caption, action] of actions) {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = caption;
    button.addEventListener('click', action);
    message.append(' ', button);
  }
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
  private readonly materials: MaterialsTab;
  private readonly info: InfoTab;
  private readonly notes: NotesTab;
  private readonly output: OutputTab;
  private readonly printDialog: PrintDialog;
  private readonly problems: ProblemsPanel;
  private readonly buttons = new Map<string, HTMLButtonElement>();

  // Each command's keys, as Mod+Z, from the engine's tables
  private readonly shortcuts: ReadonlyMap<string, string>;
  // Where the browser lets files be opened and saved in place
  private readonly files = FileAccess.create();
  // The layout's file, once opened from one or saved to one; Save writes it
  private layoutHandle: FileSystemFileHandle | undefined;
  // The file the paths the layout's sources record start from: the layout's,
  // or the pattern a new layout was started for
  private sourcesHandle: FileSystemFileHandle | undefined;
  private saving = false;
  private readonly autosave: Autosave;
  // A layout started for a pattern whose files were not all chosen: once
  // they are found, it is started again with them, so every piece is placed
  private started: { pattern: string; files: Map<string, string> } | undefined;

  constructor(engine: Engine, shortcuts: ReadonlyMap<string, string>) {
    this.shortcuts = shortcuts;
    this.document = new LayoutDocument(engine);
    this.autosave = new Autosave(
      'publish',
      this.document,
      async () => this.snapshot(),
      () => ({
        fileName: this.document.fileName,
        handles: { [WORK_LAYOUT_HANDLE]: this.layoutHandle, [WORK_SOURCES_HANDLE]: this.sourcesHandle },
      }),
      (kept) => {
        // For the tests
        document.body.dataset.workKept = String(kept);
      },
    );
    this.preview = new PreviewCanvas(previewElement, this.document, {
      selectionChanged: (placement) => {
        document.body.dataset.selected = String(placement);
        this.showPieces();
      },
      // A note picked on the pages opens its details, as on the desktop
      zoomAreaChanged: (on) => {
        const button = this.buttons.get('zoomArea');
        button?.classList.toggle('chosen', on);
        button?.setAttribute('aria-pressed', String(on));
        showMessage(on ? STRINGS.zoomAreaStatus : this.document.state.summary);
      },
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
    this.materials = new MaterialsTab(this.document, { failed: showFailure });
    this.side.addSection('materials', STRINGS.tabMaterials, ICONS.materialsTab, this.materials);
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
      print: () => {
        this.printDialog.open();
      },
      failed: showFailure,
    });
    this.printDialog = new PrintDialog(this.document, {
      baseName: () => this.baseName(),
      message: showMessage,
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

  // A command's hint with its keys, when it has some
  private hint(text: string, command: string): string {
    const keys = this.shortcuts.get(command) ?? '';
    return keys === '' ? text : STRINGS.withShortcut(text, shortcutText(keys));
  }

  // A toolbar button, kept by name to enable and disable; its hint names the
  // keys of the command it is for
  private button(name: keyof typeof ICONS, caption: string, hint: string, action: () => void): HTMLButtonElement {
    const command = KEY_BUTTONS.find(([, button]) => button === name)?.[0] ?? '';
    const made = iconButton(ICONS[name], caption, this.hint(hint, command), action);
    this.buttons.set(name, made);
    return made;
  }

  // The layout's text and every file its sources were given, as work in progress
  private async snapshot(): Promise<Map<string, string>> {
    const answer = await this.document.read('publish_snapshot');
    const texts = new Map([[WORK_LAYOUT, stringField(answer, 'layout') ?? '']]);
    for (const file of recordsField(answer, 'files')) {
      texts.set(`${WORK_FILE}${stringField(file, 'path') ?? ''}`, stringField(file, 'text') ?? '');
    }
    return texts;
  }

  // The newest work a closed tab left, to open again or drop; then the next
  private async offerLeftOver(): Promise<void> {
    const [work] = await this.autosave.leftOver();
    if (work === undefined) {
      return;
    }
    const name = work.fileName === '' ? STRINGS.untitled : work.fileName;
    showActions(STRINGS.workLeftOver(name, new Date(work.time).toLocaleString()), [
      [
        STRINGS.workOpen,
        () => {
          this.run(this.openWork(work));
        },
      ],
      [
        STRINGS.workDiscard,
        () => {
          // Cleared once it is gone, then the next is offered
          this.run(
            this.autosave.discard(work).then(async () => {
              showMessage('');
              return this.offerLeftOver();
            }),
          );
        },
      ],
    ]);
  }

  // The layout as it was, with the files its sources read, counted not saved;
  // it still saves to the file it came from
  private async openWork(work: Work): Promise<void> {
    if (this.document.state.modified && !window.confirm(STRINGS.layoutDiscardChanges)) {
      return;
    }
    const texts = await this.autosave.texts(work);
    const files = new Map<string, string>();
    for (const [name, text] of texts) {
      if (name.startsWith(WORK_FILE)) {
        files.set(name.slice(WORK_FILE.length), text);
      }
    }
    await this.document.open(files, { layout: texts.get(WORK_LAYOUT) ?? '' });
    this.layoutHandle = work.handles[WORK_LAYOUT_HANDLE];
    this.sourcesHandle = work.handles[WORK_SOURCES_HANDLE];
    this.started = undefined;
    this.document.fileName = work.fileName;
    await this.document.call('publish_mark_unsaved');
    await this.autosave.discard(work);
    showMessage(STRINGS.workOpened(work.fileName === '' ? STRINGS.untitled : work.fileName));
  }

  start(): void {
    // In the desktop's order
    toolbar.append(
      this.button('open', STRINGS.open, STRINGS.publishOpenHint, () => {
        if (!this.document.state.modified || window.confirm(STRINGS.layoutDiscardChanges)) {
          this.open();
        }
      }),
      this.button(
        'save',
        STRINGS.save,
        this.files === undefined ? STRINGS.layoutSaveHint : STRINGS.layoutSaveToFileHint,
        () => {
          this.run(this.save(false));
        },
      ),
      // A download asks where to put it anyway
      ...(this.files === undefined
        ? []
        : [
            this.button('saveAs', STRINGS.saveAs, STRINGS.layoutSaveAsHint, () => {
              this.run(this.save(true));
            }),
          ]),
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
      this.button('zoomArea', STRINGS.zoomArea, STRINGS.zoomAreaHint, () => {
        this.preview.zoomArea = !this.preview.zoomArea;
      }),
      divider(),
      this.button('print', STRINGS.print, STRINGS.layoutPrintHint, () => {
        this.printDialog.open();
      }),
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
      this.run(this.openFiles([...(openInput.files ?? [])].map((file) => ({ file, handle: undefined }))));
      openInput.value = '';
    });
    window.addEventListener('keydown', (event) => {
      this.keyDown(event);
    });
    window.addEventListener('keyup', (event) => {
      if (event.key === ' ') {
        this.preview.panKeyDown = false;
      }
    });
    window.addEventListener('blur', () => {
      this.preview.panKeyDown = false;
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
    this.autosave.start();
    // Offline use is a convenience: the app runs without it
    keepOffline(toolbar, async () => this.autosave.flush(), showFailure).catch((error: unknown) => {
      console.warn('not kept for offline use', error);
    });
    this.run(this.offerLeftOver());
  }

  // The layout's base name, for the files it is saved and exported as
  private baseName(): string {
    return this.document.fileName.replace(/\.[^.]*$/, '');
  }

  // With File System Access, the files are chosen in the browser's picker,
  // starting where the layout is, so they can be saved back to
  private open(): void {
    const files = this.files;
    if (files === undefined) {
      openInput.click();
      return;
    }
    this.run(
      files
        .openLayout(this.sourcesHandle)
        .then(async (handles) =>
          this.openFiles(await Promise.all(handles.map(async (handle) => ({ file: await handle.getFile(), handle })))),
        ),
    );
  }

  // Writes the layout to its file, or one the user chooses for a new one or
  // with Save As; without File System Access it is downloaded, and the
  // browser asks where or puts it in Downloads. Only the text written counts
  // as saved, so a change made meanwhile keeps the layout modified.
  private async save(saveAs: boolean): Promise<void> {
    const name = `${this.baseName()}${LAYOUT_EXTENSION}`;
    const files = this.files;
    if (files === undefined) {
      downloadText(name, await this.document.save());
      showMessage(STRINGS.downloaded(name));
      return;
    }
    if (this.saving) {
      return;
    }
    this.saving = true;
    const generation = this.document.generation;
    try {
      // Leave to write is asked while the click still counts
      let handle = saveAs ? undefined : this.layoutHandle;
      if (handle !== undefined && !(await files.mayWrite(handle))) {
        showMessage(STRINGS.writeRefused(handle.name));
        return;
      }
      handle ??= await files.chooseSave(name, 'layout', this.sourcesHandle);
      if (handle === undefined || this.document.generation !== generation) {
        return;
      }
      const text = await this.document.text();
      if (!(await files.write(handle, text))) {
        showMessage(STRINGS.writeRefused(handle.name));
        return;
      }
      await this.document.saved(text);
      this.layoutHandle = handle;
      this.sourcesHandle = handle;
      this.document.fileName = handle.name;
      this.showState();
      showMessage(STRINGS.saved(handle.name));
    } finally {
      this.saving = false;
    }
  }

  // The files the sources still need, found by their paths from the layout
  // in a folder the user has granted, as the design page finds a pattern's
  // measurement file. Ask lets it ask for leave, or for the folder, which
  // needs a click the user has just made.
  private async findSources(ask: boolean): Promise<void> {
    const files = this.files;
    const from = this.sourcesHandle;
    if (files === undefined || from === undefined) {
      return;
    }
    // Every file found, by name, for a layout started again
    const allFound = new Map<string, string>();
    const search = async (askNow: boolean): Promise<{ found: Map<string, string>; needsLeave: boolean }> => {
      const found = new Map<string, string>();
      let needsLeave = false;
      for (const path of this.document.state.missing) {
        // One after another: each may ask the user
        // oxlint-disable-next-line no-await-in-loop
        const result = await files.findBeside(from, path, askNow);
        if (result.file !== undefined) {
          // oxlint-disable-next-line no-await-in-loop
          found.set(path, await (await result.file.getFile()).text());
        } else if (result.needsLeave !== undefined) {
          needsLeave = true;
        }
      }
      return { found, needsLeave };
    };
    // A pattern found may name a measurement file, looked for in the next round
    let askNow = ask;
    while (this.document.state.missing.length > 0 && this.sourcesHandle === from) {
      // Each round needs the files the one before found
      // oxlint-disable-next-line no-await-in-loop
      let result = await search(askNow);
      if (askNow && result.found.size === 0 && !result.needsLeave) {
        // oxlint-disable-next-line no-await-in-loop
        if ((await files.grantFolder(from)) === undefined) {
          break;
        }
        // oxlint-disable-next-line no-await-in-loop
        result = await search(false);
      }
      if (result.found.size === 0 || this.sourcesHandle !== from) {
        break;
      }
      for (const [path, text] of result.found) {
        allFound.set(baseName(path), text);
      }
      // oxlint-disable-next-line no-await-in-loop
      await this.document.giveFiles(result.found);
      // Leave was given in this round, or the folder granted
      askNow = false;
    }
    await this.startAgain(allFound);
    if (this.document.state.missing.length > 0 && this.sourcesHandle === from) {
      this.offerFind();
    }
  }

  // A new layout untouched since it was started is started again with the
  // files found, as the desktop's would have read them all at once
  private async startAgain(found: ReadonlyMap<string, string>): Promise<void> {
    const started = this.started;
    const state = this.document.state;
    if (started === undefined || found.size === 0 || state.missing.length > 0 || state.canUndo) {
      return;
    }
    const files = new Map([...started.files, ...found]);
    this.started = { pattern: started.pattern, files };
    const generation = this.document.generation;
    await this.document.open(files, { pattern: started.pattern });
    if (this.document.generation === generation + 1) {
      this.document.fileName = started.pattern.replace(/\.[^.]*$/, LAYOUT_EXTENSION);
      this.showState(STRINGS.layoutStarted(started.pattern));
    }
  }

  private offerFind(): void {
    showActions(STRINGS.layoutFindFiles(this.document.state.missing), [
      [
        STRINGS.layoutFindFilesButton,
        () => {
          this.run(this.findSources(true));
        },
      ],
    ]);
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
  // otherwise the first pattern starts a layout, as on the desktop. The file
  // it came from, when the browser gives it, is where Save writes, and where
  // the files the sources still need are looked for.
  private async openFiles(chosen: { file: File; handle: FileSystemFileHandle | undefined }[]): Promise<void> {
    const layout = chosen.find((each) => hasExtension(each.file, LAYOUT_EXTENSION));
    const pattern = chosen.find((each) => hasExtension(each.file, PATTERN_EXTENSION));
    if (layout === undefined && pattern === undefined) {
      if (chosen[0] !== undefined) {
        showMessage(STRINGS.notALayout(chosen[0].file.name));
      }
      return;
    }
    const files = new Map<string, string>();
    for (const each of chosen) {
      if (each !== layout) {
        // oxlint-disable-next-line no-await-in-loop
        files.set(each.file.name, await each.file.text());
      }
    }
    if (layout === undefined) {
      // Only a pattern was chosen, so there is one; the new layout has no file yet
      const name = pattern?.file.name ?? '';
      await this.document.open(files, { pattern: name });
      this.layoutHandle = undefined;
      this.sourcesHandle = pattern?.handle;
      this.started = { pattern: name, files };
      this.document.fileName = name.replace(/\.[^.]*$/, LAYOUT_EXTENSION);
      this.showState(STRINGS.layoutStarted(name));
    } else {
      await this.document.open(files, { layout: await layout.file.text() });
      this.layoutHandle = layout.handle;
      this.sourcesHandle = layout.handle;
      this.started = undefined;
      this.document.fileName = layout.file.name;
      this.showState(STRINGS.layoutOpened(layout.file.name));
    }
    // Reading a folder the browser has not let the page read since it was
    // granted needs a click on the button offered
    if (this.document.state.missing.length > 0 && this.sourcesHandle !== undefined) {
      await this.findSources(false);
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
      saveAs: open,
      undo: state.canUndo,
      redo: state.canRedo,
      zoomArea: open,
      print: open && !blocked,
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
      undo.title = this.hint(state.canUndo ? STRINGS.undoStep(state.undo) : STRINGS.undoHint, 'undo');
    }
  }

  // Whether the key press is the command's, as the engine's tables give it
  private matches(event: KeyboardEvent, command: string): boolean {
    const shortcut = parseShortcut(this.shortcuts.get(command) ?? '');
    return shortcut !== undefined && matchesShortcut(event, shortcut);
  }

  // The toolbar's keys work from anywhere but a field's own; the preview's
  // keys (Delete, Escape, Space) only away from fields, as the desktop's
  // work while the preview has the focus
  private keyDown(event: KeyboardEvent): void {
    // A modal dialog takes the keys it wants itself, and the window none
    if (document.querySelector('dialog[open]') !== null) {
      return;
    }
    const typing = typingIn(event.target);
    const found = KEY_BUTTONS.find(
      ([command]) => this.matches(event, command) && !(typing && FIELD_COMMANDS.has(command)),
    );
    if (found !== undefined) {
      event.preventDefault();
      const button = this.buttons.get(found[1]);
      if (button !== undefined && !button.disabled) {
        button.click();
      }
      return;
    }
    if (typing) {
      return;
    }
    if (this.matches(event, 'removePiece') || event.key === 'Backspace') {
      event.preventDefault();
      this.preview.removeSelected();
    } else if (this.matches(event, 'clearSelection')) {
      this.preview.escape();
    } else if (event.key === ' ') {
      // Space with a drag pans, so it does not scroll the page
      event.preventDefault();
      this.preview.panKeyDown = true;
    }
  }
}

async function main(): Promise<void> {
  showMessage(STRINGS.loading);
  const { engine } = await Engine.start(
    new URL('./worker.js', import.meta.url),
    new URL('./engine_lib.wasm', import.meta.url),
  );
  const tables = await engine.call('publish_tables');
  const shortcuts = new Map(
    recordsField(tables, 'shortcuts').map((record): [string, string] => [
      stringField(record, 'command') ?? '',
      stringField(record, 'keys') ?? '',
    ]),
  );
  new PublishApp(engine, shortcuts).start();
  showMessage('');
  document.body.dataset.ready = 'true';
}

main().catch(showFailure);
