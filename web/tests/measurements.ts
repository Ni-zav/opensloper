// Drives the built Measurements app in headless Chromium: the page asks for a
// file until one is open; a set opens with its name, notes and a row a
// measurement; Show in shows the values in cm and inches; a size table has a
// column a size; and a file that is not a measurement file, or cannot be
// read, is refused with the set open kept. SCREENSHOT, as in design.ts, keeps
// the page at the end.
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Page } from 'puppeteer-core';
import { launchBrowser, serveApp, waitForData, waitForStatus, watchProblems } from './browser.ts';

const SET = '../docs/examples/skirt-block/skirt.slm';
const SIZE_TABLE = '../docs/examples/measurements/size-table.slm';
const PATTERN = '../docs/examples/skirt-block/skirt-darts.sloper';

// The table's captions, and its rows' cells
async function table(page: Page): Promise<{ head: string[]; rows: string[][] }> {
  return page.$eval('#table', (element) => ({
    head: [...element.querySelectorAll('th')].map((cell) => cell.textContent),
    rows: [...element.querySelectorAll('tbody tr')].map((row) =>
      [...row.querySelectorAll('td')].map((cell) => cell.textContent),
    ),
  }));
}

async function waitForRows(page: Page, count: number): Promise<void> {
  await page.waitForFunction((expected) => document.querySelectorAll('#table tbody tr').length === expected, {}, count);
}

async function showIn(page: Page, unit: string, waist: string): Promise<void> {
  await page.select('#show-in', unit);
  await page.waitForFunction(
    (text) => document.querySelector('#table tbody tr td:nth-child(2)')?.textContent === text,
    {},
    waist,
  );
}

const folder = await mkdtemp(join(tmpdir(), 'opensloper-measurements-'));
const app = await serveApp({ root: 'out/measurements' });
const browser = await launchBrowser();
try {
  const page = await browser.newPage();
  const problems = watchProblems(page);
  await page.goto(`http://127.0.0.1:${String(app.port)}/`);
  await waitForData(page, 'ready', 'true');
  assert.equal(await page.title(), 'OpenSloper Measurements');
  assert.equal(await page.$('#table input[type=search]'), null, 'no search box before a set is open');
  assert.match(await page.$eval('#table', (element) => element.textContent), /Open a measurement file/u);
  const input = await page.$('input#open-input');
  assert.ok(input);

  // A set without sizes: one Value column, in mm to start with
  await input.uploadFile(SET);
  await waitForStatus(page, 'Opened skirt.slm');
  await waitForRows(page, 4);
  assert.equal(await page.title(), 'skirt.slm — OpenSloper Measurements');
  assert.equal(await page.$eval('#set-name', (box) => (box instanceof HTMLInputElement ? box.value : '')), 'Tutorial');
  assert.ok(await page.$eval('#set-name', (box) => box instanceof HTMLInputElement && box.readOnly));
  assert.ok(
    await page.$eval('#table .list-header', (header) => header instanceof HTMLElement && header.offsetHeight === 0),
    'the table has no search box',
  );
  let shown = await table(page);
  assert.deepEqual(shown.head, ['Key', 'Value', 'Description']);
  assert.deepEqual(shown.rows[0], ['waist', '660', 'Waist circumference']);
  await showIn(page, 'cm', '66');
  await showIn(page, 'in', '25.9843');
  await showIn(page, 'mm', '660');

  // A size table: a column a size
  await input.uploadFile(SIZE_TABLE);
  await waitForStatus(page, 'Opened size-table.slm');
  await waitForRows(page, 11);
  shown = await table(page);
  assert.deepEqual(shown.head, ['Key', '8', '10', '12', '14', '16', 'Description']);
  assert.deepEqual(shown.rows[0], [
    'bust_circumference',
    '820',
    '870',
    '920',
    '970',
    '1020',
    'Around the fullest part of the bust',
  ]);
  assert.equal(
    await page.$eval('#set-name', (box) => (box instanceof HTMLInputElement ? box.value : '')),
    "Women's sizes 8 to 16",
  );

  // Refused: another kind of file, and one that cannot be read; the size table stays
  await input.uploadFile(PATTERN);
  await waitForStatus(page, 'skirt-darts.sloper is not a measurement file');
  const broken = join(folder, 'broken.slm');
  await writeFile(broken, '{"format": "measurements"');
  await input.uploadFile(broken);
  await waitForStatus(page, 'Could not open broken.slm');
  assert.equal(await page.title(), 'size-table.slm — OpenSloper Measurements');
  assert.equal((await table(page)).rows.length, 11);

  // SCREENSHOT names a PNG file to keep what the page shows at the end
  if ((process.env.SCREENSHOT ?? '') !== '') {
    await page.screenshot({ path: `${process.env.SCREENSHOT ?? ''}.png` });
  }
  assert.deepEqual(problems, []);
  console.log('Measurements app passed');
} finally {
  await browser.close();
  app.close();
  await rm(folder, { recursive: true, force: true });
}
