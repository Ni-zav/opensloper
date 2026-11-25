// The canvas's drawing tools, one object each, as Sloper.UI.CanvasTools: what
// a click or a move does and what the tool snaps to. The canvas keeps pan,
// zoom and the select tool's drags and boxes, and hands the rest to the tool
// in use. What a click makes is the engine's (Sloper.Editor.ToolEdits,
// through editor_tool_snap and editor_tool_click), so a click does the same
// as on the desktop; the tools here keep the first click of a two-click tool
// and show where the next would snap.
import type { PatternDocument } from '../document/patternDocument.ts';
import { EngineError } from '../engine/engine.ts';
import {
  booleanField,
  idField,
  idsField,
  isRecord,
  numberField,
  recordsField,
  stringField,
  type JsonRecord,
} from '../engine/replies.ts';
import { linesField } from '../editor/scene.ts';
import type { Vec2, ViewTransform } from '../editor/view.ts';
import { LatestOnly } from './latestOnly.ts';
import type { SnapKind, SnapMarker, SnapPreview } from './patternPainter.ts';

// Screen pixels around the pointer that a tool snaps to or picks from, as SNAP_RADIUS
export const SNAP_RADIUS = 8;

export const SNAP_KINDS: readonly SnapKind[] = [
  'free',
  'point',
  'crossing',
  'edge',
  'horizontal',
  'vertical',
  'offset',
];

// What a tool needs of the canvas
export interface CanvasToolHost {
  readonly document: Pick<PatternDocument, 'read' | 'call'>;
  readonly view: ViewTransform;
  // The role of the edges the drawing tools make
  readonly drawRole: string;
  select(ids: string[]): void;
  showSnap(snap: SnapMarker | undefined): void;
  showMessage(text: string): void;
  // The objects the tool is working with, which are labelled
  showToolObjects(ids: string[]): void;
  // The sides of the seam being picked, a polyline per edge
  showSeamSides(sideA: number[][], sideB: number[][]): void;
  // A note was added: its text is typed next
  noteAdded(id: string): void;
  // Where a point is, for the guide to the point a snap lines up with
  pointAt(id: string): Vec2 | undefined;
  // A failure that is no refusal of the engine's, which the page reports
  fail(error: unknown): void;
}

// A place as the engine's tool methods take it
interface ToolPlace {
  x: number;
  y: number;
  radius: number;
}

export abstract class CanvasToolHandler {
  protected readonly host: CanvasToolHost;
  // The engine's name for the tool
  readonly name: string;

  constructor(host: CanvasToolHost, name: string) {
    this.host = host;
    this.name = name;
  }

  // Back to the tool's first step, as when it is chosen again
  reset(): void {}

  // A left click at a screen place; shift when Shift was held
  click(_at: Vec2, _shift: boolean): void {}

  // The pointer moved over the canvas, no button held
  move(_at: Vec2): void {}

  // A press at pressAt moved far enough to be a drag: true when the tool takes
  // it, and then has dragMove and dragEnd instead of a click
  dragStart(_pressAt: Vec2): boolean {
    return false;
  }

  dragMove(_at: Vec2): void {}

  dragEnd(_at: Vec2): void {}

  // Escape or a right click: true when the tool had something to drop
  cancel(): boolean {
    return false;
  }

  // The pointer left the canvas
  leave(): void {}

  // A key besides Escape: true when the tool took it
  keyDown(_event: KeyboardEvent): boolean {
    return false;
  }

  // The pattern changed, as after undo, so what the tool holds may be gone
  sceneChanged(): void {}

  // The place a screen point is, with the snapping radius at this zoom
  protected place(at: Vec2): ToolPlace {
    const model = this.host.view.toModel(at);
    return { x: model.x, y: model.y, radius: this.host.view.pixelsToMM(SNAP_RADIUS) };
  }

