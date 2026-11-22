// While a job runs, only the newest value pushed runs next
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { LatestOnly } from '../src/ui/latestOnly.ts';

function unexpected(error: unknown): void {
  assert.fail(String(error));
}

// A job that waits until let go, recording the values it ran for
function heldJob(): { ran: number[]; job: (value: number) => Promise<void>; release: () => void } {
  const ran: number[] = [];
  const waiting: (() => void)[] = [];
  return {
    ran,
    job: async (value) => {
      ran.push(value);
      await new Promise<void>((resolve) => {
        waiting.push(resolve);
      });
    },
    release: () => {
      for (const resolve of waiting.splice(0)) {
        resolve();
      }
    },
  };
}

async function settle(): Promise<void> {
  await new Promise((resolve) => setImmediate(resolve));
}

void test('values pushed while one runs: only the last runs', async () => {
  const held = heldJob();
  const latest = new LatestOnly(held.job, unexpected);
  latest.push(1);
  latest.push(2);
  latest.push(3);
  latest.push(4);
  await settle();
  assert.deepEqual(held.ran, [1]);
  held.release();
  await settle();
  assert.deepEqual(held.ran, [1, 4]);
  held.release();
  await latest.idle();
  assert.deepEqual(held.ran, [1, 4]);
});

void test('clear drops the value waiting', async () => {
  const held = heldJob();
  const latest = new LatestOnly(held.job, unexpected);
  latest.push(1);
  latest.push(2);
  latest.clear();
  held.release();
  await latest.idle();
  assert.deepEqual(held.ran, [1]);
});

void test('a failure is reported and the next value still runs', async () => {
  const errors: unknown[] = [];
  const ran: number[] = [];
  const latest = new LatestOnly(
    async (value: number) => {
      ran.push(value);
      if (value === 1) {
        throw new Error('refused');
      }
      await Promise.resolve();
    },
    (error) => errors.push(error),
  );
  latest.push(1);
  latest.push(2);
  await latest.idle();
  assert.deepEqual(ran, [1, 2]);
  assert.equal(errors.length, 1);
});
