// Drives the built design app's File System Access in headless Chromium. The
// pickers cannot be clicked through there, so they are stood in for by ones
// that hand back files and folders of the page's private file system
// (OPFS), whose handles open, write, resolve and are kept as a user's are:
// the test says what the next picker "chooses". It opens a pattern, finds
// its measurement file by granting the folder, saves both in place, opens
// the pattern again after a reload with the folder remembered, and saves it
// under another name.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { KeyInput, Page } from 'puppeteer-core';
import {
  bodyData,
  launchBrowser,
  serveApp,
  status,
  TIMEOUT_MS,
  waitForData,
  waitForStatus,
  watchProblems,
} from './browser.ts';

const PATTERNS = '../tests/patterns';
const PATTERN = 'patterns/skirt-pieces.sloper';
const MEASUREMENTS = 'patterns/skirt-small.slm';

// The pickers, over OPFS: each takes the next path the test has queued in
// window.testPicks ('' is the top folder)
function standInPickers(): void {
  const picks: (string | string[])[] = [];
  Reflect.set(window, 'testPicks', picks);
  const next = (): string[] => {
    const pick = picks.shift();
    if (pick === undefined) {
      throw new DOMException('no pick queued', 'AbortError');
    }
    return typeof pick === 'string' ? [pick] : pick;
  };
  // Inside, as the page is sent this function alone
  // oxlint-disable-next-line unicorn/consistent-function-scoping
  const folderAt = async (parts: string[], create: boolean): Promise<FileSystemDirectoryHandle> => {
    let folder = await navigator.storage.getDirectory();
    for (const part of parts) {
      // oxlint-disable-next-line no-await-in-loop
      folder = await folder.getDirectoryHandle(part, { create });
    }
    return folder;
  };
  const fileAt = async (path: string, create: boolean): Promise<FileSystemFileHandle> => {
    const parts = path.split('/');
    const name = parts.pop() ?? '';
    return (await folderAt(parts, create)).getFileHandle(name, { create });
  };
  Object.defineProperty(window, 'showOpenFilePicker', {
    value: async () => Promise.all(next().map(async (path) => fileAt(path, false))),
  });
  Object.defineProperty(window, 'showSaveFilePicker', {
    value: async () => fileAt(next()[0] ?? '', true),
  });
  Object.defineProperty(window, 'showDirectoryPicker', {
    value: async () =>
      folderAt(
        (next()[0] ?? '').split('/').filter((part) => part !== ''),
        false,
      ),
  });
}

async function queuePicks(page: Page, ...picks: (string | string[])[]): Promise<void> {
  await page.evaluate((queued) => {
    const list: unknown = Reflect.get(window, 'testPicks');
    if (Array.isArray(list)) {
      list.push(...queued);
    }
  }, picks);
}

async function writeOpfs(page: Page, path: string, text: string): Promise<void> {
  await page.evaluate(
    async (where, contents) => {
      const parts = where.split('/');
      const name = parts.pop() ?? '';
      let folder = await navigator.storage.getDirectory();
      for (const part of parts) {
        // oxlint-disable-next-line no-await-in-loop
        folder = await folder.getDirectoryHandle(part, { create: true });
      }
      const stream = await (await folder.getFileHandle(name, { create: true })).createWritable();
      await stream.write(contents);
      await stream.close();
    },
    path,
    text,
  );
}

async function readOpfs(page: Page, path: string): Promise<string> {
  return page.evaluate(async (where) => {
    const parts = where.split('/');
    const name = parts.pop() ?? '';
    let folder = await navigator.storage.getDirectory();
    for (const part of parts) {
      // oxlint-disable-next-line no-await-in-loop
      folder = await folder.getDirectoryHandle(part);
    }
    return (await (await folder.getFileHandle(name)).getFile()).text();
  }, path);
}

async function clickToolbar(page: Page, hint: string): Promise<void> {
  await page.click(`#toolbar button[title="${hint}"]`);
}

async function pressWithControl(page: Page, key: KeyInput, shift = false): Promise<void> {
  await page.keyboard.down('Control');
  if (shift) {
    await page.keyboard.down('Shift');
  }
  await page.keyboard.press(key);
  if (shift) {
    await page.keyboard.up('Shift');
  }
  await page.keyboard.up('Control');
}

