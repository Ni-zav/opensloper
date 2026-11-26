// The publish preview, as Sloper.Publish.PreviewCanvas: the pages with the
// pieces on them, drawn with Canvas2D from what publish_scene gives. Blank
// pages are greyed out, and pages left out crossed. The wheel zooms about
// the pointer and the middle button pans. A right-click leaves the page under
// it out of the print, or puts it back. A press selects the piece under
// it, which publish_press finds and holds, and dragging moves it, one undo
// step: the engine moves it (publish_drag), so it lands on the desktop's
// grid, and the scene is read again after each move, the newest only. A copy
// dragged from the tray is dropped where it is let go. A new layout is fitted
// to the view.
import type { LayoutDocument } from '../document/layoutDocument.ts';
import {
  booleanField,
  isRecord,
  numberField,
  numbersField,
  recordsField,
  stringField,
  stringsField,
  type JsonRecord,
} from '../engine/replies.ts';
import { type Rect2, type Vec2, ViewTransform, ZOOM_STEP } from '../editor/view.ts';
import { LatestOnly } from './latestOnly.ts';
import { STRINGS } from './strings.ts';

interface ScenePage {
  area: Rect2;
  caption: string;
  blank: boolean;
  excluded: boolean;
}

interface SceneLine {
  points: number[];
  dashed: boolean;
}

interface ScenePiece {
  placement: number;
  caption: string;
  // '' when the piece is not filled
  fillColor: string;
  cutLine: number[];
  seamLine: number[];
  marks: number[];
  lines: SceneLine[];
  label: Vec2 | undefined;
}

interface Scene {
  cover: Rect2 | undefined;
  pages: ScenePage[];
  pieces: ScenePiece[];
  titleBoxes: Rect2[];
  titleLines: string[];
  // The information block's text, in mm
  titleSize: number;
  titleLineHeight: number;
  titlePadding: number;
}

export interface PreviewCanvasEvents {
  // A piece was chosen by its placement index, or -1 for none
  selectionChanged(placement: number): void;
  // A copy from the tray, by its index there, let go at a point of the layout
  dropCopy(index: number, at: Vec2): void;
  failed(error: unknown): void;
}

// What a tray line carries when dragged: its index in the tray
export const TRAY_DRAG_TYPE = 'application/x-opensloper-tray-copy';

const EMPTY_SCENE: Scene = {
  cover: undefined,
  pages: [],
  pieces: [],
  titleBoxes: [],
  titleLines: [],
  titleSize: 0,
  titleLineHeight: 0,
  titlePadding: 0,
};

// As the desktop's preview
const FIT_MARGIN = 24;
const DRAG_THRESHOLD = 3;
const CAPTION_HEIGHT = 13;
const LABEL_HEIGHT = 12;
// Text smaller than this, in pixels, is not drawn
const MIN_TEXT_HEIGHT = 6;
const DESK = 'rgb(120, 122, 128)';
const PAPER = 'rgb(255, 255, 255)';
const BLANK_PAPER = 'rgb(205, 206, 210)';
const LEFT_OUT = 'rgb(190, 60, 60)';
const EDGE = 'rgb(90, 92, 98)';
const PIECE = 'rgb(34, 36, 40)';
const SELECTED = 'rgb(37, 116, 214)';
// How strongly a piece's material tints it
const TINT_ALPHA = 50 / 255;
const DASH = [6, 4];

const LEFT_BUTTON = 0;
const MIDDLE_BUTTON = 1;
const RIGHT_BUTTON = 2;

function parseRect(item: unknown): Rect2 | undefined {
  if (!isRecord(item)) {
    return undefined;
  }
  return {
    minX: numberField(item, 'minX') ?? 0,
    minY: numberField(item, 'minY') ?? 0,
    maxX: numberField(item, 'maxX') ?? 0,
    maxY: numberField(item, 'maxY') ?? 0,
  };
}

