// Where labels go on the canvas so they cover neither each other nor what is
// drawn: a copy of Sloper.Core.LabelPlacement, run here rather than in the
// engine since it is pixel arithmetic done on every frame with the browser's
// text sizes; keep the two the same. Coordinates are screen pixels.
import type { Rect2, Vec2 } from './view.ts';

// One label: its size, and the top-left corners it may be put at, best first
export interface LabelRequest {
  width: number;
  height: number;
  places: Vec2[];
}

// How far along a line its name is tried, as fractions of its length, middle first
export const LABEL_ALONG_FRACTIONS = [0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8];

// Labels per grid cell side, so a cell holds a few labels
const CELL_LABELS = 4;
// Most cells along either side of the grid
const MAX_CELLS = 128;

export function rect2(minX: number, minY: number, maxX: number, maxY: number): Rect2 {
  return { minX, minY, maxX, maxY };
}

// The square of side 2 radius round centre
export function rectAround(centre: Vec2, radius: number): Rect2 {
  return rect2(centre.x - radius, centre.y - radius, centre.x + radius, centre.y + radius);
}

function overlapArea(first: Rect2, second: Rect2): number {
  const across = Math.min(first.maxX, second.maxX) - Math.max(first.minX, second.minX);
  const down = Math.min(first.maxY, second.maxY) - Math.max(first.minY, second.minY);
  return across <= 0 || down <= 0 ? 0 : across * down;
}

// How much of rect lies outside within
function outsideArea(rect: Rect2, within: Rect2): number {
  return (rect.maxX - rect.minX) * (rect.maxY - rect.minY) - overlapArea(rect, within);
}

function grown(extent: Rect2, rect: Rect2): Rect2 {
  return rect2(
    Math.min(extent.minX, rect.minX),
    Math.min(extent.minY, rect.minY),
    Math.max(extent.maxX, rect.maxX),
    Math.max(extent.maxY, rect.maxY),
  );
}

function clamp(value: number, low: number, high: number): number {
  return Math.min(Math.max(value, low), high);
}

// The places round a point, nearest first: above right of it (where a label
// goes when nothing is in the way), below right, above left, below left,
// above, below, right and left, gap from it, then the same again a line
// further out for each of rings more
export function placesAround(at: Vec2, width: number, height: number, gap: number, rings: number): Vec2[] {
  const result: Vec2[] = [];
  for (let ring = 0; ring <= rings; ring++) {
    const away = gap + ring * height;
    result.push(
      { x: at.x + away, y: at.y - away - height },
      { x: at.x + away, y: at.y + away },
      { x: at.x - away - width, y: at.y - away - height },
      { x: at.x - away - width, y: at.y + away },
      { x: at.x - width / 2, y: at.y - away - height },
      { x: at.x - width / 2, y: at.y + away },
      { x: at.x + away, y: at.y - height / 2 },
      { x: at.x - away - width, y: at.y - height / 2 },
    );
  }
  return result;
}

// For a line's name: round each of the line's places in turn, along best first, with no further rings
export function placesAlong(along: Vec2[], width: number, height: number, gap: number): Vec2[] {
  return along.flatMap((at) => placesAround(at, width, height, gap, 0));
}

// For a piece's name: topLeft, then a line further up or down, then half its
// width to either side, for rings lines each way
export function placesStacked(topLeft: Vec2, width: number, height: number, rings: number): Vec2[] {
  const result: Vec2[] = [topLeft];
  for (let ring = 1; ring <= rings; ring++) {
    result.push({ x: topLeft.x, y: topLeft.y - ring * height }, { x: topLeft.x, y: topLeft.y + ring * height });
  }
  for (let ring = 0; ring <= rings; ring++) {
    result.push(
      { x: topLeft.x - width / 2, y: topLeft.y + ring * height },
      { x: topLeft.x + width / 2, y: topLeft.y + ring * height },
    );
  }
  return result;
}

function distance(from: Vec2, to: Vec2): number {
  return Math.hypot(to.x - from.x, to.y - from.y);
}

function polylinePointAt(line: Vec2[], total: number, fraction: number): Vec2 {
  let remaining = total * fraction;
  for (let index = 1; index < line.length; index++) {
    const first = line[index - 1];
    const last = line[index];
    if (first === undefined || last === undefined) {
      break;
    }
    const step = distance(first, last);
    if (step > 0 && remaining <= step) {
      const share = remaining / step;
      return { x: first.x + (last.x - first.x) * share, y: first.y + (last.y - first.y) * share };
    }
    remaining -= step;
  }
  return line[line.length - 1] ?? { x: 0, y: 0 };
}

