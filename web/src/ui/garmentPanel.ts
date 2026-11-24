// The Garment tab of the side panel, as Sloper.UI.GarmentPanel: the pieces as
// sewn, darts closed and folds opened, shaded, to glance at while drafting.
// The engine builds them and draws them as SVG (editor_garment), which is
// shown as it comes, so the tab and its export match; zoom and pan change
// only its view box. The marks of the canvas's selection come from the engine
// too (editor_garment_marks) and are drawn over the pieces, as is the piece
// under the pointer. Nothing here changes the pattern.
import type { DocumentChange, PatternDocument } from '../document/patternDocument.ts';
import { isRecord, numbersField, recordsField, stringField, stringsField, type JsonRecord } from '../engine/replies.ts';
import { ViewTransform, ZOOM_STEP, type Rect2, type Vec2 } from '../editor/view.ts';
import { downloadBlob, downloadText } from './download.ts';
import { LatestOnly } from './latestOnly.ts';
import type { SideTabContent } from './sideTabs.ts';
import { STRINGS } from './strings.ts';

export interface GarmentPanelEvents {
  // The piece under the pointer, by ID, or '' when it leaves one
  hoverPiece(id: string): void;
  // A click on a piece, to select it on the canvas
  selectPiece(id: string): void;
  message(text: string): void;
  failed(error: unknown): void;
}

interface GarmentPiece {
  id: string;
  name: string;
  // Flat x, y pairs in the drawing's mm
  outline: number[];
}

const SVG_NS = 'http://www.w3.org/2000/svg';
// Pixels in from each side when the drawing is fitted
const FIT_MARGIN = 16;
// A press that moves further than this, in pixels, pans rather than clicks
const DRAG_THRESHOLD = 4;
// As the desktop's tab marks them, in pixels at any zoom
const MARK_COLOR = 'rgb(30, 120, 220)';
const MARK_WIDTH = 3;
const SEAM_MARK_COLOR = 'rgb(240, 120, 20)';
const SEAM_MARK_WIDTH = 4;
const HOVER_TINT = 'rgba(255, 255, 255, 0.16)';
export const PNG_MIN_WIDTH = 16;
export const PNG_MAX_WIDTH = 4096;
export const PNG_DEFAULT_WIDTH = 1200;
// In a file's name when the pattern has none, and after its name otherwise
const UNNAMED = 'garment';

function parsePieces(answer: JsonRecord): GarmentPiece[] {
  return recordsField(answer, 'pieces').map((piece) => ({
    id: String(piece.id),
    name: stringField(piece, 'name') ?? '',
    outline: numbersField(piece, 'outline') ?? [],
  }));
}

function parseBounds(answer: JsonRecord): Rect2 | undefined {
  const bounds = answer.bounds;
  if (!isRecord(bounds)) {
    return undefined;
  }
  const value = (name: string): number => (typeof bounds[name] === 'number' ? bounds[name] : 0);
  return { minX: value('left'), minY: value('top'), maxX: value('right'), maxY: value('bottom') };
}

function pointsText(flat: readonly number[]): string {
  const pairs: string[] = [];
  for (let index = 0; index + 1 < flat.length; index += 2) {
    pairs.push(`${String(flat[index])},${String(flat[index + 1])}`);
  }
  return pairs.join(' ');
}

function svgElement<K extends keyof SVGElementTagNameMap>(name: K): SVGElementTagNameMap[K] {
  return document.createElementNS(SVG_NS, name);
}

export class GarmentPanel implements SideTabContent {
  readonly element: HTMLElement;
  private readonly document: PatternDocument;
  private readonly events: GarmentPanelEvents;
  private readonly materialSelect: HTMLSelectElement;
  private readonly followBox: HTMLInputElement;
  private readonly drawing: HTMLElement;
  private readonly root: ShadowRoot;
  private readonly notes: HTMLElement;
  private readonly exportDialog: GarmentExportDialog;
  private readonly loads: LatestOnly<number>;
  private readonly markLoads: LatestOnly<number>;
  private readonly view = new ViewTransform();
  private shown = false;
  private stale = true;
  // The material shown, by name, '' for all; undefined until the first is chosen
  private material: string | undefined;
  private generation = -1;
  private svgText = '';
  private svg: SVGSVGElement | undefined;
  private marksGroup: SVGGElement | undefined;
  private pieces: GarmentPiece[] = [];
  private bounds: Rect2 | undefined;
  // Fitted to the tab until the user zooms or pans
  private fitted = true;
  private selection: string[] = [];
  private markedPieces: string[] = [];
  private markedLines: number[][] = [];
  private hoverId = '';
  private pressAt: Vec2 | undefined;
  private panning = false;
  // The canvas's view and size, for Follow canvas
  private canvasView: ViewTransform | undefined;
  private canvasWidth = 0;
  private canvasHeight = 0;
  private readonly listener = (_document: PatternDocument, changes: ReadonlySet<DocumentChange>): void => {
    if (
      changes.has('pattern') ||
      changes.has('objectsReplaced') ||
      changes.has('measurements') ||
      changes.has('view')
    ) {
      this.reload();
    }
  };

