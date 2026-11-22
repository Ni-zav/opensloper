// Drives the built design app (out/design, from npm run build) in headless
// Chromium as a user would: opens a regression pattern with its measurements,
// checks the canvas drew it, adds a point with the Point tool, drags it with
// the Select tool and undoes. Serves the app itself on a free port. Node runs
// this TypeScript as it is; CHROMIUM names the browser, /usr/bin/chromium by default.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { extname, join, normalize } from 'node:path';
import { launch, type Page } from 'puppeteer-core';

const ROOT = 'out/design';
const PATTERNS = '../tests/patterns';
const TIMEOUT_MS = 30000;
// The canvas's paper colour, which an empty canvas is all of but the grid
const PAPER = [252, 251, 248];
// Pixels of the pattern's ink an opened skirt draws at the least
const MIN_INKED_PIXELS = 500;
const DRAG_PIXELS = 40;

const TYPES: Record<string, string> = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.wasm': 'application/wasm',
  '.svg': 'image/svg+xml',
};

const server = createServer((request, response) => {
  const path = normalize(join(ROOT, decodeURIComponent(new URL(request.url ?? '/', 'http://x').pathname)));
  const file = path.endsWith('/') || path === ROOT ? join(path, 'index.html') : path;
  readFile(file)
    .then((data) => {
      response.writeHead(200, { 'Content-Type': TYPES[extname(file)] ?? 'application/octet-stream' });
      response.end(data);
      return undefined;
    })
    .catch(() => {
      response.writeHead(404);
      response.end();
    });
});
await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
const address: string | AddressInfo | null = server.address();
if (address === null || typeof address === 'string') {
  throw new Error('the server has no port');
}
const { port } = address;

async function bodyData(page: Page, name: string): Promise<string> {
  return page.$eval('body', (body, key) => body.dataset[key] ?? '', name);
}

async function waitForData(page: Page, name: string, value: string): Promise<void> {
  await page.waitForFunction(
    (key, expected) => document.body.dataset[key] === expected,
    { timeout: TIMEOUT_MS },
    name,
    value,
  );
}

async function status(page: Page): Promise<string> {
  return page.$eval('#status', (element) => element.textContent);
}

// Pixels of the canvas that are neither paper nor the grid's light lines
async function inkedPixels(page: Page): Promise<number> {
  return page.$eval(
    '#canvas',
    (canvas, paper) => {
      if (!(canvas instanceof HTMLCanvasElement)) {
        return 0;
      }
      const data = canvas.getContext('2d')?.getImageData(0, 0, canvas.width, canvas.height).data ?? [];
      let count = 0;
      for (let index = 0; index < data.length; index += 4) {
        const red = data[index] ?? 0;
        const green = data[index + 1] ?? 0;
        const blue = data[index + 2] ?? 0;
        // The grid is within 40 of the paper; ink is darker or coloured
        if (
          Math.abs(red - (paper[0] ?? 0)) + Math.abs(green - (paper[1] ?? 0)) + Math.abs(blue - (paper[2] ?? 0)) >
          120
        ) {
          count++;
        }
      }
      return count;
    },
    PAPER,
  );
}

const browser = await launch({
  executablePath: process.env.CHROMIUM ?? '/usr/bin/chromium',
  args: ['--no-sandbox', '--disable-gpu'],
});
const problems: string[] = [];
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1200, height: 800 });
  page.on('pageerror', (error: unknown) => {
    problems.push(`page error: ${String(error)}`);
  });
  page.on('console', (message) => {
    if (message.type() === 'error') {
      problems.push(`console: ${message.text()}`);
    }
  });
  await page.goto(`http://127.0.0.1:${String(port)}/`);
  await waitForData(page, 'ready', 'true');

  const input = await page.$('input#open-input');
  assert.ok(input !== null, 'the open input');
  await input.uploadFile(join(PATTERNS, 'skirt-pieces.sloper'), join(PATTERNS, 'skirt-small.slm'));
  await page.waitForFunction(() => document.querySelector('#status')?.textContent.startsWith('Measurements from'), {
    timeout: TIMEOUT_MS,
  });
  assert.equal(await page.title(), 'skirt-pieces.sloper — OpenSloper', 'the title');
  // The scene comes after the change, and is drawn on the next frame
  await page.waitForFunction(() => new Promise((resolve) => requestAnimationFrame(() => resolve(true))));
  await new Promise((resolve) => setTimeout(resolve, 500));
  const inked = await inkedPixels(page);
  assert.ok(inked > MIN_INKED_PIXELS, `the pattern is drawn: ${String(inked)} pixels`);
  // Opening fitted all of it, measurements and all, so Fit changes nothing
  await page.click('#toolbar button:last-child');
  await new Promise((resolve) => setTimeout(resolve, 500));
  assert.equal(await inkedPixels(page), inked, 'opened fitted to the window');

  const canvas = await page.$('#canvas');
  const box = await canvas?.boundingBox();
  assert.ok(box !== null && box !== undefined, 'the canvas has a place');
  // Near the top left, clear of the fitted pattern
  const at = { x: box.x + 30, y: box.y + 30 };
  await page.keyboard.press('p');
  await page.mouse.move(at.x, at.y);
  await page.mouse.click(at.x, at.y);
  await waitForData(page, 'undo', 'Add point');
  assert.equal(await bodyData(page, 'modified'), 'true', 'modified');
  const added = await bodyData(page, 'selection');
  assert.ok(added !== '', 'the new point is selected');

  await page.keyboard.press('s');
  await page.mouse.move(at.x, at.y);
  await page.mouse.down();
  for (let step = 1; step <= 4; step++) {
    // oxlint-disable-next-line no-await-in-loop
    await page.mouse.move(at.x + (DRAG_PIXELS * step) / 4, at.y + (DRAG_PIXELS * step) / 4);
  }
  await page.mouse.up();
  await waitForData(page, 'undo', 'Move point');
  assert.equal(await bodyData(page, 'selection'), added, 'the dragged point stays selected');

  await page.keyboard.down('Control');
  await page.keyboard.press('z');
  await page.keyboard.up('Control');
  await waitForData(page, 'undo', 'Add point');

  assert.deepEqual(problems, [], 'no errors on the page');
  console.log(
    `Design app: opened, drew ${String(inked)} pixels, added, dragged and undid a point. ${await status(page)}`,
  );
} finally {
  await browser.close();
  server.close();
}
