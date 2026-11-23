// Drives the built design app (out/design, from npm run build) in headless
// Chromium as a user would: opens a regression pattern with its measurements,
// checks the canvas drew it, adds a point with the Point tool, drags it with
// the Select tool and undoes, then uses each drawing tool and drags a curve's
// handle and a note. Serves the app itself on a free port. Node runs
// this TypeScript as it is; CHROMIUM names the browser, /usr/bin/chromium by
// default, and SCREENSHOT, a file name without .png, keeps a picture of the end.
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
// How long the page is watched while idle, in ms
const IDLE_MS = 1000;

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

// Waits for a body data value; on a timeout, says what the page showed instead
async function waitForData(page: Page, name: string, value: string): Promise<void> {
  try {
    await page.waitForFunction(
      (key, expected) => document.body.dataset[key] === expected,
      { timeout: TIMEOUT_MS },
      name,
      value,
    );
  } catch (error: unknown) {
    const shown = await page.evaluate(() => ({
      data: Object.fromEntries(Object.entries(document.body.dataset)),
      status: document.querySelector('#status')?.textContent,
    }));
    throw new Error(`waiting for ${name} "${value}": ${JSON.stringify(shown)}`, { cause: error });
  }
}

// Chooses a tool by its button, whose hint is its caption and keys
async function chooseTool(page: Page, caption: string): Promise<void> {
  await page.click(`#tools button[title^="${caption} ("]`);
}