  // Does the tool's click in the engine, selecting and saying what it answers
  protected async toolClick(params: object): Promise<Record<string, unknown>> {
    const answer = await this.host.document.call('editor_tool_click', { tool: this.name, ...params });
    if (answer.select !== null) {
      this.host.select(idsField(answer, 'select'));
    }
    const message = stringField(answer, 'message') ?? '';
    if (message !== '') {
      this.host.showMessage(message);
    }
    return answer;
  }

  // A refusal is told to the user; anything else is a failure
  protected report(error: unknown): void {
    if (error instanceof EngineError) {
      this.host.showMessage(error.message);
    } else {
      this.host.fail(error);
    }
  }
}

// What a two-click tool draws from its first click to where the second would go
const PREVIEWS: Record<string, SnapPreview> = {
  line: 'line',
  curve: 'line',
  circle: 'circle',
  rectangle: 'rectangle',
};

// Shows where a click would snap as the pointer moves, asking the engine for
// the newest place only. Point makes a point at each click; line, curve,
// circle and rectangle keep their first click as the start, and a line or
// curve carries on from the end of the last.
export class SnapTool extends CanvasToolHandler {
  private readonly snaps: LatestOnly<Vec2>;
  private start: ToolPlace | undefined;
  // Where the first click snapped, which the preview is drawn from
  private startAt: Vec2 | undefined;
  // The curve the last click made, which Shift+click carries on
  private lastCurve = '';
  private lastAt: Vec2 | undefined;
  // Where the Point tool's drag was pressed; a drag from a point places it
  // from another (editor_rebase_point)
  private dragFrom: ToolPlace | undefined;
  private readonly dragSnaps: LatestOnly<Vec2>;

  constructor(host: CanvasToolHost, name: string) {
    super(host, name);
    this.snaps = new LatestOnly(
      async (at) => this.updateSnap(at),
      (error) => {
        this.report(error);
      },
    );
    this.dragSnaps = new LatestOnly(
      async (at) => this.updateDragSnap(at),
      (error) => {
        this.report(error);
      },
    );
  }

  override dragStart(pressAt: Vec2): boolean {
    if (this.name !== 'point') {
      return false;
    }
    this.snaps.clear();
    this.dragFrom = this.place(pressAt);
    return true;
  }

  override dragMove(at: Vec2): void {
    this.lastAt = at;
    this.dragSnaps.push(at);
  }

  override dragEnd(at: Vec2): void {
    this.finishDrag(at).catch((error: unknown) => {
      this.report(error);
    });
  }

  // A drag from a point re-points it; one from anywhere else is the click it was before
  private async finishDrag(at: Vec2): Promise<void> {
    const from = this.dragFrom;
    this.dragSnaps.clear();
    await this.dragSnaps.idle();
    this.dragFrom = undefined;
    if (from === undefined) {
      return;
    }
    // Asked again, as the release may come before any preview's answer
    const drop = await this.host.document.read('editor_rebase_snap', { from, ...this.place(at) });
    if (!isRecord(drop.from)) {
      await this.commit(at, false);
      return;
    }
    const answer = await this.host.document.call('editor_rebase_point', { from, ...this.place(at) });
    if (answer.select !== null) {
      this.host.select(idsField(answer, 'select'));
    }
    // What it did stays up until the pointer moves
    this.host.showSnap(undefined);
    this.host.showToolObjects([]);
    this.host.showMessage(stringField(answer, 'message') ?? '');
  }

  private async updateDragSnap(at: Vec2): Promise<void> {
    if (this.dragFrom === undefined) {
      return;
    }
    const answer = await this.host.document.read('editor_rebase_snap', { from: this.dragFrom, ...this.place(at) });
    const from = answer.from;
    if (!isRecord(from)) {
      return;
    }
    this.host.showSnap({
      kind: SNAP_KINDS.find((each) => each === stringField(answer, 'kind')) ?? 'free',
      at: { x: numberField(answer, 'x') ?? 0, y: numberField(answer, 'y') ?? 0 },
      preview: { kind: 'line', from: { x: numberField(from, 'x') ?? 0, y: numberField(from, 'y') ?? 0 } },
    });
    this.host.showMessage(stringField(answer, 'description') ?? '');
    const dragged = idField(from, 'id');
    this.host.showToolObjects([...(dragged === undefined ? [] : [dragged]), ...idsField(answer, 'objects')]);
  }

