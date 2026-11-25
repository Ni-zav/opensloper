// Drives the built Publish app in headless Chromium: a pattern opened without
// its measurement file names the file it needs, then with it starts a layout
// whose pages the preview draws and whose pieces a click selects; a layout
// whose sources sit in other folders finds its files by name.
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Page } from 'puppeteer-core';
import { bodyData, launchBrowser, serveApp, status, waitForData, waitForStatus, watchProblems } from './browser.ts';

const PATTERN = '../docs/examples/skirt-block/skirt-darts.sloper';
const MEASUREMENTS = '../docs/examples/skirt-block/skirt.slm';

// A layout of the skirt as saved beside a folder of patterns, whose
// measurement file the pattern names beside itself
const LAYOUT = {
  format: 'layout',
  version: 1,
  units: 'mm',
  name: 'Skirt for cutting',
  nextId: 2,
  sources: [{ id: 1, pattern: 'patterns/skirt-darts.sloper' }],
};

// Waits for the preview to draw paper: white pages on the grey desk
async function waitForPaper(page: Page): Promise<void> {
  await page.waitForFunction(() => {
    const canvas = document.querySelector('#preview');
    if (!(canvas instanceof HTMLCanvasElement)) {
      return false;
    }
    const pixels = canvas.getContext('2d')?.getImageData(0, 0, canvas.width, canvas.height).data ?? [];
    let count = 0;
    for (let index = 0; index < pixels.length; index += 4) {
      if (pixels[index] === 255 && pixels[index + 1] === 255 && pixels[index + 2] === 255) {
        count += 1;
      }
    }
    return count > 1000;
  });
}

// Clicks across the preview until a piece is selected; its placement index
async function selectSomePiece(page: Page): Promise<string> {
  const box = await (await page.$('#preview'))?.boundingBox();
  assert.ok(box);
  const steps = 6;
  for (let row = 1; row < steps; row += 1) {
    for (let column = 1; column < steps; column += 1) {
      // One click at a time, each waiting for the engine's answer
      // oxlint-disable-next-line no-await-in-loop
      await page.mouse.click(box.x + (box.width * column) / steps, box.y + (box.height * row) / steps);
      // oxlint-disable-next-line no-await-in-loop
      const selected = await page
        .waitForFunction(() => Number(document.body.dataset.selected ?? '-1') >= 0, { timeout: 300 })
        .then(
          () => true,
          () => false,
        );
      if (selected) {
        return bodyData(page, 'selected');
      }
    }
  }
  throw new Error('no click selected a piece');
}

const folder = await mkdtemp(join(tmpdir(), 'opensloper-publish-'));
const app = await serveApp({ root: 'out/publish' });
const browser = await launchBrowser();
try {
  const layoutFile = join(folder, 'skirt.slayout');
  await writeFile(layoutFile, JSON.stringify(LAYOUT));
  const page = await browser.newPage();
  const problems = watchProblems(page);
  await page.goto(`http://127.0.0.1:${String(app.port)}/`);
  await waitForData(page, 'ready', 'true');
  const input = await page.$('input#open-input');
  assert.ok(input);

  await input.uploadFile(PATTERN);
  await waitForStatus(page, 'The layout needs skirt.slm');
  assert.match(await page.$eval('#problem-count', (count) => count.textContent), /stop printing/u);

  await input.uploadFile(PATTERN, MEASUREMENTS);
  await waitForStatus(page, 'Started a layout for skirt-darts.sloper');
  assert.equal(await page.title(), 'skirt-darts — OpenSloper Publish');
  assert.doesNotMatch(await status(page), /stop printing/u);
  await waitForPaper(page);
  const selected = await selectSomePiece(page);
  // A click on the desk's corner selects nothing
  const box = await (await page.$('#preview'))?.boundingBox();
  assert.ok(box);
  await page.mouse.click(box.x + 2, box.y + 2);
  await waitForData(page, 'selected', '-1');
  assert.notEqual(selected, '-1');
  // The view zooms without failing, and fits again
  await page.click('button[title="Zoom in on the middle"]');
  await page.click('button[title="Show every page"]');

  await input.uploadFile(layoutFile, PATTERN, MEASUREMENTS);
  await waitForStatus(page, 'Opened skirt.slayout');
  assert.equal(await page.title(), 'Skirt for cutting — OpenSloper Publish');
  // Every file was found; its pieces wait in the tray, so nothing would print
  assert.doesNotMatch(await status(page), /needs/u);
  assert.match(await page.$eval('#problem-count', (count) => count.textContent), /stop printing/u);

  await input.uploadFile(MEASUREMENTS);
  await waitForStatus(page, 'skirt.slm is not a layout');

  assert.deepEqual(problems, []);
  console.log('Publish app passed');
} finally {
  await browser.close();
  app.close();
  await rm(folder, { recursive: true, force: true });
}