function parsePiece(item: JsonRecord): ScenePiece {
  const label = item.label;
  return {
    placement: numberField(item, 'placement') ?? -1,
    caption: stringField(item, 'caption') ?? '',
    fillColor: stringField(item, 'fillColor') ?? '',
    cutLine: numbersField(item, 'cutLine') ?? [],
    seamLine: numbersField(item, 'seamLine') ?? [],
    marks: numbersField(item, 'marks') ?? [],
    lines: recordsField(item, 'lines').map((line) => ({
      points: numbersField(line, 'points') ?? [],
      dashed: booleanField(line, 'dashed') ?? false,
    })),
    label: isRecord(label) ? { x: numberField(label, 'x') ?? 0, y: numberField(label, 'y') ?? 0 } : undefined,
  };
}

function parseScene(answer: JsonRecord): Scene {
  const title = isRecord(answer.title) ? answer.title : {};
  return {
    cover: parseRect(answer.cover),
    pages: recordsField(answer, 'pages').map((page) => ({
      area: parseRect(page) ?? { minX: 0, minY: 0, maxX: 0, maxY: 0 },
      caption: stringField(page, 'caption') ?? '',
      blank: booleanField(page, 'blank') ?? false,
      excluded: booleanField(page, 'excluded') ?? false,
    })),
    pieces: recordsField(answer, 'pieces').map(parsePiece),
    titleBoxes: (Array.isArray(answer.titleBoxes) ? answer.titleBoxes : []).flatMap((box) => parseRect(box) ?? []),
    titleLines: stringsField(title, 'lines') ?? [],
    titleSize: numberField(title, 'size') ?? 0,
    titleLineHeight: numberField(title, 'lineHeight') ?? 0,
    titlePadding: numberField(title, 'padding') ?? 0,
  };
}

// The cover, the pages and the information block, for Fit
function shownBounds(scene: Scene): Rect2 | undefined {
  const areas = [...scene.pages.map((page) => page.area), ...scene.titleBoxes];
  if (scene.cover !== undefined) {
    areas.push(scene.cover);
  }
  if (areas.length === 0) {
    return undefined;
  }
  return {
    minX: Math.min(...areas.map((area) => area.minX)),
    minY: Math.min(...areas.map((area) => area.minY)),
    maxX: Math.max(...areas.map((area) => area.maxX)),
    maxY: Math.max(...areas.map((area) => area.maxY)),
  };
}

// The colour with the tint's strength, from #rrggbb
function tint(color: string): string {
  const alpha = Math.round(TINT_ALPHA * 255)
    .toString(16)
    .padStart(2, '0');
  return `${color.slice(0, 7)}${alpha}`;
}

export class PreviewCanvas {
  readonly element: HTMLCanvasElement;
  private readonly document: LayoutDocument;
  private readonly events: PreviewCanvasEvents;
  private readonly view = new ViewTransform();
  private readonly scenes: LatestOnly<number>;
  // A drag's moves, each sent once the one before is answered
  private readonly drags: LatestOnly<Vec2>;
  // The press the engine is still answering; a drag waits for it
  private pressing: Promise<boolean> = Promise.resolve(false);
  private readonly resizer: ResizeObserver;
  private readonly listener = (): void => {
    this.refresh();
  };
  private scene: Scene = EMPTY_SCENE;
  private generation = -1;
  private needsFit = true;
  private selectedPlacement = -1;
  private mode: 'idle' | 'pressed' | 'dragging' | 'panning' = 'idle';
  private pointerId: number | undefined;
  private pressAt: Vec2 = { x: 0, y: 0 };
  private lastAt: Vec2 = { x: 0, y: 0 };

  constructor(element: HTMLCanvasElement, document: LayoutDocument, events: PreviewCanvasEvents) {
    this.element = element;
    this.document = document;
    this.events = events;
    this.scenes = new LatestOnly(
      async () => this.loadScene(),
      (error) => {
        events.failed(error);
      },
    );
    this.drags = new LatestOnly(
      async (at) => this.dragTo(at),
      (error) => {
        events.failed(error);
      },
    );
    document.addListener(this.listener);
    this.resizer = new ResizeObserver(() => {
      this.resize();
    });
    this.resizer.observe(element);
    element.addEventListener('pointerdown', this.pointerDown);
    element.addEventListener('pointermove', this.pointerMove);
    element.addEventListener('pointerup', this.pointerUp);
    element.addEventListener('pointercancel', this.pointerInterrupted);
    element.addEventListener('lostpointercapture', this.pointerInterrupted);
    element.addEventListener('wheel', this.wheel, { passive: false });
    element.addEventListener('contextmenu', (event) => {
      event.preventDefault();
    });
    element.addEventListener('dragover', (event) => {
      if (event.dataTransfer?.types.includes(TRAY_DRAG_TYPE) === true) {
        event.preventDefault();
        event.dataTransfer.dropEffect = 'copy';
      }
    });
    element.addEventListener('drop', (event) => {
      const index = event.dataTransfer?.getData(TRAY_DRAG_TYPE) ?? '';
      if (index !== '') {
        event.preventDefault();
        events.dropCopy(Number(index), this.view.toModel(this.screenAt(event)));
      }
    });
  }

