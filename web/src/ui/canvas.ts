// The drawing canvas, as Sloper.UI.Canvas: shows the scene the engine gives,
// keeps the view (zoom and pan), the selection and the gestures: clicking to
// select, dragging a point, a note, a selected curve's handle or a callout's
// tip as one undo step, boxing a selection, panning with
// the middle button and zooming with the wheel. Other tools get the clicks and
// moves (Sloper.UI.CanvasTools). Every engine call is asynchronous; moves go
// through LatestOnly, so only the newest counts.
import type { DocumentChange, PatternDocument } from '../document/patternDocument.ts';
import { EngineError } from '../engine/engine.ts';
import {
  booleanField,
  idField,
  idsField,
  isRecord,
  numberField,
  numbersField,
  stringField,
  type JsonRecord,
} from '../engine/replies.ts';
import {
  EMPTY_SCENE,
  parseHandle,
  parseHandles,
  parseNote,
  parseScene,
  sceneBounds,
  type CurveHandle,
  type HandleRef,
  type Scene,
  type SceneNote,
  type Tables,
} from '../editor/scene.ts';
import { ViewTransform, ZOOM_STEP, type Rect2, type Vec2 } from '../editor/view.ts';
import {
  ClickTool,
  SNAP_KINDS,
  SNAP_RADIUS,
  SeamTool,
  SnapTool,
  type CanvasToolHandler,
  type CanvasToolHost,
} from './canvasTools.ts';
import { LatestOnly } from './latestOnly.ts';
import { NoteEditor } from './noteEditor.ts';
import {
  PatternPainter,
  type DraggedTip,
  type FieldGuide,
  type SnapMarker,
  type SuggestPreview,
} from './patternPainter.ts';

// A press that moves further than this, in pixels, is a drag, not a click
const DRAG_THRESHOLD = 4;
// Curves are flattened to within this many pixels
const FLATTEN_PIXELS = 0.25;
// How near a note's text a click must be, in pixels, as NOTE_HIT_PIXELS
const NOTE_HIT_PIXELS = 2;
// Points to mm, for a note's size
const POINTS_TO_MM = 25.4 / 72;
// Pixels left round the pattern when it is fitted
const FIT_MARGIN = 24;
// A zoom changed by less than this share of itself flattens nothing again
const ZOOM_UNCHANGED = 0.01;
// After the wheel stops this long, in ms, curves are flattened again for the new zoom
const ZOOM_SETTLE_MS = 150;
const MIDDLE_BUTTON = 1;
const LEFT_BUTTON = 0;
const RIGHT_BUTTON = 2;

// The tools that snap, and those that act where they are clicked
const SNAP_TOOLS = ['point', 'line', 'curve', 'circle', 'rectangle', 'text', 'callout'];
const CLICK_TOOLS = ['piece', 'notch'];

// As TLabelMode: the selection and what it works with, every object, or none
export type LabelMode = 'contextual' | 'all' | 'none';
export const LABEL_MODES: readonly LabelMode[] = ['contextual', 'all', 'none'];

export const SELECT_TOOL = 'select';

// idle; pressed: the left button is down, not yet moved; starting: a drag or
// box waits for the engine to say what was pressed; dragging; boxing;
// panning; refused: a drag the engine refused, until the button goes up
type CanvasMode = 'idle' | 'pressed' | 'starting' | 'dragging' | 'boxing' | 'panning' | 'refused';

export interface CanvasEvents {
  // What the status bar shows: a hint, a snap's description, a reason
  message(text: string): void;
  selectionChanged(ids: readonly string[]): void;
  failed(error: unknown): void;
}

// An object as the API takes it: by ID, or by name for a repeat's point not yet given one
export function targetParams(item: { id: string; name: string }): { id: number } | { name: string } {
  return /^\d+$/.test(item.id) ? { id: Number(item.id) } : { name: item.name };
}

// IDs as the API takes them; a repeat's point not yet given one is left out
function numericIds(list: Iterable<string>): number[] {
  return [...list].filter((id) => /^\d+$/.test(id)).map(Number);
}

