// Keys as the engine's tables write them, parsed as Sloper.Core.Shortcuts' ParseShortcut does
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { parseShortcut } from '../src/ui/shortcuts.ts';

void test('a letter', () => {
  assert.deepEqual(parseShortcut('P'), { key: 'P', mod: false, ctrl: false, shift: false, alt: false });
});

void test('modifiers', () => {
  assert.deepEqual(parseShortcut('Mod+Shift+Z'), { key: 'Z', mod: true, ctrl: false, shift: true, alt: false });
  assert.deepEqual(parseShortcut('Ctrl+Tab'), { key: 'Tab', mod: false, ctrl: true, shift: false, alt: false });
});

void test('keys by name are as the browser names them', () => {
  assert.equal(parseShortcut('Mod+Plus')?.key, '+');
  assert.equal(parseShortcut('Escape')?.key, 'Escape');
  assert.equal(parseShortcut('Left')?.key, 'ArrowLeft');
});

void test('what is not one key press', () => {
  assert.equal(parseShortcut('Arrows'), undefined);
  assert.equal(parseShortcut('Mod'), undefined);
  assert.equal(parseShortcut('A+B'), undefined);
  assert.equal(parseShortcut(''), undefined);
});
