// The web design app, as Sloper.Design.MainForm: starts the engine, builds
// the toolbar and the tools from the engine's tables, opens and saves files
// as text on the user's machine, and passes keys to the canvas. Nothing is
// sent anywhere: the files stay in the browser. Where the browser has File
// System Access (FileAccess) a pattern saves back to the file it came from
// and its measurement file is found beside it; elsewhere files are uploaded
// and downloaded.
import { PatternDocument } from '../document/patternDocument.ts';
import { Engine, EngineError } from '../engine/engine.ts';
import { booleanField, idsField, numberField, stringField } from '../engine/replies.ts';
import { parseTables, type Tables } from '../editor/scene.ts';
import { LABEL_MODES, PatternCanvas, SELECT_TOOL, type LabelMode } from '../ui/canvas.ts';
import type { ListPanelEvents } from '../ui/listPanel.ts';
import { baseName, downloadText } from '../ui/download.ts';
import { Autosave, type Work } from '../ui/autosave.ts';
import { FeaturesPanel } from '../ui/featuresPanel.ts';
import { MaterialsDialog } from '../ui/materialDialog.ts';
import { PrintDialog } from '../ui/printDialog.ts';
import { MaterialsPanel } from '../ui/materialPanel.ts';
import { FileAccess, PATTERN_EXTENSION } from '../ui/fileAccess.ts';
import { MeasurementsPanel } from '../ui/measurementsPanel.ts';
import { ObjectsPanel } from '../ui/objectsPanel.ts';
import { PropertiesPanel } from '../ui/properties.ts';
import { CanvasRulers } from '../ui/ruler.ts';
import { matchesShortcut, parseShortcut } from '../ui/shortcuts.ts';
import { SideTabs } from '../ui/sideTabs.ts';
import { STRINGS } from '../ui/strings.ts';
import { VariablesPanel } from '../ui/variablesPanel.ts';

// The desktop's icons for the toolbar's commands (APP_ICON_NAMES)
const ICONS = {
  open: 'folder-open',
  measurements: 'ruler-measure',
  save: 'device-floppy',
  saveAs: 'file-pencil',
  exportDraft: 'file-type-svg',
  print: 'printer',
  undo: 'arrow-back-up',
  redo: 'arrow-forward-up',
  delete: 'trash',
  cut: 'cut',
  copy: 'copy',
  paste: 'clipboard',
  fit: 'zoom-scan',
  rulers: 'ruler-2',
  // The side panel's tabs
  propertiesTab: 'adjustments-horizontal',
  objectsTab: 'list-tree',
  variablesTab: 'variable',
  measurementsTab: 'ruler-measure',
  featuresTab: 'components',
  materialsTab: 'texture',
} as const;

const DEFAULT_FILE_NAME = 'pattern.sloper';

function element<T extends HTMLElement>(id: string, type: new () => T): T {
  const found = document.getElementById(id);
  if (!(found instanceof type)) {
    throw new Error(`the page has no #${id}`);
  }
  return found;
}

const status = element('status', HTMLElement);
const toolbar = element('toolbar', HTMLElement);
const toolsBar = element('tools', HTMLElement);
const openInput = element('open-input', HTMLInputElement);
const measurementsInput = element('measurements-input', HTMLInputElement);
const importInput = element('import-input', HTMLInputElement);

function showMessage(text: string): void {
  status.textContent = text;
}

