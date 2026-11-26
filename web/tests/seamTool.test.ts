import assert from 'node:assert/strict';
import { test } from 'node:test';
import { setImmediate } from 'node:timers/promises';
import { ViewTransform } from '../src/editor/view.ts';
import type { JsonRecord } from '../src/engine/replies.ts';
import { SeamTool, type CanvasToolHost } from '../src/ui/canvasTools.ts';

function seamTool() {
  let finishFirst: ((reply: JsonRecord) => void) | undefined;
  const first = new Promise<JsonRecord>((resolve) => {
    finishFirst = resolve;
  });
  const shown: number[][][] = [];
  let picks = 0;
  const host: CanvasToolHost = {
    document: {
      read: async () => {
        picks++;
        return picks === 1 ? first : { lines: { sideA: [[2, 2, 3, 3]] } };
      },
      call: async () => assert.fail('a cancelled seam must not be created'),
    },
    view: new ViewTransform(),
    drawRole: '',
    select: () => undefined,
    showSnap: () => undefined,
    showMessage: () => undefined,
    showToolObjects: () => undefined,
    showSeamSides: (sideA) => shown.push(sideA),
    noteAdded: () => undefined,
    pointAt: () => undefined,
    fail: (error) => assert.fail(String(error)),
  };
  assert.ok(finishFirst);
  return { tool: new SeamTool(host, 'seam'), finishFirst, shown };
}

void test('Escape discards a pending first seam pick', async () => {
  const { tool, finishFirst, shown } = seamTool();
  tool.click({ x: 40, y: 40 });
  await setImmediate();
  assert.equal(tool.cancel(), true);
  finishFirst({ lines: { sideA: [[0, 0, 1, 1]] } });
  await setImmediate();
  assert.deepEqual(shown, [[]]);
});

void test('a late reply after reset cannot replace a new seam pick', async () => {
  const { tool, finishFirst, shown } = seamTool();
  tool.click({ x: 40, y: 40 });
  await setImmediate();
  tool.reset();
  tool.click({ x: 50, y: 50 });
  await setImmediate();
  assert.deepEqual(shown, [[], [[2, 2, 3, 3]]]);
  finishFirst({ lines: { sideA: [[0, 0, 1, 1]] } });
  await setImmediate();
  assert.deepEqual(shown, [[], [[2, 2, 3, 3]]]);
});