  override move(at: Vec2): void {
    this.lastAt = at;
    this.snaps.push(at);
  }

  override leave(): void {
    this.snaps.clear();
    this.lastAt = undefined;
    this.host.showSnap(undefined);
    this.host.showToolObjects([]);
  }

  override reset(): void {
    this.dropStart();
    this.leave();
  }

  override cancel(): boolean {
    if (this.dragFrom !== undefined) {
      this.dragFrom = undefined;
      this.dragSnaps.clear();
      this.host.showSnap(undefined);
      this.host.showMessage('');
      return true;
    }
    if (this.start === undefined) {
      return false;
    }
    this.dropStart();
    if (this.lastAt !== undefined) {
      this.snaps.push(this.lastAt);
    }
    return true;
  }

  override click(at: Vec2, shift: boolean): void {
    this.commit(at, shift).catch((error: unknown) => {
      this.report(error);
    });
  }

  private dropStart(): void {
    this.start = undefined;
    this.startAt = undefined;
    this.lastCurve = '';
  }

  private async commit(at: Vec2, shift: boolean): Promise<void> {
    // The snap shown is the one clicked: wait for it to catch up
    this.snaps.clear();
    await this.snaps.idle();
    const here = this.place(at);
    const params: Record<string, unknown> = { ...here, role: this.host.drawRole };
    if (this.start !== undefined) {
      params.start = this.start;
    }
    if (shift && this.name === 'curve' && this.lastCurve !== '') {
      params.extend = /^\d+$/.test(this.lastCurve) ? Number(this.lastCurve) : this.lastCurve;
    }
    const answer = await this.toolClick(params);
    const made = idsField(answer, 'select')[0];
    if (
      (this.name === 'text' || this.name === 'callout') &&
      booleanField(answer, 'done') === true &&
      made !== undefined
    ) {
      this.dropStart();
      this.host.noteAdded(made);
      return;
    }
    if (booleanField(answer, 'started') === true) {
      // The message asking for the second click stays until the pointer moves
      this.start = here;
      this.startAt = undefined;
      return;
    } else if (this.name in PREVIEWS && booleanField(answer, 'done') === true) {
      const end = answer.end;
      if (isRecord(end)) {
        // A line or curve carries on from where it ended, which is now a point
        const endAt = { x: numberField(end, 'x') ?? 0, y: numberField(end, 'y') ?? 0 };
        this.start = { ...endAt, radius: this.host.view.pixelsToMM(SNAP_RADIUS) };
        this.startAt = endAt;
        this.lastCurve = idField(answer, 'curve') ?? '';
      } else {
        this.dropStart();
      }
    } else if (stringField(answer, 'message') !== '') {
      // Refused: start again
      this.dropStart();
    }
    this.snaps.push(at);
  }

  private async updateSnap(at: Vec2): Promise<void> {
    const params: Record<string, unknown> = { tool: this.name, ...this.place(at) };
    if (this.start !== undefined) {
      params.start = this.start;
    }
    const answer = await this.host.document.read('editor_tool_snap', params);
    const kind = SNAP_KINDS.find((each) => each === stringField(answer, 'kind')) ?? 'free';
    const start = answer.start;
    if (this.start !== undefined && isRecord(start)) {
      this.startAt = { x: numberField(start, 'x') ?? 0, y: numberField(start, 'y') ?? 0 };
    }
    const lined = kind === 'horizontal' || kind === 'vertical' ? idsField(answer, 'objects')[0] : undefined;
    const preview = PREVIEWS[this.name];
    this.host.showSnap({
      kind,
      at: { x: numberField(answer, 'x') ?? 0, y: numberField(answer, 'y') ?? 0 },
      guideFrom: lined === undefined ? undefined : this.host.pointAt(lined),
      preview: this.startAt !== undefined && preview !== undefined ? { kind: preview, from: this.startAt } : undefined,
    });
    this.host.showMessage(stringField(answer, 'description') ?? '');
    this.host.showToolObjects([...idsField(answer, 'startObjects'), ...idsField(answer, 'objects')]);
  }
}