  constructor(document: PatternDocument, events: GarmentPanelEvents) {
    this.document = document;
    this.events = events;
    const make = window.document.createElement.bind(window.document);
    this.element = make('div');
    this.element.className = 'garment';

    const toolbar = make('div');
    toolbar.className = 'garment-toolbar';
    this.materialSelect = make('select');
    this.materialSelect.title = STRINGS.garmentMaterialHint;
    this.materialSelect.addEventListener('change', () => {
      this.material = this.materialSelect.value;
      this.fitted = true;
      this.reload();
    });
    const follow = make('label');
    follow.title = STRINGS.garmentFollowHint;
    this.followBox = make('input');
    this.followBox.type = 'checkbox';
    this.followBox.addEventListener('change', () => {
      if (!this.followBox.checked) {
        this.fitted = true;
      }
      this.applyView();
    });
    follow.append(this.followBox, ` ${STRINGS.garmentFollow}`);
    const exportButton = make('button');
    exportButton.type = 'button';
    exportButton.textContent = STRINGS.garmentExport;
    exportButton.title = STRINGS.garmentExportHint;
    exportButton.addEventListener('click', () => {
      this.exportDialog.open();
    });
    toolbar.append(this.materialSelect, follow, exportButton);

    this.drawing = make('div');
    this.drawing.className = 'garment-drawing';
    // The engine's drawing names its gradients and filters; its own root
    // keeps those names from meeting any elsewhere on the page
    this.root = this.drawing.attachShadow({ mode: 'open' });
    this.notes = make('div');
    this.notes.className = 'garment-notes';
    this.element.append(toolbar, this.drawing, this.notes);
    this.exportDialog = new GarmentExportDialog({
      exportSVG: () => {
        this.exportSVG();
      },
      exportPNG: async (width) => this.exportPNG(width),
      failed: (error) => {
        events.failed(error);
      },
    });

    this.drawing.addEventListener('pointerdown', this.pointerDown);
    this.drawing.addEventListener('pointermove', this.pointerMove);
    this.drawing.addEventListener('pointerup', this.pointerUp);
    this.drawing.addEventListener('pointerleave', () => {
      if (this.pressAt === undefined) {
        this.setHover('');
      }
    });
    this.drawing.addEventListener('dblclick', () => {
      this.fitted = true;
      this.applyView();
    });
    this.drawing.addEventListener('wheel', this.wheel, { passive: false });
    new ResizeObserver(() => {
      this.applyView();
    }).observe(this.drawing);

    const failed = (error: unknown): void => {
      events.failed(error);
    };
    this.loads = new LatestOnly(async () => this.load(), failed);
    this.markLoads = new LatestOnly(async () => this.loadMarks(), failed);
    document.addListener(this.listener);
  }

  setShown(shown: boolean): void {
    this.shown = shown;
    if (!shown) {
      this.setHover('');
    } else if (this.stale) {
      this.reload();
    }
  }

  dispose(): void {
    this.document.removeListener(this.listener);
    this.exportDialog.dispose();
    this.element.remove();
  }

  // The canvas's selection: selected pieces are outlined, and a selected seam
  // is marked on both its sides
  showSelection(ids: readonly string[]): void {
    this.selection = [...ids];
    if (this.shown && !this.stale) {
      this.markLoads.push(0);
    }
  }

  // The canvas's zoom and pan, for Follow canvas
  showCanvasView(view: ViewTransform, width: number, height: number): void {
    this.canvasView = view;
    this.canvasWidth = width;
    this.canvasHeight = height;
    if (this.followBox.checked && this.shown) {
      this.applyView();
    }
  }

  private reload(): void {
    if (!this.shown) {
      this.stale = true;
      return;
    }
    this.stale = false;
    this.loads.push(0);
  }