  // Stops listening to the document, so a closed preview is not kept alive
  dispose(): void {
    this.document.removeListener(this.listener);
    this.resizer.disconnect();
  }

  get selected(): number {
    return this.selectedPlacement;
  }

  set selected(placement: number) {
    if (placement === this.selectedPlacement) {
      return;
    }
    this.selectedPlacement = placement;
    this.repaint();
    this.events.selectionChanged(placement);
  }

  // Picks up the layout after any change
  refresh(): void {
    this.scenes.push(this.document.generation);
  }

  // Fits what the engine shows once its scene comes, so a fit asked for
  // straight after a change, as Pack's, fits the changed layout
  zoomToFit(): void {
    this.needsFit = true;
    this.refresh();
  }

  zoomIn(): void {
    this.zoomBy(ZOOM_STEP);
  }

  zoomOut(): void {
    this.zoomBy(1 / ZOOM_STEP);
  }

  private zoomBy(factor: number): void {
    this.view.zoomAt(factor, { x: this.element.clientWidth / 2, y: this.element.clientHeight / 2 });
    this.needsFit = false;
    this.repaint();
  }

  private async loadScene(): Promise<void> {
    const generation = this.document.generation;
    const scene = parseScene(await this.document.read('publish_scene'));
    if (generation !== this.generation) {
      // Another layout: what was selected or shown means nothing now
      this.generation = generation;
      this.needsFit = true;
      this.selected = -1;
    }
    this.scene = scene;
    if (!scene.pieces.some((piece) => piece.placement === this.selectedPlacement)) {
      this.selected = -1;
    }
    this.repaint();
  }

  private resize(): void {
    const ratio = window.devicePixelRatio;
    this.element.width = Math.round(this.element.clientWidth * ratio);
    this.element.height = Math.round(this.element.clientHeight * ratio);
    this.element.getContext('2d')?.setTransform(ratio, 0, 0, ratio, 0, 0);
    this.repaint();
  }

  private screenAt(event: MouseEvent): Vec2 {
    const bounds = this.element.getBoundingClientRect();
    return { x: event.clientX - bounds.left, y: event.clientY - bounds.top };
  }

  private readonly pointerDown = (event: PointerEvent): void => {
    if (this.pointerId !== undefined) {
      return;
    }
    const at = this.screenAt(event);
    // A page is often all piece, so a right click reaches it whatever is on it
    if (event.button === RIGHT_BUTTON) {
      const layoutAt = this.view.toModel(at);
      this.document.call('publish_toggle_page', { x: layoutAt.x, y: layoutAt.y }).catch((error: unknown) => {
        this.events.failed(error);
      });
      return;
    }
    if (event.button === MIDDLE_BUTTON) {
      this.mode = 'panning';
    } else if (event.button === LEFT_BUTTON) {
      this.mode = 'pressed';
      this.pressing = this.press(at);
      this.pressing.catch((error: unknown) => {
        this.events.failed(error);
      });
    } else {
      return;
    }
    this.pressAt = at;
    this.lastAt = at;
    this.pointerId = event.pointerId;
    this.element.setPointerCapture(event.pointerId);
    event.preventDefault();
  };

  private readonly pointerMove = (event: PointerEvent): void => {
    if (event.pointerId !== this.pointerId) {
      return;
    }
    const at = this.screenAt(event);
    const previous = this.lastAt;
    this.lastAt = at;
    if (this.mode === 'panning') {
      this.view.pan(at.x - previous.x, at.y - previous.y);
      this.needsFit = false;
      this.repaint();
    } else if (this.mode === 'pressed' && Math.hypot(at.x - this.pressAt.x, at.y - this.pressAt.y) > DRAG_THRESHOLD) {
      this.mode = 'dragging';
    }
    if (this.mode === 'dragging') {
      this.drags.push(this.view.toModel(at));
    }
  };

