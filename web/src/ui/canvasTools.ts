// The canvas's drawing tools, one object each, as Sloper.UI.CanvasTools: what
// a click or a move does and what the tool snaps to. The canvas keeps pan,
// zoom and the select tool's drags and boxes, and hands the rest to the tool
// in use. So far the Point tool; the others follow its pattern.
import type { PatternDocument } from '../document/patternDocument.ts';
import { EngineError } from '../engine/engine.ts';
import { idField, numberField, stringField } from '../engine/replies.ts';
import type { Vec2, ViewTransform } from '../editor/view.ts';
import { LatestOnly } from './latestOnly.ts';
import type { SnapKind, SnapMarker } from './patternPainter.ts';

// Screen pixels around the pointer that a tool snaps to or picks from, as SNAP_RADIUS
export const SNAP_RADIUS = 8;

const SNAP_KINDS: readonly SnapKind[] = ['free', 'point', 'crossing', 'edge', 'horizontal', 'vertical'];

// What a tool needs of the canvas
export interface CanvasToolHost {
  readonly document: PatternDocument;
  readonly view: ViewTransform;
  select(ids: string[]): void;
  showSnap(snap: SnapMarker | undefined): void;
  showMessage(text: string): void;
  // A failure that is no refusal of the engine's, which the page reports
  fail(error: unknown): void;
}

export abstract class CanvasToolHandler {
  protected readonly host: CanvasToolHost;

  constructor(host: CanvasToolHost) {
    this.host = host;
  }

  // Back to the tool's first step, as when it is chosen again
  reset(): void {}

  // A left click at a screen place
  click(_at: Vec2): void {}

  // The pointer moved over the canvas, no button held
  move(_at: Vec2): void {}

  // Escape: true when the tool had something to drop
  cancel(): boolean {
    return false;
  }

  // The pointer left the canvas
  leave(): void {}

  // A refusal is told to the user; anything else is a failure
  protected report(error: unknown): void {
    if (error instanceof EngineError) {
      this.host.showMessage(error.message);
    } else {
      this.host.fail(error);
    }
  }
}

// Shows where a click would snap as the pointer moves, asking the engine for
// the newest place only
export abstract class SnapTool extends CanvasToolHandler {
  private readonly snaps: LatestOnly<Vec2>;

  constructor(host: CanvasToolHost) {
    super(host);
    this.snaps = new LatestOnly(
      async (at) => this.updateSnap(at),
      (error) => {
        this.report(error);
      },
    );
  }

  override move(at: Vec2): void {
    this.snaps.push(at);
  }

  override leave(): void {
    this.snaps.clear();
    this.host.showSnap(undefined);
  }

  override reset(): void {
    this.leave();
  }

  // The parameters a snap at a screen place is asked for with
  protected snapParams(at: Vec2): { x: number; y: number; radius: number } {
    const model = this.host.view.toModel(at);
    return { x: model.x, y: model.y, radius: this.host.view.pixelsToMM(SNAP_RADIUS) };
  }

  private async updateSnap(at: Vec2): Promise<void> {
    const answer = await this.host.document.read('editor_snap', this.snapParams(at));
    const kind = SNAP_KINDS.find((each) => each === stringField(answer, 'kind')) ?? 'free';
    this.host.showSnap({ kind, at: { x: numberField(answer, 'x') ?? 0, y: numberField(answer, 'y') ?? 0 } });
    this.host.showMessage(stringField(answer, 'description') ?? '');
  }
}

// A click adds the point it snaps to, or selects the point clicked
export class PointTool extends SnapTool {
  override click(at: Vec2): void {
    this.add(at).catch((error: unknown) => {
      this.report(error);
    });
  }

  private async add(at: Vec2): Promise<void> {
    const answer = await this.host.document.call('editor_add_point', this.snapParams(at));
    const id = idField(answer, 'id');
    if (id !== undefined) {
      this.host.select([id]);
    }
  }
}
