// The ticks and numbers along the canvas rulers, and how far apart the
// canvas grid's lines are: a copy of Sloper.Editor.RulerTicks, run here
// rather than in the engine since it is pixel arithmetic done on every frame;
// keep the two the same. Ticks are as close as stays readable at the zoom;
// inches divide in halves down to sixteenths, the metric units in 1, 2 and 5.
import type { ViewTransform } from './view.ts';

// As TMeasureUnit, by MEASURE_UNIT_NAMES
export type MeasureUnit = 'mm' | 'cm' | 'in';
export const MEASURE_UNITS: readonly MeasureUnit[] = ['mm', 'cm', 'in'];
export const MILLIMETRES_PER_UNIT: Readonly<Record<MeasureUnit, number>> = { mm: 1, cm: 10, in: 25.4 };

// The grid's step in each unit, as DEFAULT_GRID_STEPS in Sloper.Core.Settings
export const DEFAULT_GRID_STEPS: Readonly<Record<MeasureUnit, number>> = { mm: 5, cm: 0.5, in: 0.125 };

// Closest ticks and numbers may come, in pixels
export const MIN_TICK_SPACING = 6;
export const MIN_LABEL_SPACING = 50;
// Closest grid lines may come, in pixels
export const MIN_GRID_SPACING = 10;

export type RulerTickKind = 'minor' | 'middle' | 'labelled';

export interface RulerTick {
  // In the ruler's unit
  value: number;
  // Pixels along the ruler, as on the canvas
  position: number;
  kind: RulerTickKind;
}

// In the ruler's unit; labelled is a whole number of minor steps. For the
// grid, labelled is the major lines' spacing.
export interface RulerSpacing {
  minor: number;
  labelled: number;
}

// Steps beyond the last are its multiples by ten
// 1, 2 and 5 times a power of ten, from a hundredth up
const METRIC_STEPS = [1, 2, 5];
const METRIC_FIRST_POWER = -2;
const INCH_STEPS = [1 / 16, 1 / 8, 1 / 4, 1 / 2, 1, 2, 5, 10];
const TOLERANCE = 1e-9;
// Far beyond the smallest zoom, so the loops always end
const RULER_MAX_STEPS = 60;
const DEFAULT_MAJOR_COUNT = 10;
const GRID_MAX_LEVELS = 20;
const MAX_DECIMALS = 4;

// The index-th step of the unit's series, which runs on by tens
function stepAt(unit: MeasureUnit, index: number): number {
  if (unit === 'in') {
    const last = INCH_STEPS.length - 1;
    if (index <= last) {
      return INCH_STEPS[index] ?? 1;
    }
    const count = index - last + 2;
    return (INCH_STEPS[last - 2 + (count % 3)] ?? 1) * 10 ** Math.floor(count / 3);
  }
  return (
    (METRIC_STEPS[index % METRIC_STEPS.length] ?? 1) *
    10 ** (Math.floor(index / METRIC_STEPS.length) + METRIC_FIRST_POWER)
  );
}

function isWholeMultiple(value: number, step: number): boolean {
  return Math.abs(value / step - Math.round(value / step)) < TOLERANCE;
}

export function rulerSpacing(pixelsPerUnit: number, unit: MeasureUnit): RulerSpacing {
  let index = 0;
  while (index < RULER_MAX_STEPS && stepAt(unit, index) * pixelsPerUnit < MIN_TICK_SPACING) {
    index++;
  }
  const minor = stepAt(unit, index);
  while (
    index < RULER_MAX_STEPS &&
    (stepAt(unit, index) * pixelsPerUnit < MIN_LABEL_SPACING || !isWholeMultiple(stepAt(unit, index), minor))
  ) {
    index++;
  }
  return { minor, labelled: stepAt(unit, index) };
}

// How many grid steps make a major line: ten, or a whole inch when the step divides one
export function gridMajorCount(step: number, unit: MeasureUnit): number {
  if (unit !== 'in' || step <= 0 || step >= 1) {
    return DEFAULT_MAJOR_COUNT;
  }
  const perInch = 1 / step;
  return isWholeMultiple(perInch, 1) ? Math.round(perInch) : DEFAULT_MAJOR_COUNT;
}

// The canvas grid for a spacing of step in unit. Zoomed out until the lines
// would crowd, the minor lines go and the major ones take their place, so
// every line drawn is still a multiple of step; inch fractions double first,
// through quarters and halves.
export function gridSpacing(pixelsPerUnit: number, step: number, unit: MeasureUnit): RulerSpacing {
  let minor = step;
  let count = gridMajorCount(step, unit);
  let level = 0;
  while (level < GRID_MAX_LEVELS && minor * pixelsPerUnit < MIN_GRID_SPACING) {
    // An even fraction of an inch doubles towards the whole inch
    if (unit === 'in' && minor < 1 && isWholeMultiple(1 / minor, 2)) {
      minor *= 2;
    } else {
      minor *= count;
    }
    count = gridMajorCount(minor, unit);
    level++;
  }
  return { minor, labelled: minor * count };
}

// The ticks on a ruler length pixels long. A vertical ruler counts down the
// screen, as model y does.
export function rulerTicks(view: ViewTransform, vertical: boolean, length: number, unit: MeasureUnit): RulerTick[] {
  const pixelsPerUnit = view.scale * MILLIMETRES_PER_UNIT[unit];
  if (pixelsPerUnit <= 0 || length <= 0) {
    return [];
  }
  const spacing = rulerSpacing(pixelsPerUnit, unit);
  const perLabel = Math.round(spacing.labelled / spacing.minor);
  const origin = vertical ? view.originY : view.originX;
  // The values at the two ends of the ruler
  const low = -origin / pixelsPerUnit;
  const high = (length - origin) / pixelsPerUnit;
  // Counted in whole steps, so long rulers gather no rounding
  const first = Math.ceil(low / spacing.minor - TOLERANCE);
  const last = Math.floor(high / spacing.minor + TOLERANCE);
  const ticks: RulerTick[] = [];
  for (let index = first; index <= last; index++) {
    const value = index * spacing.minor;
    let kind: RulerTickKind = 'minor';
    if (index % perLabel === 0) {
      kind = 'labelled';
    } else if (perLabel % 2 === 0 && index % (perLabel / 2) === 0) {
      kind = 'middle';
    }
    ticks.push({ value, position: origin + value * pixelsPerUnit, kind });
  }
  return ticks;
}

// A labelled tick's number, with as many decimals as the spacing needs
export function rulerLabel(value: number, labelled: number): string {
  let decimals = 0;
  while (decimals < MAX_DECIMALS && !isWholeMultiple(labelled * 10 ** decimals, 1)) {
    decimals++;
  }
  let rounded = Math.round(value * 10 ** decimals) / 10 ** decimals;
  // No "-0" at the origin
  if (Math.abs(rounded) < TOLERANCE) {
    rounded = 0;
  }
  return rounded.toFixed(decimals);
}