// Clicks the canvas at a place relative to its top left
async function clickAt(page: Page, origin: { x: number; y: number }, x: number, y: number): Promise<void> {
  await page.mouse.move(origin.x + x, origin.y + y);
  // The snap shown is the one clicked: let it catch up, as a user's hand does
  await new Promise((resolve) => setTimeout(resolve, 100));
  await page.mouse.click(origin.x + x, origin.y + y);
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
  // Counts the scenes asked of the engine, in body data, to check an idle page asks nothing
  await page.evaluateOnNewDocument(() => {
    // Kept to be called with each worker as this, through Reflect.apply
    // oxlint-disable-next-line typescript/unbound-method
    const original = Worker.prototype.postMessage;
    Object.defineProperty(Worker.prototype, 'postMessage', {
      value: function (this: Worker, ...args: unknown[]): unknown {
        if (JSON.stringify(args[0]).includes('editor_scene')) {
          document.body.dataset.sceneCalls = String(Number(document.body.dataset.sceneCalls ?? '0') + 1);
        }
        return Reflect.apply(original, this, args);
      },
    });
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
  await page.click('#toolbar button[title="Fit everything in the window"]');
  await new Promise((resolve) => setTimeout(resolve, 500));
  assert.equal(await inkedPixels(page), inked, 'opened fitted to the window');
  // Fitting after each scene once led to a new scene after each fit, forever
  const calls = async (): Promise<number> => Number(await bodyData(page, 'sceneCalls'));
  const callsBefore = await calls();
  await new Promise((resolve) => setTimeout(resolve, IDLE_MS));
  assert.equal((await calls()) - callsBefore, 0, 'an idle page asks the engine for nothing');

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

  // The drawing tools, in the empty space left of the pattern
  await chooseTool(page, 'Line');
  await clickAt(page, box, 60, 120);
  await clickAt(page, box, 200, 120);
  await waitForData(page, 'undo', 'Add line');
  await page.keyboard.press('Escape');

  // A curve, whose handles lie a third along it: selected, the first is dragged down
  await chooseTool(page, 'Curve');
  await clickAt(page, box, 60, 220);
  await clickAt(page, box, 210, 220);
  await waitForData(page, 'undo', 'Add curve');
  await page.keyboard.press('Escape');
  await chooseTool(page, 'Select');
  await clickAt(page, box, 135, 220);
  await page.waitForFunction(() => (document.body.dataset.selection ?? '').split(' ').length === 1);
  await new Promise((resolve) => setTimeout(resolve, 200));
  await page.mouse.move(box.x + 110, box.y + 220);
  await page.mouse.down();
  for (let step = 1; step <= 4; step++) {
    // oxlint-disable-next-line no-await-in-loop
    await page.mouse.move(box.x + 110, box.y + 220 + step * 10);
  }
  await page.mouse.up();
  await waitForData(page, 'undo', 'Move curve handle');

  await chooseTool(page, 'Rectangle');
  await clickAt(page, box, 60, 300);
  assert.match(await status(page), /opposite corner/, 'the rectangle asks for its other corner');
  await clickAt(page, box, 200, 450);
  await waitForData(page, 'undo', 'Add rectangle');
  assert.equal((await bodyData(page, 'selection')).split(' ').length, 4, 'its four edges selected');

  await chooseTool(page, 'Piece');
  await clickAt(page, box, 130, 375);
  await waitForData(page, 'undo', 'Add piece');
  await chooseTool(page, 'Notch');
  await clickAt(page, box, 130, 300);
  await waitForData(page, 'undo', 'Add notch');

  await chooseTool(page, 'Circle');
  await clickAt(page, box, 130, 560);
  await clickAt(page, box, 170, 560);
  await waitForData(page, 'undo', 'Add circle or arc');

  // A seam from the rectangle piece's top edge to its bottom one
  await chooseTool(page, 'Seam');
  await clickAt(page, box, 100, 300);
  assert.match(await status(page), /^Side A/, 'side A picked');
  await page.keyboard.press('Tab');
  await page.waitForFunction(() => document.querySelector('#status')?.textContent.startsWith('Side B'));
  await clickAt(page, box, 100, 450);
  await page.keyboard.press('Enter');
  await waitForData(page, 'undo', 'Add seam');

  // A note: the Text tool adds it and opens its text to type
  await chooseTool(page, 'Text');
  await clickAt(page, box, 60, 650);
  await waitForData(page, 'undo', 'Add note');
  await page.waitForSelector('textarea.note-editor', { timeout: TIMEOUT_MS });
  await page.keyboard.type('Cut 2 on fold');
  await page.keyboard.down('Control');
  await page.keyboard.press('Enter');
  await page.keyboard.up('Control');
  await waitForData(page, 'undo', 'Change note');
  assert.equal(await page.$('textarea.note-editor'), null, 'the text field closed');

  // A callout from the circle's centre, its text to the right
  await chooseTool(page, 'Callout');
  await clickAt(page, box, 130, 560);
  assert.match(await status(page), /text goes/, 'asks where its text goes');
  await clickAt(page, box, 240, 600);
  await waitForData(page, 'undo', 'Add callout');
  await page.waitForSelector('textarea.note-editor', { timeout: TIMEOUT_MS });
  await page.keyboard.press('Escape');

  // Dragging the note by its text
  await chooseTool(page, 'Select');
  await page.mouse.move(box.x + 64, box.y + 653);
  await page.mouse.down();
  for (let step = 1; step <= 4; step++) {
    // oxlint-disable-next-line no-await-in-loop
    await page.mouse.move(box.x + 64 + step * 10, box.y + 653 + step * 5);
  }
  await page.mouse.up();
  await waitForData(page, 'undo', 'Move note');

  // Every label drawn adds ink
  await page.select('#labels', 'none');
  await new Promise((resolve) => setTimeout(resolve, 300));
  const unlabelled = await inkedPixels(page);
  await page.select('#labels', 'all');
  await new Promise((resolve) => setTimeout(resolve, 300));
  assert.ok((await inkedPixels(page)) > unlabelled + MIN_INKED_PIXELS, 'labels drawn');

  // SCREENSHOT names a PNG file to keep what the canvas shows at the end
  if ((process.env.SCREENSHOT ?? '') !== '') {
    await page.mouse.move(box.x + box.width / 2, box.y + box.height - 20);
    await new Promise((resolve) => setTimeout(resolve, 300));
    await page.screenshot({ path: `${process.env.SCREENSHOT ?? ''}.png` });
  }
  assert.deepEqual(problems, [], 'no errors on the page');
  console.log(
    `Design app: opened, drew ${String(inked)} pixels; added, dragged and undid a point; drew a line, a curve, ` +
      `dragged its handle, a rectangle, a piece, a notch, a circle and a seam; wrote a note and a callout and moved the note; labelled everything. ` +
      (await status(page)),
  );
} finally {
  await browser.close();
  server.close();
}