  private async load(): Promise<void> {
    if (this.generation !== this.document.state.generation) {
      // Another pattern: start again on its first material, fitted
      this.generation = this.document.state.generation;
      this.material = undefined;
      this.fitted = true;
    }
    let answer = await this.document.read('editor_garment', { material: this.material ?? '' });
    const materials = stringsField(answer, 'materials') ?? [];
    if (this.material === undefined) {
      // The first material, so lining does not cover the main pieces
      this.material = materials[0] ?? '';
      if (this.material !== '') {
        answer = await this.document.read('editor_garment', { material: this.material });
      }
    }
    // A material deleted or renamed: all are shown
    this.material = stringField(answer, 'material') ?? '';
    this.showMaterials(materials);
    this.svgText = stringField(answer, 'svg') ?? '';
    this.pieces = parsePieces(answer);
    this.bounds = parseBounds(answer);
    this.showDrawing();
    this.showNotes(stringsField(answer, 'notes') ?? [], materials.length > 0 && this.material !== '');
    await this.loadMarks();
  }

  private async loadMarks(): Promise<void> {
    const answer = await this.document.read('editor_garment_marks', {
      selection: this.selection.filter((id) => /^\d+$/.test(id)).map(Number),
      material: this.material ?? '',
    });
    this.markedPieces = (numbersField(answer, 'pieces') ?? []).map(String);
    this.markedLines = Array.isArray(answer.lines)
      ? answer.lines.filter(Array.isArray).map((line) => line.filter((value) => typeof value === 'number'))
      : [];
    this.drawMarks();
  }

  private showMaterials(materials: readonly string[]): void {
    const make = window.document.createElement.bind(window.document);
    const all = make('option');
    all.value = '';
    all.textContent = STRINGS.garmentAllMaterials;
    const options = [all];
    for (const name of materials) {
      const option = make('option');
      option.value = name;
      option.textContent = name;
      options.push(option);
    }
    this.materialSelect.replaceChildren(...options);
    this.materialSelect.value = this.material ?? '';
  }

  private showNotes(notes: readonly string[], oneMaterial: boolean): void {
    const lines = [...notes];
    if (this.pieces.length === 0) {
      lines.unshift(oneMaterial ? STRINGS.garmentNoPiecesOfMaterial : STRINGS.garmentNoPieces);
    }
    this.notes.textContent = lines.join('\n');
    this.notes.hidden = lines.length === 0;
  }

  // The engine's drawing, its size taken from the view box, with groups over
  // it for the marks and for finding the piece under the pointer
  private showDrawing(): void {
    const parsed = new DOMParser().parseFromString(this.svgText, 'image/svg+xml').documentElement;
    if (!(parsed instanceof SVGSVGElement)) {
      this.root.replaceChildren();
      this.svg = undefined;
      return;
    }
    const svg = window.document.importNode(parsed, true);
    svg.removeAttribute('width');
    svg.removeAttribute('height');
    svg.setAttribute('preserveAspectRatio', 'none');
    const marks = svgElement('g');
    marks.setAttribute('pointer-events', 'none');
    const hits = svgElement('g');
    for (const piece of this.pieces) {
      const shape = svgElement('polygon');
      shape.setAttribute('points', pointsText(piece.outline));
      shape.setAttribute('fill', 'transparent');
      shape.dataset.id = piece.id;
      hits.append(shape);
    }
    svg.append(marks, hits);
    const style = window.document.createElement('style');
    style.textContent = 'svg { display: block; width: 100%; height: 100%; }';
    this.root.replaceChildren(style, svg);
    this.svg = svg;
    this.marksGroup = marks;
    if (!this.pieces.some((piece) => piece.id === this.hoverId)) {
      this.setHover('');
    }
    this.applyView();
    this.drawMarks();
  }

  private drawMarks(): void {
    const group = this.marksGroup;
    if (group === undefined) {
      return;
    }
    const shapes: SVGElement[] = [];
    const hovered = this.pieces.find((piece) => piece.id === this.hoverId);
    if (hovered !== undefined) {
      const tint = svgElement('polygon');
      tint.setAttribute('points', pointsText(hovered.outline));
      tint.setAttribute('fill', HOVER_TINT);
      shapes.push(tint);
    }
    for (const line of this.markedLines) {
      const mark = svgElement('polyline');
      mark.setAttribute('points', pointsText(line));
      this.stroke(mark, SEAM_MARK_COLOR, SEAM_MARK_WIDTH);
      shapes.push(mark);
    }
    for (const piece of this.pieces) {
      if (this.markedPieces.includes(piece.id)) {
        const outline = svgElement('polygon');
        outline.setAttribute('points', pointsText(piece.outline));
        this.stroke(outline, MARK_COLOR, MARK_WIDTH);
        shapes.push(outline);
      }
    }
    group.replaceChildren(...shapes);
  }

