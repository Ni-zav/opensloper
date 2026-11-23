// The paths between files that patterns record, as ui/fileAccess.ts works them out
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { relativePath, walkPath } from '../src/ui/fileAccess.ts';

void test('a file beside the pattern is named alone', () => {
  assert.equal(relativePath(['skirt', 'skirt.sloper'], ['skirt', 'me.slm']), 'me.slm');
});

void test('a file in another folder climbs out of the pattern’s', () => {
  assert.equal(relativePath(['patterns', 'skirt', 'skirt.sloper'], ['sets', 'me.slm']), '../../sets/me.slm');
  assert.equal(relativePath(['skirt.sloper'], ['sets', 'me.slm']), 'sets/me.slm');
});

void test('a recorded path is walked from the pattern’s folder', () => {
  assert.deepEqual(walkPath(['patterns', 'skirt'], '../../sets/me.slm'), ['sets', 'me.slm']);
  assert.deepEqual(walkPath(['skirt'], './me.slm'), ['skirt', 'me.slm']);
});

void test('a path that leaves the granted folder is not found there', () => {
  assert.equal(walkPath(['skirt'], '../../me.slm'), undefined);
});
