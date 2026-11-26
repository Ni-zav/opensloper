// Drives the built Publish app's File System Access in headless Chromium,
// with the pickers stood in for over the page's private file system, as
// files.ts does for the design app. A layout whose pattern sits in another
// folder opens, and its pattern and measurement file are found by granting
// the folder that holds them. The layout is changed and saved in place with
// the shortcut; a failed write leaves it changed. Save As writes another
// file, and a layout started for a pattern is saved beside it.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import type { Page } from 'puppeteer-core';
import {
  launchBrowser,
  pressWithMod,
  queuePicks,
  readOpfs,
  serveApp,
  standInPickers,
  waitForData,
  waitForStatus,
  watchProblems,
  writeOpfs,
} from './browser.ts';

const PATTERN = 'patterns/skirt-darts.sloper';
const MEASUREMENTS = 'patterns/skirt.slm';
const LAYOUT = 'cut/skirt.slayout';
const WRITE_FAILURE = 'Simulated layout write failure';
// A layout beside a folder of patterns, as the desktop saves one
const LAYOUT_TEXT = JSON.stringify({
  format: 'layout',
  version: 1,
  units: 'mm',
  name: 'Skirt for cutting',
  nextId: 2,
  sources: [{ id: 1, pattern: '../patterns/skirt-darts.sloper' }],
});

async function title(page: Page): Promise<string> {
  return page.title();
}

async function toolbarButton(page: Page, caption: string): Promise<void> {
  await page.waitForFunction(
    (text) => {
      const button = [...document.querySelectorAll('#toolbar button')].find(
        (each) => each.textContent === text && each instanceof HTMLButtonElement && !each.disabled,
      );
      if (button instanceof HTMLButtonElement) {
        button.click();
        return true;
      }
      return false;
    },
    {},
    caption,
  );
}

const app = await serveApp({ root: 'out/publish' });
const browser = await launchBrowser();
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1200, height: 800 });
  const problems = watchProblems(page);
  await page.evaluateOnNewDocument(standInPickers);
  await page.goto(`http://127.0.0.1:${String(app.port)}/`);
  await waitForData(page, 'ready', 'true');
  await writeOpfs(page, PATTERN, await readFile('../docs/examples/skirt-block/skirt-darts.sloper', 'utf8'));
  await writeOpfs(page, MEASUREMENTS, await readFile('../docs/examples/skirt-block/skirt.slm', 'utf8'));
  await writeOpfs(page, LAYOUT, LAYOUT_TEXT);

  // Opened alone, its pattern is in a folder the page may not read yet: the
  // button offered asks for the folder that holds both
  await queuePicks(page, LAYOUT);
  await toolbarButton(page, 'Open…');
  await waitForStatus(page, 'The layout needs ../patterns/skirt-darts.sloper: find them');
  await queuePicks(page, '');
  await page.click('#message button');
  // Found, with the measurement file the pattern names; its pieces wait in the tray
  await page.waitForFunction(() => document.querySelector('#message button') === null);
  await page.waitForFunction(() => !(document.querySelector('#message')?.textContent ?? '').includes('needs'));
  assert.equal(await title(page), 'Skirt for cutting — OpenSloper Publish');

  // Changed, then saved to its own file with the shortcut
  await page.evaluate(() => {
    [...document.querySelectorAll('.pieces button')]
      .find((each) => each.textContent === 'Place new pieces')
      ?.dispatchEvent(new MouseEvent('click'));
  });
  await page.waitForFunction(() => document.title.startsWith('•'));
  // A write that fails leaves the layout changed and the file as it was
  await page.evaluate((reason) => {
    const prototype = FileSystemFileHandle.prototype;
    // Called with the original file handle below
    // oxlint-disable-next-line typescript/unbound-method
    const createWritable = prototype.createWritable;
    prototype.createWritable = async function (options) {
      if (this.name === 'skirt.slayout') {
        prototype.createWritable = createWritable;
        throw new DOMException(reason, 'QuotaExceededError');
      }
      return createWritable.call(this, options);
    };
  }, WRITE_FAILURE);
  await pressWithMod(page, 's');
  await waitForStatus(page, `Something went wrong: ${WRITE_FAILURE}`);
  assert.ok((await title(page)).startsWith('•'), 'still changed');
  assert.equal(await readOpfs(page, LAYOUT), LAYOUT_TEXT, 'the file left alone');
  await pressWithMod(page, 's');
  await waitForStatus(page, 'Saved skirt.slayout');
  assert.equal(await title(page), 'Skirt for cutting — OpenSloper Publish', 'saved');
  const saved = await readOpfs(page, LAYOUT);
  assert.match(saved, /"placements"/u, 'written back to its file');
  assert.match(saved, /"\.\.\/patterns\/skirt-darts\.sloper"/u, 'its pattern where it was');

  // Save As writes another file, which Save then writes
  await queuePicks(page, 'cut/skirt-copy.slayout');
  await toolbarButton(page, 'Save as…');
  await waitForStatus(page, 'Saved skirt-copy.slayout');
  assert.match(await readOpfs(page, 'cut/skirt-copy.slayout'), /"placements"/u);

  // A layout started for a pattern finds its measurement file in the folder
  // granted, and is saved beside it
  await queuePicks(page, PATTERN);
  await toolbarButton(page, 'Open…');
  await waitForStatus(page, 'Started a layout for skirt-darts.sloper');
  await page.waitForFunction(() => !(document.querySelector('#message')?.textContent ?? '').includes('needs'));
  await queuePicks(page, 'patterns/skirt-darts.slayout');
  await pressWithMod(page, 's');
  await waitForStatus(page, 'Saved skirt-darts.slayout');
  const started = await readOpfs(page, 'patterns/skirt-darts.slayout');
  assert.match(started, /"skirt-darts\.sloper"/u);
  assert.match(started, /"placements": \[\s*\{/u, 'every piece placed, as once its files were found');

  // The failed write was asked for
  assert.deepEqual(
    problems.filter((problem) => !problem.includes(WRITE_FAILURE)),
    [],
  );
  console.log('Publish files passed');
} finally {
  await browser.close();
  app.close();
}