  private stroke(shape: SVGElement, color: string, width: number): void {
    shape.setAttribute('fill', 'none');
    shape.setAttribute('stroke', color);
    shape.setAttribute('stroke-width', String(width));
    shape.setAttribute('stroke-linejoin', 'round');
    shape.setAttribute('vector-effect', 'non-scaling-stroke');
  }

  // The view box from the view: fitted, the canvas's, or as zoomed and panned
  private applyView(): void {
    const width = this.drawing.clientWidth;
    const height = this.drawing.clientHeight;
    if (this.svg === undefined || width <= 0 || height <= 0) {
      return;
    }
    const canvas = this.canvasView;
    if (this.followBox.checked && canvas !== undefined) {
      // The canvas's zoom, and the middle of what it shows in the middle here
      this.view.scale = canvas.scale;
      this.view.centreOn(canvas.toModel({ x: this.canvasWidth / 2, y: this.canvasHeight / 2 }), width, height);
    } else if (this.fitted && this.bounds !== undefined) {
      this.view.fit(this.bounds, width, height, FIT_MARGIN);
    }
    const corner = this.view.toModel({ x: 0, y: 0 });
    this.svg.setAttribute(
      'viewBox',
      `${String(corner.x)} ${String(corner.y)} ${String(width / this.view.scale)} ${String(height / this.view.scale)}`,
    );
  }

  private at(event: MouseEvent): Vec2 {
    const box = this.drawing.getBoundingClientRect();
    return { x: event.clientX - box.left, y: event.clientY - box.top };
  }

  private pieceAt(event: MouseEvent): string {
    const found = this.root.elementFromPoint(event.clientX, event.clientY);
    return found instanceof SVGElement ? (found.dataset.id ?? '') : '';
  }

  private setHover(id: string): void {
    if (id === this.hoverId) {
      return;
    }
    this.hoverId = id;
    const piece = this.pieces.find((each) => each.id === id);
    this.drawing.title = piece?.name ?? '';
    this.drawMarks();
    this.events.hoverPiece(id);
  }

  private readonly pointerDown = (event: PointerEvent): void => {
    if (event.button !== 0) {
      return;
    }
    this.pressAt = this.at(event);
    this.panning = false;
    this.drawing.setPointerCapture(event.pointerId);
  };

  private readonly pointerMove = (event: PointerEvent): void => {
    const at = this.at(event);
    const pressAt = this.pressAt;
    if (pressAt !== undefined && !this.followBox.checked) {
      if (this.panning || Math.abs(at.x - pressAt.x) > DRAG_THRESHOLD || Math.abs(at.y - pressAt.y) > DRAG_THRESHOLD) {
        this.panning = true;
        this.fitted = false;
        this.view.pan(at.x - pressAt.x, at.y - pressAt.y);
        this.pressAt = at;
        this.applyView();
        return;
      }
    }
    if (pressAt === undefined) {
      this.setHover(this.pieceAt(event));
    }
  };

  private readonly pointerUp = (event: PointerEvent): void => {
    if (this.pressAt === undefined) {
      return;
    }
    this.pressAt = undefined;
    this.drawing.releasePointerCapture(event.pointerId);
    const id = this.pieceAt(event);
    if (!this.panning && id !== '') {
      this.events.selectPiece(id);
    }
    this.panning = false;
    this.setHover(id);
  };

  private readonly wheel = (event: WheelEvent): void => {
    event.preventDefault();
    if (this.followBox.checked) {
      return;
    }
    this.fitted = false;
    this.view.zoomAt(event.deltaY < 0 ? ZOOM_STEP : 1 / ZOOM_STEP, this.at(event));
    this.applyView();
  };

  private fileName(extension: string): string {
    const name = this.document.fileName.replace(/\.[^.]*$/, '');
    return `${name === '' ? UNNAMED : `${name}-${UNNAMED}`}.${extension}`;
  }

  private exportSVG(): void {
    const name = this.fileName('svg');
    downloadText(name, this.svgText, 'image/svg+xml');
    this.events.message(STRINGS.garmentExported(name));
  }