// What lies under a place: the objects in the order a click picks them, and
// a selected callout's tip or curve's handle, which lie over them all
interface Hits {
  ids: string[];
  tip: string | undefined;
  handle: HandleRef | undefined;
}

const NO_HITS: Hits = { ids: [], tip: undefined, handle: undefined };

function distance(from: Vec2, to: Vec2): number {
  return Math.hypot(to.x - from.x, to.y - from.y);
}

// The path a drag by one field keeps to, as editor_drag_begin and _to give it
function parseGuide(answer: JsonRecord): FieldGuide | undefined {
  const guide = answer.guide;
  if (!isRecord(guide)) {
    return undefined;
  }
  const number = (name: string): number => numberField(guide, name) ?? 0;
  if (stringField(guide, 'kind') === 'circle') {
    return { kind: 'circle', centre: { x: number('cx'), y: number('cy') }, radius: number('radius') };
  }
  return { kind: 'line', from: { x: number('x1'), y: number('y1') }, to: { x: number('x2'), y: number('y2') } };
}

function sameHandle(one: HandleRef | undefined, other: HandleRef | undefined): boolean {
  return one?.edge === other?.edge && one?.field === other?.field;
}

export class PatternCanvas implements CanvasToolHost {
  readonly document: PatternDocument;
  readonly view = new ViewTransform();
  // The role of the edges the drawing tools make, as the role box chooses
  drawRole = 'outline';
  private readonly element: HTMLCanvasElement;
  private readonly painter: PatternPainter;
  private readonly tables: Tables;
  private readonly events: CanvasEvents;
  private readonly tools = new Map<string, CanvasToolHandler>();
  private readonly resizer: ResizeObserver;
  private readonly scenes: LatestOnly<number>;
  private readonly hovers: LatestOnly<Vec2>;
  private readonly drags: LatestOnly<Vec2>;
  private readonly labelQueue: LatestOnly<number>;
  private readonly handleQueue: LatestOnly<number>;
  // The selected curves' handles, and the one under the cursor
  private handles: CurveHandle[] = [];
  private hoverHandle: HandleRef | undefined;
  private labelIds: string[] = [];
  private labelMode: LabelMode = 'contextual';
  // Every label shows while the show-labels key is held
  private labelsHeld = false;
  // What the tool in use is working with, which is labelled too
  private toolIds: string[] = [];
  private seamA: number[][] = [];
  private seamB: number[][] = [];
  private readonly noteEditor: NoteEditor;
  private scene: Scene = EMPTY_SCENE;
  private selection = new Set<string>();
  private hoverId = '';
  private snap: SnapMarker | undefined;
  private tool = SELECT_TOOL;
  private mode: CanvasMode = 'idle';
  private pressAt: Vec2 = { x: 0, y: 0 };
  private lastAt: Vec2 = { x: 0, y: 0 };
  private pressShift = false;
  private pressHits: Promise<Hits> = Promise.resolve(NO_HITS);
  // The steps of the gesture under way, run in order
  private gesture: Promise<void> = Promise.resolve();
  private dragId = '';
  // A callout's tip is being dragged: it snaps, and changes nothing until dropped
  private dragTip = false;
  private draggedTip: DraggedTip | undefined;
  private dragOffset: Vec2 = { x: 0, y: 0 };
  // While a field's formula suggestions are open, dragging its point changes
  // only that field, along the guide drawn while it is dragged
  private lockId = '';
  private lockField = '';
  private fieldGuide: FieldGuide | undefined;
  // Where the suggestion being hovered would put things
  private suggestPreview: SuggestPreview | undefined;
  // A note drawn with the text being typed for it in the Properties tab
  private readonly notePreviews: LatestOnly<{ id: string; text: string } | undefined>;
  private previewNote: SceneNote | undefined;
  private previewNoteId: string | undefined;
  private generation = -1;
  // Fit each new scene to the window: from opening a pattern until the user
  // zooms, pans or edits, since its measurements may come after it and
  // bring the rest of it into view
  private autoFit = false;
  private frame = 0;
  private zoomTimer: ReturnType<typeof setTimeout> | undefined;
  private readonly listener = (_document: PatternDocument, changes: ReadonlySet<DocumentChange>): void => {
    this.documentChanged(changes);
  };

