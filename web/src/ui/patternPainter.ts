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
import type { CurveHandle, EvalState, HandleRef, Scene, SceneNote, SceneObject, Tables } from '../editor/scene.ts';
import { DEFAULT_GRID_STEPS, gridSpacing, MILLIMETRES_PER_UNIT, type MeasureUnit } from '../editor/rulerTicks.ts';
import type { Rect2, Vec2, ViewTransform } from '../editor/view.ts';

// Screen pixels
const MARKING_LINE_WIDTH = 1.5;
const POINT_RADIUS = 3.5;
const COINCIDENT_GAP = 3;
const SNAP_MARKER_SIZE = 6;
// A curve's handle, and how much larger the one under the cursor is
const HANDLE_RADIUS = 4;
const HANDLE_HOVER_GROWTH = 1.5;
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
// Points to mm, for a note's size
const POINTS_TO_MM = 25.4 / 72;
// Text smaller than this many pixels is drawn as a faint bar
const MIN_NOTE_PIXELS = 3;
// How strongly a dimmed note's ink shows, and a note too small to read, of 255
const DIM_NOTE_ALPHA = 60;
const OPAQUE = 255;
// A stamp's thinnest stroke, in pixels
const MIN_STAMP_STROKE_PIXELS = 0.5;
const NOTE_BAR_ALPHA = 40;
// A callout's dot at its tip, in mm, and at least this many pixels
const LEADER_DOT_RADIUS = 0.8;
const MIN_DOT_PIXELS = 1.5;
// The tint round a hovered or selected note's text, in pixels past it
const NOTE_TINT_ACROSS = 2;
const NOTE_TINT_DOWN = 1;
// The family a note without one of its own is drawn in
const DEFAULT_NOTE_FONT = 'system-ui, sans-serif';
// Alpha of a failing object's ink, of 255
const FADED_ALPHA = 150;
const FULL_ALPHA = 255;
// Laid over what an isolated piece does not use
const DIM_WASH_ALPHA = 200;
// The line a drag locked to one field follows, and a suggestion's ghost point, in pixels
const FIELD_GUIDE_WIDTH = 1;
const GHOST_RADIUS = 6;
const GHOST_WIDTH = 1.5;

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
// A suggestion's object at the smallest and largest sizes
const GRADE_GHOST_INK = rgba(196, 48, 140, 160);
// The faint line a drag locked to one field follows
const GUIDE_INK = rgba(37, 116, 214, 90);
const WHITE = rgba(255, 255, 255);

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
  // The selected curves' handles, and the one under the cursor
  handles: readonly CurveHandle[];
  hoverHandle: HandleRef | undefined;
  // A selected callout shows a handle on its tip, for dragging it
  tipHandles: boolean;
  // The callout whose tip is being dragged, where it snapped and its leader there
  draggedTip: DraggedTip | undefined;
  // While a point is dragged by one field, the path it keeps to
  fieldGuide: FieldGuide | undefined;
  // The formula suggestion being hovered
  suggestPreview: SuggestPreview | undefined;
}

// The path a drag of one field keeps the point on, in model mm: a line
// through two places, drawn past both, or a circle
export type FieldGuide = { kind: 'line'; from: Vec2; to: Vec2 } | { kind: 'circle'; centre: Vec2; radius: number };

// A suggestion's object at one size: polylines (flat x, y lists) and its point
export interface GradeGhost {
  lines: number[][];
  point: Vec2 | undefined;
}

// Where a hovered formula suggestion would put the point, if it places one,
// and its object at the first and last sizes
export interface SuggestPreview {
  position: Vec2 | undefined;
  ghosts: GradeGhost[];
}

export interface DraggedTip {
  id: string;
  at: Vec2;
  leaderStrokes: number[];
}

export class PatternPainter {
  private readonly context: CanvasRenderingContext2D;
  private width = 0;
  private height = 0;
  // Where the notes were drawn this frame, for labels to keep off
  private noteFrames: Rect2[] = [];
  private state: PaintState | undefined;

  constructor(context: CanvasRenderingContext2D) {
    this.context = context;
  }