// A click does the tool's job where it is: piece makes a piece of the outline
// round it, notch adds or removes a notch there
export class ClickTool extends CanvasToolHandler {
  override click(at: Vec2): void {
    this.toolClick(this.place(at)).catch((error: unknown) => {
      this.report(error);
    });
  }
}

// Clicks pick the edges of side A; Tab moves to side B (Shift+Tab back),
// Enter makes the seam, Escape drops what was picked
export class SeamTool extends CanvasToolHandler {
  private sideA: JsonRecord[] = [];
  private sideB: JsonRecord[] = [];
  private onB = false;
  // Each step waits for the one before, so Enter makes the seam with every
  // edge clicked before it, however fast
  private steps: Promise<void> | undefined;
  private generation = 0;

  private queue(step: (generation: number) => Promise<void>): void {
    const generation = this.generation;
    const pending = (this.steps ?? Promise.resolve())
      .then(() => (generation === this.generation ? step(generation) : undefined))
      .catch((error: unknown) => {
        if (generation === this.generation) {
          this.report(error);
        }
      })
      .finally(() => {
        if (this.steps === pending) {
          this.steps = undefined;
        }
      });
    this.steps = pending;
  }

  override reset(): void {
    this.generation++;
    this.steps = undefined;
    this.sideA = [];
    this.sideB = [];
    this.onB = false;
    this.host.showSeamSides([], []);
  }

  override cancel(): boolean {
    const picking = this.steps !== undefined || this.sideA.length > 0 || this.sideB.length > 0 || this.onB;
    if (picking) {
      this.reset();
    }
    return picking;
  }

  override click(at: Vec2): void {
    const place = this.place(at);
    this.queue(async (generation) => this.pick(place, generation));
  }

  override keyDown(event: KeyboardEvent): boolean {
    if (event.key === 'Tab') {
      const onB = !event.shiftKey;
      this.queue(async (generation) => {
        this.onB = onB;
        await this.pick({}, generation);
      });
      return true;
    }
    if (event.key === 'Enter') {
      this.queue(async (generation) => this.make(generation));
      return true;
    }
    return false;
  }

  // Undo may have taken away a piece or edge picked
  override sceneChanged(): void {
    if (this.sideA.length > 0 || this.sideB.length > 0) {
      this.queue(async (generation) => this.pick({}, generation));
    }
  }

  // Without a place, only the sides as they are, and the progress
  private async pick(place: object, generation: number): Promise<void> {
    const answer = await this.host.document.read('editor_seam_pick', {
      ...place,
      sideA: this.sideA,
      sideB: this.sideB,
      onB: this.onB,
    });
    if (generation !== this.generation) {
      return;
    }
    this.sideA = recordsField(answer, 'sideA');
    this.sideB = recordsField(answer, 'sideB');
    const lines = isRecord(answer.lines) ? answer.lines : {};
    this.host.showSeamSides(linesField(lines, 'sideA'), linesField(lines, 'sideB'));
    this.host.showMessage(stringField(answer, 'message') ?? '');
  }

  private async make(generation: number): Promise<void> {
    const answer = await this.host.document.call('editor_seam_make', { sideA: this.sideA, sideB: this.sideB });
    if (generation !== this.generation) {
      return;
    }
    if (booleanField(answer, 'done') === true) {
      this.reset();
    }
    if (answer.select !== null) {
      this.host.select(idsField(answer, 'select'));
    }
    this.host.showMessage(stringField(answer, 'message') ?? '');
  }
}