  constructor(element: HTMLCanvasElement, document: PatternDocument, tables: Tables, events: CanvasEvents) {
    this.element = element;
    this.document = document;
    this.tables = tables;
    this.events = events;
    const context = element.getContext('2d');
    if (context === null) {
      throw new Error('the browser cannot draw on a canvas');
    }
    this.painter = new PatternPainter(context);
    for (const name of SNAP_TOOLS) {
      this.tools.set(name, new SnapTool(this, name));
    }
    for (const name of CLICK_TOOLS) {
      this.tools.set(name, new ClickTool(this, name));
    }
    this.tools.set('seam', new SeamTool(this, 'seam'));
    this.noteEditor = new NoteEditor(element.parentElement ?? window.document.body, document, (text) => {
      this.events.message(text);
    });
    const fail = (error: unknown): void => {
      this.report(error);
    };
    this.scenes = new LatestOnly(async (tolerance) => this.loadScene(tolerance), fail);
    this.hovers = new LatestOnly(async (at) => this.updateHover(at), fail);
    this.drags = new LatestOnly(async (at) => this.dragTo(at), fail);
    this.labelQueue = new LatestOnly(async () => this.loadLabels(), fail);
    this.handleQueue = new LatestOnly(async () => this.loadHandles(), fail);
    this.notePreviews = new LatestOnly(async (typed) => this.loadNotePreview(typed), fail);
    document.addListener(this.listener);
    this.resizer = new ResizeObserver(() => {
      this.resize();
    });
    this.resizer.observe(element);
    element.addEventListener('pointerdown', this.pointerDown);
    element.addEventListener('pointermove', this.pointerMove);
    element.addEventListener('pointerup', this.pointerUp);
    element.addEventListener('pointerleave', this.pointerLeave);
    element.addEventListener('wheel', this.wheel, { passive: false });
    element.addEventListener('dblclick', this.doubleClick);
    element.addEventListener('contextmenu', (event) => {
      event.preventDefault();
    });
  }

  // Stops listening to the document, so a closed canvas is not kept alive
  dispose(): void {
    this.document.removeListener(this.listener);
    this.resizer.disconnect();
  }

  get selectedIds(): readonly string[] {
    return [...this.selection];
  }

  get toolName(): string {
    return this.tool;
  }

  setTool(name: string): void {
    if (name !== SELECT_TOOL && !this.tools.has(name)) {
      return;
    }
    this.tools.get(this.tool)?.reset();
    this.tool = name;
    this.tools.get(name)?.reset();
    this.hoverId = '';
    this.hoverHandle = undefined;
    this.showSnap(undefined);
    this.events.message(this.tables.tools.find((tool) => tool.name === name)?.hint ?? '');
  }

  // Which tools the canvas has so far
  hasTool(name: string): boolean {
    return name === SELECT_TOOL || this.tools.has(name);
  }

  // Shows everything, as the Fit command
  fitAll(): void {
    const bounds = sceneBounds(this.scene);
    if (bounds === undefined) {
      return;
    }
    const scale = this.view.scale;
    this.view.fit(bounds, this.element.clientWidth, this.element.clientHeight, FIT_MARGIN);
    // Curves are flattened again only for another zoom: a fit after each
    // scene, while the pattern is first shown, would otherwise never stop
    if (Math.abs(this.view.scale - scale) > scale * ZOOM_UNCHANGED) {
      this.zoomed();
    } else {
      this.repaint();
    }
  }

  // Brings the selection into view without zooming in, as when it is chosen in a list
  async revealSelection(): Promise<void> {
    const bounds = await this.selectionBounds();
    if (bounds !== undefined) {
      this.autoFit = false;
      this.view.reveal(bounds, this.element.clientWidth, this.element.clientHeight, FIT_MARGIN);
      this.repaint();
    }
  }

  // Fills the window with the selection, as double-clicking it in a list
  async zoomToSelection(): Promise<void> {
    const bounds = await this.selectionBounds();
    if (bounds !== undefined) {
      this.autoFit = false;
      this.view.fit(bounds, this.element.clientWidth, this.element.clientHeight, FIT_MARGIN);
      this.zoomed();
    }
  }

