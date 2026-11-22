// Draws the scene on a canvas as the desktop's Sloper.UI.PatternPainter does:
// paper and grid, pieces under edges, edges under points, then the overlays the
// canvas asks for (the snap, the selection box). It draws what it is given and
// decides nothing about tools or input. Colours and sizes are the desktop's.
import {
  placeLabels,
  placesAlong,
  placesAround,
  placesStacked,
  polylinePlaces,
  rectAround,
  type LabelRequest,
} from '../editor/labelPlacement.ts';
import type { EvalState, Scene, SceneObject, Tables } from '../editor/scene.ts';
import type { Rect2, Vec2, ViewTransform } from '../editor/view.ts';

// Screen pixels
const MARKING_LINE_WIDTH = 1.5;
const POINT_RADIUS = 3.5;
const COINCIDENT_GAP = 3;
const SNAP_MARKER_SIZE = 6;
// A copied point's diamond reaches this many dot radii from its centre
const DIAMOND_SCALE = 1.6;
// A role's dashes are this many pixels a millimetre of its pattern, at any zoom
const DASH_PIXELS_PER_MILLIMETRE = 2.5;
// psDash, in line widths
const CONSTRUCTION_DASH = [3, 1];
// psDot, for the guide to the point a snap lines up with, in pixels
const GUIDE_DOTS = [1, 2];
// A piece's grainline, fold and marking strokes, and its notches, in pixels
const PIECE_MARK_WIDTH = 1.5;
const NOTCH_WIDTH = 2;
const SEAM_LINE_WIDTH = 4;
const CHEVRON_SIZE = 7;
// Degrees either side of the way a chevron points, to its wings
const CHEVRON_SPREAD = 150;
const CHEVRON_WIDTH = 2;
const LABEL_FONT_HEIGHT = 13;
// A label's box is this much taller than its font, for the ascenders and descenders
const LABEL_LINE_HEIGHT = 1.2;
const LABEL_FONT = `${String(LABEL_FONT_HEIGHT)}px system-ui, sans-serif`;
// How far a label is from its point or line, and how many lines further out
// it may move to keep clear of others, in pixels
const LABEL_GAP_PIXELS = 4;
const LABEL_RINGS = 2;
// Labels this far off the canvas are left out, in pixels
const OFFSCREEN_LABEL_PIXELS = 200;
// The grid's lines, in mm, drawn while they are at least this many pixels apart
const GRID_STEP = 10;
const GRID_MAJOR_EVERY = 10;
const GRID_MIN_PIXELS = 6;
// Alpha of a failing object's ink, of 255
const FADED_ALPHA = 150;
const FULL_ALPHA = 255;
// Laid over what an isolated piece does not use
const DIM_WASH_ALPHA = 200;

interface Rgba {
  red: number;
  green: number;
  blue: number;
  alpha: number;
}

function rgba(red: number, green: number, blue: number, alpha = FULL_ALPHA): Rgba {
  return { red, green, blue, alpha };
}

const PAPER = rgba(252, 251, 248);
const GRID_MINOR = rgba(236, 234, 228);
const GRID_MAJOR = rgba(218, 215, 207);
const INK = rgba(34, 36, 40);
const CONSTRUCTION_INK = rgba(128, 134, 145);
const SELECTED_INK = rgba(37, 116, 214);
const SNAP_INK = rgba(196, 48, 140);
const BOX_FILL = rgba(37, 116, 214, 20);
const PIECE_HOVER_TINT = rgba(37, 116, 214, 30);
const HOVER_HALO = rgba(37, 116, 214, 60);
const ERROR_INK = rgba(209, 52, 56);
const BLOCKED_INK = rgba(226, 140, 40);
const SEAM_INK_A = rgba(214, 96, 37);
const SEAM_INK_B = rgba(20, 140, 120);

function css(color: Rgba): string {
  return `rgba(${String(color.red)}, ${String(color.green)}, ${String(color.blue)}, ${String(color.alpha / FULL_ALPHA)})`;
}