  // The drawing rasterised by the browser at the width asked for, as high as
  // the drawing needs, on white as it is drawn
  private async exportPNG(width: number): Promise<void> {
    // The drawing's own view box, x, y, width and height in mm
    const viewBox = (
      new DOMParser().parseFromString(this.svgText, 'image/svg+xml').documentElement.getAttribute('viewBox') ?? ''
    )
      .split(/\s+/)
      .map(Number);
    const drawnWidth = viewBox[2] ?? 1;
    const drawnHeight = viewBox[3] ?? 1;
    const height = Math.max(1, Math.round((width * drawnHeight) / Math.max(drawnWidth, 1)));
    const url = URL.createObjectURL(new Blob([this.svgText], { type: 'image/svg+xml' }));
    try {
      const image = new Image();
      image.src = url;
      await image.decode();
      const canvas = window.document.createElement('canvas');
      canvas.width = width;
      canvas.height = height;
      const context = canvas.getContext('2d');
      if (context === null) {
        throw new Error(STRINGS.garmentPNGFailed);
      }
      context.fillStyle = '#ffffff';
      context.fillRect(0, 0, width, height);
      context.drawImage(image, 0, 0, width, height);
      const blob = await new Promise<Blob | null>((resolve) => {
        canvas.toBlob(resolve, 'image/png');
      });
      if (blob === null) {
        throw new Error(STRINGS.garmentPNGFailed);
      }
      const name = this.fileName('png');
      downloadBlob(name, blob);
      this.events.message(STRINGS.garmentExported(name));
    } finally {
      URL.revokeObjectURL(url);
    }
  }
}

interface GarmentExportEvents {
  exportSVG(): void;
  exportPNG(width: number): Promise<void>;
  failed(error: unknown): void;
}

// Export…: SVG at true size, or PNG of the width asked for
class GarmentExportDialog {
  private readonly dialog: HTMLDialogElement;
  private readonly pngChoice: HTMLInputElement;
  private readonly widthInput: HTMLInputElement;
  private readonly reason: HTMLElement;

  constructor(events: GarmentExportEvents) {
    const make = window.document.createElement.bind(window.document);
    this.dialog = make('dialog');
    this.dialog.className = 'garment-export';
    const title = make('h2');
    title.textContent = STRINGS.garmentExportTitle;
    const choice = (caption: string, checked: boolean): [HTMLLabelElement, HTMLInputElement] => {
      const label = make('label');
      const input = make('input');
      input.type = 'radio';
      input.name = 'garment-format';
      input.checked = checked;
      input.addEventListener('change', () => {
        this.widthInput.disabled = !this.pngChoice.checked;
      });
      label.append(input, ` ${caption}`);
      return [label, input];
    };
    const [svgLabel] = choice(STRINGS.garmentExportSVG, true);
    const [pngLabel, pngChoice] = choice(STRINGS.garmentExportPNG, false);
    this.pngChoice = pngChoice;
    const widthLabel = make('label');
    widthLabel.className = 'garment-export-width';
    this.widthInput = make('input');
    this.widthInput.type = 'number';
    this.widthInput.min = String(PNG_MIN_WIDTH);
    this.widthInput.max = String(PNG_MAX_WIDTH);
    this.widthInput.value = String(PNG_DEFAULT_WIDTH);
    this.widthInput.disabled = true;
    widthLabel.append(STRINGS.garmentPNGWidth, ' ', this.widthInput);
    this.reason = make('div');
    this.reason.className = 'garment-export-reason';
    const buttons = make('div');
    buttons.className = 'garment-export-buttons';
    const exportButton = make('button');
    exportButton.type = 'button';
    exportButton.className = 'default';
    exportButton.textContent = STRINGS.garmentExportButton;
    exportButton.addEventListener('click', () => {
      if (!this.pngChoice.checked) {
        this.dialog.close();
        events.exportSVG();
        return;
      }
      const width = Number(this.widthInput.value);
      if (!Number.isInteger(width) || width < PNG_MIN_WIDTH || width > PNG_MAX_WIDTH) {
        this.reason.textContent = STRINGS.garmentPNGWidthRange(PNG_MIN_WIDTH, PNG_MAX_WIDTH);
        return;
      }
      this.dialog.close();
      events.exportPNG(width).catch((error: unknown) => {
        events.failed(error);
      });
    });
    const cancel = make('button');
    cancel.type = 'button';
    cancel.textContent = STRINGS.garmentExportCancel;
    cancel.addEventListener('click', () => {
      this.dialog.close();
    });
    buttons.append(exportButton, cancel);
    this.dialog.append(title, svgLabel, pngLabel, widthLabel, this.reason, buttons);
    window.document.body.append(this.dialog);
  }

  open(): void {
    this.reason.textContent = '';
    this.dialog.showModal();
  }

  dispose(): void {
    this.dialog.remove();
  }
}