  private async selectionBounds(): Promise<Rect2 | undefined> {
    const answer = await this.document.read('editor_bounds', { ids: numericIds(this.selection) });
    const [minX, minY, maxX, maxY] = numbersField(answer, 'bounds') ?? [];
    if (minX === undefined || minY === undefined || maxX === undefined || maxY === undefined) {
      return undefined;
    }
    return { minX, minY, maxX, maxY };
  }

  // Escape: drops a drag, then the tool's step, then the selection
  cancel(): void {
    if (this.mode === 'dragging' || this.mode === 'starting') {
      this.mode = 'refused';
      this.gesture = this.gesture.then(async () => this.endDrag(true));
      return;
    }
    if (this.tools.get(this.tool)?.cancel() === true) {
      return;
    }
    this.select([]);
  }

  // CanvasToolHost

  select(ids: string[]): void {
    this.selection = new Set(ids);
    this.events.selectionChanged(ids);
    this.handleQueue.push(0);
    this.relabel();
    this.repaint();
  }

  showToolObjects(ids: string[]): void {
    if (ids.join(' ') !== this.toolIds.join(' ')) {
      this.toolIds = ids;
      this.relabel();
    }
  }

  showSeamSides(sideA: number[][], sideB: number[][]): void {
    this.seamA = sideA;
    this.seamB = sideB;
    this.repaint();
  }

  showSnap(snap: SnapMarker | undefined): void {
    this.snap = snap;
    this.repaint();
  }

  showMessage(text: string): void {
    this.events.message(text);
  }

  // Opens the note's text to type, once the scene shows it
  noteAdded(id: string): void {
    this.editNote(id).catch((error: unknown) => {
      this.report(error);
    });
  }

  private async editNote(id: string): Promise<void> {
    await this.scenes.idle();
    const note = this.scene.notes.find((each) => each.id === id);
    if (note !== undefined) {
      const at = this.view.toScreen({ x: note.box.minX, y: note.box.minY });
      await this.noteEditor.open(id, at, note.size * POINTS_TO_MM * this.view.scale);
    }
  }

  // Double-clicking a note goes to its text
  private readonly doubleClick = (event: MouseEvent): void => {
    if (this.tool !== SELECT_TOOL) {
      return;
    }
    const at = this.screenAt(event);
    this.objectsAt(at)
      .then((hits) => {
        const id = hits.ids[0];
        if (id !== undefined && this.scene.notes.some((note) => note.id === id)) {
          this.select([id]);
          this.noteAdded(id);
        }
        return undefined;
      })
      .catch((error: unknown) => {
        this.report(error);
      });
  };

  pointAt(id: string): Vec2 | undefined {
    return this.scene.points.find((point) => point.id === id);
  }

  fail(error: unknown): void {
    this.events.failed(error);
  }

  // The objects labelled now, as Export Draft SVG writes them
  get shownLabels(): readonly string[] {
    return this.labelIds;
  }

  get labels(): LabelMode {
    return this.labelMode;
  }

  set labels(mode: LabelMode) {
    this.labelMode = mode;
    this.relabel();
  }

  // The show-labels key held or let go
  holdLabels(held: boolean): void {
    if (held !== this.labelsHeld) {
      this.labelsHeld = held;
      this.relabel();
    }
  }

  // A key for the tool in use, such as Tab and Enter for the Seam tool; true when it took it
  toolKeyDown(event: KeyboardEvent): boolean {
    return this.tools.get(this.tool)?.keyDown(event) ?? false;
  }

  // Drawing

  private relabel(): void {
    this.labelQueue.push(0);
  }

  private async loadLabels(): Promise<void> {
    const answer = await this.document.read('editor_label_keys', {
      mode: this.labelsHeld ? 'all' : this.labelMode,
      selection: numericIds(this.selection),
      hover: /^\d+$/.test(this.hoverId) ? Number(this.hoverId) : null,
      tool: numericIds(this.toolIds),
    });
    this.labelIds = idsField(answer, 'objects');
    this.repaint();
  }

