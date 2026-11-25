// Drives the built Publish app in headless Chromium: a pattern opened without
// its measurement file names the file it needs, then with it starts a layout
// whose pages the preview draws and whose pieces a click selects. The layout
// is packed, undone and redone, saved and exported, and the saved file opens
// again. A layout whose sources sit in other folders finds its files by name,
// and its waiting pieces are placed.
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
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

// Clicks the toolbar's button with this caption, once it is enabled
async function command(page: Page, caption: string): Promise<void> {
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

// A downloaded file's contents, once the browser has written it
async function download(folder: string, name: string): Promise<Buffer> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    // oxlint-disable-next-line no-await-in-loop
    const bytes = await readFile(join(folder, name)).catch(() => undefined);
    if (bytes !== undefined && bytes.length > 0) {
      return bytes;
    }
    // oxlint-disable-next-line no-await-in-loop
    await new Promise((resolve) => {
      setTimeout(resolve, 50);
    });
  }
  throw new Error(`${name} was not downloaded`);
}

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
const downloads = join(folder, 'downloads');
const app = await serveApp({ root: 'out/publish' });
const browser = await launchBrowser();
try {
  const layoutFile = join(folder, 'skirt.slayout');
  await writeFile(layoutFile, JSON.stringify(LAYOUT));
  const page = await browser.newPage();
  const problems = watchProblems(page);
  const session = await page.createCDPSession();
  await session.send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: downloads });
  await page.goto(`http://127.0.0.1:${String(app.port)}/`);
  await waitForData(page, 'ready', 'true');
  const input = await page.$('input#open-input');
  assert.ok(input);

  await input.uploadFile(PATTERN);
  await waitForStatus(page, 'The layout needs skirt.slm');
  assert.match(await page.$eval('#problem-count', (count) => count.textContent), /stop printing/u);

  await input.uploadFile(PATTERN, MEASUREMENTS);
  await waitForStatus(page, 'Started a layout for skirt-darts.sloper');
  assert.equal(await page.title(), '• skirt-darts — OpenSloper Publish', 'not saved yet');
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
  await command(page, 'Zoom In');
  await command(page, 'Fit Pages');

  // Pack, undone and redone, each one step
  await command(page, 'Pack pieces');
  await waitForStatus(page, 'Packed');
  await page.waitForSelector('#toolbar button[title="Undo Pack pieces"]:enabled');
  await command(page, 'Undo');
  await page.waitForSelector('#toolbar button[title="Take back the last change"]:disabled');
  await command(page, 'Redo');
  await page.waitForSelector('#toolbar button[title="Undo Pack pieces"]:enabled');

  // Saved as a download, counted saved; then exported
  await command(page, 'Save');
  await waitForStatus(page, 'Downloaded skirt-darts.slayout');
  const saved = (await download(downloads, 'skirt-darts.slayout')).toString();
  assert.match(saved, /"placements"/u);
  await page.waitForFunction(() => document.title === 'skirt-darts — OpenSloper Publish');
  await command(page, 'Export PDF');
  assert.equal((await download(downloads, 'skirt-darts.pdf')).subarray(0, 5).toString(), '%PDF-');
  await command(page, 'Export SVG');
  assert.match((await download(downloads, 'skirt-darts.svg')).toString(), /<svg/u);
  await command(page, 'Export DXF');
  assert.match((await download(downloads, 'skirt-darts.dxf')).toString(), /SECTION/u);

  // The saved layout opens again as it was
  await input.uploadFile(join(downloads, 'skirt-darts.slayout'), PATTERN, MEASUREMENTS);
  await waitForStatus(page, 'Opened skirt-darts.slayout');
  assert.equal(await page.title(), 'skirt-darts — OpenSloper Publish');

  await input.uploadFile(layoutFile, PATTERN, MEASUREMENTS);
  await waitForStatus(page, 'Opened skirt.slayout');
  assert.equal(await page.title(), 'Skirt for cutting — OpenSloper Publish');
  // Every file was found; its pieces wait in the tray, so nothing would print
  assert.doesNotMatch(await status(page), /needs/u);
  assert.match(await page.$eval('#problem-count', (count) => count.textContent), /stop printing/u);
  await command(page, 'Place new pieces');
  await waitForStatus(page, 'Placed');
  assert.doesNotMatch(await status(page), /stop printing/u);

  await input.uploadFile(MEASUREMENTS);
  await waitForStatus(page, 'skirt.slm is not a layout');

  assert.deepEqual(problems, []);
  console.log('Publish app passed');
} finally {
  await browser.close();
  app.close();
  await rm(folder, { recursive: true, force: true });
}
