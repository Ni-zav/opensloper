// Ruler ticks and grid spacing, with the cases and numbers Sloper.Tests.RulerTicks
// runs on Sloper.Editor.RulerTicks, so the copy stays the same as the original
import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  gridMajorCount,
  gridSpacing,
  MEASURE_UNITS,
  MILLIMETRES_PER_UNIT,
  MIN_GRID_SPACING,
  MIN_LABEL_SPACING,
  MIN_TICK_SPACING,
  rulerLabel,
  rulerSpacing,
  rulerTicks,
} from '../src/editor/rulerTicks.ts';
import { MAX_SCALE, MIN_SCALE, ViewTransform } from '../src/editor/view.ts';

const TOLERANCE = 1e-6;

function near(message: string, expected: number, actual: number): void {
  assert.ok(Math.abs(actual - expected) < TOLERANCE, `${message}: ${String(actual)}, expected ${String(expected)}`);
}

function view(scale: number, originX: number, originY: number): ViewTransform {
  const result = new ViewTransform();
  result.scale = scale;
  result.originX = originX;
  result.originY = originY;
  return result;
}

// Every zoom from the smallest to the largest, a tenth apart
function scales(): number[] {
  const result: number[] = [];
  for (let scale = MIN_SCALE; scale <= MAX_SCALE; scale *= 1.1) {
    result.push(scale);
  }
  return result;
}

void test('millimetre spacing at the default zoom', () => {
  // 2 px per mm: 5 mm is the first step 6 px apart, 50 mm the first 50 px apart
  const spacing = rulerSpacing(2, 'mm');
  near('minor', 5, spacing.minor);
  near('labelled', 50, spacing.labelled);
});

void test('inch spacing at the default zoom', () => {
  // 50.8 px per inch
  const spacing = rulerSpacing(2 * 25.4, 'in');
  near('minor', 1 / 8, spacing.minor);
  near('labelled', 1, spacing.labelled);
});

void test('centimetre spacing', () => {
  // 40 px per cm
  const spacing = rulerSpacing(40, 'cm');
  near('minor', 0.2, spacing.minor);
  near('labelled', 2, spacing.labelled);
});

void test('spacing is readable at every zoom', () => {
  for (const unit of MEASURE_UNITS) {
    for (const scale of scales()) {
      const pixelsPerUnit = scale * MILLIMETRES_PER_UNIT[unit];
      const spacing = rulerSpacing(pixelsPerUnit, unit);
      assert.ok(spacing.minor * pixelsPerUnit >= MIN_TICK_SPACING, `${unit} minor at ${String(scale)}`);
      assert.ok(spacing.labelled * pixelsPerUnit >= MIN_LABEL_SPACING, `${unit} labels at ${String(scale)}`);
    }
  }
});

void test('labelled is a whole number of minor', () => {
  for (const unit of MEASURE_UNITS) {
    for (const scale of scales()) {
      const spacing = rulerSpacing(scale * MILLIMETRES_PER_UNIT[unit], unit);
      const ratio = spacing.labelled / spacing.minor;
      near(`${unit} at ${String(scale)}`, Math.round(ratio), ratio);
    }
  }
});

void test('horizontal ticks match the view', () => {
  const transform = view(2, 40, 300);
  const ticks = rulerTicks(transform, false, 800, 'mm');
  assert.ok(ticks.length > 0, 'some ticks');
  for (const tick of ticks) {
    near(`at ${String(tick.value)} mm`, transform.toScreen({ x: tick.value, y: 0 }).x, tick.position);
  }
  // The origin is 40 px in, so the ruler starts at -20 mm, on a tick
  near('first at the left edge', -20, ticks[0]?.value ?? Number.NaN);
});

void test('vertical ticks count down the screen', () => {
  const transform = view(2, 40, 300);
  const ticks = rulerTicks(transform, true, 600, 'mm');
  assert.ok(ticks.length > 1, 'some ticks');
  for (const tick of ticks) {
    near(`at ${String(tick.value)} mm`, transform.toScreen({ x: 0, y: tick.value }).y, tick.position);
  }
  for (let index = 1; index < ticks.length; index++) {
    assert.ok(
      (ticks[index]?.position ?? 0) > (ticks[index - 1]?.position ?? 0),
      'larger values sit lower, as model y points down',
    );
  }
});