  private async loadHandles(): Promise<void> {
    const answer = await this.document.read('editor_handles', { selection: numericIds(this.selection) });
    this.handles = parseHandles(answer);
    this.repaint();
  }

  private repaint(): void {
    if (this.frame !== 0) {
      return;
    }
    this.frame = requestAnimationFrame(() => {
      this.frame = 0;
      this.paint();
    });
  }

  private paint(): void {
    const box: [Vec2, Vec2] | undefined = this.mode === 'boxing' ? [this.pressAt, this.lastAt] : undefined;
    this.painter.beginFrame(this.element.clientWidth, this.element.clientHeight, {
      view: this.view,
      selection: this.selection,
      hoverId: this.hoverId,
      snap: this.snap,
      box,
      labelIds: this.labelIds,
      seamA: this.seamA,
      seamB: this.seamB,
      handles: this.handles,
      hoverHandle: this.hoverHandle,
      tipHandles: this.tool === SELECT_TOOL,
      draggedTip: this.draggedTip,
      fieldGuide: this.mode === 'dragging' ? this.fieldGuide : undefined,
      suggestPreview: this.suggestPreview,
    });
    this.painter.drawGrid();
    this.painter.drawPattern(this.scene, this.tables);
    this.painter.drawSeams(this.scene);
    const preview = this.previewNote;
    this.painter.drawNotes(
      preview === undefined
        ? this.scene
        : { ...this.scene, notes: this.scene.notes.map((note) => (note.id === preview.id ? preview : note)) },
    );
    if (this.tool === SELECT_TOOL) {
      this.painter.drawHandles();
    }
    this.painter.drawLabels(this.scene);
    this.painter.drawSnap();
    this.painter.drawBox();
    this.painter.drawFieldGuide();
    this.painter.drawSuggestPreview();
  }

  // While a field's formula suggestions are open, dragging its point changes
  // only that field; empty strings unlock
  setFieldLock(id: string, field: string): void {
    this.lockId = id;
    this.lockField = field;
  }

  // Draws the note with the text being typed for it, or as it is when undefined
  showNoteText(id: string | undefined, text = ''): void {
    this.previewNoteId = id;
    if (id === undefined) {
      this.notePreviews.clear();
      // Kept until a scene asked for by a commit comes, so the old text never shows between
      this.scenes
        .idle()
        .then(() => {
          if (this.previewNoteId === undefined && this.previewNote !== undefined) {
            this.previewNote = undefined;
            this.repaint();
          }
          return undefined;
        })
        .catch((error: unknown) => {
          this.report(error);
        });
      return;
    }
    this.notePreviews.push({ id, text });
  }

  private async loadNotePreview(typed: { id: string; text: string } | undefined): Promise<void> {
    if (typed === undefined) {
      return;
    }
    const answer = await this.document.read('editor_note_preview', {
      id: Number(typed.id),
      text: typed.text,
      fileName: this.document.fileName,
    });
    const note = answer.note;
    // Ended while the engine worked
    if (this.previewNoteId !== typed.id) {
      return;
    }
    this.previewNote = isRecord(note) ? parseNote(note) : undefined;
    this.repaint();
  }

  // A hovered suggestion's ghosts, or undefined to take them away
  showSuggestPreview(preview: SuggestPreview | undefined): void {
    this.suggestPreview = preview;
    this.repaint();
  }

  private resize(): void {
    const ratio = window.devicePixelRatio;
    this.element.width = Math.round(this.element.clientWidth * ratio);
    this.element.height = Math.round(this.element.clientHeight * ratio);
    this.element.getContext('2d')?.setTransform(ratio, 0, 0, ratio, 0, 0);
    this.repaint();
  }

  // The scene

  private documentChanged(changes: ReadonlySet<DocumentChange>): void {
    if (this.document.state.generation !== this.generation) {
      // Another pattern: what was selected or shown means nothing now
      this.generation = this.document.state.generation;
      this.autoFit = true;
      this.noteEditor.close();
      this.selection.clear();
      this.events.selectionChanged([]);
    } else if (changes.has('pattern') && !changes.has('measurements')) {
      // An edit: the view stays where the user is working
      this.autoFit = false;
    }
    if (
      changes.has('pattern') ||
      changes.has('objectsReplaced') ||
      changes.has('measurements') ||
      changes.has('view')
    ) {
      this.reloadScene();
    }
  }

