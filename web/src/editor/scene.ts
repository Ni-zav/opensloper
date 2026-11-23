// What editor_scene and editor_tables give, checked and typed: the pieces,
// edges and points to draw, and the tables the editor reads from the engine
// rather than copying (tools, edge roles).
import {
  stringsField,
  booleanField,
  idField,
  numberField,
  numbersField,
  recordsField,
  stringField,
  type JsonRecord,
} from '../engine/replies.ts';
import type { Rect2, Vec2 } from './view.ts';

export type EvalState = 'valid' | 'dirty' | 'error' | 'invalid' | 'blocked';

export interface SceneObject {
  id: string;
  name: string;
  state: EvalState;
  locked: boolean;
  dimmed: boolean;
}

export interface ScenePiece extends SceneObject {
  fillColor: string;
  fillStyle: string;
  // Model mm, x and y in turn
  cutLine: number[];
  // Segments, x1, y1, x2, y2 for each: the grainline, fold and marking
  // strokes, and the notches from where they are cut to their tips
  marks: number[];
  notches: number[];
  // Its label, where the label goes, and a chevron along each edge (x, y and
  // the angle it points, for each), shown while it is selected or hovered
  caption: string;
  middle: Vec2;
  chevrons: number[];
}

// Drawn while selected: each side's edges, a polyline each, and their chevrons
export interface SceneSeam extends SceneObject {
  sideA: number[][];
  sideB: number[][];
  chevronsA: number[];
  chevronsB: number[];
}

// A note as the canvas draws it: its text, fields filled in, line by line;
// its look; where its text and its frame (the white box, or just the text)
// are; and a callout's leader, as segments
export interface SceneNote extends SceneObject {
  print: boolean;
  lines: string[];
  // Points at true print size, and mm from one line to the next
  size: number;
  lineHeight: number;
  align: 'left' | 'centre' | 'right';
  boxed: boolean;
  font: string;
  bold: boolean;
  italic: boolean;
  box: Rect2;
  frame: Rect2;
  anchor: string;
  anchorAt: Vec2;
  leader: string;
  leaderStrokes: number[];
}

// The marker of a point or edge, as segments as a piece's marks are
export interface SceneMarker extends SceneObject {
  strokes: number[];
}

export interface SceneEdge extends SceneObject {
  role: string;
  // The transform this is a copy from, or ''
  copyOf: string;
  line: number[];
  // Moved aside by slot gaps along normal, when it lies on other edges
  slot: number;
  normal: Vec2;
}

export interface ScenePoint extends SceneObject {
  copyOf: string;
  x: number;
  y: number;
}

// A selected curve's handle, as editor_handles gives it: the end of a
// tangent line from its anchor on the curve, named by its length field
export interface CurveHandle {
  edge: string;
  field: string;
  anchor: Vec2;
  at: Vec2;
  // False when a formula or a lock sets it, which draws it hollow
  draggable: boolean;
}

// Which handle: its curve and its length field
export interface HandleRef {
  edge: string;
  field: string;
}

export function parseHandle(record: JsonRecord | undefined): HandleRef | undefined {
  const edge = idField(record, 'edge');
  const field = stringField(record, 'field');
  return edge === undefined || field === undefined ? undefined : { edge, field };
}

export function parseHandles(result: JsonRecord): CurveHandle[] {
  return recordsField(result, 'handles').flatMap((record): CurveHandle[] => {
    const ref = parseHandle(record);
    if (ref === undefined) {
      return [];
    }
    return [
      {
        ...ref,
        anchor: { x: numberField(record, 'anchorX') ?? 0, y: numberField(record, 'anchorY') ?? 0 },
        at: { x: numberField(record, 'x') ?? 0, y: numberField(record, 'y') ?? 0 },
        draggable: booleanField(record, 'draggable') ?? false,
      },
    ];
  });
}

export interface Scene {
  isolated: string;
  pieces: ScenePiece[];
  edges: SceneEdge[];
  markers: SceneMarker[];
  seams: SceneSeam[];
  notes: SceneNote[];
  points: ScenePoint[];
}

export interface ToolInfo {
  name: string;
  caption: string;
  hint: string;
  icon: string;
  keys: string;
}

export interface RoleInfo {
  name: string;
  caption: string;
  // '' for one drawn in ink
  color: string;
  // Dash and gap lengths in mm; empty for a solid line
  dashes: number[];
}

export interface Tables {
  tools: ToolInfo[];
  roles: Map<string, RoleInfo>;
  // Each command's keys, as undo gives Mod+Z
  shortcuts: Map<string, string>;
}

const STATES: readonly EvalState[] = ['valid', 'dirty', 'error', 'invalid', 'blocked'];

export function stateField(record: JsonRecord): EvalState {
  const value = stringField(record, 'state');
  return STATES.find((state) => state === value) ?? 'invalid';
}

function sceneObject(record: JsonRecord): SceneObject {
  return {
    id: idField(record, 'id') ?? '',
    name: stringField(record, 'name') ?? '',
    state: stateField(record),
    locked: booleanField(record, 'locked') ?? false,
    dimmed: booleanField(record, 'dimmed') ?? false,
  };
}

export const EMPTY_SCENE: Scene = {
  isolated: '',
  pieces: [],
  edges: [],
  markers: [],
  seams: [],
  notes: [],
  points: [],
};

const ALIGNS = ['left', 'centre', 'right'] as const;

// A rectangle given as [minX, minY, maxX, maxY]
function rectField(record: JsonRecord, name: string): Rect2 {
  const values = numbersField(record, name) ?? [];
  return { minX: values[0] ?? 0, minY: values[1] ?? 0, maxX: values[2] ?? 0, maxY: values[3] ?? 0 };
}