void test('ticks stay on the ruler', () => {
  for (const [vertical, unit] of [
    [false, 'cm'],
    [true, 'in'],
  ] as const) {
    for (const tick of rulerTicks(view(3.7, -123.4, 456.7), vertical, 500, unit)) {
      assert.ok(
        tick.position >= -TOLERANCE && tick.position <= 500 + TOLERANCE,
        `${String(tick.position)} on the ruler`,
      );
    }
  }
});

void test('tick kinds', () => {
  // 5 mm minor, 50 mm labelled, 25 mm middle
  for (const tick of rulerTicks(view(2, 0, 0), false, 400, 'mm')) {
    if (Math.abs(tick.value - 50 * Math.round(tick.value / 50)) < TOLERANCE) {
      assert.equal(tick.kind, 'labelled', `${String(tick.value)} labelled`);
    } else if (Math.abs(tick.value - 25 * Math.round(tick.value / 25)) < TOLERANCE) {
      assert.equal(tick.kind, 'middle', `${String(tick.value)} middle`);
    } else {
      assert.equal(tick.kind, 'minor', `${String(tick.value)} minor`);
    }
  }
});

void test('inch ticks at sixteenths', () => {
  // 3.9 px per mm is 99 px per inch: room for sixteenths, numbers every inch
  const ticks = rulerTicks(view(3.9, 0, 0), false, 100, 'in');
  near('step', 1 / 16, (ticks[1]?.value ?? 0) - (ticks[0]?.value ?? 0));
  assert.equal(ticks.length, 17, '0 to 1 inch');
  assert.equal(ticks[16]?.kind, 'labelled', 'inch labelled');
  assert.equal(ticks[8]?.kind, 'middle', 'half inch middle');
  assert.equal(ticks[4]?.kind, 'minor', 'quarter inch minor');
});

void test('an empty ruler has no ticks', () => {
  assert.equal(rulerTicks(view(2, 0, 0), false, 0, 'mm').length, 0);
});

void test('labels', () => {
  assert.equal(rulerLabel(0, 50), '0');
  assert.equal(rulerLabel(-1e-12, 50), '0', 'no minus zero');
  assert.equal(rulerLabel(-150, 50), '-150');
  assert.equal(rulerLabel(0.5, 0.5), '0.5');
  assert.equal(rulerLabel(1.25, 0.25), '1.25');
  assert.equal(rulerLabel(3, 1), '3', 'whole step, no decimals');
});

void test('the grid keeps its step', () => {
  // 5 mm at 4 px per mm is 20 px apart: as set, majors every ten
  const spacing = gridSpacing(4, 5, 'mm');
  near('minor', 5, spacing.minor);
  near('major', 50, spacing.labelled);
});

void test('the grid inch major is an inch', () => {
  const spacing = gridSpacing(200, 1 / 8, 'in');
  near('minor', 1 / 8, spacing.minor);
  near('major', 1, spacing.labelled);
  assert.equal(gridMajorCount(0.3, 'in'), 10, 'a step not dividing an inch');
  assert.equal(gridMajorCount(1, 'in'), 10, 'a whole inch');
  assert.equal(gridMajorCount(0.125, 'cm'), 10, 'metric');
});

void test('the grid zoomed out drops minor lines', () => {
  // 5 mm at 1 px per mm would be 5 px apart, so the 50 mm lines take over
  let spacing = gridSpacing(1, 5, 'mm');
  near('minor', 50, spacing.minor);
  near('major', 500, spacing.labelled);
  // An eighth of an inch at 20 px per inch doubles to a half, 10 px apart
  spacing = gridSpacing(20, 1 / 8, 'in');
  near('inch minor', 1 / 2, spacing.minor);
  near('inch major', 1, spacing.labelled);
  // Further out, whole inches and then tens
  spacing = gridSpacing(5, 1 / 8, 'in');
  near('inches', 10, spacing.minor);
  near('tens', 100, spacing.labelled);
});

void test('the grid is readable at every zoom', () => {
  for (const unit of MEASURE_UNITS) {
    for (const scale of scales()) {
      const pixelsPerUnit = scale * MILLIMETRES_PER_UNIT[unit];
      const spacing = gridSpacing(pixelsPerUnit, 0.1, unit);
      assert.ok(spacing.minor * pixelsPerUnit >= MIN_GRID_SPACING, `${unit} at ${String(scale)}`);
      const ratio = spacing.labelled / spacing.minor;
      assert.ok(Math.abs(ratio - Math.round(ratio)) < 1e-9, 'major is a multiple');
    }
  }
});