// A message with buttons that do something about it, as finding a file
function showActions(text: string, actions: [caption: string, action: () => void][]): void {
  status.replaceChildren(text);
  for (const [caption, action] of actions) {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = caption;
    button.addEventListener('click', action);
    status.append(' ', button);
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

// A field or box that takes keys and the clipboard for itself
function isTextField(target: EventTarget | null): boolean {
  return (
    target instanceof HTMLInputElement ||
    target instanceof HTMLSelectElement ||
    target instanceof HTMLTextAreaElement ||
    (target instanceof HTMLElement && target.isContentEditable)
  );
}

// A file from the site, named as its address ends; undefined when it cannot be had
async function fetchFile(address: URL): Promise<File | undefined> {
  const response = await fetch(address);
  if (!response.ok) {
    return undefined;
  }
  return new File([await response.text()], baseName(address.pathname));
}

class DesignApp {
  private readonly document: PatternDocument;
  private readonly tables: Tables;
  private readonly canvas: PatternCanvas;
  private readonly rulers: CanvasRulers;
  private readonly rulersButton: HTMLButtonElement;
  private readonly objects: ObjectsPanel;
  private readonly variables: VariablesPanel;
  private readonly side: SideTabs;
  private readonly properties: PropertiesPanel;
  private readonly features: FeaturesPanel;
  private readonly materials: MaterialsPanel;
  private readonly materialsDialog: MaterialsDialog;
  private readonly printDialog: PrintDialog;
  private readonly measurements: MeasurementsPanel;
  private readonly toolButtons = new Map<string, HTMLButtonElement>();
  private readonly undoButton: HTMLButtonElement;
  private readonly deleteButton: HTMLButtonElement;
  // Cut, Copy and Delete, which need a selection
  private readonly selectionButtons: HTMLButtonElement[];
  // The fragment last copied, and whether the browser let it onto the
  // clipboard; when it did not, Paste takes it from here
  private copied = '';
  private copiedToClipboard = false;
  private readonly redoButton: HTMLButtonElement;
  // The measurement file the open pattern names, while it has none
  private wantedMeasurements = '';
  // Files in place, where the browser can; the pattern's file and its set's when opened so
  private readonly files = FileAccess.create();
  private patternHandle: FileSystemFileHandle | undefined;
  private measurementsHandle: FileSystemFileHandle | undefined;
  // Unsaved work kept in the browser, and offered back once the tab that left it has closed
  private readonly autosave: Autosave;

  constructor(engine: Engine, tables: Tables) {
    this.document = new PatternDocument(engine);
    this.tables = tables;
    const rulers = new CanvasRulers(element('canvas-host', HTMLElement));
    this.rulers = rulers;
    // As the Delete key; there is nothing to delete until something is selected
    const deleteButton = iconButton(ICONS.delete, STRINGS.delete, STRINGS.deleteHint, () => {
      this.run(this.canvas.deleteSelection());
    });
    this.deleteButton = deleteButton;
    const shortcutOf = (command: string): string => tables.shortcuts.get(command) ?? '';
    const selectionButtons = [
      iconButton(ICONS.cut, STRINGS.cut, STRINGS.cutHint(shortcutOf('cut')), () => {
        this.run(this.copy(true));
      }),
      iconButton(ICONS.copy, STRINGS.copy, STRINGS.copyHint(shortcutOf('copy')), () => {
        this.run(this.copy(false));
      }),
      deleteButton,
    ];
    for (const button of selectionButtons) {
      button.disabled = true;
    }
    this.selectionButtons = selectionButtons;
    this.canvas = new PatternCanvas(element('canvas', HTMLCanvasElement), this.document, tables, {
      message: showMessage,
      selectionChanged: (ids) => {
        document.body.dataset.selection = ids.join(' ');
        for (const button of selectionButtons) {
          button.disabled = ids.length === 0;
        }
        this.objects.showSelection(ids);
        this.properties.showSelection(ids);
        this.features.showSelection(ids);
      },
      failed: showFailure,
      painted: (view, unit) => {
        rulers.showView(view, unit);
      },
      pointerAt: (model) => {
        rulers.showPointer(model);
      },
    });
    this.objects = new ObjectsPanel(this.document, {
      ...this.listEvents(),
      select: (keys) => {
        this.canvas.select([...keys]);
        this.run(this.canvas.revealSelection());
      },
      zoom: () => {
        this.run(this.canvas.zoomToSelection());
      },
      delete: () => {
        this.run(this.canvas.deleteSelection());
      },
    });
    this.properties = new PropertiesPanel(this.document, {
      message: showMessage,
      failed: showFailure,
      suggestChanged: (id, field) => {
        this.canvas.setFieldLock(id, field);
      },
      suggestPreview: (preview) => {
        this.canvas.showSuggestPreview(preview);
      },
      suggestObjects: (ids) => {
        this.canvas.showSuggestionObjects(ids);
      },
      noteText: (id, text) => {
        this.canvas.showNoteText(id, text);
      },
    });
    const side = new SideTabs(element('side', HTMLElement));
    this.side = side;
    this.variables = new VariablesPanel(this.document, {
      ...this.listEvents(),
      import: () => {
        this.importVariables();
      },
    });
    side.addSection('properties', STRINGS.tabProperties, ICONS.propertiesTab, this.properties);
    side.addSection('objects', STRINGS.tabObjects, ICONS.objectsTab, this.objects);
    side.addSection('variables', STRINGS.tabVariables, ICONS.variablesTab, this.variables);
    this.measurements = new MeasurementsPanel(this.document, this.listEvents());
    this.measurements.patternFileName = () => this.document.fileName;
    if (this.files !== undefined) {
      const files = this.files;
      // The file it is written to, chosen before the edits are made
      let target: FileSystemFileHandle | undefined;
      this.measurements.saver = {
        prepare: async (path, isNew) => {
          target = await this.measurementsTarget(files, path);
          if (target === undefined || !(await files.mayWrite(target))) {
            return undefined;
          }
          // A new set is recorded where it was put, when the pattern's folder is known
          const recorded =
            isNew && this.patternHandle !== undefined ? await files.pathBetween(this.patternHandle, target) : undefined;
          return recorded ?? (isNew ? target.name : path);
        },
        write: async (_path, text) => {
          // The tab then says what was saved
          if (target !== undefined && (await files.write(target, text))) {
            this.measurementsHandle = target;
          }
        },
      };
    }
    side.addSection('measurements', STRINGS.tabMeasurements, ICONS.measurementsTab, this.measurements);
    this.printDialog = new PrintDialog(this.document, {
      fileName: () => this.document.fileName || DEFAULT_FILE_NAME,
      message: showMessage,
      failed: showFailure,
    });
    this.materialsDialog = new MaterialsDialog(this.document, {
      failed: showFailure,
      historyKey: (event) => (this.matches(event, 'undo') ? 'undo' : this.matches(event, 'redo') ? 'redo' : undefined),
    });
    this.materials = new MaterialsPanel(this.document, {
      edit: (index) => {
        this.materialsDialog.open(index);
      },
      failed: showFailure,
    });
    side.addSection('materials', STRINGS.tabMaterials, ICONS.materialsTab, this.materials);
    this.features = new FeaturesPanel(this.document, { message: showMessage, failed: showFailure });
    side.addSection('features', STRINGS.tabFeatures, ICONS.featuresTab, this.features);
    this.undoButton = iconButton(ICONS.undo, STRINGS.undo, STRINGS.undo, () => {
      this.run(this.document.undo());
    });
    this.redoButton = iconButton(ICONS.redo, STRINGS.redo, STRINGS.redo, () => {
      this.run(this.document.redo());
    });
    this.rulersButton = iconButton(
      ICONS.rulers,
      STRINGS.rulers,
      STRINGS.rulersHint(this.tables.shortcuts.get('rulers') ?? ''),
      () => {
        this.toggleRulers();
      },
    );
    this.rulersButton.classList.add('chosen');
    toolbar.append(
      iconButton(ICONS.open, STRINGS.open, STRINGS.openHint, () => {
        this.open();
      }),
      iconButton(ICONS.measurements, STRINGS.measurements, STRINGS.measurementsHint, () => {
        this.openMeasurements();
      }),
      iconButton(ICONS.save, STRINGS.save, this.files === undefined ? STRINGS.saveHint : STRINGS.saveToFileHint, () => {
        this.run(this.save(false));
      }),
      // A download asks where to put it anyway
      ...(this.files === undefined
        ? []
        : [
            iconButton(ICONS.saveAs, STRINGS.saveAs, STRINGS.saveAsHint, () => {
              this.run(this.save(true));
            }),
          ]),
      this.undoButton,
      this.redoButton,
      ...this.selectionButtons.slice(0, 2),
      iconButton(ICONS.paste, STRINGS.paste, STRINGS.pasteHint(shortcutOf('paste')), () => {
        this.run(this.pasteFromButton());
      }),
      this.deleteButton,
      iconButton(ICONS.exportDraft, STRINGS.exportDraft, STRINGS.exportDraftHint, () => {
        this.run(this.exportDraft());
      }),
      iconButton(ICONS.print, STRINGS.print, STRINGS.printHint, () => {
        this.printDialog.open();
      }),
      iconButton(ICONS.fit, STRINGS.fit, STRINGS.fitHint, () => {
        this.canvas.fitAll();
      }),
      this.rulersButton,
      this.exampleBox(),
      this.roleBox(),
      this.labelBox(),
    );
    for (const tool of tables.tools.filter((each) => this.canvas.hasTool(each.name))) {
      const button = iconButton(tool.icon, tool.caption, `${tool.caption} (${tool.keys})`, () => {
        this.useTool(tool.name);
      });
      this.toolButtons.set(tool.name, button);
      toolsBar.append(button);
    }
    openInput.addEventListener('change', () => {
      this.run(this.openFiles([...(openInput.files ?? [])].map((file) => ({ file, handle: undefined }))));
      openInput.value = '';
    });
    importInput.addEventListener('change', () => {
      const file = importInput.files?.[0];
      if (file !== undefined) {
        this.run(this.importVariablesFrom(file));
      }
      importInput.value = '';
    });
    measurementsInput.addEventListener('change', () => {
      const file = measurementsInput.files?.[0];
      if (file !== undefined) {
        this.measurementsHandle = undefined;
        this.run(this.useMeasurements(file));
      }
      measurementsInput.value = '';
    });
    document.addEventListener('keydown', (event) => {
      this.keyDown(event);
    });
    // The paste key gives the clipboard's text without asking; in a field it pastes text
    document.addEventListener('paste', (event) => {
      if (document.querySelector('dialog[open]') !== null || isTextField(event.target)) {
        return;
      }
      event.preventDefault();
      this.run(this.paste(event.clipboardData?.getData('text/plain')));
    });
    // Every label shows while the show-labels key is held
    document.addEventListener('keyup', (event) => {
      if (this.isShowLabelsKey(event)) {
        this.canvas.holdLabels(false);
      }
    });
    window.addEventListener('blur', () => {
      this.canvas.holdLabels(false);
    });
    this.document.addListener(() => {
      this.updateState();
    });
    this.autosave = new Autosave(
      this.document,
      () => ({
        fileName: this.document.fileName,
        patternHandle: this.patternHandle,
        measurementsHandle: this.measurementsHandle,
      }),
      (kept) => {
        // For the tests
        document.body.dataset.workKept = String(kept);
      },
    );
    this.useTool(SELECT_TOOL);
    this.updateState();
  }

  // Keeps the app for offline use; a new version waits until the user reloads into it
  private async registerServiceWorker(): Promise<void> {
    if (!('serviceWorker' in navigator)) {
      return;
    }
    const container = navigator.serviceWorker;
    const registration = await container.register('sw.js');
    const update = document.createElement('button');
    update.id = 'update';
    update.type = 'button';
    update.textContent = STRINGS.update;
    update.title = STRINGS.updateHint;
    update.hidden = true;
    toolbar.append(update);
    let reloading = false;
    // The newest worker waiting to take over
    let waiting: ServiceWorker | undefined;
    update.addEventListener('click', () => {
      const next = waiting;
      if (next === undefined) {
        return;
      }
      reloading = true;
      // The work is in the browser before the page goes
      this.run(
        this.autosave.flush().then(() => {
          next.postMessage('skipWaiting');
          return undefined;
        }),
      );
    });
    const offer = (worker: ServiceWorker): void => {
      waiting = worker;
      update.hidden = false;
    };
    // Only a worker replacing one that runs the page waits; the first takes over at once
    const offerWhenInstalled = (worker: ServiceWorker): void => {
      worker.addEventListener('statechange', () => {
        if (worker.state === 'installed' && container.controller !== null) {
          offer(worker);
        }
      });
    };
    if (registration.waiting !== null && container.controller !== null) {
      offer(registration.waiting);
    }
    if (registration.installing !== null) {
      offerWhenInstalled(registration.installing);
    }
    registration.addEventListener('updatefound', () => {
      if (registration.installing !== null) {
        offerWhenInstalled(registration.installing);
      }
    });
    const controlled = (): void => {
      // For the tests: the page now loads from the cache
      document.body.dataset.offline = String(container.controller !== null);
    };
    controlled();
    container.addEventListener('controllerchange', () => {
      controlled();
      if (reloading) {
        window.location.reload();
      }
    });
  }

  async start(): Promise<void> {
    await this.document.refresh();
    this.updateState();
    this.autosave.start();
    // Offline use is a convenience: the app runs without it
    this.registerServiceWorker().catch((error: unknown) => {
      console.warn('not kept for offline use', error);
    });
    await this.offerLeftOver();
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

  // Opens the work as it was, still to be saved, with the files it came from
  private async openWork(work: Work): Promise<void> {
    if (!this.mayDropChanges()) {
      return;
    }
    const { text, measurementsText } = await this.autosave.texts(work);
    await this.openPattern(new File([text], work.fileName), work.patternHandle);
    if (measurementsText !== undefined) {
      // The pattern keeps the file it records
      await this.document.call('use_measurements', { text: measurementsText });
      this.wantedMeasurements = '';
      this.measurementsHandle = work.measurementsHandle;
    }
    this.document.fileName = work.fileName;
    await this.document.call('editor_mark_unsaved');
    await this.autosave.discard(work);
    showMessage(STRINGS.workOpened(work.fileName === '' ? STRINGS.untitled : work.fileName));
  }

  // Opening something else drops unsaved changes, kept only for this tab, so the user is asked first
  private mayDropChanges(): boolean {
    return (!this.document.state.modified || window.confirm(STRINGS.discardChanges)) && this.mayDropMeasurementEdits();
  }

  // Edit > Copy or Cut: the fragment goes on the clipboard as text, so
  // another tab or the desktop app can paste it, and is kept here too
  private async copy(cut: boolean): Promise<void> {
    const text = await this.canvas.copySelection(cut);
    if (text === '') {
      return;
    }
    this.copied = text;
    this.copiedToClipboard = false;
    try {
      await navigator.clipboard.writeText(text);
      this.copiedToClipboard = true;
    } catch {
      // Refused, as without a click or a secure page: Paste takes it from here
    }
  }

  // The clipboard's text, unless the last copy never reached it
  private async paste(clipboardText: string | undefined): Promise<void> {
    const text =
      clipboardText !== undefined && clipboardText !== '' && (this.copiedToClipboard || this.copied === '')
        ? clipboardText
        : this.copied;
    if (text === '') {
      showMessage(STRINGS.nothingToPaste);
      return;
    }
    await this.canvas.paste(text);
  }

  // The Paste button has no paste event, so reads the clipboard itself, which the browser may refuse
  private async pasteFromButton(): Promise<void> {
    let text: string | undefined;
    try {
      text = await navigator.clipboard.readText();
    } catch {
      text = undefined;
    }
    await this.paste(text);
  }

  private run(pending: Promise<void>): void {
    pending.catch((error: unknown) => {
      if (error instanceof EngineError) {
        showMessage(error.message);
      } else {
        showFailure(error);
      }
    });
  }

  private open(): void {
    if (!this.mayDropChanges()) {
      return;
    }
    const files = this.files;
    if (files === undefined) {
      openInput.click();
      return;
    }
    this.run(
      files
        .openPattern(this.patternHandle)
        .then(async (handles) =>
          this.openFiles(await Promise.all(handles.map(async (handle) => ({ file: await handle.getFile(), handle })))),
        ),
    );
  }

  // The Variables tab's Import…: another pattern's variables, from a file the user chooses
  private importVariables(): void {
    const files = this.files;
    if (files === undefined) {
      importInput.click();
      return;
    }
    this.run(
      files.openOtherPattern(this.patternHandle).then(async (handle) => {
        if (handle !== undefined) {
          await this.importVariablesFrom(await handle.getFile());
        }
        return undefined;
      }),
    );
  }

  // As the desktop, the new variables are chosen in the tab, and a variable
  // kept or nothing imported is said in a dialog as well as the status bar
  private async importVariablesFrom(file: File): Promise<void> {
    const answer = await this.document.call('editor_variable_import', { text: await file.text(), fileName: file.name });
    const message = stringField(answer, 'message') ?? '';
    showMessage(message);
    const added = idsField(answer, 'added');
    if (added.length > 0) {
      this.side.open('variables');
      this.variables.showSelection(added);
    }
    if (booleanField(answer, 'done') !== true || booleanField(answer, 'warning') === true) {
      window.alert(message);
    }
  }

  private openMeasurements(): void {
    if (!this.mayDropMeasurementEdits()) {
      return;
    }
    const files = this.files;
    if (files === undefined) {
      measurementsInput.click();
      return;
    }
    this.run(
      files.openMeasurements(this.patternHandle ?? this.measurementsHandle).then(async (handle) => {
        if (handle !== undefined) {
          await this.useMeasurementsFile(files, handle);
        }
        return undefined;
      }),
    );
  }

  // Recorded by its path from the pattern when a granted folder holds both, else by its name
  private async useMeasurementsFile(files: FileAccess, handle: FileSystemFileHandle): Promise<void> {
    const path = this.patternHandle === undefined ? undefined : await files.pathBetween(this.patternHandle, handle);
    await this.useMeasurements(await handle.getFile(), path);
    this.measurementsHandle = handle;
  }

  // The set's file to write: the one it came from, else the one the pattern
  // names in a granted folder, else one the user chooses
  private async measurementsTarget(files: FileAccess, path: string): Promise<FileSystemFileHandle | undefined> {
    if (this.measurementsHandle !== undefined) {
      return this.measurementsHandle;
    }
    if (this.patternHandle !== undefined) {
      const found = await files.findBeside(this.patternHandle, path, true);
      if (found.file !== undefined) {
        return found.file;
      }
    }
    return files.chooseSave(baseName(path), 'measurements', this.patternHandle);
  }

  // Looks in the granted folders, asking leave to read them, then has the
  // user choose the folder that holds the pattern and its measurements
  private async findMeasurements(): Promise<void> {
    const files = this.files;
    const pattern = this.patternHandle;
    const wanted = this.wantedMeasurements;
    if (files === undefined || pattern === undefined || wanted === '') {
      return;
    }
    let found = await files.findBeside(pattern, wanted, true);
    if (found.file === undefined && found.needsLeave === undefined) {
      if ((await files.grantFolder(pattern)) === undefined) {
        this.offerFind(wanted);
        return;
      }
      found = await files.findBeside(pattern, wanted, false);
    }
    if (found.file === undefined) {
      showMessage(STRINGS.needsMeasurements(wanted));
    } else if (this.patternHandle === pattern) {
      await this.useMeasurementsFile(files, found.file);
    }
  }

  private offerFind(wanted: string): void {
    showActions(STRINGS.findMeasurements(wanted), [
      [
        STRINGS.findMeasurementsButton,
        () => {
          this.run(this.findMeasurements());
        },
      ],
    ]);
  }

  // Another pattern or set drops the measurement edits not saved, so the user is asked first
  private mayDropMeasurementEdits(): boolean {
    return !this.measurements.hasPending || window.confirm(STRINGS.discardMeasurementEdits);
  }

  // What a list tells the app; its rows' choices stay in the list unless a tab says otherwise
  private listEvents(): ListPanelEvents {
    return {
      select: () => undefined,
      zoom: () => undefined,
      message: showMessage,
      failed: showFailure,
    };
  }

  // The user guide's example patterns, fetched from the site as any page is
  private exampleBox(): HTMLSelectElement {
    const box = document.createElement('select');
    box.id = 'examples';
    box.title = STRINGS.examplesHint;
    box.add(new Option(STRINGS.examples, '', true, true));
    for (const [path, caption] of STRINGS.exampleCaptions) {
      box.add(new Option(caption, path));
    }
    box.addEventListener('change', () => {
      const path = box.value;
      box.value = '';
      if (path !== '' && this.mayDropChanges()) {
        this.run(this.openExample(path));
      }
    });
    return box;
  }

  // The example and the measurement file it names, from beside it on the site
  private async openExample(path: string): Promise<void> {
    const address = new URL(`examples/${path}`, window.location.href);
    const pattern = await fetchFile(address);
    if (pattern === undefined) {
      showMessage(STRINGS.exampleMissing(baseName(path)));
      return;
    }
    await this.openPattern(pattern, undefined);
    if (this.wantedMeasurements === '') {
      return;
    }
    const measurements = await fetchFile(new URL(this.wantedMeasurements, address));
    if (measurements === undefined) {
      showMessage(STRINGS.needsMeasurements(this.wantedMeasurements));
    } else {
      await this.useMeasurements(measurements);
    }
  }

  // The role new edges get, as the desktop's role box
  private roleBox(): HTMLSelectElement {
    const box = document.createElement('select');
    box.id = 'role';
    box.title = STRINGS.drawRoleHint;
    for (const role of this.tables.roles.values()) {
      box.add(new Option(role.caption, role.name, false, role.name === this.canvas.drawRole));
    }
    box.addEventListener('change', () => {
      this.canvas.drawRole = box.value;
    });
    return box;
  }

  // Which objects are labelled, as the desktop's Labels menu
  private labelBox(): HTMLSelectElement {
    const box = document.createElement('select');
    box.id = 'labels';
    box.title = STRINGS.labelsHint;
    const captions: Record<LabelMode, string> = {
      contextual: STRINGS.labelsContextual,
      all: STRINGS.labelsAll(this.tables.shortcuts.get('showLabels') ?? ''),
      none: STRINGS.labelsNone,
    };
    for (const mode of LABEL_MODES) {
      box.add(new Option(captions[mode], mode, false, mode === this.canvas.labels));
    }
    box.addEventListener('change', () => {
      this.canvas.labels = LABEL_MODES.find((mode) => mode === box.value) ?? 'contextual';
    });
    return box;
  }

  private useTool(name: string): void {
    this.canvas.setTool(name);
    for (const [toolName, button] of this.toolButtons) {
      button.classList.toggle('chosen', toolName === name);
    }
  }

  private updateState(): void {
    const state = this.document.state;
    this.undoButton.disabled = !state.canUndo;
    this.undoButton.title = state.canUndo ? STRINGS.undoStep(state.undo) : STRINGS.undo;
    this.redoButton.disabled = !state.canRedo;
    this.redoButton.title = state.canRedo ? STRINGS.redoStep(state.redo) : STRINGS.redo;
    const name = this.document.fileName === '' ? STRINGS.untitled : this.document.fileName;
    document.title = `${state.modified ? `${STRINGS.modifiedMark} ` : ''}${name} — ${STRINGS.appName}`;
    // For the tests, which drive the page as a user would
    document.body.dataset.undo = state.undo;
    document.body.dataset.modified = String(state.modified);
  }

  // A pattern file, and its measurement file when it is among those chosen
  // or, with File System Access, in a granted folder that holds the pattern
  private async openFiles(chosen: { file: File; handle: FileSystemFileHandle | undefined }[]): Promise<void> {
    const pattern = chosen.find((each) => each.file.name.toLowerCase().endsWith(PATTERN_EXTENSION));
    if (pattern === undefined) {
      if (chosen[0] !== undefined) {
        showMessage(STRINGS.notAPattern(chosen[0].file.name));
      }
      return;
    }
    await this.openPattern(pattern.file, pattern.handle);
    const wanted = this.wantedMeasurements;
    if (wanted === '') {
      return;
    }
    const measurements = chosen.find((each) => each.file.name === baseName(wanted));
    if (measurements !== undefined) {
      await this.useMeasurements(measurements.file);
      this.measurementsHandle = measurements.handle;
      return;
    }
    if (this.files === undefined || pattern.handle === undefined) {
      showMessage(STRINGS.needsMeasurements(wanted));
      return;
    }
    // Reading a folder the browser has not let the page read since it was
    // granted needs a click on the button offered
    const found = await this.files.findBeside(pattern.handle, wanted, false);
    if (found.file === undefined) {
      this.offerFind(wanted);
    } else {
      await this.useMeasurementsFile(this.files, found.file);
    }
  }

  // Opens the pattern, noting the measurement file it names, and the file it
  // came from when the browser gives it
  private async openPattern(pattern: File, handle: FileSystemFileHandle | undefined): Promise<void> {
    const answer = await this.document.call('open', { text: await pattern.text() });
    this.patternHandle = handle;
    this.measurementsHandle = undefined;
    this.document.fileName = pattern.name;
    this.updateState();
    showMessage(STRINGS.opened(pattern.name, numberField(answer, 'objects') ?? 0));
    this.wantedMeasurements = stringField(answer, 'measurementsFile') ?? '';
  }

  // The pattern keeps the file it names when this is it; another is recorded
  // by its path from the pattern when that is known, else beside the pattern
  private async useMeasurements(file: File, path?: string): Promise<void> {
    const params: { text: string; file?: string } = { text: await file.text() };
    if (path !== undefined && path !== this.wantedMeasurements) {
      params.file = path;
    } else if (path === undefined && baseName(this.wantedMeasurements) !== file.name) {
      params.file = file.name;
    }
    await this.document.call('use_measurements', params);
    this.wantedMeasurements = '';
    showMessage(STRINGS.measurementsUsed(file.name));
  }

  // The draft as the canvas shows it, labels and all, as Export Draft SVG
  private async exportDraft(): Promise<void> {
    const name = `${(this.document.fileName || DEFAULT_FILE_NAME).replace(/\.[^.]*$/, '')}.svg`;
    const answer = await this.document.read('editor_export_draft', {
      labels: [...this.canvas.shownLabels],
      fileName: this.document.fileName,
    });
    downloadText(name, stringField(answer, 'text') ?? '', 'image/svg+xml');
    showMessage(STRINGS.exportedDraft(name));
  }

  // Writes the pattern to its file, or one the user chooses for a new one or
  // with Save as; without File System Access it is downloaded, and the
  // browser asks where or puts it in Downloads
  private async save(saveAs: boolean): Promise<void> {
    const name = this.document.fileName === '' ? DEFAULT_FILE_NAME : this.document.fileName;
    const files = this.files;
    if (files === undefined) {
      const answer = await this.document.call('save', { text: true });
      downloadText(name, stringField(answer, 'text') ?? '');
      return;
    }
    // Leave to write is asked while the click still counts, before the engine is
    let handle = saveAs ? undefined : this.patternHandle;
    if (handle !== undefined && !(await files.mayWrite(handle))) {
      showMessage(STRINGS.writeRefused(handle.name));
      return;
    }
    handle ??= await files.chooseSave(name, 'pattern', this.patternHandle ?? this.measurementsHandle);
    if (handle === undefined) {
      return;
    }
    const answer = await this.document.call('save', { text: true });
    if (!(await files.write(handle, stringField(answer, 'text') ?? ''))) {
      showMessage(STRINGS.writeRefused(handle.name));
      return;
    }
    this.patternHandle = handle;
    this.document.fileName = handle.name;
    this.updateState();
    showMessage(STRINGS.saved(handle.name));
  }

  // Open, Save, Save as and Measurements work from anywhere, a field being
  // typed in committing first as it loses the focus
  private fileKeyDown(event: KeyboardEvent): boolean {
    const command = ['open', 'save', 'saveAs', 'openMeasurements'].find((name) => {
      const shortcut = parseShortcut(this.tables.shortcuts.get(name) ?? '');
      return shortcut !== undefined && matchesShortcut(event, shortcut);
    });
    if (command === undefined) {
      return false;
    }
    if (document.activeElement instanceof HTMLElement) {
      document.activeElement.blur();
    }
    switch (command) {
      case 'open':
        this.open();
        break;
      case 'openMeasurements':
        this.openMeasurements();
        break;
      default:
        this.run(this.save(command === 'saveAs'));
    }
    return true;
  }

  // Shows or hides the rulers, as the desktop's View > Rulers; the button is chosen while they show
  private toggleRulers(): void {
    this.rulers.shown = !this.rulers.shown;
    this.rulersButton.classList.toggle('chosen', this.rulers.shown);
  }

  private isShowLabelsKey(event: KeyboardEvent): boolean {
    const shortcut = parseShortcut(this.tables.shortcuts.get('showLabels') ?? '');
    return shortcut !== undefined && matchesShortcut(event, shortcut);
  }

  // Whether the key press is the command's shortcut, as the engine's tables give it
  private matches(event: KeyboardEvent, command: string): boolean {
    const shortcut = parseShortcut(this.tables.shortcuts.get(command) ?? '');
    return shortcut !== undefined && matchesShortcut(event, shortcut);
  }

  private keyDown(event: KeyboardEvent): void {
    // A modal dialog takes the keys it wants itself, and the window none
    if (document.querySelector('dialog[open]') !== null) {
      return;
    }
    if (this.fileKeyDown(event)) {
      event.preventDefault();
      return;
    }
    if (isTextField(event.target)) {
      return;
    }
    const matches = (command: string): boolean => this.matches(event, command);
    let handled = true;
    if (this.canvas.toolKeyDown(event)) {
      // The tool took it, as Tab and Enter for the Seam tool
    } else if (this.isShowLabelsKey(event)) {
      this.canvas.holdLabels(true);
    } else if (event.key === 'Escape') {
      this.canvas.cancel();
    } else if (
      (event.key === 'Delete' || event.key === 'Backspace') &&
      !event.shiftKey &&
      !event.ctrlKey &&
      !event.metaKey &&
      !event.altKey
    ) {
      // Plain only: Shift+Delete is Cut on the desktop
      this.run(this.canvas.deleteSelection());
    } else if (matches('undo')) {
      this.run(this.document.undo());
    } else if (matches('redo')) {
      this.run(this.document.redo());
    } else if (matches('fit')) {
      this.canvas.fitAll();
    } else if (matches('copy') || matches('cut')) {
      this.run(this.copy(matches('cut')));
    } else if (matches('rulers')) {
      this.toggleRulers();
    } else {
      const tool = this.tables.tools.find((each) => {
        const shortcut = parseShortcut(each.keys);
        return this.canvas.hasTool(each.name) && shortcut !== undefined && matchesShortcut(event, shortcut);
      });
      if (tool === undefined) {
        handled = false;
      } else {
        this.useTool(tool.name);
      }
    }
    if (handled) {
      event.preventDefault();
    }
  }
}

async function main(): Promise<void> {
  showMessage(STRINGS.loading);
  const { engine } = await Engine.start(
    new URL('./worker.js', import.meta.url),
    new URL('./engine_lib.wasm', import.meta.url),
  );
  const app = new DesignApp(engine, parseTables(await engine.call('editor_tables')));
  await app.start();
  document.body.dataset.ready = 'true';
}

main().catch(showFailure);