  private readonly pointerUp = (event: PointerEvent): void => {
    if (event.pointerId !== this.pointerId) {
      return;
    }
    const dragged = this.mode === 'dragging';
    this.endPointer();
    if (dragged) {
      this.endDrag('publish_release');
    }
  };

  // A drag the browser took away puts back what it moved
  private readonly pointerInterrupted = (event: PointerEvent): void => {
    if (event.pointerId === this.pointerId) {
      const dragged = this.mode === 'dragging';
      this.endPointer();
      if (dragged) {
        this.endDrag('publish_cancel');
      }
    }
  };

  // Once the last move is answered, so the step holds every one
  private endDrag(method: string): void {
    const ending = async (): Promise<void> => {
      await this.drags.idle();
      await this.document.call(method);
    };
    ending().catch((error: unknown) => {
      this.events.failed(error);
    });
  }

  private endPointer(): void {
    if (this.pointerId !== undefined && this.element.hasPointerCapture(this.pointerId)) {
      this.element.releasePointerCapture(this.pointerId);
    }
    this.pointerId = undefined;
    this.mode = 'idle';
  }

  private readonly wheel = (event: WheelEvent): void => {
    event.preventDefault();
    this.view.zoomAt(event.deltaY < 0 ? ZOOM_STEP : 1 / ZOOM_STEP, this.screenAt(event));
    this.needsFit = false;
    this.repaint();
  };

  // Selects the piece pressed, as the desktop does on the button going
  // down; true when the engine holds one to drag. Sheet notes are not drawn
  // here yet, so one pressed is not dragged.
  private async press(at: Vec2): Promise<boolean> {
    const layoutAt = this.view.toModel(at);
    const answer = await this.document.live('publish_press', { x: layoutAt.x, y: layoutAt.y });
    const placement = numberField(answer, 'placement') ?? -1;
    this.selected = placement;
    return placement >= 0;
  }

  // Moves what the press holds, and shows it moved
  private async dragTo(at: Vec2): Promise<void> {
    if (!(await this.pressing)) {
      return;
    }
    await this.document.live('publish_drag', { x: at.x, y: at.y });
    await this.loadScene();
  }

  // Drawing

  private repaint(): void {
    const context = this.element.getContext('2d');
    if (context === null) {
      return;
    }
    const width = this.element.clientWidth;
    const height = this.element.clientHeight;
    const whole = shownBounds(this.scene);
    if (this.needsFit && whole !== undefined && width > 0 && height > 0) {
      this.view.fit(whole, width, height, FIT_MARGIN);
      this.needsFit = false;
    }
    context.fillStyle = DESK;
    context.fillRect(0, 0, width, height);
    if (this.scene.cover !== undefined) {
      this.drawSheet(context, this.scene.cover, PAPER, STRINGS.previewCover);
    }
    // Used pages last, so their overlaps with blank ones stay white
    for (const page of this.scene.pages.filter((each) => each.blank)) {
      this.drawPage(context, page);
    }
    for (const page of this.scene.pages.filter((each) => !each.blank && !each.excluded)) {
      this.drawPage(context, page);
    }
    for (const page of this.scene.pages.filter((each) => !each.blank && each.excluded)) {
      this.drawPage(context, page);
    }
    for (const piece of this.scene.pieces) {
      this.drawPiece(context, piece);
    }
    // Over the pieces, as it clears what is under it in a tile's corner
    this.drawTitleBoxes(context);
  }

  private screenRect(area: Rect2): { x: number; y: number; width: number; height: number } {
    const topLeft = this.view.toScreen({ x: area.minX, y: area.minY });
    const bottomRight = this.view.toScreen({ x: area.maxX, y: area.maxY });
    return { x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y };
  }

  private drawSheet(context: CanvasRenderingContext2D, area: Rect2, fill: string, caption: string): void {
    const box = this.screenRect(area);
    context.fillStyle = fill;
    context.fillRect(box.x, box.y, box.width, box.height);
    context.strokeStyle = EDGE;
    context.lineWidth = 1;
    context.setLineDash([]);
    context.strokeRect(box.x, box.y, box.width, box.height);
    context.fillStyle = EDGE;
    context.font = `${String(CAPTION_HEIGHT)}px sans-serif`;
    context.textBaseline = 'top';
    context.fillText(caption, box.x + 4, box.y + 2);
  }