const { port, close } = await serveApp();
const browser = await launchBrowser();
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1200, height: 800 });
  const problems = watchProblems(page);
  await page.evaluateOnNewDocument(standInPickers);
  const address = `http://127.0.0.1:${String(port)}/`;
  await page.goto(address);
  await waitForData(page, 'ready', 'true');
  const pattern = await readFile(join(PATTERNS, 'skirt-pieces.sloper'), 'utf8');
  await writeOpfs(page, PATTERN, pattern);
  await writeOpfs(page, MEASUREMENTS, await readFile(join(PATTERNS, 'skirt-small.slm'), 'utf8'));

  // Opened alone, its measurement file is not yet in a folder the page may read: the
  // button offered asks for the folder, which holds both
  await queuePicks(page, PATTERN);
  await clickToolbar(page, 'Open a pattern, with its measurement file if you have it');
  await waitForStatus(page, 'The pattern uses the measurement file skirt-small.slm');
  assert.equal(await page.title(), 'skirt-pieces.sloper — OpenSloper', 'the title');
  await queuePicks(page, '');
  await page.click('#status button');
  await waitForStatus(page, 'Measurements from skirt-small.slm');

  // A point added and saved in place with the shortcut
  const canvas = await page.$('#canvas');
  const box = await canvas?.boundingBox();
  assert.ok(box !== null && box !== undefined, 'the canvas has a place');
  await page.keyboard.press('p');
  await page.mouse.move(box.x + 30, box.y + 30);
  await page.mouse.click(box.x + 30, box.y + 30);
  await waitForData(page, 'undo', 'Add point');
  assert.equal(await bodyData(page, 'modified'), 'true', 'modified');
  await pressWithControl(page, 's');
  await waitForStatus(page, 'Saved skirt-pieces.sloper');
  assert.equal(await bodyData(page, 'modified'), 'false', 'saved');
  const savedPattern = await readOpfs(page, PATTERN);
  assert.notEqual(savedPattern, pattern, 'written back to its file');
  assert.ok(savedPattern.includes('"measurementFile": "skirt-small.slm"'), 'still naming its set');

  // A measurement edited and saved to the set's own file
  await page.click('.side-column [data-tab="measurements"]');
  await page.waitForFunction(() => document.querySelectorAll('.list-panel:not([hidden]) tbody tr').length > 0);
  await page.click('.list-panel:not([hidden]) tbody tr:first-child td:nth-child(2)');
  await page.keyboard.type('777.5');
  await page.keyboard.press('Enter');
  await page.waitForSelector('.list-panel:not([hidden]) tr.marked', { timeout: TIMEOUT_MS });
  await page.click('.list-panel:not([hidden]) .list-buttons button:nth-child(2)');
  let saved = '';
  for (let tries = 0; tries < 50 && !saved.includes('777.5'); tries++) {
    // oxlint-disable-next-line no-await-in-loop
    saved = await readOpfs(page, MEASUREMENTS);
    // oxlint-disable-next-line no-await-in-loop
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  assert.ok(saved.includes('777.5'), 'the set written in place');

  // After a reload the folder is remembered, so the set is found with the pattern
  await page.reload();
  await waitForData(page, 'ready', 'true');
  await queuePicks(page, PATTERN);
  await pressWithControl(page, 'o');
  await waitForStatus(page, 'Measurements from skirt-small.slm');

  // Save as puts it in another folder, which it then saves to
  await queuePicks(page, 'copies/copy.sloper');
  await clickToolbar(page, 'Save the pattern to another file');
  await waitForStatus(page, 'Saved copy.sloper');
  assert.equal(await page.title(), 'copy.sloper — OpenSloper', 'the new name');
  assert.ok((await readOpfs(page, 'copies/copy.sloper')).includes('"format"'), 'a pattern file');

  assert.deepEqual(problems, [], 'no errors on the page');
  console.log(
    'Files: opened a pattern and found its measurements by granting the folder; saved the pattern and the set in place; ' +
      `found the set again after a reload; saved under another name. ${await status(page)}`,
  );
} finally {
  await browser.close();
  close();
}
