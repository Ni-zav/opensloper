// The view transform, with the cases and numbers Sloper.Tests.CanvasModel
// runs on Sloper.Editor.View, so the copy stays the same as the original
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { MAX_SCALE, MIN_SCALE, ViewTransform, ZOOM_STEP, type Rect2, type Vec2 } from '../src/editor/view.ts';

const TOLERANCE = 1e-6;

function near(message: string, expected: number, actual: number): void {
  assert.ok(Math.abs(actual - expected) < TOLERANCE, `${message}: ${String(actual)}, expected ${String(expected)}`);
}

function pointsNear(message: string, expected: Vec2, actual: Vec2): void {
  near(`${message} x`, expected.x, actual.x);
  near(`${message} y`, expected.y, actual.y);
}

function view(scale = 2, originX = 40, originY = 40): ViewTransform {
  const result = new ViewTransform();
  result.scale = scale;
  result.originX = originX;
  result.originY = originY;
  return result;
}

function rect(minX: number, minY: number, maxX: number, maxY: number): Rect2 {
  return { minX, minY, maxX, maxY };
}

void test('the default view is DefaultView', () => {
  pointsNear('origin', { x: 40, y: 40 }, new ViewTransform().toScreen({ x: 0, y: 0 }));
  near('scale', 2, new ViewTransform().scale);
});

void test('y points down', () => {
  const transform = view(2, 100, 300);
  pointsNear('origin', { x: 100, y: 300 }, transform.toScreen({ x: 0, y: 0 }));
  pointsNear('down in the model is down on screen', { x: 120, y: 320 }, transform.toScreen({ x: 10, y: 10 }));
  near('pixels to mm', 5, transform.pixelsToMM(10));
});

void test('round trip', () => {
  const transform = view();
  transform.zoomAt(3.7, { x: 123, y: 456 });
  transform.pan(-17, 9);
  const model = { x: -31.5, y: 77.25 };
  pointsNear('round trip', model, transform.toModel(transform.toScreen(model)));
});

void test('zoom keeps the anchor', () => {
  const transform = view();
  const before = transform.toModel({ x: 250, y: 180 });
  transform.zoomAt(ZOOM_STEP, { x: 250, y: 180 });
  near('scale', 2 * ZOOM_STEP, transform.scale);
  pointsNear('same model point under the cursor', before, transform.toModel({ x: 250, y: 180 }));
});

void test('zoom limits', () => {
  const transform = view();
  transform.zoomAt(1e9, { x: 0, y: 0 });
  near('max', MAX_SCALE, transform.scale);
  transform.zoomAt(1e-12, { x: 0, y: 0 });
  near('min', MIN_SCALE, transform.scale);
});

void test('fit', () => {
  const transform = view();
  transform.fit(rect(0, -600, 480, 12), 1000, 700, 50);
  near('height limits the scale', 600 / 612, transform.scale);
  pointsNear('centred', { x: 500, y: 350 }, transform.toScreen({ x: 240, y: -294 }));
});

void test('zoom to box', () => {
  const transform = view();
  // Model (0, 0) to (100, 25) at 2 px/mm and origin (40, 40)
  transform.zoomToBox({ x: 40, y: 40 }, { x: 240, y: 90 }, 1000, 500);
  near('width limits the scale', 10, transform.scale);
  pointsNear('centred', { x: 500, y: 250 }, transform.toScreen({ x: 50, y: 12.5 }));
});

void test('zoom to box, corners either way', () => {
  const transform = view();
  const other = view();
  transform.zoomToBox({ x: 40, y: 40 }, { x: 240, y: 90 }, 1000, 500);
  other.zoomToBox({ x: 240, y: 40 }, { x: 40, y: 90 }, 1000, 500);
  near('same scale', transform.scale, other.scale);
  pointsNear('same place', transform.toScreen({ x: 0, y: 0 }), other.toScreen({ x: 0, y: 0 }));
});

void test('reveal leaves what shows alone', () => {
  const transform = view(1, 0, 0);
  transform.reveal(rect(10, 10, 50, 50), 800, 400, 5);
  near('x', 0, transform.originX);
  near('y', 0, transform.originY);
});

void test('reveal centres without zooming', () => {
  const transform = view(2, 0, 400);
  transform.reveal(rect(1000, -500, 1100, -400), 800, 400, 5);
  near('zoom kept', 2, transform.scale);
  pointsNear('centred', { x: 400, y: 200 }, transform.toScreen({ x: 1050, y: -450 }));
});

void test('show pans when it fits', () => {
  const transform = view(2, 0, 400);
  transform.show(rect(1000, -500, 1100, -400), 800, 400, 5);
  near('zoom kept', 2, transform.scale);
  pointsNear('centred', { x: 400, y: 200 }, transform.toScreen({ x: 1050, y: -450 }));
});

void test('show zooms out when too big', () => {
  const transform = view(2);
  transform.show(rect(0, 0, 980, 600), 800, 400, 5);
  assert.ok(transform.scale < 2, 'zoomed out');
  assert.ok(transform.toScreen({ x: 0, y: 0 }).x >= 5 - TOLERANCE, 'left end shows');
  assert.ok(transform.toScreen({ x: 980, y: 600 }).x <= 795 + TOLERANCE, 'right end shows');
  assert.ok(transform.toScreen({ x: 980, y: 600 }).y <= 395 + TOLERANCE, 'bottom shows');
});