// A place given as [x, y]
function pointField(record: JsonRecord, name: string): Vec2 {
  const values = numbersField(record, name) ?? [];
  return { x: values[0] ?? 0, y: values[1] ?? 0 };
}

// A list of polylines, each a flat list x, y, x, y
export function linesField(record: JsonRecord, name: string): number[][] {
  const value = record[name];
  if (!Array.isArray(value)) {
    return [];
  }
  return value.filter(
    (line: unknown): line is number[] => Array.isArray(line) && line.every((item) => typeof item === 'number'),
  );
}

export function parseScene(result: JsonRecord): Scene {
  const pieces = recordsField(result, 'pieces').map((record): ScenePiece => {
    const piece = sceneObject(record);
    return Object.assign(piece, {
      fillColor: stringField(record, 'fillColor') ?? '',
      fillStyle: stringField(record, 'fillStyle') ?? '',
      cutLine: numbersField(record, 'cutLine') ?? [],
      marks: numbersField(record, 'marks') ?? [],
      notches: numbersField(record, 'notches') ?? [],
      caption: stringField(record, 'caption') ?? '',
      middle: pointField(record, 'middle'),
      chevrons: numbersField(record, 'chevrons') ?? [],
    });
  });
  const edges = recordsField(result, 'edges').map((record): SceneEdge => {
    const normal = numbersField(record, 'normal') ?? [0, 0];
    return Object.assign(sceneObject(record), {
      role: stringField(record, 'role') ?? 'construction',
      copyOf: idField(record, 'copyOf') ?? '',
      line: numbersField(record, 'line') ?? [],
      slot: numberField(record, 'slot') ?? 0,
      normal: { x: normal[0] ?? 0, y: normal[1] ?? 0 },
    });
  });
  const points = recordsField(result, 'points').map((record): ScenePoint =>
    Object.assign(sceneObject(record), {
      copyOf: idField(record, 'copyOf') ?? '',
      x: numberField(record, 'x') ?? 0,
      y: numberField(record, 'y') ?? 0,
    }),
  );
  const markers = recordsField(result, 'markers').map((record): SceneMarker =>
    Object.assign(sceneObject(record), { strokes: numbersField(record, 'strokes') ?? [] }),
  );
  const seams = recordsField(result, 'seams').map((record): SceneSeam =>
    Object.assign(sceneObject(record), {
      sideA: linesField(record, 'sideA'),
      sideB: linesField(record, 'sideB'),
      chevronsA: numbersField(record, 'chevronsA') ?? [],
      chevronsB: numbersField(record, 'chevronsB') ?? [],
    }),
  );
  const notes = recordsField(result, 'notes').map(parseNote);
  return { isolated: idField(result, 'isolated') ?? '', pieces, edges, markers, seams, notes, points };
}

// One of the scene's notes, as editor_note_preview gives one too
export function parseNote(record: JsonRecord): SceneNote {
  return Object.assign(sceneObject(record), {
    print: booleanField(record, 'print') ?? true,
    lines: stringsField(record, 'lines') ?? [],
    size: numberField(record, 'size') ?? 0,
    lineHeight: numberField(record, 'lineHeight') ?? 0,
    align: ALIGNS.find((align) => align === stringField(record, 'align')) ?? 'left',
    boxed: booleanField(record, 'boxed') ?? false,
    font: stringField(record, 'font') ?? '',
    bold: booleanField(record, 'bold') ?? false,
    italic: booleanField(record, 'italic') ?? false,
    box: rectField(record, 'box'),
    frame: rectField(record, 'frame'),
    anchor: stringField(record, 'anchor') ?? 'free',
    anchorAt: pointField(record, 'anchorAt'),
    leader: stringField(record, 'leader') ?? 'none',
    leaderStrokes: numbersField(record, 'leaderStrokes') ?? [],
  });
}

export function parseTables(result: JsonRecord): Tables {
  return {
    tools: recordsField(result, 'tools').map((record) => ({
      name: stringField(record, 'name') ?? '',
      caption: stringField(record, 'caption') ?? '',
      hint: stringField(record, 'hint') ?? '',
      icon: stringField(record, 'icon') ?? '',
      keys: stringField(record, 'keys') ?? '',
    })),
    roles: new Map(
      recordsField(result, 'roles').map((record) => {
        const name = stringField(record, 'name') ?? '';
        return [
          name,
          {
            name,
            caption: stringField(record, 'caption') ?? name,
            color: stringField(record, 'color') ?? '',
            dashes: numbersField(record, 'dashes') ?? [],
          },
        ];
      }),
    ),
    shortcuts: new Map(
      recordsField(result, 'shortcuts').map((record) => [
        stringField(record, 'command') ?? '',
        stringField(record, 'keys') ?? '',
      ]),
    ),
  };
}

// The extent of everything in the scene, or undefined when it is empty
export function sceneBounds(scene: Scene): Rect2 | undefined {
  let bounds: Rect2 | undefined;
  const add = (x: number, y: number): void => {
    bounds =
      bounds === undefined
        ? { minX: x, minY: y, maxX: x, maxY: y }
        : {
            minX: Math.min(bounds.minX, x),
            minY: Math.min(bounds.minY, y),
            maxX: Math.max(bounds.maxX, x),
            maxY: Math.max(bounds.maxY, y),
          };
  };
  const addLine = (line: number[]): void => {
    for (let index = 0; index + 1 < line.length; index += 2) {
      add(line[index] ?? 0, line[index + 1] ?? 0);
    }
  };
  for (const piece of scene.pieces) {
    addLine(piece.cutLine);
  }
  for (const edge of scene.edges) {
    addLine(edge.line);
  }
  for (const point of scene.points) {
    add(point.x, point.y);
  }
  return bounds;
}