// The points a line's name is tried at: its middle, then out towards its
// ends, as fractions of its length
export function polylinePlaces(line: Vec2[]): Vec2[] {
  if (line.length === 0) {
    return [];
  }
  let total = 0;
  for (let index = 1; index < line.length; index++) {
    total += distance(line[index - 1] ?? { x: 0, y: 0 }, line[index] ?? { x: 0, y: 0 });
  }
  return LABEL_ALONG_FRACTIONS.map((fraction) => polylinePointAt(line, total, fraction));
}

// Rectangles by the grid cells they touch, so that a place is checked only
// against what is near it
class RectGrid {
  private readonly left: number;
  private readonly top: number;
  private readonly cellSize: number;
  private readonly columns: number;
  private readonly rows: number;
  private readonly cells: number[][];
  private readonly rects: Rect2[] = [];
  // The query each rectangle was last counted in, so one spanning several cells counts once
  private readonly seen: number[] = [];
  private query = 0;

  constructor(extent: Rect2, cellSize: number) {
    this.left = extent.minX;
    this.top = extent.minY;
    let size = Math.max(cellSize, Math.max(extent.maxX - extent.minX, extent.maxY - extent.minY) / MAX_CELLS);
    if (size <= 0) {
      size = 1;
    }
    this.cellSize = size;
    this.columns = Math.floor((extent.maxX - this.left) / size) + 1;
    this.rows = Math.floor((extent.maxY - this.top) / size) + 1;
    this.cells = Array.from({ length: this.columns * this.rows }, (): number[] => []);
  }

  add(rect: Rect2): void {
    const index = this.rects.length;
    this.rects.push(rect);
    this.seen.push(-1);
    this.forCells(rect, (cell) => {
      this.cells[cell]?.push(index);
    });
  }

  overlap(rect: Rect2): number {
    let result = 0;
    this.query++;
    this.forCells(rect, (cell) => {
      for (const index of this.cells[cell] ?? []) {
        if (this.seen[index] !== this.query) {
          this.seen[index] = this.query;
          result += overlapArea(rect, this.rects[index] ?? rect2(0, 0, 0, 0));
        }
      }
    });
    return result;
  }

  private forCells(rect: Rect2, visit: (cell: number) => void): void {
    const lastRow = this.rows - 1;
    const lastColumn = this.columns - 1;
    const firstRow = clamp(Math.floor((rect.minY - this.top) / this.cellSize), 0, lastRow);
    const endRow = clamp(Math.floor((rect.maxY - this.top) / this.cellSize), 0, lastRow);
    const firstColumn = clamp(Math.floor((rect.minX - this.left) / this.cellSize), 0, lastColumn);
    const endColumn = clamp(Math.floor((rect.maxX - this.left) / this.cellSize), 0, lastColumn);
    for (let row = firstRow; row <= endRow; row++) {
      for (let column = firstColumn; column <= endColumn; column++) {
        visit(row * this.columns + column);
      }
    }
  }
}

// Each request's chosen top-left corner, in their order: the first of its
// places that overlaps no obstacle, no label placed before it, and stays
// inside within when given; when none does, the one overlapping least.
// Earlier requests get the better places.
export function placeLabels(requests: LabelRequest[], obstacles: Rect2[], within?: Rect2): Vec2[] {
  if (requests.length === 0) {
    return [];
  }
  // The grid covers every place and obstacle, with cells a few labels high
  let extent: Rect2 | undefined;
  let totalHeight = 0;
  for (const request of requests) {
    totalHeight += request.height;
    for (const place of request.places) {
      const box = rect2(place.x, place.y, place.x + request.width, place.y + request.height);
      extent = extent === undefined ? box : grown(extent, box);
    }
  }
  for (const box of obstacles) {
    extent = extent === undefined ? box : grown(extent, box);
  }
  const grid = new RectGrid(extent ?? rect2(0, 0, 0, 0), (CELL_LABELS * totalHeight) / requests.length);
  for (const box of obstacles) {
    grid.add(box);
  }
  return requests.map((request) => {
    let result: Vec2 = { x: 0, y: 0 };
    let bestCost = Number.POSITIVE_INFINITY;
    let bestBox = rect2(0, 0, 0, 0);
    for (const place of request.places) {
      const box = rect2(place.x, place.y, place.x + request.width, place.y + request.height);
      let cost = grid.overlap(box);
      if (within !== undefined) {
        cost += outsideArea(box, within);
      }
      if (cost < bestCost) {
        bestCost = cost;
        bestBox = box;
        result = place;
        if (cost <= 0) {
          break;
        }
      }
    }
    if (request.places.length > 0) {
      grid.add(bestBox);
    }
    return result;
  });
}
