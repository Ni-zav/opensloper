// The web Publish app, as Sloper.Publish.MainForm: starts the engine and opens
// a layout with its patterns and measurement files, or patterns to start a
// layout, as the desktop's Open does. The preview shows its pages and pieces;
// the title names the layout, and the status bar has a message and the count
// of problems. Nothing leaves the
// machine: the files are read in the browser and given to the engine as text.
import { LayoutDocument } from '../document/layoutDocument.ts';
import { Engine } from '../engine/engine.ts';
import { PreviewCanvas } from '../ui/previewCanvas.ts';
import { STRINGS } from '../ui/strings.ts';

const LAYOUT_EXTENSION = '.slayout';
const PATTERN_EXTENSION = '.sloper';

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

class PublishApp {
  private readonly document: LayoutDocument;
  private readonly preview: PreviewCanvas;

  constructor(engine: Engine) {
    this.document = new LayoutDocument(engine);
    this.preview = new PreviewCanvas(previewElement, this.document, {
      selectionChanged: (placement) => {
        document.body.dataset.selected = String(placement);
      },
      failed: showFailure,
    });
  }

  start(): void {
    toolbar.append(
      iconButton('folder-open', STRINGS.open, STRINGS.publishOpenHint, () => {
        openInput.click();
      }),
      iconButton('zoom-scan', STRINGS.fitPages, STRINGS.fitPagesHint, () => {
        this.preview.zoomToFit();
      }),
      iconButton('zoom-in', STRINGS.zoomIn, STRINGS.zoomInHint, () => {
        this.preview.zoomIn();
      }),
      iconButton('zoom-out', STRINGS.zoomOut, STRINGS.zoomOutHint, () => {
        this.preview.zoomOut();
      }),
    );
    openInput.addEventListener('change', () => {
      this.run(this.openFiles([...(openInput.files ?? [])]));
      openInput.value = '';
    });
    this.showState();
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
    document.title = name === '' ? STRINGS.publishName : `${name} — ${STRINGS.publishName}`;
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
    problemCount.title = state.problems.map((problem) => problem.text).join('\n');
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