function hexColor(hex: string): Rgba {
  const value = Number.parseInt(hex.replace('#', ''), 16);
  return rgba((value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff);
}

function stateInk(state: EvalState, normal: Rgba): Rgba {
  if (state === 'error' || state === 'invalid') {
    return ERROR_INK;
  }
  return state === 'blocked' ? BLOCKED_INK : normal;
}

// A locked object is drawn greyed: its ink without colour, half way to the paper
function greyed(color: Rgba): Rgba {
  const grey = Math.trunc((Math.trunc((color.red * 30 + color.green * 59 + color.blue * 11) / 100) + PAPER.red) / 2);
  return rgba(grey, grey, grey, color.alpha);
}

// Normal, greyed when the object is locked, then in its state's colour, faded while failing
function inkFor(item: SceneObject, normal: Rgba): Rgba {
  const ink = stateInk(item.state, item.locked ? greyed(normal) : normal);
  return item.state === 'valid' ? ink : { ...ink, alpha: FADED_ALPHA };
}

export type SnapKind = 'free' | 'point' | 'crossing' | 'edge' | 'horizontal' | 'vertical';

// What a two-click tool's second click would make, drawn from its first
export type SnapPreview = 'line' | 'circle' | 'rectangle';

export interface SnapMarker {
  kind: SnapKind;
  at: Vec2;
  // The point a horizontal or vertical snap lines up with, model mm
  guideFrom?: Vec2 | undefined;
  preview?: { kind: SnapPreview; from: Vec2 } | undefined;
}

// What the canvas shows besides the pattern itself
export interface PaintState {
  view: ViewTransform;
  selection: ReadonlySet<string>;
  hoverId: string;
  snap: SnapMarker | undefined;
  // The selection box's screen corners, while one is dragged
  box: [Vec2, Vec2] | undefined;
  // The objects to label
  labelIds: readonly string[];
  // The sides of the seam the Seam tool is picking, a polyline per edge
  seamA: readonly number[][];
  seamB: readonly number[][];
}

export class PatternPainter {
  private readonly context: CanvasRenderingContext2D;
  private width = 0;
  private height = 0;
  private state: PaintState | undefined;

  constructor(context: CanvasRenderingContext2D) {
    this.context = context;
  }

  // Starts a frame of width by height CSS pixels on blank paper
  beginFrame(width: number, height: number, state: PaintState): void {
    this.width = width;
    this.height = height;
    this.state = state;
    this.context.fillStyle = css(PAPER);
    this.context.fillRect(0, 0, width, height);
  }

  drawGrid(): void {
    const view = this.paintState().view;
    if (GRID_STEP * view.scale < GRID_MIN_PIXELS) {
      return;
    }
    const first = view.toModel({ x: 0, y: 0 });
    const last = view.toModel({ x: this.width, y: this.height });
    const context = this.context;
    context.lineWidth = 1;
    for (const [low, high, across] of [
      [first.x, last.x, true],
      [first.y, last.y, false],
    ] as const) {
      for (let step = Math.ceil(low / GRID_STEP); step * GRID_STEP <= high; step++) {
        const screen = view.toScreen({ x: step * GRID_STEP, y: step * GRID_STEP });
        context.strokeStyle = css(step % GRID_MAJOR_EVERY === 0 ? GRID_MAJOR : GRID_MINOR);
        context.beginPath();
        // Half a pixel in, so a one pixel line is sharp
        const line = Math.round(across ? screen.x : screen.y) + 0.5;
        if (across) {
          context.moveTo(line, 0);
          context.lineTo(line, this.height);
        } else {
          context.moveTo(0, line);
          context.lineTo(this.width, line);
        }
        context.stroke();
      }
    }
  }

  // Pieces under edges, edges under points; what an isolated piece leaves out under a wash
  drawPattern(scene: Scene, tables: Tables): void {
    if (scene.isolated === '') {
      this.drawLayer(scene, tables, false);
      return;
    }
    this.drawLayer(scene, tables, true);
    this.context.fillStyle = css({ ...PAPER, alpha: DIM_WASH_ALPHA });
    this.context.fillRect(0, 0, this.width, this.height);
    this.drawLayer(scene, tables, false);
  }

  // The selected seams, each side in its colour with chevrons the way it
  // runs, and the sides the Seam tool is picking
  drawSeams(scene: Scene): void {
    const state = this.paintState();
    for (const seam of scene.seams) {
      if (!state.selection.has(seam.id)) {
        continue;
      }
      this.strokeLines(seam.sideA, SEAM_INK_A, SEAM_LINE_WIDTH);
      this.strokeLines(seam.sideB, SEAM_INK_B, SEAM_LINE_WIDTH);
      this.drawChevrons(seam.chevronsA, SEAM_INK_A);
      this.drawChevrons(seam.chevronsB, SEAM_INK_B);
    }
    this.strokeLines(state.seamA, SEAM_INK_A, SEAM_LINE_WIDTH);
    this.strokeLines(state.seamB, SEAM_INK_B, SEAM_LINE_WIDTH);
  }

  // Over the rest, so no edge or point crosses out a label: pieces' names
  // first, then points', then edges', each where it covers least
  drawLabels(scene: Scene): void {
    const state = this.paintState();
    const wanted = new Set(state.labelIds);
    if (wanted.size === 0) {
      return;
    }
    const context = this.context;
    context.font = LABEL_FONT;
    const height = Math.round(LABEL_FONT_HEIGHT * LABEL_LINE_HEIGHT);
    const requests: LabelRequest[] = [];
    const texts: { text: string; color: string }[] = [];
    const request = (item: SceneObject, text: string, places: (width: number) => Vec2[]): void => {
      const width = context.measureText(text).width;
      requests.push({ width, height, places: places(width) });
      texts.push({ text, color: css(this.isSelected(item) ? SELECTED_INK : inkFor(item, INK)) });
    };
    const obstacles: Rect2[] = [];
    for (const point of scene.points) {
      const at = state.view.toScreen(point);
      if (this.nearScreen(at)) {
        obstacles.push(rectAround(at, POINT_RADIUS));
      }
    }
    for (const piece of scene.pieces) {
      const at = state.view.toScreen(piece.middle);
      if (wanted.has(piece.id) && this.nearScreen(at)) {
        request(piece, piece.caption, (width) => placesStacked(at, width, height, LABEL_RINGS));
      }
    }
    for (const point of scene.points) {
      const at = state.view.toScreen(point);
      if (wanted.has(point.id) && this.nearScreen(at)) {
        request(point, point.name, (width) => placesAround(at, width, height, LABEL_GAP_PIXELS, LABEL_RINGS));
      }
    }
    for (const edge of scene.edges) {
      if (!wanted.has(edge.id)) {
        continue;
      }
      const line: Vec2[] = [];
      for (let index = 0; index + 1 < edge.line.length; index += 2) {
        line.push(state.view.toScreen({ x: edge.line[index] ?? 0, y: edge.line[index + 1] ?? 0 }));
      }
      const along = polylinePlaces(line);
      if (along[0] !== undefined && this.nearScreen(along[0])) {
        request(edge, edge.name, (width) => placesAlong(along, width, height, LABEL_GAP_PIXELS));
      }
    }
    const places = placeLabels(requests, obstacles);
    context.textBaseline = 'top';
    places.forEach((place, index) => {
      const label = texts[index];
      if (label !== undefined) {
        context.fillStyle = label.color;
        context.fillText(label.text, place.x, place.y);
      }
    });
  }

  // The snap marker, a guide to the point it lines up with, and what the
  // second click would make from the first, as the desktop draws them
  drawSnap(): void {
    const snap = this.paintState().snap;
    if (snap === undefined) {
      return;
    }
    const view = this.paintState().view;
    const at = view.toScreen(snap.at);
    const context = this.context;
    if (snap.preview !== undefined) {
      const from = view.toScreen(snap.preview.from);
      context.strokeStyle = css(SELECTED_INK);
      context.lineWidth = 1.5;
      context.setLineDash(CONSTRUCTION_DASH.map((length) => length * context.lineWidth));
      context.beginPath();
      if (snap.preview.kind === 'circle') {
        context.arc(from.x, from.y, Math.hypot(at.x - from.x, at.y - from.y), 0, 2 * Math.PI);
      } else if (snap.preview.kind === 'rectangle') {
        context.rect(from.x, from.y, at.x - from.x, at.y - from.y);
      } else {
        context.moveTo(from.x, from.y);
        context.lineTo(at.x, at.y);
      }
      context.stroke();
    }
    if (snap.guideFrom !== undefined) {
      const base = view.toScreen(snap.guideFrom);
      context.strokeStyle = css(SNAP_INK);
      context.lineWidth = 1;
      context.setLineDash(GUIDE_DOTS);
      context.beginPath();
      context.moveTo(base.x, base.y);
      context.lineTo(at.x, at.y);
      context.stroke();
    }
    context.setLineDash([]);
    context.strokeStyle = css(SNAP_INK);
    context.lineWidth = 2;
    const size = SNAP_MARKER_SIZE;
    context.beginPath();
    switch (snap.kind) {
      case 'point':
        context.arc(at.x, at.y, size, 0, 2 * Math.PI);
        break;
      case 'crossing':
        context.moveTo(at.x - size, at.y - size);
        context.lineTo(at.x + size, at.y + size);
        context.moveTo(at.x - size, at.y + size);
        context.lineTo(at.x + size, at.y - size);
        break;
      case 'edge':
        context.moveTo(at.x, at.y - size);
        context.lineTo(at.x + size, at.y);
        context.lineTo(at.x, at.y + size);
        context.lineTo(at.x - size, at.y);
        context.closePath();
        break;
      case 'horizontal':
      case 'vertical':
        context.rect(at.x - size + 1, at.y - size + 1, 2 * size - 2, 2 * size - 2);
        break;
      case 'free':
        context.lineWidth = 1.5;
        context.moveTo(at.x - size, at.y);
        context.lineTo(at.x + size, at.y);
        context.moveTo(at.x, at.y - size);
        context.lineTo(at.x, at.y + size);
        break;
    }
    context.stroke();
  }

  drawBox(): void {
    const box = this.paintState().box;
    if (box === undefined) {
      return;
    }
    const [corner, otherCorner] = box;
    const context = this.context;
    context.fillStyle = css(BOX_FILL);
    context.strokeStyle = css(SELECTED_INK);
    context.lineWidth = 1;
    context.setLineDash([]);
    const left = Math.min(corner.x, otherCorner.x);
    const top = Math.min(corner.y, otherCorner.y);
    const boxWidth = Math.abs(corner.x - otherCorner.x);
    const boxHeight = Math.abs(corner.y - otherCorner.y);
    context.fillRect(left, top, boxWidth, boxHeight);
    context.strokeRect(left + 0.5, top + 0.5, boxWidth, boxHeight);
  }

  private paintState(): PaintState {
    if (this.state === undefined) {
      throw new Error('drawing outside a frame');
    }
    return this.state;
  }

  private isSelected(item: SceneObject, copyOf = ''): boolean {
    const selection = this.paintState().selection;
    // Selecting a transform shows its copies
    return selection.has(item.id) || (copyOf !== '' && selection.has(copyOf));
  }

  private tracePolyline(line: number[], shift: Vec2 = { x: 0, y: 0 }): void {
    const view = this.paintState().view;
    this.context.beginPath();
    for (let index = 0; index + 1 < line.length; index += 2) {
      const at = view.toScreen({ x: line[index] ?? 0, y: line[index + 1] ?? 0 });
      if (index === 0) {
        this.context.moveTo(at.x + shift.x, at.y + shift.y);
      } else {
        this.context.lineTo(at.x + shift.x, at.y + shift.y);
      }
    }
  }

  // Near enough the canvas for its label to matter
  private nearScreen(at: Vec2): boolean {
    return (
      at.x > -OFFSCREEN_LABEL_PIXELS &&
      at.y > -OFFSCREEN_LABEL_PIXELS &&
      at.x < this.width + OFFSCREEN_LABEL_PIXELS &&
      at.y < this.height + OFFSCREEN_LABEL_PIXELS
    );
  }

  private strokeLines(lines: readonly number[][], color: Rgba, width: number): void {
    const context = this.context;
    context.strokeStyle = css(color);
    context.lineWidth = width;
    context.setLineDash([]);
    for (const line of lines) {
      this.tracePolyline(line);
      context.stroke();
    }
  }

  // Chevrons as a flat list, x, y and the angle each points (degrees,
  // anticlockwise on screen), drawn at the same size at any zoom
  private drawChevrons(chevrons: readonly number[], color: Rgba): void {
    const view = this.paintState().view;
    const context = this.context;
    context.strokeStyle = css(color);
    context.lineWidth = CHEVRON_WIDTH;
    context.setLineDash([]);
    for (let index = 0; index + 2 < chevrons.length; index += 3) {
      const tip = view.toScreen({ x: chevrons[index] ?? 0, y: chevrons[index + 1] ?? 0 });
      const angle = chevrons[index + 2] ?? 0;
      const wing = (turn: number): Vec2 => {
        const radians = ((angle + turn) * Math.PI) / 180;
        // Up the screen is a positive angle
        return { x: tip.x + CHEVRON_SIZE * Math.cos(radians), y: tip.y - CHEVRON_SIZE * Math.sin(radians) };
      };
      const first = wing(CHEVRON_SPREAD);
      const last = wing(-CHEVRON_SPREAD);
      context.beginPath();
      context.moveTo(first.x, first.y);
      context.lineTo(tip.x, tip.y);
      context.lineTo(last.x, last.y);
      context.stroke();
    }
  }

  // Segments as a flat list, x1, y1, x2, y2 for each, in model mm
  private strokeSegments(segments: number[], color: string, width: number): void {
    if (segments.length < 4) {
      return;
    }
    const view = this.paintState().view;
    const context = this.context;
    context.strokeStyle = color;
    context.lineWidth = width;
    context.beginPath();
    for (let index = 0; index + 3 < segments.length; index += 4) {
      const first = view.toScreen({ x: segments[index] ?? 0, y: segments[index + 1] ?? 0 });
      const last = view.toScreen({ x: segments[index + 2] ?? 0, y: segments[index + 3] ?? 0 });
      context.moveTo(first.x, first.y);
      context.lineTo(last.x, last.y);
    }
    context.stroke();
  }

  private drawLayer(scene: Scene, tables: Tables, dimmed: boolean): void {
    const state = this.paintState();
    const context = this.context;
    context.lineJoin = 'round';
    context.lineCap = 'round';
    for (const piece of scene.pieces) {
      if (piece.dimmed !== dimmed || piece.cutLine.length < 2) {
        continue;
      }
      this.tracePolyline(piece.cutLine);
      context.closePath();
      if (piece.id === state.hoverId) {
        context.fillStyle = css(PIECE_HOVER_TINT);
        context.fill();
      }
      const selected = this.isSelected(piece);
      context.strokeStyle = css(selected ? SELECTED_INK : inkFor(piece, CONSTRUCTION_INK));
      context.lineWidth = selected ? 2 : 1;
      context.setLineDash([]);
      context.stroke();
    }
    for (const edge of scene.edges) {
      if (edge.dimmed !== dimmed || edge.line.length < 4) {
        continue;
      }
      const role = tables.roles.get(edge.role);
      let color = INK;
      let width = 2;
      if (edge.role === 'construction') {
        color = CONSTRUCTION_INK;
        width = 1;
      } else if (role !== undefined && role.color !== '') {
        color = hexColor(role.color);
        width = MARKING_LINE_WIDTH;
      }
      color = inkFor(edge, color);
      const gap = edge.slot * COINCIDENT_GAP;
      this.tracePolyline(edge.line, { x: edge.normal.x * gap, y: edge.normal.y * gap });
      if (edge.id === state.hoverId) {
        context.strokeStyle = css(HOVER_HALO);
        context.lineWidth = width + 6;
        context.setLineDash([]);
        context.stroke();
      }
      if (this.isSelected(edge, edge.copyOf)) {
        color = SELECTED_INK;
        width += 1;
      }
      context.strokeStyle = css(color);
      context.lineWidth = width;
      if (edge.role === 'construction') {
        context.setLineDash(CONSTRUCTION_DASH.map((length) => length * width));
      } else {
        context.setLineDash((role?.dashes ?? []).map((length) => length * DASH_PIXELS_PER_MILLIMETRE));
      }
      context.stroke();
    }
    context.setLineDash([]);
    for (const piece of scene.pieces) {
      if (piece.dimmed !== dimmed) {
        continue;
      }
      const ink = css(this.isSelected(piece) ? SELECTED_INK : inkFor(piece, CONSTRUCTION_INK));
      this.strokeSegments(piece.marks, ink, PIECE_MARK_WIDTH);
      this.strokeSegments(piece.notches, ink, NOTCH_WIDTH);
      // Which way the piece's path runs, while it is selected or hovered
      if (!dimmed && (this.isSelected(piece) || piece.id === this.paintState().hoverId)) {
        this.drawChevrons(piece.chevrons, SELECTED_INK);
      }
    }
    // A marker shows at its point whether or not it is on a piece yet
    for (const marker of scene.markers) {
      if (marker.dimmed === dimmed) {
        this.strokeSegments(marker.strokes, css(this.isSelected(marker) ? SELECTED_INK : inkFor(marker, INK)), 1);
      }
    }
    for (const point of scene.points) {
      if (point.dimmed !== dimmed) {
        continue;
      }
      const at = state.view.toScreen(point);
      let radius = POINT_RADIUS;
      let color = inkFor(point, INK);
      if (point.id === state.hoverId) {
        context.fillStyle = css(HOVER_HALO);
        context.beginPath();
        context.arc(at.x, at.y, radius + 5, 0, 2 * Math.PI);
        context.fill();
      }
      if (this.isSelected(point, point.copyOf)) {
        color = SELECTED_INK;
        radius += 1.5;
      }
      context.fillStyle = css(color);
      context.beginPath();
      // A transform copy is a diamond, so it reads as following something else
      if (point.copyOf === '') {
        context.arc(at.x, at.y, radius, 0, 2 * Math.PI);
      } else {
        radius *= DIAMOND_SCALE;
        context.moveTo(at.x, at.y - radius);
        context.lineTo(at.x + radius, at.y);
        context.lineTo(at.x, at.y + radius);
        context.lineTo(at.x - radius, at.y);
        context.closePath();
      }
      context.fill();
    }
  }
}