  private reloadScene(): void {
    this.scenes.push(this.view.pixelsToMM(FLATTEN_PIXELS));
  }

  private async loadScene(tolerance: number): Promise<void> {
    this.scene = parseScene(await this.document.read('editor_scene', { tolerance, fileName: this.document.fileName }));
    if (this.autoFit) {
      this.fitAll();
    }
    // Objects gone, as after undo, leave the selection
    const shown = new Set(
      [...this.scene.pieces, ...this.scene.edges, ...this.scene.seams, ...this.scene.notes, ...this.scene.points].map(
        (item) => item.id,
      ),
    );
    const kept = [...this.selection].filter((id) => shown.has(id));
    if (kept.length !== this.selection.size) {
      this.select(kept);
    }
    this.tools.get(this.tool)?.sceneChanged();
    this.handleQueue.push(0);
    this.relabel();
    this.repaint();
  }

  private zoomed(): void {
    this.repaint();
    if (this.zoomTimer !== undefined) {
      clearTimeout(this.zoomTimer);
    }
    this.zoomTimer = setTimeout(() => {
      this.zoomTimer = undefined;
      this.reloadScene();
    }, ZOOM_SETTLE_MS);
  }

  // Input

  private screenAt(event: MouseEvent): Vec2 {
    const bounds = this.element.getBoundingClientRect();
    return { x: event.clientX - bounds.left, y: event.clientY - bounds.top };
  }

  private async objectsAt(at: Vec2): Promise<Hits> {
    const model = this.view.toModel(at);
    const radius = this.view.pixelsToMM(SNAP_RADIUS);
    const answer = await this.document.read('editor_objects_at', {
      x: model.x,
      y: model.y,
      pointRadius: radius,
      edgeRadius: radius,
      noteMargin: this.view.pixelsToMM(NOTE_HIT_PIXELS),
      fileName: this.document.fileName,
      selection: numericIds(this.selection),
    });
    const handle = answer.handle;
    return {
      ids: idsField(answer, 'objects'),
      tip: idField(answer, 'tip'),
      handle: parseHandle(isRecord(handle) ? handle : undefined),
    };
  }

  private readonly pointerDown = (event: PointerEvent): void => {
    if (this.mode !== 'idle') {
      return;
    }
    const at = this.screenAt(event);
    this.pressAt = at;
    this.lastAt = at;
    if (event.button === MIDDLE_BUTTON) {
      this.mode = 'panning';
      this.autoFit = false;
    } else if (event.button === RIGHT_BUTTON) {
      // Drops a tool's first click, as on the desktop
      this.tools.get(this.tool)?.cancel();
      return;
    } else if (event.button === LEFT_BUTTON) {
      this.mode = 'pressed';
      this.pressShift = event.shiftKey;
      if (this.tool === SELECT_TOOL) {
        this.pressHits = this.objectsAt(at);
        // Read again where it is used; a failure here is reported there
        this.pressHits.catch(() => undefined);
      }
    } else {
      return;
    }
    this.element.setPointerCapture(event.pointerId);
    event.preventDefault();
  };

  private readonly pointerMove = (event: PointerEvent): void => {
    const at = this.screenAt(event);
    const previous = this.lastAt;
    this.lastAt = at;
    switch (this.mode) {
      case 'idle':
        if (this.tool === SELECT_TOOL) {
          this.hovers.push(at);
        } else {
          this.tools.get(this.tool)?.move(at);
        }
        break;
      case 'panning':
        this.view.pan(at.x - previous.x, at.y - previous.y);
        this.repaint();
        break;
      case 'pressed':
        if (this.tool === SELECT_TOOL && distance(this.pressAt, at) > DRAG_THRESHOLD) {
          this.mode = 'starting';
          this.gesture = this.gesture.then(async () => this.startDragOrBox());
        }
        break;
      case 'dragging':
        this.drags.push(at);
        break;
      case 'boxing':
        this.repaint();
        break;
      case 'starting':
      case 'refused':
        break;
    }
  };

