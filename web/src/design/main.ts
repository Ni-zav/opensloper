// The web design app, as Sloper.Design.MainForm: starts the engine, builds
// the toolbar and the tools from the engine's tables, opens and saves files
// as text on the user's machine, and passes keys to the canvas. Nothing is
// sent anywhere: the files stay in the browser.
import { PatternDocument } from '../document/patternDocument.ts';
import { Engine, EngineError } from '../engine/engine.ts';
import { numberField, stringField } from '../engine/replies.ts';
import { parseTables, type Tables } from '../editor/scene.ts';
import { LABEL_MODES, PatternCanvas, SELECT_TOOL, type LabelMode } from '../ui/canvas.ts';
import type { ListPanelEvents } from '../ui/listPanel.ts';
import { baseName, downloadText } from '../ui/download.ts';
import { MeasurementsPanel } from '../ui/measurementsPanel.ts';
import { ObjectsPanel } from '../ui/objectsPanel.ts';
import { PropertiesPanel } from '../ui/properties.ts';
import { matchesShortcut, parseShortcut } from '../ui/shortcuts.ts';
import { SideTabs } from '../ui/sideTabs.ts';
import { STRINGS } from '../ui/strings.ts';
import { VariablesPanel } from '../ui/variablesPanel.ts';

// The desktop's icons for the toolbar's commands (APP_ICON_NAMES)
const ICONS = {
  open: 'folder-open',
  measurements: 'ruler-measure',
  save: 'device-floppy',
  undo: 'arrow-back-up',
  redo: 'arrow-forward-up',
  fit: 'zoom-scan',
  // The side panel's tabs
  propertiesTab: 'adjustments-horizontal',
  objectsTab: 'list-tree',
  variablesTab: 'variable',
  measurementsTab: 'ruler-measure',
} as const;

const PATTERN_EXTENSION = '.sloper';
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