  // Starts a frame of width by height CSS pixels on blank paper
  beginFrame(width: number, height: number, state: PaintState): void {
    this.width = width;
    this.height = height;
    this.state = state;
    this.noteFrames = [];
    this.context.fillStyle = css(PAPER);
    this.context.fillRect(0, 0, width, height);
  }

  // The grid in the pattern's unit, at the desktop's default step, its lines
  // counted in whole steps from the origin so major lines stay put, as
  // TPatternPainter.DrawGrid
  drawGrid(unit: MeasureUnit): void {
    const view = this.paintState().view;
    const spacing = gridSpacing(view.scale * MILLIMETRES_PER_UNIT[unit], DEFAULT_GRID_STEPS[unit], unit);
    const step = spacing.minor * MILLIMETRES_PER_UNIT[unit];
    const perMajor = Math.max(1, Math.round(spacing.labelled / spacing.minor));
    const first = view.toModel({ x: 0, y: 0 });
    const last = view.toModel({ x: this.width, y: this.height });
    const context = this.context;
    context.lineWidth = 1;
    for (const [low, high, across] of [
      [first.x, last.x, true],
      [first.y, last.y, false],
    ] as const) {
      for (let index = Math.floor(low / step); index <= Math.ceil(high / step); index++) {
        const screen = view.toScreen({ x: index * step, y: index * step });
        context.strokeStyle = css(index % perMajor === 0 ? GRID_MAJOR : GRID_MINOR);
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

  // Each note's text in its size and font, with a callout's leader, a white
  // box when it has one, and the tint of being hovered or selected
  drawNotes(scene: Scene): void {
    for (const note of scene.notes) {
      this.drawNote(note);
    }
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
    const obstacles: Rect2[] = [...this.noteFrames];
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

  // Each selected curve's tangent lines. A handle set by a formula is hollow,
  // since it cannot be dragged.
  drawHandles(): void {
    const { handles, hoverHandle, view } = this.paintState();
    const context = this.context;
    context.setLineDash([]);
    context.lineWidth = 1;
    for (const handle of handles) {
      const anchor = view.toScreen(handle.anchor);
      const tip = view.toScreen(handle.at);
      context.strokeStyle = css(SELECTED_INK);
      context.beginPath();
      context.moveTo(anchor.x, anchor.y);
      context.lineTo(tip.x, tip.y);
      context.stroke();
      const hovered = hoverHandle?.edge === handle.edge && hoverHandle.field === handle.field;
      const radius = HANDLE_RADIUS + (hovered ? HANDLE_HOVER_GROWTH : 0);
      context.beginPath();
      context.arc(tip.x, tip.y, radius, 0, 2 * Math.PI);
      if (handle.draggable) {
        context.fillStyle = css(SELECTED_INK);
        context.fill();
      } else {
        context.fillStyle = css(PAPER);
        context.fill();
        context.lineWidth = 1.5;
        context.stroke();
        context.lineWidth = 1;
      }
    }
  }

  // Dashed across the whole canvas, or round the circle
  drawFieldGuide(): void {
    const guide = this.paintState().fieldGuide;
    if (guide === undefined) {
      return;
    }
    const view = this.paintState().view;
    const context = this.context;
    context.strokeStyle = css(GUIDE_INK);
    context.lineWidth = FIELD_GUIDE_WIDTH;
    context.setLineDash(CONSTRUCTION_DASH.map((length) => length * FIELD_GUIDE_WIDTH));
    context.beginPath();
    if (guide.kind === 'line') {
      const start = view.toScreen(guide.from);
      const finish = view.toScreen(guide.to);
      const length = Math.hypot(finish.x - start.x, finish.y - start.y);
      if (length === 0) {
        context.setLineDash([]);
        return;
      }
      // Past both edges of the canvas from anywhere on it
      const reach = 2 * (this.width + this.height) + Math.hypot(start.x - this.width / 2, start.y - this.height / 2);
      const across = ((finish.x - start.x) / length) * reach;
      const down = ((finish.y - start.y) / length) * reach;
      context.moveTo(start.x - across, start.y - down);
      context.lineTo(start.x + across, start.y + down);
    } else {
      const centre = view.toScreen(guide.centre);
      context.arc(centre.x, centre.y, guide.radius * view.scale, 0, 2 * Math.PI);
    }
    context.stroke();
    context.setLineDash([]);
  }

  // The hovered suggestion's object at the smallest and largest sizes, and
  // the dashed ring where it would put the point
  drawSuggestPreview(): void {
    const preview = this.paintState().suggestPreview;
    if (preview === undefined) {
      return;
    }
    const view = this.paintState().view;
    const context = this.context;
    context.lineWidth = GHOST_WIDTH;
    context.setLineDash(CONSTRUCTION_DASH.map((length) => length * GHOST_WIDTH));
    context.strokeStyle = css(GRADE_GHOST_INK);
    for (const ghost of preview.ghosts) {
      context.beginPath();
      for (const line of ghost.lines) {
        for (let index = 0; index + 1 < line.length; index += 2) {
          const at = view.toScreen({ x: line[index] ?? 0, y: line[index + 1] ?? 0 });
          if (index === 0) {
            context.moveTo(at.x, at.y);
          } else {
            context.lineTo(at.x, at.y);
          }
        }
      }
      if (ghost.point !== undefined) {
        const spot = view.toScreen(ghost.point);
        context.moveTo(spot.x + GHOST_RADIUS, spot.y);
        context.arc(spot.x, spot.y, GHOST_RADIUS, 0, 2 * Math.PI);
      }
      context.stroke();
    }
    if (preview.position !== undefined) {
      const at = view.toScreen(preview.position);
      context.strokeStyle = css(SELECTED_INK);
      context.beginPath();
      context.arc(at.x, at.y, GHOST_RADIUS, 0, 2 * Math.PI);
      context.stroke();
      context.setLineDash([]);
      context.fillStyle = css(HOVER_HALO);
      context.beginPath();
      context.arc(at.x, at.y, POINT_RADIUS, 0, 2 * Math.PI);
      context.fill();
    }
    context.setLineDash([]);
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

  private drawNote(note: SceneNote): void {
    const state = this.paintState();
    const view = state.view;
    const context = this.context;
    const selected = this.isSelected(note);
    const topLeft = view.toScreen({ x: note.box.minX, y: note.box.minY });
    const bottomRight = view.toScreen({ x: note.box.maxX, y: note.box.maxY });
    const frameFirst = view.toScreen({ x: note.frame.minX, y: note.frame.minY });
    const frameLast = view.toScreen({ x: note.frame.maxX, y: note.frame.maxY });
    if (this.nearScreen(frameFirst) || this.nearScreen(frameLast)) {
      this.noteFrames.push({ minX: frameFirst.x, minY: frameFirst.y, maxX: frameLast.x, maxY: frameLast.y });
    }
    let ink = selected ? SELECTED_INK : inkFor(note, INK);
    // A screen-only note is drawn lighter, as it never prints
    if (!note.print) {
      ink = { ...ink, alpha: Math.trunc(ink.alpha / 2) };
    }
    if (note.dimmed) {
      ink = { ...ink, alpha: DIM_NOTE_ALPHA };
    }
    // A callout's leader, to where its tip is being dragged while it is
    const dragged = state.draggedTip?.id === note.id ? state.draggedTip : undefined;
    const tip = dragged?.at ?? note.anchorAt;
    const leaderStrokes = dragged?.leaderStrokes ?? note.leaderStrokes;
    if (note.leader !== 'none' && leaderStrokes.length >= 4) {
      this.strokeSegments(leaderStrokes, css(ink), 1);
      if (note.leader === 'dot') {
        const spot = view.toScreen(tip);
        context.fillStyle = css(ink);
        context.beginPath();
        context.arc(spot.x, spot.y, Math.max(MIN_DOT_PIXELS, LEADER_DOT_RADIUS * view.scale), 0, 2 * Math.PI);
        context.fill();
      }
    } else if (selected && note.anchor !== 'free') {
      // A plain note shows faintly what it hangs from
      const anchor = view.toScreen(note.anchorAt);
      context.strokeStyle = css(HOVER_HALO);
      context.lineWidth = 1;
      context.setLineDash(GUIDE_DOTS);
      context.beginPath();
      context.moveTo(anchor.x, anchor.y);
      context.lineTo(topLeft.x, topLeft.y);
      context.stroke();
      context.setLineDash([]);
    }
    // A selected callout's tip can be dragged to something else
    if (selected && note.leader !== 'none' && state.tipHandles) {
      const spot = view.toScreen(tip);
      context.beginPath();
      context.arc(spot.x, spot.y, HANDLE_RADIUS, 0, 2 * Math.PI);
      context.fillStyle = css(PAPER);
      context.fill();
      context.strokeStyle = css(SELECTED_INK);
      context.lineWidth = 1.5;
      context.stroke();
    }
    if (note.boxed) {
      context.fillStyle = css(WHITE);
      context.fillRect(frameFirst.x, frameFirst.y, frameLast.x - frameFirst.x, frameLast.y - frameFirst.y);
    }
    if (selected || note.id === state.hoverId) {
      context.fillStyle = css(PIECE_HOVER_TINT);
      context.fillRect(
        topLeft.x - NOTE_TINT_ACROSS,
        topLeft.y - NOTE_TINT_DOWN,
        bottomRight.x - topLeft.x + 2 * NOTE_TINT_ACROSS,
        bottomRight.y - topLeft.y + 2 * NOTE_TINT_DOWN,
      );
    }
    // A stamp keeps its colours, faded as the ink would be
    if (note.stamp.length > 0) {
      let alpha = 1;
      if (!note.print) {
        alpha = 1 / 2;
      }
      if (note.dimmed) {
        alpha = DIM_NOTE_ALPHA / OPAQUE;
      }
      this.drawStamp(note, alpha);
      return;
    }
    const emPixels = note.size * POINTS_TO_MM * view.scale;
    if (emPixels < MIN_NOTE_PIXELS) {
      context.fillStyle = css({ ...ink, alpha: NOTE_BAR_ALPHA });
      context.fillRect(topLeft.x, topLeft.y, bottomRight.x - topLeft.x, bottomRight.y - topLeft.y);
      return;
    }
    const family = note.font === '' ? DEFAULT_NOTE_FONT : `"${note.font}", ${DEFAULT_NOTE_FONT}`;
    context.font = `${note.italic ? 'italic ' : ''}${note.bold ? 'bold ' : ''}${String(emPixels)}px ${family}`;
    context.fillStyle = css(ink);
    context.textBaseline = 'top';
    const boxPixels = bottomRight.x - topLeft.x;
    note.lines.forEach((line, index) => {
      const width = context.measureText(line).width;
      // As AlignedLeft
      let left = topLeft.x;
      if (note.align === 'centre') {
        left += (boxPixels - width) / 2;
      } else if (note.align === 'right') {
        left += boxPixels - width;
      }
      context.fillText(line, left, topLeft.y + index * note.lineHeight * view.scale);
    });
  }

  // Its paths in model mm, so the canvas scales them, strokes too, as the view does
  private drawStamp(note: SceneNote, alpha: number): void {
    const view = this.paintState().view;
    const context = this.context;
    context.save();
    context.globalAlpha = alpha;
    context.transform(view.scale, 0, 0, view.scale, view.originX, view.originY);
    for (const path of note.stamp) {
      const shape = new Path2D(path.d);
      if (path.fill !== 'none') {
        context.fillStyle = path.fill;
        // The canvas's fill of a path, which the rule takes for Array.prototype.fill
        // oxlint-disable-next-line unicorn/no-array-fill-with-reference-type
        context.fill(shape, path.evenOdd ? 'evenodd' : 'nonzero');
      }
      if (path.stroke !== 'none') {
        context.strokeStyle = path.stroke;
        context.lineWidth = Math.max(path.strokeWidth, MIN_STAMP_STROKE_PIXELS / view.scale);
        context.stroke(shape);
      }
    }
    context.restore();
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