  private drawPage(context: CanvasRenderingContext2D, page: ScenePage): void {
    this.drawSheet(context, page.area, page.blank || page.excluded ? BLANK_PAPER : PAPER, page.caption);
    if (page.excluded) {
      const box = this.screenRect(page.area);
      context.strokeStyle = LEFT_OUT;
      context.lineWidth = 1.5;
      context.beginPath();
      context.moveTo(box.x, box.y);
      context.lineTo(box.x + box.width, box.y + box.height);
      context.moveTo(box.x + box.width, box.y);
      context.lineTo(box.x, box.y + box.height);
      context.stroke();
    }
  }

  private tracePoints(context: CanvasRenderingContext2D, points: number[], closed: boolean): void {
    context.beginPath();
    for (let index = 0; index + 1 < points.length; index += 2) {
      const at = this.view.toScreen({ x: points[index] ?? 0, y: points[index + 1] ?? 0 });
      if (index === 0) {
        context.moveTo(at.x, at.y);
      } else {
        context.lineTo(at.x, at.y);
      }
    }
    if (closed) {
      context.closePath();
    }
  }

  private drawPiece(context: CanvasRenderingContext2D, piece: ScenePiece): void {
    const selected = piece.placement === this.selectedPlacement;
    const ink = selected ? SELECTED : PIECE;
    context.setLineDash([]);
    if (piece.fillColor !== '') {
      this.tracePoints(context, piece.cutLine, true);
      context.fillStyle = tint(piece.fillColor);
      context.fill();
    }
    this.tracePoints(context, piece.cutLine, true);
    context.strokeStyle = ink;
    context.lineWidth = selected ? 2.5 : 1.5;
    context.stroke();
    context.lineWidth = 1;
    if (piece.seamLine.length > 0) {
      context.setLineDash(DASH);
      this.tracePoints(context, piece.seamLine, true);
      context.stroke();
      context.setLineDash([]);
    }
    context.beginPath();
    for (let index = 0; index + 3 < piece.marks.length; index += 4) {
      const first = this.view.toScreen({ x: piece.marks[index] ?? 0, y: piece.marks[index + 1] ?? 0 });
      const last = this.view.toScreen({ x: piece.marks[index + 2] ?? 0, y: piece.marks[index + 3] ?? 0 });
      context.moveTo(first.x, first.y);
      context.lineTo(last.x, last.y);
    }
    context.stroke();
    for (const line of piece.lines) {
      context.setLineDash(line.dashed ? DASH : []);
      this.tracePoints(context, line.points, false);
      context.stroke();
    }
    context.setLineDash([]);
    if (piece.label !== undefined) {
      const spot = this.view.toScreen(piece.label);
      context.fillStyle = ink;
      context.font = `${String(LABEL_HEIGHT)}px sans-serif`;
      context.textBaseline = 'top';
      context.fillText(piece.caption, spot.x, spot.y);
    }
  }

  // As the PDF prints it: lines in a ruled box, on white
  private drawTitleBoxes(context: CanvasRenderingContext2D): void {
    const scene = this.scene;
    const textHeight = scene.titleSize * this.view.scale;
    for (const area of scene.titleBoxes) {
      const box = this.screenRect(area);
      context.fillStyle = PAPER;
      context.fillRect(box.x, box.y, box.width, box.height);
      context.strokeStyle = PIECE;
      context.lineWidth = 1;
      context.strokeRect(box.x, box.y, box.width, box.height);
      // Text too small to read would overflow the box
      if (textHeight < MIN_TEXT_HEIGHT) {
        continue;
      }
      context.fillStyle = PIECE;
      context.font = `${String(textHeight)}px sans-serif`;
      context.textBaseline = 'top';
      scene.titleLines.forEach((line, index) => {
        context.fillText(
          line,
          box.x + scene.titlePadding * this.view.scale,
          box.y + (scene.titlePadding + index * scene.titleLineHeight) * this.view.scale,
        );
      });
    }
  }
}