function showMessage(text: string): void {
  status.textContent = text;
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
  private readonly objects: ObjectsPanel;
  private readonly properties: PropertiesPanel;
  private readonly measurements: MeasurementsPanel;
  private readonly toolButtons = new Map<string, HTMLButtonElement>();
  private readonly undoButton: HTMLButtonElement;
  private readonly redoButton: HTMLButtonElement;
  // The measurement file the open pattern names, while it has none
  private wantedMeasurements = '';

  constructor(engine: Engine, tables: Tables) {
    this.document = new PatternDocument(engine);
    this.tables = tables;
    this.canvas = new PatternCanvas(element('canvas', HTMLCanvasElement), this.document, tables, {
      message: showMessage,
      selectionChanged: (ids) => {
        document.body.dataset.selection = ids.join(' ');
        this.objects.showSelection(ids);
        this.properties.showSelection(ids);
      },
      failed: showFailure,
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
    });
    this.properties = new PropertiesPanel(this.document, { message: showMessage, failed: showFailure });
    const side = new SideTabs(element('side', HTMLElement));
    side.addSection('properties', STRINGS.tabProperties, ICONS.propertiesTab, this.properties);
    side.addSection('objects', STRINGS.tabObjects, ICONS.objectsTab, this.objects);
    side.addSection(
      'variables',
      STRINGS.tabVariables,
      ICONS.variablesTab,
      new VariablesPanel(this.document, this.listEvents()),
    );
    this.measurements = new MeasurementsPanel(this.document, this.listEvents());
    this.measurements.patternFileName = () => this.document.fileName;
    side.addSection('measurements', STRINGS.tabMeasurements, ICONS.measurementsTab, this.measurements);
    this.undoButton = iconButton(ICONS.undo, STRINGS.undo, STRINGS.undo, () => {
      this.run(this.document.undo());
    });
    this.redoButton = iconButton(ICONS.redo, STRINGS.redo, STRINGS.redo, () => {
      this.run(this.document.redo());
    });
    toolbar.append(
      iconButton(ICONS.open, STRINGS.open, STRINGS.openHint, () => {
        if (this.mayDropMeasurementEdits()) {
          openInput.click();
        }
      }),
      iconButton(ICONS.measurements, STRINGS.measurements, STRINGS.measurementsHint, () => {
        if (this.mayDropMeasurementEdits()) {
          measurementsInput.click();
        }
      }),
      iconButton(ICONS.save, STRINGS.save, STRINGS.saveHint, () => {
        this.run(this.save());
      }),
      this.undoButton,
      this.redoButton,
      iconButton(ICONS.fit, STRINGS.fit, STRINGS.fitHint, () => {
        this.canvas.fitAll();
      }),
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
      this.run(this.openFiles([...(openInput.files ?? [])]));
      openInput.value = '';
    });
    measurementsInput.addEventListener('change', () => {
      const file = measurementsInput.files?.[0];
      if (file !== undefined) {
        this.run(this.useMeasurements(file));
      }
      measurementsInput.value = '';
    });
    document.addEventListener('keydown', (event) => {
      this.keyDown(event);
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
    this.useTool(SELECT_TOOL);
    this.updateState();
  }

  async start(): Promise<void> {
    await this.document.refresh();
    this.updateState();
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
      if (path !== '' && this.mayDropMeasurementEdits()) {
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
    await this.openPattern(pattern);
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
  private async openFiles(files: File[]): Promise<void> {
    const pattern = files.find((file) => file.name.toLowerCase().endsWith(PATTERN_EXTENSION));
    if (pattern === undefined) {
      if (files[0] !== undefined) {
        showMessage(STRINGS.notAPattern(files[0].name));
      }
      return;
    }
    await this.openPattern(pattern);
    if (this.wantedMeasurements === '') {
      return;
    }
    const measurements = files.find((file) => file.name === baseName(this.wantedMeasurements));
    if (measurements === undefined) {
      showMessage(STRINGS.needsMeasurements(this.wantedMeasurements));
    } else {
      await this.useMeasurements(measurements);
    }
  }

  // Opens the pattern, noting the measurement file it names
  private async openPattern(pattern: File): Promise<void> {
    const answer = await this.document.call('open', { text: await pattern.text() });
    this.document.fileName = pattern.name;
    this.updateState();
    showMessage(STRINGS.opened(pattern.name, numberField(answer, 'objects') ?? 0));
    this.wantedMeasurements = stringField(answer, 'measurementsFile') ?? '';
  }

  // The pattern keeps the file it names when this is it; another is recorded beside the pattern
  private async useMeasurements(file: File): Promise<void> {
    const params: { text: string; file?: string } = { text: await file.text() };
    if (baseName(this.wantedMeasurements) !== file.name) {
      params.file = file.name;
    }
    await this.document.call('use_measurements', params);
    this.wantedMeasurements = '';
    showMessage(STRINGS.measurementsUsed(file.name));
  }

  // Downloads the pattern file; the browser asks where, or puts it in Downloads
  private async save(): Promise<void> {
    const answer = await this.document.call('save', { text: true });
    downloadText(
      this.document.fileName === '' ? DEFAULT_FILE_NAME : this.document.fileName,
      stringField(answer, 'text') ?? '',
    );
  }

  private isShowLabelsKey(event: KeyboardEvent): boolean {
    const shortcut = parseShortcut(this.tables.shortcuts.get('showLabels') ?? '');
    return shortcut !== undefined && matchesShortcut(event, shortcut);
  }

  private keyDown(event: KeyboardEvent): void {
    if (
      event.target instanceof HTMLInputElement ||
      event.target instanceof HTMLSelectElement ||
      event.target instanceof HTMLTextAreaElement
    ) {
      return;
    }
    const matches = (command: string): boolean => {
      const shortcut = parseShortcut(this.tables.shortcuts.get(command) ?? '');
      return shortcut !== undefined && matchesShortcut(event, shortcut);
    };
    let handled = true;
    if (this.canvas.toolKeyDown(event)) {
      // The tool took it, as Tab and Enter for the Seam tool
    } else if (this.isShowLabelsKey(event)) {
      this.canvas.holdLabels(true);
    } else if (event.key === 'Escape') {
      this.canvas.cancel();
    } else if (matches('undo')) {
      this.run(this.document.undo());
    } else if (matches('redo')) {
      this.run(this.document.redo());
    } else if (matches('fit')) {
      this.canvas.fitAll();
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
