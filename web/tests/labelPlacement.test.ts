// Label placement, with the cases and numbers Sloper.Tests.LabelPlacement runs
// on Sloper.Core.LabelPlacement, so the copy stays the same as the original
import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  LABEL_ALONG_FRACTIONS,
  placeLabels,
  placesAround,
  polylinePlaces,
  rect2,
  type LabelRequest,
} from '../src/editor/labelPlacement.ts';
import type { Rect2, Vec2 } from '../src/editor/view.ts';

const TOLERANCE = 1e-6;
const SLACK = 1e-9;

function near(message: string, expected: number, actual: number | undefined): void {
  assert.ok(
    actual !== undefined && Math.abs(actual - expected) < TOLERANCE,
    `${message}: ${String(actual)}, expected ${String(expected)}`,
  );
}

function request(at: Vec2, width: number, height: number): LabelRequest {
  return { width, height, places: placesAround(at, width, height, 2, 2) };
}

function overlaps(first: Rect2, second: Rect2): boolean {
  return (
    first.minX < second.maxX - SLACK &&
    second.minX < first.maxX - SLACK &&
    first.minY < second.maxY - SLACK &&
    second.minY < first.maxY - SLACK
  );
}

function box(topLeft: Vec2 | undefined, item: LabelRequest | undefined): Rect2 {
  assert.ok(topLeft !== undefined && item !== undefined);
  return rect2(topLeft.x, topLeft.y, topLeft.x + item.width, topLeft.y + item.height);
}

void test('a clear label keeps its place', () => {
  // Above right of the point, gap from it, as labels always went
  const places = placeLabels([request({ x: 10, y: 20 }, 30, 5)], []);
  near('x', 12, places[0]?.x);
  near('y', 13, places[0]?.y);
});

void test('a label moves off a note', () => {
  const item = request({ x: 10, y: 20 }, 30, 5);
  // A note over where the label would go
  const note = rect2(11, 10, 50, 18);
  const places = placeLabels([item], [note]);
  assert.ok(!overlaps(box(places[0], item), note), 'clear of the note');
  // Below right is the next best
  near('x', 12, places[0]?.x);
  near('y', 22, places[0]?.y);
});

void test('labels at one point do not overlap', () => {
  const items = [
    request({ x: 0, y: 0 }, 20, 5),
    request({ x: 0, y: 0 }, 20, 5),
    request({ x: 1, y: 0 }, 20, 5),
    request({ x: 0, y: 1 }, 20, 5),
  ];
  const places = placeLabels(items, []);
  for (let first = 0; first < items.length; first++) {
    for (let second = first + 1; second < items.length; second++) {
      assert.ok(
        !overlaps(box(places[first], items[first]), box(places[second], items[second])),
        `${String(first)} and ${String(second)}`,
      );
    }
  }
});

void test('a label stays within', () => {
  // A point at the right edge: its name goes to the left instead of off it
  const item = request({ x: 100, y: 50 }, 30, 5);
  const places = placeLabels([item], [], rect2(0, 0, 100, 100));
  assert.ok((places[0]?.x ?? Infinity) + item.width <= 100, 'inside');
  near('above left', 68, places[0]?.x);
  near('still above', 43, places[0]?.y);
});

void test('boxed in takes the least overlap', () => {
  const item: LabelRequest = {
    width: 10,
    height: 5,
    places: [
      { x: 0, y: 0 },
      { x: 100, y: 0 },
    ],
  };
  // The first place is wholly covered, the second only partly
  const places = placeLabels([item], [rect2(-5, -5, 20, 20), rect2(105, 0, 120, 20)]);
  near('the less covered', 100, places[0]?.x);
});

void test('earlier labels get the better place', () => {
  const items = [request({ x: 0, y: 0 }, 20, 5), request({ x: 0, y: 0 }, 20, 5)];
  const places = placeLabels(items, []);
  near('first keeps above right', items[0]?.places[0]?.y ?? NaN, places[0]?.y);
  near('second moves below', items[1]?.places[1]?.y ?? NaN, places[1]?.y);
});

void test("a line's name is tried at its middle first", () => {
  const along = polylinePlaces([
    { x: 0, y: 0 },
    { x: 50, y: 0 },
    { x: 100, y: 0 },
  ]);
  assert.equal(along.length, LABEL_ALONG_FRACTIONS.length, 'places');
  near('middle', 50, along[0]?.x);
  near('then towards the start', 40, along[1]?.x);
  near('and the end', 60, along[2]?.x);
  assert.equal(polylinePlaces([]).length, 0, 'an empty line has none');
});

void test('many labels all clear', () => {
  // A row of points close together, as along a waistline
  const count = 40;
  const items = Array.from({ length: count }, (_, index) => request({ x: index * 8, y: 0 }, 12, 5));
  const places = placeLabels(items, []);
  for (let index = 0; index < count; index++) {
    for (let other = index + 1; other < count; other++) {
      assert.ok(
        !overlaps(box(places[index], items[index]), box(places[other], items[other])),
        `${String(index)} and ${String(other)}`,
      );
    }
  }
});

void test('no labels', () => {
  assert.equal(placeLabels([], [rect2(0, 0, 1, 1)]).length, 0, 'nothing');
});
