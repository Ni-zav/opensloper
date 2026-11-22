// The canvas view: how model millimetres map to screen pixels, both y down,
// with zoom and pan. A copy of Sloper.Editor.View, run here rather than in
// the engine since it is pixel arithmetic done on every frame; keep the two
// the same.

export const MIN_SCALE = 0.02; // pixels per mm
export const MAX_SCALE = 200;
export const ZOOM_STEP = 1.25;

export interface Vec2 {
  x: number;
  y: number;
}

export interface Rect2 {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}

function clamp(value: number, low: number, high: number): number {
  return Math.min(Math.max(value, low), high);
}

export class ViewTransform {
  // Pixels per millimetre
  scale = 2;
  // Screen position of the model origin
  originX = 40;
  originY = 40;

  toScreen(model: Vec2): Vec2 {
    return { x: this.originX + model.x * this.scale, y: this.originY + model.y * this.scale };
  }

  toModel(screen: Vec2): Vec2 {
    return { x: (screen.x - this.originX) / this.scale, y: (screen.y - this.originY) / this.scale };
  }

  // Screen pixels as millimetres at this zoom
  pixelsToMM(pixels: number): number {
    return pixels / this.scale;
  }

  // Zooms by factor keeping the model point under anchor (screen) still
  zoomAt(factor: number, anchor: Vec2): void {
    const fixed = this.toModel(anchor);
    this.scale = clamp(this.scale * factor, MIN_SCALE, MAX_SCALE);
    this.originX = anchor.x - fixed.x * this.scale;
    this.originY = anchor.y - fixed.y * this.scale;
  }

  pan(dx: number, dy: number): void {
    this.originX += dx;
    this.originY += dy;
  }

  // Puts the model point centre in the middle of a width x height view
  centreOn(centre: Vec2, width: number, height: number): void {
    this.originX = width / 2 - centre.x * this.scale;
    this.originY = height / 2 - centre.y * this.scale;
  }

  // Shows bounds (model) centred in a width x height view, with margin pixels around it
  fit(bounds: Rect2, width: number, height: number, margin: number): void {
    const modelWidth = Math.max(bounds.maxX - bounds.minX, 1);
    const modelHeight = Math.max(bounds.maxY - bounds.minY, 1);
    this.scale = clamp(
      Math.min((width - 2 * margin) / modelWidth, (height - 2 * margin) / modelHeight),
      MIN_SCALE,
      MAX_SCALE,
    );
    this.centreOn({ x: (bounds.minX + bounds.maxX) / 2, y: (bounds.minY + bounds.maxY) / 2 }, width, height);
  }

  // Centres bounds (model) without zooming, unless all of it already shows,
  // margin pixels clear of the edges of a width x height view
  reveal(bounds: Rect2, width: number, height: number, margin: number): void {
    const corner = this.toScreen({ x: bounds.minX, y: bounds.minY });
    const otherCorner = this.toScreen({ x: bounds.maxX, y: bounds.maxY });
    if (
      corner.x >= margin &&
      corner.y >= margin &&
      otherCorner.x <= width - margin &&
      otherCorner.y <= height - margin
    ) {
      return;
    }
    this.pan(width / 2 - (corner.x + otherCorner.x) / 2, height / 2 - (corner.y + otherCorner.y) / 2);
  }

  // Reveals bounds when it fits at this zoom, else fits it: zooms out, never in
  show(bounds: Rect2, width: number, height: number, margin: number): void {
    if (
      (bounds.maxX - bounds.minX) * this.scale > width - 2 * margin ||
      (bounds.maxY - bounds.minY) * this.scale > height - 2 * margin
    ) {
      this.fit(bounds, width, height, margin);
    } else {
      this.reveal(bounds, width, height, margin);
    }
  }

  // Fills a width x height view with the box between two screen corners
  zoomToBox(corner: Vec2, otherCorner: Vec2, width: number, height: number): void {
    const first = this.toModel(corner);
    const last = this.toModel(otherCorner);
    this.fit(
      {
        minX: Math.min(first.x, last.x),
        maxX: Math.max(first.x, last.x),
        minY: Math.min(first.y, last.y),
        maxY: Math.max(first.y, last.y),
      },
      width,
      height,
      0,
    );
  }
}
