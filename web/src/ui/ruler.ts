// The rulers along the top and left of the canvas and the corner between
// them, which names the unit, as Sloper.UI.Ruler. Each ruler starts where the
// canvas does, so its pixels line up with the canvas's; the pointer shows as
// a line across it. Ticks come from editor/rulerTicks.ts.
import { rulerLabel, rulerSpacing, rulerTicks, MILLIMETRES_PER_UNIT, type MeasureUnit } from '../editor/rulerTicks.ts';
import { ViewTransform, type Vec2 } from '../editor/view.ts';

// Tick lengths as shares of the ruler's thickness
const LABELLED_SHARE = 0.9;
const MIDDLE_SHARE = 0.45;
const MINOR_SHARE = 0.25;
const MIN_MINOR_PIXELS = 2;
// Between a tick and its number, in pixels
const LABEL_GAP = 2;
const FONT = '11px system-ui, sans-serif';
const TICK_COLOUR = 'rgb(110, 108, 104)';
const TEXT_COLOUR = 'rgb(48, 48, 52)';
const CURSOR_COLOUR = 'rgb(214, 54, 40)';

export class CanvasRulers {
  private readonly host: HTMLElement;
  private readonly corner: HTMLElement;
  private readonly top: HTMLCanvasElement;
  private readonly left: HTMLCanvasElement;
  private readonly view = new ViewTransform();
  private unit: MeasureUnit = 'mm';
  private pointer: Vec2 | undefined;
  private frame = 0;

  // Adds the rulers and corner to host, which lays them out round the canvas
  constructor(host: HTMLElement) {
    this.host = host;
    this.corner = document.createElement('div');
    this.corner.className = 'ruler-corner';
    this.top = document.createElement('canvas');
    this.top.className = 'ruler ruler-top';
    this.left = document.createElement('canvas');
    this.left.className = 'ruler ruler-left';
    host.prepend(this.corner, this.top, this.left);
    this.corner.textContent = this.unit;
    const resizer = new ResizeObserver(() => {
      this.repaint();
    });
    resizer.observe(this.top);
    resizer.observe(this.left);
  }

  get shown(): boolean {
    return !this.host.classList.contains('no-rulers');
  }

  set shown(shown: boolean) {
    this.host.classList.toggle('no-rulers', !shown);
    this.repaint();
  }

  // The canvas's view, which moves the ticks, and the pattern's unit
  showView(view: ViewTransform, unit: MeasureUnit): void {
    if (
      view.scale === this.view.scale &&
      view.originX === this.view.originX &&
      view.originY === this.view.originY &&
      unit === this.unit
    ) {
      return;
    }
    this.view.scale = view.scale;
    this.view.originX = view.originX;
    this.view.originY = view.originY;
    if (unit !== this.unit) {
      this.unit = unit;
      this.corner.textContent = unit;
    }
    this.repaint();
  }

  // The pointer on the canvas, in model millimetres, or undefined once it leaves
  showPointer(pointer: Vec2 | undefined): void {
    if (pointer?.x === this.pointer?.x && pointer?.y === this.pointer?.y) {
      return;
    }
    this.pointer = pointer;
    this.repaint();
  }

  private repaint(): void {
    if (this.frame !== 0 || !this.shown) {
      return;
    }
    this.frame = requestAnimationFrame(() => {
      this.frame = 0;
      this.paint(this.top, false);
      this.paint(this.left, true);
    });
  }

  private paint(ruler: HTMLCanvasElement, vertical: boolean): void {
    const width = ruler.clientWidth;
    const height = ruler.clientHeight;
    const ratio = window.devicePixelRatio;
    ruler.width = Math.round(width * ratio);
    ruler.height = Math.round(height * ratio);
    const context = ruler.getContext('2d');
    if (context === null) {
      return;
    }
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    context.clearRect(0, 0, width, height);
    const thickness = vertical ? width : height;
    const length = vertical ? height : width;
    const labelled = rulerSpacing(this.view.scale * MILLIMETRES_PER_UNIT[this.unit], this.unit).labelled;
    context.font = FONT;
    context.textBaseline = 'top';
    context.lineWidth = 1;
    context.strokeStyle = TICK_COLOUR;
    context.fillStyle = TEXT_COLOUR;
    context.beginPath();
    for (const tick of rulerTicks(this.view, vertical, length, this.unit)) {
      // Half a pixel in, so a one pixel line is sharp
      const along = Math.round(tick.position) + 0.5;
      const tickLength =
        tick.kind === 'labelled'
          ? Math.round(thickness * LABELLED_SHARE)
          : tick.kind === 'middle'
            ? Math.round(thickness * MIDDLE_SHARE)
            : Math.max(Math.round(thickness * MINOR_SHARE), MIN_MINOR_PIXELS);
      // Ticks grow from the edge next to the canvas
      if (vertical) {
        context.moveTo(thickness - tickLength, along);
        context.lineTo(thickness, along);
      } else {
        context.moveTo(along, thickness - tickLength);
        context.lineTo(along, thickness);
      }
      if (tick.kind === 'labelled') {
        this.drawLabel(context, rulerLabel(tick.value, labelled), Math.round(tick.position), vertical);
      }
    }
    context.stroke();
    if (this.pointer !== undefined) {
      const at = this.view.toScreen(this.pointer);
      const along = Math.round(vertical ? at.y : at.x) + 0.5;
      context.strokeStyle = CURSOR_COLOUR;
      context.beginPath();
      if (vertical) {
        context.moveTo(0, along);
        context.lineTo(width, along);
      } else {
        context.moveTo(along, 0);
        context.lineTo(along, height);
      }
      context.stroke();
    }
  }

  // A number just past its tick: to the right on the top ruler; on the left
  // ruler turned to read upwards, below the tick, as values grow downwards
  private drawLabel(context: CanvasRenderingContext2D, label: string, position: number, vertical: boolean): void {
    if (!vertical) {
      context.fillText(label, position + LABEL_GAP, 0);
      return;
    }
    context.save();
    context.translate(0, position + LABEL_GAP + context.measureText(label).width);
    context.rotate(-Math.PI / 2);
    context.fillText(label, 0, 0);
    context.restore();
  }
}
