// What editor_scene and editor_tables give, checked and typed: the pieces,
// edges and points to draw, and the tables the editor reads from the engine
// rather than copying (tools, edge roles).
import {
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

export interface Scene {
  isolated: string;
  pieces: ScenePiece[];
  edges: SceneEdge[];
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

function stateField(record: JsonRecord): EvalState {
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

export const EMPTY_SCENE: Scene = { isolated: '', pieces: [], edges: [], points: [] };

export function parseScene(result: JsonRecord): Scene {
  const pieces = recordsField(result, 'pieces').map((record): ScenePiece => {
    const piece = sceneObject(record);
    return Object.assign(piece, {
      fillColor: stringField(record, 'fillColor') ?? '',
      fillStyle: stringField(record, 'fillStyle') ?? '',
      cutLine: numbersField(record, 'cutLine') ?? [],
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
  return { isolated: idField(result, 'isolated') ?? '', pieces, edges, points };
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
          { name, color: stringField(record, 'color') ?? '', dashes: numbersField(record, 'dashes') ?? [] },
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
