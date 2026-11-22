// The canvas's drawing tools, one object each, as Sloper.UI.CanvasTools: what
// a click or a move does and what the tool snaps to. The canvas keeps pan,
// zoom and the select tool's drags and boxes, and hands the rest to the tool
// in use. What a click makes is the engine's (Sloper.Editor.ToolEdits,
// through editor_tool_snap and editor_tool_click), so a click does the same
// as on the desktop; the tools here keep the first click of a two-click tool
// and show where the next would snap.
import type { PatternDocument } from '../document/patternDocument.ts';
import { EngineError } from '../engine/engine.ts';
import { booleanField, idField, idsField, isRecord, numberField, stringField } from '../engine/replies.ts';
import type { Vec2, ViewTransform } from '../editor/view.ts';
import { LatestOnly } from './latestOnly.ts';
import type { SnapKind, SnapMarker, SnapPreview } from './patternPainter.ts';

// Screen pixels around the pointer that a tool snaps to or picks from, as SNAP_RADIUS
export const SNAP_RADIUS = 8;

const SNAP_KINDS: readonly SnapKind[] = ['free', 'point', 'crossing', 'edge', 'horizontal', 'vertical'];

// What a tool needs of the canvas
export interface CanvasToolHost {
  readonly document: PatternDocument;
  readonly view: ViewTransform;
  // The role of the edges the drawing tools make
  readonly drawRole: string;
  select(ids: string[]): void;
  showSnap(snap: SnapMarker | undefined): void;
  showMessage(text: string): void;
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

  // Escape or a right click: true when the tool had something to drop
  cancel(): boolean {
    return false;
  }

  // The pointer left the canvas
  leave(): void {}

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

  constructor(host: CanvasToolHost, name: string) {
    super(host, name);
    this.snaps = new LatestOnly(
      async (at) => this.updateSnap(at),
      (error) => {
        this.report(error);
      },
    );
  }

  override move(at: Vec2): void {
    this.lastAt = at;
    this.snaps.push(at);
  }

  override leave(): void {
    this.snaps.clear();
    this.lastAt = undefined;
    this.host.showSnap(undefined);
  }

  override reset(): void {
    this.dropStart();
    this.leave();
  }

  override cancel(): boolean {
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
