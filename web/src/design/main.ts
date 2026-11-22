// The web design app, as Sloper.Design.MainForm: starts the engine, builds
// the toolbar and the tools from the engine's tables, opens and saves files
// as text on the user's machine, and passes keys to the canvas. Nothing is
// sent anywhere: the files stay in the browser.
import { PatternDocument } from '../document/patternDocument.ts';
import { Engine, EngineError } from '../engine/engine.ts';
import { numberField, stringField } from '../engine/replies.ts';
import { parseTables, type Tables } from '../editor/scene.ts';
import { PatternCanvas, SELECT_TOOL } from '../ui/canvas.ts';
import { matchesShortcut, parseShortcut } from '../ui/shortcuts.ts';
import { STRINGS } from '../ui/strings.ts';

// The desktop's icons for the toolbar's commands (APP_ICON_NAMES)
const ICONS = {
  open: 'folder-open',
  measurements: 'ruler-measure',
  save: 'device-floppy',
  undo: 'arrow-back-up',
  redo: 'arrow-forward-up',
  fit: 'zoom-scan',
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

// The last part of a path with /, as the pattern records its measurement file
function baseName(path: string): string {
  return path.slice(path.lastIndexOf('/') + 1);
}

class DesignApp {
  private readonly document: PatternDocument;
  private readonly tables: Tables;
  private readonly canvas: PatternCanvas;
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
      },
      failed: showFailure,
    });
    this.undoButton = iconButton(ICONS.undo, STRINGS.undo, STRINGS.undo, () => {
      this.run(this.document.undo());
    });
    this.redoButton = iconButton(ICONS.redo, STRINGS.redo, STRINGS.redo, () => {
      this.run(this.document.redo());
    });
    toolbar.append(
      iconButton(ICONS.open, STRINGS.open, STRINGS.openHint, () => {
        openInput.click();
      }),
      iconButton(ICONS.measurements, STRINGS.measurements, STRINGS.measurementsHint, () => {
        measurementsInput.click();
      }),
      iconButton(ICONS.save, STRINGS.save, STRINGS.saveHint, () => {
        this.run(this.save());
      }),
      this.undoButton,
      this.redoButton,
      iconButton(ICONS.fit, STRINGS.fit, STRINGS.fitHint, () => {
        this.canvas.fitAll();
      }),
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
    const answer = await this.document.call('open', { text: await pattern.text() });
    this.document.fileName = pattern.name;
    this.updateState();
    showMessage(STRINGS.opened(pattern.name, numberField(answer, 'objects') ?? 0));
    this.wantedMeasurements = stringField(answer, 'measurementsFile') ?? '';
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
    const link = document.createElement('a');
    link.href = URL.createObjectURL(new Blob([stringField(answer, 'text') ?? ''], { type: 'application/json' }));
    link.download = this.document.fileName === '' ? DEFAULT_FILE_NAME : this.document.fileName;
    link.click();
    URL.revokeObjectURL(link.href);
  }

  private keyDown(event: KeyboardEvent): void {
    if (event.target instanceof HTMLInputElement) {
      return;
    }
    const matches = (command: string): boolean => {
      const shortcut = parseShortcut(this.tables.shortcuts.get(command) ?? '');
      return shortcut !== undefined && matchesShortcut(event, shortcut);
    };
    let handled = true;
    if (event.key === 'Escape') {
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