  private readonly pointerUp = (event: PointerEvent): void => {
    const at = this.screenAt(event);
    this.lastAt = at;
    switch (this.mode) {
      case 'panning':
      case 'refused':
        this.mode = 'idle';
        break;
      case 'pressed':
        this.mode = 'idle';
        if (this.tool === SELECT_TOOL) {
          const shift = this.pressShift;
          this.gesture = this.gesture.then(async () => this.clickSelect(shift));
        } else {
          this.tools.get(this.tool)?.click(at, this.pressShift);
        }
        break;
      case 'starting':
      case 'dragging':
      case 'boxing':
        // After the drag or box has started, whenever that is
        this.gesture = this.gesture.then(async () => this.finishGesture());
        break;
      case 'idle':
        break;
    }
    this.gesture = this.gesture.catch((error: unknown) => {
      this.mode = 'idle';
      this.report(error);
    });
  };

  private readonly pointerLeave = (): void => {
    if (this.mode === 'idle') {
      this.hovers.clear();
      this.tools.get(this.tool)?.leave();
      if (this.hoverId !== '' || this.hoverHandle !== undefined) {
        this.hoverId = '';
        this.hoverHandle = undefined;
        this.repaint();
      }
    }
  };

  private readonly wheel = (event: WheelEvent): void => {
    event.preventDefault();
    this.autoFit = false;
    this.view.zoomAt(event.deltaY < 0 ? ZOOM_STEP : 1 / ZOOM_STEP, this.screenAt(event));
    this.zoomed();
  };

  private async updateHover(at: Vec2): Promise<void> {
    const hits = await this.objectsAt(at);
    if (!sameHandle(hits.handle, this.hoverHandle)) {
      this.hoverHandle = hits.handle;
      this.repaint();
    }
    const id = hits.ids[0] ?? '';
    if (id !== this.hoverId) {
      this.hoverId = id;
      this.relabel();
      this.repaint();
    }
  }

  private async clickSelect(toggle: boolean): Promise<void> {
    const hits = await this.pressHits;
    // A click on a handle or a callout's tip leaves the selection as it is
    if (hits.tip !== undefined || hits.handle !== undefined) {
      return;
    }
    const id = hits.ids[0];
    if (id === undefined) {
      if (!toggle) {
        this.select([]);
      }
      return;
    }
    if (!toggle) {
      this.select([id]);
    } else if (this.selection.has(id)) {
      this.select([...this.selection].filter((each) => each !== id));
    } else {
      this.select([...this.selection, id]);
    }
  }

  // A press on a handle, a point or a note drags it; anywhere else draws a selection box
  private async startDragOrBox(): Promise<void> {
    const hits = await this.pressHits;
    if (hits.tip !== undefined) {
      // The tip goes where the pointer is, snapped
      this.dragTip = true;
      await this.beginDrag(hits.tip, { id: Number(hits.tip), tip: true }, this.view.toModel(this.pressAt));
      return;
    }
    if (hits.handle !== undefined) {
      await this.startHandleDrag(hits.handle);
      return;
    }
    const id = hits.ids[0];
    const note = this.scene.notes.find((each) => each.id === id);
    // A note is dragged by its text's top left
    const point =
      note === undefined
        ? this.scene.points.find((each) => each.id === id)
        : { id: note.id, name: note.name, x: note.box.minX, y: note.box.minY };
    if (point === undefined) {
      this.mode = 'boxing';
      this.repaint();
      return;
    }
    const params: Record<string, unknown> = { ...targetParams(point) };
    if (point.id === this.lockId && note === undefined) {
      params.field = this.lockField;
    }
    await this.beginDrag(point.id, params, point);
  }

  private async startHandleDrag(handle: HandleRef): Promise<void> {
    const shown = this.handles.find((each) => each.edge === handle.edge && each.field === handle.field);
    if (shown === undefined) {
      this.mode = 'idle';
      return;
    }
    await this.beginDrag(handle.edge, { id: Number(handle.edge), handle: handle.field }, shown.at);
  }

  // Opens the drag in the engine, keeping the press's offset from where the object is
  private async beginDrag(id: string, params: object, from: Vec2): Promise<void> {
    try {
      this.fieldGuide = parseGuide(await this.document.call('editor_drag_begin', params));
    } catch (error: unknown) {
      this.mode = 'refused';
      this.dragTip = false;
      throw error;
    }
    this.dragId = id;
    const pressed = this.view.toModel(this.pressAt);
    this.dragOffset = { x: from.x - pressed.x, y: from.y - pressed.y };
    if (this.mode === 'refused') {
      // Escape came while the drag was starting
      await this.endDrag(true);
      return;
    }
    this.mode = 'dragging';
    this.hoverId = '';
    this.drags.push(this.lastAt);
  }

  private async dragTo(at: Vec2): Promise<void> {
    if (this.dragId === '') {
      return;
    }
    const model = this.view.toModel(at);
    if (this.dragTip) {
      await this.tipTo(model);
      return;
    }
    const answer = await this.document.call('editor_drag_to', {
      x: model.x + this.dragOffset.x,
      y: model.y + this.dragOffset.y,
    });
    this.fieldGuide = parseGuide(answer);
    // As on the desktop, only a drag that cannot follow says why
    if (booleanField(answer, 'moved') === false) {
      this.events.message(stringField(answer, 'reason') ?? '');
    }
  }

  // Shows where the tip snaps and the leader to it, and says what it would point at
  private async tipTo(model: Vec2): Promise<void> {
    const answer = await this.document.read('editor_drag_to', {
      x: model.x,
      y: model.y,
      radius: this.view.pixelsToMM(SNAP_RADIUS),
      fileName: this.document.fileName,
    });
    const snapped = { x: numberField(answer, 'x') ?? model.x, y: numberField(answer, 'y') ?? model.y };
    this.draggedTip = { id: this.dragId, at: snapped, leaderStrokes: numbersField(answer, 'leaderStrokes') ?? [] };
    this.showSnap({ kind: SNAP_KINDS.find((each) => each === stringField(answer, 'kind')) ?? 'free', at: snapped });
    this.events.message(stringField(answer, 'message') ?? '');
  }

  // Ends the drag once its last move has run; a cancel drops moves still waiting
  private async endDrag(cancel: boolean): Promise<void> {
    if (cancel) {
      this.drags.clear();
    }
    await this.drags.idle();
    const id = this.dragId;
    this.dragId = '';
    const tip = this.dragTip;
    this.dragTip = false;
    this.fieldGuide = undefined;
    if (id === '') {
      return;
    }
    try {
      await this.document.call(cancel ? 'editor_drag_cancel' : 'editor_drag_end');
    } finally {
      // The scene shows the tip where it was dropped, or where it was
      if (tip) {
        this.draggedTip = undefined;
        this.showSnap(undefined);
      }
    }
    if (!cancel && !this.selection.has(id)) {
      this.select([id]);
    }
  }

  private async finishGesture(): Promise<void> {
    const mode = this.mode;
    this.mode = 'idle';
    if (mode === 'dragging') {
      this.drags.push(this.lastAt);
      await this.endDrag(false);
    } else if (mode === 'boxing') {
      await this.selectBox(this.pressShift);
    }
    this.repaint();
  }

  private async selectBox(add: boolean): Promise<void> {
    const first = this.view.toModel(this.pressAt);
    const last = this.view.toModel(this.lastAt);
    const answer = await this.document.read('editor_objects_in_box', {
      minX: Math.min(first.x, last.x),
      minY: Math.min(first.y, last.y),
      maxX: Math.max(first.x, last.x),
      maxY: Math.max(first.y, last.y),
    });
    const ids = idsField(answer, 'objects');
    this.select(add ? [...new Set([...this.selection, ...ids])] : ids);
  }

  private report(error: unknown): void {
    if (error instanceof EngineError) {
      this.events.message(error.message);
    } else {
      this.events.failed(error);
    }
  }
}
